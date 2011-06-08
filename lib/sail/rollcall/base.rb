require 'active_resource'

module Rollcall
  class Base < ActiveResource::Base
    self.site = ROLLCALL_URL
  end
end