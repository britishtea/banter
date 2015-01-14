require_relative "../test_helper"
require "banter/plugin"
require "banter/network"
require "stringio"

Thread.abort_on_exception = true

class Plugin < Banter::Plugin
  extend Banter::Plugin::Concurrent

  define("name") do
    if network.equal?($network)
      $test += 1
    else
      sleep
    end    
  end
end

setup { Plugin.dup }

prepare do
  $stderr            = STDERR
  $network           = Banter::Network.new("irc://0.0.0.0:6667")
  $different_network = Banter::Network.new("irc://0.0.0.0:6667")
  $test              = 0
end

test "waits for thread to finish when registered" do |plugin|
  plugin.define("name") { $test += 1 }
  plugin.call(:register, $network)

  assert_equal $test, 1
end

test "waits for all running threads when unregistered" do |plugin|
  plugin.call(:event, $different_network)
  plugin.call(:event, $network)
  plugin.call(:event, $network)
  plugin.call(:unregister, $network)

  assert_equal $test, 3
end

test "finishes running plugins when disconnected" do |plugin|
  plugin.call(:event, $different_network)
  plugin.call(:event, $network)
  plugin.call(:event, $network)
  plugin.call(:disconnect, $network)

  assert_equal $test, 3
end

test "raises exceptions" do |plugin|
  plugin.define("name") { raise "an exception" }
  $stderr = StringIO.new # Make the test less noisy
  
  assert_raise(RuntimeError) do
    plugin.call(:event, $network).join
  end
end
