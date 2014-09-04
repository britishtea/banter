require "banter/errors"
require "banter/selectable_queue"
require "thread_safe"

module Banter
  # Internal: Utility class to simplify server queries.
  #
  # Examples
  # 
  #   query = Query.new
  #   query.replies [:kick]
  #   
  #   # From a different thread
  #   query.queue.push message # An IRC::Message.
  #   
  #   query.wait
  #   query.messages
  #   # => [#<IRC::Message: ...>]
  class Query
    attr_accessor :start, :replies, :end, :errors

    # Public: Initializes the query.
    #
    # start   - A Symbol or nil (default: nil).
    # ending  - A Sybol or nil (default: nil).
    # replies - An Array of Symbols or nil (default: nil).
    # errors  - An Array of Symbols or nil (default: nil).
    def initialize(start = nil, ending = nil, replies = nil, errors = nil)
      @start, @end, @replies, @errors = start, ending, replies, errors
      @messages  = ThreadSafe::Array.new
      @queue     = SelectableQueue.new
      @started   = false
      @run       = false
    end

    # Public: Sends a message to the query.
    #
    # message - An IRC::Message.
    def <<(message)
      @queue.push message
    end

    # Public: Waits until all replies are received. This is a blocking call.
    #
    # Raises Banter::ErrorReply if an error reply is received.
    def wait
      return if @run == true

      loop do
        queues, _ = IO.select [@queue]
        message   = queues.first.pop(true)

        case message.command
          when *self.replies then @messages << message if started?
          when self.start    then @started = true
          when self.end      then break
          when *self.errors  then raise error_reply(message)
        end

        break if self.end.nil?
      end
    ensure
      @run = true
    end

    # Public: Returns the received messages. If #wait raised an ErrorReply,
    # an empty ThreadSafe::Array will be returned.
    #
    # Returns a ThreadSafe::Array.
    def messages
      self.wait if @run == false
      
      return @messages
    end

  private

    def started?
      self.start.nil? || @started
    end

    def error_reply(message)
      exception_message = "#{message.command}, #{message}"
      exception         = ErrorReply.new exception_message, message.command

      return exception
    end
  end
end
