require 'sail/rollcall/base'

class Rollcall::User < Rollcall::Base
  
  def jid
    "#{account.login}@#{ENV['XMPP_DOMAIN']}"
  end
  
  def to_s
    "User[#{id}:#{account.login.inspect}]"
  end
end