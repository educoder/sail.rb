require 'json'

module Sail
  module Agent
    def self.included(base)
      base.extend(DSL)
    end

    def trigger_event(type, data, opts = {})
      to = opts[:to] || channel
      format = opts[:format] || format

      ev = {'type' => type, 'content' => content}

      body = ev.to_json

      msg = Blather::Stanza::Message.new
      msg.to = to
      msg.type = :groupchat unless opts[:to]
      msg.body = body

      client.send(msg)
    end

    def channel
      @channel
    end

    def format
      @format || :json
    end

    module DSL
      def sail_event(type = nil, &block)
        lambda = 
        message lambda &block
      end
    end
  end
end
