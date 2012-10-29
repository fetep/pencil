require 'pencil/models/base'
require 'pencil/models/graph'
require 'pencil/models/host'
require 'set'

module Pencil::Models
  class Dashboard
    class << self
      ATTRS = [:groupings, :group_map]
      attr_accessor(*ATTRS)
      # fixme modulify
      def save
        ATTRS.each do |a|
          val = instance_variable_get("@#{a}")
          instance_variable_set("@_#{a}", val)
        end
      end
      def restore
        ATTRS.each do |a|
          val = instance_variable_get("@_#{a}")
          instance_variable_set("@#{a}", val)
        end
      end
    end

    def self.groups
      @groupings
    end

    def self.clear # on reload
      @groupings = SortedSet.new
      @group_map = {} # group => SortedSet of dashboards
    end

    def self.group_entries (group)
      @group_map[group]
    end

    attr_reader :title, :graphs, :name, :group, :description
    attr_accessor :assoc # graph -> wildcard -> hosts

    # fixme warn on duplicate titles
    def initialize(file, config_directory)
      path = Pathname.new(file).relative_path_from(Pathname.new(config_directory)).to_s
      relname = File.dirname(path).split(File::SEPARATOR).last
      relname = 'default' if relname == '.'
      yaml = YAML::load_file file
      @name = File.basename(file, '.yml').chomp('.yaml')
      @group = yaml['group'] || relname
      self.class.groupings ||= SortedSet.new
      self.class.group_map ||= {}
      self.class.groupings << @group
      self.class.groupings << @group
      self.class.group_map[@group] ||= SortedSet.new
      self.class.group_map[@group] << self
      @title = yaml['title']
      @description = yaml['description']
      # fixme warn about no hosts key
      global_hosts = {'hosts' => (yaml['hosts'] || '*')}
      @graphs = yaml['graphs'].map do |a|
        a.is_a?(String) ? [a, global_hosts] : a.first
      end
      @assoc = {}
      @graphs.each do |g, h|
        raise "dashboard #{@name} graph #{g} has no hosts!" unless h['hosts']
        h['hosts'].each do |wildcard|
          @assoc[g] ||= {}
          @assoc[g][wildcard] ||= SortedSet.new
        end
      end
    end

    # fixme make these better
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
