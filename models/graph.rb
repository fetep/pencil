require "models/base"
require "uri"

module Dash::Models
  class Graph < Base
    def initialize(name, params={})
      super

      @params["hosts"] ||= ["*"]
      @params["title"] ||= name

      if not @params["metrics"]
        raise ArgumentError, "graph #{name} needs a 'metrics' map"
      end
    end

    # fixme parameters in general
    def width (opts={})
      opts["width"] || @params[:url_opts][:width]
    end

    def render_url(hosts, clusters, opts={})
      opts = {
        :sum => nil,
        :title => @params["title"],
      }.merge(opts)


      if ! [:global, :cluster, nil].member?(opts[:sum])
        raise ArgumentError, "render graph #{name}: invalid :sum - #{opts[:sum]}"
      end

      sym_hash = {}
      (opts[:dynamic_url_opts]||[]).each do |k,v|
        sym_hash[k.to_sym] = v
      end

      #fixme key checking may be necessary
      url_opts = {
        :title => opts[:title],
      }.merge(@params[:url_opts]).merge(sym_hash)

      if start = Chronic.parse(url_opts.delete(:start))
        url_opts[:from] = start.strftime("%s")
      else
        #we don't really care what gets output; it's wrong
        url_opts[:from] = ""
      end

      duration = url_opts.delete(:duration)
      if duration && seconds = ChronicDuration.parse(duration)
        url_opts[:until] = url_opts[:from].to_i + seconds.to_i
      end

      if @params["stack"] == true
        url_opts[:areaMode] = "stacked"
      end

      target = []
      colors = []
      if opts[:sum] == :global
        @params["metrics"].each do |stat_name, opts|
          opts['key'] ||= stat_name
          metric = "#{stat_name}.{#{clusters.to_a.join(',')}}" +
            ".{#{hosts.to_a.join(',')}}"

          label = "global #{opts[:key]}"
          target << "alias(" +
            _target("sumSeries(#{metric})") + ", #{label.inspect})"
          colors << next_color(colors, opts[:color])
        end # @params["metrics"].each
      elsif opts[:sum] == :cluster # one line per cluster/metric
        clusters.each do |cluster|
          @params["metrics"].each do |stat_name, opts|
            metrics = []
            hosts.each do |host|
              metrics << "#{stat_name}.#{cluster}.#{host}"
            end # hosts.each

            label = "#{cluster} #{opts[:key]}"
            target << "alias(" +
                      _target("sumSeries(" + metrics.join(",") + ")") +
                      ", #{label.inspect})"
            colors << next_color(colors, opts[:color])
          end # metrics.each
        end # clusters.each
      else # one line per {metric,host,colo}
        @params["metrics"].each do |stat_name, opts|
          clusters.each do |cluster|
            hosts.each do |host|
              label = "#{host} #{opts[:key]}"
              metric = _target("#{stat_name}.#{cluster}.#{host}")
              if label =~ /\*/
                # fixme proper labeling... maybe
                # With wildcards let graphite contruct the legend (or not).
                # Since we're handling wildcards we don't know how many
                # hosts will match, so just put in the default color list.
                target << metric
                colors.concat(@params[:default_colors]) if colors.empty?
              else
                target << "alias(#{metric}, \"#{host}/#{cluster} #{label}\")"
                colors << next_color(colors, opts[:color])
              end
            end
          end
        end # @params["metrics"].each
      end # if opts[:sum]

      url_opts[:target] = target
      url_opts[:colorList] = colors.join(",")

      url = URI.join(@params[:graphite_url], "/render/?").to_s
      url_parts = []
      url_opts.each do |k, v|
        [v].flatten.each do |v|
          url_parts << "#{URI.escape(k.to_s)}=#{URI.escape(v.to_s)}"
        end
      end
      url += url_parts.join("&")
      return url
    end

    # return an array of all metrics matching the specifications in
    # @params['metrics']
    # metrics are arrays of fields (once delimited by periods)
    def expand
      url = URI.join(@params[:graphite_url], "/metrics/expand/?query=").to_s
      metrics = []

      @params['metrics'].each do |metric|
        query = open("#{url}#{metric.first}.*.*").read
        metrics << JSON.parse(query)['results']
      end

      return metrics.flatten.map { |x| x.split('.') }
    end

    def hosts_clusters
      metrics = expand
      clusters = Set.new

      # field -1 is the host name, and -2 is its cluster
      hosts = metrics.map do |x|
        Host.new(x[-1], @params.merge({ 'cluster' => x[-2] }))
      end.uniq

      # filter by what matches the graph definition
      hosts = hosts.select { |h| h.multi_match(@params['hosts']) }
      hosts.each { |h| clusters << h.cluster }

      return hosts, clusters
    end

    private
    def _target(target)
      res = target.dup
      if @params["scale"]
        res = "scale(#{res}, #{@params["scale"].to_f})"
      end
      return res
    end

    private
    def next_color(colors, preferred_color=nil)
      default_colors = @params[:default_colors].clone

      if preferred_color and !colors.member?(preferred_color)
        return preferred_color
      end

      if preferred_color and ! default_colors.member?(preferred_color)
        default_colors << preferred_color
      end

      weights = Hash.new { |h, k| h[k] = 0 }
      colors.each do |c|
        weights[c] += 1
      end

      i = 0
      loop do
        default_colors.each do |c|
          return c if weights[c] == i
        end
        i += 1
      end
    end
  end # Dash::Models::Graph
end # Dash::Models
