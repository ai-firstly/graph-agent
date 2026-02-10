# frozen_string_literal: true

module GraphAgent
  module State
    class Schema
      attr_reader :fields

      Field = Data.define(:name, :type, :reducer, :default)

      def initialize(&block)
        @fields = {}
        instance_eval(&block) if block
      end

      def field(name, type: nil, reducer: nil, default: nil)
        @fields[name.to_sym] = Field.new(
          name: name.to_sym,
          type: type,
          reducer: reducer,
          default: default
        )
      end

      def initial_state
        @fields.transform_values do |f|
          if f.default.nil?
            nil
          elsif f.default.respond_to?(:dup)
            begin
              f.default.dup
            rescue TypeError
              f.default
            end
          else
            f.default
          end
        end
      end

      def apply(state, updates)
        updates.each do |key, value|
          key = key.to_sym
          f = @fields[key]
          if f&.reducer
            state[key] = f.reducer.call(state[key], value)
          else
            state[key] = value
          end
        end
        state
      end
    end
  end
end
