require "thread"

module Banter
  # Internal: A queue that is selectable with IO.select. Inspired by 
  # https://gist.github.com/garybernhardt/2963229. Popping off the queue should
  # be done by a single thread only.
  class SelectableQueue
    def initialize
      @queue        = Queue.new
      @read, @write = IO.pipe
      @push_mutex   = Mutex.new
      @pop_mutex    = Mutex.new
    end

    def push(object)
      @push_mutex.synchronize do
        @queue.push object
        @write << "."
      end

      return self
    end

    def pop(non_block = false)
      @pop_mutex.synchronize do
        object = @queue.pop non_block
        @read.read 1

        object
      end
    end

    def size
      @queue.size
    end

    def selected_for_reading
    end

    def selected_for_writing
    end

    def to_io
      @read
    end
  end
end
