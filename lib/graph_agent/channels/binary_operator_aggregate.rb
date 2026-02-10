# frozen_string_literal: true

module GraphAgent
  module Channels
    class BinaryOperatorAggregate < BaseChannel
      attr_reader :operator

      def initialize(operator:, key: "", default: MISSING)
        super(key: key)
        @operator = operator
        @value = default
      end

      def get
        raise EmptyChannelError.new("Channel '#{key}' is empty") if @value.equal?(MISSING)

        @value
      end

      def update(values)
        return false if values.empty?

        if @value.equal?(MISSING)
          @value = values.first
          values = values[1..]
        end

        values.each do |value|
          @value = @operator.call(@value, value)
        end

        true
      end

      def available?
        !@value.equal?(MISSING)
      end

      def checkpoint
        @value
      end

      def from_checkpoint(checkpoint)
        ch = self.class.new(operator: @operator, key: key)
        ch.instance_variable_set(:@value, checkpoint.equal?(MISSING) ? MISSING : checkpoint)
        ch
      end

      def copy
        ch = self.class.new(operator: @operator, key: key)
        ch.instance_variable_set(:@value, @value)
        ch
      end
    end
  end
end
