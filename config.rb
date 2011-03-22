require "rubygems"
require "json"
require "models"

module Dash
  class Config
    include Dash::Models

    attr_reader :dashboards
    attr_reader :graphs
    attr_reader :hosts

    def initialize
      @confdir = File.join(File.dirname(__FILE__), "conf")
      @graphs = {}
      @hosts = {}
      @dashboards = {}
      @rawconfig = {}

      reload!
    end

    def config(name, value)
      @rawconfig[name] = value
    end

    def reload!
      configs = Dir.glob("#{@confdir}/*.rb")
      configs.each { |c| eval(File.read(c)) }

      [:graphs, :hosts, :dashboards].each do |c|
        if not @rawconfig[c]
          raise "Missing config name '#{c.to_s}'"
        end
      end

      graphs_new = []
      @rawconfig[:graphs].each do |name, config|
        graphs_new << Graph.new(name, config)
      end

      hosts_new = []
      @rawconfig[:hosts].each do |name, config|
        hosts_new << Host.new(name, config)
      end

      dashboards_new = []
      @rawconfig[:dashboards].each do |name, config|
        dashboards_new << Dashboard.new(name, config)
      end

      @dashboards, @graphs, @hosts = dashboards_new, graphs_new, hosts_new
    end
  end # Dash::Config
end # Dash
