# frozen_string_literal: true

require "securerandom"

module GraphAgent
  module Checkpoint
    class InMemorySaver < BaseSaver
      def initialize
        super
        @storage = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
        @writes = Hash.new { |h, k| h[k] = {} }
        @order = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }
      end

      def get_tuple(config)
        thread_id = config.dig(:configurable, :thread_id)
        checkpoint_ns = config.dig(:configurable, :checkpoint_ns) || ""
        checkpoint_id = config.dig(:configurable, :checkpoint_id)

        if checkpoint_id
          saved = @storage[thread_id][checkpoint_ns][checkpoint_id]
          return nil unless saved

          build_tuple(thread_id, checkpoint_ns, checkpoint_id, saved, config)
        else
          checkpoints = @storage[thread_id][checkpoint_ns]
          return nil if checkpoints.empty?

          checkpoint_id = @order[thread_id][checkpoint_ns].last
          return nil unless checkpoint_id

          saved = checkpoints[checkpoint_id]
          result_config = {
            configurable: {
              thread_id: thread_id,
              checkpoint_ns: checkpoint_ns,
              checkpoint_id: checkpoint_id
            }
          }
          build_tuple(thread_id, checkpoint_ns, checkpoint_id, saved, result_config)
        end
      end

      def list(config, filter: nil, before: nil, limit: nil)
        thread_ids = config ? [config.dig(:configurable, :thread_id)] : @storage.keys
        results = []

        thread_ids.each do |thread_id|
          @storage[thread_id].each do |checkpoint_ns, checkpoints|
            _list_ns(thread_id, checkpoint_ns, checkpoints, results, filter: filter, before: before, limit: limit)
          end
        end

        results
      end

      def put(config, checkpoint, metadata, new_versions)
        thread_id = config.dig(:configurable, :thread_id)
        checkpoint_ns = config.dig(:configurable, :checkpoint_ns) || ""
        checkpoint_id = checkpoint[:id] || SecureRandom.uuid

        @storage[thread_id][checkpoint_ns][checkpoint_id] = {
          checkpoint: checkpoint,
          metadata: metadata,
          parent_checkpoint_id: config.dig(:configurable, :checkpoint_id)
        }
        @order[thread_id][checkpoint_ns] << checkpoint_id

        {
          configurable: {
            thread_id: thread_id,
            checkpoint_ns: checkpoint_ns,
            checkpoint_id: checkpoint_id
          }
        }
      end

      def put_writes(config, writes, task_id)
        thread_id = config.dig(:configurable, :thread_id)
        checkpoint_ns = config.dig(:configurable, :checkpoint_ns) || ""
        checkpoint_id = config.dig(:configurable, :checkpoint_id)
        key = [thread_id, checkpoint_ns, checkpoint_id]

        writes.each_with_index do |(channel, value), idx|
          @writes[key][[task_id, idx]] = { task_id: task_id, channel: channel, value: value }
        end
      end

      def delete_thread(thread_id)
        @storage.delete(thread_id)
        @order.delete(thread_id)
        @writes.delete_if { |key, _| key.first == thread_id }
      end

      private

      def _list_ns(thread_id, checkpoint_ns, checkpoints, results, filter:, before:, limit:)
        ordered_ids = @order[thread_id][checkpoint_ns].reverse
        entries = ordered_ids.filter_map { |id| [id, checkpoints[id]] if checkpoints[id] }

        entries.each do |checkpoint_id, saved|
          next if before && _skip_before?(checkpoint_id, before)
          next if filter && !_matches_filter?(saved[:metadata], filter)
          break if limit && results.length >= limit

          tuple_config = { configurable: { thread_id: thread_id, checkpoint_ns: checkpoint_ns,
                                           checkpoint_id: checkpoint_id } }
          results << build_tuple(thread_id, checkpoint_ns, checkpoint_id, saved, tuple_config)
        end
      end

      def _skip_before?(checkpoint_id, before)
        before_id = before.dig(:configurable, :checkpoint_id)
        before_id && checkpoint_id >= before_id
      end

      def _matches_filter?(metadata, filter)
        filter.all? { |k, v| metadata[k] == v }
      end

      def build_tuple(thread_id, checkpoint_ns, checkpoint_id, saved, config)
        pending = @writes[[thread_id, checkpoint_ns, checkpoint_id]].values
        parent_id = saved[:parent_checkpoint_id]

        parent_config = if parent_id
                          {
                            configurable: {
                              thread_id: thread_id,
                              checkpoint_ns: checkpoint_ns,
                              checkpoint_id: parent_id
                            }
                          }
                        end

        CheckpointTuple.new(
          config: config,
          checkpoint: saved[:checkpoint],
          metadata: saved[:metadata],
          parent_config: parent_config,
          pending_writes: pending.map { |w| [w[:task_id], w[:channel], w[:value]] }
        )
      end
    end
  end
end
