require_relative "../test_helper"
require "banter/query"
require "irc/rfc2812/message"

def msg(message)
  IRC::RFC2812::Message.new message
end

setup { Banter::Query.new }

test "expecting one reply (no start, no end)" do |query|
  query.replies = [:reply]
  
  query << msg("REPLY")
  query.wait

  assert_equal query.messages, [msg("REPLY")]
end

test "expecting multiple replies (no start, with end)" do |query|
  query.replies = [:replyone, :replytwo]
  query.end     = :end

  query << msg("REPLYONE")
  query << msg("REPLYTWO")
  query << msg("END")
  query.wait

  assert_equal query.messages, [msg("REPLYONE"), msg("REPLYTWO")]
end

test "expecting multiple replies (with start, with end)" do |query|
  query.replies = [:replyone, :replytwo]
  query.start   = :start
  query.end     = :end

  query << msg("REPLYONE") # this one should be ignored
  query << msg("START")
  query << msg("REPLYONE")
  query << msg("REPLYTWO")
  query << msg("END")
  query.wait

  assert_equal query.messages, [msg("REPLYONE"), msg("REPLYTWO")]
end

test "errors" do |query|
  query.replies = [:reply]
  query.errors  = [:error]

  query << msg("ERROR")
  
  assert_raise(Banter::ErrorReply) { query.wait }
  assert_equal query.messages, []
end
