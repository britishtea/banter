require "banter/errors"
require "irc/rfc2812/commands"
require "irc/rfc2812/constants"

module Banter
  # Public: Represents a plugin.
  class Plugin
    include IRC::RFC2812::Commands
    include IRC::RFC2812::Constants

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
        thread = Thread.new { super }
        threadgroups[network].add(thread)

        if event == :register
          thread.join
        end

        return thread
      ensure
        if [:unregister, :disconnect].include?(event)
          threadgroups[network].list.each(&:join)
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

    # Public: Gets the Banter::Network.
    attr_reader :network

    # Public: Initializes the plugin.
    def initialize(event, network, *args, &block)
      @event, @network, @args, @block = event, network, args, block
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
      if @event == event
        throw(:__matched__, yield(*@args))
      end
    rescue UncaughtThrowError
    end

    # Public: Executes the plugin. All exceptions except Banter::Errors are
    # printed to the standard error stream (STDERR) before they are re-raised.
    def call
      catch(:__matched__) { instance_exec(*@args, &@block) }
    rescue Banter::Error
      raise
    rescue => exception
      warn "#{exception.class}: #{exception.message}"
      warn exception.backtrace.map { |line| "    #{line}" }

      raise
    end

    def run(plugin)
      plugin.call @event, self.network, *@args
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
