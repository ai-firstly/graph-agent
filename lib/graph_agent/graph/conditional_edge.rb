# frozen_string_literal: true

module GraphAgent
  module Graph
    class ConditionalEdge
      attr_reader :source, :path, :path_map

      def initialize(source, path, path_map: nil)
        @source = source.to_s
        @path = path
        @path_map = path_map
      end

      def resolve(state, config = {})
        result = invoke_path(state, config)
        _resolve_result(result)
      end

      private

      def invoke_path(state, config)
        unless @path.is_a?(Proc) || @path.respond_to?(:call)
          raise GraphError.new("Conditional edge path is not callable")
        end

        case @path.arity
        when 0 then @path.call
        when 1, -1 then @path.call(state)
        else @path.call(state, config)
        end
      end

      def _resolve_result(result)
        case result
        when GraphAgent::Send then [result]
        when Array            then _resolve_array(result)
        else @path_map ? _map_result(result) : result
        end
      end

      def _resolve_array(result)
        return result if result.all? { |r| r.is_a?(GraphAgent::Send) }
        return result.map { |r| _map_result(r) } if @path_map

        result
      end

      def _map_result(result)
        mapped = @path_map[result]
        mapped = @path_map[:default] if mapped.nil? && @path_map.key?(:default)
        raise InvalidGraphError.new("Unknown path result: #{result.inspect}") if mapped.nil?

        mapped
      end
    end
  end
end
