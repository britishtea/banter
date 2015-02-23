module Banter
  Error = Module.new

  # Public: Mixed into any connection errors.
  ConnectionError = Module.new { include Error }

  # Public: Raised when attemping to register a plugin that does not respond to
  # #call.
  InvalidPlugin = Class.new(ArgumentError) { include Error }
  
  # Public: Raised when attempting to register a plugin without setting the
  # required settings.
  MissingSettings = Class.new(KeyError) { include Error }

  # Public: Raised when a Banter::Command receives invalid arguments.
  CommandArgumentError = Class.new(ArgumentError) { include Error }

  # Public: Raised when an error reply is received to query.
  class ErrorReply < StandardError
    include Error

    attr_reader :code

    def initialize(message, code)
      super message
      @code = code
    end
  end
end
