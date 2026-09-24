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

      def decode(bytes, minimum_code_size, expected_size: nil)
        raise ArgumentError, "minimum code size must be between 2 and 8" unless minimum_code_size.is_a?(Integer) && minimum_code_size.between?(2, 8)

        bytes = String(bytes).b
        clear_code = 1 << minimum_code_size
        end_code = clear_code + 1
        dictionary = initial_dictionary(clear_code)
        next_code = end_code + 1
        code_width = minimum_code_size + 1
        bit_offset = 0
        previous = nil
        output = "".b
        ended = false
        loop do
          code = read_code(bytes, bit_offset, code_width)
          break if code.nil?
          bit_offset += code_width
          if code == clear_code
            dictionary = initial_dictionary(clear_code)
            next_code = end_code + 1
            code_width = minimum_code_size + 1
            previous = nil
            next
          end
          if code == end_code
            ended = true
            break
          end

          entry = if code < dictionary.length && dictionary[code]
            dictionary[code]
          elsif code == next_code && previous
            previous + [previous.first]
          else
            raise Error, "invalid GIF LZW code"
          end
          output << entry.pack("C*")
          raise Error, "GIF frame expands beyond its dimensions" if expected_size && output.bytesize > expected_size

          if previous && next_code < 4096
            dictionary[next_code] = previous + [entry.first]
            next_code += 1
            code_width += 1 if next_code == (1 << code_width) && code_width < 12
          end
          previous = entry
        end
        raise Error, "GIF LZW data is truncated" unless ended && (!expected_size || output.bytesize == expected_size)

        output
      end

      def initial_dictionary(clear_code)
        Array.new(clear_code) { |index| [index] } + [nil, nil]
      end
      private_class_method :initial_dictionary

      def read_code(bytes, bit_offset, width)
        return nil if bit_offset + width > bytes.bytesize * 8

        value = 0
        width.times do |bit|
          value |= ((bytes.getbyte((bit_offset + bit) / 8) >> ((bit_offset + bit) % 8)) & 1) << bit
        end
        value
      end
      private_class_method :read_code
    end
  end
end
