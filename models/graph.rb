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

    def render_url(hosts, clusters, opts={})
      opts = {
        :sum => nil,
        :title => @params["title"],
      }.merge(opts)


      if ! [:global, :cluster, nil].member?(opts[:sum])
        raise ArgumentError, "render graph #{name}: invalid :sum - #{opts[:sum]}"
      end

      # fixme make these configurable
      url_opts = {
        :width => 1000,
        :height => 400,
        :from => "-2hours",  # TODO: better timepsec handling
        :title => opts[:title],
        :template => "noc",
        :fontSize => 12,
        :yMin => 0,
        :margin => 5,
        :thickness => 2,
      }

      if @params["stack"] == true
        url_opts[:areaMode] = "stacked"
      end

      target = []
      colors = []
      if opts[:sum] == :global # one line per metric
        @params["metrics"].each do |stat_name, opts|
          opts['key'] ||= stat_name
          metrics = []
          clusters.each do |cluster|
            hosts.each do |host|
              metrics << "#{stat_name}.#{cluster}.#{host}"
            end
          end

          if metrics.length > 0
            label = "global #{opts[:key]}"
            target << "alias(" +
                     _target("sumSeries(" + metrics.join(",") + ")") +
                     ", #{label.inspect})"
            colors << next_color(colors, opts[:color])
          end
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
              target << "alias(#{metric}, \"#{host}/#{cluster} #{label}\")"
              colors << next_color(colors, opts[:color])
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
