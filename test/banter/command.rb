require_relative "../test_helper"
require "banter/command"

setup do
  lambda = lambda { |req, opt = nil| [req, opt] }
  
  Banter::Command.new("!", "name", "Description", &lambda)
end

test "usage" do |command|
  assert_equal command.usage, "!name <req> [opt]"
end

test "help message" do |command|
  assert_equal command.help, "Description: !name <req> [opt]"
end

test "ignores normal messages" do |command|
  assert_equal nil, command.call("normal message")
end

test "ignores other commands" do |command|
  assert_equal nil, command.call("!other req")
end

test "ignores other prefixes" do |command|
  assert_equal nil, command.call("@name req")
end

test "starts from the beginning" do |command|
  assert_equal nil, command.call("Just type !name req")
end

test "call with --help as argument" do |command|
  exception = assert_raise(ArgumentError) do
    command.call("!name --help")
  end

  assert_equal exception.message, command.help

  assert_raise(ArgumentError) do
    command.call("!name -h")
  end

  assert_equal exception.message, command.help
end

test "call with too few arguments" do |command|
  exception = assert_raise(ArgumentError) do
    command.call("!name")
  end

  assert_equal exception.message, "Usage: #{command.usage}"
end

test "call with enough arguments" do |command|
  assert_equal ["req", nil], command.call("!name req")
end

test "call with optional arguments" do |command|
  assert_equal ["req", "opt"], command.call("!name req opt")
end

test "call with too much arguments" do |command|
  assert_equal ["req", "opt 1 2"], command.call("!name req opt 1 2")
end

test "call with different case" do |command|
  assert_equal ["req", "opt"], command.call("!NAmE req opt")
end
