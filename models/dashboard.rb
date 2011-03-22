require "models/base"
require "models/graph"
require "models/host"
require "set"

module Dash::Models
  class Dashboard < Base
    attr_accessor :graphs

    def initialize(name, params={})
      super

      @graphs = []
      params["graphs"].each do |name|
        g = Graph.find(name)
        @graphs << g if g
      end
    end

    def get_valid_hosts(graph, cluster=nil)
      clusters = Set.new
      if cluster
        hosts = Host.find_by_cluster(cluster)
      else
        hosts = Host.all
        hosts.each { |h| clusters << h.cluster }
      end

      # filter by what matches the graph definition
      hosts = hosts.select { |h| h.multi_match(graph['hosts']) }

      # filter if we have a dashboard-level 'hosts' filter
      if @params['hosts']
        hosts = hosts.select { |h| h.multi_match(@params['hosts']) }
      end

      hosts.each { |h| clusters << h.cluster }
      hosts = hosts.collect { |h| h.name }.uniq # host name w/o cluster

      return hosts, clusters
    end

    def render_cluster_graph(graph, clusters, opts={})
      hosts = Set.new
      clusters.each do |cluster|
        new_hosts, new_clusters = get_valid_hosts(graph, cluster)
        hosts.merge(new_hosts)
      end

      if opts[:zoom]
        graph_url = graph.render_url(hosts.to_a, clusters, opts)
      else
        opts[:sum] = :cluster
        graph_url = graph.render_url(hosts.to_a, clusters, opts)
      end
      return graph_url
    end

    def render_global_graph(graph, opts={})
      hosts, clusters = get_valid_hosts(graph)

      next_url = ""
      if opts[:zoom]
        graph_url = graph.render_url(hosts, clusters, :sum => :cluster)
      else
        graph_url = graph.render_url(hosts, clusters, :sum => :global)
      end
      return graph_url
    end

    def self.find_by_graph(graph)
      ret = []
      Dashboard.each do |name, dash|
        if dash['graphs'].member?(graph.name)
          ret << dash
        end
      end

      return ret
    end
  end # Dash::Models::Dashboard
end # Dash::Models
