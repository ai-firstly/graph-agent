# frozen_string_literal: true

module GraphAgent
  module Channels
    class Topic < BaseChannel
      attr_reader :accumulate

      def initialize(key: "", accumulate: false)
        super(key: key)
        @accumulate = accumulate
        @values = []
      end

      def get
        raise EmptyChannelError.new("Channel '#{key}' is empty") if @values.empty?

        @values.dup
      end

      def update(values)
        updated = false

        unless @accumulate
          updated = !@values.empty?
          @values = []
        end

        flat = values.flat_map { |v| v.is_a?(Array) ? v : [v] }
        unless flat.empty?
          updated = true
          @values.concat(flat)
        end

        updated
      end

      def available?
        !@values.empty?
      end

      def checkpoint
        @values.dup
      end

      def from_checkpoint(checkpoint)
        ch = self.class.new(key: key, accumulate: @accumulate)
        ch.instance_variable_set(:@values, checkpoint.equal?(MISSING) ? [] : Array(checkpoint))
        ch
      end

      def copy
        ch = self.class.new(key: key, accumulate: @accumulate)
        ch.instance_variable_set(:@values, @values.dup)
        ch
      end
    end
  end
end
