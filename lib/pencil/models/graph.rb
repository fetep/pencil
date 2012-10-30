require 'pencil/models/base'
require 'graphite_graph'
require 'thread'

module Pencil::Models
  class PencilGraph < GraphiteGraph
    # This class consists of some pretty bad hacks to the GraphiteGraph that will
    # make it work with a system like Pencil's. Stare too long at this and your
    # eyes may bleed (though not as much as the old YAML-based configs did).
    attr_reader :name, :metrics

    class << self
      # fixme modulify
      ATTRS = [:graphite_url, :metric_format, :render_url, :expand_url]
      attr_accessor(*ATTRS)
      # fixme module
      def save
        ATTRS.each do |a|
          val = instance_variable_get("@#{a}")
          instance_variable_set("@_#{a}", val)
        end
      end
      def restore
        ATTRS.each do |a|
          val = instance_variable_get("@_#{a}")
          instance_variable_set("@#{a}", val)
        end
      end
      def clear
        @render_url = nil
        @expand_url = nil
      end
    end

    METRIC_REGEXP = /[^(),]+/

    def render_url
      self.class.render_url ||=
        "#{URI.join(self.class.graphite_url, '/render/?')}"
    end
    def expand_url
      self.class.expand_url ||=
        "#{URI.join(self.class.graphite_url, '/metrics/expand/?leavesOnly=1&query=')}"
    end

    def initialize(file, overrides={}, info={})
      super(file, overrides, info)
      @name = File.basename(@file.chomp('.graph'))
      @aggregator ||= 'sumSeries'
      @lock = Mutex.new
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
        results = JSON::parse(open(query).read)['results'].map{|x| x.split('.')}
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

    # The graphite DSL supports parameterization, but only at
    # instantiation. Since we want to parameterize at the call to url()
    # (depending on the view), this hack exists. Probably the correct way with
    # the API to handle this is to generate as many graphs as views,
    # but that is impractical since there are hundreds of them.
    # Each graph must be kept exclusive while the properties method is
    # redefined (when url_gen() is called).
    def url_gen (clusters, hosts, prefix, overrides={})
      @lock.lock
      clusters = [] if clusters.size == 1 && clusters.first.is_a?(Cluster)

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
      @lock.unlock
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
        url_gen(cluster ? [cluster]: [], [host], label,
                {:title => gentitle(name, cluster, host)}.merge(overrides))
    end
  end
end # Pencil::Models
