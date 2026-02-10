# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-02-10

### Added
- Initial release of GraphAgent Ruby SDK
- Graph-based workflow engine with Pregel execution model
- State management with Schema and typed fields
- Built-in reducers: ADD, APPEND, MERGE, REPLACE, add_messages
- StateGraph and MessageGraph for building workflows
- Conditional edges with dynamic routing
- Send (map-reduce) and Command (routing + state update) patterns
- Checkpoint system with InMemorySaver for persistence
- Human-in-the-loop support with interrupt_before/interrupt_after
- Streaming execution with :values and :updates modes
- Retry policies with exponential backoff and jitter
- Mermaid diagram visualization for graph structures
- Comprehensive error handling (GraphRecursionError, InvalidUpdateError, etc.)
- Full test suite with RSpec
