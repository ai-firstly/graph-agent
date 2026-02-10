# frozen_string_literal: true

module GraphAgent
  module Channels
    class EphemeralValue < BaseChannel
      def initialize(key: "", guard: true)
        super(key: key)
        @guard = guard
        @value = MISSING
      end

      def get
        raise EmptyChannelError.new("Channel '#{key}' is empty") if @value.equal?(MISSING)

        @value
      end

      def update(values)
        if values.empty?
          if @value.equal?(MISSING)
            return false
          else
            @value = MISSING
            return true
          end
        end

        if values.length != 1 && @guard
          raise InvalidUpdateError.new(
            "At key '#{key}': EphemeralValue(guard=true) can receive only one value per step."
          )
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
        ch = self.class.new(key: key, guard: @guard)
        ch.instance_variable_set(:@value, checkpoint.equal?(MISSING) ? MISSING : checkpoint)
        ch
      end

      def copy
        ch = self.class.new(key: key, guard: @guard)
        ch.instance_variable_set(:@value, @value)
        ch
      end
    end
  end
end
