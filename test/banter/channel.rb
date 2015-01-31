require_relative "../test_helper"
require "banter/channel"
require "banter/network"
require "irc/rfc2812/message"

setup { Banter::Channel.new "#channel", $network }

prepare { $network = Banter::Network.new "irc://0.0.0.0:6667" }

test "#prefix" do |channel|
  assert_equal channel.prefix, "#"
end

test "#name" do |channel|
  assert_equal channel.name, "#channel"
end

# Conversions

test "#to_s" do |channel|
  assert_equal channel.to_s, "#channel"
end

test "#to_str" do |channel|
  assert_equal channel.to_str, "#channel"
end

test "sending a privmsg" do |channel|
  channel.privmsg("trail")

  assert_equal $network.queue.gets, "PRIVMSG #channel :trail\r\n"
end

test "sending a notice" do |channel|
  channel.notice("trail")

  assert_equal $network.queue.gets, "NOTICE #channel :trail\r\n"
end


# Channel modes

test "getting a list of channel modes" do |channel|
  messages = ["324 nickname #channel +knt key"]
  modes    = simulate(messages) { channel.modes }

  assert_equal modes.to_hash, { :k => "key", :n => true, :t => true }
end

test "getting a mode when mode is set" do |channel|
  messages = ["324 nickname #channel +nti"]
  mode     = simulate(messages) { channel[:i] }

  assert_equal mode, true
end

test "getting a mode with parameters when mode is set" do |channel|
  messages = ["324 nickname #channel +knt key"]
  mode     = simulate(messages) { channel[:k] }
  
  assert_equal mode, "key"  
end

test "getting a mode when mode is not set" do |channel|
  messages = ["324 nickname #channel +nt"]
  mode     = simulate(messages) { channel[:k] }

  assert_equal mode, false
end

test "getting a mode with parameters when mode is not set" do |channel|
  messages = ["324 nickname #channel +nt"]
  mode     = simulate(messages) { channel[:k] }
  
  assert_equal mode, false
end

test "getting mode \"b\" (ban masks)" do |channel|
  messages  = ["367 nickname #channel one!*@*",
               "367 nickname #channel two!*@*",
               "368 nickname #channel :End of channel ban list"]
  masks = simulate(messages) { channel[:b] }
  
  assert_equal masks, ["one!*@*", "two!*@*"]
end

test "getting mode \"e\" (exception masks)" do |channel|
  messages = ["348 nickname #channel one!*@*",
              "348 nickname #channel two!*@*",
              "349 nickname #channel :End of channel exception list"]
  masks = simulate(messages) { channel[:e] }
  
  assert_equal masks, ["one!*@*", "two!*@*"]  
end

test "getting mode \"I\" (invitation masks)" do |channel|
  messages = ["346 nickname #channel one!*@*",
              "346 nickname #channel two!*@*",
              "347 nickname #channel :End of channel invite list"]
  masks = simulate(messages) { channel[:I] }
  
  assert_equal masks, ["one!*@*", "two!*@*"]  
end

test "setting a mode successfully" do |channel|
  messages = ["MODE #channel +nti"]
  mode     = simulate(messages) { channel[:i] = true }

  assert mode
end

test "setting a mode with parameters successfully" do |channel|
  messages = ["MODE #channel +kti key"]
  mode     = simulate(messages) { channel[:k] = "key" }
  
  assert mode
end

test "setting a mode unsuccessfully" do |channel|
  messages = $network.protocol::REPLIES[:channel_mode][:errors]
  
  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { channel[:i] = true }
    end
  end 
end


# Topic

test "getting the topic when topis is set" do |channel|
  messages = ["332 nickname #channel :the topic"]
  topic    = simulate(messages) { channel.topic }

  assert_equal topic, "the topic"
end

test "getting the topic when topic is not set" do |channel|
  messages = ["331 nickname #channel :No topic is set"]
  topic    = simulate(messages) { channel.topic }

  assert_equal topic, nil  
end

test "getting the topic of a channel not currently joined" do |channel|
  messages = $network.protocol::REPLIES[:topic][:errors]
  
  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { channel.topic }
    end
  end
end

test "setting the topic successfully" do |channel|
  messages = ["TOPIC #channel :topic"]
  topic    = simulate(messages) { channel.topic = "topic" }

  assert_equal topic, "topic"
end

test "setting the topic without operator privileges" do |channel|
  messages = $network.protocol::REPLIES[:topic][:errors]
  
  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { channel.topic = "topic" }
    end
  end
end


# Names

test "getting the list of names" do |channel|
  messages = ["353 nickname = #other :@a +b c \\",
              "353 nickname = #channel :@one +two",
              "353 nickname = #channel :three \\",
              "366 nickname #channel :End of /NAMES list."]
  names = simulate(messages) { channel.names }
 
  assert_equal names, ["one", "two", "three", "\\"]
end

test "getting the list of users with a particular status" do |channel|
  messages = ["353 nickname = #other :@a +b c",
              "353 nickname = #channel :@one +two",
              "353 nickname = #channel :three",
              "366 nickname #channel :End of /NAMES list."]
  names = simulate(messages) { channel.names("@") }
  
  assert_equal names, ["one"]
end

test "getting the list of names unsuccessfully" do |channel|
  messages = $network.protocol::REPLIES[:names][:errors]
  
  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { channel.names }
    end
  end 
end


# Invite

test "inviting a user successfully" do |channel|
  messages = ["341 nickname #channel they"]
  invite   = simulate(messages) { channel.invite "they" }
  
  assert_equal invite, true
end

test "invitng a user that is away" do |channel|
  messages = ["301 nickname they :away message"]
  invite   = simulate(messages) { channel.invite "they" }

  assert_equal invite, false
end

test "inviting a user unsuccessfully" do |channel|
  messages = $network.protocol::REPLIES[:invite][:errors]

  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { channel.invite "they" }
    end
  end
end

# Kick

test "kicking a user successfully" do |channel|
  messages = ["KICK #channel they"]
  kick     = simulate(messages) { channel.kick "they" }

  assert_equal kick, true
end

test "kicking a user with a reason successfully" do |channel|
  messages = ["KICK #channel they :reason"]
  kick     = simulate(messages) { channel.kick "they", "reason" }

  assert_equal kick, true
end

test "kicking a user unsuccessfully" do |channel|
  messages = $network.protocol::REPLIES[:kick][:errors]

  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { channel.kick "they", "reason" }
    end
  end
end
