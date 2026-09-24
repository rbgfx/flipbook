# frozen_string_literal: true

module Flipbook
  module GIF
    class Reader
      attr_reader :width, :height

      def self.read(path)
        new(File.binread(path)).frames
      end

      def initialize(data, max_pixels: 16_777_216, max_frames: 10_000, max_total_pixels: 67_108_864)
        @data = String(data).b
        @cursor = 0
        @max_pixels = max_pixels
        @max_frames = max_frames
        @max_total_pixels = max_total_pixels
        @decoded_pixels = 0
        @frames = []
        @delays = []
        decode
      end

      def frames
        @frames.map(&:dup).freeze
      end

      def delays
        @delays.dup.freeze
      end

      def each(&block)
        return enum_for(:each) unless block

        @frames.each(&block)
      end

      private

      def decode
        raise Error, "invalid GIF signature" unless take(6).match?(/\AGIF8[79]a\z/)

        @width, @height, packed, @background_index, = take(7).unpack("v2C3")
        raise Error, "invalid GIF dimensions" unless @width.positive? && @height.positive?
        raise Error, "GIF exceeds pixel limit" if @width * @height > @max_pixels

        global = (packed & 0x80).zero? ? nil : read_palette(1 << ((packed & 7) + 1))
        background = global && global[@background_index]
        canvas = Tessel::Image.new(@width, @height)
        @current_control = { disposal: 1, delay: 0, transparent: nil }
        previous = nil
        previous_disposal = 0
        restore = nil
        control = { disposal: 1, delay: 0, transparent: nil }

        until @cursor >= @data.bytesize
          marker = byte
          case marker
          when 0x3B then break
          when 0x21 then read_extension(control)
          when 0x2C
            raise Error, "GIF exceeds frame limit" if @frames.length >= @max_frames
            @current_control = control
            frame = read_frame(global)
            if previous
              if previous_disposal == 2
                color = control_background(global, background, previous[:control][:transparent])
                canvas.fill_rect(previous[:left], previous[:top], previous[:width], previous[:height], color)
              elsif previous_disposal == 3 && restore
                canvas = restore.dup
              end
            elsif background && frame[:control][:transparent] != @background_index
              canvas.clear([*background, 255])
            end
            restore = canvas.dup if frame[:control][:disposal] == 3
            composite(canvas, frame)
            @frames << canvas.dup
            @delays << Rational(frame[:control][:delay], 100)
            previous = frame
            previous_disposal = frame[:control][:disposal]
            control = { disposal: 1, delay: 0, transparent: nil }
            @current_control = control
          else
            raise Error, "invalid GIF block marker"
          end
        end
        raise Error, "GIF contains no frames" if @frames.empty?
      end

      def read_extension(control)
        label = byte
        if label == 0xF9
          raise Error, "invalid GIF control extension" unless byte == 4
          packed, delay, transparent = take(4).unpack("CvC")
          raise Error, "invalid GIF control terminator" unless byte.zero?
          control.replace(disposal: (packed >> 2) & 7, delay: delay, transparent: (packed & 1).zero? ? nil : transparent)
        else
          skip_sub_blocks
        end
      end

      def read_frame(global)
        left, top, width, height, packed = take(9).unpack("v4C")
        raise Error, "invalid GIF frame dimensions" unless width.positive? && height.positive?
        raise Error, "GIF frame exceeds pixel limit" if width * height > @max_pixels
        raise Error, "GIF exceeds total decoded pixel limit" if @decoded_pixels + width * height > @max_total_pixels
        raise Error, "GIF frame lies outside the logical screen" if left + width > @width || top + height > @height

        local = (packed & 0x80).zero? ? nil : read_palette(1 << ((packed & 7) + 1))
        palette = local || global
        raise Error, "GIF frame has no color table" unless palette
        minimum = byte
        compressed = read_sub_blocks
        indices = LZW.decode(compressed, minimum, expected_size: width * height)
        indices = deinterlace(indices, width, height) unless (packed & 0x40).zero?
        @decoded_pixels += width * height
        { left:, top:, width:, height:, palette:, indices:, control: @current_control.dup }
      end

      def composite(canvas, frame)
        frame[:height].times do |row|
          frame[:width].times do |column|
            index = frame[:indices].getbyte(row * frame[:width] + column)
            next if index == frame[:control][:transparent]

            color = frame[:palette][index]
            raise Error, "GIF color index out of range" unless color
            canvas[frame[:left] + column, frame[:top] + row] = [*color, 255]
          end
        end
      end

      def control_background(global, background, transparent)
        return [0, 0, 0, 0] if transparent == @background_index
        return [0, 0, 0, 0] unless global && background

        [*background, 255]
      end

      def deinterlace(indices, width, height)
        rows = [0, 4, 2, 1].flat_map do |start|
          step = { 0 => 8, 4 => 8, 2 => 4, 1 => 2 }.fetch(start)
          (start...height).step(step).to_a
        end
        output = "\0".b * indices.bytesize
        rows.each_with_index do |row, source_row|
          output[row * width, width] = indices.byteslice(source_row * width, width)
        end
        output
      end

      def read_palette(count)
        take(count * 3).bytes.each_slice(3).map(&:freeze)
      end

      def skip_sub_blocks
        read_sub_blocks
      end

      def read_sub_blocks
        output = "".b
        loop do
          length = byte
          break if length.zero?
          raise Error, "GIF sub-block exceeds input" if @cursor + length > @data.bytesize

          output << take(length)
        end
        output
      end

      def byte
        raise Error, "truncated GIF" if @cursor >= @data.bytesize

        value = @data.getbyte(@cursor)
        @cursor += 1
        value
      end

      def take(length)
        raise Error, "truncated GIF" if length.negative? || @cursor + length > @data.bytesize

        value = @data.byteslice(@cursor, length)
        @cursor += length
        value
      end
    end
  end
end
