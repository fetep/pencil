module Dash::Helpers
  include Dash::Models

  @@prefs = [["Start", "from"],
             ["End", "until"],
             ["Width", "width"],
             ["Height", "height"]]

  # convert keys to symbols before lookup
  def param_lookup (name)
    sym_hash = {}
    session.each { |k,v| sym_hash[k.to_sym] = v }
    params.each { |k,v| sym_hash[k.to_sym] = v }
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

  def suggest_dashboards(host, graph)
    ret = Set.new

    host.graphs.each do |g|
      Dashboard.find_by_graph(g).each do |d|
        valid, _ = d.get_valid_hosts(g, host['cluster'])
        ret << d.name if valid.member?(host.name)
      end
    end

    return ret
  end

  # generate the input box fields, filled in to url parameters if specified
  # fixme html formatting
  # fixme fill in cookied params as well?
  def input_boxen
    result = '<form name="input" method="get"><table>'
    @@prefs.each do |label, name|
      result << "\n"
      result << "<tr><td>#{label}:<td><input "
      if param_lookup(name)
        result << "value=\"#{param_lookup(name)}\" "
      elsif name == "until" # special case
        result << "value=\"now\" "
      end
    
      result << "type=\"text\" name=\"#{name}\"><td>"
    end

    result << '</table> <input type="submit" value="Submit">' + 
      '</form> <form method="get"> <input type="submit" value="Clear"></form>'
    return result
  end

  def cookies_form
    result = '<form action="/saveprefs" name="input" method="get">'
    @@prefs.each do |label, name|
      if params[name]
        result << "\n"
        result << "<input value=\"#{params[name]}\" "
        result << "type=\"hidden\" name=\"#{name}\"><br>"
      end
    end

    result << <<STR
<input type=\"submit\" value=\"save preferences in a cookie\"/>
</form>

<form action="/clear" name="clear" method="get">
<input type="submit" value="clear cookies">
</form>
STR

  end

  def refresh_button
    result = "<form action=\"#{request.path}\" name=\"input\" method=\"get\">"
    result << "<input type=\"submit\" value=\"Refresh\">"
    @@prefs.each do |label, name|
      if params[name]
        result << "\n"
        result << "<input value=\"#{params[name]}\" "
        result << "type=\"hidden\" name=\"#{name}\"><br>"
      end
    end
    result << "\n</form>"
  end

  def dash_link(dash, cluster)
    return append_query_string("/dash/#{cluster}/#{dash.name}")
  end

  def css_url
    mtime = File.mtime('public/style.css').to_i.to_s
    return \
    %Q[<link href="/style.css?#{mtime}" rel="stylesheet" type="text/css">]
  end

  def refresh
    if settings.config.global_config[:refresh_rate]
      rate = settings.config.global_config[:refresh_rate] || 60
      return %Q[<meta http-equiv="refresh" content="#{rate}">]
    end
  end

  def append_query_string(str)
    v = str.dup
    (v << "?#{request.query_string}") if !request.query_string.empty?
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

end
