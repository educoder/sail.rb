require 'blather/client/dsl'
require 'json'

module Sail
  class Agent
    include Blather::DSL
      
    attr_accessor :config
    
    def initialize(config = {})
      config[:port]     ||= 5222
      config[:username] ||= self.class.name
      config[:nickname] ||= config[:username]
      
      @config = config
    end
    
    def spawn!
      setup(agent_jid, config[:password], config[:host], config[:port])
      log "Spawning #{self} with: #{config.inspect}"
      behaviour # TODO: consider checking for 'behavior' (american spelling) and execute if present?
    end
    
    def behviour
      raise NotImplemetedError, "You must implement a `behaviour` method for your agent."
    end
    
    def agent_jid
      config[:username].downcase + "@" + config[:host]
    end
    
    def room_jid
      "#{config[:room]}@conference.#{config[:host]}"
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
      "#{room_jid}/#{config[:nickname]}"
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
      "#{self.class.name}(#{agent_jid})"
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
    # Note that the type can be omitted, in which case this handler
    # will be triggered for ALL events.
    def event(*type, &block)
      if type.nil? || (type.kind_of?(Array) && type.empty?)
        log "Setting up catch-all event handler..."
        setup_message_handler(nil, &block) # catch all
      elsif type.kind_of? Array
        log "Setting up event handler for multiple events: #{type.inspect}"
        type.each {|t| setup_message_handler(t, &block) }
      else
        log "Setting up event handler for: #{type.inspect}"
        setup_message_handler(type, &block)
      end
    end
    
    def log(log_msg, level = :INFO)
      timestamp = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")
      puts "#{timestamp} [#{agent_jid_in_room}] [#{level}] #{log_msg}"
      
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
      
      def self.parse_json(json)
        # FIXME: this is a bandaid for weird UTF-8 decoding issues under Ruby 1.8 (looks like this is not necessary under 1.9)
        json = json.gsub(/\302\240/,'') if RUBY_VERSION < "1.9"
        return JSON.parse(json)
      end
    end
    
    protected
    
    def setup_message_handler(type, &block)
      type = type.to_s.gsub(/\?$/,'')
      
      matcher = lambda do |stanza|
        log "Running matcher with #{type.inspect}"
        begin
          data = Util.parse_json(stanza.body)
          if type.blank? # type is catch all
            return true
          else
            return data['eventType'] && data['eventType'].to_s == type.to_s
          end
        rescue JSON::ParserError
          log "Couldn't parse JSON: #{stanza.body.inspect}", :WARN
          return false
        end
      end
  
      wrapper = lambda do |stanza|
        data = Util.parse_json(stanza.body)
      
        begin
          block.call(stanza, data)
        rescue => e
          log e, :FATAL
          puts e.backtrace.join("\n\t")
        end
      end
      
      message(matcher, &wrapper)
    end
  end
end
