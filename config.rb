require "rubygems"
require "models"

module Dash
  class Config
    include Dash::Models

    attr_reader :dashboards
    attr_reader :graphs
    attr_reader :global_config

    def initialize
      @confdir = File.join(File.dirname(__FILE__), "conf")
      @graphs = {}
      @dashboards = {}
      @rawconfig = {}
      @global_config = {}

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
      [:graphite_url].each do |c|
        if not @global_config[c]
          raise "Missing config name '#{c.to_s}'"
        end
      end

      # possibly check url_opts here as well

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

      @dashboards, @graphs= dashboards_new, graphs_new
    end
  end # Dash::Config
end # Dash
