# frozen_string_literal: true

module Flipbook
  module Diff
    module_function

    # Returns the smallest changed rectangle, or nil when the images match.
    def bounds(previous, current)
      unless previous.is_a?(Tessel::Image) && current.is_a?(Tessel::Image)
        raise TypeError, "frames must be Tessel::Image values"
      end
      unless previous.width == current.width && previous.height == current.height
        raise ArgumentError, "frame dimensions must match"
      end

      left = current.width
      top = current.height
      right = -1
      bottom = -1
      before = previous.bytes
      after = current.bytes
      current.height.times do |y|
        current.width.times do |x|
          offset = (y * current.width + x) * 4
          next if before.byteslice(offset, 4) == after.byteslice(offset, 4)

          left = x if x < left
          top = y if y < top
          right = x if x > right
          bottom = y if y > bottom
        end
      end
      right.negative? ? nil : [left, top, right - left + 1, bottom - top + 1]
    end

    def crop(image, rectangle)
      x, y, width, height = rectangle
      image.crop(x, y, width, height)
    end
  end
end
