require_relative "../test_helper"
require "banter/network"

$plugin = proc { |*args| $test = args }

begin
  $port   = 4000
  $server = TCPServer.new $port
rescue
  $port = $port.succ and retry
end

setup { Banter::Network.new "irc://0.0.0.0:#{$port}", :key => "value" }

prepare { $test = nil }


# Attributes

test "getting the URI" do |network|
  assert_equal network.uri, URI("irc://0.0.0.0:#{$port}")
end

test "getting the settings" do |network|
  assert_equal network.settings.class, ThreadSafe::Hash
  assert_equal network.settings, ThreadSafe::Hash.new(:key => "value")
end

test "getting non-existing settings" do |network|
  assert_equal network.settings[:a], ThreadSafe::Hash.new
  assert_equal network.settings[:a][:b][:c], ThreadSafe::Hash.new
end

test "getting the socket" do |network|
  assert network.socket.is_a? Socket
end

test "getting the queue" do |network|
  assert_equal network.queue.class, Banter::SelectableQueue
end


# Plugins

test "listing plugins" do |network|
  assert_equal network.plugins, []
end

test "registering a plugin" do |network|
  assert_equal network.register($plugin), $plugin 
  assert_equal network.plugins, [$plugin]
  assert_equal network.settings[$plugin], ThreadSafe::Hash.new

  assert_equal $test, [:register, network]
end

test "registering a plugin with settings" do |network|
  network.register $plugin, :key => "value"

  assert_equal network.settings[$plugin], ThreadSafe::Hash.new(:key => "value")
end

test "registering a plugin twice" do |network|
  2.times { network.register $plugin }

  assert_equal network.plugins, [$plugin, $plugin]
end

test "registering a plugin that raises on #call(:register, ...)" do |network|
  plugin = proc { raise StandardError }

  assert_equal network.register(plugin, :key => "value"), false
  assert_equal network.plugins, []
  assert_equal network.settings[plugin], ThreadSafe::Hash.new
end

test "registering an invalid plugin" do |network|
  assert_raise(ArgumentError) { network.register "" }
end

test "unregistering a registered plugin" do |network|
  network.register $plugin

  assert_equal network.unregister($plugin), $plugin
  assert_equal $test, [:unregister, network]
  assert_equal network.settings[$plugin], ThreadSafe::Hash.new
end

test "unregistering an unregistered plugin" do |network|
  assert_equal network.unregister($plugin), false
end


# Message handling

test "parsing messages" do |network|
  msg = ":prefix PRIVMSG #channel :Hello"

  assert_equal network.parse_message(msg), IRC::RFC2812::Message.new(msg)
end

test "handling a message" do |network|
  msg = ":prefix PRIVMSG #channel :Hello"

  network.register $plugin
  network.handle_message msg
  network.stop_handling!

  assert_equal $test, [:receive, network, IRC::RFC2812::Message.new(msg)]
end

test "handling a message when #stop_handling! has been called" do |network|
  network.stop_handling!

  assert_raise Banter::Network::StoppedHandling do
    network.handle_message "hello"
  end
end


# Sockets

# TODO: All networking should probably extracted into a Connection class.

test "connection status before connecting" do |network|
  assert_equal network.connected?, false
end

test "connecting" do |network|
  network.register $plugin
  client = Thread.new { $server.accept }
  network.connect
  client.join

  IO.select nil, [network] # wait until connected
  assert_equal network.connect, true
  assert_equal $test, [:connect, network]

  client.value.close
end

test "connection status after connecting" do |network|
  client = Thread.new { $server.accept }
  network.connect
  client.join

  IO.select nil, [network] # wait until connected
  network.connect

  assert_equal network.connected?, true

  client.value.close 
end


test "disconnecting" do |network|
  network.register $plugin
  client = Thread.new { $server.accept }

  network.connect
  IO.select nil, [network]
  network.disconnect

  assert client.value.eof?
  assert_equal $test, [:disconnect, network]
end

test "connection status after disconnecting" do |network|
  client = Thread.new { $server.accept }

  network.connect
  IO.select nil, [network]
  network.disconnect

  assert client.value.eof?
  assert_equal network.connected?, false
end

# test "reading from a socket with no data" do |network|
#   client = Thread.new { $server.accept }
#   network.connect
#   client.join

#   assert_equal network.read, []

#   client.value.close
# end

# test "reading from a socket with data" do |network|
#   client = Thread.new { $server.accept }
#   network.connect
#   client.join

#   client.value.write ":prefix PRIVMSG banter :Hello\n"
#   IO.select [network]
  
#   assert_equal network.read, [":prefix PRIVMSG banter :Hello\n"]

#   client.value.close
# end

# test "reading from a socket with partial data" do |network|
#   client = Thread.new { $server.accept }
#   network.connect
#   client.join
  
#   client.value.write ":prefix PRIVMSG banter :Hell"
#   IO.select [network]
  
#   assert_equal network.read, nil

#   client.value.write "o\n"
#   IO.select [network]

#   assert_equal network.read, [":prefix PRIVMSG banter :Hello\n"]

#   client.value.close
# end

# test "reading from a closed socket" do |network|
#   client    = Thread.new { $server.accept }
#   connected = network.connect

#   unless connected
#     IO.select nil, [network]
#     network.connect
#   end

#   client.value.close
#   IO.select [network], nil, nil, 0

#   # TODO: I think an exception should be raised here.
#   assert_equal network.read, []
# end

# test "connection status after reading from a closed socket" do |network|
#   client    = Thread.new { $server.accept }
#   connected = network.connect

#   unless connected
#     IO.select nil, [network]
#     network.connect
#   end
  
#   client.value.close
#   IO.select [network], nil, nil, 0
#   network.read rescue

#   assert_equal network.connected?, false
# end

# test "writing" do |network|
#   client    = Thread.new { $server.accept }
#   connected = network.connect

#   unless connected
#     IO.select nil, [network]
#     network.connect
#   end

#   read = Thread.new do
#     IO.select [client.value], nil, nil, 3
#     client.value.read_nonblock(3)
#   end
  
#   IO.select nil, [network], nil, 0
  
#   assert network.write("hey")
# end

# TODO: Add tests for writing to closed/broken/disconnected sockets.

# test "writing to a closed socket" do |network|

#   client    = Thread.new { $server.accept }
#   connected = network.connect

#   unless connected
#     IO.select nil, [network]
#     network.connect
#   end

#   client.value.close_read
#   client.value.close_write

#   GC.start
#   IO.select nil, [network]

#   # A closed socket is detected only AFTER a write.
#   assert_equal network.write("hey"), true
  
#   # It isn't garantueed that the next write will fail, but one eventually will.
#   begin
#     IO.select nil, [network]
#     assert_equal network.write("hey"), false
#   rescue Cutest::AssertionFailed
#     sleep 1
#     retry
#   end
# end

# test "connection status after writing to a closed socket" do |network|
#   client    = Thread.new { $server.accept }
#   connected = network.connect

#   unless connected
#     IO.select nil, [network]
#     network.connect
#   end

#   client.value.close
#   IO.select nil, [network], nil, 0
#   network.write "hey" # first time we won't notice.
#   network.write "hey"

#   assert_equal network.connected?, false
# end


# Conversions

test "#to_io" do |network|
  assert network.to_io.is_a? IO
end
