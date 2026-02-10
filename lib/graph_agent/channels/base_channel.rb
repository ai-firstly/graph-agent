# frozen_string_literal: true

module GraphAgent
  module Channels
    class BaseChannel
      MISSING = Object.new.freeze

      attr_accessor :key

      def initialize(key: "")
        @key = key
      end

      def get
        raise NotImplementedError.new("#{self.class}#get must be implemented")
      end

      def update(values)
        raise NotImplementedError.new("#{self.class}#update must be implemented")
      end

      def checkpoint
        get
      rescue EmptyChannelError
        MISSING
      end

      def from_checkpoint(checkpoint)
        raise NotImplementedError.new("#{self.class}#from_checkpoint must be implemented")
      end

      def available?
        get
        true
      rescue EmptyChannelError
        false
      end

      def consume
        false
      end

      def finish
        false
      end

      def copy
        from_checkpoint(checkpoint)
      end
    end
  end
end
