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

    def key
      "#{@cluster}#{@name}"
    end

    def to_s
      @name
    end

    def eql?(other)
      key == other.key
    end

    def ==(other)
      key == other.key
    end

    def <=>(other)
      unless @params[:host_sort] == "numeric"
        return key <=> other.key
      end

      regex = /\d+/
      match = @name.match(regex)
      match2 = other.name.match(regex)
      if match.pre_match != match2.pre_match
        match.pre_match <=> match2.pre_match
      else
        match[0].to_i <=> match2[0].to_i
      end
    end

    def hash
      key.hash
    end

    def self.find_by_name_and_cluster(name, cluster)
      Host.each do |host_name, host|
        next unless host_name = name
        return host if host.cluster == cluster
      end
      return nil
    end

    def self.find_by_cluster(cluster)
      ret = []
      Host.each do |name, host|
        ret << host if host.cluster == cluster
      end
      return ret
    end

  end # Dash::Models::Host
end # Dash::Models
