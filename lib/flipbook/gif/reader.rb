# frozen_string_literal: true

module Flipbook
  module GIF
    class Reader
      def self.read(path, max_pixels: 16_384 * 16_384, max_frames: 10_000, max_total_pixels: 100_000_000)
        new(File.binread(path), max_pixels:, max_frames:, max_total_pixels:).read
      end

      def initialize(bytes, max_pixels: 16_384 * 16_384, max_frames: 10_000, max_total_pixels: 100_000_000)
        @bytes = String(bytes).b
        @offset = 0
        @max_pixels = Integer(max_pixels)
        @max_frames = Integer(max_frames)
        @max_total_pixels = Integer(max_total_pixels)
        raise ArgumentError, "limits must be positive" unless @max_pixels.positive? && @max_frames.positive? && @max_total_pixels.positive?
      end

      def read
        signature = take(6)
        raise Error, "invalid GIF signature" unless %w[GIF87a GIF89a].include?(signature)

        @width, @height, packed, background_index, = take(7).unpack("v2C3")
        raise Error, "invalid GIF dimensions" if @width.zero? || @height.zero? || @width * @height > @max_pixels

        @global_palette = read_palette(1 << ((packed & 7) + 1)) if (packed & 0x80).positive?
        @background_index = background_index
        @background = palette_color(@global_palette, background_index)
        @frames = []
        @canvas = Tessel::Image.new(@width, @height, fill: @background)
        @control = default_control
        @previous_disposal = nil
        @finished = false

        until @finished
          marker = byte
          case marker
          when 0x21 then read_extension
          when 0x2c then read_image
          when 0x3b then @finished = true
          else raise Error, "invalid GIF block marker 0x#{marker.to_s(16)}"
          end
        end
        raise Error, "GIF contains no frames" if @frames.empty?

        @frames
      end

      private

      def default_control
        { delay: 0, disposal: 0, transparent: nil }
      end

      def read_extension
        label = byte
        case label
        when 0xf9
          size = byte
          raise Error, "invalid GIF graphic control extension" unless size == 4

          packed, delay, transparent_index = take(4).unpack("C v C")
          raise Error, "invalid GIF graphic control terminator" unless byte.zero?
          disposal = (packed >> 2) & 7
          raise Error, "unsupported GIF disposal method" if disposal > 3

          @control = { delay: delay, disposal:, transparent: (packed & 1).positive? ? transparent_index : nil }
        when 0x01
          skip_sub_blocks # fixed plain-text header and text data are both sub-blocks
        else
          skip_sub_blocks
        end
      end

      def read_image
        left, top, width, height, packed = take(9).unpack("v4C")
        raise Error, "invalid GIF image dimensions" if width.zero? || height.zero?
        raise Error, "GIF image rectangle is outside the canvas" if left + width > @width || top + height > @height

        palette = (packed & 0x80).positive? ? read_palette(1 << ((packed & 7) + 1)) : @global_palette
        raise Error, "GIF frame has no color table" unless palette
        raise Error, "GIF transparent palette index is out of range" if @control[:transparent] && @control[:transparent] >= palette.length
        minimum_code_size = byte
        raise Error, "invalid GIF LZW code size" unless minimum_code_size.between?(2, 8)

        indices = LZW.decode(read_sub_blocks, minimum_code_size, width * height)
        indices = deinterlace(indices, width, height) if (packed & 0x40).positive?
        draw_frame(indices, palette, left, top, width, height)
      end

      def draw_frame(indices, palette, left, top, width, height)
        disposal = @control[:disposal]
        if @previous_disposal
          previous = @previous_disposal
          case previous[:method]
          when 2
            @canvas.fill_rect(*previous[:rect], previous[:background])
          when 3
            @canvas = previous[:restore]
          end
        end

        raise Error, "GIF frame limit exceeded" if @frames.length >= @max_frames
        raise Error, "GIF total pixel limit exceeded" if (@frames.length + 1) * @width * @height > @max_total_pixels
        restore = @canvas.dup if disposal == 3
        transparent = @control[:transparent]
        transparent_background = transparent && (!@global_palette || transparent == @background_index)
        @canvas.clear([0, 0, 0, 0]) if @frames.empty? && transparent_background
        indices.each_with_index do |palette_index, index|
          next if palette_index == transparent

          color = palette[palette_index]
          raise Error, "GIF palette index is out of range" unless color

          x = left + index % width
          y = top + index / width
          @canvas[x, y] = [*color, 255]
        end
        @frames << @canvas.dup
        background = if transparent_background
          [0, 0, 0, 0]
        else
          [*@background, 255]
        end
        @previous_disposal = { method: disposal, rect: [left, top, width, height], background:, restore: }
        @control = default_control
      end

      def deinterlace(indices, width, height)
        rows = Array.new(height)
        offset = 0
        [[0, 8], [4, 8], [2, 4], [1, 2]].each do |start, step|
          (start...height).step(step) do |y|
            rows[y] = indices.slice(offset, width)
            offset += width
          end
        end
        rows.flatten
      end

      def read_palette(count)
        take(count * 3).unpack("C*").each_slice(3).map(&:freeze)
      end

      def palette_color(palette, index)
        color = palette&.[](index)
        color || [0, 0, 0]
      end

      def read_sub_blocks
        output = "".b
        loop do
          length = byte
          break if length.zero?

          output << take(length)
        end
        output
      end

      def skip_sub_blocks
        loop do
          length = byte
          break if length.zero?

          take(length)
        end
      end

      def take(length)
        raise Error, "truncated GIF data" if length.negative? || @offset + length > @bytes.bytesize

        result = @bytes.byteslice(@offset, length)
        @offset += length
        result
      end

      def byte
        take(1).getbyte(0)
      end
    end

    module LZW
      module_function

      def decode(bytes, minimum_code_size, expected_size)
        clear = 1 << minimum_code_size
        ending = clear + 1
        prefix = Array.new(4096)
        suffix = Array.new(4096)
        clear.times { |index| suffix[index] = index }
        next_code = ending + 1
        width = minimum_code_size + 1
        bit_offset = 0
        previous = nil
        first = nil
        output = String.new(capacity: expected_size, encoding: Encoding::BINARY)
        ended = false

        loop do
          code = read_code(bytes, bit_offset, width)
          break unless code

          bit_offset += width
          if code == clear
            clear.times { |index| suffix[index] = index }
            next_code = ending + 1
            width = minimum_code_size + 1
            previous = nil
            next
          end
          if code == ending
            ended = true
            break
          end

          if code < next_code && suffix[code]
            entry, first = expand(code, clear, prefix, suffix)
          elsif code == next_code && previous
            entry, first = expand(previous, clear, prefix, suffix)
            entry << first
          else
            raise Error, "invalid GIF LZW code"
          end
          output << entry.pack("C*")
          raise Error, "GIF frame data exceeds its dimensions" if output.bytesize > expected_size

          if previous && next_code < 4096
            prefix[next_code] = previous
            suffix[next_code] = first
            next_code += 1
            width += 1 if next_code == (1 << width) && width < 12
          end
          previous = code
        end
        raise Error, "truncated GIF LZW data" unless ended && output.bytesize == expected_size

        output.bytes
      end

      def expand(code, clear, prefix, suffix)
        stack = []
        current = code
        while current >= clear
          raise Error, "invalid GIF LZW dictionary" unless current < 4096 && suffix[current] && prefix[current]

          stack << suffix[current]
          current = prefix[current]
        end
        stack << current
        first = current
        [stack.reverse, first]
      end
      private_class_method :expand

      def read_code(bytes, bit_offset, width)
        return nil if bit_offset + width > bytes.bytesize * 8

        code = 0
        width.times do |bit|
          code |= ((bytes.getbyte((bit_offset + bit) / 8) >> ((bit_offset + bit) % 8)) & 1) << bit
        end
        code
      end
      private_class_method :read_code
    end
  end
end
