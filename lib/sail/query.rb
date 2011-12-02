require 'blather/stanza/iq/query'

module Sail
  # quick and dirty way to send arbitrary JSON-encoded queries and resposnes as XMPP IQs
  class Query < Blather::Stanza::Iq::Query
    NS = 'sail:query'
    
    register :query, :query, NS
    
    def query
      q = if self.class.registered_ns
        find_first('query_ns:query', :query_ns => self.class.registered_ns)
      else
        find_first('query')
      end

      unless q
        (self << (q = Blather::XMPPNode.new('query', self.document)))
        q.namespace = self.class.registered_ns
      end
      q
    end
  end
end