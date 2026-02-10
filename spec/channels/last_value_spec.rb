# frozen_string_literal: true

RSpec.describe GraphAgent::Channels::LastValue do
  subject(:channel) { described_class.new(key: "test") }

  describe "#get" do
    it "raises EmptyChannelError when empty" do
      expect { channel.get }.to raise_error(GraphAgent::EmptyChannelError, /Channel 'test' is empty/)
    end

    it "returns the stored value after update" do
      channel.update([42])
      expect(channel.get).to eq(42)
    end
  end

  describe "#update" do
    it "stores a single value" do
      channel.update(["hello"])
      expect(channel.get).to eq("hello")
    end

    it "overwrites previous value" do
      channel.update([1])
      channel.update([2])
      expect(channel.get).to eq(2)
    end

    it "raises InvalidUpdateError for multiple values" do
      expect { channel.update([1, 2]) }.to raise_error(
        GraphAgent::InvalidUpdateError,
        /At key 'test': Can receive only one value per step/
      )
    end

    it "returns false for empty update" do
      expect(channel.update([])).to be false
    end

    it "returns true for non-empty update" do
      expect(channel.update([1])).to be true
    end
  end

  describe "#available?" do
    it "returns false when empty" do
      expect(channel).not_to be_available
    end

    it "returns true after a value is stored" do
      channel.update([1])
      expect(channel).to be_available
    end
  end

  describe "#checkpoint / #from_checkpoint" do
    it "round-trips a stored value" do
      channel.update(["data"])
      cp = channel.checkpoint
      restored = channel.from_checkpoint(cp)
      expect(restored.get).to eq("data")
    end

    it "round-trips MISSING when empty" do
      cp = channel.checkpoint
      restored = channel.from_checkpoint(cp)
      expect(restored).not_to be_available
    end
  end

  describe "#copy" do
    it "creates an independent copy" do
      channel.update([10])
      copy = channel.copy
      expect(copy.get).to eq(10)

      copy.update([20])
      expect(copy.get).to eq(20)
      expect(channel.get).to eq(10)
    end
  end

  describe "with default value" do
    it "returns default without any update" do
      ch = described_class.new(key: "d", default: "default_val")
      expect(ch.get).to eq("default_val")
      expect(ch).to be_available
    end
  end
end
