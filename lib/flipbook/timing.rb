# frozen_string_literal: true

module Flipbook
  module Timing
    module_function

    def delays(count, fps: nil, delay: nil, warn_short: true)
      raise ArgumentError, "frame count must be a positive integer" unless count.is_a?(Integer) && count.positive?
      raise ArgumentError, "provide fps or delay, not both" if !fps.nil? && !delay.nil?
      raise ArgumentError, "fps or delay is required" if fps.nil? && delay.nil?

      values = if fps
        rate = rational(fps)
        raise ArgumentError, "fps must be positive" unless rate.positive?
        Array.new(count, 1 / rate)
      elsif delay.is_a?(Array)
        raise ArgumentError, "delay count must match frame count" unless delay.length == count
        delay.map { |value| positive_delay(value) }
      else
        Array.new(count) { positive_delay(delay) }
      end
      warn("Flipbook: delays below 1/50 second may be clamped by GIF viewers") if warn_short && values.any? { |value| value < Rational(1, 50) }
      values
    end

    def duration(value)
      positive_delay(value)
    end

    def centiseconds(delays)
      elapsed = Rational(0)
      rounded = 0
      delays.map do |delay|
        elapsed += rational(delay)
        target = (elapsed * 100).floor
        current = target - rounded
        rounded = target
        current
      end
    end

    def rational(value)
      raise TypeError, "delay and fps must be numeric" unless value.is_a?(Numeric)

      value.is_a?(Rational) ? value : Rational(value.to_s)
    rescue ArgumentError, ZeroDivisionError
      raise TypeError, "delay and fps must be numeric"
    end
    private_class_method :rational

    def positive_delay(value)
      result = rational(value)
      raise ArgumentError, "delay must be positive" unless result.positive?
      result
    end
    private_class_method :positive_delay
  end
end
