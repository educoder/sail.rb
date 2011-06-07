require 'sail/rollcall/base'

class Rollcall::User < Rollcall::Base
  
  def jid
    "#{account.login}@#{XMPP_DOMAIN}"
  end
  
  def to_s
    "User[#{id}:#{display_name.inspect}]"
  end
end