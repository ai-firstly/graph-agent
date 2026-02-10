# frozen_string_literal: true

RSpec.describe GraphAgent::Send do
  it "stores node and arg" do
    send = described_class.new("worker", { task: 1 })
    expect(send.node).to eq("worker")
    expect(send.arg).to eq({ task: 1 })
  end

  it "supports equality" do
    a = described_class.new("worker", { task: 1 })
    b = described_class.new("worker", { task: 1 })
    c = described_class.new("worker", { task: 2 })

    expect(a).to eq(b)
    expect(a).not_to eq(c)
  end

  it "supports use as a Hash key" do
    a = described_class.new("worker", { task: 1 })
    b = described_class.new("worker", { task: 1 })

    hash = { a => true }
    expect(hash[b]).to eq(true)
  end

  it "converts to string representation" do
    send = described_class.new("worker", 42)
    expect(send.to_s).to include("worker")
    expect(send.inspect).to include("42")
  end
end

RSpec.describe GraphAgent::Command do
  it "stores goto as an array" do
    cmd = described_class.new(goto: "node_a")
    expect(cmd.goto).to eq(["node_a"])
  end

  it "stores update" do
    cmd = described_class.new(update: { key: "val" })
    expect(cmd.update).to eq({ key: "val" })
  end

  it "stores resume" do
    cmd = described_class.new(resume: "value")
    expect(cmd.resume).to eq("value")
  end

  it "stores graph" do
    cmd = described_class.new(graph: "subgraph")
    expect(cmd.graph).to eq("subgraph")
  end

  it "handles multiple goto targets" do
    cmd = described_class.new(goto: %w[a b c])
    expect(cmd.goto).to eq(%w[a b c])
  end

  it "converts to string" do
    cmd = described_class.new(goto: "x", update: { a: 1 })
    expect(cmd.to_s).to include("goto")
    expect(cmd.to_s).to include("update")
  end
end

RSpec.describe GraphAgent::Interrupt do
  it "stores value" do
    interrupt = described_class.new("please confirm")
    expect(interrupt.value).to eq("please confirm")
  end

  it "auto-generates an ID" do
    interrupt = described_class.new("test")
    expect(interrupt.id).to be_a(String)
    expect(interrupt.id.length).to eq(32)
  end

  it "accepts a custom ID" do
    interrupt = described_class.new("test", id: "custom-id")
    expect(interrupt.id).to eq("custom-id")
  end

  it "supports equality based on id and value" do
    a = described_class.new("val", id: "id1")
    b = described_class.new("val", id: "id1")
    c = described_class.new("val", id: "id2")

    expect(a).to eq(b)
    expect(a).not_to eq(c)
  end

  it "supports use as a Hash key" do
    a = described_class.new("val", id: "id1")
    b = described_class.new("val", id: "id1")

    hash = { a => true }
    expect(hash[b]).to eq(true)
  end
end

RSpec.describe GraphAgent::RetryPolicy do
  describe "#should_retry?" do
    it "retries on matching error class" do
      policy = described_class.new(retry_on: RuntimeError)
      expect(policy.should_retry?(RuntimeError.new("fail"))).to be true
      expect(policy.should_retry?(ArgumentError.new("fail"))).to be false
    end

    it "retries on array of error classes" do
      policy = described_class.new(retry_on: [RuntimeError, ArgumentError])
      expect(policy.should_retry?(RuntimeError.new)).to be true
      expect(policy.should_retry?(ArgumentError.new)).to be true
      expect(policy.should_retry?(TypeError.new)).to be false
    end

    it "supports a proc for retry_on" do
      policy = described_class.new(retry_on: ->(e) { e.message.include?("retry") })
      expect(policy.should_retry?(StandardError.new("please retry"))).to be true
      expect(policy.should_retry?(StandardError.new("no"))).to be false
    end
  end

  describe "#interval_for" do
    it "applies exponential backoff" do
      policy = described_class.new(
        initial_interval: 1.0,
        backoff_factor: 2.0,
        max_interval: 100.0,
        jitter: false
      )

      expect(policy.interval_for(1)).to eq(2.0)
      expect(policy.interval_for(2)).to eq(4.0)
      expect(policy.interval_for(3)).to eq(8.0)
    end

    it "caps at max_interval" do
      policy = described_class.new(
        initial_interval: 1.0,
        backoff_factor: 2.0,
        max_interval: 5.0,
        jitter: false
      )

      expect(policy.interval_for(10)).to eq(5.0)
    end

    it "adds jitter when enabled" do
      policy = described_class.new(
        initial_interval: 1.0,
        backoff_factor: 2.0,
        jitter: true
      )

      intervals = 10.times.map { policy.interval_for(1) }
      expect(intervals.uniq.length).to be > 1
    end
  end

  it "has sensible defaults" do
    policy = described_class.new
    expect(policy.max_attempts).to eq(3)
    expect(policy.initial_interval).to eq(0.5)
    expect(policy.backoff_factor).to eq(2.0)
    expect(policy.max_interval).to eq(128.0)
    expect(policy.jitter).to be true
    expect(policy.retry_on).to eq(StandardError)
  end
end
