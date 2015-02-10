# Banter

A small IRC library.



## What is it

Banter is a lightweight, flexible IRC framework written in Ruby. It has a
flexible plugin system and a convenient way to interact with channels and users.

Banter is currently in development, the API–especially the plugin API– is 
subject to change.



## Usage

```ruby
client = Banter::Client.new
client.network("irc://irc.freenode.net:6667")
client.register(Banter::Plugins::Default, :nick => "banter_bot",
                                          :channels => ["#banter"])
client.start!
```

### Plugins

Banter has a flexible and simple plugin system. Any object that responds to 
`#call` and which takes two required arguments and one optional argument is a
valid plugin.

The simplest possible plugin is a `Proc`. This one echoes incoming `PRIVMSGS`s.

```ruby
plugin = proc do |event, network, message = nil|
  if event == :receive
    network << "PRIVMSG #{message.params[0]} :#{message}\r\n"
  end
end
```

As said, plugins take two required arguments and on optional argument.

1. `event`: an event `Symbol` (`:register`, `:unregister`, `:connect`, 
   `:disconnect`, `:receive` or `:send`).
2. `network`: a `Banter::Network` instance.
3. `message`: An `IRC::Message` (for the events `:receive` and 
   `:send`).

Banter provides the `Banter::Plugin` class to make it easy to write plugins.
Below is a simple plugin that relays messages between two channels.

```ruby
require "banter/channel"

class Relay < Banter::Plugin
  define "relay" do
    event(:register) do
      required :channel
    end

    event(:receive) do |message|
      message.match(:privmsg) do
        settings[:channel].privmsg "[#{message.prefix.nick}] #{message}"
      end
    end
  end
end

client    = Banter::Client.new
freenode  = client.network("irc://irc.freenode.net:6667")
localhost = client.network("irc://0.0.0.0:6667")

freenode.register(Relay,  :channel => Banter::Channel.new("#banter", localhost))
localhost.register(Relay, :channel => Banter::Channel.new("#banter", freenode))
client.register(Banter::Default, :nick => "banter_bot", :channels => ["#banter"])

client.start!
```

Plugins can be run concurrently when the module `Banter::Plugin::Concurrent` is
mixed in.

```ruby
class Relay
  extend Banter::Plugin::Concurrent

  ...
end
```

See the `/examples` directory for examples of plugins.



## Installation

`gem install banter`



## License

See the LICENSE file.
