require "banter/errors"
require "irc/rfc2812/commands"
require "irc/rfc2812/constants"

module Banter
  # Public: Represents a plugin.
  class Plugin
    # Public: Makes a plugin concurrent. Use `extend` on a Banter::Plugin to
    # make it run concurrently. When the plugin is called with events 
    # `:unregister` or `:disconnect`, #call blocks until all running instances
    # have finished.
    module Concurrent
      def threadgroups
        @threadgroups ||= Hash.new do |hash, key|
          hash[key] = ThreadGroup.new
        end
      end

      # Public: Runs the plugin in a thread.
      #
      # Returns the spawned thread.
      def call(event, network, *args)
        if event == :register
          super
        else
          thread = Thread.new { super }
          threadgroups[network].add(thread)

          return thread
        end
      ensure
        if [:unregister, :disconnect].include?(event)
          thread.join
          threadgroups[network].list.each(&:join)
        end

        if event == :disconnect
          threadgroups.delete(network)
        end
      end
    end

    def self.name;  @name;  end
    def self.usage; @usage; end

    def self.define(name, usage = nil, &block)
      @name, @usage, @block = name, usage, block
    end

    # Public: Creates a new plugin and calls it.
    def self.call(event, network, *args)
      new(event, network, *args, &@block).call
    end

    # Public: Initializes the plugin.
    def initialize(event, network, *args, &block)
      @_event, @_network, @_args, @_block = event, network, args, block

      
      if network.respond_to? :protocol
        protocol = network.protocol
      else
        protocol = IRC::RFC2812
      end

      extend protocol::Commands
      singleton_class.send(:include, protocol::Constants)
    end

    # Public: Gets the Banter::Network.
    def network
      @_network
    end

    # Public: Gets the plugin settings ThreadSafe::Hash.
    def settings
      self.network[self.class]
    end

    # Public: Guarantees settings are present.
    #
    # keys - Key Symbols.
    #
    # Examples
    #
    #   required :api_key, :api_secret
    #
    # Raises Banter::MissingSettings if one or more settings are not present.
    def required(*keys)
      missing = keys.reject { |key| self.settings.key? key }
      
      unless missing.empty?
        raise MissingSettings, "The setting(s) #{missing.join ","} are not set "
                               "for #{self.class}"
      end

      return true
    end

    # Public: Sets default settings if settings are not present.
    #
    # defaults - A Hash.
    #
    # Examples
    #
    #   default :nickname => "banter", :username => "banter"
    def default(defaults)
      defaults.each do |key, value|
        self.settings[key] = value unless self.settings.key? key
      end
    end

    # Public: Runs `block` if `event` matches the event.
    #
    # event - An event Symbol.
    #
    # Examples
    #
    #   event :receive do |message|
    #     "..."
    #   end
    #
    # Throws :__matched__
    def event(event, &block)
      if @_event == event
        throw(:__matched__, yield(*@_args))
      end
    rescue UncaughtThrowError
    end

    # Public: Executes the plugin. All exceptions except Banter::Errors are
    # printed to the standard error stream (STDERR) before they are re-raised.
    def call
      catch(:__matched__) { instance_exec(*@_args, &@_block) }
    rescue Banter::Error
      raise
    rescue => exception
      warn "#{exception.class}: #{exception.message}"
      warn exception.backtrace.map { |line| "    #{line}" }

      raise
    end

    def run(plugin)
      plugin.call @_event, self.network, *@_args
    end

    # Public: Pushes messages onto the network queue. This method is also used
    # by the IRC::RFC2812::Commands mixin.
    #
    # message - An object implementing #to_s.
    def raw(message)
      self.network << message
    end
  end
end
