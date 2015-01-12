require "banter/query"

module Banter
  # TODO: Use a proper WHOIS parser.
  class User
    # Public: Initializes the Banter::User.
    #
    # prefix  - A prefix String.
    # network - A Banter::Network.
    def initialize(prefix, network)
      @network = network
      @prefix  = network.protocol::Prefix.new(prefix)
      
      # Convenience
      @commands  = @network.protocol::Commands
      @constants = @network.protocol::Constants
      @replies   = @network.protocol::REPLIES
    end

    def ==(other)
      @prefix == @network.protocol::Prefix.new(other)
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

    def user
      whois(@constants::RPL_WHOISUSER).first.params[2]
    end

    def host
      whois(@constants::RPL_WHOISUSER).first.params[3]      
    end

    def realname
      whois(@constants::RPL_WHOISUSER).first.trail
    end

    # Public: Gets a list of channels the user is connected to. If a `status`
    # argument is given it only returns the channels the user has that status
    # on. If no `status` argument is given it returns all channels.
    #
    # status - A status Symbol such as `:@` or `:+` (default: nil).
    #
    # Returns an Array of channel Strings.
    def channels(status = nil)
      replies  = whois(@constants::RPL_WHOISCHANNELS)
      channels = replies.flat_map { |reply| reply.trail.split }

      # TODO: An abomination, don't hardcode channel namespaces!
      if status.nil?
        channels.map { |chan|
          if chan =~ /^[@+~%&]/
            chan[1..-1]
          else
            chan
          end
        }
      else
        channels.select { |chan| chan.start_with?(status.to_s) }
                .map    { |chan| chan[1..-1] }
      end
    end

    # Public: Gets the hostname of server the user is connected to.
    #
    # Returns a String.
    def server
      whois(@constants::RPL_WHOISSERVER).first.params[2]
    end

    # Public: Checks if the user is an IRC operator.
    def network_operator?
      whois(@constants::RPL_WHOISOPERATOR).size > 0
    end

    # Public: Gets the idle time.
    #
    # Returns a Time object.
    def idle_since
      message = whois(@constants::RPL_WHOISIDLE).first

      return message.time - message.params[2].to_i
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
    # command - A command Symbol.
    #
    # Returns the replies matching `command`.
    def whois(command)
      query   = Query.new(@replies[:whois])
      replies = replies_for(query) { @commands.whois(self) }

      return replies.select { |reply| reply.command == command }
    end
  end
end
