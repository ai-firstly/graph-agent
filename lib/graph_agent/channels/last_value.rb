# frozen_string_literal: true

module GraphAgent
  module Channels
    class LastValue < BaseChannel
      def initialize(key: "", default: MISSING)
        super(key: key)
        @value = default
      end

      def get
        raise EmptyChannelError.new("Channel '#{key}' is empty") if @value.equal?(MISSING)

        @value
      end

      def update(values)
        return false if values.empty?

        if values.length != 1
          raise InvalidUpdateError.new("At key '#{key}': Can receive only one value per step.")
        end

        @value = values.last
        true
      end

      def available?
        !@value.equal?(MISSING)
      end

      def checkpoint
        @value
      end

      def from_checkpoint(checkpoint)
        ch = self.class.new(key: key)
        ch.instance_variable_set(:@value, checkpoint.equal?(MISSING) ? MISSING : checkpoint)
        ch
      end

      def copy
        ch = self.class.new(key: key)
        ch.instance_variable_set(:@value, @value)
        ch
      end
    end
  end
end
