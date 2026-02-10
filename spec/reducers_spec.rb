# frozen_string_literal: true

RSpec.describe GraphAgent::Reducers do
  describe "ADD" do
    it "adds numbers" do
      expect(GraphAgent::Reducers::ADD.call(3, 4)).to eq(7)
    end

    it "concatenates arrays" do
      expect(GraphAgent::Reducers::ADD.call([1, 2], [3])).to eq([1, 2, 3])
    end

    it "concatenates strings" do
      expect(GraphAgent::Reducers::ADD.call("foo", "bar")).to eq("foobar")
    end
  end

  describe "MERGE" do
    it "merges hashes" do
      result = GraphAgent::Reducers::MERGE.call({ a: 1 }, { b: 2 })
      expect(result).to eq({ a: 1, b: 2 })
    end

    it "overwrites duplicate keys" do
      result = GraphAgent::Reducers::MERGE.call({ a: 1 }, { a: 2 })
      expect(result).to eq({ a: 2 })
    end
  end

  describe "REPLACE" do
    it "replaces old value with new" do
      expect(GraphAgent::Reducers::REPLACE.call("old", "new")).to eq("new")
    end

    it "ignores the old value" do
      expect(GraphAgent::Reducers::REPLACE.call(100, 200)).to eq(200)
    end
  end

  describe "APPEND" do
    it "appends arrays" do
      expect(GraphAgent::Reducers::APPEND.call([1], [2, 3])).to eq([1, 2, 3])
    end

    it "wraps non-array values" do
      expect(GraphAgent::Reducers::APPEND.call(1, 2)).to eq([1, 2])
    end

    it "handles nil by wrapping in array" do
      expect(GraphAgent::Reducers::APPEND.call(nil, 1)).to eq([1])
    end
  end

  describe ".add_messages" do
    it "appends messages without IDs" do
      existing = [{ role: "user", content: "hi" }]
      new_msgs = [{ role: "assistant", content: "hello" }]
      result = described_class.add_messages(existing, new_msgs)
      expect(result.length).to eq(2)
      expect(result.last[:content]).to eq("hello")
    end

    it "merges messages with matching IDs" do
      existing = [
        { id: "1", role: "user", content: "hi" },
        { id: "2", role: "assistant", content: "hello" }
      ]
      new_msgs = [{ id: "1", role: "user", content: "updated" }]
      result = described_class.add_messages(existing, new_msgs)
      expect(result.length).to eq(2)
      expect(result[0][:content]).to eq("updated")
      expect(result[1][:content]).to eq("hello")
    end

    it "appends messages with new IDs" do
      existing = [{ id: "1", content: "first" }]
      new_msgs = [{ id: "2", content: "second" }]
      result = described_class.add_messages(existing, new_msgs)
      expect(result.length).to eq(2)
    end

    it "handles mixed ID and non-ID messages" do
      existing = [{ id: "1", content: "a" }]
      new_msgs = [
        { id: "1", content: "a_updated" },
        { content: "no_id" }
      ]
      result = described_class.add_messages(existing, new_msgs)
      expect(result.length).to eq(2)
      expect(result[0][:content]).to eq("a_updated")
      expect(result[1][:content]).to eq("no_id")
    end

    it "handles nil existing messages" do
      result = described_class.add_messages(nil, [{ content: "hi" }])
      expect(result).to eq([{ content: "hi" }])
    end

    it "does not mutate the original array" do
      existing = [{ id: "1", content: "original" }]
      described_class.add_messages(existing, [{ id: "2", content: "new" }])
      expect(existing.length).to eq(1)
    end
  end
end
