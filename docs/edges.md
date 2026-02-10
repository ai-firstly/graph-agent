# Edges

Edges define how control flows between nodes in the graph. GraphAgent supports
several edge types for different routing patterns.

---

## Normal Edges

A **normal edge** creates an unconditional transition from one node to another.

```ruby
graph.add_edge("node_a", "node_b")
```

After `node_a` executes, `node_b` will always execute next.

`add_edge` returns `self`, so calls can be chained:

```ruby
graph.add_edge("a", "b")
     .add_edge("b", "c")
     .add_edge("c", GraphAgent::END_NODE)
```

---

## Entry Points (from START)

Every graph must have at least one entry point — an edge from `START` to a node:

```ruby
graph.add_edge(GraphAgent::START, "first_node")
```

Or use the convenience method:

```ruby
graph.set_entry_point("first_node")
```

Both are equivalent; `set_entry_point` calls `add_edge(START, node_name)`.

---

## Exit Points (to END_NODE)

To terminate the graph, route to `END_NODE`:

```ruby
graph.add_edge("last_node", GraphAgent::END_NODE)
```

Or use the convenience method:

```ruby
graph.set_finish_point("last_node")
```

When all active nodes route to `END_NODE`, the graph stops and returns the
final state.

---

## Conditional Edges

A **conditional edge** routes dynamically based on the current state. Provide a
callable (lambda, proc, or method) that receives state and returns the name of
the next node:

```ruby
router = ->(state) do
  if state[:score] > 0.8
    "approve"
  else
    "reject"
  end
end

graph.add_conditional_edges("evaluate", router)
```

### With a path_map

A `path_map` translates the return value of the routing function to actual node
names. This decouples your routing logic from the graph structure:

```ruby
graph.add_conditional_edges(
  "classifier",
  ->(state) { state[:category] },
  {
    "billing"   => "billing_handler",
    "technical" => "tech_handler",
    "other"     => "general_handler"
  }
)
```

If the path function returns `"billing"`, the graph transitions to
`"billing_handler"`.

A `:default` key in the path_map is used as a fallback:

```ruby
graph.add_conditional_edges(
  "router",
  ->(state) { state[:intent] },
  {
    "buy"     => "purchase_flow",
    "return"  => "return_flow",
    default:    "help_flow"
  }
)
```

### Routing to END_NODE

A conditional edge can terminate the graph by returning `END_NODE`:

```ruby
graph.add_conditional_edges("check", ->(state) {
  state[:done] ? GraphAgent::END_NODE.to_s : "process"
})
```

### Config access

The routing function can accept two arguments to access config:

```ruby
graph.add_conditional_edges("node", ->(state, config) {
  config.dig(:configurable, :model) == "fast" ? "quick_path" : "thorough_path"
})
```

---

## Conditional Entry Points

Route from `START` conditionally:

```ruby
graph.set_conditional_entry_point(
  ->(state) { state[:type] },
  { "chat" => "chat_node", "search" => "search_node" }
)
```

This is equivalent to:

```ruby
graph.add_conditional_edges(GraphAgent::START, path, path_map)
```

---

## Waiting Edges (Multi-Source Synchronization)

A **waiting edge** fires only when **all** source nodes have executed in the
same step. Pass an Array of source nodes:

```ruby
graph.add_edge(["fetch_a", "fetch_b"], "merge")
```

Here `"merge"` will only execute once both `"fetch_a"` and `"fetch_b"` have
completed in the same superstep. This is useful for fan-in / join patterns.

---

## Sequences

`add_sequence` is a shorthand for creating a chain of nodes with normal edges
between them:

```ruby
graph.add_sequence([
  ["step1", ->(state) { { data: "raw" } }],
  ["step2", ->(state) { { data: state[:data] + "_cleaned" } }],
  ["step3", ->(state) { { data: state[:data] + "_validated" } }]
])
```

This is equivalent to:

```ruby
graph.add_node("step1", ->(state) { { data: "raw" } })
graph.add_node("step2", ->(state) { { data: state[:data] + "_cleaned" } })
graph.add_node("step3", ->(state) { { data: state[:data] + "_validated" } })
graph.add_edge("step1", "step2")
graph.add_edge("step2", "step3")
```

You still need to add entry and exit edges yourself:

```ruby
graph.add_edge(GraphAgent::START, "step1")
graph.add_edge("step3", GraphAgent::END_NODE)
```

Sequence items can be:

- `[name, action]` — a two-element array with node name and callable.
- A callable with a `.name` method (e.g., a method reference) — the name is
  inferred automatically.
- A string — references an already-added node by name.

---

## Validation Rules

At compile time, the graph validates:

1. **Entry point exists** — at least one edge from `START` or a conditional
   entry point.
2. **Edge references are valid** — every source/target in an edge must be a
   known node, `START`, or `END_NODE`.
3. **No dead-end nodes** — every node must have at least one outgoing edge or
   conditional edge.

Violations raise `InvalidGraphError`.

---

## Complete Example

```ruby
require "graph_agent"

schema = GraphAgent::State::Schema.new do
  field :query, type: String
  field :results, type: Array, reducer: GraphAgent::Reducers::ADD, default: []
  field :route, type: String
end

graph = GraphAgent::Graph::StateGraph.new(schema)

graph.add_node("classify") do |state|
  route = state[:query].include?("weather") ? "weather" : "general"
  { route: route }
end

graph.add_node("weather") do |state|
  { results: ["Weather: sunny, 72°F"] }
end

graph.add_node("general") do |state|
  { results: ["I can help with that!"] }
end

graph.add_edge(GraphAgent::START, "classify")
graph.add_conditional_edges(
  "classify",
  ->(state) { state[:route] },
  { "weather" => "weather", "general" => "general" }
)
graph.add_edge("weather", GraphAgent::END_NODE)
graph.add_edge("general", GraphAgent::END_NODE)

app = graph.compile
result = app.invoke({ query: "What's the weather?" })
puts result[:results]
# => ["Weather: sunny, 72°F"]
```
