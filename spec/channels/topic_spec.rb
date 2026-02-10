# frozen_string_literal: true

RSpec.describe GraphAgent::Channels::Topic do
  describe "non-accumulate mode (default)" do
    subject(:channel) { described_class.new(key: "topic") }

    it "starts empty" do
      expect { channel.get }.to raise_error(GraphAgent::EmptyChannelError)
      expect(channel).not_to be_available
    end

    it "appends values" do
      channel.update([1, 2])
      expect(channel.get).to eq([1, 2])
    end

    it "clears previous values on new update" do
      channel.update([1, 2])
      channel.update([3])
      expect(channel.get).to eq([3])
    end

    it "returns false for empty update when already empty" do
      expect(channel.update([])).to be false
    end

    it "returns true when clearing non-empty values even with empty input" do
      channel.update([1])
      expect(channel.update([])).to be true
    end

    it "flattens array inputs" do
      channel.update([[1, 2], 3, [4, 5]])
      expect(channel.get).to eq([1, 2, 3, 4, 5])
    end
  end

  describe "accumulate mode" do
    subject(:channel) { described_class.new(key: "accum", accumulate: true) }

    it "keeps values across updates" do
      channel.update([1, 2])
      channel.update([3, 4])
      expect(channel.get).to eq([1, 2, 3, 4])
    end

    it "does not clear on empty update" do
      channel.update([1])
      result = channel.update([])
      expect(result).to be false
      expect(channel.get).to eq([1])
    end
  end

  describe "#checkpoint / #from_checkpoint" do
    it "round-trips stored values" do
      ch = described_class.new(key: "rt")
      ch.update([1, 2, 3])
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect(restored.get).to eq([1, 2, 3])
    end

    it "round-trips empty state" do
      ch = described_class.new(key: "rt")
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      expect(restored).not_to be_available
    end

    it "preserves accumulate setting" do
      ch = described_class.new(key: "rt", accumulate: true)
      ch.update([1])
      cp = ch.checkpoint
      restored = ch.from_checkpoint(cp)
      restored.update([2])
      expect(restored.get).to eq([1, 2])
    end
  end

  describe "#copy" do
    it "creates an independent copy" do
      ch = described_class.new(key: "c")
      ch.update([1, 2])
      copy = ch.copy
      expect(copy.get).to eq([1, 2])

      copy.update([3])
      expect(copy.get).to eq([3])
      expect(ch.get).to eq([1, 2])
    end
  end
end
