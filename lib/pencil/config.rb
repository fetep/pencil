require 'map'
require 'pencil/models'
require 'logger'
require 'pathname'
require 'thread'
require 'find'

module Pencil
  class Config
    include Pencil::Models

    attr_reader :dashboards
    attr_reader :graphs
    attr_reader :hosts
    attr_reader :clusters
    attr_reader :global_config
    attr_reader :confdir
    attr_reader :lock
    attr_reader :version
    attr_reader :autoreload, :poll_interval
    attr_accessor :mtime, :mtime_d
    attr_accessor :reload_available, :reload_pending

    def initialize
      port = 9292
      @rawconfig = {}
      @confdir = "."
      @recursive = false
      @reload_available = false
      @reload_pending = false
      # mapping of config files to mtimes
      @mtime = {}
      @mtime_d = {}
      @lock = Mutex.new
      @autoreload = false
      @poll_thread_active = false
      @logger = Logger.new(STDOUT) # fixme use the sinatra logger

      optparse = OptionParser.new do |o|
        o.on("-d", "--config-dir DIR",
             "location of the config directory (default .)") do |arg|
          @confdir = arg
          @recursive = true
        end
        o.on("-p", "--port PORT", "port to bind to (default 9292)") do |arg|
          port = arg.to_i
        end
      end

      optparse.parse!
      poll
      stage_load
      reload!

      @global_config[:port] = port
    end

    # check the config directory for changes
    def poll
      trigger = false
      #fixme remove stale entries
      Find.find(@confdir) do |f|
        if File.directory? f
          if !@mtime_d[f] || (@mtime_d[f] && File.mtime(f) != @mtime_d[f])
            @mtime_d[f] = File.mtime(f)
            trigger = true
          end
        elsif filetest f
          if !@mtime[f] || (@mtime[f] && File.mtime(f) != @mtime[f])
            @mtime[f] = File.mtime(f)
            trigger = true
          end
        end
      end
      return trigger
    end

    def filetest (f)
      File.file?(f) && f =~ /\.ya?ml$/
    end

    def stage_load
      @rawconfig = {}
      # only do a recursive search if "-d" is specified
      configs = Dir.glob("#{@confdir}/#{@recursive ? '**/' : ''}*.y{a,}ml")

      configs.each do |c|
        yml = YAML.load(File.read(c))
        next unless yml
        @rawconfig[:config] = yml[:config] if yml[:config]
        a = @rawconfig[:dashboards]
        b = yml[:dashboards]
        c = @rawconfig[:graphs]
        d = yml[:graphs]

        if a && b
          a.merge!(b)
        elsif b
          @rawconfig[:dashboards] = b
        end
        if c && d
          c.merge!(d)
        elsif d
          @rawconfig[:graphs] = d
        end
      end
      @rawconfig = Map(@rawconfig)

      [:graphs, :dashboards, :config].each do |c|
        if not @rawconfig[c.to_s]
          raise "Missing config name '#{c.to_s}'"
        end
      end

      @_global_config = @rawconfig[:config]
      # do some sanity checking of other configuration parameters
      [:graphite_url, :url_opts].each do |c|
        if not @_global_config[c]
          raise "Missing config name '#{c.to_s}'"
        end
      end

      @_autoreload = @_global_config[:autoreload] || false
      @_poll_interval = @_global_config[:poll_interval] || 300

      # possibly check more url_opts here as well
      if @_global_config[:url_opts][:start]
        if !ChronicDuration.parse(@_global_config[:url_opts][:start])
          raise "bad default timespec in :url_opts"
        end
      end

      @_global_config[:default_colors] ||=
        ["blue", "green", "yellow", "red", "purple", "brown", "aqua", "gold"]

      if @_global_config[:refresh_rate]
        duration = ChronicDuration.parse(@_global_config[:refresh_rate].to_s)
        if !duration
          raise "couldn't parse key :refresh_rate"
        end
        @_global_config[:refresh_rate] = duration
      end

      @_global_config[:metric_format] ||= "%m.%c.%h"
      if @_global_config[:metric_format] !~ /%m/
        raise "missing metric (%m) in :metric_format"
      elsif @_global_config[:metric_format] !~ /%c/
        raise "missing cluster (%c) in :metric_format"
      elsif @_global_config[:metric_format] !~ /%h/
        raise "missing host (%h) in :metric_format"
      end

      graphs_new = []
      @rawconfig[:graphs].each do |name, config|
        graphs_new << Graph.new(name, config.merge(@_global_config))
      end

      dashboards_new = []
      @rawconfig[:dashboards].each do |name, config|
        dashboards_new << Dashboard.new(name, config.merge(@_global_config))
      end

      hosts_new = Set.new
      clusters_new = Set.new

      # generate host and cluster information at init time
      graphs_new.each do |g|
        hosts, clusters = g.hosts_clusters
        hosts.each { |h| hosts_new << h }
        clusters.each { |h| clusters_new << h }
      end

      @_dashboards, @_graphs = dashboards_new, graphs_new
      @_hosts, @_clusters = hosts_new, clusters_new
    end

    def load_verify_stage
      begin
        @logger.info "staging load"
        stage_load
        @logger.info "staging load succeeded"
        @logger.info "the next request will load configuration #{@version}"
      rescue Exception => err
        @logger.error "error reloading configuration:\n#{err}"
        @logger.warn "staging load failed, using old configuration #{@version}"
        return false
      end
      return true
    end

    def reload!
      @poll_interval = @_poll_interval
      @autoreload = @_autoreload
      spawn_polling_thread if @autoreload && !@poll_thread_active
      @dashboards, @graphs = @_dashboards, @_graphs
      @hosts, @clusters = @_hosts, @_clusters
      @global_config = @_global_config
      @_global_config = @_dashboards = @_graphs = @_hosts = @_clusters = nil
      @version = Time.now.to_i
    end

    def trigger_restart
      poll
      @lock.lock
      if @reload_pending || @reload_available
        @lock.unlock
      else
        @reload_pending = true
        @lock.unlock
        @logger.info "scheduling a config reload for #{Time.now + 10}"
        Thread.new do
          begin
            sleep 10
            available = load_verify_stage # new structures loaded and valid
            @lock.lock
            @reload_available = available
            @reload_pending = false
            @lock.unlock
          rescue Exception => err
            @logger.error err
          end
        end
      end
    end

    # TODO delay execution of trigger thread every time a config file changes
    # FIXME with Mongrel, when the application exits, if this thread was
    # spawned within a request context the server believes it is serving a
    # request and waits indefinitely for it to finish, even though its parent
    # thread served the request. This will only happen if the :autoreload
    # parameter is changed from false to true during a config change, an
    # unlikely event.
    def spawn_polling_thread
      @logger.info "spawning polling thread"
      @poll_thread_active = true
      Thread.new do
        while true
          break unless @autoreload
          begin
            trigger_restart if poll
            sleep @poll_interval
          rescue Exception => err
            @logger.error err
          end
        end
        @logger.info "polling thread finished"
        @poll_thread_active = false
      end
    end

  end # Pencil::Config
end # Pencil
