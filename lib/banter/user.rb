require "banter/query"

module Banter
  class User
    # Public: Initializes the Banter::User.
    #
    # prefix  - A prefix String.
    # network - A Banter::Network.
    def initialize(prefix, network)
      @network = network
      @prefix  = network.implementation::Prefix.new(prefix)
      
      # Convenience
      @commands  = @network.implementation::Commands
      @constants = @network.implementation::Constants
      @replies   = @network.implementation::REPLIES
    end

    def ==(other)
      @prefix == @network.implementation::Prefix.new(other)
    end

    def privmsg(message)
      @network << @commands.privmsg(self, message)
    end

    def notice(message)
      @network << @commands.notice(self, message)
    end

    def nick
      @prefix.nick
    end

    alias_method :to_s, :nick

    def user;     whois.user;     end
    def host;     whois.host;     end
    def realname; whois.realname; end

    # Public: Gets a list of channels the user is connected to. If a `status`
    # argument is given it only returns the channels the user has that status
    # on. If no `status` argument is given it returns all channels.
    #
    # status - A status Symbol such as `:@` or `:+` (default: false).
    #
    # Returns an Array of channel Strings.
    def channels(status = false)
      whois.channels(status)
    end

    # Public: Gets the hostname of server the user is connected to.
    #
    # Returns a String.
    def server
      whois.server
    end

    # Public: Checks if the user is an IRC operator.
    def network_operator?
      whois.operator?
    end

    # Public: Gets the idle time.
    #
    # Returns a Time object.
    def idle_since
      Time.now - whois.seconds_idle
    end

    # Public: Checks if the user is marked as "away".
    def away?
      query   = Query.new(@replies[:userhost])
      message = replies_for(query) { @commands.userhost(self) }.first

      return message.trail.split("=", 2).last.start_with?("+")
    end

    # Public: Checks if the user is online
    def online?
      query   = Query.new(@replies[:ison])
      message = replies_for(query) { @commands.ison(self) }.first

      return message.trail.split(" ").include?(nick)
    end

  private

    # Internal: Registers the query as a plugin with the network, sends the 
    # result of block to the network and unregsiters the query as a plugin.
    #
    # query - A Banter::Query.
    def replies_for(query)
      @network.register(query)
          
      if block_given?
        @network << yield
      end
      
      return query.messages
    ensure
      @network.unregister(query)
    end

    # Internal: Performs a WHOIS query.
    #
    # Returns an IRC::*::Whois object.
    def whois
      query    = Query.new(@replies[:whois])
      messages = replies_for(query) { @commands.whois(self) }

      return @network.implementation::Whois.new(*messages)
    end
  end
end
