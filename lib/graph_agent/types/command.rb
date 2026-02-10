# frozen_string_literal: true

module GraphAgent
  class Command
    PARENT = :__parent__

    attr_reader :graph, :update, :resume, :goto

    def initialize(graph: nil, update: nil, resume: nil, goto: [])
      @graph = graph
      @update = update
      @resume = resume
      @goto = Array(goto)
    end

    def to_s
      parts = []
      parts << "graph=#{graph.inspect}" if graph
      parts << "update=#{update.inspect}" if update
      parts << "resume=#{resume.inspect}" if resume
      parts << "goto=#{goto.inspect}" unless goto.empty?
      "Command(#{parts.join(", ")})"
    end
    alias inspect to_s
  end
end
