require 'rubygems'

require 'pidly'

module Sail
  class Daemon < Pidly::Control
    
    before_start do
      load_agents
    end
    
    start do
      trap(:INT) do
        @agents.each {|a| a.stop}
        EM.stop
      end
      trap(:TERM) do
        @agents.each {|a| a.stop}
        EM.stop
      end
      
      a = ""
      begin
        # ... don't really understand why the begin-rescue needs to be outside EM.run
        # but if we put it inside, expections don't seem to get caught
        EM.run do
          @agents.each do |a|
            a.run
          end
        end
      rescue => e
        msg = "Couldn't load #{a.class} agent! --> #{e}\n#{e.backtrace.join("\n")}"
        $stderr.puts msg
        log(:error, msg)
      end
    end
    
    stop do
      EM.stop_event_loop
    end
    
    def load_agents
      @agents = []
      Dir['*.rb'].each do |rb|
        next unless File.file?(rb)
        
        log(:info, "Trying to load #{rb.inspect} as an agent...")
        load(rb)
                
        # adapted from ActiveSupport's "camelize" (MIT Licensed)
        agent_class = rb.to_s.
          gsub(/\.rb$/,'').
          gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
        
        if defined?(agent_class)
          begin
            agent = Module.const_get(agent_class).new
            if agent.respond_to?(:run)
              agent.prep if agent.respond_to?(:prep)
              log(:info, "Initialized #{agent_class} agent.")
              @agents << agent
            end
          rescue NameError
            log(:info, "Skipping #{agent_class}.")
          end
        end
      end 
    end
    
  end
end
