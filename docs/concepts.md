# Core Concepts

## Graphs

A **graph** is a directed workflow of nodes connected by edges. GraphAgent provides
`StateGraph` as the primary graph builder and `MessageGraph` as a convenience
subclass for chat-oriented workflows.

```ruby
graph = GraphAgent::Graph::StateGraph.new(schema)
```

A graph is built in three phases:

1. **Define** — add nodes, edges, and conditional edges.
2. **Compile** — validate the graph and produce a `CompiledStateGraph`.
3. **Execute** — invoke or stream the compiled graph.

---

## State

State is the shared data structure that flows through the graph. Every node
reads state and returns updates that are applied back to it.

State is defined by a **Schema** that declares fields, their types, optional
reducers, and defaults.

```ruby
schema = GraphAgent::State::Schema.new do
  field :messages, type: Array, reducer: GraphAgent::Reducers::ADD, default: []
  field :count, type: Integer, default: 0
end
```

### Last-value semantics

Fields without a reducer use **last-value** semantics: the most recent write wins.

```ruby
field :status  # no reducer → last write wins
```

### Aggregation semantics

Fields with a reducer **accumulate** values. The reducer is called as
`reducer.call(current_value, new_value)` each time the field is updated.

```ruby
field :messages, reducer: GraphAgent::Reducers::ADD, default: []
```

See [State Management](state.md) for the full DSL and all built-in reducers.

---

## Nodes

A **node** is a callable (block, lambda, method) that receives the current
state and optionally a config hash, then returns a Hash of state updates.

```ruby
graph.add_node("greet") do |state|
  { greeting: "Hello, #{state[:name]}!" }
end
```

Nodes can also return `Command` or `Send` objects for advanced routing (see
[Send & Command](send_and_command.md)).

### Arity

- **0 args** — `->() { { key: value } }` — no state access.
- **1 arg** — `->(state) { ... }` — reads state.
- **2 args** — `->(state, config) { ... }` — reads state and config.

### Retry

Nodes can have a `RetryPolicy` for automatic retries on failure:

```ruby
policy = GraphAgent::RetryPolicy.new(max_attempts: 3)
graph.add_node("flaky", method(:call_api), retry_policy: policy)
```

---

## Edges

Edges define transitions between nodes.

### Normal edges

```ruby
graph.add_edge("node_a", "node_b")
```

### Conditional edges

Route dynamically based on state:

```ruby
graph.add_conditional_edges("router", ->(state) {
  state[:route]
})
```

### Entry and exit

Every graph needs at least one entry point from `START` and typically ends at `END_NODE`:

```ruby
graph.add_edge(GraphAgent::START, "first_node")
graph.add_edge("last_node", GraphAgent::END_NODE)
```

Convenience helpers:

```ruby
graph.set_entry_point("first_node")
graph.set_finish_point("last_node")
```

See [Edges](edges.md) for waiting edges, sequences, conditional entry points,
and more.

---

## Supersteps (Pregel Execution Model)

GraphAgent executes graphs using the **Pregel** (Bulk Synchronous Parallel)
model. Each iteration is called a **superstep**:

```
┌─────────┐
│  PLAN   │  Determine which nodes to run based on edges/state
└────┬────┘
     ▼
┌─────────┐
│ EXECUTE │  Run all active nodes on a frozen snapshot of state
└────┬────┘
     ▼
┌─────────┐
│ UPDATE  │  Apply all node outputs atomically via reducers
└────┬────┘
     ▼
┌──────────┐
│CHECKPOINT│  Save state if a checkpointer is configured
└────┬─────┘
     ▼
┌─────────┐
│ REPEAT  │  Continue until END_NODE is reached or recursion_limit hit
└─────────┘
```

Key properties:

- Nodes within the same superstep see the **same frozen state snapshot**.
- All updates are applied **atomically** after every node in the step finishes.
- A **recursion limit** (default 25) prevents infinite loops.

---

## Channels

Channels are the internal mechanism that stores individual state fields. You
rarely interact with channels directly, but understanding them helps when
debugging:

| Channel | Behavior |
|---------|----------|
| `LastValue` | Stores a single value; errors if updated more than once per step |
| `BinaryOperatorAggregate` | Applies a reducer to aggregate multiple updates |
| `EphemeralValue` | Resets to empty between steps |
| `Topic` | Collects multiple values; optionally accumulates across steps |

See `lib/graph_agent/channels/` for implementation details.

---

## START and END_NODE

Two sentinel constants control graph flow:

| Constant | Value | Purpose |
|----------|-------|---------|
| `GraphAgent::START` | `:"__start__"` | Virtual entry node; edges from START define where execution begins |
| `GraphAgent::END_NODE` | `:"__end__"` | Virtual terminal node; reaching END_NODE stops execution |

```ruby
graph.add_edge(GraphAgent::START, "first")
graph.add_edge("last", GraphAgent::END_NODE)
```

---

## Compilation

Calling `compile` validates the graph and returns a `CompiledStateGraph`:

```ruby
app = graph.compile(
  checkpointer: checkpointer,       # optional persistence
  interrupt_before: ["review"],      # optional human-in-the-loop
  interrupt_after: ["draft"],        # optional human-in-the-loop
  debug: false                       # enable debug events
)
```

Validation checks:

- At least one entry point exists (edge from `START` or conditional entry).
- Every edge references an existing node (or `START`/`END_NODE`).
- Every node has at least one outgoing edge or conditional edge.

If validation fails, an `InvalidGraphError` is raised at compile time.
