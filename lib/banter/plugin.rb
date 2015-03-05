require "banter/command"
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

      
      if network.respond_to? :implementation
        implementation = network.implementation
      else
        implementation = IRC::RFC2812
      end

      extend implementation::Commands
      singleton_class.send(:include, implementation::Constants)
    end

    # Public: Gets the Banter::Network.
    def network
      @_network
    end

    # Public: Gets the IRC::Message.
    def message
      @_args.first
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

    # TODO: Should Banter::Plugin#command return the result of the block?

    # Public: Executes its block if a message matches a typical irc command of
    # the form `"!name argument argument"`. 
    #
    # The prefix is configurable. If the plugin setting `:plugin` is configured,
    # it will be used as the prefix. If it's not configured, the network setting
    # `:prefix` will be used. The network setting `:prefix` defaults to `"!"`.
    #
    # A help message is automatically generated from the description String and
    # the block arguments. The help messages is sent as a PRIVMSG when the 
    # command is invoked with `"--help"` or `"-h"` as its only argument.
    #
    # name        - The command name String.
    # description - The command description String.
    # block       - The command logic.
    #
    # Examples
    #
    #   command("slap", "Slaps a user") do |nickname, object = "trout"|
    #     response = "slaps #{nickname} around a bit with a large #{object}"
    #     privmsg message.target_channel, response
    #   end
    #
    #   <britishtea> !slap --help"
    #   <banter>     Slaps a user: !slap <nickname> [object]"
    #   <britishtea> !slap
    #   <banter>     Usage: !slap <nickname> [object]
    #   <britishtea> !slap banter
    #   <banter>     slaps banter around a bit with a large trout
    def command(name, description = "Usage", &block)
      return unless @_event == :receive

      # Get ready, we're doing magic! Blocks are Procs by default, meaning they
      # don't care about arguments at all. Give too few, give too much, a Proc
      # doesn't care a bit. But we do, Command really, really wants a lambda! 
      #
      # Fortunately, lambdas also care about arguments. Give too few, exception!
      # Give too much, exception! That's neat. Unfortunately, Procs can't really
      # be converted to lambdas. `lambda(&block)` is a no-op, it happily returns
      # one of those care-free Procs. That's not neat.
      #
      # So we're doing magic. If a Method is converted to a Proc, it becomes a
      # lambda. So, to preserve `self` (this instance), we're creating a method
      # on this plugin, "fake_proc", turn it into a Method object using
      # Object#method and then turn that into a Proc using Method#to_proc. It'll
      # return a lambda.
      define_singleton_method(:fake_proc, &block)

      prefix  = settings.fetch(:prefix, network[:prefix])
      lambda  = method(:fake_proc).to_proc
      command = Command.new(prefix, name, description, &lambda)
      result  = command.call(@_args.first)

      unless result.nil?
        throw(:__matched__, result)
      end
    rescue CommandArgumentError => exception
      privmsg @_args.first.params[0], exception.message

      throw(:__matched__)
    rescue UncaughtThrowError
    ensure
      # TODO: Remove our fake proc method.
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

    # Public: Replies to a PRIVMSG.
    def reply(response)
      if @_event == :receive && message.command == :privmsg
        privmsg message.params[0], response
      end
    end
  end
end
