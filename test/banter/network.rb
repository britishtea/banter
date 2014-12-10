require_relative "../test_helper"
require "banter/network"

$plugin = proc { |*args| $test = args }

setup { Banter::Network.new "irc://0.0.0.0:4000", :key => "value" }

prepare { $test = nil }


# Attributes

test "getting the URI" do |network|
  assert_equal network.uri, URI("irc://0.0.0.0:4000")
end

test "getting the settings" do |network|
  assert_equal network.settings.class, ThreadSafe::Hash
  assert_equal network.settings, ThreadSafe::Hash.new(:key => "value")
end

test "getting non-existing settings" do |network|
  assert_equal network.settings[:a], ThreadSafe::Hash.new
  assert_equal network.settings[:a][:b][:c], ThreadSafe::Hash.new
end

test "getting the connection" do |network|
  assert_equal network.connection.class, Banter::Connection
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
  plugin = proc { |_, network| $test = network.settings[plugin] }
  network.register plugin, :key => "value"

  assert_equal $test, ThreadSafe::Hash.try_convert(:key => "value")
end

test "registering a plugin twice" do |network|
  2.times { network.register $plugin }

  assert_equal network.plugins, [$plugin, $plugin]
end

test "registering a plugin that raises Banter::MissingSettings" do |network|
  exception = Banter::MissingSettings
  plugin    = proc { raise exception }

  assert_raise(exception) { network.register plugin, :key => "value" }
  assert_equal network.plugins, []
  assert_equal network.settings.key?(plugin), false
end

test "registering an invalid plugin" do |network|
  assert_raise(Banter::InvalidPlugin) { network.register "" }
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


test "parsing messages" do |network|
  msg = ":prefix PRIVMSG #channel :Hello"

  assert_equal network.parse_message(msg), IRC::RFC2812::Message.new(msg)
end

# Handling events

test "handling an event" do |network|
  message = ":prefix PRIVMSG #channel :Hello"
  network.register $plugin
  network.handle_event :receive, message

  assert_equal $test, [:receive, network, message]
end

test "handling an event when #stop_handling! has been called" do |network|
  network.stop_handling!

  assert_raise Banter::StoppedHandling do
    network.handle_event :receive, "hello"
  end
end

test "handling an event concurrently" do |network|
  message = ":prefix PRIVMSG #channel :Hello"
  network.register $plugin
  network.handle_event_concurrently :receive, message
  network.stop_handling!

  assert_equal $test, [:receive, network, message]
end

test "handling an event concurrently when #stop_handling! has been called" do |network|
  network.stop_handling!

  assert_raise Banter::StoppedHandling do
    network.handle_event_concurrently :receive, "hello"
  end
end


# Sockets

test "connecting successfully" do |network|
  network.connection.define_singleton_method(:connect) { |*| true }

  network.register($plugin) && $test = nil
  network.connect
  
  assert_equal $test, [:connect, network, nil]
end

test "connecting unsuccessfully" do |network|
  network.connection.define_singleton_method(:connect) { |*| false }

  network.register($plugin) && $test = nil
  network.connect

  assert_equal $test, nil
end

test "disconnecting" do |network|
  network.connection.define_singleton_method(:disconnect) { |*| nil }

  network.register($plugin) && $test = nil
  network.connect
  network.disconnect

  assert_equal $test, [:disconnect, network, nil]
end


test "selected for reading while not connected" do |network|
  network.connection.define_singleton_method(:read) { |*| $test = true }
  
  network.selected_for_reading

  assert_equal $test, nil
end

test "selected for reading while connected" do |network|
  network.define_singleton_method(:connected?) { true }
  network.connection.define_singleton_method(:read) { |*| ["PING"] }

  network.register $plugin
  network.selected_for_reading
  network.stop_handling!

  assert_equal $test, [:receive, network, network.parse_message("PING")]
end

test "selected for reading while connected with errors" do |network|
  exception = StandardError.new
  network.define_singleton_method(:connected?) { true }
  network.connection.define_singleton_method(:read) { raise exception }
  
  network.register $plugin
  
  assert_raise(exception.class) { network.selected_for_reading }
end

test "selected for writing while not connected" do |network|
  network.define_singleton_method(:connected?) { false }
  network.define_singleton_method(:connect) { |*| $test = true }

  network.selected_for_writing

  assert_equal $test, true
end

test "selected for writing while connected" do |network|
  network.define_singleton_method(:connected?) { true }
  network.connection.define_singleton_method(:write) { |*| "PING\n" }

  network.register($plugin) && $test = nil
  network << "PING\n"
  network.selected_for_writing
  network.stop_handling!

  assert_equal $test, [:send, network, network.parse_message("PING\n")]
end

test "selected for writing while connected with partial message" do |network|
  network.define_singleton_method(:connected?) { true }
  network.connection.define_singleton_method(:write) { |*| "PIN" }

  network.register($plugin) && $test = nil
  network << "PING\n"
  network.selected_for_writing

  network.connection.define_singleton_method(:write) { |*| "G\n"}
  network.selected_for_writing
  network.stop_handling!

  assert_equal $test, [:send, network, network.parse_message("PING\n")]  
end

test "selected for writing while connected with empty queue" do |network|
  network.define_singleton_method(:connected?) { true }
  network.connection.define_singleton_method(:write) { |*| "" }

  network.register($plugin) && $test = nil
  network.selected_for_writing
  network.stop_handling!

  assert_equal $test, nil
end

test "selected for writing while connected with errors" do |network|
  exception = StandardError.new
  network.define_singleton_method(:connected?) { true }
  network.connection.define_singleton_method(:write) { |*| raise exception }

  network.register $plugin
  network << "PING\n"
  
  assert_raise(exception.class) { network.selected_for_writing }
end


# Conversions

test "#to_io" do |network|
  assert network.to_io.is_a? IO
end
