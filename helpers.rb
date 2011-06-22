module Dash::Helpers
  include Dash::Models

  @@prefs = [["Start", "start"],
             ["Duration", "duration"],
             ["Width", "width"],
             ["Height", "height"]]

  # convert keys to symbols before lookup
  def param_lookup (name)
    sym_hash = {}
    session.each { |k,v| sym_hash[k.to_sym] = v unless v.empty? }
    params.each { |k,v| sym_hash[k.to_sym] = v unless v.empty? }
    settings.config.global_config[:url_opts].merge(sym_hash)[name.to_sym]
  end

  def cluster_graph(g, cluster, title="wtf")
    image_url = \
    @dash.render_cluster_graph(g, cluster,
                               :title => title,
                               :dynamic_url_opts => merge_opts)
    zoom_url = cluster_graph_link(@dash.name, g, cluster)
    return image_url, zoom_url
  end

  def cluster_graph_link(name, g, cluster)
    return append_query_string("/dash/#{cluster}/#{name}/#{g.name}")
  end

  def cluster_zoom_graph(g, cluster, host, title)
    image_url = g.render_url([host], [cluster], :title => title,
                             :dynamic_url_opts => merge_opts)
    zoom_url = cluster_zoom_link(cluster, host)
    return image_url, zoom_url
  end

  def cluster_zoom_link(cluster, host)
    return append_query_string("/host/#{cluster}/#{host}")
  end

  def suggest_cluster_links(clusters)
    links = []
    clusters.each do |c|
      href = append_query_string("/dash/#{c}/#{params[:dashboard]}")
      links << "<a href=\"#{href}\">#{c}</a>"
    end
    return "(" + links.join(", ") + ")"
  end

  def suggest_dashboards_links(host, graph)
    suggested = suggest_dashboards(host, graph)
    return "" if suggested.length == 0

    links = []
    suggested.each do |d|
      links << "<a href=\"/dash/#{host.cluster}/#{append_query_string(d)}\">" +
        "#{d}</a>"
    end
    return "(" + links.join(", ") + ")"
  end

  # it's mildly annoying that when this set is empty there're no uplinks
  # consider adding a link up to the cluster (which is best we can do)
  def suggest_dashboards(host, graph)
    ret = Set.new

    host.graphs.each do |g|
      Dashboard.find_by_graph(g).each do |d|
        valid, _ = d.get_valid_hosts(g, host['cluster'])
        ret << d.name if valid.member?(host)
      end
    end

    return ret
  end

  # generate the input box fields, filled in to current parameters if specified
  def input_boxes
    @prefs = @@prefs
    erb :'partials/input_boxes', :layout => false
  end

  def cookies_form
    @prefs = @@prefs
    erb :'partials/cookies_form', :layout => false
  end

  def refresh_button
    @prefs = @@prefs
    erb :'partials/refresh_button', :layout => false
  end

  def dash_link(dash, cluster)
    return append_query_string("/dash/#{cluster}/#{dash.name}")
  end

  def cluster_link(cluster)
    return append_query_string("/dash/#{cluster}")
  end

  def css_url
    mtime = File.mtime('public/style.css').to_i.to_s
    return \
    %Q[<link href="/style.css?#{mtime}" rel="stylesheet" type="text/css">]
  end

  def refresh
    return "" if params["permalink"]
    if settings.config.global_config[:refresh_rate] != false
      rate = settings.config.global_config[:refresh_rate] || 60
      return %Q[<meta http-equiv="refresh" content="#{rate}">]
    end
  end

  def hosts_selector (hosts)
    @hosts = hosts
    erb :'partials/hosts_selector', :layout => false
  end

  def append_query_string(str)
    v = str.dup
    query = request.query_string.chomp("&permalink=1")
    (v << "?#{query}") unless request.query_string.empty?
    return v
  end

  def merge_opts
    # fixme
    # surely sinatra has a better way than this or parsing request.query_string
    static_opts = ["cluster", "dashboard", "zoom", "host"]
    opts = params.dup
    opts.delete_if { |k,v| static_opts.member?(k) || v.empty? }
    session.merge(opts)
  end

  def cluster_switcher
    erb :'partials/cluster_switcher', :layout => false
  end

  def dash_switcher
    erb :'partials/dash_switcher', :layout => false
  end

  def graph_switcher
    erb :'partials/graph_switcher', :layout => false
  end

  def cluster_selector
    @clusters = settings.config.clusters.sort + ["global"]
    erb :'partials/cluster_selector', :layout => false
  end

  def host_uplink
    link = "/dash/#{append_query_string(@host.cluster)}"
    "zoom out: <a href=\"#{link}\">#{@host.cluster}</a>"
  end

  def graph_uplink
    link = append_query_string(request.path.split('/')[0..-2].join('/'))
    "zoom out: <a href=\"#{link}\">#{@dash}</a>"
  end

  def dash_uplink
    link = append_query_string(request.path.split('/')[0..-2].join('/'))
    "zoom out: <a href=\"#{link}\">#{@params[:cluster]}</a>"
  end

  def check_times
    (!@params[:start] || Chronic.parse(@params[:start])) &&
      (!@params[:duration] || ChronicDuration.parse(@params[:duration]))
  end

  def range_string
    format = settings.config.global_config[:date_format] || "%X %x"
    start = param_lookup("start")
    duration = param_lookup("duration")
    stime = Chronic.parse(start)
    t1 = stime ? stime.strftime(format) : ""
    etime = stime + (ChronicDuration.parse(duration)||0) if duration && stime
    t2 = (etime || Time.now).strftime(format)
    return t1 && t2 ? "timeslice: #{t1} - #{t2}" : "invalid time range"
  end

  def permalink
    url = request.path + '?'
    @@prefs.each do |label, name|
      next if name == "start" || name == "duration" # done specially
      url << "&#{name}=#{param_lookup(name)}"
    end
    # fixme some code duplication
    format = "%x %X" # chronic understands this
    start = param_lookup("start")
    duration = param_lookup("duration")
    stime = Chronic.parse(start)
    return "" unless stime
    t1 = stime.strftime(format)
    seconds = stime.strftime("%s").to_i
    if duration
      etime = ChronicDuration.parse(duration)
      return "" unless etime
      t2 = ChronicDuration.output(etime)
    else
      t2 = ChronicDuration.output(Time.now.strftime("%s").to_i - seconds)
    end

    url << "&start=#{t1}"
    url << "&duration=#{t2}"
    url << "&permalink=1"
    "<a href=\"#{url}\">permalink</a>"
  end
end
