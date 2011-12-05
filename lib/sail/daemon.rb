require 'rubygems'
require 'pidly'


module Sail
  class Daemon < Pidly::Control
    
    def initialize(*args)
      super(*args)
      @agents = []
    end
    
    def load_config(path)
      json = File.read(path)
      @config = JSON.parse(json, :symbolize_names => true)
      validate_config!
    end
    
    def validate_config!
      raise "Missing xmpp configuration! Check your config.json..." unless @config[:xmpp]
      raise "Missing xmpp domain configuration! Check your config.json..." unless @config[:xmpp][:domain]
      raise "Missing xmpp port configuration! Check your config.json..." unless @config[:xmpp][:domain]
    end
    
    def <<(agent)
      agent.config[:host] = @config[:xmpp][:domain]
      agent.config[:port] = @config[:xmpp][:port]
      agent.config[:sail] = @config
      @agents << agent
    end
    
    before_start do
      @agents.each{|a| a.spawn!}
    end
    
    start do
      trap(:INT) { @agents.each{|a| a.stop}; EM.stop }
      trap(:TERM) { @agents.each{|a| a.stop}; EM.stop }
      EM.run { @agents.each{|a| a.run} }
    end
    
    stop do
      @agents.each{|a| a.stop }
      EM.stop_event_loop
    end
    
  end
end