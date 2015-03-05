require_relative "../test_helper"
require "banter/command"
require "irc/rfc2812/message"

def msg(message)
  IRC::RFC2812::Message.new(message)
end

setup do
  lambda = lambda { |req, opt = nil| $test = [req, opt] }
  
  Banter::Command.new("!", "name", "Description", &lambda)
end

prepare { $test = nil }

test "usage" do |command|
  assert_equal command.usage, "!name <req> [opt]"
end

test "help message" do |command|
  assert_equal command.help, "Description: !name <req> [opt]"
end

test "ignores normal messages" do |command|
  message = msg("PRIVMSG target :normal message")
  assert_equal false, command.call(message)
end

test "ignores other commands" do |command|
  message = msg("PRIVMSG target :!names req")
  assert_equal false, command.call(message)
end

test "ignores other prefixes" do |command|
  message = msg("PRIVMSG target :@name req")
  assert_equal false, command.call(message)
end

test "starts from the beginning" do |command|
  message = msg("PRIVMSG target :Just type !name req")
  assert_equal false, command.call(message)
end

test "call with --help as argument" do |command|
  exception = assert_raise(ArgumentError) do
    command.call(msg("PRIVMSG target :!name --help"))
  end

  assert_equal exception.message, command.help
end

test "call with -h as argument" do |command|
  exception = assert_raise(ArgumentError) do
    command.call(msg("PRIVMSG target :!name -h"))
  end

  assert_equal exception.message, command.help
end

test "call with too few arguments" do |command|
  exception = assert_raise(ArgumentError) do
    command.call(msg("PRIVMSG target :!name"))
  end

  assert_equal exception.message, "Usage: #{command.usage}"
end

test "call with enough arguments" do |command|
  message = msg("PRIVMSG target :!name req")

  assert_equal true, command.call(message)
  assert_equal ["req", nil], $test
end

test "call with optional arguments" do |command|
  message = msg("PRIVMSG target :!name req opt")

  assert_equal true, command.call(message)
  assert_equal ["req", "opt"], $test
end

test "call with too much arguments" do |command|
  message = msg("PRIVMSG target :!name req opt 1 2")

  assert_equal true, command.call(message)
  assert_equal ["req", "opt 1 2"], $test
end

test "call with different case" do |command|
  message = msg("PRIVMSG target :!NAmE req opt")

  assert_equal true, command.call(message)
  assert_equal ["req", "opt"], $test
end
