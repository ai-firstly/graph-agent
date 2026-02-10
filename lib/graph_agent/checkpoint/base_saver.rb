# frozen_string_literal: true

module GraphAgent
  module Checkpoint
    CheckpointTuple = Data.define(:config, :checkpoint, :metadata, :parent_config, :pending_writes) do
      def initialize(config:, checkpoint:, metadata: nil, parent_config: nil, pending_writes: [])
        super
      end
    end

    class BaseSaver
      def get(config)
        tuple = get_tuple(config)
        tuple&.checkpoint
      end

      def get_tuple(config)
        raise NotImplementedError.new("#{self.class}#get_tuple must be implemented")
      end

      def list(config, filter: nil, before: nil, limit: nil)
        raise NotImplementedError.new("#{self.class}#list must be implemented")
      end

      def put(config, checkpoint, metadata, new_versions)
        raise NotImplementedError.new("#{self.class}#put must be implemented")
      end

      def put_writes(config, writes, task_id)
        raise NotImplementedError.new("#{self.class}#put_writes must be implemented")
      end

      def delete_thread(thread_id)
        raise NotImplementedError.new("#{self.class}#delete_thread must be implemented")
      end
    end
  end
end
