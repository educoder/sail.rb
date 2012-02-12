require 'rubygems'
require 'pidly'
require 'json'

module Sail
  class Daemon < Pidly::Control
    
    attr_accessor :config
    
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
      _before_start
    end
    
    start do
      _start
    end
    
    stop do
      _stop
    end
    
    def start_interactive
      _before_start
      _start
      #_stop
    end
    
    def _before_start
      @agents.each{|a| a.spawn!}
    end
    
    def _start
      trap(:INT) { @agents.each{|a| a.stop}; EM.stop }
      trap(:TERM) { @agents.each{|a| a.stop}; EM.stop }
      EM.run { @agents.each{|a| a.run} }
    end
    
    def _stop
      @agents.each{|a| a.stop }
      EM.stop_event_loop
    end
    
  end
end