require 'blather/client/dsl'
require 'json'

module Sail
  class Agent
    include Blather::DSL
    
    attr_accessor :host, :port, :username, :password, :room, :nickname
    
    def initialize(opts = {})
      raise ArgumentError, "Missing password!" unless opts[:password]
      
      @host     = opts[:host]   || "proto.encorelab.org"
      @port     = opts[:port]     || 5222
      @username = opts[:username] || self.class.name
      @password = opts[:password]
      @nickname = opts[:nickname] || @username
      @room     = opts[:room]     || "s3"
      
      setup(agent_jid, password, host, port)
    end
    
    def agent_jid
      # "#{nickname}.#{host}"
      username.downcase + "@" + host
    end
    
    def room_jid
      "#{room}@conference.#{host}"
    end
    
    def agent_jid_in_room
      "#{room_jid}/#{nickname}"
    end
    
    def debug=(debug)
      if debug
        Blather.logger.level = Logger::DEBUG if debug
      else
        Blather.logger.level = Logger::ERROR
      end
    end
    
    def run
      begin
        client.run
      rescue => e
        EM.stop_event_loop
        raise e
      end
    end
    
    def stop
      puts "stopping #{self}..."
      client.clear_handlers(:disconnected)
      client.close
      EM.stop_event_loop
    end
    
    def run_em
      trap(:INT) { EM.stop }
      trap(:TERM) { EM.stop }
      EM.run do
        self.run
      end
    end
    
    def to_s
      "#{self.class.name} Agent"
    end

    # Triggers a Sail event of the given type with the given data.
    #
    # opts:
    #   :to => JID who the event should be directed at;
    #          if omitted, event will be sent to @room
    #          as a groupchat message
    def event!(type, data, opts = {})
      raise ArgumentError, "'data' must be a Hash!" unless data.kind_of?(Hash)
      
      to = opts[:to] || room_jid

      ev = {}
      ev['eventType'] = type
      ev['payload'] = data.dup

      body = ev.to_json

      msg = Blather::Stanza::Message.new
      msg.to = to
      msg.type = :groupchat unless opts[:to]
      msg.body = body

      client.write(msg)
    end
  
    # Sets up a handler for a Sail event of the given type.
    def event(type = nil, &block)
      type = type.to_s.gsub(/\?$/,'')
      
      matcher = lambda do |stanza|
        puts stanza.inspect
        begin
          data = JSON.parse(stanza.body)
          if type
            return data['eventType'] && data['eventType'].to_s == type.to_s
          else
            return true
          end
        rescue JSON::ParserError
          return false
        end
      end
    
      wrapper = Proc.new do |stanza|
        data = JSON.parse(stanza.body)
        payload = data['payload']
        block.call(stanza, payload)
      end
      message(matcher, &wrapper)
    end

  end
end
