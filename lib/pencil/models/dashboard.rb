require "pencil/models/base"
require "pencil/models/graph"
require "pencil/models/host"
require "set"

module Pencil
  module Models
    class Dashboard < Base
      attr_accessor :graphs
      attr_accessor :graph_opts

      def initialize(name, params={})
        super

        @graphs = []
        @graph_opts = {}
        params["graphs"].each do |name|
          # graphs map to option hashes
          if name.respond_to?(:keys) # could be YAML::Omap
            g = Graph.find(name.keys.first) # should only be one key
            @graph_opts[g] = name[name.keys.first]||{}
          else
            raise "Bad format for graph (must be a hash-y; #{name.class}:#{name.inspect} is not)"
          end

          @graphs << g if g
        end

        @valid_hosts_table = {} # cache calls to get_valid_hosts
      end

      def clusters
        clusters = Set.new
        @graphs.each { |g| clusters += get_valid_hosts(g)[1] }
        clusters.sort
      end

      def get_all_hosts(cluster=nil)
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
        if @valid_hosts_table[[graph, cluster]]
          return @valid_hosts_table[[graph, cluster]]
        end

        clusters = Set.new
        if cluster
          hosts = Host.find_by_cluster(cluster)
        else
          hosts = Host.all
        end

        # filter by what matches the graph definition
        hosts = hosts.select { |h| h.multi_match(graph["hosts"]) }

        # filter if we have a dashboard-level 'hosts' filter
        if @params["hosts"]
          hosts = hosts.select { |h| h.multi_match(@params["hosts"]) }
        end

        hosts.each { |h| clusters << h.cluster }

        @valid_hosts_table[[graph, cluster]] = [hosts, clusters]
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

      def get_host_wildcards(graph)
        return graph_opts[graph]["hosts"] || @params["hosts"] || graph["hosts"]
      end

      def render_global_graph(graph, opts={})
        hosts = get_host_wildcards(graph)
        _, clusters = get_valid_hosts(graph)

        next_url = ""
        type = opts[:zoom] ? :cluster : :global
        options = opts.merge({:sum => type})
        graph_url = graph.render_url(hosts, clusters, options)
        return graph_url
      end

      def self.find_by_graph(graph)
        ret = []
        Dashboard.each do |name, dash|

          if dash["graphs"].map { |x| x.keys.first }.member?(graph.name)
            ret << dash
          end
        end

        return ret
      end
    end # Pencil::Models::Dashboard
  end
end # Pencil::Models
