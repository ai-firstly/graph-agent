# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

GraphAgent 是 LangGraph 的 Ruby 移植版，是一个用于构建有状态、多参与者代理工作流的 Ruby 框架。框架实现了 Pregel 执行模型（整体同步并行计算模型）。

## 常用命令

```bash
# 安装依赖
make install
# 或
bundle install

# 运行测试
make test
# 或运行特定测试文件
make test TEST=spec/graph/state_graph_spec.rb

# 代码检查
make lint        # 只检查不修复
make format      # 自动修复格式问题

# 构建 gem
make build

# 清理构建产物
make clean

# 交互式控制台（加载 gem）
make console
# 或
bundle exec irb -r graph_agent

# 发布流程
make tag                    # 自动递增补丁版本并打 tag
make tag VERSION=1.2.3      # 指定版本号打 tag
make release                # tag + 推送到 RubyGems
```

## 核心架构

### 目录结构

```
lib/graph_agent/
├── graph/               # 图相关核心类
│   ├── state_graph.rb       # StateGraph - 用于构建有向图的 DSL
│   ├── compiled_state_graph.rb  # CompiledStateGraph - 编译后可执行的图
│   ├── message_graph.rb     # MessageGraph - 预配置消息状态的便捷封装
│   ├── node.rb              # Node - 图节点包装器
│   ├── edge.rb              # Edge - 有向边
│   ├── conditional_edge.rb  # ConditionalEdge - 条件边
│   └── mermaid_visualizer.rb # Mermaid 图表可视化
├── state/
│   └── schema.rb            # Schema - 状态 schema 定义
├── channels/                # Channel 抽象（当前主要是 last_value、binary_operator_aggregate 等）
├── checkpoint/              # 状态持久化
│   ├── base_saver.rb        # 检查点保存器基类
│   └── in_memory_saver.rb   # 内存检查点实现
├── types/
│   ├── send.rb              # Send - 动态创建并行任务（map-reduce 模式）
│   ├── command.rb           # Command - 状态更新 + 路由决策的组合
│   ├── retry_policy.rb      # RetryPolicy - 节点重试策略
│   ├── cache_policy.rb      # CachePolicy - 缓存策略
│   ├── interrupt.rb         # Interrupt - 中断信号
│   └── state_snapshot.rb    # StateSnapshot - 状态快照
├── reducers.rb              # 内置 reducer 函数（ADD, APPEND, MERGE, REPLACE 等）
├── errors.rb                # 异常类定义
├── constants.rb             # 常量（START, END_NODE）
└── version.rb               # 版本号
```

### 核心概念

1. **State（状态）**: 共享数据结构，通过 Schema 定义。每个字段可以指定 reducer 来控制状态合并行为。
   - 无 reducer 的字段使用 "last-value" 语义（直接替换）
   - 有 reducer 的字段使用 reducer 定义的语义（如 ADD、MERGE）

2. **Node（节点）**: 处理状态的函数，接收 state 和可选的 config 参数，返回状态更新（Hash）、Command 或 Send。

3. **Edge（边）**: 定义节点间的流转
   - 普通边：固定从 A 到 B
   - 条件边：根据状态动态路由
   - 等待边：多个源节点都执行完后才到目标节点

4. **Pregel 执行流程**: PLAN → EXECUTE → UPDATE → CHECKPOINT → REPEAT

### 关键类关系

```
StateGraph (builder)  →  CompiledStateGraph (executable)
    ↓                      ↓
  schema                 invoke/stream
  nodes                  checkpointer
  edges                  interrupt_before/after
  branches
```

### Send 和 Command 的区别

- **Send**: 用于条件边返回，动态创建并行执行任务，可传递独立参数
- **Command**: 节点返回值，同时更新状态并指定下一个跳转的节点

## 开发注意事项

1. **Ruby 版本**: 最低要求 3.1.0

2. **代码风格**: 使用 Rubocop 进行检查和格式化（`make format`）

3. **测试**: 使用 RSpec，所有测试文件位于 `spec/` 目录

4. **命名约定**:
   - 内部方法以 `_` 前缀开头（如 `_normalize_schema`）
   - 节点名称转换为字符串存储
   - 所有配置键使用 Symbol

5. **保留节点名**: `START` 和 `END_NODE`（实际字符串 "__start__" 和 "__end__"）是保留的入口/出口哨兵

6. **状态更新**: 节点返回的 Hash 会通过 Schema 中定义的 reducer 进行合并

7. **错误处理**:
   - `GraphRecursionError`: 超过最大递归步数
   - `InvalidUpdateError`: 无效的状态更新
   - `NodeExecutionError`: 节点执行错误（包装原始错误）
   - `GraphInterrupt`: 人为中断（用于 human-in-the-loop）
