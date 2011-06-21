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
        # graphs can now map to option hashes, which in the current
        # implementation override the graph's original parameters
        # :override is observed by dashboards when choosing the appropriate
        # hosts to send off to graphite

        # if we ever decide to fix support for arbitrary graph AND dash filters
        # concurrently probably a new key like :expand could be used
        if name.instance_of?(Hash)
          g = Graph.find(name.keys.first) # should only be one key
          if g && name.values.first
            h = name.values.first.member?('hosts') ? {:override => true} : {}
            g.update_params(name.values.first.merge(h))
          end
        else
          g = Graph.find(name)
        end

        @graphs << g if g
      end

    end

    def clusters
      clusters = Set.new
      @graphs.each { |g| clusters += get_valid_hosts(g)[1] }
      clusters.sort
    end

    def get_all_hosts (cluster=nil)
      hosts = Set.new
      clusters = Set.new
      @graphs.each do |g|
        h, c = get_valid_hosts(g, cluster)
        hosts += h
        clusters += c
      end
      return hosts, clusters
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

      return hosts, clusters
    end

    def render_cluster_graph(graph, clusters, opts={})
      # FIXME: edge case where the dash filter does not filter to a subset of
      # the hosts filter

      hosts = get_host_wildcards(graph)
      opts[:sum] = :cluster unless opts[:zoom]
      graph_url = graph.render_url(hosts.to_a, clusters, opts)
      return graph_url
    end

    def get_host_wildcards (graph)
      if graph[:override]
        hosts = graph['hosts']
      else
        hosts = @params['hosts'] || graph['hosts']
      end
      return hosts
    end

    def render_global_graph(graph, opts={})
      hosts = get_host_wildcards(graph)
      _, clusters = get_valid_hosts(graph) #fixme redundant

      next_url = ""
      type = opts[:zoom] ? :cluster : :global
      options = opts.merge({:sum => type})
      graph_url = graph.render_url(hosts, clusters, options)
      return graph_url
    end

    def self.find_by_graph(graph)
      ret = []
      Dashboard.each do |name, dash|

        if dash['graphs'].map { |x| x.keys.first }.member?(graph.name)
          ret << dash
        end
      end

      return ret
    end
  end # Dash::Models::Dashboard
end # Dash::Models
