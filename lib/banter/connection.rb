require "banter/errors"
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
    # connecting was successful. If an exception is raised it is extended by
    # Banter::ConnectionError.
    #
    # host - A host String.
    # port - A port Integer.
    #
    # Returns true if connection was made, nil if the connecting is still in
    # progress, false otherwise.
    # Raises every exception Socket#connect_nonblock raises, except 
    # Errno::EISCONN and Errno::EINPROGRESS.
    def connect(host, port)
      @socket.connect_nonblock Socket.pack_sockaddr_in(port, host)
    rescue Errno::EISCONN
      @connected = true
    rescue Errno::EINPROGRESS
      return nil
    rescue => exception
      raise exception.extend(Banter::ConnectionError)
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
    # is received it will be stored in a buffer. If an exception is raised it is
    # extended by Banter::ConnectionError.
    #
    # Returns an Array.
    # Raises every exception IO#read_nonblock raises, except Errno::EWOULDBLOCK
    # and Errno::EAGAIN (i.e. IO::WaitReadable).
    def read
      @read_buffer << @socket.read_nonblock(4096)

      if @read_buffer.include? "\n" 
        full_lines = @read_buffer.slice!(0, @read_buffer.rindex("\n") + 1)
        full_lines.lines
      else
        return []
      end
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN # Nothing to read.
      return []
    rescue *READ_ERRORS => exception
      @connected = false

      raise exception.extend(Banter::ConnectionError)
    end

    # Public: Writes a String to the socket. If the message can't be written
    # fully, it is stored in a buffer and sent on the next call. If an exception
    # is raised it is extended by Banter::ConnectionError.
    #
    # message - A message String.
    #
    # Returns a String (the part of `message` that was written). The String is
    # empty if the data couldn't not be written (was blocked on writing).
    # Raises every exception IO#write_nonblock raises except Errno::EWOULDBLOCK,
    # Errno::EAGAIN and Errno::ENOBUFS (i.e. IO::WaitWriteable).
    def write(message)
      @write_buffer << message
      bytes_written = @socket.write_nonblock(@write_buffer)
      
      return @write_buffer.slice!(0, bytes_written)
    rescue Errno::EWOULDBLOCK, Errno::EAGAIN, Errno::ENOBUFS
      return ""
    rescue *WRITE_ERRORS => exception
      @connected = false
      
      raise exception.extend(Banter::ConnectionError)
    end

    def to_io
      @socket
    end

  private

    # Internal: Errors that indicate a flaky connection on reading.
    READ_ERRORS = [EOFError, Errno::EBADF, Errno::ECONNRESET, Errno::ENOTCONN, 
      Errno::ETIMEDOUT]

    # Internal: Errors that indicate a flaky connection on writing.
    WRITE_ERRORS = [Errno::EBADF, Errno::ECONNRESET, Errno::ENETDOWN,
      Errno::ENETUNREACH, Errno::EPIPE]

    # Internal: Returns a new Socket of the right type. Currently only IPv4
    # sockets are supported.
    def create_socket
      Socket.new :INET, :STREAM, 0
    end
  end
end
