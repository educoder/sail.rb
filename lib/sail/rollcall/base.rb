require 'active_resource'

module Rollcall
  class Base < ActiveResource::Base
    XMPP_DOMAIN = "proto.encorelab.org"
    
    if SAIL_ENV == :development
      self.site = "http://localhost:3000"
    else
      self.site = "http://rollcall.proto.encorelab.org"
    end
  end
end