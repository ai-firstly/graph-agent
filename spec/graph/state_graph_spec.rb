# frozen_string_literal: true

RSpec.describe GraphAgent::Graph::StateGraph do
  let(:schema) do
    s = GraphAgent::State::Schema.new
    s.field(:value, default: "")
    s
  end

  describe "#add_node" do
    it "adds a node with a block" do
      graph = described_class.new(schema)
      graph.add_node("a") { |state| state }

      expect(graph.nodes).to have_key("a")
    end

    it "adds a node with a callable" do
      graph = described_class.new(schema)
      action = ->(state) { state }
      graph.add_node("a", action)

      expect(graph.nodes).to have_key("a")
      expect(graph.nodes["a"].action).to eq(action)
    end

    it "rejects duplicate node names" do
      graph = described_class.new(schema)
      graph.add_node("a") { |state| state }

      expect { graph.add_node("a") { |state| state } }
        .to raise_error(GraphAgent::InvalidGraphError, /already exists/)
    end

    it "rejects the reserved name START" do
      graph = described_class.new(schema)

      expect { graph.add_node(GraphAgent::START) { |s| s } }
        .to raise_error(GraphAgent::InvalidGraphError, /reserved/)
    end

    it "rejects the reserved name END_NODE" do
      graph = described_class.new(schema)

      expect { graph.add_node(GraphAgent::END_NODE) { |s| s } }
        .to raise_error(GraphAgent::InvalidGraphError, /reserved/)
    end

    it "requires an action" do
      graph = described_class.new(schema)

      expect { graph.add_node("a") }
        .to raise_error(GraphAgent::InvalidGraphError, /action must be provided/)
    end
  end

  describe "#add_edge" do
    it "adds a normal edge" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.add_edge(GraphAgent::START, "a")

      expect(graph.edges.size).to eq(1)
    end

    it "rejects END_NODE as a source" do
      graph = described_class.new(schema)

      expect { graph.add_edge(GraphAgent::END_NODE, "a") }
        .to raise_error(GraphAgent::InvalidGraphError, /END cannot be a start node/)
    end

    it "rejects START as a target" do
      graph = described_class.new(schema)

      expect { graph.add_edge("a", GraphAgent::START) }
        .to raise_error(GraphAgent::InvalidGraphError, /START cannot be an end node/)
    end

    it "supports waiting edges (multi-source)" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.add_node("b") { |s| s }
      graph.add_node("c") { |s| s }
      graph.add_edge(%w[a b], "c")

      expect(graph.waiting_edges.size).to eq(1)
      sources, target = graph.waiting_edges.first
      expect(sources).to eq(%w[a b])
      expect(target).to eq("c")
    end
  end

  describe "#add_conditional_edges" do
    it "adds a conditional edge" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      router = ->(_state) { "a" }
      graph.add_conditional_edges(GraphAgent::START, router)

      expect(graph.branches[GraphAgent::START.to_s]).not_to be_empty
    end

    it "rejects duplicate branch names" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      router = ->(_state) { "a" }
      def router.name = "my_router"

      graph.add_conditional_edges(GraphAgent::START, router)

      expect { graph.add_conditional_edges(GraphAgent::START, router) }
        .to raise_error(GraphAgent::InvalidGraphError, /already exists/)
    end
  end

  describe "#set_entry_point and #set_finish_point" do
    it "set_entry_point adds an edge from START" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.set_entry_point("a")

      edge = graph.edges.first
      expect(edge.source).to eq(GraphAgent::START.to_s)
      expect(edge.target).to eq("a")
    end

    it "set_finish_point adds an edge to END_NODE" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.set_finish_point("a")

      edge = graph.edges.first
      expect(edge.source).to eq("a")
      expect(edge.target).to eq(GraphAgent::END_NODE.to_s)
    end
  end

  describe "#compile validation" do
    it "requires an entry point" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.add_edge("a", GraphAgent::END_NODE)

      expect { graph.compile }
        .to raise_error(GraphAgent::InvalidGraphError, /entry point/)
    end

    it "requires all nodes to have outgoing edges" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.add_node("b") { |s| s }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      expect { graph.compile }
        .to raise_error(GraphAgent::InvalidGraphError, /no outgoing edges/)
    end

    it "validates that edges reference valid nodes" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", "nonexistent")

      expect { graph.compile }
        .to raise_error(GraphAgent::InvalidGraphError, /unknown target node/)
    end

    it "validates source nodes exist" do
      graph = described_class.new(schema)
      graph.add_node("a") { |s| s }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)
      graph.add_edge("nonexistent", "a")

      expect { graph.compile }
        .to raise_error(GraphAgent::InvalidGraphError, /unknown source node/)
    end
  end

  describe "Hash-based schema initialization" do
    it "accepts a Hash as schema" do
      graph = described_class.new({ value: { default: "" } })
      graph.add_node("a") { |s| { value: "done" } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      compiled = graph.compile
      result = compiled.invoke({ value: "hi" })
      expect(result[:value]).to eq("done")
    end
  end

  describe "#add_sequence" do
    it "creates a connected chain of nodes" do
      graph = described_class.new(schema)
      graph.add_sequence([
        ["a", ->(s) { { value: s[:value] + "a" } }],
        ["b", ->(s) { { value: s[:value] + "b" } }],
        ["c", ->(s) { { value: s[:value] + "c" } }]
      ])
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("c", GraphAgent::END_NODE)

      compiled = graph.compile
      result = compiled.invoke({ value: "" })
      expect(result[:value]).to eq("abc")
    end
  end
end
