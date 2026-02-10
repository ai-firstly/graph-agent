# frozen_string_literal: true

module GraphAgent
  class RetryPolicy
    attr_reader :initial_interval, :backoff_factor, :max_interval,
                :max_attempts, :jitter, :retry_on

    def initialize(
      initial_interval: 0.5,
      backoff_factor: 2.0,
      max_interval: 128.0,
      max_attempts: 3,
      jitter: true,
      retry_on: StandardError
    )
      @initial_interval = initial_interval
      @backoff_factor = backoff_factor
      @max_interval = max_interval
      @max_attempts = max_attempts
      @jitter = jitter
      @retry_on = retry_on
    end

    def should_retry?(error)
      case @retry_on
      when Proc
        @retry_on.call(error)
      when Array
        @retry_on.any? { |klass| error.is_a?(klass) }
      else
        error.is_a?(@retry_on)
      end
    end

    def interval_for(attempt)
      interval = @initial_interval * (@backoff_factor**attempt)
      interval = [interval, @max_interval].min
      interval += rand * interval * 0.1 if @jitter
      interval
    end
  end
end
