class Default < Banter::Plugin
  include IRC::RFC2812::Constants
  
  define "default" do
    event :register do
      required :nickname, :username
      default  :channels => [], :realname => settings[:username],
               :quit_message => ""
    end

    event :connect do  
      pass settings[:password] if settings.key?(:password)
      nick settings[:nickname]
      user settings[:username], settings[:realname]
    end

    event :disconnect do
      quit settings[:quit_message]
    end

    event :receive do |message|
      message.match RPL_MYINFO do
        join settings[:channels]
      end

      message.match RPL_BOUNCE, /Try server (\S+), port (\d+)/i do |host, port|
        network.uri.host = host
        network.uri.port = port.to_i
        network.reconnect
      end

      message.match :ping do
        pong message.prefix
      end
    end
  end
end
