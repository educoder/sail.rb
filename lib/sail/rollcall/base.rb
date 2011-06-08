require 'active_resource'

module Rollcall
  class Base < ActiveResource::Base
    self.site = ENV['ROLLCALL_URL']
  end
end