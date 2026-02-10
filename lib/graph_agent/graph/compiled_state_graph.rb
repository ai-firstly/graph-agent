# frozen_string_literal: true

require "securerandom"

module GraphAgent
  module Graph
    class CompiledStateGraph # rubocop:disable Metrics/ClassLength
      DEFAULT_RECURSION_LIMIT = 25

      attr_reader :builder, :checkpointer

      def initialize(builder:, checkpointer: nil, interrupt_before: [], interrupt_after: [], debug: false)
        @builder = builder
        @checkpointer = checkpointer
        @interrupt_before = _normalize_interrupt(interrupt_before)
        @interrupt_after = _normalize_interrupt(interrupt_after)
        @debug = debug
      end

      def invoke(input, config: {}, recursion_limit: DEFAULT_RECURSION_LIMIT)
        last_state = nil

        _run_pregel(input, config: config, recursion_limit: recursion_limit) do |_event|
          last_state = _event[:state] if _event[:type] == :values
        end

        last_state
      end

      def stream(input, config: {}, recursion_limit: DEFAULT_RECURSION_LIMIT, stream_mode: :values, &block)
        unless block
          return enum_for(:stream, input, config: config, recursion_limit: recursion_limit, stream_mode: stream_mode)
        end

        _run_pregel(input, config: config, recursion_limit: recursion_limit) do |event|
          _emit_stream_event(event, stream_mode, &block)
        end
      end

      def get_state(config)
        return nil unless @checkpointer

        tuple = @checkpointer.get_tuple(config)
        return nil unless tuple

        StateSnapshot.new(
          values: tuple.checkpoint[:channel_values] || {},
          config: tuple.config,
          metadata: tuple.metadata || {},
          parent_config: tuple.parent_config,
          next_nodes: tuple.checkpoint[:next_nodes] || []
        )
      end

      def update_state(config, values, as_node: nil)
        return nil unless @checkpointer

        tuple = @checkpointer.get_tuple(config)
        return nil unless tuple

        current_state = tuple.checkpoint[:channel_values] || {}
        new_state = _apply_updates(current_state, values)

        checkpoint = _build_checkpoint(new_state, [])
        metadata = { source: :update, step: (tuple.metadata || {})[:step].to_i + 1, writes: values }

        @checkpointer.put(tuple.config, checkpoint, metadata, {})
      end

      def get_graph
        { nodes: @builder.nodes.keys, edges: @builder.edges.to_a.map { |e| [e.source, e.target] } }
      end

      private

      def _run_pregel(input, config:, recursion_limit:, &event_handler)
        state = _initialize_state(input, config)
        step = 0
        current_nodes = _resolve_entry_nodes(state, config)

        _save_checkpoint(config, state, step, :input, current_nodes)

        while current_nodes.any? { |n| !_is_terminal?(n) }
          _check_recursion_limit!(step, recursion_limit)
          runnable_nodes = current_nodes.reject { |n| _is_terminal?(n) }
          _check_interrupts_before!(runnable_nodes, config, state, step)

          state, next_nodes = _execute_superstep(runnable_nodes, state, config, step, &event_handler)

          _check_interrupts_after!(runnable_nodes, config, state, step)

          current_nodes = next_nodes.uniq
          step += 1
          _save_checkpoint(config, state, step, :loop, current_nodes)
        end

        _save_checkpoint(config, state, step, :exit, [])
        event_handler.call({ type: :values, step: step, state: state })
      end

      def _execute_superstep(runnable_nodes, state, config, step, &event_handler)
        state_snapshot = _deep_dup(state)
        step_updates = {}
        next_nodes_from_commands = []
        sends = []

        runnable_nodes.each do |node_name|
          result = _execute_node(node_name, state_snapshot, config)
          _collect_results(result, node_name, step_updates, next_nodes_from_commands, sends)
        end

        step_updates.each_value { |updates| state = _apply_updates(state, updates) }

        event_handler.call({ type: :updates, step: step, updates: step_updates.transform_keys(&:to_s) })
        event_handler.call({ type: :values, step: step, state: state })

        next_nodes = _resolve_next_nodes_for_step(runnable_nodes, state, config)
        next_nodes.concat(next_nodes_from_commands)

        state = _execute_sends(sends, state, config)

        [state, next_nodes]
      end

      def _execute_node(node_name, state_snapshot, config)
        node = @builder.nodes[node_name]
        raise InvalidGraphError.new("Node '#{node_name}' not found") unless node

        node.call(state_snapshot, config)
      rescue GraphInterrupt, GraphRecursionError
        raise
      rescue => e
        raise NodeExecutionError.new(node_name, e)
      end

      def _collect_results(result, node_name, step_updates, next_nodes_from_commands, sends)
        node_updates, node_commands, node_sends = _process_result(result)

        step_updates[node_name] = node_updates if node_updates && !node_updates.empty?

        node_commands.each do |cmd|
          _collect_command(cmd, node_name, step_updates, next_nodes_from_commands, sends)
        end

        sends.concat(node_sends)
      end

      def _collect_command(cmd, node_name, step_updates, next_nodes_from_commands, sends)
        if cmd.update
          cmd_updates = cmd.update.is_a?(Hash) ? cmd.update : {}
          step_updates["#{node_name}:command"] = cmd_updates unless cmd_updates.empty?
        end
        cmd.goto.each do |target|
          if target.is_a?(GraphAgent::Send)
            sends << target
          else
            next_nodes_from_commands << target.to_s
          end
        end
      end

      def _execute_sends(sends, state, config)
        sends.each do |send_obj|
          target = send_obj.node.to_s
          next unless @builder.nodes.key?(target)

          send_state = send_obj.arg.is_a?(Hash) ? _apply_updates(_deep_dup(state), send_obj.arg) : state
          result = @builder.nodes[target].call(send_state, config)
          node_updates, = _process_result(result)
          state = _apply_updates(state, node_updates) if node_updates
        end
        state
      end

      def _check_recursion_limit!(step, limit)
        return unless step >= limit

        raise GraphRecursionError.new("Recursion limit of #{limit} reached without hitting END node")
      end

      def _check_interrupts_before!(runnable_nodes, config, state, step)
        runnable_nodes.each do |node_name|
          next unless _should_interrupt_before?(node_name)

          _save_checkpoint(config, state, step, :interrupt, [node_name])
          raise GraphInterrupt.new([Interrupt.new("Interrupted before '#{node_name}'")])
        end
      end

      def _check_interrupts_after!(runnable_nodes, config, state, step)
        runnable_nodes.each do |node_name|
          next unless _should_interrupt_after?(node_name)

          _save_checkpoint(config, state, step, :interrupt, [])
          raise GraphInterrupt.new([Interrupt.new("Interrupted after '#{node_name}'")])
        end
      end

      def _emit_stream_event(event, stream_mode)
        case stream_mode
        when :values
          yield event[:state].dup if event[:type] == :values
        when :updates
          yield event[:updates] if event[:type] == :updates && event[:updates]
        when :debug
          yield event
        end
      end

      def _process_result(result)
        updates = {}
        commands = []
        sends = []

        case result
        when Hash      then updates = result
        when Command   then commands << result
                            updates = result.update if result.update.is_a?(Hash)
        when Send      then sends << result
        when Array     then _process_array_result(result, updates, commands, sends)
        end

        [updates, commands, sends]
      end

      def _process_array_result(result, updates, commands, sends)
        result.each do |item|
          case item
          when Hash    then updates.merge!(item)
          when Command then commands << item
                            updates.merge!(item.update) if item.update.is_a?(Hash)
          when Send    then sends << item
          end
        end
      end

      def _initialize_state(input, config)
        state = _restore_from_checkpoint(input, config)
        return state if state

        if @builder.schema.is_a?(State::Schema)
          state = @builder.schema.initial_state
          _apply_updates(state, input) if input.is_a?(Hash)
          state
        elsif input.is_a?(Hash)
          input.transform_keys(&:to_sym).dup
        else
          {}
        end
      end

      def _restore_from_checkpoint(input, config)
        return nil unless @checkpointer && config.dig(:configurable, :thread_id)

        tuple = @checkpointer.get_tuple(config)
        return nil unless tuple

        state = tuple.checkpoint[:channel_values]&.dup || {}
        input.is_a?(Hash) ? _apply_updates(state, input) : state
      end

      def _apply_updates(state, updates)
        return state unless updates.is_a?(Hash) && state.is_a?(Hash)

        updates.each do |key, value|
          key = key.to_sym
          field = @builder.schema.is_a?(State::Schema) ? @builder.schema.fields[key] : nil

          if field&.reducer
            state[key] = field.reducer.call(state[key], value)
          else
            state[key] = value
          end
        end

        state
      end

      def _resolve_entry_nodes(state, config)
        nodes = @builder.edges.select { |e| e.source == START.to_s }.map(&:target)

        if @builder.branches.key?(START.to_s)
          @builder.branches[START.to_s].each_value do |branch|
            nodes.concat(Array(branch.resolve(state, config)).map(&:to_s))
          end
        end

        nodes.uniq
      end

      def _resolve_next_nodes_for_step(executed_nodes, state, config)
        next_nodes = []

        executed_nodes.each do |node_name|
          @builder.edges.each { |edge| next_nodes << edge.target if edge.source == node_name }
          _resolve_branches(node_name, state, config, next_nodes)
        end

        _resolve_waiting_edges(executed_nodes, next_nodes)
        next_nodes.uniq
      end

      def _resolve_branches(node_name, state, config, next_nodes)
        return unless @builder.branches.key?(node_name)

        @builder.branches[node_name].each_value do |branch|
          next_nodes.concat(Array(branch.resolve(state, config)).map(&:to_s))
        end
      end

      def _resolve_waiting_edges(executed_nodes, next_nodes)
        @builder.waiting_edges.each do |sources, target|
          next_nodes << target if sources.all? { |s| executed_nodes.include?(s) }
        end
      end

      def _is_terminal?(node_name)
        node_name == END_NODE.to_s
      end

      def _should_interrupt_before?(node_name)
        @interrupt_before.include?("*") || @interrupt_before.include?(node_name)
      end

      def _should_interrupt_after?(node_name)
        @interrupt_after.include?("*") || @interrupt_after.include?(node_name)
      end

      def _normalize_interrupt(value)
        case value
        when Array then value.map(&:to_s)
        when String, Symbol then [value.to_s]
        when nil then []
        else Array(value).map(&:to_s)
        end
      end

      def _save_checkpoint(config, state, step, source, next_nodes)
        return unless @checkpointer && config.dig(:configurable, :thread_id)

        checkpoint = _build_checkpoint(_deep_dup(state), next_nodes)
        metadata = { source: source, step: step, parents: {} }
        @checkpointer.put(config, checkpoint, metadata, {})
      end

      def _build_checkpoint(channel_values, next_nodes)
        { id: SecureRandom.uuid, channel_values: channel_values, channel_versions: {},
          versions_seen: {}, next_nodes: next_nodes }
      end

      def _deep_dup(obj)
        case obj
        when Hash    then obj.transform_values { |v| _deep_dup(v) }
        when Array   then obj.map { |v| _deep_dup(v) }
        when String  then obj.dup
        when Integer, Float, Symbol, TrueClass, FalseClass, NilClass then obj
        else obj.respond_to?(:dup) ? obj.dup : obj
        end
      end
    end
  end
end
