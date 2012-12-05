#!/usr/bin/env ruby
###############################################################################
# convert_configs: generate configuration in the new format
###############################################################################

require 'logger'
require 'pp'
require 'yaml'
require 'chronic'
require 'optparse'
require 'erb'

l = Logger.new(STDOUT)
l.formatter = proc do |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
end

begin
  require 'graphite_graph'
rescue LoadError
  l.error 'Pencil 0.4+ requires the graphite_graph library.
  Try again after "gem install graphite_graph" o.s.'
  exit 1
end

begin
  require 'map'
rescue LoadError
  l.error 'This script requires the map gem as Pencil 0.3* did.
  Try again after "gem install map" o.s.'
  exit 1
end

# convert a pencil graph definition to the graphite dsl
class Graph
  def initialize(name, params={})
    @params = params
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
    # procs and lambdas don't support default arguments in 1.8, so I have to
    # do this
    z = lambda { |*body| "#{func}(#{body[0]||str})" }
    y = "#{str}, #{arg}"
    x = lambda { z.call(y) }

    changed = {
      'scale' => :scale,
      'derivative' => :derivative,
      'nonNegativeDerivative' => :non_negative_derivative,
      'log' => :logbase,
      'movingAverage' => :smoothing,
      'asPercent' => :as_percent,
      'highestAverage' => :highest_average,
      'alias' => :alias,
      'key' => :alias,
      'drawAsInfinite' => :line,
      'lineWidth' => :linewidth,
      'dashed' => :dashed,
      'keepLastValue' => :keep_last_value,
      'color' => :color
    }

    if changed[func]
      #puts ":#{changed[func]} => #{(arg||'true').inspect}"
      @field_data << ":#{changed[func]} => #{(arg||'true').inspect}"
      return str
    end

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

    url_opts = Map({
                     :title => opts[:title],
                   }).merge(Map(@params[:url_opts])).merge(Map(opts[:dynamic_url_opts]))

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

    @params["targets"].each do |stat_name, o|
      @field_data = []
      z = new_map(o)
      clusters.each do |cluster|
        hosts.each do |host|
          if stat_name.instance_of?(Array)
            metric = stat_name.map do |m|
              mm = m.keys.first
              handle_metric(mm, m[m.keys.first], true)
            end.join(",")
          else
            metric = handle_metric(stat_name, {}, true)
          end
          h = handle_metric(metric, z)
          @field_data << ":data => #{h.inspect}"
          target << [h.gsub(/[\.\(\),\+:]/, '_').gsub(/^_+/, '').gsub(/_+$/, ''), @field_data.uniq]
        end
      end
    end # @params["targets"].each

    return target, url_opts
  end

  def new_map (opts)
    if opts.is_a?(Array)
      z = Map(opts.flatten)
    else
      z = Map(opts)
    end
  end
end # Dash::Models::Graph

class App
  def initialize(logger)
    @l = logger
    @dry_run = false
    @dir = Dir.pwd
    @rawconfig = {}
    @rawconfig = {}
    @dashboards = []
    @graphs = []
    @errors = []

    @name_change = {
      :areaMode => :area,
      :bgcolor => :background_color,
      :hideGrid => :hide_grid,
      :hideLegend => :hide_legend,
      :fgcolor => :foreground_color,
      :title => :title,
      :vtitle => :vtitle,
      :yMin => :ymin,
      :yMax => :ymax,
      :fontSize => :fontsize,
      :fontBold => :fontbold,
      :fontName => :fontname,
    }
  end

  def run
    optparse = OptionParser.new do |o|
      o.on("-n", "--dry-run",
           "don't commit new config to disk (#{Dir.pwd})") do
        @dry_run = true
      end
      o.on("-d", "--config-dir DIR", "config directory to act upon") do |arg|
        @dir = arg
      end
      o.on_tail("-h", "--help", "Show this message") do
        puts o
        puts
        puts "After running this script, the new configuration file should reside at:\n
    #{Dir.pwd}/pencil.yml.new\n
and templates in:\n
    #{Dir.pwd}/templates_new\n\n"
        exit
      end
    end
    optparse.parse!

    if !@dry_run
      if File.exist?('templates_new')
        l.error 'templates_new dir already exists, remove and try again'
        exit 2
      end
      if File.exist?('pencil.yml.new')
        l.error 'new config pencil.yml.new already exists, remove and try again'
        exit 3
      end
    end

    load_configs
    y2y
    y2d
    puts
    y2g

    if !@dry_run
      @l.info "committing to disk..."
      @l.info "making directory templates_new"
      Dir.mkdir('templates_new')
      @l.info "making directory templates_new/graphs"
      Dir.mkdir('templates_new/graphs')
      y2y_commit
      y2d_commit
      y2g_commit
      puts

      t = "\n*NOTE*: You may need to tweak your graph definitions in some cases as
        this script doesn't ensure that the new graph definitions correspond
        completely to the old ones (it certainly tries though).\n
Next steps:\n
  You should probably group your dashboards by moving them from templates_new/*.yml
  to subdirectories with the group name like templates_new/service[12]/*.yml.\n
  You may also want to group your graph files with their associated dashboards
  by putting them in the same subdirectories (not required).\n
  You can also add description fields to your graphs and dashboards that will
  show up in the UI.\n
Raise an issue at https://github.com/fetep/pencil if this script doesn't work for you."

      if @errors.size == 0
        @l.info "Great success! Try the new config with pencil -f ./pencil.yml.new before replacing your old ones."
        puts t
      else
        @l.warn 'Run completed with some errors.'
        @l.warn 'The following graph definitions had problems:'
        pp @errors
        @l.info "You'll need to edit them manually before pencil will start successfully."
        puts t
      end
    else
      if @errors.size > 0
        @l.warn 'Dry run completed with some errors.'
        @l.warn 'The following graph definitions had problems:'
        pp @errors
        @l.info "You can still generate these graphs, but you'll need to edit them manually before pencil will start successfully."
      else
        @l.info 'Dry run completed successfully.'
      end
    end
  end

  def load_configs
    @l.info 'loading configs'
    configs = Dir.glob("#{@dir}/**/*.y{a,}ml")

    configs.each do |c|
      yml = YAML.load_file(c)
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
    [:graphs, :dashboards, :config].each do |c|
      if not @rawconfig[c]
        @l.error "Missing config name '#{c.to_s}' in directory #{@dir}"
        exit 4
      end
    end
    @l.info 'done loading configs'
  end

  # convert :config values to the new format
  def y2y
    y = @rawconfig[:config]
    deprecated = {
      :use_color => "If your graphite doesn't have the color() function you should update to version 0.9.9 or later.",
      :default_colors => 'Modify the [default] template in your graphite graphTemplates.conf if you want similar behavior.',
      :quantum => '',
      :now_threshold => '',
      :date_format => '(yet, moment.js style format strings will be supported in the future.)'
    }

    g = GraphiteGraph.new(:none)

    newconfig = {}

    @l.info "processing :config..."
    y.keys.each do |key|
      if deprecated[key]
        @l.warn ":#{key} is no longer supported (removed)#{"\n    " + deprecated[key] if deprecated[key].size>0}"
      elsif key == :url_opts
        next
      else
        @l.info "adding :#{key} to new configuration"
        newconfig[key] = y[key]
      end
    end


    @l.info "processing :url_opts"
    newconfig[:default_url_opts] = {}
    opts = y[:url_opts]
    opts.keys.each do |key2|
      if key2 == :start
        newconfig[:default_views] = [{'-1h' => 'one hour view'},
                                     {'-8h' => 'eight hour view'},
                                     {'-1d' => 'one day view'}]
        now = Time.now
        min = ((now - Chronic.parse(opts[key2], :now => now)) / 60).to_i
        h = min / 60
        if [1, 8, 24].include? h
          index = newconfig[:default_views].index {|x| x.keys.first =~ /#{h}/}
          v = newconfig[:default_views][index]
          v2 = {'default' => v}
          newconfig[:default_views].delete(newconfig[:default_views][index])
          newconfig[:default_views].insert(index, v2)
        else
          newconfig[:default_views] <<{'default' => "-#{min}min"}
        end
        @l.info "added default view -#{min}min"
      elsif g.properties.include?(key2.to_s.downcase.to_sym)
        newconfig[:default_url_opts][key2.to_s.downcase.to_sym] = opts[key2]
      elsif @name_change[key2]
        newconfig[:default_url_opts][@name_change[key2]] = opts[key2]
      else
        @l.warn "dropping url_opt :#{key2}: not supported by the graphite DSL"
      end
    end

    newconfig[:templates_dir] = "./templates_new"

    @l.info "processing :url_opts done"
    @l.info "processing :config done"

    @l.info "new config looks like this: \n"
    puts newconfig.to_yaml
    puts "\n"
    @newconfig = newconfig
  end

  def y2y_commit
    @l.info "writing pencil.yml.new"
    File.open('pencil.yml.new', 'w') do |f|
      f.puts @newconfig.to_yaml
    end
  end

  # dashboards
  def y2d
    @l.info "processing :dashboards..."
    y = @rawconfig[:dashboards]
    y.each do |f, hash|
      fname = f + ".yml"
      @l.info "generate dashboard #{fname}"
      hash["graphs"].map! do |m|
        if m.values != [nil]
          m
        else
          m.keys.first
        end
      end
      @dashboards << [fname,
                      { "title" => hash["title"] ,
                        "graphs" => hash["graphs"],
                        "hosts" => hash["hosts"]}.to_yaml]
    end
    @l.info "processing :dashboards done"
  end

  def y2d_commit
    @l.info "writing dashboard files..."
    @dashboards.each do |f, y|
      File.open(File.join('templates_new', f), "w") do |f2|
        f2.puts(y)
      end
    end
  end

  # graphs
  def y2g
    template = ERB.new <<-EOT
# -*- mode: ruby -*-
title '<%= h['title'] %>'<% attrs.each do |a, v| %>
<%= a.to_s %> <%= v.inspect %><% end %>
<% fields.each do |name, inner_attrs| %>
field :<%= name %>,<% inner_attrs.each_with_index do |s, i| %>
      <%= s %><%= ',' unless i+1 == inner_attrs.size %><% end %>
<% end %>
EOT

    @l.info "processing :graphs..."
    y = Map(@rawconfig[:graphs])
    y.each do |f, hash|
      h = {}
      fname = f + '.graph'
      h['title'] = hash['title']
      attrs = []
      # hash.each do |k, v|
      #   attrs << [@name_change[k.to_sym], v] if @name_change[k.to_sym]
      # end
      g = Graph.new(f, hash)
      fields, moar_attrs = g.render_url(['F'], ['U'])
      h['fields'] = fields
      moar_attrs = moar_attrs.to_a.map {|z, zz| [@name_change[z.to_sym], zz]}
      attrs += moar_attrs
      attrs.delete_if {|x, z| x == :title}
      @l.info "generated graph #{fname}"
      result = template.result(binding)
      graph = GraphiteGraph.new(:none)
      begin
        graph.instance_eval(result)
      rescue Exception => e
        @l.error "in generated graph definition #{fname}: #{e}"
        puts '   You will have to edit this graph manually!'
        @errors << f
      end
      @graphs << [fname, result]
    end
    @l.info "processing :graphs done"
  end

  def y2g_commit
    @l.info "writing graph files..."
    @graphs.each do |fname, text|
      File.open(File.join('templates_new', 'graphs', fname), 'w') do |f|
        f.puts text
      end
    end
  end
end

App.new(l).run

###############################################################################
