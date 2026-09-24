# frozen_string_literal: true

module Flipbook
  module Diff
    module_function

    def bounds(previous, current)
      raise TypeError, "current must be a Tessel::Image" unless current.is_a?(Tessel::Image)
      return [0, 0, current.width, current.height] unless previous
      raise TypeError, "previous must be a Tessel::Image" unless previous.is_a?(Tessel::Image)
      raise ArgumentError, "image dimensions must match" unless previous.width == current.width && previous.height == current.height

      old_bytes = previous.bytes
      new_bytes = current.bytes
      left, top, right, bottom = current.width, current.height, -1, -1
      (0...(current.width * current.height)).each do |index|
        offset = index * 4
        next if old_bytes.byteslice(offset, 4) == new_bytes.byteslice(offset, 4)

        x = index % current.width
        y = index / current.width
        left = x if x < left
        top = y if y < top
        right = x if x > right
        bottom = y if y > bottom
      end
      right.negative? ? [0, 0, 1, 1] : [left, top, right - left + 1, bottom - top + 1]
    end
  end
end
