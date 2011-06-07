require 'blather/client/dsl'
require 'json'
require 'ruby-debug'
module Sail
  class Agent
    include Blather::DSL
    
    attr_accessor :host, :port, :username, :password, :room, :nickname
    
    def initialize(opts = {})
      @host     = opts[:host]   || "proto.encorelab.org"
      @port     = opts[:port]     || 5222
      @username = opts[:username] || self.class.name
      @password = opts[:password] || "3deaf4592358b1d837e6eb075bdce10a9438834b" # "Encore agent secret password!"
      @nickname = opts[:nickname] || @username
      @room     = opts[:room]     || "s3"
      
      setup(agent_jid, password, host, port)
    end
    
    def vitalize
      logic
    end
    
    def agent_jid
      # "#{nickname}.#{host}"
      username.downcase + "@" + host
    end
    
    def room_jid
      "#{room}@conference.#{host}"
    end
    
    def log_room_jid
      return nil unless @groupchat_logger_ready
      
      if @log_room_jid
        @log_room_jid
      elsif room
        room_jid
      else
        nil
      end
    end
    
    def groupchat_logger_ready!
      # TODO: set to false when no longer ready (e.g. disconnected)
      @groupchat_logger_ready = true
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
    
      wrapper = lambda do |stanza|
        data = JSON.parse(stanza.body)
        payload = data['payload']
        
        if stanza.type == :groupchat
          payload[:from] = stanza.from.resource
        else
          payload[:from] = stanza.from.node
        end
        
        begin
          block.call(stanza, payload)
        rescue => e
          log e, :FATAL
        end
      end
      message(matcher, &wrapper)
    end
    
    def log(log_msg, level = :INFO)
      puts log_msg
      
      room_jid = room_jid || @log_room_jid
      
      if log_room_jid
        msg = Blather::Stanza::Message.new
        msg.to = log_room_jid
        msg.type = :groupchat
        msg.body = "#{level}: #{log_msg}"

        client.write(msg)
      end
    end

    class Util
      def self.jid_pattern
        /(.*?)@([a-zA-Z0-9\.\-]*)(?:\/(.*?))?/
      end
      
      def self.extract_jid(jid)
        if jid.kind_of? Blather::JID
          return {
            :node => jid.node,
            :domain => jid.domain,
            :resource => jid.resource
          }
        else
          parts = jid_pattern.match(jid)
          return {
            :node => parts[1],
            :domain => parts[2],
            :resource => parts[3]
          }
        end
      end
      
      def self.extract_login(str)
        jid = extract_jid(str)
        username = jid[:resource] || jid[:node]
        if username =~ jid_pattern
          return extract_login(username)
        else
          return username
        end
      end
    end
  end
end
