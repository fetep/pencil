class YAML::Omap
  def keys
    self.map {|k,v| k}
  end
  def values
    self.map {|k,v| v}
  end
end
