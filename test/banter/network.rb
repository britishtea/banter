require_relative "../test_helper"
require "banter/network"

$plugin = proc { |*args| $test = args }

setup { Banter::Network.new "irc://0.0.0.0:6667", :key => "value" }

prepare { $test = nil }


# Attributes

test "getting the URI" do |network|
  assert_equal network.uri, URI("irc://0.0.0.0:6667")
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

test "getting the buffer String" do |network|
  assert_equal network.buffer.class, String
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


# Conversions

test "#to_io" do |network|
  assert network.to_io.is_a? IO
end
