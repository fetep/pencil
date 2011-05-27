require "models/base"
require "models/graph"
require "models/host"
require "set"

module Dash::Models
  class Dashboard < Base
    CACHE_EXPIRE_TIME = 3600 # in seconds
    attr_accessor :graphs
    attr_accessor :cache # {graph=> [GEN_TIME,HOSTS,CLUSTERS]}

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

      @cache = {}
    end

    # now with caching!
    def get_valid_hosts(graph, cluster=nil)
      if Time.now.to_i - (cache[graph]||[0]).first > CACHE_EXPIRE_TIME
        puts "#{graph.name} cache #{cache[graph] ? 'stale' : 'miss'}"
        metrics = expand(graph)

        clusters = Set.new
        if cluster
          metrics = metrics.select { |m| m[-2] == cluster }
        end

        # field -1 is the host name, and -2 is its cluster
        hosts = metrics.map { |x| Host.new(x[-1], {'cluster' => x[-2]}) }

        # filter by what matches the graph definition
        hosts = hosts.select { |h| h.multi_match(graph['hosts']) }

        # filter if we have a dashboard-level 'hosts' filter
        if @params['hosts']
          hosts = hosts.select { |h| h.multi_match(@params['hosts']) }
        end

        hosts.each { |h| clusters << h.cluster }
        hosts = hosts.collect { |h| h.name }.uniq # host name w/o cluster
        cache[graph] = [Time.now.to_i, hosts, clusters]
      end

      return cache[graph][1], cache[graph][2]
    end

    # return an array of all metrics matching the specifications in graph['metrics']
    # metrics are arrays of fields (once delimited by periods)
    def expand(graph)
      url = URI.join(@params[:graphite_url], "/metrics/expand/?query=").to_s
      hosts = @params['hosts'] || graph['hosts']
      metrics = []

      graph['metrics'].each do |metric|
        query = open("#{url}#{metric.first}.*.*").read
        metrics << JSON.parse(query)['results']
      end

      return metrics.flatten.map { |x| x.split('.') }
    end

    def render_cluster_graph(graph, clusters, opts={})
      # FIXME: edge case where the dash filter does not filter to a subset of the hosts filter
      # for now, simply use dash filters (or inherit graph filters when no dash filters are defined)
      hosts = get_host_wildcards(graph)

      if opts[:zoom]
        graph_url = graph.render_url(hosts.to_a, clusters, opts)
      else
        opts[:sum] = :cluster
        graph_url = graph.render_url(hosts.to_a, clusters, opts)
      end
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
      clusters = expand(graph).map { |x| x[-2] }.uniq

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

        if dash['graphs'].map { |x| x.keys.first }.member?(graph.name)
          ret << dash
        end
      end

      return ret
    end
  end # Dash::Models::Dashboard
end # Dash::Models
