# Send & Command

GraphAgent provides two types for advanced routing beyond simple edges:
`Send` for fan-out/fan-in (map-reduce) patterns, and `Command` for combining
state updates with routing decisions.

---

## Send

`GraphAgent::Send` dispatches work to a specific node with custom input. It is
primarily used inside conditional edge functions to create **map-reduce**
patterns.

### Constructor

```ruby
GraphAgent::Send.new(node, arg)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `node` | String/Symbol | Target node name |
| `arg` | Hash | State updates to apply before executing the target node |

### Fan-Out (Map)

Return an array of `Send` objects from a conditional edge to fan out work
across multiple invocations of the same (or different) nodes:

```ruby
schema = GraphAgent::State::Schema.new do
  field :subjects, type: Array, default: []
  field :jokes, type: Array, reducer: GraphAgent::Reducers::ADD, default: []
end

graph = GraphAgent::Graph::StateGraph.new(schema)

graph.add_node("get_subjects") do |state|
  { subjects: ["cats", "dogs", "programming"] }
end

graph.add_node("generate_joke") do |state|
  subject = state[:subjects].first
  { jokes: ["Why did the #{subject} cross the road? ..."] }
end

fan_out = ->(state) do
  state[:subjects].map do |subject|
    GraphAgent::Send.new("generate_joke", { subjects: [subject] })
  end
end

graph.add_edge(GraphAgent::START, "get_subjects")
graph.add_conditional_edges("get_subjects", fan_out)
graph.add_edge("generate_joke", GraphAgent::END_NODE)

app = graph.compile
result = app.invoke({})
puts result[:jokes]
```

Each `Send` triggers a separate execution of `"generate_joke"` with a different
subject. All results are aggregated back via the `:jokes` reducer.

### Fan-In (Reduce)

Fan-in happens automatically: all `Send` targets write to the same shared
state, and reducers aggregate the results. You can also use
[waiting edges](edges.md#waiting-edges-multi-source-synchronization) to
synchronize before a downstream node.

---

## Command

`GraphAgent::Command` combines a **state update** with a **routing decision**
in a single return value from a node.

### Constructor

```ruby
GraphAgent::Command.new(
  graph: nil,        # reserved for subgraph routing
  update: nil,       # Hash of state updates to apply
  resume: nil,       # resume value (for interrupt workflows)
  goto: []           # String, Symbol, Send, or Array thereof — next node(s)
)
```

### Basic Usage

Return a `Command` from a node to update state and route simultaneously:

```ruby
graph.add_node("router") do |state|
  target = state[:intent] == "buy" ? "purchase" : "browse"
  GraphAgent::Command.new(
    update: { routed: true, route: target },
    goto: target
  )
end
```

### Goto with Multiple Targets

`goto` accepts an array to route to multiple nodes in the next step:

```ruby
graph.add_node("fork") do |state|
  GraphAgent::Command.new(
    goto: ["analyze", "log"]
  )
end
```

### Goto with Send

You can mix `Send` objects in `goto` for dynamic fan-out:

```ruby
graph.add_node("dispatch") do |state|
  sends = state[:tasks].map do |task|
    GraphAgent::Send.new("worker", { current_task: task })
  end
  GraphAgent::Command.new(goto: sends)
end
```

### Update Without Routing

If you only need state updates (with routing handled by normal edges), use a
plain Hash return instead of `Command`. Use `Command` specifically when you
need the node to **control routing**.

---

## When to Use Command vs Conditional Edges

| Use Case | Recommended |
|----------|-------------|
| Route based on state, node doesn't modify state | Conditional edge |
| Route based on state **and** modify state atomically | `Command` |
| Fan-out to multiple instances of the same node | `Send` via conditional edge |
| Fan-out with per-instance state modifications | `Command` with `Send` in `goto` |
| Simple sequential flow | Normal edge |

### Command vs Conditional Edge Example

**Conditional edge** — routing logic is separate from the node:

```ruby
graph.add_node("classify") do |state|
  { category: detect_category(state[:input]) }
end

graph.add_conditional_edges("classify", ->(state) {
  state[:category]
}, { "a" => "handler_a", "b" => "handler_b" })
```

**Command** — routing logic is inside the node:

```ruby
graph.add_node("classify") do |state|
  category = detect_category(state[:input])
  GraphAgent::Command.new(
    update: { category: category },
    goto: "handler_#{category}"
  )
end

# Still need outgoing edges for validation — use conditional edges
# that won't actually be reached, or structure so that Command targets
# are valid node names.
```

---

## Complete Map-Reduce Example

```ruby
require "graph_agent"

schema = GraphAgent::State::Schema.new do
  field :urls, type: Array, default: []
  field :pages, type: Array, reducer: GraphAgent::Reducers::ADD, default: []
  field :summary, type: String
end

graph = GraphAgent::Graph::StateGraph.new(schema)

graph.add_node("plan") do |state|
  { urls: ["https://example.com/a", "https://example.com/b"] }
end

graph.add_node("fetch") do |state|
  url = state[:urls].first
  { pages: ["Content from #{url}"] }
end

graph.add_node("summarize") do |state|
  { summary: "Summarized #{state[:pages].length} pages" }
end

fan_out_fetches = ->(state) do
  state[:urls].map { |url| GraphAgent::Send.new("fetch", { urls: [url] }) }
end

graph.add_edge(GraphAgent::START, "plan")
graph.add_conditional_edges("plan", fan_out_fetches)
graph.add_edge("fetch", "summarize")
graph.add_edge("summarize", GraphAgent::END_NODE)

app = graph.compile
result = app.invoke({})
puts result[:summary]
```
