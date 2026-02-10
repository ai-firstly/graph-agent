# frozen_string_literal: true

module GraphAgent
  module Graph
    class Edge
      attr_reader :source, :target

      def initialize(source, target)
        @source = source.to_s
        @target = target.to_s
      end

      def ==(other)
        other.is_a?(Edge) && source == other.source && target == other.target
      end
      alias eql? ==

      def hash
        [source, target].hash
      end
    end
  end
end
