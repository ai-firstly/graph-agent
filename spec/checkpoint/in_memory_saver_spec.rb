# frozen_string_literal: true

RSpec.describe GraphAgent::Checkpoint::InMemorySaver do
  let(:saver) { described_class.new }
  let(:config) do
    { configurable: { thread_id: "thread-1", checkpoint_ns: "" } }
  end

  def make_checkpoint(id: nil, values: {})
    {
      id: id || SecureRandom.uuid,
      channel_values: values,
      channel_versions: {},
      versions_seen: {},
      next_nodes: []
    }
  end

  describe "#put and #get_tuple" do
    it "stores and retrieves a checkpoint" do
      checkpoint = make_checkpoint(values: { count: 1 })
      metadata = { source: :input, step: 0 }

      saver.put(config, checkpoint, metadata, {})

      tuple = saver.get_tuple(config)
      expect(tuple).to be_a(GraphAgent::Checkpoint::CheckpointTuple)
      expect(tuple.checkpoint[:channel_values][:count]).to eq(1)
      expect(tuple.metadata[:source]).to eq(:input)
    end

    it "retrieves specific checkpoint by ID" do
      cp1 = make_checkpoint(values: { v: 1 })
      cp2 = make_checkpoint(values: { v: 2 })

      saver.put(config, cp1, { step: 0 }, {})
      saver.put(config, cp2, { step: 1 }, {})

      specific_config = {
        configurable: {
          thread_id: "thread-1",
          checkpoint_ns: "",
          checkpoint_id: cp1[:id]
        }
      }

      tuple = saver.get_tuple(specific_config)
      expect(tuple.checkpoint[:channel_values][:v]).to eq(1)
    end

    it "returns nil for missing thread" do
      tuple = saver.get_tuple(config)
      expect(tuple).to be_nil
    end

    it "returns latest checkpoint when no ID specified" do
      cp1 = make_checkpoint(id: "aaa", values: { v: 1 })
      cp2 = make_checkpoint(id: "zzz", values: { v: 2 })

      saver.put(config, cp1, { step: 0 }, {})
      saver.put(config, cp2, { step: 1 }, {})

      tuple = saver.get_tuple(config)
      expect(tuple.checkpoint[:channel_values][:v]).to eq(2)
    end
  end

  describe "#list" do
    before do
      3.times do |i|
        cp = make_checkpoint(id: "cp-#{i}", values: { step: i })
        saver.put(config, cp, { source: :loop, step: i }, {})
      end
    end

    it "returns all checkpoints for a thread" do
      results = saver.list(config)
      expect(results.length).to eq(3)
    end

    it "filters by metadata" do
      cp = make_checkpoint(id: "cp-special", values: { special: true })
      saver.put(config, cp, { source: :update, step: 99 }, {})

      results = saver.list(config, filter: { source: :update })
      expect(results.length).to eq(1)
      expect(results.first.metadata[:step]).to eq(99)
    end

    it "respects limit" do
      results = saver.list(config, limit: 2)
      expect(results.length).to eq(2)
    end

    it "returns results in reverse order (newest first)" do
      results = saver.list(config)
      steps = results.map { |t| t.metadata[:step] }
      expect(steps).to eq(steps.sort.reverse)
    end
  end

  describe "#delete_thread" do
    it "removes all data for a thread" do
      cp = make_checkpoint(values: { v: 1 })
      saver.put(config, cp, { step: 0 }, {})

      saver.delete_thread("thread-1")

      tuple = saver.get_tuple(config)
      expect(tuple).to be_nil
    end
  end

  describe "#put_writes" do
    it "stores pending writes" do
      cp = make_checkpoint(id: "cp-w")
      saver.put(config, cp, { step: 0 }, {})

      write_config = {
        configurable: {
          thread_id: "thread-1",
          checkpoint_ns: "",
          checkpoint_id: "cp-w"
        }
      }

      saver.put_writes(write_config, [[:channel_a, "value_a"], [:channel_b, "value_b"]], "task-1")

      tuple = saver.get_tuple(write_config)
      expect(tuple.pending_writes.length).to eq(2)
      expect(tuple.pending_writes[0]).to eq(["task-1", :channel_a, "value_a"])
    end
  end

  describe "multiple threads" do
    it "stores threads independently" do
      config1 = { configurable: { thread_id: "t1", checkpoint_ns: "" } }
      config2 = { configurable: { thread_id: "t2", checkpoint_ns: "" } }

      saver.put(config1, make_checkpoint(values: { v: "one" }), { step: 0 }, {})
      saver.put(config2, make_checkpoint(values: { v: "two" }), { step: 0 }, {})

      t1 = saver.get_tuple(config1)
      t2 = saver.get_tuple(config2)

      expect(t1.checkpoint[:channel_values][:v]).to eq("one")
      expect(t2.checkpoint[:channel_values][:v]).to eq("two")
    end
  end
end
