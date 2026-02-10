# frozen_string_literal: true

require "securerandom"

module GraphAgent
  class Interrupt
    attr_reader :value, :id

    def initialize(value, id: nil)
      @value = value
      @id = id || SecureRandom.hex(16)
    end

    def ==(other)
      other.is_a?(Interrupt) && id == other.id && value == other.value
    end
    alias eql? ==

    def hash
      [id, value].hash
    end

    def to_s
      "Interrupt(value=#{value.inspect}, id=#{id.inspect})"
    end
    alias inspect to_s
  end
end
