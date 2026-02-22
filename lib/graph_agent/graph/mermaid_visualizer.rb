# frozen_string_literal: true

require "set"

module GraphAgent
  module Graph
    class MermaidVisualizer
      START_LABEL = "START"
      END_LABEL = "END"
      CONDITION_PREFIX = "cond_"

      # Generate Mermaid diagram for a StateGraph
      def self.render(state_graph, options = {})
        new(state_graph, options).render
      end

      def initialize(state_graph, options = {})
        @graph = state_graph
        @options = options
      end

      def render
        lines = ["graph TD"]
        lines << _style_definitions
        lines << ""

        # Render entry point (START)
        lines << _node_definition(START.to_s, START_LABEL, :start)

        # Render all graph nodes
        @graph.nodes.each do |name, node|
          lines << _node_definition(name, _node_label(name, node), :node)
        end

        # Render exit point (END)
        lines << _node_definition(END_NODE.to_s, END_LABEL, :end)

        lines << ""

        # Render regular edges
        @graph.edges.each do |edge|
          lines << _edge_definition(edge)
        end

        # Render conditional edges (branches)
        @graph.branches.each do |source, branches|
          branches.each_with_index do |(name, branch), idx|
            cond_id = "#{source}_#{CONDITION_PREFIX}#{idx}"
            lines << _node_definition(cond_id, _condition_label(branch), :condition)

            # Edge from source to condition node
            lines << "  #{_safe_id(source)} --> #{_safe_id(cond_id)}"

            # Edges from condition to targets
            if branch.path_map
              _render_path_map_edges(branch, cond_id, lines)
            else
              # Simple condition - render with note
              lines << "  #{_safe_id(cond_id)} -.->|condition| #{_safe_id(source)}_next"
              lines << "  #{_safe_id(source)}_next[\"?\"]"
            end
          end
        end

        # Render waiting edges (multi-source edges)
        @graph.waiting_edges.each do |(sources, target)|
          sources.each do |source|
            lines << "  #{_safe_id(source)} --> #{_safe_id(target)}"
          end
        end

        lines.join("\n")
      end

      private

      def _style_definitions
        <<~STYLES
          classDef start fill:#e1f5e1,stroke:#4caf50,stroke-width:2px
          classDef endNode fill:#ffebee,stroke:#f44336,stroke-width:2px
          classDef node fill:#e3f2fd,stroke:#2196f3,stroke-width:2px,rx:5px
          classDef condition fill:#fff9c4,stroke:#ffc107,stroke-width:2px

          class #{_safe_id(START.to_s)} start
          class #{_safe_id(END_NODE.to_s)} endNode
        STYLES
      end

      def _node_definition(id, label, type)
        safe_id = _safe_id(id)
        case type
        when :condition
          "  #{safe_id}{#{label.inspect}}"
        else
          "  #{safe_id}[#{label.inspect}]"
        end
      end

      def _edge_definition(edge)
        "  #{_safe_id(edge.source)} --> #{_safe_id(edge.target)}"
      end

      def _render_path_map_edges(branch, cond_id, lines)
        branch.path_map.each do |condition, target|
          next if condition == :default

          lines << "  #{_safe_id(cond_id)} -.->|#{condition}| #{_safe_id(target)}"
        end
        # Handle default path
        if branch.path_map.key?(:default)
          lines << "  #{_safe_id(cond_id)} -.->|default| #{_safe_id(branch.path_map[:default])}"
        end
      end

      def _safe_id(id)
        # Escape special characters for Mermaid
        id.to_s.gsub(/[^a-zA-Z0-9_]/, "_")
      end

      def _node_label(name, node)
        # Use node name or try to extract a readable name from action
        if @options[:show_node_names]
          name
        else
          _extract_readable_name(name, node)
        end
      end

      def _extract_readable_name(name, node)
        # Try to get a readable name from the action
        action = node.action
        if action.respond_to?(:name) && !action.name.nil? && !action.name.to_s.empty?
          action.name.to_s.split("::").last
        else
          name
        end
      end

      def _condition_label(branch)
        # Try to extract a meaningful label from the condition
        path = branch.path
        if path.respond_to?(:name) && !path.name.nil? && !path.name.empty?
          path.name
        elsif branch.path_map
          # Show the possible conditions
          conditions = branch.path_map.keys - [:default]
          conditions.join(" / ")
        else
          "?"
        end
      end
    end
  end
end
