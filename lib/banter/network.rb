require "banter/connection"
require "banter/errors"
require "banter/selectable_queue"
require "irc/rfc2812/message"
require "thread_safe"
require "uri"

module Banter
  # Public: Represents a network.
  class Network
    # Public: Gets the URI. 
    attr_reader :uri

    # Public: Gets the settings ThreadSafe::Hash.
    attr_reader :settings

    # Public: Gets the Banter::Connection.
    attr_reader :connection

    # Public: Gets the Banter::SelectableQueue.
    attr_reader :queue

    # Public: Gets the ThreadSafe::Array of plugins.
    attr_reader :plugins

    # Public: Initializes the Network.
    #
    # uri   - A URI formatted String.
    # block - A block that receives the new Network instance (optional).
    def initialize(uri, settings = {}, &block)
      # Public
      @uri                   = URI(uri)
      @settings              = ThreadSafe::Hash.new settings
      @settings.default_proc = proc { |hash, key| hash[key] = hash.dup.clear }
      @connection            = Connection.new
      @queue                 = SelectableQueue.new
      @plugins               = ThreadSafe::Array.new

      # Internal
      @thgroup = ThreadGroup.new
      @buffer  = ""

      yield(self) if block_given?
    end

    # Public: Registers a plugin. Invokes #call on `plugin` with `:register` and
    # `self` as arguments.
    #
    # plugin   - An object that responds to #call.
    # settings - A settings Hash (default: {}).
    #
    # Examples
    #
    #   plugin = proc { |event, network, message| "..." }
    #   network.register plugin, :key => "value"
    #   # => #<Proc:...>
    #
    #   plugin = proc { raise StandardError}
    #   network.register plugin, :key => "value"
    #   # => false
    #
    # Returns `plugin` when registering was successfull.
    # Raises Banter::InvalidPlugin when `plugin` does not respond to #call.
    # Raises Banter::MissingSettings when plugin is missing required settings.
    def register(plugin, settings = {})
      unless plugin.respond_to? :call
        raise InvalidPlugin, "#{plugin}#call not implemented"
      end

      self.settings[plugin].merge! settings
      plugin.call :register, self
      self.plugins << plugin

      return plugin
    rescue MissingSettings
      self.settings.delete plugin
      raise
    end

    # Public: Unregisters a plugin. Invokes #call on `plugin` with `:unregister`
    # and `self` as arguments.
    #
    # plugin - The plugin to unregister.
    #
    # Returns `plugin` if unregistering was successful, false if plugin was not
    # registered.
    def unregister(plugin)
      return false unless self.plugins.include? plugin

      plugin.call :unregister, self
      
      self.plugins.delete plugin
      self.settings.delete(plugin)

      return plugin
    end

    # Public: Parses a message String. This method is used by #handle_message to
    # transform message Strings into useable objects it can hand to plugins. It
    # can safely be monkey-patched if another message format is required.
    #
    # message - A message String.
    #
    # Returns an IRC::RFC2812::Message.
    def parse_message(message)
      IRC::RFC2812::Message.new message
    end

    # Public: Calls all plugins with `event` and `message`.
    #
    # event   - An event name Symbol.
    # message - A message String (default: nil).
    #
    # Raises Banter::StoppedHandling if #stop_handling! has been called.
    def handle_event(event, message = nil)
      if @thgroup.enclosed?
        raise StoppedHandling, "waiting for plugins to finish"
      end

      self.plugins.each { |plugin| plugin.call event, self, message }
    end

    # Public: Calls all plugins concurrently with `event` and `message`. If an 
    # exception was raised in the plugin, it's called again with `:exception` 
    # and the exception.
    #
    # event   - An event name Symbol.
    # message - A message String (default: nil).
    #
    # Raises Banter::StoppedHandling if #stop_handling! has been called.
    def handle_event_concurrently(event, message = nil)
      if @thgroup.enclosed?
        raise StoppedHandling, "waiting for plugins to finish"
      end

      self.plugins.each do |plugin|
        @thgroup.add Thread.new { plugin.call event, self, message }
      end
    end

    # Public: Waits for all running plugins to finish. Note that after calling
    # #handle_message will raise a StoppedHandling.
    def stop_handling!
      @thgroup.enclose
      @thgroup.list.each(&:join)
    end

    def connected?
      self.connection.connected?
    end

    def connect
      return true if self.connected?

      connected = self.connection.connect self.uri.host, self.uri.port
      
      if connected
        self.handle_event(:connect)
      end

      return connected
    end

    def disconnect
      self.connection.disconnect
      self.handle_event(:disconnect)
    end

    def reconnect
      self.disconnect if self.connected?
      self.connection.reset!
      self.connect
    end

    # Public: Sends a message to the server.
    #
    # message - An object implementing #to_s.
    #
    # Returns `self`.
    def <<(message)
      @queue.push(message.to_s)

      return self
    end

    # Public: Calls #handle_message for every received line (if connected).
    #
    # Raises the same exceptions as Banter::Connection#read.
    def selected_for_reading
      return unless self.connected?

      self.connection.read.each do |line|
        self.handle_event_concurrently :receive, self.parse_message(line)
      end
    end

    # Public: Calls #connect if unconnected, otherwise pops a message of the
    # queue and sends it to the IRC server.
    def selected_for_writing
      if self.connected?
        # There might be something left in the buffers of the Connection. An 
        # empty String is written to clear the Connection buffers.
        if self.queue.size > 0
          to_write = self.queue.pop(true).to_s
        else
          to_write = ""
        end

        @buffer << self.connection.write(to_write)

        # Not the full message might have been written. To avoid the plugins
        # handling partial messages, the partial message is stored in a buffer
        # and handled by a next call when the full message has been written.
        if @buffer.include? "\n"
          to_handle = @buffer.slice! 0, @buffer.rindex("\n") + 2
          
          to_handle.each_line do |line|
            self.handle_event_concurrently :send, self.parse_message(line)
          end
        end
      else
        self.connect
      end
    rescue ThreadError # Queue was empty
    end

    def to_io
      self.connection.to_io
    end
  end
end
