require 'rubygems'
require 'pidly'


module Sail
  class Daemon < Pidly::Control
    
    def initialize(*args)
      super(*args)
      @agents = []
    end
    
    def <<(agent)
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