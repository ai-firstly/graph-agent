# Error Handling

GraphAgent defines a hierarchy of error classes for different failure modes.
All errors inherit from `GraphAgent::GraphError`, which inherits from
`StandardError`.

---

## Error Hierarchy

```
StandardError
└── GraphAgent::GraphError
    ├── GraphAgent::GraphRecursionError
    ├── GraphAgent::InvalidUpdateError
    ├── GraphAgent::EmptyChannelError
    ├── GraphAgent::InvalidGraphError
    ├── GraphAgent::NodeExecutionError
    ├── GraphAgent::GraphInterrupt
    ├── GraphAgent::EmptyInputError
    └── GraphAgent::TaskNotFound
```

---

## GraphRecursionError

Raised when the graph exceeds its `recursion_limit` without reaching
`END_NODE`.

```ruby
begin
  app.invoke(input, recursion_limit: 10)
rescue GraphAgent::GraphRecursionError => e
  puts e.message
  # => "Recursion limit of 10 reached without hitting END node"
end
```

The default limit is **25** (`CompiledStateGraph::DEFAULT_RECURSION_LIMIT`).
Increase it for graphs that legitimately need many steps:

```ruby
result = app.invoke(input, recursion_limit: 100)
```

Common causes:

- A conditional edge never routes to `END_NODE`.
- A loop's exit condition is never satisfied.
- The limit is too low for the workload.

---

## InvalidUpdateError

Raised when a channel receives an invalid update. The most common case is a
`LastValue` channel receiving more than one value in a single step:

```ruby
# Two nodes both write to the same last-value field in the same step
# => InvalidUpdateError: "At key 'status': Can receive only one value per step."
```

Also raised by `EphemeralValue` when `guard: true` (the default) and more than
one value is written per step.

---

## NodeExecutionError

Wraps any unhandled exception raised inside a node. Provides access to the
node name and the original error:

```ruby
begin
  app.invoke(input)
rescue GraphAgent::NodeExecutionError => e
  puts "Failed node: #{e.node_name}"
  puts "Original error: #{e.original_error.class}: #{e.original_error.message}"
  puts e.message
  # => "Error in node 'fetch_data': Connection refused"
end
```

`GraphInterrupt` and `GraphRecursionError` raised inside nodes are **not**
wrapped — they propagate directly.

---

## GraphInterrupt

Raised when the graph hits an interrupt point (see
[Human-in-the-Loop](human_in_the_loop.md)). Contains an array of
`Interrupt` objects:

```ruby
begin
  app.invoke(input, config: config)
rescue GraphAgent::GraphInterrupt => e
  puts "#{e.interrupts.length} interrupt(s)"
  e.interrupts.each do |interrupt|
    puts "  #{interrupt.value} (id: #{interrupt.id})"
  end
end
```

---

## EmptyChannelError

Raised when reading from a channel that has no value. This is an internal
error — you typically encounter it only if you access a state field that was
never initialized and has no default.

---

## InvalidGraphError

Raised at **compile time** (when calling `graph.compile`) if the graph
structure is invalid:

```ruby
begin
  app = graph.compile
rescue GraphAgent::InvalidGraphError => e
  puts e.message
end
```

Validation checks:

| Check | Error message |
|-------|---------------|
| No entry point | `"Graph must have an entry point..."` |
| Edge references unknown source | `"Edge references unknown source node '...'"` |
| Edge references unknown target | `"Edge references unknown target node '...'"` |
| Node has no outgoing edges | `"Node '...' has no outgoing edges"` |
| Duplicate node name | `"Node '...' already exists"` |
| Reserved node name | `"Node name '...' is reserved"` |
| END as start node | `"END cannot be a start node"` |
| START as end node | `"START cannot be an end node"` |
| Missing node action | `"Node action must be provided"` |
| Duplicate branch name | `"Branch '...' already exists for node '...'"` |

---

## EmptyInputError

Raised when the graph receives empty input where input is required.

---

## TaskNotFound

Raised when referencing a task that does not exist in the checkpoint.

---

## RetryPolicy

Configure automatic retries for individual nodes to handle transient failures:

```ruby
policy = GraphAgent::RetryPolicy.new(
  initial_interval: 0.5,    # seconds before first retry
  backoff_factor: 2.0,      # multiply interval each attempt
  max_interval: 128.0,      # cap on interval
  max_attempts: 3,           # total attempts (1 initial + 2 retries)
  jitter: true,              # add random jitter to intervals
  retry_on: StandardError    # which errors to retry
)

graph.add_node("api_call", method(:call_api), retry_policy: policy)
```

### retry_on options

| Value | Behavior |
|-------|----------|
| `StandardError` (default) | Retry on any standard error |
| `[Net::ReadTimeout, Timeout::Error]` | Retry only on specific error classes |
| `->(e) { e.message.include?("429") }` | Custom predicate |

### Retry timing

For attempt `n` (0-indexed), the interval is:

```
interval = initial_interval * (backoff_factor ^ n)
interval = min(interval, max_interval)
interval += rand() * interval * 0.1    # if jitter enabled
```

### Example: Retrying API calls

```ruby
retry_policy = GraphAgent::RetryPolicy.new(
  max_attempts: 5,
  initial_interval: 1.0,
  backoff_factor: 2.0,
  retry_on: [Net::ReadTimeout, Net::OpenTimeout]
)

graph.add_node("call_llm", retry_policy: retry_policy) do |state|
  response = call_openai(state[:messages])
  { messages: [response] }
end
```

---

## Comprehensive Error Handling

```ruby
require "graph_agent"

config = { configurable: { thread_id: "t1" } }

begin
  result = app.invoke(input, config: config)
  puts "Success: #{result}"

rescue GraphAgent::GraphInterrupt => e
  puts "Human review needed"
  snapshot = app.get_state(config)
  puts "State: #{snapshot.values}"

rescue GraphAgent::GraphRecursionError
  puts "Graph ran too many steps — check for infinite loops"

rescue GraphAgent::NodeExecutionError => e
  puts "Node '#{e.node_name}' failed: #{e.original_error.message}"

rescue GraphAgent::InvalidUpdateError => e
  puts "State update conflict: #{e.message}"

rescue GraphAgent::GraphError => e
  puts "Graph error: #{e.message}"
end
```
