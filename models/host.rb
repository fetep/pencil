require "models/base"
require "models/graph"

module Dash::Models
  class Host < Base
    attr_accessor :graphs

    def initialize(name, params={})
      super

      @graphs = []
      Graph.each do |graph_name, graph|
        graph['hosts'].each do |h|
          if match(h)
            @graphs << graph
            break
          end
        end # graph['hosts'].each
      end # Graph.each
    end

    def cluster
      return @params['cluster']
    end

  end # Dash::Models::Host
end # Dash::Models
