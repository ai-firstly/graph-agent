# Streaming

GraphAgent supports streaming intermediate results as the graph executes,
instead of waiting for the final output.

---

## Stream Modes

The `stream` method accepts a `stream_mode` parameter:

| Mode | Yields | Description |
|------|--------|-------------|
| `:values` | Full state Hash | Emits the complete state after each superstep |
| `:updates` | Per-node updates Hash | Emits only the changes each node produced |
| `:debug` | Raw event Hash | Emits all internal events with type, step, state, and updates |

---

## stream_mode: :values

Yields the full state after each superstep. This is the default mode.

```ruby
app.stream({ query: "hello" }, stream_mode: :values) do |state|
  puts "Messages: #{state[:messages].length}"
  puts "Status: #{state[:status]}"
end
```

The final yield contains the complete output state (same as what `invoke`
would return).

---

## stream_mode: :updates

Yields only the updates produced by each node in the step:

```ruby
app.stream({ query: "hello" }, stream_mode: :updates) do |updates|
  updates.each do |node_name, node_updates|
    puts "#{node_name} produced: #{node_updates}"
  end
end
```

The updates hash maps node names (strings) to the Hash each node returned.

---

## stream_mode: :debug

Yields raw event hashes with full internal detail:

```ruby
app.stream({ query: "hello" }, stream_mode: :debug) do |event|
  case event[:type]
  when :values
    puts "Step #{event[:step]}: state = #{event[:state]}"
  when :updates
    puts "Step #{event[:step]}: updates = #{event[:updates]}"
  end
end
```

Event structure:

```ruby
{
  type: :values | :updates,
  step: Integer,
  state: Hash,      # present for :values events
  updates: Hash     # present for :updates events
}
```

---

## Using Block Form

Pass a block to `stream` to process events as they arrive:

```ruby
app.stream(input, config: config, stream_mode: :values) do |state|
  render_state(state)
end
```

---

## Using Enumerator (No Block)

When called without a block, `stream` returns an `Enumerator`:

```ruby
events = app.stream(input, stream_mode: :values)

events.each do |state|
  puts state[:messages].last
end
```

The `Enumerator` is lazy — events are produced as the graph executes. You can
use standard Enumerable methods:

```ruby
# Get the first 3 states
first_three = app.stream(input, stream_mode: :values).take(3)

# Find the first state where processing is complete
done = app.stream(input, stream_mode: :values).find { |s| s[:done] }
```

---

## Streaming with Config

All `stream` options from `invoke` are available:

```ruby
app.stream(
  input,
  config: { configurable: { thread_id: "t1" } },
  recursion_limit: 50,
  stream_mode: :updates
) do |updates|
  puts updates
end
```

---

## Complete Example

```ruby
require "graph_agent"

schema = GraphAgent::State::Schema.new do
  field :numbers, type: Array, default: []
  field :sum, type: Integer, reducer: GraphAgent::Reducers::ADD, default: 0
  field :step_name, type: String
end

graph = GraphAgent::Graph::StateGraph.new(schema)

graph.add_node("add_evens") do |state|
  evens = state[:numbers].select(&:even?)
  { sum: evens.sum, step_name: "add_evens" }
end

graph.add_node("add_odds") do |state|
  odds = state[:numbers].select(&:odd?)
  { sum: odds.sum, step_name: "add_odds" }
end

graph.add_edge(GraphAgent::START, "add_evens")
graph.add_edge("add_evens", "add_odds")
graph.add_edge("add_odds", GraphAgent::END_NODE)

app = graph.compile

puts "=== :values mode ==="
app.stream({ numbers: [1, 2, 3, 4, 5] }, stream_mode: :values) do |state|
  puts "sum=#{state[:sum]} step=#{state[:step_name]}"
end

puts "\n=== :updates mode ==="
app.stream({ numbers: [1, 2, 3, 4, 5] }, stream_mode: :updates) do |updates|
  updates.each { |node, u| puts "#{node}: #{u}" }
end
```
