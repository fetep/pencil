class Pencil::Models::Cluster
  attr_accessor :hosts, :noassoc
  attr_reader :name, :psuedo

  # keep track of dashboards associated with this cluster
  def initialize (name, hosts, noassoc, psuedo=false)
    @name = name || 'global'
    @hosts = hosts
    @noassoc = noassoc
    @psuedo = psuedo
    @dashboards = []
  end

  def to_s
    @name
  end
  def <=> (other)
    @name <=> other.name
  end
end
