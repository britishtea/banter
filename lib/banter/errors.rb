module Banter
  Error = Module.new

  # Public: Mixed into any connection errors.
  ConnectionError = Module.new { include Error }

  # Public: Raised when attemping to register a plugin that does not respond to
  # #call.
  InvalidPlugin = Class.new(ArgumentError) { include Error }
  
  # Public: Raised when attempting to handle an event after 
  # Banter::Network#stopped_handling has been called.
  StoppedHandling = Class.new(RuntimeError) { include Error }
  
  # Public: Raised when attempting to register a plugin without setting the
  # required settings.
  MissingSettings = Class.new(KeyError) { include Error }
end
