# frozen_string_literal: true

RSpec.describe GraphAgent::State::Schema do
  describe "field DSL" do
    it "defines fields with block syntax" do
      schema = described_class.new do
        field :name, type: String
        field :age, type: Integer, default: 0
      end

      expect(schema.fields.keys).to eq(%i[name age])
      expect(schema.fields[:name].type).to eq(String)
      expect(schema.fields[:age].default).to eq(0)
    end

    it "defines fields without a block" do
      schema = described_class.new
      schema.field(:count, type: Integer, default: 0)
      expect(schema.fields[:count].name).to eq(:count)
    end

    it "converts string field names to symbols" do
      schema = described_class.new
      schema.field("messages", type: Array, default: [])
      expect(schema.fields).to have_key(:messages)
    end
  end

  describe "#initial_state" do
    it "returns correct defaults" do
      schema = described_class.new do
        field :name, type: String
        field :count, type: Integer, default: 0
        field :items, type: Array, default: []
      end

      state = schema.initial_state
      expect(state[:name]).to be_nil
      expect(state[:count]).to eq(0)
      expect(state[:items]).to eq([])
    end

    it "dups mutable defaults so they are independent" do
      schema = described_class.new do
        field :list, type: Array, default: [1, 2]
      end

      state1 = schema.initial_state
      state2 = schema.initial_state
      state1[:list] << 3
      expect(state2[:list]).to eq([1, 2])
    end

    it "handles non-dupable defaults like integers" do
      schema = described_class.new do
        field :n, type: Integer, default: 42
      end

      expect(schema.initial_state[:n]).to eq(42)
    end
  end

  describe "#apply" do
    it "applies updates with reducers" do
      schema = described_class.new do
        field :total, type: Integer, default: 0, reducer: ->(a, b) { a + b }
        field :items, type: Array, default: [], reducer: ->(a, b) { a + b }
      end

      state = schema.initial_state
      schema.apply(state, { total: 5, items: [1] })
      expect(state[:total]).to eq(5)
      expect(state[:items]).to eq([1])

      schema.apply(state, { total: 3, items: [2, 3] })
      expect(state[:total]).to eq(8)
      expect(state[:items]).to eq([1, 2, 3])
    end

    it "applies updates without reducers (last-value semantics)" do
      schema = described_class.new do
        field :name, type: String
      end

      state = schema.initial_state
      schema.apply(state, { name: "Alice" })
      expect(state[:name]).to eq("Alice")

      schema.apply(state, { name: "Bob" })
      expect(state[:name]).to eq("Bob")
    end

    it "handles string keys in updates" do
      schema = described_class.new do
        field :value, type: Integer, default: 0, reducer: ->(a, b) { a + b }
      end

      state = schema.initial_state
      schema.apply(state, { "value" => 10 })
      expect(state[:value]).to eq(10)
    end

    it "returns the mutated state" do
      schema = described_class.new do
        field :x, type: Integer
      end

      state = schema.initial_state
      result = schema.apply(state, { x: 1 })
      expect(result).to equal(state)
    end
  end
end
