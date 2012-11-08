module Pencil::Helpers
  include Pencil::Models
  include Rack::Utils

  # todo not suck
  def cluster_switcher
    return @cluster.name unless @multi
    target = @dash.clusters - [@cluster.name]
    return @cluster.name if target.size == 0

    res = target.map do |c|
      "<li><a tabindex=\"-1\" href=\"/dash/#{c}/#{@dash.name}\">#{c}</a></li>"
    end
    if @cluster.name != 'global'
      res << '<li class="divider"></li>'
      res << "<li><a tabindex=\"-1\" href=\"/dash/global/#{@dash.name}\">global</a></li>"
    end

    <<EOF
  <span class="dropdown">
    <a id="drop1" href="#" role="button" class="dropdown-toggle" data-toggle="dropdown">#{@cluster}</a>
    <ul class="dropdown-menu" role="menu" aria-labelledby="drop1">
      #{res.join("\n")}
    </ul>
  </span>
EOF
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
