# GraphAgent Documentation

A Ruby framework for building stateful, multi-actor agent workflows.
Ruby port of [LangGraph](https://github.com/langchain-ai/langgraph).

## Guides

| Document | Description |
|----------|-------------|
| [Quickstart](quickstart.md) | Installation, minimal examples, and first steps |
| [Core Concepts](concepts.md) | Graphs, state, nodes, edges, supersteps, channels, and compilation |
| [State Management](state.md) | Schema DSL, reducers, defaults, and atomic updates |
| [Edges](edges.md) | Normal, conditional, entry/exit, waiting, and sequence edges |
| [Send & Command](send_and_command.md) | Map-reduce fan-out/fan-in with `Send` and combined routing with `Command` |
| [Persistence](persistence.md) | Checkpointing, thread-based conversations, and state snapshots |
| [Streaming](streaming.md) | Stream modes (`:values`, `:updates`, `:debug`), block and enumerator usage |
| [Human-in-the-Loop](human_in_the_loop.md) | Interrupts, inspecting/modifying state, and resuming execution |
| [Error Handling](error_handling.md) | Error classes, recursion limits, retry policies |
| [API Reference](api_reference.md) | Full reference for every class, method, and constant |

## Source Layout

```
lib/
  graph_agent.rb                          # Entry point & requires
  graph_agent/
    constants.rb                          # START, END_NODE sentinels
    errors.rb                             # Error hierarchy
    reducers.rb                           # Built-in reducer functions
    state/
      schema.rb                           # Schema DSL for state definition
    channels/
      base_channel.rb                     # Abstract channel interface
      last_value.rb                       # Single-value channel
      binary_operator_aggregate.rb        # Reducer-based aggregation channel
      ephemeral_value.rb                  # Per-step ephemeral channel
      topic.rb                            # Multi-value topic channel
    types/
      send.rb                             # Send (fan-out routing)
      command.rb                          # Command (update + routing)
      interrupt.rb                        # Interrupt value type
      retry_policy.rb                     # Retry configuration
      cache_policy.rb                     # Cache configuration
      state_snapshot.rb                   # Snapshot of graph state
    checkpoint/
      base_saver.rb                       # Abstract checkpoint saver
      in_memory_saver.rb                  # In-memory checkpoint implementation
    graph/
      node.rb                             # Node wrapper with retry support
      edge.rb                             # Static edge
      conditional_edge.rb                 # Dynamic conditional edge
      state_graph.rb                      # Graph builder
      compiled_state_graph.rb             # Compiled executable graph (Pregel)
      message_graph.rb                    # Pre-built message-oriented graph
```
