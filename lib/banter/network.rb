# require "irc/rfc2812/message"
require "socket"
require "thread_safe"
require "uri"

# TODO: Actually use irc-helpers.
module IRC
  module RFC2812
    Message = String
  end
end

module Banter
  # TODO: Implement SelectableQueue
  class SelectableQueue; end

  # Public: Represents a network.
  class Network
    StoppedHandling = Class.new(RuntimeError)

    # Public: Gets the URI. 
    attr_reader :uri

    # Public: Gets the settings ThreadSafe::Hash.
    attr_reader :settings

    # Public: Gets the Socket.
    attr_reader :socket

    # Public: Gets the SelectableQueue.
    attr_reader :queue

    # Public: Gets the buffer String.
    attr_reader :buffer

    # Public: Gets the ThreadSafe::Array of plugins.
    attr_reader :plugins

    # Public: Initializes the Network.
    #
    # uri   - A URI formatted String.
    # block - A block that receives the new Network instance (optional).
    def initialize(uri, settings = {}, &block)
      @mutex    = Hash.new { |hash, key| hash[key] = Mutex.new }
      @thgroup  = ThreadGroup.new

      @uri      = URI(uri)
      @settings = ThreadSafe::Hash.new settings
      @socket   = Socket.new :INET, :STREAM
      @queue    = SelectableQueue.new
      @buffer   = String.new
      @plugins  = ThreadSafe::Array.new

      @settings.default_proc = proc do |hash, key|
        hash[key] = ThreadSafe::Hash.new
        hash[key].default_proc = @settings.default_proc
        hash[key]
      end

      yield(self) if block_given?
    end

    # Public: Registers a plugin. Invokes #call on `plugin` with `:registered`
    # and `self` as arguments.
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
    # Returns false when registering was unsuccessfull.
    # Raises ArgumentError when `plugin` does not respond to #call.
    def register(plugin, settings = {})
      unless plugin.respond_to? :call
        raise ArgumentError, "#{plugin}#call not implemented"
      end

      begin
        plugin.call :register, self
      rescue
        return false
      end

      self.plugins << plugin
      self.settings[plugin] = ThreadSafe::Hash.new settings

      return plugin
    end

    # Public: Unregisters a plugin. Invokes #call on `plugin` with 
    # `:unregistered` and `self` as arguments.
    #
    # plugin - The plugin to unregister.
    #
    # Returns `plugin` if unregistering was successful.
    # Returns false if plugin was not registered.
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

    # Public: Calls all plugins concurrently and passes them a message.
    #
    # event   - An event name Symbol.
    # message - A message String (default: nil).
    #
    # Raises RunTimeError if #stop_handling! called after #wait has been called.
    def handle_message(message)
      if @thgroup.enclosed?
        raise StoppedHandling, "waiting for plugins to finish"
      end

      self.plugins.each do |plugin|
        @thgroup.add Thread.new { 
          plugin.call :receive, self, self.parse_message(message)
        }
      end
    end

    # Public: Waits for all running plugins to finish. Note that after calling
    # #handle_message will raise a StoppedHandling.
    def stop_handling!
      @thgroup.enclose
      @thgroup.list.each(&:join)
    end

    alias_method :to_io, :socket
  end
end
