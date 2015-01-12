require_relative "../test_helper"
require "banter/network"
require "banter/user"

setup { Banter::User.new("nick", $network) }

prepare { $network = Banter::Network.new("irc://0.0.0.0:6667") }

test "nickname" do |user|
  assert_equal user.nick, "nick"
end

# Conversions

test "#to_s" do |user|
  assert_equal user.to_s, "nick"
end

# Equality 

test "#==" do |user|
  assert user == "nick"
  assert user == "NICK"
  assert user == user
end


# Commands

test "sending a PRIVMSG" do |user|
  user.privmsg("trail")

  assert_equal $network.queue.gets, "PRIVMSG nick :trail\r\n"
end

test "sending a NOTICE" do |user|
  user.notice("trail")

  assert_equal $network.queue.gets, "NOTICE nick :trail\r\n"
end


# Whois query

whois = [":server.com 311 us nick user host.com * :realname\r\n",
         ":server.com 319 us nick :@#one +#two #three \r\n",
         ":server.com 312 us nick server.com :Server info\r\n",
         ":server.com 317 us nick 0 :seconds idle\r\n",
         ":server.com 318 us nick :End of /WHOIS list.\r\n"]

test "#user" do |user|
  assert_equal simulate(whois) { user.user }, "user"
end

test "#host" do |user|
  assert_equal simulate(whois) { user.host }, "host.com"
end

test "#realname" do |user|
  assert_equal simulate(whois) { user.realname }, "realname"
end

test "#channels" do |user|
  assert_equal simulate(whois) { user.channels }, ["#one", "#two", "#three"]
end

test "#channels (with status)" do |user|
  assert_equal simulate(whois) { user.channels("@") }, ["#one"]
end

test "#server" do |user|
  assert_equal simulate(whois) { user.server }, "server.com"
end

test "#network_operator? (is an IRC operator)" do |user|
  messages = [":server.com 313 us nick :is an IRC operator\r\n"] + whois

  assert_equal simulate(messages) { user.network_operator? }, true
end

test "#network_operator? (isn't an IRC operator)" do |user|
  assert_equal simulate(whois) { user.network_operator? }, false
end

test "#idle_since" do |user|
  idle_time = simulate(whois) { user.idle_since }
  
  assert_equal idle_time.class, Time
  assert Time.now - idle_time < 1 # This can sometimes fail.
end

test "an unsuccessful WHOIS query" do |user|
  messages = $network.protocol::REPLIES[:whois][:errors]

  messages.each do |message|
    assert_raise(Banter::ErrorReply) do
      simulate([message.to_s]) { user.user }
    end
  end
end


# Userhost query

test "#away? (user is away)" do |user|
  messages = [":server.com 302 us :nick=+realname@host.com \r\n"]

  assert_equal simulate(messages) { user.away? }, true
end

test "#away? (user is not away)" do |user|
  messages = [":server.com 302 us :nick=-realname@host.com \r\n"]

  assert_equal simulate(messages) { user.away? }, false 
end


# ISON query

test "#online? (user is online)" do |user|
  messages = [":server.com 303 banter :nick\r\n"]

  assert_equal simulate(messages) { user.online? }, true
end

test "#online? (user is not online)" do |user|
  messages = [":server.com 303 banter :\r\n"]

  assert_equal simulate(messages) { user.online? }, false
end

