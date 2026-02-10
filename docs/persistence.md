# Persistence & Checkpointing

Persistence enables multi-turn conversations, fault recovery, and
human-in-the-loop workflows by saving graph state between invocations.

---

## Why Persistence Matters

Without persistence, every `invoke` starts from scratch. With a checkpointer:

- **Multi-turn conversations** — state accumulates across calls using the same
  `thread_id`.
- **Fault tolerance** — if a graph fails mid-execution, the last checkpoint is
  available to resume from.
- **Human-in-the-loop** — interrupts pause execution; the state is saved so a
  human can inspect, modify, and resume.
- **Time travel** — list past checkpoints to replay or debug execution history.

---

## InMemorySaver

`GraphAgent::Checkpoint::InMemorySaver` stores checkpoints in a Ruby Hash. It
is suitable for development, testing, and single-process applications.

```ruby
checkpointer = GraphAgent::Checkpoint::InMemorySaver.new
app = graph.compile(checkpointer: checkpointer)
```

> **Note:** Data is lost when the process exits. For production, implement a
> custom saver backed by a database (see below).

---

## Thread-Based Conversations

A **thread** is identified by `thread_id` in the config. All invocations with
the same `thread_id` share state:

```ruby
config = { configurable: { thread_id: "user-42" } }

# First turn
result1 = app.invoke(
  { messages: [{ role: "user", content: "Hi, I'm Alice" }] },
  config: config
)

# Second turn — state includes messages from the first turn
result2 = app.invoke(
  { messages: [{ role: "user", content: "What's my name?" }] },
  config: config
)
# result2[:messages] contains all messages from both turns
```

Different `thread_id` values create independent conversations:

```ruby
config_a = { configurable: { thread_id: "thread-a" } }
config_b = { configurable: { thread_id: "thread-b" } }

# These are completely independent
app.invoke({ messages: [{ role: "user", content: "Hello" }] }, config: config_a)
app.invoke({ messages: [{ role: "user", content: "Bonjour" }] }, config: config_b)
```

---

## Checkpoint Lifecycle

During execution, checkpoints are saved at specific points with a `source`
metadata field:

| Source | When |
|--------|------|
| `:input` | After initializing state from input, before any nodes run |
| `:loop` | After each superstep completes |
| `:interrupt` | When an interrupt fires (before or after a node) |
| `:exit` | After the graph finishes (reaches `END_NODE`) |
| `:update` | After a manual `update_state` call |

Each checkpoint stores:

- `channel_values` — the full state at that point.
- `next_nodes` — which nodes would execute next.
- `id` — a UUID identifying this checkpoint.

---

## get_state

Retrieve the current state snapshot for a thread:

```ruby
snapshot = app.get_state(config)
```

Returns a `GraphAgent::StateSnapshot` with:

| Attribute | Type | Description |
|-----------|------|-------------|
| `values` | Hash | Current state values |
| `next_nodes` | Array | Nodes that would execute next |
| `config` | Hash | Config including `checkpoint_id` |
| `metadata` | Hash | Step number, source, etc. |
| `parent_config` | Hash/nil | Config of the previous checkpoint |
| `tasks` | Array | Pending tasks |
| `interrupts` | Array | Active interrupts |

```ruby
snapshot = app.get_state(config)
puts snapshot.values[:messages]
puts "Next: #{snapshot.next_nodes}"
puts "Step: #{snapshot.metadata[:step]}"
```

Returns `nil` if no checkpoint exists for the given config.

---

## update_state

Manually modify the state of a thread:

```ruby
app.update_state(config, { approved: true, reviewer: "Alice" })
```

This creates a new checkpoint with the updated state. The metadata `source` is
set to `:update`.

`update_state` respects reducers: if a field has a reducer, the update value is
merged via that reducer, not replaced.

```ruby
# If :messages has an ADD reducer:
app.update_state(config, {
  messages: [{ role: "system", content: "Human approved this action" }]
})
# The new message is appended, not replaced
```

Returns the new checkpoint config (with the new `checkpoint_id`), or `nil` if
no checkpoint exists.

---

## StateSnapshot

`GraphAgent::StateSnapshot` is a read-only object returned by `get_state`:

```ruby
snapshot = app.get_state(config)

snapshot.values       # => { messages: [...], count: 5 }
snapshot.next_nodes   # => ["process"]
snapshot.config       # => { configurable: { thread_id: "t1", checkpoint_id: "..." } }
snapshot.metadata     # => { source: :loop, step: 3 }
snapshot.parent_config # => { configurable: { ... } } or nil
snapshot.created_at   # => Time or nil
snapshot.tasks        # => []
snapshot.interrupts   # => []
```

---

## Listing Checkpoints

`InMemorySaver#list` returns all checkpoints for a thread (most recent first):

```ruby
checkpoints = checkpointer.list(config)

checkpoints.each do |tuple|
  puts "ID: #{tuple.config.dig(:configurable, :checkpoint_id)}"
  puts "Step: #{tuple.metadata[:step]}"
  puts "Source: #{tuple.metadata[:source]}"
  puts "---"
end
```

Options:

```ruby
# Filter by metadata
checkpointer.list(config, filter: { source: :loop })

# Limit results
checkpointer.list(config, limit: 5)

# Before a specific checkpoint
checkpointer.list(config, before: {
  configurable: { checkpoint_id: "some-uuid" }
})
```

---

## Deleting Threads

Remove all checkpoints and writes for a thread:

```ruby
checkpointer.delete_thread("user-42")
```

---

## Implementing a Custom CheckpointSaver

Subclass `GraphAgent::Checkpoint::BaseSaver` and implement four methods:

```ruby
class PostgresSaver < GraphAgent::Checkpoint::BaseSaver
  def get_tuple(config)
    thread_id = config.dig(:configurable, :thread_id)
    checkpoint_id = config.dig(:configurable, :checkpoint_id)

    # Query your database for the checkpoint
    row = db_query(thread_id, checkpoint_id)
    return nil unless row

    GraphAgent::Checkpoint::CheckpointTuple.new(
      config: config,
      checkpoint: row[:checkpoint],
      metadata: row[:metadata],
      parent_config: row[:parent_config],
      pending_writes: row[:pending_writes] || []
    )
  end

  def list(config, filter: nil, before: nil, limit: nil)
    # Return an array of CheckpointTuple, newest first
  end

  def put(config, checkpoint, metadata, new_versions)
    thread_id = config.dig(:configurable, :thread_id)
    checkpoint_id = checkpoint[:id]

    # Insert into your database
    db_insert(thread_id, checkpoint_id, checkpoint, metadata)

    # Return the new config
    {
      configurable: {
        thread_id: thread_id,
        checkpoint_ns: config.dig(:configurable, :checkpoint_ns) || "",
        checkpoint_id: checkpoint_id
      }
    }
  end

  def put_writes(config, writes, task_id)
    # Store pending writes
  end

  def delete_thread(thread_id)
    # Delete all data for the thread
  end
end
```

### CheckpointTuple

`GraphAgent::Checkpoint::CheckpointTuple` is a `Data.define` with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `config` | Hash | Config with `thread_id`, `checkpoint_ns`, `checkpoint_id` |
| `checkpoint` | Hash | Serialized state (`channel_values`, `id`, etc.) |
| `metadata` | Hash/nil | Step, source, parents |
| `parent_config` | Hash/nil | Config pointing to the previous checkpoint |
| `pending_writes` | Array | Pending writes as `[task_id, channel, value]` triples |
