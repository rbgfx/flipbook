# frozen_string_literal: true

module Flipbook
  module GIF
    class BitWriter
      def initialize
        @bytes = "".b
        @buffer = 0
        @bits = 0
      end

      def write(code, width)
        @buffer |= code << @bits
        @bits += width
        while @bits >= 8
          @bytes << (@buffer & 255)
          @buffer >>= 8
          @bits -= 8
        end
      end

      def sub_blocks
        @bytes << (@buffer & 255) if @bits.positive?
        output = "".b
        @bytes.bytes.each_slice(255) { |slice| output << slice.length << slice.pack("C*") }
        output << "\0".b
      end
    end
  end
end
