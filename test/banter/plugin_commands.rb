require_relative "../test_helper"
require "banter/network"
require "banter/plugin"
require "irc/rfc2812/message"

def msg(message)
  IRC::RFC2812::Message.new(message)
end

setup do
  Banter::Plugin.define do
    command "name", "Description" do |required, optional = nil|
      $test = [required, optional]
    end

    command "name", "Description" do |required, optional = nil|
      $test = false
    end
  end

  Banter::Plugin
end

prepare do
  $network = Banter::Network.new("irc://0.0.0.0:6667")
  $prefix  = $network[:prefix]
  $test    = nil
end

test "defaults to the network prefix" do |plugin|
  message = msg("PRIVMSG target :#{$prefix}name req opt")
  plugin.call(:receive, $network, message)

  assert_equal $network[plugin].key?(:prefix), false
  assert_equal $test, ["req", "opt"]
end

test "prefers the plugin prefix" do |plugin|
  $network[plugin][:prefix] = "#"
  plugin.call(:receive, $network, msg("PRIVMSG target :#name req opt"))

  assert_equal $test, ["req", "opt"]
end

test "only runs when the event is :receive" do |plugin|
  message = msg("PRIVMSG target :#{$prefix}name req opt")
  plugin.call(:send, $network, message)

  assert_equal $test, nil
end

test "only runs when the IRC command is PRIVMSG" do |plugin|
  message = msg("NOTICE target :#{$prefix}name req opt")
  plugin.call(:receive, $network, message)

  assert_equal $test, nil
end

test "only runs the first matching command" do |plugin|
  message = msg("PRIVMSG target :#{$prefix}name req opt")
  plugin.call(:receive, $network, message)

  assert_equal $test, ["req", "opt"]
end

test "sends usage if invoked improperly" do |plugin|
  $network.define_singleton_method(:<<) { |msg| $test = msg }

  message = msg("PRIVMSG target :#{$prefix}name")
  plugin.call(:receive, $network, message)

  assert_equal $test, "PRIVMSG target :Usage: !name <required> [optional]\r\n"
end

test "sends help message if invoked with --help or -h" do |plugin|
  $network.define_singleton_method(:<<) { |msg| $test = msg }

  messages = [
    msg("PRIVMSG target :#{$prefix}name --help"),
    msg("PRIVMSG target :#{$prefix}name -h"),
  ]

  messages.each do |message|
    plugin.call(:receive, $network, message)

    excepted = "PRIVMSG target :Description: !name <required> [optional]\r\n"
    assert_equal $test, excepted
  end
end

test "has access to the plugin instance" do |plugin|
  plugin.define do
    command("name", "Description") { $test = self }
  end

  message = msg("PRIVMSG target :#{$prefix}name")
  plugin.call(:receive, $network, message)
  
  assert $test.is_a?(plugin)
end
