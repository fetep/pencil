module Dash::Helpers
  include Dash::Models

  @@prefs = [["Start", "start"],
             ["Duration", "duration"],
             ["Width", "width"],
             ["Height", "height"]]

  # convert keys to symbols before lookup
  def param_lookup(name)
    sym_hash = {}
    session.each { |k,v| sym_hash[k.to_sym] = v unless v.empty? }
    params.each { |k,v| sym_hash[k.to_sym] = v unless v.empty? }
    settings.config.global_config[:url_opts].merge(sym_hash)[name.to_sym]
  end

  def cluster_graph(g, cluster, title="wtf")
    image_url, desc = \
    @dash.render_cluster_graph(g, cluster,
                               :title => title,
                               :dynamic_url_opts => merge_opts)
    zoom_url = cluster_graph_link(@dash, g, cluster)
    return image_url, desc, zoom_url
  end

  def cluster_graph_link(dash, g, cluster)
    link = dash.graph_opts[g]["click"] ||
      "/dash/#{cluster}/#{dash.name}/#{g.name}"
    return append_query_string(link)
  end

  def cluster_zoom_graph(g, cluster, host, title)
    image_url, desc = g.render_url([host.name], [cluster], :title => title,
                             :dynamic_url_opts => merge_opts)
    zoom_url = cluster_zoom_link(cluster, host)
    return image_url, desc, zoom_url
  end

  def cluster_zoom_link(cluster, host)
    return append_query_string("/host/#{cluster}/#{host}")
  end

  def suggest_cluster_links(clusters, g)
    links = []
    clusters.each do |c|
      href = append_query_string("/dash/#{c}/#{params[:dashboard]}/#{g.name}")
      links << "<a href=\"#{href}\">#{c}</a>"
    end
    return "zoom (" + links.join(", ") + ")"
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
    style = File.join(settings.root, "public/style.css")
    mtime = File.mtime(style).to_i.to_s
    return \
    %Q[<link href="/style.css?#{mtime}" rel="stylesheet" type="text/css">]
  end

  def refresh
    if settings.config.global_config[:refresh_rate] != false && nowish
      rate = settings.config.global_config[:refresh_rate] || 60
      return %Q[<meta http-equiv="refresh" content="#{rate}">]
    end
  end

  def hosts_selector(hosts, print_clusters=false)
    @print_clusters = print_clusters
    @hosts = hosts
    erb :'partials/hosts_selector', :layout => false
  end

  def append_query_string(str)
    v = str.dup
    (v << "?#{request.query_string}") unless request.query_string.empty?
    return v
  end

  def merge_opts
    static_opts = ["cluster", "dashboard", "zoom", "host", "session_id"]
    opts = params.dup
    session.merge(opts).delete_if { |k,v| static_opts.member?(k) || v.empty? }
  end

  def cluster_switcher(clusters)
    @clusters = clusters
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
    link = append_query_string(request.path.split("/")[0..-2].join("/"))
    "zoom out: <a href=\"#{link}\">#{@dash}</a>"
  end

  def dash_uplink
    link = append_query_string(request.path.split("/")[0..-2].join("/"))
    "zoom out: <a href=\"#{link}\">#{@params[:cluster]}</a>"
  end

  def nowish
    if settings.config.global_config[:now_threshold] == false
      return false
    end
    threshold = settings.config.global_config[:now_threshold] || 300
    return @request_time.to_i - @etime.to_i < threshold
  end

  def range_string
    format = settings.config.global_config[:date_format] || "%X %x"
    if @stime && @etime
      if nowish
        "timeslice: from #{@stime.strftime(format)}"
      else
        "timeslice: #{@stime.strftime(format)} - #{@etime.strftime(format)}"
      end
    else
      "invalid time range"
    end

  end

  def permalink
    return "" unless @stime && @duration
    format = "%F %T" # chronic REALLY understands this
    url = request.path + "?"
    url << "&start=#{@stime.strftime(format)}"
    url << "&duration=#{ChronicDuration.output(@duration)}"
    "<a href=\"#{url}\">permalink</a>"
  end
end
