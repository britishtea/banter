require "socket"

module Banter
  class Connection
    # Public: Initializes the Connection.
    def initialize
      @read_buffer  = String.new
      @write_buffer = String.new
      @connected    = false

      reset!
    end

    def reset!
      @socket = create_socket
    end

    # Public: Connects the socket. Causes #connected? to return true if 
    # connecting was successful.
    #
    # host - A host String.
    # port - A port Integer.
    #
    # Returns true if connection was made, nil if the connecting is still in
    # progress, false otherwise.
    # Raises every exception Socket#connect_nonblock raises, except 
    # Errno::EISCONN and Errno::EINPROGRESS.
    def connect(host, port)
      warn "      Connecting..." if $DEBUG

      @socket.connect_nonblock Socket.pack_sockaddr_in(port, host)
    rescue Errno::EISCONN
      warn "      Connected!" if $DEBUG

      @connected = true
    rescue Errno::EINPROGRESS
      return nil
    rescue
      return @connection
    else
      return @connected
    end

    # Public: Disconnectes the socket. Causes #connected? to return false.
    def disconnect
      @socket.close
    rescue IOError # Stream was already closed.
    ensure
      warn "      Disconnected" if $DEBUG

      @connected = false
    end

    # Public: Checks if the socket is connected.
    def connected?
      @connected
    end

    # Public: Reads from the socket. Only reads full lines, if a partial message
    # is received it will be stored in a buffer.
    #
    # Returns an Array.
    # Raises every exception IO#read_nonblock raises, except Errno::EWOULDBLOCK
    # and Errno::EAGAIN (i.e. IO::WaitReadable).
    def read
      @read_buffer << @socket.read_nonblock(4096)

      if @read_buffer.include? "\n" 
        full_lines = @read_buffer.slice!(0, @read_buffer.rindex("\n") + 1)
        full_lines.lines
      end
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN
      return []
    rescue EOFError, Errno::EBADF
      @connected = false
      raise
    end

    # Public: Writes a String to the socket. If the message can't be written
    # fully, it is stored in a buffer and sent on the next call.
    #
    # message - A message String.
    #
    # Returns the part of `message` that was written if data was written, 
    # returns false if no data was written.
    # Raises every exception IO#write_nonblock raises, except Errno::EWOULDBLOCK
    # and Errno::EAGAIN (i.e. IO::WaitWriteable).
    def write(message)
      @write_buffer << message

      to_write      = @write_buffer.slice(0, @write_buffer.rindex("\n") + 2)
      bytes_written = @socket.write_nonblock to_write
      
      return @write_buffer.slice!(0, bytes_written)
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN
      return false
    rescue Errno::ECONNRESET
      @connected = false
      raise
    end

    def to_io
      @socket
    end

  private

    # Internal: Returns a new Socket of the right type. Currently only IPv4
    # sockets are supported.
    def create_socket
      Socket.new :INET, :STREAM, 0
    end
  end
end
