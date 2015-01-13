require_relative "../test_helper"
require "banter/plugin"
require "banter/network"

setup do
  Banter::Plugin.extend(Banter::Plugin::Concurrent)
  Banter::Plugin.define("name") { $test += 1 }

  Banter::Plugin
end

prepare do
  $stderr  = STDERR
  $network = Banter::Network.new("irc://0.0.0.0:6667")
  $test    = 0
end

test "finishes running plugins when unregistered" do |plugin|
  plugin.call(:event, $network)
  plugin.call(:event, $network)
  plugin.call(:unregister, $network)

  assert_equal $test, 3
end

test "finishes running plugins when disconnected" do |plugin|
  plugin.call(:event, $network)
  plugin.call(:event, $network)
  plugin.call(:disconnect, $network)

  assert_equal $test, 3
end

test "raises exceptions" do |plugin|
  plugin.define("name") { raise "an exception" }
  $stderr = File.open("/dev/null", "w") # Make the test less noisy
  
  assert_raise(RuntimeError) do
    plugin.call(:event, $network)
  end
end
