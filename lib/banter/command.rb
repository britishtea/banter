require "banter/errors"

module Banter
  # Internal: Represents a command.
  class Command
    # Public: Initializes the command. 
    #
    # prefix      - A prefix String.
    # name        - A command name String.
    # description - A command description String (default: nil).
    # lambda      - A lambda, it can only take required or optional arguments.
    #
    # Raises ArgumentError if `lambda` isn't a lambda.
    def initialize(prefix, name, description = nil, &lambda)
      unless lambda.lambda?
        raise ArgumentError, "no lambda given"
      end

      @command     = prefix + name.downcase
      @description = description
      @block       = lambda
    end

    # Public: Returns the usage information. Required arguments are surrounded
    # by `<` and `>`, optional arguments by `[` and `]`.
    #
    # Examples
    #
    #   lambda  = lambda { |search_term, max_result = 1| ... }
    #   command = Command.new("!", "g", "Searches Google", &lambda)
    #   command.usage # => "!g <search_term> [max_results]"
    #
    # Returns a String.
    def usage
      parameters = @block.parameters.map do |type, name|
        case type
          when :req then "<#{name}>"
          when :opt then "[#{name}]"
        end
      end

      "#{@command} #{parameters.join(" ")}"
    end

    # Public: Returns a help message String.
    def help
      "#{@description}: #{usage}"
    end

    # Public: Executes the command if the given message matches.
    #
    # message - An object responding to #to_s.
    #
    # Returns nil.
    # Raises CommandArgumentError if the first argument is `"--help"` or not
    # enough arguments were given.
    def call(message)
      message = message.to_s.dup

      unless message.downcase.start_with?(@command)
        return nil
      end

      message.slice!(0, @command.size)

      args = message.strip.split(/\s+/, max_args)

      if help?(args)
        raise CommandArgumentError, help
      elsif insufficient_args?(args)
        raise CommandArgumentError, "Usage: #{usage}"
      else
        return @block.call(*args)
      end
    end

    private

    def help?(args)
      args.size == 1 && (args[0] == "--help" || args[0] == "-h")
    end

    def insufficient_args?(args)
      args.size < min_args
    end

    def min_args
      arity = @block.arity
      arity < 0 ? arity.abs.pred : arity
    end     

    def max_args
      @block.parameters.size { |type,_| type == :req || type == :opt }
    end
  end
end
