require "banter/errors"
require "banter/query"
require "thread_safe"

module Banter
  class Channel
    attr_reader :name, :prefix

    alias_method :to_s, :name
    alias_method :to_str, :to_s

    # Public: Initializes the channel.
    #
    # name    - The channel name String.
    # network - The Banter::Network.
    def initialize(name, network)
      @name, @prefix, @network = name, name[0], network

      # Convenience.
      @commands  = network.protocol::Commands
      @constants = network.protocol::Constants
      @replies   = network.protocol::REPLIES
    end

    def privmsg(message)
      @network << @commands.privmsg(self.name, message)
    end

    def notice(message)
      @network << @commands.notice(self.name, message)
    end

    # Public: Gets the channel modes.
    #
    # Returns a Hash.
    def modes
      replies = @replies[:channel_mode].dup
      replies.delete(:end)

      query    = Query.new replies
      messages = replies_for(query) { @commands.mode(self.name) }

      return parse_modes(messages.first)
    end

    # Public: Looks up a channel mode.
    #
    # mode - A mode Symbol.
    #
    # Returns `true`/`false` for set/unset modes, a String for set modes with a 
    # parameter and an Array of mask Strings for set modes "b", "e" and "I".
    def [](mode)
      case mode.to_s
        when "b", "e", "I" then return masks_list(mode)
        else                    return self.modes.fetch(mode, false)
      end
    end

    # Public: Sets a mode. Use `true`/`false` to set/unset modes.
    #
    # mode      - A mode Symbol.
    # parameter - A parameter String, true or false.
    def []=(mode, parameter)
      replies = @replies[:channel_mode].dup
      replies.delete(:end)

      query     = Query.new replies
      messages  = replies_for(query) do
        if parameter == true
          parameter = nil
        elsif parameter == false
          mode = :"-#{mode}"
        end

        @commands.mode(self.name, mode, parameter)
      end

      unless parse_modes(messages.first).key?(mode)
        raise Banter::ErrorReply.new("setting mode failed", 0)
      end
    end

    # Public: Gets the topic.
    #
    # Returns a String if there is a topic or `nil` if there is no topic.
    def topic
      query    = Query.new @replies[:topic]
      messages = replies_for(query) { @commands.topic(self.name) }
      message  = messages.first

      case message.command
        when @constants::RPL_NOTOPIC then return nil
        when @constants::RPL_TOPIC   then return message.trail
      end
    end

    # Public: Sets the topic.
    #
    # topic - An object implementing #to_s.
    def topic=(topic)
      query = Query.new @replies[:topic]

      replies_for(query) { @commands.topic(self.name, topic) }

      return true
    end

    # Public: Gets the nicknames of users on the channel. If a `status` argument
    # is given it returns only the users with that status on the channel. If no
    # `status` argument is given it returns all users.
    #
    # status - A prefix Symbol such as `:@` or `:+` (default: nil).
    #
    # Returns an Array of nickname Strings.
    def names(status = nil)
      query = Query.new @replies[:names]
      msgs  = replies_for(query) { @commands.names(self.name) }
      names = msgs.select do |msg| 
        if msg.params[2].nil? 
          msg.params[1][1..-1] == self.name
        else
          msg.params[2] == self.name
        end
      end.map { |m| m.trail.split }.flatten

      # TODO: Make removing status Symbols more robust (won't work for user \ for example).
      if status.nil?
        names.map { |nick| nick[/^[^a-zA-Z]/] ? nick[1..-1] : nick }
      else
        names.select { |nick| nick[0] == status }
             .map { |nick| nick[1..-1] }
      end
    end

    # Public: Invites a user to channel.
    #
    # user - An object implementing #to_s.
    #
    # Returns `true` or `false`.
    def invite(user)
      query    = Query.new @replies[:invite]
      messages = replies_for(query) do
        @commands.invite(user, self.name)
      end

      return case messages.first.command
        when @constants::RPL_INVITING then true
        when @constants::RPL_AWAY     then false
      end
    end
    
    # Public: Kicks a user of the channel.
    #
    # user - An object implementing #to_s.
    # reason - An object implementing #to_s (default: nil).
    #
    # Returns true.
    def kick(user, reason = nil)
      query = Query.new @replies[:kick]

      replies_for(query) { @commands.kick(self.name, user, reason) }

      return true
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

    # TODO: Use a proper mode parser.
    def parse_modes(message)
      if message.command == :mode
        mode_chars = message.params[1]
        parameters = message.params[2..-1]
      else
        mode_chars = message.params[2]
        parameters = message.params[3..-1]
      end
      
      mode_chars = mode_chars.delete("+").chars.map(&:to_sym)
      parameters.fill true, parameters.length, mode_chars.length

      return Hash[mode_chars.zip parameters]
    end

    def masks_list(mode)
      query = Query.new @replies[:channel_mode]
      msgs  = replies_for(query) { @commands.mode(self.name, mode) }

      return msgs.map { |message| message.params[2] }
    end
  end
end
