# Quickstart

## Installation

Add to your Gemfile:

```ruby
gem "graph_agent"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install graph_agent
```

Requires Ruby >= 3.1.0.

---

## Hello World

The simplest possible graph: one node, in → out.

```ruby
require "graph_agent"

graph = GraphAgent::Graph::StateGraph.new({ greeting: {} })

graph.add_node("greet") do |state|
  { greeting: "Hello, #{state[:name]}!" }
end

graph.add_edge(GraphAgent::START, "greet")
graph.add_edge("greet", GraphAgent::END_NODE)

app = graph.compile
result = app.invoke({ name: "World" })

puts result[:greeting]
# => "Hello, World!"
```

**What happened:**

1. We defined a state with a single field `:greeting` (last-value semantics — no reducer).
2. We added a node `"greet"` that reads `:name` from state and writes `:greeting`.
3. We wired `START → greet → END_NODE`.
4. We compiled and invoked.

---

## Calculator Agent

A more realistic example: a loop that processes arithmetic operations until there are none left.

```ruby
require "graph_agent"

schema = GraphAgent::State::Schema.new do
  field :operations, type: Array, reducer: GraphAgent::Reducers::REPLACE, default: []
  field :results, type: Array, reducer: GraphAgent::Reducers::ADD, default: []
  field :done, type: :boolean, default: false
end

graph = GraphAgent::Graph::StateGraph.new(schema)

graph.add_node("compute") do |state|
  op = state[:operations].first
  remaining = state[:operations][1..]

  answer = case op[:op]
           when "+" then op[:a] + op[:b]
           when "-" then op[:a] - op[:b]
           when "*" then op[:a] * op[:b]
           when "/" then op[:a].to_f / op[:b]
           end

  {
    operations: remaining,
    results: [{ expression: "#{op[:a]} #{op[:op]} #{op[:b]}", answer: answer }],
    done: remaining.empty?
  }
end

should_continue = ->(state) do
  state[:done] ? GraphAgent::END_NODE.to_s : "compute"
end

graph.add_edge(GraphAgent::START, "compute")
graph.add_conditional_edges("compute", should_continue)

app = graph.compile

result = app.invoke({
  operations: [
    { op: "+", a: 2, b: 3 },
    { op: "*", a: 4, b: 5 },
    { op: "-", a: 10, b: 7 }
  ]
})

result[:results].each do |r|
  puts "#{r[:expression]} = #{r[:answer]}"
end
# 2 + 3 = 5
# 4 * 5 = 20
# 10 - 7 = 3
```

---

## Running with Streaming

Instead of waiting for the final result, stream intermediate states:

```ruby
app.stream(
  { operations: [{ op: "+", a: 1, b: 2 }, { op: "*", a: 3, b: 4 }] },
  stream_mode: :updates
) do |updates|
  puts "Step updates: #{updates}"
end
```

Or use an `Enumerator` (no block):

```ruby
events = app.stream(
  { operations: [{ op: "+", a: 1, b: 2 }] },
  stream_mode: :values
)

events.each do |state|
  puts "Results so far: #{state[:results]}"
end
```

---

## Where to Go Next

- [Core Concepts](concepts.md) — understand graphs, state, nodes, edges, and supersteps.
- [State Management](state.md) — deep dive into schemas, reducers, and defaults.
- [Edges](edges.md) — all edge types including conditional and waiting edges.
- [Persistence](persistence.md) — checkpointing and multi-turn conversations.
- [Human-in-the-Loop](human_in_the_loop.md) — interrupt, inspect, modify, resume.
- [API Reference](api_reference.md) — every class and method.
