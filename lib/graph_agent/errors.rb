# frozen_string_literal: true

module GraphAgent
  class GraphError < StandardError; end

  class GraphRecursionError < GraphError
    def initialize(msg = nil)
      super(msg || "Graph has exhausted the maximum number of steps. " \
                   "To increase the limit, set recursion_limit in config.")
    end
  end

  class InvalidUpdateError < GraphError; end

  class EmptyChannelError < GraphError; end

  class InvalidGraphError < GraphError; end

  class NodeExecutionError < GraphError
    attr_reader :node_name, :original_error

    def initialize(node_name, original_error)
      @node_name = node_name
      @original_error = original_error
      super("Error in node '#{node_name}': #{original_error.message}")
    end
  end

  class GraphInterrupt < GraphError
    attr_reader :interrupts

    def initialize(interrupts = [])
      @interrupts = interrupts
      super("Graph interrupted with #{interrupts.length} interrupt(s)")
    end
  end

  class EmptyInputError < GraphError; end

  class TaskNotFound < GraphError; end
end
