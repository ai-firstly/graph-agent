# frozen_string_literal: true

module GraphAgent
  class StateSnapshot
    attr_reader :values, :next_nodes, :config, :metadata,
                :created_at, :parent_config, :tasks, :interrupts

    def initialize(
      values:,
      next_nodes: [],
      config: {},
      metadata: nil,
      created_at: nil,
      parent_config: nil,
      tasks: [],
      interrupts: []
    )
      @values = values
      @next_nodes = Array(next_nodes)
      @config = config
      @metadata = metadata
      @created_at = created_at
      @parent_config = parent_config
      @tasks = Array(tasks)
      @interrupts = Array(interrupts)
    end
  end
end
