# require "banter/eventloop"
require "banter/network"

module Banter
  # TODO: Implement Banter::EventLoop.
  EventLoop = Class.new

  class Client
    # Public: Gets the Array of registered Networks.
    attr_reader :networks

    # Public: Initializes the client.
    def initialize
      @networks  = Array.new
      @eventloop = EventLoop.new
    end

    # Public: Registers a network with the client.
    #
    # Examples
    # 
    #   client.network "irc://0.0.0.0", :key => "value"
    #   # => #<Banter::Network ...>
    def network(*args, &blk)
      Network.new(*args, &blk).tap { |network| self.networks << network }
    end

    # Public: Unregisters a network with the client.
    def remove_network(network)
      self.networks.delete network
    end

    # Public: Registers a plugin for every currently registered network.
    def register(*args, &blk)
      self.networks.each { |network| network.register *args, &blk }
    end

    # Public: Unregisters a plugin for every currently registered network.
    def unregister(*args)
      self.networks.each { |network| network.unregister *args }
    end

    # Public: Connects all networks.
    def start!
      @eventloop.start self.networks
    end

    # Public: Disconnects all networks.
    def stop!
      @eventloop.stop
    end
  end
end
