require_relative "../test_helper"
require "banter/plugin"
require "banter/network"
require "irc/rfc2812/message"

def msg(message)
  IRC::RFC2812::Message.new(message)
end

setup { Banter::Plugin }

prepare do
  $network        = Banter::Network.new "irc://0.0.0.0:6667"
  $implementation = proc { |*args| $test = args }
  $test           = nil
end

test "doesn't step on irc-helpers' toes" do |plugin|
  commands_methods = IRC::RFC2812::Commands.instance_methods false
  plugin_methods   = plugin.instance_methods false

  assert_equal commands_methods - plugin_methods, commands_methods - [:raw]
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

test "executing a plugin that raises an exception" do |plugin|
  implementation = proc { |*args| raise Banter::MissingSettings }
  
  plugin.define "name", "usage", &implementation

  assert_raise Banter::MissingSettings do 
    plugin.call :event, "network", "message"
  end
end

test "replying to PRIVMSGs" do |plugin|
  $network.define_singleton_method(:<<) { |msg| $test = msg }
  plugin.define("name", "usage") { reply "reply" }

  plugin.call(:send, $network, msg("PRIVMSG target :message"))
  assert_equal $test, nil

  plugin.call(:receive, $network, msg("PRIVMSG target :message"))
  assert_equal $test, "PRIVMSG target :reply\r\n"
end


# Convenience methods

setup { Banter::Plugin.new :event, $network, "args" }

test "getting the network" do |plugin|
  assert_equal plugin.network, $network
end

test "getting the message" do |plugin|
  assert_equal plugin.message, "args"
end

test "getting the settings" do |plugin|
  assert plugin.settings.equal?($network[plugin.class])
end

test "requiring settings" do |plugin|
  plugin.settings[:one] = "one"
  plugin.settings[:two] = "two"

  assert plugin.required :one
  assert plugin.required :one, :two
  
  assert_raise(Banter::MissingSettings) { plugin.required :three }
  assert_raise(Banter::MissingSettings) { plugin.required :three, :four }
end

test "defaulting settings" do |plugin|
  plugin.settings[:one] = "ONE"

  plugin.default :one => "one"
  plugin.default :two => "two", :three => "three"

  assert_equal plugin.settings[:one], "ONE"
  assert_equal plugin.settings[:two], "two"
  assert_equal plugin.settings[:three], "three"
end

test "events" do |plugin|
  plugin.event(:event)       { |*args| $test = [:event, args]  }
  plugin.event(:other_event) { |*args| $test = [:other_event, args] }

  assert_equal $test, [:event, ["args"]]
end

test "sending messages to the network" do |plugin|
  plugin.raw "hello\r\n"

  assert_equal $network.queue.gets, "hello\r\n"
end

test "running another plugin" do |plugin|
  plugin.run $implementation

  assert_equal $test, [:event, $network, "args"]

  plugin.run $implementation, ["ARGS"]
  assert_equal $test, [:event, $network, "ARGS"]
end
