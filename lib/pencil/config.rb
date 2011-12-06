require "pencil/models"

module Pencil
  class Config
    include Pencil::Models

    attr_reader :dashboards
    attr_reader :graphs
    attr_reader :hosts
    attr_reader :clusters
    attr_reader :global_config

    def initialize
      port = 9292
      @rawconfig = {}
      @confdir = "."

      optparse = OptionParser.new do |o|
        o.on("-d", "--config-dir DIR",
          "location of the config directory (default .)") do |arg|
          @confdir = arg
        end
        o.on("-p", "--port PORT", "port to bind to (default 9292)") do |arg|
          port = arg.to_i
        end
      end

      optparse.parse!
      reload!
      @global_config[:port] = port
    end

    def reload!
      configs = Dir.glob("#{@confdir}/*.y{a,}ml")
      configs.each { |c| @rawconfig.merge!(YAML.load(File.read(c))) }

      [:graphs, :dashboards, :config].each do |c|
        if not @rawconfig[c]
          raise "Missing config name '#{c.to_s}'"
        end
      end

      @global_config = @rawconfig[:config]
      # do some sanity checking of other configuration parameters
      [:graphite_url, :url_opts].each do |c|
        if not @global_config[c]
          raise "Missing config name '#{c.to_s}'"
        end
      end

      # possibly check more url_opts here as well
      if @global_config[:url_opts][:start]
        if !ChronicDuration.parse(@global_config[:url_opts][:start])
          raise "bad default timespec in :url_opts"
        end
      end

      @global_config[:default_colors] ||=
        ["blue", "green", "yellow", "red", "purple", "brown", "aqua", "gold"]

      if @global_config[:refresh_rate]
        duration = ChronicDuration.parse(@global_config[:refresh_rate].to_s)
        if !duration
          raise "couldn't parse key :refresh_rate"
        end
        @global_config[:refresh_rate] = duration
      end

      @global_config[:metric_format] ||= "%m.%c.%h"
      if @global_config[:metric_format] !~ /%m/
        raise "missing metric (%m) in :metric_format"
      elsif @global_config[:metric_format] !~ /%c/
        raise "missing cluster (%c) in :metric_format"
      elsif @global_config[:metric_format] !~ /%h/
        raise "missing host (%h) in :metric_format"
      end

      graphs_new = []
      @rawconfig[:graphs].each do |name, config|
        graphs_new << Graph.new(name, config.merge(@global_config))
      end

      dashboards_new = []
      @rawconfig[:dashboards].each do |name, config|
        dashboards_new << Dashboard.new(name, config.merge(@global_config))
      end

      hosts_new = Set.new
      clusters_new = Set.new

      # generate host and cluster information at init time
      graphs_new.each do |g|
        hosts, clusters = g.hosts_clusters
        hosts.each { |h| hosts_new << h }
        clusters.each { |h| clusters_new << h }
      end

      @dashboards, @graphs = dashboards_new, graphs_new
      @hosts, @clusters = hosts_new, clusters_new
    end
  end # Pencil::Config
end # Pencil
