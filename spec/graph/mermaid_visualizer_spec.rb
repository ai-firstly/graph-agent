# frozen_string_literal: true

require "spec_helper"
require "graph_agent/graph/state_graph"

RSpec.describe GraphAgent::Graph::MermaidVisualizer do
  describe ".render" do
    it "generates Mermaid diagram for simple linear graph" do
      graph = GraphAgent::Graph::StateGraph.new

      graph.add_node("step1") { |state| { count: 1 } }
      graph.add_node("step2") { |state| { count: 2 } }
      graph.add_edge(GraphAgent::START, "step1")
      graph.add_edge("step1", "step2")
      graph.add_edge("step2", GraphAgent::END_NODE)

      mermaid = graph.to_mermaid

      expect(mermaid).to include("graph TD")
      expect(mermaid).to include("__start__")
      expect(mermaid).to include("__end__")
      expect(mermaid).to include("step1")
      expect(mermaid).to include("step2")
      expect(mermaid).to include("-->")
    end

    it "generates Mermaid diagram with conditional edges" do
      graph = GraphAgent::Graph::StateGraph.new

      graph.add_node("router") { |state| {} }
      graph.add_node("handler_a") { |state| {} }
      graph.add_node("handler_b") { |state| {} }

      graph.add_edge(GraphAgent::START, "router")
      graph.add_conditional_edges(
        "router",
        ->(state) { state[:type] },
        { "a" => "handler_a", "b" => "handler_b" }
      )
      graph.add_edge("handler_a", GraphAgent::END_NODE)
      graph.add_edge("handler_b", GraphAgent::END_NODE)

      mermaid = graph.to_mermaid

      expect(mermaid).to include("router")
      expect(mermaid).to include("handler_a")
      expect(mermaid).to include("handler_b")
      expect(mermaid).to include("cond_")
      expect(mermaid).to include("|a|")
      expect(mermaid).to include("|b|")
    end

    it "includes style definitions" do
      graph = GraphAgent::Graph::StateGraph.new
      graph.add_node("node1") { |state| {} }
      graph.add_edge(GraphAgent::START, "node1")
      graph.add_edge("node1", GraphAgent::END_NODE)

      mermaid = graph.to_mermaid

      expect(mermaid).to include("classDef start")
      expect(mermaid).to include("classDef endNode")
      expect(mermaid).to include("classDef node")
      expect(mermaid).to include("classDef condition")
    end

    it "handles conditional edges without path_map" do
      graph = GraphAgent::Graph::StateGraph.new

      graph.add_node("decider") { |state| {} }
      graph.add_node("next_step") { |state| {} }

      graph.add_edge(GraphAgent::START, "decider")
      graph.add_conditional_edges("decider", ->(state) { "next_step" })
      graph.add_edge("next_step", GraphAgent::END_NODE)

      mermaid = graph.to_mermaid

      expect(mermaid).to include("decider")
      expect(mermaid).to include("cond_")
    end
  end
end
