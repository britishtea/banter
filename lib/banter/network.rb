require "banter/selectable_queue"
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

    # Public: Gets the ThreadSafe::Array of plugins.
    attr_reader :plugins

    # Public: Initializes the Network.
    #
    # uri   - A URI formatted String.
    # block - A block that receives the new Network instance (optional).
    def initialize(uri, settings = {}, &block)
      # Public
      @uri       = URI(uri)
      @settings  = ThreadSafe::Hash.new settings
      @socket    = create_socket
      @queue     = SelectableQueue.new
      @plugins   = ThreadSafe::Array.new
      @connected = false

      @settings.default_proc = proc do |hash, key|
        hash[key] = ThreadSafe::Hash.new
        hash[key].default_proc = @settings.default_proc
        hash[key]
      end

      # Internal
      @thgroup      = ThreadGroup.new
      @read_buffer  = String.new
      @write_buffer = String.new

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

      self.settings[plugin].merge! settings

      begin
        plugin.call :register, self
      rescue
        self.settings.delete plugin
        return false
      end

      self.plugins << plugin

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

    def connected?
      @connected
    end

    # Public: Connects the socket. Causes #connected to return true if 
    # connecting was successful.
    #
    # Note in case the connection is refused (Errno::ECONNREFUSED) a new socket
    # is created and an attempt to connect it is made.
    #
    # Returns true if connection was made, false otherwise.
    # Raises every exception Socket#connect_nonblock raises, except 
    # Errno::EISCONN and Errno::EINPROGRESS.
    def connect
      puts "      Connecting..." if $DEBUG

      remote_addr = Socket.pack_sockaddr_in self.uri.port, self.uri.host
      self.socket.connect_nonblock remote_addr
    rescue Errno::EISCONN
      puts "      Connected!" if $DEBUG

      self.plugins.each { |plugin| plugin.call :connect, self }

      return @connected = true
    rescue Errno::EINPROGRESS
      return false
    else
      return false
    end

    # Public: Closes the socket. Causes #connected to return false.
    def disconnect
      self.socket.close
    rescue IOError # Stream was already closed.
    ensure
      self.plugins.each { |plugin| plugin.call :disconnect, self }

      @connected = false
    end

    # Public: Reconnects the socket.
    def reconnect
      self.disconnect if self.connected?
      @socket = create_socket
      self.connect
    end

    # Public: Calls #handle_message for every received line (if connected).
    def selected_for_reading
      if self.connected?
        read.each { |line| self.handle_message line }
      end
    end

    # Public: Calls #connect if unconnected, otherwise pops a message of the
    # queue and sends it to the IRC server.
    def selected_for_writing
      if self.connected?
        to_write = self.queue.pop(true).to_s
          
        write to_write unless to_write.empty?
      else
        self.connect
      end
    rescue ThreadError # Queue was empty
    end

    alias_method :to_io, :socket

  private

    # Internal: Returns a new Socket of the right type.
    def create_socket
      Socket.new :INET, :STREAM, 0
    end

    # Public: Reads from the socket. Only reads full lines, if a partial message
    # is received it will be stored in a buffer.
    #
    # Note: In case of a faulty socket, a new socket is created and an attempt 
    # to connect it is made.
    #
    # Returns an Array.
    def read
      @read_buffer << self.socket.read_nonblock(4096)

      if @read_buffer.include? "\n" 
        full_lines = @read_buffer.slice!(0, @read_buffer.rindex("\n") + 2)
        full_lines.lines
      end
    rescue IO::WaitReadable
      return []
    end

    # Public: ...
    #
    # Note: In case of a faulty socket, a new socket is created and an attempt
    # to connect it is made.
    def write(message)
      @write_buffer << message

      bytes_written =  self.socket.write_nonblock @write_buffer 
      @write_buffer.slice! 0, bytes_written

      return true
    rescue IO::WaitWritable
      return false
    end
  end
end
