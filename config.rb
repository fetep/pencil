require "rubygems"
require "models"

module Dash
  class Config
    include Dash::Models

    attr_reader :dashboards
    attr_reader :graphs
    attr_reader :hosts
    attr_reader :clusters
    attr_reader :global_config

    def initialize
      @confdir = File.join(File.dirname(__FILE__), "conf")
      @rawconfig = {}
      reload!
    end

    def reload!
      configs = Dir.glob("#{@confdir}/*.yml")
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
        if @global_config[:url_opts][:start]
          if !ChronicDuration.parse(@global_config[:url_opts][:start])
            raise "bad default timespec in :url_opts"
          end
        end
      end

      @global_config[:default_colors] ||=
        ["blue", "green", "yellow", "red", "purple", "brown", "aqua", "gold"]

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
  end # Dash::Config
end # Dash
