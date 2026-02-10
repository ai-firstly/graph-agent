# frozen_string_literal: true

module GraphAgent
  module Graph
    class StateGraph
      attr_reader :schema, :nodes, :edges, :branches, :waiting_edges

      def initialize(schema = nil, input_schema: nil, output_schema: nil)
        @schema = _normalize_schema(schema)
        @input_schema = input_schema ? _normalize_schema(input_schema) : nil
        @output_schema = output_schema ? _normalize_schema(output_schema) : nil
        @nodes = {}
        @edges = Set.new
        @branches = Hash.new { |h, k| h[k] = {} }
        @waiting_edges = Set.new
      end

      def add_node(name, action = nil, metadata: nil, retry_policy: nil, cache_policy: nil, &block)
        action = block if block && action.nil?
        name = _get_node_name(name, action)

        raise InvalidGraphError.new("Node action must be provided") if action.nil?
        raise InvalidGraphError.new("Node '#{name}' already exists") if @nodes.key?(name)
        raise InvalidGraphError.new("Node name '#{name}' is reserved") if [END_NODE.to_s, START.to_s].include?(name)

        @nodes[name] = Node.new(
          name, action,
          metadata: metadata,
          retry_policy: retry_policy,
          cache_policy: cache_policy
        )
        self
      end

      def add_edge(start_key, end_key)
        if start_key.is_a?(Array)
          targets = start_key.map(&:to_s)
          @waiting_edges.add([targets, end_key.to_s])
          return self
        end

        start_key = start_key.to_s
        end_key = end_key.to_s

        raise InvalidGraphError.new("END cannot be a start node") if start_key == END_NODE.to_s
        raise InvalidGraphError.new("START cannot be an end node") if end_key == START.to_s

        @edges.add(Edge.new(start_key, end_key))
        self
      end

      def add_conditional_edges(source, path, path_map = nil)
        source = source.to_s
        name = _branch_name(path)

        if @branches[source].key?(name)
          raise InvalidGraphError.new("Branch '#{name}' already exists for node '#{source}'")
        end

        @branches[source][name] = ConditionalEdge.new(source, path, path_map: path_map)
        self
      end

      def add_sequence(nodes)
        node_names = nodes.map do |node|
          if node.is_a?(Array)
            name, action = node
            add_node(name, action)
            name.to_s
          elsif node.respond_to?(:call)
            name = _get_node_name(nil, node)
            add_node(name, node)
            name
          else
            node.to_s
          end
        end

        node_names.each_cons(2) { |a, b| add_edge(a, b) }
        self
      end

      def set_entry_point(node_name)
        add_edge(START, node_name)
      end

      def set_finish_point(node_name)
        add_edge(node_name, END_NODE)
      end

      def set_conditional_entry_point(path, path_map = nil)
        add_conditional_edges(START, path, path_map)
      end

      def compile(checkpointer: nil, interrupt_before: nil, interrupt_after: nil, debug: false)
        validate!

        CompiledStateGraph.new(
          builder: self,
          checkpointer: checkpointer,
          interrupt_before: interrupt_before || [],
          interrupt_after: interrupt_after || [],
          debug: debug
        )
      end

      private

      def _normalize_schema(schema)
        case schema
        when State::Schema then schema
        when Hash          then _schema_from_hash(schema)
        when nil           then nil
        end
      end

      def _schema_from_hash(hash)
        s = State::Schema.new
        hash.each do |name, opts|
          opts.is_a?(Hash) ? s.field(name, **opts) : s.field(name)
        end
        s
      end

      def _get_node_name(name, action)
        return name.to_s if name

        if action.respond_to?(:name) && !action.name.nil? && !action.name.empty?
          action.name.split("::").last.gsub(/[^a-zA-Z0-9_]/, "_")
        else
          raise InvalidGraphError.new("Node name must be provided")
        end
      end

      def _branch_name(path)
        if path.respond_to?(:name) && path.name && !path.name.empty?
          path.name
        else
          "condition_#{@branches.values.sum(&:size)}"
        end
      end

      def validate!
        _validate_entry_point!
        _validate_edges!
        _validate_outgoing_edges!
      end

      def _validate_entry_point!
        entry_edges = @edges.any? { |e| e.source == START.to_s }
        entry_branches = @branches[START.to_s]&.any?

        return if entry_edges || entry_branches

        raise InvalidGraphError.new("Graph must have an entry point. Use set_entry_point or add_edge(START, ...)")
      end

      def _validate_edges!
        sentinel = [START.to_s, END_NODE.to_s]
        @edges.each do |edge|
          next if sentinel.include?(edge.source)

          unless @nodes.key?(edge.source)
            raise InvalidGraphError.new("Edge references unknown source node '#{edge.source}'")
          end

          next if edge.target == END_NODE.to_s

          unless @nodes.key?(edge.target)
            raise InvalidGraphError.new("Edge references unknown target node '#{edge.target}'")
          end
        end
      end

      def _validate_outgoing_edges!
        @nodes.each_key do |name|
          has_outgoing = @edges.any? { |e| e.source == name } ||
                         (@branches.key?(name) && !@branches[name].empty?)

          raise InvalidGraphError.new("Node '#{name}' has no outgoing edges") unless has_outgoing
        end
      end
    end
  end
end
