require 'pencil/models/base'
require 'pencil/models/graph'
require 'pencil/models/host'
require 'set'

module Pencil::Models
  class Dashboard
    @@groupings = SortedSet.new
    @@group_map = {} # group => SortedSet of dashboards
    def self.groups
      @@groupings
    end
    def self.clear # on reload
      @@groupings = SortedSet.new
      @@group_map = {} # group => SortedSet of dashboards
    end
    def self.group_entries (group)
      @@group_map[group]
    end

    attr_reader :title, :graphs, :name, :group
    attr_accessor :assoc # graph -> wildcard -> hosts

    # fixme warn on duplicate titles
    def initialize(file, config_directory)
      path = Pathname.new(file).relative_path_from(Pathname.new(config_directory)).to_s
      relname = File.dirname(path).split(File::SEPARATOR).last
      relname = 'default' if relname == '.'
      yaml = YAML::load_file file
      @name = File.basename(file, '.yml').chomp('.yaml')
      @group = yaml['group'] || relname
      @@groupings << @group
      @@group_map[@group] ||= SortedSet.new
      @@group_map[@group] << self
      @title = yaml['title']
      # fixme warn about no hosts key
      global_hosts = {'hosts' => (yaml['hosts'] || '*')}
      @graphs = yaml['graphs'].map do |a|
        a.is_a?(String) ? [a, global_hosts] : a.first
      end
      @assoc = {}
      @graphs.each do |g, h|
        h['hosts'].each do |wildcard|
          @assoc[g] ||= {}
          @assoc[g][wildcard] ||= SortedSet.new
        end
      end
    end

    def to_s
      @name
    end

    def inspect
      @name
    end

    def <=> (other)
      @name <=> other.name
    end
  end # Pencil::Models::Dashboard
end # Pencil::Models
