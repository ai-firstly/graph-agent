# frozen_string_literal: true

module GraphAgent
  class CachePolicy
    attr_reader :key_func, :ttl

    def initialize(key_func: nil, ttl: nil)
      @key_func = key_func
      @ttl = ttl
    end
  end
end
