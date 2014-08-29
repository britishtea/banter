require "banter/errors"
require "irc/rfc2812/commands"
require "irc/rfc2812/constants"

module Banter
  # Public: Represents a plugin.
  class Plugin
    include IRC::RFC2812::Commands
    include IRC::RFC2812::Constants

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
      self.network.settings[self.class]
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
    def event(event, &block)
      block.call(*@args) if @event == event
    end

    # Public: Executes the plugin. All exceptions except for Banter::Error are
    # caught and passed to the plugin with event `:exception`.
    def call
      instance_exec *@args, &@block
    rescue Banter::Error
      raise
    rescue => exception
      instance_exec :exception, self.network, exception, &@block
    end

    def run(plugin)
      plugin.call @event, self.network, *@args
    end

    # Public: Pushes messages onto the network queue. This method is also used
    # by the IRC::RFC2812::Commands mixin.
    #
    # message - A message String.
    def raw(message)
      self.network.queue.push message.to_s
    end
  end
end
