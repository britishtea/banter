require_relative "../test_helper"
require "banter/event_loop"
require "banter/network"

setup { Banter::EventLoop.new [$network] }

prepare do
  $network = Banter::Network.new "irc://0.0.0.0:6667"
  $test    = nil
end


test "for readability: unconnected" do |eventloop|
  assert_equal eventloop.for_reading, []
end

test "for readabilty: connected" do |eventloop|
  $network.define_singleton_method(:connected?) { true }
  
  assert_equal eventloop.for_reading, [$network, $network.queue]
end


test "for writeability: unconnected, queue empty" do |eventloop|
  assert_equal eventloop.for_writing, [$network]
end

test "for writeability: unconnected, queue filled" do |eventloop|
  $network << "PING :hello"

  assert_equal eventloop.for_writing, [$network]
end

test "for writeability: connected, queue empty" do |eventloop|
  $network.define_singleton_method(:connected?) { true }

  assert_equal eventloop.for_writing, []
end

test "for writeability: connected, queue filled" do |eventloop|
  $network.define_singleton_method(:connected?) { true }
  $network << "PING :hello"

  assert_equal eventloop.for_writing, [$network]
end


test "handle readable" do |eventloop|
  $network.define_singleton_method(:selected_for_reading) { $test = true }
  eventloop.handle_readable $network

  assert_equal $test, true
end

test "handle readable with a connection error" do |eventloop|
  $network.define_singleton_method :selected_for_reading do
    raise StandardError.new.extend(Banter::ConnectionError)
  end
  $network.define_singleton_method(:reconnect) { $test = true }

  eventloop.handle_readable $network

  assert_equal $test, true
  assert_equal eventloop.for_reading, []
end


test "handle writeble" do |eventloop|
  $network.define_singleton_method(:selected_for_writing) { $test = true }
  eventloop.handle_writable $network

  assert_equal $test, true
end

test "handle writable with a connection error" do |eventloop|
  $network.define_singleton_method :selected_for_writing do
    raise StandardError.new.extend(Banter::ConnectionError)
  end
  $network.define_singleton_method(:reconnect) { $test = true }
  
  eventloop.handle_writable $network

  assert_equal $test, true
  assert_equal eventloop.for_writing, []
end
