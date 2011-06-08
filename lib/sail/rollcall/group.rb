require 'sail/rollcall/base'

class Rollcall::Group < Rollcall::Base
  
  def jid
    if account && account.login
      "#{account.login}@#{ENV['XMPP_DOMAIN']}"
    else
      nil
    end
  end
  
  def to_s
    "Group[#{id}:#{name.inspect}]"
  end
end