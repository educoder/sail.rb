require 'blather/client/dsl'
require 'json'

module Sail
  class Agent
    include Blather::DSL
    
    attr_accessor :server, :port, :password, :room, :nickname
    
    def initialize(opts = {})
      @server   = opts[:server]   || "proto.encorelab.org"
      # @port     = opts[:port]     || 5275
      # @password = opts[:password] || "encore!"
      # @room  =    opts[:room]     || "s3"
      # @nickname = opts[:nickname] || self.class.name
      @port     = opts[:port]     || 5222
      @password = opts[:password] || "2072eb498b176dd2824d7c21da697bd4a2a26a58"
      @nickname = opts[:nickname] || self.class.name
      @room  =    opts[:room]     || "s3"
    end
    
    def my_jid
      # "#{nickname}.#{server}"
      nickname.downcase + "@" + server
    end
    
    def room_jid
      "#{room}@conference.#{server}"
    end
    
    def my_jid_in_room
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
      client.run
    end
    
    def stop
      puts "stopping #{self}..."
      client.clear_handlers(:disconnected)
      client.close
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

      ev = data.dup
      ev['type'] = type

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
            return data['type'] && data['type'].to_s == type.to_s
          else
            return true
          end
        rescue JSON::ParserError
          return false
        end
      end
    
      wrapper = Proc.new{|stanza| block.call(stanza, JSON.parse(stanza.body))}
      message(matcher, &wrapper)
    end

  end
end
