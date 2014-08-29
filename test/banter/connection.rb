require_relative "../test_helper"
require "banter/connection"

setup { Banter::Connection.new }

# Conversions

test "to_io" do |connection|
  assert connection.to_io.is_a? IO
end


test "connection status before connecting" do |connection|
  assert_equal connection.connected?, false
end

test "connecting" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EINPROGRESS
  end

  assert_equal connection.connect("0.0.0.0", 6667), nil

  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EISCONN
  end

  assert_equal connection.connect("0.0.0.0", 6667), true
end

test "connection status after connecting" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EINPROGRESS
  end

  connection.connect "0.0.0.0", 6667

  assert_equal connection.connected?, false

  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EISCONN
  end

  connection.connect "0.0.0.0", 6667

  assert_equal connection.connected?, true
end

test "connecting with errors" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise StandardError
  end

  assert_raise(StandardError) { connection.connect }
end

test "connection status after connecting with errors" do |connection|
   connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise StandardError
  end

  connection.connect "0.0.0.0", 6667 rescue nil

  assert_equal connection.connected?, false
end


test "disconnecting" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EISCONN
  end
  connection.to_io.define_singleton_method(:close) { |*| $test = true }

  connection.connect "0.0.0.0", 6667
  connection.disconnect

  assert_equal $test, true 
end

test "connection status after disconnecting" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EISCONN
  end
  connection.to_io.define_singleton_method(:close) { |*| }

  connection.connect "0.0.0.0", 6667
  connection.disconnect

  assert_equal connection.connected?, false
end

test "disconnecting with errors" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EISCONN
  end
  connection.to_io.define_singleton_method(:close) { |*| raise IOError }

  connection.connect "0.0.0.0", 6667
  connection.disconnect

  # TODO: What is the assertion here?
end

test "connection status after disconnecting with errors" do |connection|
  connection.to_io.define_singleton_method(:connect_nonblock) do |*|
    raise Errno::EISCONN
  end
  connection.to_io.define_singleton_method(:close) { |*| raise IOError }

  connection.connect "0.0.0.0", 6667
  connection.disconnect

  assert_equal connection.connected?, false
end


test "reading while readable" do |connection|
  connection.to_io.define_singleton_method(:read_nonblock) { |*| "hi\n" }

  assert_equal connection.read, ["hi\n"]
end

test "reading partial messages while readable" do |connection|
  connection.to_io.define_singleton_method(:read_nonblock) { |*| "hi\nho" }

  assert_equal connection.read, ["hi\n"]

  connection.to_io.define_singleton_method(:read_nonblock) { |*| "\n" }

  assert_equal connection.read, ["ho\n"]
end

test "reading while not readable" do |connection|
  connection.to_io.define_singleton_method(:read_nonblock) do |*|
    raise Errno::EWOULDBLOCK
  end

  assert_equal connection.read, []
end

test "reading from closed socket" do |connection|
  connection.to_io.define_singleton_method(:read_nonblock) do |*|
    raise EOFError
  end

  assert_raise(Banter::ConnectionError) { connection.read }
  assert_raise(EOFError)                { connection.read }
end

test "connection status after reading from closed socket" do |connection|
  connection.to_io.define_singleton_method(:read_nonblock) do |*|
    raise EOFError
  end

  connection.read rescue nil

  assert_equal connection.connected?, false
end

# TODO: Reading tests with other errors.


test "writing while writeable" do |connection|
  connection.to_io.define_singleton_method(:write_nonblock) { |*| 4 }

  assert_equal connection.write("hi\n"), "hi\n"

  connection.to_io.define_singleton_method(:write_nonblock) { |*| 0 }

  assert_equal connection.write("ho\n"), ""

  connection.to_io.define_singleton_method(:write_nonblock) { |*| 4 }

  assert_equal connection.write(""), "ho\n"
end

test "writing while not writeable" do |connection|
  connection.to_io.define_singleton_method(:write_nonblock) do |*|
    raise Errno::EWOULDBLOCK.tap { |x| x.extend IO::WaitWritable }
  end

  assert_equal connection.write("hi\n"), false
end

test "writing to closed socket" do |connection|
  connection.to_io.define_singleton_method(:write_nonblock) do |*|
    raise Errno::ECONNRESET
  end

  assert_raise(Banter::ConnectionError) { connection.write "hi\n" }
  assert_raise(Errno::ECONNRESET)       { connection.write "hi\n" }
end

test "connection status after writing to closed socket" do |connection|
  connection.to_io.define_singleton_method(:write_nonblock) do |*|
    raise Errno::ECONNRESET
  end

  connection.write("hi\n") rescue nil

  assert_equal connection.connected?, false
end

# TODO: Writing tests with other errors.
