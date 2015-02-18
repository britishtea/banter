require "banter/channel"
require "banter/connection"
require "banter/errors"
require "banter/user"
require "irc/rfc2812"
require "thread_safe"
require "uri"

module Banter
  # Public: Represents a network.
  class Network
    # Public: Gets the URI. 
    attr_reader :uri

    # Public: Gets the Banter::Connection.
    attr_reader :connection

    # Public: Gets the pipe (IO) for outgoing messages.
    attr_reader :queue

    # Public: Gets the ThreadSafe::Array of plugins.
    attr_reader :plugins

    # Public: Gets the implementation namespace (default: IRC::RFC2812).
    attr_accessor :implementation

    # Public: Initializes the Network.
    #
    # uri   - A URI formatted String.
    # block - A block that receives the new Network instance (optional).
    def initialize(uri, settings = {}, &block)
      # Public
      @uri                   = URI(uri)
      @settings              = ThreadSafe::Hash.new
      @settings.default_proc = proc { |hash, key| hash[key] = hash.dup.clear }
      @connection            = Connection.new
      @queue, @queue_write   = IO.pipe
      @plugins               = ThreadSafe::Array.new
      @implementation        = IRC::RFC2812

      # Internal
      @buffer = ""

      @settings.merge!(settings)

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

      @settings[plugin].merge!(settings)
      plugin.call :register, self
      self.plugins << plugin

      return plugin
    rescue MissingSettings
      @settings.delete(plugin)
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
      @settings.delete(plugin)

      return plugin
    end

    def [](key)
      @settings[key]
    end

    def []=(key, value)
      @settings[key] = value
    end

    # Public: Calls all plugins with `event` and `message`.
    #
    # event   - An event name Symbol.
    # message - A message String (default: nil).
    def handle_event(event, message = nil)
      self.plugins.each do |plugin|
        plugin.call(event, self, message) rescue nil
      end

      return self
    end

    # Public: Creates a Banter::Channel instance.
    #
    # Returns a Banter::Channel.
    def channel(name)
      Channel.new(name, self)
    end

    # Public: Creates a Banter::User instance.
    #
    # Returns a Banter::User.
    def user(prefix)
      User.new(prefix, self)
    end

    def connected?
      self.connection.connected?
    end

    # Plugins will receive a :connect event after the connection is made.
    def connect
      return true if self.connected?

      connected = self.connection.connect self.uri.host, self.uri.port
      
      if connected
        self.handle_event(:connect)
      end

      return connected
    end

    # Plugins will receive a :disconnect event before disconnecting.
    def disconnect
      self.handle_event(:disconnect)
      empty_buffers
      self.connection.disconnect
    end

    def reconnect
      if self.connected?
        self.disconnect
      else
        discard_buffers
      end

      self.connection.reset!
      self.connect
    end

    # Public: Sends a message to the server.
    #
    # message - An object implementing #to_s.
    #
    # Returns `self`.
    def <<(message)
      @queue_write.write(message)
    rescue IOError # queue is closed for writing
    ensure
      return self
    end

    # Public: Calls #handle_message for every received line (if connected).
    #
    # Raises the same exceptions as Banter::Connection#read.
    def selected_for_reading
      return unless self.connected?

      self.connection.read.each do |line|
        self.handle_event(:receive, parse_message(line))
      end
    end

    # Public: Calls #connect if unconnected, otherwise pops a message of the
    # queue and sends it to the IRC server.
    def selected_for_writing
      if self.connected?
        # There might be something left in the buffers of the Connection. An 
        # empty String is written to clear the Connection buffers.
        readable, _ = IO.select([@queue], nil, nil, 0)

        if readable.nil? || readable.empty?
          to_write = ""
        else
          to_write = @queue.readpartial(1024)
        end

        @buffer << self.connection.write(to_write)

        # Not the full message might have been written. To avoid the plugins
        # handling partial messages, the partial message is stored in a buffer
        # and handled by a next call when the full message has been written.
        if @buffer.include? "\n"
          to_handle = @buffer.slice! 0, @buffer.rindex("\n") + 1 
          
          to_handle.each_line do |line|
            self.handle_event(:send, parse_message(line))
          end
        end
      else
        self.connect
      end
    end

    def to_io
      self.connection.to_io
    end

  private

    # Writes the internal buffers @buffer and @queue to the socket and clears
    # them.
    def empty_buffers
      @queue_write.close
      @buffer << @queue.read
      @queue.close

      @buffer.each_line do |line|
        to_io.write(line)
        handle_event(:send, parse_message(line))
      end

      @buffer.clear

      @queue, @queue_write = IO.pipe
    end

    # Clears the internal buffers @buffer and @queue.
    def discard_buffers
      @queue_write.close
      @buffer.clear
      @queue.close

      @queue, @queue_write = IO.pipe
    end

    def parse_message(message)
      @implementation::Message.new(message)
    end
  end
end
