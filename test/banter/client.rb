require_relative "../test_helper"
require "banter/client"

$plugin = proc { |*args| $test = args }

setup { Banter::Client.new }

prepare { $test = nil }

test "listing networks" do |client|
  assert_equal client.networks, []
end

test "registering a network" do |client|
  network = client.network "irc://0.0.0.0:6667", :key => "value"

  assert_equal network.class, Banter::Network
  assert_equal client.networks, [network]
end

test "unregistering a network" do |client|
  network = client.network "irc://0.0.0.0:6667", :key => "value"
  client.remove_network network
  
  assert_equal client.networks, []
end

test "registering a plugin" do |client|
  network = client.network "irc://0.0.0.0:6667", :key => "value"

  client.register $plugin, :key => "value"

  assert_equal network.plugins, [$plugin]
end

test "unregistering a plugin" do |client|
  network = client.network "irc://0.0.0.0:6667", :key => "value"
  
  client.register $plugin, :key => "value"
  client.unregister $plugin

  assert_equal network.plugins, []
end
