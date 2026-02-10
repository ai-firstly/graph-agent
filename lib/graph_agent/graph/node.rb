# frozen_string_literal: true

module GraphAgent
  module Graph
    class Node
      attr_reader :name, :action, :metadata, :retry_policy, :cache_policy

      def initialize(name, action, metadata: nil, retry_policy: nil, cache_policy: nil)
        @name = name.to_s
        @action = action
        @metadata = metadata || {}
        @retry_policy = retry_policy
        @cache_policy = cache_policy
      end

      def call(state, config = {})
        result = execute_with_retry(state, config)
        normalize_result(result)
      end

      private

      def execute_with_retry(state, config)
        if @retry_policy
          attempt = 0
          begin
            attempt += 1
            invoke_action(state, config)
          rescue => e
            if attempt < @retry_policy.max_attempts && @retry_policy.should_retry?(e)
              sleep(@retry_policy.interval_for(attempt))
              retry
            end
            raise
          end
        else
          invoke_action(state, config)
        end
      end

      def invoke_action(state, config)
        if @action.is_a?(Proc) || @action.respond_to?(:call)
          case @action.arity
          when 0
            @action.call
          when 1, -1
            @action.call(state)
          else
            @action.call(state, config)
          end
        else
          raise GraphError.new("Node '#{name}' action is not callable")
        end
      end

      def normalize_result(result)
        result
      end
    end
  end
end
