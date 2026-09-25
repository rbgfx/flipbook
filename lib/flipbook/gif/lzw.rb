# frozen_string_literal: true

module Flipbook
  module GIF
    module LZW
      module_function

      def encode(indices, minimum_code_size)
        minimum_code_size = Integer(minimum_code_size)
        raise ArgumentError, "minimum code size must be between 2 and 8" unless minimum_code_size.between?(2, 8)

        clear_code = 1 << minimum_code_size
        end_code = clear_code + 1
        next_code = end_code + 1
        code_width = minimum_code_size + 1
        dictionary = {}
        writer = BitWriter.new
        writer.write(clear_code, code_width)
        bytes = String(indices).b
        return writer.tap { |bits| bits.write(end_code, code_width) }.sub_blocks if bytes.empty?

        prefix = bytes.getbyte(0)
        bytes.byteslice(1..).to_s.each_byte do |byte|
          key = (prefix << 8) | byte
          if dictionary.key?(key)
            prefix = dictionary[key]
            next
          end

          writer.write(prefix, code_width)
          if next_code < 4096
            dictionary[key] = next_code
            next_code += 1
            code_width += 1 if next_code > (1 << code_width) && code_width < 12
          else
            writer.write(clear_code, code_width)
            dictionary.clear
            next_code = end_code + 1
            code_width = minimum_code_size + 1
          end
          prefix = byte
        end
        writer.write(prefix, code_width)
        code_width += 1 if next_code == (1 << code_width) && code_width < 12
        writer.write(end_code, code_width)
        writer.sub_blocks
      end

    end
  end
end
