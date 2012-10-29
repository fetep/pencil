require 'logger'
require 'pathname'
require 'thread'
require 'find'
require 'optparse'
require 'json'
require 'open-uri'
require 'yaml'
require 'set'

require 'pencil/models'
require 'pencil/attime'

module Pencil
  class Config
    include Pencil::Models

    attr_reader :dashboards
    attr_reader :graphs
    attr_reader :hosts
    attr_reader :clusters
    attr_reader :clustermap
    attr_reader :config_file
    attr_reader :version
    attr_reader :port
    attr_reader :argv

    def initialize
      @port = 9292
      @config_file = File.expand_path './pencil.yml'
      @recursive = false
      @logger = Logger.new(STDOUT) # fixme use the sinatra logger
      @argv = ARGV.clone

      optparse = OptionParser.new do |o|
        o.on('-f', '--config-file FILE',
             'location of the config file (default ./pencil.yml)') do |arg|
          @config_file = File.expand_path arg
        end
        o.on('-p', '--port PORT', 'port to bind to (default 9292)') do |arg|
          @port = arg.to_i
        end
      end

      optparse.parse(@argv)
      stage_load
      reload!
    end

    def [] (key)
      @config[key]
    end

    # for views
    class << self
      attr_accessor :klass
    end
    def klass
      self.class.klass ||= Struct.new(:from, :offset, :label, :is_default)
    end

    # fixme handle exceptions in ATTime code
    def gen_view (h)
      if h.is_a? String
        klass.new(h, ATTime.parseTimeOffset(h), nil)
      elsif h.keys.first.to_s == 'default'
        if h.values.first.is_a? String
          klass.new(h.values.first, ATTime.parseTimeOffset(h.values.first), nil, true)
        else
          klass.new(h.values.first.keys.first,
                    ATTime.parseTimeOffset(h.values.first.keys.first),
                    h.values.first.values.first, true)
        end
      else
        klass.new(h.keys.first, ATTime.parseTimeOffset(h.keys.first), h.values.first)
      end
    end

    # fixme re-implement all the config reload stuff
    def stage_load
      defaults = {
        :host_sort => 'sensible',
        :metric_format => '%m.%c.%h',
        :refresh_rate => 60,
        :views =>
        [{'-1h' => 'one hour view'},
         {'default' => {'-8h' => 'eight hour view'}},
         {'-1day' => 'one day view'}]
      }
      unless File.readable?(@config_file) && File.file?(@config_file)
        abort "config file #{@config_file} not found or not readable (-f)"
      end

      yaml = YAML::load_file @config_file
      abort "couldn't parse #{@config_file} as YAML" unless yaml
      @_config = defaults.merge(yaml)

      # do some sanity checking of other configuration parameters
      [:graphite_url, :templates_dir].each do |c|
        if not yaml[c]
          abort "Missing config name ':#{c.to_s}'"
        end
      end
      PencilGraph.graphite_url = yaml[:graphite_url]
      PencilGraph.metric_format = yaml[:metric_format]

      @templates_dir = yaml[:templates_dir]

      if Pathname.new(@templates_dir).relative?
        @templates_dir = File.expand_path @templates_dir
      end

      @templates_dir = @templates_dir[0..-2] if @templates_dir[-1..-1] == '/'

      unless File.readable?(@templates_dir) && File.directory?(@templates_dir)
        abort "templates directory #{@templates_dir} not found or not readable"
      end

      if @_config[:webapp]
        @_config[:webapp] = {} if @_config[:webapp] == true
        unless @_config[:webapp][:manifest]
          @logger.info "no :manifest key for webapp, using default"
          @_config[:webapp][:manifest] = {
            "name" => "Pencil",
            "description" => "Graphite Dashboard Frontend",
            "launch_path" => "/",
            "icons" => {
              "16" => "/favicon.ico"
            },
            "developer" => {
              "name" => "whd@mozilla.com",
              "url" => "https://github.com/fetep/pencil"
            },
            "default_locale" => "en"
          }
        end
      end

      @_config[:views].map! {|h| gen_view(h)}

      default = @_config[:views].select {|x| x.is_default}
      if default.size > 1
        @logger.warn "multiple default timeslices, using first: #{@_config[:views].first.from}"
        default[1..-1].each {|x| x.is_default = false}
      elsif default.size == 0
        @logger.warn "no default timeslice, using first: #{@_config[:views].first.from}"
        @_config[:views].first.is_default = true
      end

      # fixme warn on duplicate names, error checking
      # load graph definitions first
      @_graphs = {}
      @_dashboards = {}
      Dir.glob("#{@templates_dir}/**/*.graph").each do |f|
        g = PencilGraph.new(f, yaml[:default_url_opts])
        @_graphs[g.name] = g
      end
      Dir.glob("#{@templates_dir}/**/*.y{a,}ml").map do |f|
        d = Dashboard.new(f, @templates_dir)
        @_dashboards[d.name] = d
      end

      if yaml[:metric_format] !~ /%m/
        abort 'missing metric (%m) in :metric_format'
      elsif yaml[:metric_format] !~ /%h/
        abort 'missing host (%h) in :metric_format'
      end

      @_hosts = {}
      clusters = SortedSet.new
      clustermap = {} # cluster name => cluster

      # fixme not reload safe
      Host.sort_method = @_config[:host_sort]
      @_graphs.each do |name, graph|
        hosts = graph.discover_hosts
        hosts.each do |hname, cluster|
          name = Host.get_name(hname, cluster)
          @_hosts[name] ||= Host.new(hname, cluster)
          @_hosts[name].graphs << graph.name
          clusters << cluster if cluster
          clustermap[cluster||:global] ||= SortedSet.new
          clustermap[cluster||:global] << @_hosts[name]
        end
      end

      noassoc = {} # cluster => hosts
      @_hosts.each do |name, h|
        h.graphs.sort!
        assoc = false
        @_dashboards.each do |dname, d|
          d.graphs.each do |g, hash|
            hash['hosts'].each do |w|
              if h.match(w)
                d.assoc[g][w] << h
                assoc = true
              end
            end
          end
        end
        unless assoc
          @logger.info "#{h.name} not associated with a dashboard"
          noassoc[h.cluster||:global] ||= SortedSet.new
          noassoc[h.cluster||:global] << h
        end
      end

      @_clusters = []
      if clusters.size == 0
        @_clusters <<
          Cluster.new(nil, clustermap[:global], noassoc[:global], true)
      else
        clusters.each do |c|
          @_clusters << Cluster.new(c, clustermap[c], noassoc[c])
        end
      end
      @_clusters.sort!
    end

    def load_verify_stage
      begin
        # save class variables
        @logger.info 'staging load'
        [PencilGraph, Dashboard, Host].each(&:save)
        [PencilGraph, Dashboard].each(&:clear)
        stage_load
        @logger.info 'staging load succeeded, reloading'
        reload!
      rescue Exception => err
        [PencilGraph, Dashboard, Host].map(&:restore)
        @logger.error "error reloading configuration:\n#{err}"
        @logger.warn "staging load failed, using old configuration #{@version}"
        return false
      end
      return true
    end

    def reload!
      @dashboards, @graphs = @_dashboards, @_graphs
      @hosts, @clusters = @_hosts, @_clusters
      @config = @_config
      @clustermap = @_clustermap
      @_clustermap = @_config = @_dashboards = nil
      @_graphs = @_hosts = @_clusters = nil
      @version = Time.now.to_i
    end

  end # Pencil::Config
end # Pencil
