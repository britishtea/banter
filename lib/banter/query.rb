require "banter/errors"
require "thread_safe"

module Banter
  # Internal: Utility class to simplify server queries.
  #
  # Examples
  # 
  #   query = Query.new :replies => [:kick], :errors => [:error], :end => [:end]
  #   
  #   # From a different thread
  #   query << message # An IRC::Message.
  #   
  #   query.messages
  #   # => [#<IRC::Message: ...>]
  class Query
    # Public: Initializes the query.
    #
    # hash - A Hash with keys :start, :end, :replies and :errors.
    def initialize(hash)
      @start,@end,@replies,@errors = hash.values_at :start,:end,:replies,:errors
      
      @messages  = ThreadSafe::Array.new
      @queue     = Queue.new
      @started   = false
      @run       = false
    end

    # Public: Returns the received messages. If #wait raised an ErrorReply,
    # an empty ThreadSafe::Array will be returned.
    #
    # Returns a ThreadSafe::Array.
    def messages
      wait             unless @run
      raise @exception unless @exception.nil?
      
      return @messages
    end

    def <<(message)
      @queue.push message

      return self
    end

    def call(event, network, message = nil)
      if event == :receive && message.respond_to?(:command)
        self << message
      end
    end
    
  private

    # Internal: Waits until all replies are received. This is a blocking call.
    #
    # Raises Banter::ErrorReply if an error reply is received.
    def wait
      loop do
        message = @queue.pop

        case message.command
          when *@replies then @messages << message if started?
          when @start    then @started = true
          when *@end     then break unless @messages.empty?
          when *@errors  then raise error_reply(message)
        end

        if @end.nil? && @messages.size > 0
          break 
        end
      end
    rescue ErrorReply => e
      @exception = e
      raise
    ensure
      @run = true
    end

    def started?
      @start.nil? || @started
    end

    def error_reply(message)
      exception_message = "#{message.command}, #{message}"
      exception         = ErrorReply.new exception_message, message.command

      return exception
    end
  end
end
