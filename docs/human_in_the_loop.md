# Human-in-the-Loop

GraphAgent supports pausing graph execution so a human can inspect the state,
approve actions, provide input, or modify state before resuming.

---

## Overview

The human-in-the-loop pattern works in three steps:

1. **Interrupt** — the graph pauses before or after a specific node.
2. **Inspect / Modify** — the human reads the state, optionally modifies it.
3. **Resume** — the graph continues from where it left off.

This requires a **checkpointer** to persist state across the pause.

---

## interrupt_before and interrupt_after

Specify which nodes should trigger interrupts at compile time:

```ruby
checkpointer = GraphAgent::Checkpoint::InMemorySaver.new

app = graph.compile(
  checkpointer: checkpointer,
  interrupt_before: ["human_review"],  # pause BEFORE this node runs
  interrupt_after: ["draft"]           # pause AFTER this node runs
)
```

- `interrupt_before` — pauses **before** the node executes. The node has not
  yet seen or modified state.
- `interrupt_after` — pauses **after** the node executes and its updates are
  applied.

Both accept an array of node name strings or symbols.

---

## Catching GraphInterrupt

When an interrupt fires, the graph raises `GraphAgent::GraphInterrupt`:

```ruby
config = { configurable: { thread_id: "review-1" } }

begin
  result = app.invoke(input, config: config)
  puts "Completed: #{result}"
rescue GraphAgent::GraphInterrupt => e
  puts "Paused with #{e.interrupts.length} interrupt(s)"
  e.interrupts.each do |interrupt|
    puts "  #{interrupt.value}"
  end
end
```

Each interrupt in the `interrupts` array is a `GraphAgent::Interrupt` object:

| Attribute | Type | Description |
|-----------|------|-------------|
| `value` | Object | Description of the interrupt (typically a String) |
| `id` | String | Unique identifier for this interrupt |

---

## Inspecting State with get_state

After an interrupt, inspect the saved state:

```ruby
snapshot = app.get_state(config)

puts "Current state: #{snapshot.values}"
puts "Next nodes: #{snapshot.next_nodes}"
puts "Step: #{snapshot.metadata[:step]}"
```

This lets the human review what the graph has computed so far and decide
whether to approve, modify, or reject.

---

## Modifying State with update_state

The human can modify state before resuming:

```ruby
app.update_state(config, {
  approved: true,
  reviewer_notes: "Looks good, proceed"
})
```

Updates respect reducers — if a field has a reducer, the update is merged
through it.

---

## Resuming Execution

Resume by calling `invoke` with `nil` input and the same config:

```ruby
result = app.invoke(nil, config: config)
```

The graph picks up from the last checkpoint and continues execution.

---

## Wildcard Interrupts

Use `"*"` to interrupt before or after **every** node:

```ruby
app = graph.compile(
  checkpointer: checkpointer,
  interrupt_before: ["*"]
)
```

This is useful for step-by-step debugging or approval workflows where every
action needs human review.

---

## Full Example

```ruby
require "graph_agent"

schema = GraphAgent::State::Schema.new do
  field :messages, type: Array, reducer: GraphAgent::Reducers::ADD, default: []
  field :draft, type: String
  field :approved, type: :boolean, default: false
end

graph = GraphAgent::Graph::StateGraph.new(schema)

graph.add_node("generate_draft") do |state|
  topic = state[:messages].last[:content]
  { draft: "Draft response about: #{topic}" }
end

graph.add_node("human_review") do |state|
  if state[:approved]
    { messages: [{ role: "ai", content: state[:draft] }] }
  else
    { messages: [{ role: "ai", content: "Draft was rejected." }] }
  end
end

graph.add_edge(GraphAgent::START, "generate_draft")
graph.add_edge("generate_draft", "human_review")
graph.add_edge("human_review", GraphAgent::END_NODE)

checkpointer = GraphAgent::Checkpoint::InMemorySaver.new
app = graph.compile(
  checkpointer: checkpointer,
  interrupt_before: ["human_review"]
)

config = { configurable: { thread_id: "review-session-1" } }

# Step 1: Start execution — will pause before human_review
begin
  app.invoke(
    { messages: [{ role: "user", content: "Write about Ruby" }] },
    config: config
  )
rescue GraphAgent::GraphInterrupt => e
  puts "Interrupted: #{e.interrupts.first.value}"
end

# Step 2: Inspect the draft
snapshot = app.get_state(config)
puts "Draft: #{snapshot.values[:draft]}"

# Step 3: Approve and resume
app.update_state(config, { approved: true })
result = app.invoke(nil, config: config)
puts "Final: #{result[:messages].last[:content]}"
```

---

## Patterns

### Approval Gate

```ruby
graph.add_node("propose_action") do |state|
  { proposed_action: "Delete 50 records" }
end

graph.add_node("execute_action") do |state|
  if state[:approved]
    { result: "Deleted 50 records" }
  else
    { result: "Action cancelled" }
  end
end

graph.add_edge(GraphAgent::START, "propose_action")
graph.add_edge("propose_action", "execute_action")
graph.add_edge("execute_action", GraphAgent::END_NODE)

app = graph.compile(
  checkpointer: checkpointer,
  interrupt_before: ["execute_action"]
)
```

### Human Input Collection

```ruby
graph.add_node("ask_question") do |state|
  { question: "What is your preferred language?" }
end

graph.add_node("process_answer") do |state|
  { result: "You chose: #{state[:human_input]}" }
end

# After interrupt, the human provides input via update_state:
# app.update_state(config, { human_input: "Ruby" })
```
