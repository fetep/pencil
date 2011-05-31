module Dash::Helpers
  include Dash::Models

  def cluster_graph(g, cluster, title="wtf")
    image_url = @dash.render_cluster_graph(g, cluster, :title => title)
    zoom_url = cluster_graph_link(@dash.name, g, cluster)
    return image_url, zoom_url
  end

  def cluster_graph_link(name, g, cluster)
    # TODO: preserve URL params
    return "/dash/#{cluster}/#{name}/#{g.name}"
  end

  def cluster_zoom_graph(g, cluster, host, title)
    image_url = g.render_url([host], [cluster], :title => title)
    zoom_url = cluster_zoom_link(cluster, host)
    return image_url, zoom_url
  end

  def cluster_zoom_link(cluster, host)
    # TODO: preserve URL params
    return "/host/#{cluster}/#{host}"
  end

  def suggest_dashboards_links(host, graph)
    suggested = suggest_dashboards(host, graph)
    return "" if suggested.length == 0

    links = []
    suggested.each do |d|
      links << "<a href=\"/dash/#{host.cluster}/#{d}\">" +
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

  def dash_link(dash, cluster)
    return "/dash/#{cluster}/#{dash.name}"
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
end
