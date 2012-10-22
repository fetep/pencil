require 'pencil/models/base'
require 'graphite_graph'

module Pencil::Models
  class PencilGraph < GraphiteGraph
    # This class consists of some pretty bad hacks to the GraphiteGraph that will
    # make it work with a system like Pencil's. Stare too long at this and your
    # eyes may bleed (though not as much as the old YAML-based configs did).
    attr_reader :name, :metrics
    class << self
      attr_accessor :graphite_url, :metric_format
    end

    METRIC_REGEXP = /[^(),]+/

    def render_url
      @@render_url ||= "#{URI.join(self.class.graphite_url, '/render/?')}"
    end
    def expand_url
      @@expand_url ||= \
      "#{URI.join(self.class.graphite_url, '/metrics/expand/?leavesOnly=1&query=')}"
    end

    def initialize(file, overrides={}, info={})
      super(file, overrides, info)
      @name = File.basename(@file.chomp('.graph'))
      @aggregator ||= 'sumSeries'
      @metrics = []
      targets.each do  |t, b|
        d = b[:data].gsub(' ', '').scan(METRIC_REGEXP)
        d.each {|metric| @metrics << metric if metric =~ /\./}
      end
    end

    def compose_metric (metric, clusters, hosts)
      self.class.metric_format.dup.gsub('%m', metric).
        gsub('%c', clusters).gsub('%h', hosts)
    end

    def discover_hosts
      hosts = Set.new
      # todo lcs metrics with common substrings to reduce number of graphite
      # queries
      @metrics.map {|m| compose_metric(m, '*', '*')}.each do |u|
        query = "#{expand_url}#{u}"
        results = JSON.parse(open(query).read)['results'].map{|x| x.split('.')}
        f = self.class.metric_format.dup.split('%m')
        first = f.first.split('.')
        last = f.last.split('.')
        ci = hi = nil
        first.each_with_index do |v, i|
          ci = i if v.match('%c')
          hi = i if v.match('%h')
        end
        unless ci && hi
          last.reverse.each_with_index do |v, i|
            ci = (-1) -i if v.match('%c')
            hi = (-1) -i if v.match('%h')
          end
        end
        results.each do |m|
          hosts << [m[hi], ci ? m[ci] : nil]
        end
      end
      hosts.to_a
    end

    def aggregator (str)
      @aggregator = str
    end

    def w (arr)
      arr.size == 1 ? arr.first : "{#{arr.join(',')}}"
    end

    alias inner_properties properties

    # fixme will have to hack a little harder as this isn't thread-safe
    def url_gen (clusters, hosts, prefix, overrides={})
      self.class.instance_eval do
        define_method :properties do
          inner_properties.merge(overrides)
        end
      end
      prefix = prefix + ' ' unless prefix =~ / $/
      replace = @metrics.map do |m|
        [m, "#{@aggregator}(#{compose_metric(m, w(clusters), w(hosts))})"]
      end.uniq
      target_order.each do |t|
        target = targets[t]
        target[:alias] = prefix + target[:alias]
        replace.each {|m, m2| target[:data].gsub!(m, m2)}
      end
      ret = url
      alias properties inner_properties
      target_order.each do |t|
        target = targets[t]
        target[:alias] = target[:alias][prefix.size..-1]
        replace.each {|m, m2| target[:data].gsub!(m2, m)}
      end
      return ret
    end


    def gentitle (*args)
      args.select {|x| x}.join(' / ')
    end

    def render_global (clusters, hosts, overrides={})
      render_url +
        url_gen(clusters, hosts, 'global ', overrides)
    end

    def render_global_zoom (cluster, hosts, dash, overrides={})
      render_url +
        url_gen([cluster], hosts, "#{cluster} ",
                {:title => gentitle(dash, name, cluster)}.merge(overrides))
    end

    def render_cluster (clusters, hosts, overrides={})
      raise "#{clusters.size} != 1" unless clusters.size == 1
      cluster = clusters.first.to_s
      render_url +
        url_gen([cluster], hosts, "#{cluster} ",
                {:title => gentitle(name, cluster)}.merge(overrides))
    end

    def render_cluster_zoom (cluster, hosts, overrides={})
      render_url +
        url_gen([cluster], hosts, "#{cluster} ", overrides)
    end

    def render_host (cluster, host, overrides={})
      label = cluster ? "#{host}/#{cluster} " : "#{host} "
      render_url +
        url_gen([cluster], [host], label,
                {:title => gentitle(name, cluster, host)}.merge(overrides))
    end
  end
end # Pencil::Models
