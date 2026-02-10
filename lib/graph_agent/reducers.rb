# frozen_string_literal: true

module GraphAgent
  module Reducers
    ADD = ->(a, b) { a + b }
    MERGE = ->(a, b) { a.merge(b) }
    REPLACE = ->(_, b) { b }
    APPEND = ->(a, b) { Array(a) + Array(b) }

    module_function

    def add_messages(existing, new_messages)
      existing = Array(existing)
      new_messages = Array(new_messages)

      existing_by_id = {}
      existing.each_with_index do |msg, idx|
        if msg.is_a?(Hash) && msg[:id]
          existing_by_id[msg[:id]] = idx
        end
      end

      result = existing.dup
      new_messages.each do |msg|
        if msg.is_a?(Hash) && msg[:id] && existing_by_id.key?(msg[:id])
          result[existing_by_id[msg[:id]]] = msg
        else
          result << msg
        end
      end
      result
    end
  end
end
