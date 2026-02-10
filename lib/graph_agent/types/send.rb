# frozen_string_literal: true

module GraphAgent
  class Send
    attr_reader :node, :arg

    def initialize(node, arg)
      @node = node.to_s
      @arg = arg
    end

    def ==(other)
      other.is_a?(Send) && node == other.node && arg == other.arg
    end
    alias eql? ==

    def hash
      [node, arg].hash
    end

    def to_s
      "Send(node=#{node.inspect}, arg=#{arg.inspect})"
    end
    alias inspect to_s
  end
end
