require_relative "../test_helper"
require "banter/plugin"
require "banter/network"

setup { Banter::Plugin }

prepare do
  $network        = Banter::Network.new "irc://0.0.0.0:6667"
  $implementation = proc { |*args| $test = args }
  $test           = nil
end

test "defining a plugin" do |plugin|
  plugin.define "name", &$implementation
end

test "defining a plugin with a usage String" do |plugin|
  plugin.define "name", "usage", &$implementation
end

test "getting the plugin name" do |plugin|
  plugin.define "name", &$implementation

  assert_equal plugin.name, "name"
end

test "getting the usage String from a plugin without usage String" do |plugin|
  plugin.define "name", &$implementation

  assert_equal plugin.usage, nil
end

test "getting the usage String from a plugin with usage String" do |plugin|
  plugin.define "name", "usage", &$implementation

  assert_equal plugin.usage, "usage"
end

test "executing a plugin" do |plugin|
  plugin.define "name", "usage", &$implementation
  plugin.call :event, "network", "message"

  assert_equal $test, ["message"]
end

# Convenience methods

setup { Banter::Plugin.new :event, $network, "args" }

test "getting the network" do |plugin|
  assert_equal plugin.network, $network
end

test "getting the settings" do |plugin|
  assert plugin.settings.equal?($network.settings[plugin.class])
end

test "required settings that are not set" do |plugin|
  plugin.settings[:one] = "one"

  assert_raise(Banter::MissingSettings) { plugin.required :one, :two }
end

test "required settings that are set" do |plugin|
  plugin.settings[:one] = "one"
  plugin.settings[:two] = "two"

  assert plugin.required :one, :two
end

test "default settings that are not set" do |plugin|
  plugin.default :one => "one", :two => "two"

  assert_equal plugin.settings.values_at(:one, :two), ["one", "two"]
end

test "default settings that are set" do |plugin|
  plugin.settings[:one], plugin.settings[:two] = "one", "two"
  plugin.default :one => "ONE", :two => "TWO"

  assert_equal plugin.settings.values_at(:one, :two), ["one", "two"]
end

test "running a block per event" do |plugin|
  plugin.event(:event)       { |*args| $test = [:event, args]  }
  plugin.event(:other_event) { |*args| $test = [:other_event, args] }

  assert_equal $test, [:event, ["args"]]
end

test "working with irc-helpers" do |plugin|
  commands_methods = IRC::RFC2812::Commands.instance_methods false
  plugin_methods   = Banter::Plugin.instance_methods false

  assert_equal commands_methods - plugin_methods, commands_methods - [:raw]
end

test "sending messages to the network" do |plugin|
  plugin.raw "hello\nbye\n"

  assert_equal $network.queue.pop, "hello\nbye\n"
end

test "running another plugin" do |plugin|
  plugin.run $implementation

  assert_equal $test, [:event, $network, "args"]
end

# TODO: cuba style on matchers (?), #reply, User and Channel helpers.
