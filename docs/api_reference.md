# API Reference

Complete reference for all public classes, methods, and constants.

---

## Constants

Defined in `lib/graph_agent/constants.rb`.

| Constant | Value | Description |
|----------|-------|-------------|
| `GraphAgent::START` | `:"__start__"` | Virtual entry point; edges from START define where execution begins |
| `GraphAgent::END_NODE` | `:"__end__"` | Virtual terminal node; routing here stops execution |
| `GraphAgent::TAG_NOSTREAM` | `:nostream` | Tag to suppress streaming for a node |
| `GraphAgent::TAG_HIDDEN` | `:"langsmith:hidden"` | Tag to hide a node from tracing |

---

## GraphAgent::Graph::StateGraph

Defined in `lib/graph_agent/graph/state_graph.rb`.

The primary graph builder. Define nodes, edges, and conditional routing, then
compile into an executable graph.

### Constructor

```ruby
StateGraph.new(schema = nil, input_schema: nil, output_schema: nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `schema` | `Schema`, `Hash`, or `nil` | State schema defining fields, reducers, and defaults |
| `input_schema:` | `Schema`/`nil` | Input-only schema (stored, not yet enforced) |
| `output_schema:` | `Schema`/`nil` | Output-only schema (stored, not yet enforced) |

Hash schemas are auto-converted to `Schema` objects (see [State](state.md)).

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `schema` | `Schema` | The normalized state schema |
| `nodes` | `Hash{String => Node}` | Registered nodes by name |
| `edges` | `Set<Edge>` | Registered static edges |
| `branches` | `Hash{String => Hash{String => ConditionalEdge}}` | Conditional edges by source |
| `waiting_edges` | `Set<[Array<String>, String]>` | Multi-source waiting edges |

### Methods

#### `add_node(name, action = nil, metadata: nil, retry_policy: nil, cache_policy: nil, &block)`

Add a node to the graph.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | String/Symbol | Node name (must be unique, not reserved) |
| `action` | Proc/callable/nil | The node function; can also be passed as a block |
| `metadata:` | Hash/nil | Arbitrary metadata attached to the node |
| `retry_policy:` | `RetryPolicy`/nil | Retry configuration for transient failures |
| `cache_policy:` | `CachePolicy`/nil | Cache configuration |

Returns `self` for chaining.

Raises `InvalidGraphError` if:
- No action provided
- Name already exists
- Name is reserved (`START` or `END_NODE`)

```ruby
graph.add_node("process") do |state|
  { result: compute(state[:input]) }
end

graph.add_node("fetch", method(:fetch_data), retry_policy: policy)
```

#### `add_edge(start_key, end_key)`

Add a directed edge between two nodes.

| Parameter | Type | Description |
|-----------|------|-------------|
| `start_key` | String/Symbol/Array | Source node (or array for waiting edges) |
| `end_key` | String/Symbol | Target node |

Returns `self` for chaining.

When `start_key` is an Array, creates a **waiting edge** that fires only when
all source nodes have executed.

Raises `InvalidGraphError` if `END_NODE` is used as source or `START` as
target.

```ruby
graph.add_edge("a", "b")
graph.add_edge(GraphAgent::START, "first")
graph.add_edge("last", GraphAgent::END_NODE)
graph.add_edge(["fetch_a", "fetch_b"], "merge")
```

#### `add_conditional_edges(source, path, path_map = nil)`

Add a conditional edge that routes based on state.

| Parameter | Type | Description |
|-----------|------|-------------|
| `source` | String/Symbol | Source node name |
| `path` | Proc/callable | Function `(state) → target` or `(state, config) → target` |
| `path_map` | Hash/nil | Maps path return values to node names |

Returns `self` for chaining.

```ruby
graph.add_conditional_edges("router", ->(state) { state[:route] })

graph.add_conditional_edges(
  "classifier",
  ->(state) { state[:category] },
  { "a" => "handler_a", "b" => "handler_b", default: "fallback" }
)
```

#### `add_sequence(nodes)`

Add a linear sequence of nodes with edges between consecutive pairs.

| Parameter | Type | Description |
|-----------|------|-------------|
| `nodes` | Array | Array of `[name, action]` pairs, callables, or existing node names |

Returns `self` for chaining.

```ruby
graph.add_sequence([
  ["step1", ->(s) { { x: 1 } }],
  ["step2", ->(s) { { x: s[:x] + 1 } }]
])
```

#### `set_entry_point(node_name)`

Shorthand for `add_edge(START, node_name)`.

#### `set_finish_point(node_name)`

Shorthand for `add_edge(node_name, END_NODE)`.

#### `set_conditional_entry_point(path, path_map = nil)`

Shorthand for `add_conditional_edges(START, path, path_map)`.

#### `compile(checkpointer: nil, interrupt_before: nil, interrupt_after: nil, debug: false)`

Validate the graph and return a `CompiledStateGraph`.

| Parameter | Type | Description |
|-----------|------|-------------|
| `checkpointer:` | `BaseSaver`/nil | Checkpoint saver for persistence |
| `interrupt_before:` | Array/nil | Node names to interrupt before |
| `interrupt_after:` | Array/nil | Node names to interrupt after |
| `debug:` | Boolean | Enable debug mode |

Raises `InvalidGraphError` if validation fails.

```ruby
app = graph.compile(
  checkpointer: GraphAgent::Checkpoint::InMemorySaver.new,
  interrupt_before: ["review"]
)
```

---

## GraphAgent::Graph::CompiledStateGraph

Defined in `lib/graph_agent/graph/compiled_state_graph.rb`.

The compiled, executable form of a graph. Implements the Pregel execution
model.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DEFAULT_RECURSION_LIMIT` | `25` | Default maximum supersteps |

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `builder` | `StateGraph` | The original graph builder |
| `checkpointer` | `BaseSaver`/nil | The checkpoint saver |

### Methods

#### `invoke(input, config: {}, recursion_limit: DEFAULT_RECURSION_LIMIT)`

Run the graph to completion and return the final state.

| Parameter | Type | Description |
|-----------|------|-------------|
| `input` | Hash/nil | Initial state values; `nil` to resume from checkpoint |
| `config:` | Hash | Config with `{ configurable: { thread_id: ... } }` |
| `recursion_limit:` | Integer | Maximum supersteps before raising `GraphRecursionError` |

Returns a Hash of the final state.

Raises:
- `GraphRecursionError` if the limit is exceeded
- `GraphInterrupt` if an interrupt fires
- `NodeExecutionError` if a node raises

```ruby
result = app.invoke({ messages: [{ role: "user", content: "Hi" }] })
result = app.invoke({ query: "hello" }, config: config, recursion_limit: 50)
result = app.invoke(nil, config: config)  # resume from checkpoint
```

#### `stream(input, config: {}, recursion_limit: DEFAULT_RECURSION_LIMIT, stream_mode: :values, &block)`

Stream execution events. See [Streaming](streaming.md).

| Parameter | Type | Description |
|-----------|------|-------------|
| `input` | Hash/nil | Initial state values |
| `config:` | Hash | Config hash |
| `recursion_limit:` | Integer | Maximum supersteps |
| `stream_mode:` | Symbol | `:values`, `:updates`, or `:debug` |
| `&block` | Block | Event handler; omit for Enumerator |

Returns `Enumerator` if no block given; `nil` otherwise.

```ruby
app.stream(input, stream_mode: :values) { |state| puts state }
events = app.stream(input, stream_mode: :updates)
```

#### `get_state(config)`

Retrieve the current state snapshot for a thread.

| Parameter | Type | Description |
|-----------|------|-------------|
| `config` | Hash | Config with `thread_id` |

Returns `StateSnapshot` or `nil`.

```ruby
snapshot = app.get_state(config)
snapshot.values     # => { messages: [...] }
snapshot.next_nodes # => ["process"]
```

#### `update_state(config, values, as_node: nil)`

Manually update the state of a thread.

| Parameter | Type | Description |
|-----------|------|-------------|
| `config` | Hash | Config with `thread_id` |
| `values` | Hash | State updates to apply |
| `as_node:` | String/nil | Reserved; node to attribute the update to |

Returns the new checkpoint config Hash, or `nil`.

```ruby
app.update_state(config, { approved: true })
```

#### `get_graph`

Return the graph structure as a Hash.

```ruby
app.get_graph
# => { nodes: ["a", "b"], edges: [["__start__", "a"], ["a", "b"]] }
```

---

## GraphAgent::Graph::MessageGraph

Defined in `lib/graph_agent/graph/message_graph.rb`.

A convenience subclass of `StateGraph` pre-configured with a `messages` field
using the `add_messages` reducer.

### Constructor

```ruby
MessageGraph.new
```

No arguments. Internally creates a `MessagesState` schema with:

```ruby
field :messages, type: Array, reducer: Reducers.method(:add_messages), default: []
```

```ruby
graph = GraphAgent::Graph::MessageGraph.new
graph.add_node("chat") { |s| { messages: [{ role: "ai", content: "Hi" }] } }
graph.set_entry_point("chat")
graph.set_finish_point("chat")
app = graph.compile
```

---

## GraphAgent::Graph::MessagesState

Defined in `lib/graph_agent/graph/message_graph.rb`.

A `Schema` subclass with a single `:messages` field. Used internally by
`MessageGraph`.

---

## GraphAgent::State::Schema

Defined in `lib/graph_agent/state/schema.rb`.

DSL for defining state fields, types, reducers, and defaults.

### Constructor

```ruby
Schema.new(&block)
```

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `fields` | `Hash{Symbol => Field}` | Registered fields |

### Methods

#### `field(name, type: nil, reducer: nil, default: nil)`

Define a state field.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | String/Symbol | Field name |
| `type:` | Class/nil | Type annotation (not enforced) |
| `reducer:` | Proc/nil | `(current, new) → merged` |
| `default:` | Object/nil | Initial value (duplicated per invocation) |

#### `initial_state`

Returns a Hash of field names to duplicated defaults.

```ruby
schema.initial_state  # => { messages: [], count: 0 }
```

#### `apply(state, updates)`

Apply updates to state using reducers. Mutates and returns `state`.

### Schema::Field

A `Data.define(:name, :type, :reducer, :default)` value object.

---

## GraphAgent::Reducers

Defined in `lib/graph_agent/reducers.rb`.

### Constants

| Constant | Lambda | Description |
|----------|--------|-------------|
| `ADD` | `(a, b) → a + b` | Concatenation / addition |
| `APPEND` | `(a, b) → Array(a) + Array(b)` | Array append |
| `MERGE` | `(a, b) → a.merge(b)` | Hash merge |
| `REPLACE` | `(_, b) → b` | Always replace |

### Module Methods

#### `add_messages(existing, new_messages)`

Smart message reducer. Matches by `:id` key — updates existing messages
in-place, appends new ones.

| Parameter | Type | Description |
|-----------|------|-------------|
| `existing` | Array | Current messages |
| `new_messages` | Array | New messages to merge |

Returns a new Array.

---

## GraphAgent::Send

Defined in `lib/graph_agent/types/send.rb`.

Routes execution to a specific node with custom arguments.

### Constructor

```ruby
Send.new(node, arg)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `node` | String/Symbol | Target node name (converted to String) |
| `arg` | Object | Argument passed as state override |

### Attributes

| Attribute | Type |
|-----------|------|
| `node` | String |
| `arg` | Object |

### Methods

| Method | Description |
|--------|-------------|
| `==` / `eql?` | Equality by `node` and `arg` |
| `hash` | Hash code |
| `to_s` / `inspect` | `"Send(node=..., arg=...)"` |

---

## GraphAgent::Command

Defined in `lib/graph_agent/types/command.rb`.

Combines state updates with routing decisions.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `PARENT` | `:__parent__` | Sentinel for routing to parent graph |

### Constructor

```ruby
Command.new(graph: nil, update: nil, resume: nil, goto: [])
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `graph:` | Object/nil | Target subgraph (reserved) |
| `update:` | Hash/nil | State updates to apply |
| `resume:` | Object/nil | Resume value for interrupt workflows |
| `goto:` | String/Symbol/Send/Array | Next node(s) to route to |

### Attributes

| Attribute | Type |
|-----------|------|
| `graph` | Object/nil |
| `update` | Hash/nil |
| `resume` | Object/nil |
| `goto` | Array |

### Methods

| Method | Description |
|--------|-------------|
| `to_s` / `inspect` | `"Command(update=..., goto=...)"` |

---

## GraphAgent::Interrupt

Defined in `lib/graph_agent/types/interrupt.rb`.

Represents a single interrupt event.

### Constructor

```ruby
Interrupt.new(value, id: nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `value` | Object | Description of the interrupt |
| `id:` | String/nil | Unique ID (auto-generated UUID if nil) |

### Attributes

| Attribute | Type |
|-----------|------|
| `value` | Object |
| `id` | String |

### Methods

| Method | Description |
|--------|-------------|
| `==` / `eql?` | Equality by `id` and `value` |
| `hash` | Hash code |
| `to_s` / `inspect` | `"Interrupt(value=..., id=...)"` |

---

## GraphAgent::RetryPolicy

Defined in `lib/graph_agent/types/retry_policy.rb`.

Configures automatic retries with exponential backoff.

### Constructor

```ruby
RetryPolicy.new(
  initial_interval: 0.5,
  backoff_factor: 2.0,
  max_interval: 128.0,
  max_attempts: 3,
  jitter: true,
  retry_on: StandardError
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `initial_interval:` | Float | `0.5` | Seconds before first retry |
| `backoff_factor:` | Float | `2.0` | Multiplier per attempt |
| `max_interval:` | Float | `128.0` | Maximum interval cap |
| `max_attempts:` | Integer | `3` | Total attempts |
| `jitter:` | Boolean | `true` | Add random jitter |
| `retry_on:` | Class/Array/Proc | `StandardError` | Which errors to retry |

### Attributes

All constructor parameters are exposed as readers.

### Methods

#### `should_retry?(error)`

Returns `true` if the error matches the `retry_on` configuration.

#### `interval_for(attempt)`

Returns the sleep interval (Float) for the given attempt number (0-indexed).

---

## GraphAgent::CachePolicy

Defined in `lib/graph_agent/types/cache_policy.rb`.

Configures caching for node results.

### Constructor

```ruby
CachePolicy.new(key_func: nil, ttl: nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `key_func:` | Proc/nil | Function to compute cache key from state |
| `ttl:` | Numeric/nil | Time-to-live in seconds |

### Attributes

| Attribute | Type |
|-----------|------|
| `key_func` | Proc/nil |
| `ttl` | Numeric/nil |

---

## GraphAgent::StateSnapshot

Defined in `lib/graph_agent/types/state_snapshot.rb`.

Read-only snapshot of graph state returned by `get_state`.

### Constructor

```ruby
StateSnapshot.new(
  values:,
  next_nodes: [],
  config: {},
  metadata: nil,
  created_at: nil,
  parent_config: nil,
  tasks: [],
  interrupts: []
)
```

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `values` | Hash | Current state values |
| `next_nodes` | Array<String> | Nodes that would execute next |
| `config` | Hash | Config including `checkpoint_id` |
| `metadata` | Hash/nil | Step, source, etc. |
| `created_at` | Time/nil | When the snapshot was created |
| `parent_config` | Hash/nil | Config of the parent checkpoint |
| `tasks` | Array | Pending tasks |
| `interrupts` | Array | Active interrupts |

---

## GraphAgent::Checkpoint::BaseSaver

Defined in `lib/graph_agent/checkpoint/base_saver.rb`.

Abstract base class for checkpoint persistence. Subclass and implement all
methods to create a custom saver.

### Methods

#### `get(config)`

Convenience method. Calls `get_tuple(config)` and returns the checkpoint hash,
or `nil`.

#### `get_tuple(config)` (abstract)

Return a `CheckpointTuple` for the given config, or `nil`.

#### `list(config, filter: nil, before: nil, limit: nil)` (abstract)

Return an Array of `CheckpointTuple` matching the criteria.

#### `put(config, checkpoint, metadata, new_versions)` (abstract)

Save a checkpoint. Return the new config hash with `checkpoint_id`.

#### `put_writes(config, writes, task_id)` (abstract)

Save pending writes for a checkpoint.

#### `delete_thread(thread_id)` (abstract)

Delete all data for a thread.

---

## GraphAgent::Checkpoint::CheckpointTuple

Defined in `lib/graph_agent/checkpoint/base_saver.rb`.

A `Data.define` value object for checkpoint data.

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `config` | Hash | required | Config with thread/checkpoint IDs |
| `checkpoint` | Hash | required | Serialized state |
| `metadata` | Hash/nil | `nil` | Step, source, parents |
| `parent_config` | Hash/nil | `nil` | Parent checkpoint config |
| `pending_writes` | Array | `[]` | `[task_id, channel, value]` triples |

---

## GraphAgent::Checkpoint::InMemorySaver

Defined in `lib/graph_agent/checkpoint/in_memory_saver.rb`.

In-memory implementation of `BaseSaver`. Stores data in Ruby Hashes. Data is
lost when the process exits.

### Constructor

```ruby
InMemorySaver.new
```

### Methods

Implements all `BaseSaver` abstract methods:

- `get_tuple(config)` — retrieve by `thread_id` and optional `checkpoint_id`
- `list(config, filter:, before:, limit:)` — list checkpoints newest first
- `put(config, checkpoint, metadata, new_versions)` — store a checkpoint
- `put_writes(config, writes, task_id)` — store pending writes
- `delete_thread(thread_id)` — remove all data for a thread

---

## GraphAgent::Graph::Node

Defined in `lib/graph_agent/graph/node.rb`.

Internal wrapper around a node's callable action.

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | String | Node name |
| `action` | Proc/callable | The node function |
| `metadata` | Hash | Arbitrary metadata |
| `retry_policy` | `RetryPolicy`/nil | Retry configuration |
| `cache_policy` | `CachePolicy`/nil | Cache configuration |

### Methods

#### `call(state, config = {})`

Execute the node action with retry support. Returns the normalized result
(Hash, Command, Send, Array, or nil).

---

## GraphAgent::Graph::Edge

Defined in `lib/graph_agent/graph/edge.rb`.

A static directed edge between two nodes.

### Attributes

| Attribute | Type |
|-----------|------|
| `source` | String |
| `target` | String |

### Methods

| Method | Description |
|--------|-------------|
| `==` / `eql?` | Equality by source and target |
| `hash` | Hash code |

---

## GraphAgent::Graph::ConditionalEdge

Defined in `lib/graph_agent/graph/conditional_edge.rb`.

A dynamic edge that routes based on a callable path function.

### Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `source` | String | Source node |
| `path` | Proc/callable | Routing function |
| `path_map` | Hash/nil | Maps return values to node names |

### Methods

#### `resolve(state, config = {})`

Invoke the path function and map the result. Returns a String (node name),
Array of Strings, or Array of `Send` objects.

---

## Channels

Defined in `lib/graph_agent/channels/`. These are internal types used by the
execution engine.

### GraphAgent::Channels::BaseChannel

Abstract base. Key methods: `get`, `update(values)`, `checkpoint`,
`from_checkpoint(value)`, `available?`, `consume`, `finish`, `copy`.

Sentinel constant: `MISSING` — represents an unset value.

### GraphAgent::Channels::LastValue

Single-value channel. Raises `InvalidUpdateError` if more than one value is
written per step. Constructor: `LastValue.new(key:, default:)`.

### GraphAgent::Channels::BinaryOperatorAggregate

Aggregation channel using a binary operator (reducer). Constructor:
`BinaryOperatorAggregate.new(operator:, key:, default:)`.

### GraphAgent::Channels::EphemeralValue

Single-value channel that resets to `MISSING` between steps. Constructor:
`EphemeralValue.new(key:, guard:)`. When `guard: true` (default), raises
`InvalidUpdateError` on multiple writes.

### GraphAgent::Channels::Topic

Multi-value channel that collects values into an array. Constructor:
`Topic.new(key:, accumulate:)`. When `accumulate: false` (default), values
are cleared between steps.

---

## Error Classes

Defined in `lib/graph_agent/errors.rb`.

| Class | Parent | Description |
|-------|--------|-------------|
| `GraphError` | `StandardError` | Base class for all GraphAgent errors |
| `GraphRecursionError` | `GraphError` | Recursion limit exceeded |
| `InvalidUpdateError` | `GraphError` | Invalid channel update |
| `EmptyChannelError` | `GraphError` | Reading from an empty channel |
| `InvalidGraphError` | `GraphError` | Invalid graph structure (compile-time) |
| `NodeExecutionError` | `GraphError` | Wraps errors raised inside nodes |
| `GraphInterrupt` | `GraphError` | Graph paused by interrupt |
| `EmptyInputError` | `GraphError` | Empty input where input is required |
| `TaskNotFound` | `GraphError` | Referenced task does not exist |

### NodeExecutionError

Extra attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `node_name` | String | Name of the failed node |
| `original_error` | Exception | The wrapped error |

### GraphInterrupt

Extra attributes:

| Attribute | Type | Description |
|-----------|------|-------------|
| `interrupts` | Array<Interrupt> | The interrupt objects |
