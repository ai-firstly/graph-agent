# frozen_string_literal: true

RSpec.describe GraphAgent::Channels::BinaryOperatorAggregate do
  describe "with addition operator" do
    subject(:channel) { described_class.new(operator: ->(a, b) { a + b }, key: "sum") }

    it "raises EmptyChannelError when empty" do
      expect { channel.get }.to raise_error(GraphAgent::EmptyChannelError)
    end

    it "stores the first value as initial" do
      channel.update([5])
      expect(channel.get).to eq(5)
    end

    it "aggregates multiple values in a single update" do
      channel.update([1, 2, 3])
      expect(channel.get).to eq(6)
    end

    it "aggregates across multiple updates" do
      channel.update([10])
      channel.update([5])
      expect(channel.get).to eq(15)
    end

    it "returns false for empty update" do
      expect(channel.update([])).to be false
    end

    it "returns true for non-empty update" do
      expect(channel.update([1])).to be true
    end
  end

  describe "with array concat operator" do
    subject(:channel) { described_class.new(operator: ->(a, b) { a + b }, key: "list") }

    it "concatenates arrays" do
      channel.update([[1, 2]])
      channel.update([[3, 4]])
      expect(channel.get).to eq([1, 2, 3, 4])
    end
  end

  describe "with default value" do
    it "uses default as initial value" do
      ch = described_class.new(operator: ->(a, b) { a + b }, key: "x", default: 100)
      expect(ch.get).to eq(100)
      ch.update([5])
      expect(ch.get).to eq(105)
    end

    it "uses array default" do
      ch = described_class.new(operator: ->(a, b) { a + b }, key: "arr", default: [])
      expect(ch.get).to eq([])
      ch.update([[1]])
      expect(ch.get).to eq([1])
    end
  end

  describe "#checkpoint / #from_checkpoint" do
    it "round-trips a stored value" do
      ch = described_class.new(operator: ->(a, b) { a + b }, key: "rt")
      ch.update([10, 20])
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect(restored.get).to eq(30)
    end

    it "round-trips MISSING when empty" do
      ch = described_class.new(operator: ->(a, b) { a + b }, key: "rt")
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect(restored).not_to be_available
    end
  end

  describe "with custom lambda operator" do
    it "applies max aggregation" do
      ch = described_class.new(operator: ->(a, b) { [a, b].max }, key: "max")
      ch.update([3, 7, 2, 9, 1])
      expect(ch.get).to eq(9)
    end

    it "applies string join" do
      ch = described_class.new(operator: ->(a, b) { "#{a},#{b}" }, key: "join")
      ch.update(%w[a b c])
      expect(ch.get).to eq("a,b,c")
    end
  end
end
