module Pencil::Helpers
  include Pencil::Models
  include Rack::Utils

  # todo not suck
  def cluster_switcher
    res = (@clusters.map(&:name) - [@cluster.name]).map do |c|
      "<li><a tabindex=\"-1\" href=\"/dash/#{c}/#{@dash.name}\">#{c}</a></li>"
    end
    if @cluster.name != 'global'
      res << '<li class="divider"></li>'
      res << "<li><a tabindex=\"-1\" href=\"/dash/global/#{@dash.name}\">global</a></li>"
    end
    res
  end

  def append_query_string(str)
    v = str.dup
    unless request.query_string.empty?
      v << "?#{request.query_string.gsub("&", "&amp;")}"
    end
    return v
  end

  def suggest_dashboards(host, graph)
    ret = Set.new

    @dashboards.select do |dname, d|
      d.assoc[graph] && d.assoc[graph].values.find {|x| x.member?(@host)}
    end.each do |d|
      ret << d.first
    end

    return ret
  end

  def current (d)
    d.select do |g|
      !(@multi && !@cluster.psuedo && @cluster.name && !g.clusters.include?(@cluster.name))
    end
  end
end
