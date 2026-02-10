# frozen_string_literal: true

RSpec.describe GraphAgent::Channels::EphemeralValue do
  describe "with guard mode (default)" do
    subject(:channel) { described_class.new(key: "eph") }

    it "starts empty" do
      expect { channel.get }.to raise_error(GraphAgent::EmptyChannelError)
      expect(channel).not_to be_available
    end

    it "stores a single value" do
      channel.update(["val"])
      expect(channel.get).to eq("val")
      expect(channel).to be_available
    end

    it "clears value on empty update after being set" do
      channel.update(["val"])
      result = channel.update([])
      expect(result).to be true
      expect(channel).not_to be_available
      expect { channel.get }.to raise_error(GraphAgent::EmptyChannelError)
    end

    it "returns false for empty update when already empty" do
      expect(channel.update([])).to be false
    end

    it "raises InvalidUpdateError for multiple values in guard mode" do
      expect { channel.update([1, 2]) }.to raise_error(
        GraphAgent::InvalidUpdateError,
        /EphemeralValue\(guard=true\) can receive only one value per step/
      )
    end
  end

  describe "without guard mode" do
    subject(:channel) { described_class.new(key: "eph_ng", guard: false) }

    it "accepts multiple values and keeps last" do
      channel.update([1, 2, 3])
      expect(channel.get).to eq(3)
    end

    it "does not raise for multiple values" do
      expect { channel.update([1, 2]) }.not_to raise_error
    end
  end

  describe "#checkpoint / #from_checkpoint" do
    it "round-trips a stored value" do
      ch = described_class.new(key: "rt")
      ch.update(["data"])
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect(restored.get).to eq("data")
    end

    it "round-trips MISSING when empty" do
      ch = described_class.new(key: "rt")
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect(restored).not_to be_available
    end

    it "preserves guard setting" do
      ch = described_class.new(key: "rt", guard: false)
      ch.update(["x"])
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect { restored.update([1, 2]) }.not_to raise_error
    end
  end

  describe "#copy" do
    it "creates an independent copy" do
      ch = described_class.new(key: "c")
      ch.update([42])
      copy = ch.copy
      expect(copy.get).to eq(42)

      copy.update([])
      expect(copy).not_to be_available
      expect(ch.get).to eq(42)
    end
  end
end
