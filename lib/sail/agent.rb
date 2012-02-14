require 'blather/client/dsl'
require 'json'

require 'sail/query'

module Sail
  class Agent
    include Blather::DSL
      
    attr_accessor :config
    
    attr_accessor :log_to
    attr_accessor :catch_event_exceptions
    
    attr_reader :registered_events
    
    def initialize(config = {})
      config[:port]     ||= 5222
      config[:username] ||= self.class.name
      config[:nickname] ||= config[:username]
      
      @config = config
      @log_to = $stdout
      @catch_event_exceptions = true
      
      @registered_events = []
    end
    
    def spawn!
      setup(agent_jid, config[:password], config[:host], config[:port])
      log "Spawning #{self} with: #{config.inspect}"
      
      # put this in "default_behaviour" or something
      message :type => :error do |stanza|
        log stanza, :ERROR
      end
      
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
        @log_room_jid || "#{config[:room]}-log@conference.#{config[:host]}"
    end
    
    def groupchat_logger_ready!
      # TODO: set to false when no longer ready (e.g. disconnected)
      @groupchat_logger_ready = true
    end
    
    def agent_jid_in_room
      "#{room_jid}/#{config[:nickname]}"
    end
    
    def agent_jid_in_log_room
      "#{log_room_jid}/#{config[:nickname]}"
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
      
      opts.symbolize_keys!
      data.symbolize_keys!
      
      to = opts[:to] || room_jid

      ev = {}
      ev['eventType'] = type
      ev['payload'] = data.dup
      ev['origin'] = opts[:origin] || config[:nickname] || config[:username]
      ev['timestamp'] = opts[:timestamp] || Time.now 

      body = ev.to_json

      msg = Blather::Stanza::Message.new
      msg.to = to
      msg.type = :groupchat unless opts[:to] # if explicit :to was given, then this event is to be delivered as a private message
      msg.body = body

      client.write(msg)
    end
    
    def onetime_event(*type, &block)
      log "Setting up onetime event handler for: #{type.inspect}"
      setup_event_handler(type, true, &block)
    end
  
    ##### DSL ADDITIONS ####
    
    # Sets up a handler for a Sail event of the given type.
    # Note that the type can be omitted, in which case this handler
    # will be triggered for ALL events.
    def event(*type, &block)
      if type.nil? || type.empty?
        log "Setting up catch-all event handler..."
        setup_event_handler(nil, &block) # catch all
      elsif type.length == 1
        log "Setting up event handler for: #{type.inspect}"
        setup_event_handler(type, &block)
      else
        log "Setting up event handler for multiple events: #{type.inspect}"
        type.each {|t| setup_event_handler(t, &block) }
      end
    end
    
    # TODO: check that this actually works
    def self_joined_room(&block)
      presence(:from => Blather::JID.new(agent_jid_in_room), :type => nil, &block)
    end
    
    # TODO: check that this actually works
    def someone_joined_room(&block)
      presence(:from => Regexp.new("^#{room_jid}/.*"), :type => nil, &block)
    end
    
    # TODO: check that this actually works
    def self_left_room(&block)
      presence(:from => Blather::JID.new(agent_jid_in_room), :type => :unavailable, &block)
    end
    
    # TODO: check that this actually works
    def someone_left_room(&block)
      presence(:from => Regexp.new("^"+Blather::JID.new(room_jid).to_s+".*"), :type => :unavailable, &block)
    end
    
    def self_joined_log_room(&block)
      presence(:from => Blather::JID.new(agent_jid_in_log_room), :type => nil, &block)
    end
    
    #### END DSL ADDITIONS ####
    
    def log(log_msg, level = :INFO)
      timestamp = Time.now.strftime("%Y-%m-%dT%H:%M:%S.%L")
      @log_to.puts "#{timestamp} [#{agent_jid_in_room}] [#{level}] #{log_msg}"
      @log_to.flush
      
      if @groupchat_logger_ready
        msg = Blather::Stanza::Message.new
        msg.to = log_room_jid
        msg.type = :groupchat
        msg.body = "#{level}: #{log_msg}"

        client.write(msg)
      end
    end
    
    def join_room
      pres = Blather::Stanza::Presence::Status.new
      pres.to = agent_jid_in_room
      pres.state = :chat
      
      log "Joining #{agent_jid_in_room.inspect}..."
      
      client.write(pres)
    end
    
    def join_log_room
      pres = Blather::Stanza::Presence::Status.new
      pres.to = agent_jid_in_log_room
      pres.state = :chat
      
      log "Joining #{agent_jid_in_log_room.inspect}..."
      
      client.write(pres)
    end

    class Util
      def self.jid_pattern
        /(.*?)@([a-zA-Z0-9\.\-]*)(?:\/(.*))?/
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
          # resource was actually a full jid (happens in prosody, for example)
          jid2 = extract_jid(username)
          return jid2[:node]
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
    
    def setup_event_handler(type, onetime = false, &block)
      type = type.to_s.gsub(/\?$/,'')
      
      matcher = lambda do |stanza|
        if stanza.from.stripped == Blather::JID.new(log_room_jid).stripped
          # ignore messages in the log room
          return false
        end
        
        begin
          data = Util.parse_json(stanza.body)
          if type.blank? # type is catch all
            return true
          else
            return data['eventType'] && data['eventType'].to_s == type.to_s
          end
        rescue JSON::ParserError
          log "Couldn't parse JSON for event handler #{type.inspect}: #{stanza.body.inspect}", :WARN
          return false
        end
      end
  
      wrapper = lambda do |stanza|
        if onetime
          # unregister
          client.instance_eval do
            @handlers[:message].delete_if {|g, _| g.first === matcher}
          end
          @registered_events.delete_if{|ev|
            ev[:type] === type && ev[:handler] === block && 
            ev[:onetime] == onetime && ev[:mater] == matcher }
        end
        
        data = Util.parse_json(stanza.body)
      
        begin
          block.call(stanza, data)
        rescue => e          
          log e, :FATAL
          if @catch_event_exceptions
            # FIXME: don't do this... this ignores @log_to. Not sure what else to do with it though.
            $stderr.puts e
            $stderr.puts e.backtrace.join("\n\t")
          else
            raise e
          end
        end
      end
      
      @registered_events << {
        :type => type,
        :handler => block,
        :wrapped_handler => wrapper,
        :matcher => matcher,
        :onetime => onetime
      }
      
      message(matcher, &wrapper)
    end
  end
end
