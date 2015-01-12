$:.unshift File.expand_path('../../lib', __FILE__)

def simulate(messages, &block)
  result = Thread.new { yield }

  # Ensure message is "sent" before waiting for replies.
  $network.queue.gets

  messages.each do |message|
    $network.handle_event(:receive, $network.protocol::Message.new(message))
  end

  result.value
end
