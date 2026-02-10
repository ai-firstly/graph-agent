# frozen_string_literal: true

RSpec.describe GraphAgent::Graph::CompiledStateGraph do
  def build_linear_graph(schema: nil)
    graph = GraphAgent::Graph::StateGraph.new(schema)
    graph.add_node("a") { |s| { value: s[:value] + "a" } }
    graph.add_node("b") { |s| { value: s[:value] + "b" } }
    graph.add_node("c") { |s| { value: s[:value] + "c" } }
    graph.add_edge(GraphAgent::START, "a")
    graph.add_edge("a", "b")
    graph.add_edge("b", "c")
    graph.add_edge("c", GraphAgent::END_NODE)
    graph
  end

  describe "#invoke" do
    it "returns final state" do
      compiled = build_linear_graph.compile
      result = compiled.invoke({ value: "" })

      expect(result).to be_a(Hash)
      expect(result[:value]).to eq("abc")
    end

    it "executes linear graph A -> B -> C" do
      order = []
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") do |s|
        order << :a
        { value: "a" }
      end
      graph.add_node("b") do |s|
        order << :b
        { value: "b" }
      end
      graph.add_node("c") do |s|
        order << :c
        { value: "c" }
      end
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", "b")
      graph.add_edge("b", "c")
      graph.add_edge("c", GraphAgent::END_NODE)

      graph.compile.invoke({})
      expect(order).to eq(%i[a b c])
    end

    it "supports conditional routing based on state" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("start_node") { |s| { route: s[:input] } }
      graph.add_node("left") { |s| { result: "left" } }
      graph.add_node("right") { |s| { result: "right" } }

      graph.add_edge(GraphAgent::START, "start_node")
      graph.add_conditional_edges("start_node", ->(s) { s[:route] })
      graph.add_edge("left", GraphAgent::END_NODE)
      graph.add_edge("right", GraphAgent::END_NODE)

      compiled = graph.compile

      result = compiled.invoke({ input: "left" })
      expect(result[:result]).to eq("left")

      result = compiled.invoke({ input: "right" })
      expect(result[:result]).to eq("right")
    end

    it "supports reducer-based state aggregation" do
      schema = GraphAgent::State::Schema.new
      schema.field(:items, reducer: ->(a, b) { Array(a) + Array(b) }, default: [])

      graph = GraphAgent::Graph::StateGraph.new(schema)
      graph.add_node("a") { |_s| { items: [1] } }
      graph.add_node("b") { |_s| { items: [2] } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", "b")
      graph.add_edge("b", GraphAgent::END_NODE)

      result = graph.compile.invoke({})
      expect(result[:items]).to eq([1, 2])
    end

    it "works with nil schema (bare hash state)" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") { |_s| { foo: "bar" } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      result = graph.compile.invoke({ initial: true })
      expect(result[:foo]).to eq("bar")
      expect(result[:initial]).to eq(true)
    end

    it "works with Hash-based schema" do
      graph = GraphAgent::Graph::StateGraph.new({ count: { default: 0 } })
      graph.add_node("inc") { |s| { count: s[:count] + 1 } }
      graph.add_edge(GraphAgent::START, "inc")
      graph.add_edge("inc", GraphAgent::END_NODE)

      result = graph.compile.invoke({})
      expect(result[:count]).to eq(1)
    end
  end

  describe "error handling" do
    it "raises GraphRecursionError when limit exceeded" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("loop") { |s| { count: (s[:count] || 0) + 1 } }
      graph.add_edge(GraphAgent::START, "loop")
      graph.add_conditional_edges("loop", ->(_s) { "loop" })

      compiled = graph.compile

      expect { compiled.invoke({}, recursion_limit: 3) }
        .to raise_error(GraphAgent::GraphRecursionError, /Recursion limit/)
    end

    it "raises NodeExecutionError wrapping node errors" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("bad") { |_s| raise "boom" }
      graph.add_edge(GraphAgent::START, "bad")
      graph.add_edge("bad", GraphAgent::END_NODE)

      compiled = graph.compile

      expect { compiled.invoke({}) }
        .to raise_error(GraphAgent::NodeExecutionError) { |e|
          expect(e.node_name).to eq("bad")
          expect(e.original_error.message).to eq("boom")
        }
    end
  end

  describe "Command routing" do
    it "follows Command goto" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("router") { |_s| GraphAgent::Command.new(goto: ["target"]) }
      graph.add_node("target") { |_s| { reached: true } }
      graph.add_node("other") { |_s| { reached: false } }

      graph.add_edge(GraphAgent::START, "router")
      graph.add_conditional_edges("router", ->(_s) { GraphAgent::END_NODE.to_s })
      graph.add_edge("target", GraphAgent::END_NODE)
      graph.add_edge("other", GraphAgent::END_NODE)

      result = graph.compile.invoke({})
      expect(result[:reached]).to eq(true)
    end

    it "applies Command state update" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("cmd_node") do |_s|
        GraphAgent::Command.new(
          update: { from_command: "yes" },
          goto: [GraphAgent::END_NODE.to_s]
        )
      end

      graph.add_edge(GraphAgent::START, "cmd_node")
      graph.add_conditional_edges("cmd_node", ->(_s) { GraphAgent::END_NODE.to_s })

      result = graph.compile.invoke({})
      expect(result[:from_command]).to eq("yes")
    end
  end

  describe "Send for map-reduce" do
    it "executes Send objects returned from a node" do
      schema = GraphAgent::State::Schema.new
      schema.field(:results, reducer: ->(a, b) { Array(a) + Array(b) }, default: [])

      graph = GraphAgent::Graph::StateGraph.new(schema)
      graph.add_node("fan_out") do |_s|
        [
          { results: ["start"] },
          GraphAgent::Send.new("worker", { task: 1 }),
          GraphAgent::Send.new("worker", { task: 2 })
        ]
      end
      graph.add_node("worker") { |_s| { results: ["worked"] } }

      graph.add_edge(GraphAgent::START, "fan_out")
      graph.add_edge("fan_out", GraphAgent::END_NODE)
      graph.add_edge("worker", GraphAgent::END_NODE)

      result = graph.compile.invoke({})
      expect(result[:results]).to include("start")
      expect(result[:results].count("worked")).to eq(2)
    end
  end

  describe "#stream" do
    let(:compiled) { build_linear_graph.compile }

    it "yields state after each step with :values mode" do
      states = []
      compiled.stream({ value: "" }, stream_mode: :values) { |s| states << s }

      expect(states.length).to be >= 3
      expect(states.last[:value]).to eq("abc")
    end

    it "yields per-node updates with :updates mode" do
      updates = []
      compiled.stream({ value: "" }, stream_mode: :updates) { |u| updates << u }

      expect(updates).not_to be_empty
      expect(updates.any? { |u| u.key?("a") }).to be true
    end

    it "returns an Enumerator when no block is given" do
      enum = compiled.stream({ value: "" }, stream_mode: :values)

      expect(enum).to be_a(Enumerator)
      results = enum.to_a
      expect(results.last[:value]).to eq("abc")
    end
  end

  describe "interrupts" do
    it "interrupts before a node" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") { |_s| { step: "a" } }
      graph.add_node("b") { |_s| { step: "b" } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", "b")
      graph.add_edge("b", GraphAgent::END_NODE)

      saver = GraphAgent::Checkpoint::InMemorySaver.new
      compiled = graph.compile(
        checkpointer: saver,
        interrupt_before: ["b"]
      )

      expect do
        compiled.invoke({}, config: { configurable: { thread_id: "t1" } })
      end.to raise_error(GraphAgent::GraphInterrupt) { |e|
        expect(e.interrupts.first.value).to include("before")
      }
    end

    it "interrupts after a node" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") { |_s| { step: "a" } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      saver = GraphAgent::Checkpoint::InMemorySaver.new
      compiled = graph.compile(
        checkpointer: saver,
        interrupt_after: ["a"]
      )

      expect do
        compiled.invoke({}, config: { configurable: { thread_id: "t1" } })
      end.to raise_error(GraphAgent::GraphInterrupt) { |e|
        expect(e.interrupts.first.value).to include("after")
      }
    end
  end

  describe "checkpointing" do
    let(:saver) { GraphAgent::Checkpoint::InMemorySaver.new }
    let(:config) { { configurable: { thread_id: "t1" } } }

    it "saves and restores state" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") { |s| { count: (s[:count] || 0) + 1 } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      compiled = graph.compile(checkpointer: saver)
      compiled.invoke({ count: 0 }, config: config)

      result = compiled.invoke({ count: 0 }, config: config)
      expect(result[:count]).to be >= 1
    end

    it "get_state returns StateSnapshot" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") { |_s| { value: "done" } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      compiled = graph.compile(checkpointer: saver)
      compiled.invoke({}, config: config)

      snapshot = compiled.get_state(config)
      expect(snapshot).to be_a(GraphAgent::StateSnapshot)
      expect(snapshot.values[:value]).to eq("done")
    end

    it "update_state modifies checkpoint" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") { |_s| { value: "original" } }
      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", GraphAgent::END_NODE)

      compiled = graph.compile(checkpointer: saver)
      compiled.invoke({}, config: config)

      compiled.update_state(config, { value: "modified" })

      snapshot = compiled.get_state(config)
      expect(snapshot.values[:value]).to eq("modified")
    end
  end

  describe "deep dup prevents state mutation between nodes" do
    it "does not leak mutations across nodes" do
      mutations = []

      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("a") do |s|
        s[:leaked] = "mutated"
        { value: "a" }
      end
      graph.add_node("b") do |s|
        mutations << s[:leaked]
        { value: "b" }
      end

      graph.add_edge(GraphAgent::START, "a")
      graph.add_edge("a", "b")
      graph.add_edge("b", GraphAgent::END_NODE)

      graph.compile.invoke({})
      expect(mutations.first).to be_nil
    end
  end
end
