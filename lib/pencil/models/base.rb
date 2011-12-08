module Pencil
  module Models
    class Base
      @@objects = Hash.new { |h, k| h[k] = Hash.new }
      attr_reader :name

      def initialize(name, params={})
        @name = name
        @match_name = name
        @params = params
        @@objects[self.class.to_s][name] = self
      end

      def self.find(name)
        return @@objects[self.name][name] rescue []
      end

      def self.each(&block)
        h = @@objects[self.name] rescue {}
        h.each { |k, v| yield(k, v) }
      end

      def self.all
        return @@objects[self.name].values
      end

      def [](key)
        return @params[key] rescue []
      end

      def match(glob)
        return true if glob == '*'
        # convert glob to a regular expression
        glob_parts = glob.split('*').collect { |s| Regexp.escape(s) }
        if glob[0].chr == '*'
          glob_re = /^.*#{glob_parts.join('.*')}$/
        elsif glob[-1].chr == '*'
          glob_re = /^#{glob_parts.join('.*')}.*$/
        else
          glob_re = /^#{glob_parts.join('.*')}$/
        end
        return @match_name.match(glob_re)
      end

      def multi_match(globs)
        ret = false

        globs.each do |glob|
          ret = match(glob)
          break if ret
        end

        return ret
      end

      def to_s
        return @name
      end

      def <=>(other)
        return to_s <=> other.to_s
      end

      def update_params(hash)
        @params.merge!(hash)
      end

      # compose a metric using a :metric_format
      # format string with %c for metric, %c for cluster, and %h for host
      def compose_metric (m, c, h)
        @params[:metric_format].dup.gsub("%m", m).gsub("%c", c).gsub("%h", h)
      end
    end # Pencil::Models::Base
  end
end # Pencil::Models
