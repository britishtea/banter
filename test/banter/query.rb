require_relative "../test_helper"
require "banter/query"
require "irc/rfc2812/message"

def msg(message)
  IRC::RFC2812::Message.new message
end

setup { Banter::Query }

test "expecting one reply (no start, no end)" do |klass|
  query = klass.new(:replies => [:reply])
  
  query << msg("IGNORE") << msg("REPLY") << msg("REPLY")

  assert_equal query.messages, [msg("REPLY")]
end

test "expecting multiple replies (no start, with end)" do |klass|
  query = klass.new(:end => [:end], :replies => [:one, :two])

  query << msg("ONE") << msg("IGNORE") << msg("TWO")
  query << msg("END")

  assert_equal query.messages, [msg("ONE"), msg("TWO")]
end

test "expecting multiple replies (with start, with end)" do |klass|
  query = klass.new(:start => :start, :end => :end, :replies => [:one, :two])

  query << msg("ONE") # this one should be ignored
  query << msg("START")
  query << msg("ONE") << msg("IGNORE") << msg("TWO") 
  query << msg("END")

  assert_equal query.messages, [msg("ONE"), msg("TWO")]
end

test "errors" do |klass|
  query = klass.new(:replies => [:reply], :errors => [:error])

  query << msg("ERROR")
  
  assert_raise(Banter::ErrorReply) { query.messages }
  
  exception = assert_raise(Banter::ErrorReply) { query.messages }
  assert_equal exception.code, :error
end

test "can act as a plugin" do |klass|
  query = klass.new({})

  assert query.respond_to? :call
  assert_equal query.method(:call).arity, -3
end
