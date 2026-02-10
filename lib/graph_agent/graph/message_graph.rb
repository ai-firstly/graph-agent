# frozen_string_literal: true

module GraphAgent
  module Graph
    class MessagesState < State::Schema
      def initialize
        super
        field :messages, type: Array, reducer: GraphAgent::Reducers.method(:add_messages), default: []
      end
    end

    class MessageGraph < StateGraph
      def initialize
        super(MessagesState.new)
      end
    end
  end
end
