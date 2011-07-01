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
    def width(opts={})
      opts["width"] || @params[:url_opts][:width]
    end

    # translate STR into graphite-speak for applying FUNC to STR
    # graphite functions take zero or one argument
    # pass passes STR through, instead of raising an error
    def translate(func, str, arg=nil, pass=false)
      # puts "calling translate"
      # puts "func => #{func}"
      # puts "str => #{str}"
      # puts "arg => #{arg}"
      # procs and lambdas don't support default arguments in 1.8, so I have to
      # do this
      z = lambda { |*body| "#{func}(#{body[0]||str})" }
      y = "#{str}, #{arg}"
      x = lambda { z.call(y) }

      return \
      case func.to_s
        # comb
      when "sumSeries", "averageSeries", "minSeries", "maxSeries", "group"
        z.call
        # transform
      when "scale", "offset"
        # perhaps .to_f
        x.call
      when "derivative", "integral"
        z.call
      when "nonNegativeDerivative"
        z.call("#{str}#{', ' + arg if arg}")
      when "log", "timeShift", "summarize", "hitcount",
        # calculate
        "movingAverage", "stdev", "asPercent"
        x.call
      when "diffSeries", "ratio"
        z.call
        # filters
      when "mostDeviant"
        z.call("#{arg}, #{str}")
      when "highestCurrent", "lowestCurrent", "nPercentile", "currentAbove",
        "currentBelow", "highestAverage", "lowestAverage", "averageAbove",
        "averageBelow", "maximumAbove", "maximumBelow"
        x.call
      when "sortByMaxima", "minimalist"
        z.call
      when "limit", "exclude"
        x.call
      when "key"
        "alias(#{str}, \"#{arg}\")"
      when "cumulative"
      when "drawAsInfinite"
        z.call
      when "lineWidth"
        x.call
      when "dashed", "keepLastValue"
        z.call
      when "substr", "threshold"
        x.call
      when "color"
        str #color is handled elsewhere
      else
        raise "BAD FUNC #{func}" unless pass
        str
      end
    end

    # inner means we're dealing with a complex key; @params will be applied
    # later on
    def handle_metric(name, opts, inner=false)
      ret = name.dup
      unless inner
        @params.each do |k, v|
          ret = translate(k, ret, v, true)
        end
      end
      (opts||{}).each do |k, v|
        #puts "#{k} => #{v}"
        ret = translate(k, ret, v)
      end
      ret
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

      url_opts[:from] = url_opts.delete(:stime) || ""
      url_opts[:until] = url_opts.delete(:etime) || ""
      url_opts.delete(:start)
      url_opts.delete(:duration)

      # @params holds the graph-level options
      # url_opts are assumed to be directly passable to graphite... kind of
      if @params["stack"] == true
        url_opts[:areaMode] = "stacked"
      end

      target = []
      colors = []
      if opts[:sum] == :global
        @params["metrics"].each do |stat_name, opts|
          z = opts.dup
          # opts['key'] ||= stat_name
          z[:key] ||= stat_name
          #######################
          if stat_name.instance_of?(Array)
            metric = stat_name.map do |m|
              mm = "#{m.keys.first}.{#{clusters.to_a.join(',')}}" +
                ".{#{hosts.to_a.join(',')}}"
              handle_metric(mm, m[m.keys.first], true)
            end.join(',')
          else
            metric = "#{stat_name}.{#{clusters.to_a.join(',')}}" +
              ".{#{hosts.to_a.join(',')}}"
          end
          #######################
          z[:key] = "global #{z[:key]}"
          target << handle_metric("sumSeries(#{metric})", z)
          colors << next_color(colors, z[:color])
        end # @params["metrics"].each
      elsif opts[:sum] == :cluster # one line per cluster/metric
        clusters.each do |cluster|
          @params["metrics"].each do |stat_name, opts|
            z = opts.dup
            metrics = []
            hosts.each do |host|
              #######################
              if stat_name.instance_of?(Array)
                metrics << stat_name.map do |m|
                  mm = "#{m.keys.first}.#{cluster}.#{host}"
                  handle_metric(mm, m[m.keys.first], true)
                end.join(',')
              else
                metrics << "#{stat_name}.#{cluster}.#{host}"
              end
              #######################
            end # hosts.each

            z[:key] = "#{cluster} #{z[:key]}"
            target << handle_metric("sumSeries(#{metrics.join(',')})", z)
            colors << next_color(colors, z[:color])
          end # metrics.each
        end # clusters.each
      else # one line per {metric,host,colo}
        @params["metrics"].each do |stat_name, opts|
          clusters.each do |cluster|
            hosts.each do |host|
              label = "#{host} #{opts[:key]}"
              #################
              if stat_name.instance_of?(Array)
                metric = stat_name.map do |m|
                  mm = "#{m.keys.first}.#{cluster}.#{host}"
                  handle_metric(mm, m[m.keys.first], true)
                end.join(',')
              else
                metric = "#{stat_name}.#{cluster}.#{host}"
              end
              #################

              if label =~ /\*/
                z = opts.dup
                # fixme proper labeling... maybe
                # With wildcards let graphite construct the legend (or not).
                # Since we're handling wildcards we don't know how many
                # hosts will match, so just put in the default color list.
                # technically we do know, so this can be fixed
                z.delete(:key)
                target << handle_metric(metric, z)
                colors.concat(@params[:default_colors]) if colors.empty?
              else
                z = opts.dup
                #puts opts[:key]
                z[:key] = "#{host}/#{cluster} #{opts[:key]}"
                target << handle_metric(metric, z)
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
        query = open("#{url}#{metric.first.first}.*.*").read
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
