require "pencil/models/base"
require "uri"

module Pencil
  module Models
    class Graph < Base
      def initialize(name, params={})
        super

        @params["hosts"] ||= ["*"]
        @params["title"] ||= name

        if not @params["targets"]
          raise ArgumentError, "graph #{name} needs a 'targets' map"
        end
      end

      def width(opts={})
        opts["width"] || @params[:url_opts][:width]
      end

      # translate STR into graphite-speak for applying FUNC to STR
      # graphite functions take zero or one argument
      # pass passes STR through, instead of raising an error if FUNC isn't
      # recognized
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
        when "diffSeries", "divideSeries"
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
        when "key", "alias"
          "alias(#{str}, \"#{arg}\")"
        when "cumulative", "drawAsInfinite"
          z.call
        when "lineWidth"
          x.call
        when "dashed", "keepLastValue"
          z.call
        when "substr", "threshold"
          x.call
        when "color"
          @params[:use_color] ? "color(#{str}, \"#{arg}\")" : str
        else
          raise "BAD FUNC #{func}" unless pass
          str
        end
      end

      # FIXME Map().keys => Array of strings
      # inner means we're dealing with a complex key; @params will be applied
      # make sure to apply alias and color arguments last, if applicable
      def handle_metric(name, opts, inner=false)
        later = []
        ret = name.dup
        if inner
          @params.each do |k, v|
            ret = translate(k, ret, v, true)
          end
        end
        (opts||{}).each do |k, v|
          if k == "color" || k == "key"
            later << [k, v]
          else
            ret = translate(k, ret, v)
          end
        end
        later.each do |k, v|
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

        # FIXME actually use Maps for everything initially instead of this crap
        url_opts = Map({
          :title => opts[:title],
        }).merge(Map(@params[:url_opts])).merge(Map(opts[:dynamic_url_opts]))

        url_opts[:from] = url_opts.delete(:stime) || ""
        url_opts[:until] = url_opts.delete(:etime) || ""
        url_opts.delete(:start)
        url_opts.delete(:duration)

        graphite_opts = [ "vtitle", "yMin", "yMax", "lineWidth", "areaMode",
          "template", "lineMode", "bgcolor", "graphOnly", "hideAxes", "hideGrid",
          "hideLegend", "fgcolor", "fontSize", "fontName", "fontItalic",
          "fontBold", "logBase" ]

        @params.each do |k, v|
          if graphite_opts.member?(k)
            url_opts[k.to_sym] = v
          end
        end

        target = []
        colors = []
        #FIXME code duplication
        if opts[:sum] == :global
          @params["targets"].each do |stat_name, o|
            z = new_map(o)

            z[:key] ||= stat_name
            #######################
            if stat_name.instance_of?(Array)
              metric = stat_name.map do |m|
                mm = compose_metric(m.keys.first,
                             "{#{clusters.to_a.join(',')}}",
                             "{#{hosts.to_a.join(',')}}")

                if z.keys.member?("divideSeries")
                  handle_metric(translate(:sumSeries, mm),
                         m[m.keys.first], true)
                else
                  handle_metric(mm, m[m.keys.first], true)
                end
              end.join(",")
            else
              metric = compose_metric(stat_name,
                               "{#{clusters.to_a.join(',')}}",
                               "{#{hosts.to_a.join(',')}}")
              metric = handle_metric(metric, {}, true)
            end
            #######################
            z[:key] = "global #{z[:key]}"
            # target << handle_metric(translate(:sumSeries, metric), z)

            if z.keys.member?('divideSeries') # special case
              # apply divideSeries, sumSeries then other options
              res = translate(:divideSeries, metric)
              res = translate(:sumSeries, res)
              z.delete(:divideSeries)
              h = YAML::Omap.new
              z.each { |k,v| h[k] = v unless k == 'divideSeries' }
              target << handle_metric(res, h)
            else
              target << handle_metric(translate(:sumSeries, metric), z)
            end
            if !@params[:use_color] ||
                (!z[:color] && @params[:use_color])
              colors << next_color(colors, z[:color])
            end
          end # @params["targets"].each
        elsif opts[:sum] == :cluster # one line per cluster/metric
          clusters.each do |cluster|
            @params["targets"].each do |stat_name, o|
              z = new_map(o)

              metrics = []
              #######################
              h = "{#{hosts.to_a.join(',')}}"
              if stat_name.instance_of?(Array)
                metrics << stat_name.map do |m|
                  mm = compose_metric(m.keys.first, cluster, h)
                  # note: we take the ratio of the sums in this case, instead of
                  # the sums of the ratios
                  if z.keys.member?('divideSeries')
                    # divideSeries is picky about the number of series given as
                    # arguments, so sum them in this case
                    handle_metric(translate(:sumSeries, mm),
                                  m[m.keys.first], true)
                  else
                    handle_metric(mm, m[m.keys.first], true)
                  end
                end.join(",")
              else
                metrics << handle_metric(compose_metric(stat_name,
                                                        cluster, h), {}, true)
              end
              #######################
              z[:key] = "#{cluster} #{z[:key]}"

              if z.keys.member?('divideSeries') # special case
                # apply divideSeries, sumSeries then other options
                res = translate(:divideSeries, metrics.join(','))
                res = translate(:sumSeries, res)
                z.delete(:divideSeries)
                h = Map.new
                z.each { |k,v| h[k] = v unless k == 'divideSeries' }
                target << handle_metric(res, h)
              else
                target << handle_metric(translate(:sumSeries,
                                                  metrics.join(',')), z)
              end

              if !@params[:use_color] || (!z[:color] && @params[:use_color])
                colors << next_color(colors, z[:color])
              end
            end # metrics.each
          end # clusters.each
        else # one line per {metric,host,colo}
          @params["targets"].each do |stat_name, o|
            z = new_map(o)
            clusters.each do |cluster|
              hosts.each do |host|
                label = "#{host} #{z[:key]}"
                #################
                if stat_name.instance_of?(Array)
                  metric = stat_name.map do |m|
                    mm = compose_metric(m.keys.first, cluster, host)
                    handle_metric(mm, m[m.keys.first], true)
                  end.join(",")
                else
                  metric = handle_metric(compose_metric(stat_name, cluster, host), {}, true)
                end
                #################

                if label =~ /\*/
                  # for this particular type of graph, don't display a legend,
                  # and color with abandon
                  url_opts[:hideLegend] = true

                  z.delete(:color)
                  # fixme proper labeling... maybe
                  # With wildcards let graphite construct the legend (or not).
                  # Since we're handling wildcards we don't know how many
                  # hosts will match, so just put in the default color list.
                  # technically we do know, so this can be fixed
                  z.delete(:key)
                  target << handle_metric(metric, z)
                  colors.concat(@params[:default_colors]) if colors.empty?
                else
                  z[:key] = "#{host}/#{cluster} #{z[:key]}"
                  target << handle_metric(metric, z)
                  if !@params[:use_color] ||
                    (!z[:color] && @params[:use_color])
                    colors << next_color(colors, z[:color])
                  end
                end
              end
            end
          end # @params["targets"].each
        end # if opts[:sum]

        url_opts[:target] = target
        url_opts[:colorList] = colors.join(",")

        url = URI.join(@params[:graphite_url], "/render/?").to_s
        url_parts = []
        url_opts.each do |k, v|
          [v].flatten.each do |v2|
            url_parts << "#{URI.escape(k.to_s)}=#{URI.escape(v2.to_s)}"
          end
        end
        url += url_parts.join("&amp;")
        return url
      end

      # return an array of all metrics matching the specifications in
      # @params["targets"]
      # metrics are arrays of fields (once delimited by periods)
      def expand
        url = URI.join(@params[:graphite_url], "/metrics/expand/?query=").to_s
        metrics = []

        require "json"
        @params["targets"].each do |k, v|
          # temporary hack for Map class complaining block parameters
          metric = [k, v]
          unless metric.first.instance_of?(Array)
            # wrap it
            metric[0] = [{metric[0] => nil}]
          end
          metric.first.each do |m|
            composed = compose_metric(m.first.first, "*", "*")
            composed2 = compose_metric2(m.first.first, "*", "*")
            query = open("#{url}#{composed}").read
            query2 = open("#{url}#{composed2}").read
            results = JSON.parse(query)["results"]
            results2 = JSON.parse(query2)["results"].map {|x| x.split('.')[0..-2].join('.')}
            metrics << results - results2
          end
        end

        return metrics.flatten.map { |x| x.split(".") }
      end

      def hosts_clusters
        metrics = expand
        clusters = Set.new

        # find the indicies of the clusters and hosts
        f = @params[:metric_format].dup.split("%m")
        first = f.first.split(".")
        last = f.last.split(".")
        ci = hi = nil
        first.each_with_index do |v, i|
          ci = i if v.match("%c")
          hi = i if v.match("%h")
        end
        unless ci && hi
          last.reverse.each_with_index do |v, i|
            ci = (-1) -i if v.match("%c")
            hi = (-1) -i if v.match("%h")
          end
        end
        hosts = metrics.map do |m|
          Host.new(m[hi], m[ci], @params)
        end.uniq

        # filter by what matches the graph definition
        hosts = hosts.select { |h| h.multi_match(@params["hosts"]) }
        hosts.each { |h| clusters << h.cluster }

        return hosts, clusters
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

        weights = Hash.new(0)
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

      # if Map() in config.rb converted a YAML::Omap into an array, we
      # need to turn it back into a Map (which is ordered, conveniently)
      def new_map (opts)
        if opts.is_a?(Array)
          z = Map(opts.flatten)
        else
          z = Map(opts)
        end
      end
    end # Dash::Models::Graph
  end
end # Pencil::Models
