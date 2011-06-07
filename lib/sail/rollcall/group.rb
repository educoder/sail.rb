require 'sail/rollcall/base'

class Rollcall::Group < Rollcall::Base
  def to_s
    "Group[#{id}:#{name.inspect}]"
  end
end