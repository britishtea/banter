module Banter
  # Internal: An event loop.
  class EventLoop
    # Public: The timeout in seconds. This is the amount of time between recon-
    # nect attempts.
    TIMEOUT = 5

    # Public: Initializes the event loop. Note that the contents of `network`
    # may be changed from outside while the event loop is running.
    #
    # Note: Banter::Eventloop expects the objects in `network` to respond to
    # - #queue
    # - #connected?
    # - #connect
    # - #selected_for_reading
    # - #selected_for_writing
    #
    # networks - An Array of Banter::Networks.
    def initialize(networks)
      @networks = networks
      @skip     = Array.new
      @stop     = false
    end

    # Public: Returns a list of selectable objects that should be monitored for
    # reading.
    def for_reading
      connected = @networks.select &:connected?
      queues    = connected.map &:queue

      connected.concat(queues) - @skip
    end

    # Public: Returns a list of selectable objects that should be monitored for
    # writing.
    def for_writing
      with_filled_queue = @networks.select { |network| network.queue.size > 0 }
      unconnected       = @networks.reject &:connected?

      with_filled_queue.concat(unconnected).uniq - @skip
    end

    # Public: Starts the event loop. This is a blocking call.
    def start
      @networks.each { |network| network.connect }

      until @stop
        select_and_handle for_reading, for_writing
      end

      @stop = false
    end

    # Public: Stops the event loop.
    def stop
      @stop = true
    end

    # Public: Handles a readable IO object. If a connection error is detected
    # #reconnect is called on `io`.
    #
    # io - An IO object.
    def handle_readable(io)
      io.selected_for_reading
    rescue Banter::ConnectionError
      io.reconnect if io.respond_to? :reconnect
      @skip << io # causes a timeout of `TIMEOUT` seconds
    end

    # Public: Handles a writable IO object. If a connection error is detected
    # #reconnect is called on `io`.
    #
    # io - An IO object.
    def handle_writable(io)
      io.selected_for_writing
    rescue Banter::ConnectionError
      io.reconnect if io.respond_to? :reconnect
      @skip << io # causes a timeout of `TIMEOUT` seconds
    end

    # Public: Calls select and handles readable and writable sockets.
    #
    # reading - An Array of IO objects.
    # writing - An Array of IO objects.
    def select_and_handle(reading, writing)
      readable, writable = IO.select reading, writing, nil, TIMEOUT

      @skip.clear
      
      Array(readable).each { |io| handle_readable io }
      Array(writable).each { |io| handle_writable io }
    end
  end
end
