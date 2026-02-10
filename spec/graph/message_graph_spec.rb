# frozen_string_literal: true

RSpec.describe GraphAgent::Graph::MessageGraph do
  it "creates a graph with messages state" do
    graph = described_class.new
    expect(graph.schema).to be_a(GraphAgent::Graph::MessagesState)
    expect(graph.schema.fields).to have_key(:messages)
  end

  it "accumulates messages via add_messages reducer" do
    graph = described_class.new
    graph.add_node("a") { |_s| { messages: [{ role: "user", content: "hello" }] } }
    graph.add_node("b") { |_s| { messages: [{ role: "assistant", content: "hi" }] } }
    graph.add_edge(GraphAgent::START, "a")
    graph.add_edge("a", "b")
    graph.add_edge("b", GraphAgent::END_NODE)

    result = graph.compile.invoke({})
    expect(result[:messages].length).to eq(2)
    expect(result[:messages][0][:role]).to eq("user")
    expect(result[:messages][1][:role]).to eq("assistant")
  end

  it "updates messages with matching IDs in place" do
    graph = described_class.new
    graph.add_node("a") { |_s| { messages: [{ id: "m1", role: "user", content: "v1" }] } }
    graph.add_node("b") { |_s| { messages: [{ id: "m1", role: "user", content: "v2" }] } }
    graph.add_edge(GraphAgent::START, "a")
    graph.add_edge("a", "b")
    graph.add_edge("b", GraphAgent::END_NODE)

    result = graph.compile.invoke({})
    expect(result[:messages].length).to eq(1)
    expect(result[:messages][0][:content]).to eq("v2")
  end
end
