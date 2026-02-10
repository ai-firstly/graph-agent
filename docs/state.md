# State Management

## Overview

State is the shared data structure that every node reads from and writes to.
GraphAgent applies updates atomically after each superstep using **reducers**.

---

## Defining State with Schema DSL

Use `GraphAgent::State::Schema` with a block:

```ruby
schema = GraphAgent::State::Schema.new do
  field :messages,   type: Array,   reducer: GraphAgent::Reducers::ADD, default: []
  field :count,      type: Integer, reducer: GraphAgent::Reducers::ADD, default: 0
  field :status,     type: String
  field :metadata,   type: Hash,    reducer: GraphAgent::Reducers::MERGE, default: {}
end
```

Each `field` call accepts:

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | Symbol/String | Field name (converted to Symbol) |
| `type:` | Class/nil | Optional type annotation (not enforced at runtime) |
| `reducer:` | Proc/nil | Callable `(current, new) → merged`; nil means last-value semantics |
| `default:` | Object/nil | Initial value; duplicated per invocation to avoid shared state |

---

## Defining State with Hash Shorthand

Pass a Hash directly to `StateGraph.new` instead of a `Schema` object:

```ruby
graph = GraphAgent::Graph::StateGraph.new({
  messages: { type: Array, reducer: ->(a, b) { a + b }, default: [] },
  count: { type: Integer, reducer: ->(a, b) { a + b }, default: 0 },
  status: {}  # last-value semantics, no default
})
```

Each key becomes a field name. Values can be:

- A **Hash** with `:type`, `:reducer`, `:default` keys (all optional).
- Any non-Hash value is treated as a field with no options.

---

## Built-in Reducers

Defined in `GraphAgent::Reducers`:

| Reducer | Lambda | Behavior |
|---------|--------|----------|
| `ADD` | `(a, b) → a + b` | Concatenates arrays, adds numbers, joins strings |
| `APPEND` | `(a, b) → Array(a) + Array(b)` | Wraps both sides in arrays then concatenates |
| `MERGE` | `(a, b) → a.merge(b)` | Shallow-merges hashes |
| `REPLACE` | `(_, b) → b` | Always replaces with the new value |

### `add_messages`

A special reducer for chat message lists. It matches messages by `:id` and
replaces existing messages in-place; new messages (without matching IDs) are
appended:

```ruby
field :messages, reducer: GraphAgent::Reducers.method(:add_messages), default: []
```

Example:

```ruby
existing = [
  { id: "1", role: "user", content: "Hi" },
  { id: "2", role: "ai", content: "Hello" }
]

new_msgs = [
  { id: "2", role: "ai", content: "Hello! How can I help?" },  # updates id "2"
  { id: "3", role: "user", content: "Tell me a joke" }          # appended
]

result = GraphAgent::Reducers.add_messages(existing, new_msgs)
# => [
#   { id: "1", role: "user", content: "Hi" },
#   { id: "2", role: "ai", content: "Hello! How can I help?" },
#   { id: "3", role: "user", content: "Tell me a joke" }
# ]
```

---

## Custom Reducers

Any callable that takes two arguments works as a reducer:

```ruby
# Keep only the last N messages
keep_last_10 = ->(existing, new_msgs) do
  (Array(existing) + Array(new_msgs)).last(10)
end

schema = GraphAgent::State::Schema.new do
  field :messages, reducer: keep_last_10, default: []
end
```

```ruby
# Union of sets
set_union = ->(a, b) { (Array(a) | Array(b)) }

schema = GraphAgent::State::Schema.new do
  field :tags, reducer: set_union, default: []
end
```

---

## Initial State and Defaults

When a graph is invoked, `Schema#initial_state` produces the starting state by
duplicating each field's default value:

```ruby
schema = GraphAgent::State::Schema.new do
  field :items, default: []
  field :count, default: 0
end

schema.initial_state
# => { items: [], count: 0 }
```

- Defaults are `.dup`'d to prevent shared mutation between invocations.
- Fields without a default start as `nil`.
- Input values passed to `invoke` are merged on top of the initial state.

---

## How Updates Are Applied

After each superstep, the compiled graph calls `Schema#apply` (or the internal
`_apply_updates` method) for every update returned by the nodes:

```ruby
# Pseudocode for one superstep:
# 1. All nodes run on a frozen snapshot
# 2. Collect updates: { "node_a" => { count: 1 }, "node_b" => { count: 2 } }
# 3. For each update hash, for each key:
#      if field has a reducer  → state[key] = reducer.call(state[key], value)
#      else                    → state[key] = value   (last-value)
```

This means:

- **With a reducer** (`ADD`), two nodes returning `{ count: 1 }` and `{ count: 2 }`
  produce `count = 0 + 1 + 2 = 3` (assuming default 0).
- **Without a reducer**, the last update wins (order depends on iteration of
  the updates hash).

---

## Private / Input / Output Schemas

`StateGraph` accepts `input_schema:` and `output_schema:` parameters:

```ruby
graph = GraphAgent::Graph::StateGraph.new(
  full_schema,
  input_schema: input_only_schema,
  output_schema: output_only_schema
)
```

These are stored on the builder for future use (e.g., input validation and
output filtering) but are not yet enforced at runtime. The main `schema`
parameter defines all fields the graph operates on.
