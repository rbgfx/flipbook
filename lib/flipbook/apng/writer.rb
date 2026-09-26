# frozen_string_literal: true

require "stringio"

module Flipbook
  module APNG
    class Writer
      def self.open(path, **options, &block)
        Output.open(self, path, **options, &block)
      end

      def initialize(io, width:, height:, loop: true, optimize: true, buffered: nil)
        @io = io
        @width = Integer(width)
        @height = Integer(height)
        raise ArgumentError, "APNG dimensions must be between 1 and 2147483647" unless @width.between?(1, 2_147_483_647) && @height.between?(1, 2_147_483_647)
        raise TypeError, "optimize must be true or false" unless [true, false].include?(optimize)

        @loop = loop_count(loop)
        @optimize = optimize
        @buffered = buffered.nil? ? !seekable?(io) : buffered
        @frames = []
        @previous_image = nil
        @frame_count = 0
        @sequence = 0
        @closed = false
        write_header unless @buffered
      end

      def add(image, delay:)
        raise IOError, "APNG writer is closed" if @closed
        raise TypeError, "frame must be a Tessel::Image" unless image.is_a?(Tessel::Image)
        raise ArgumentError, "frame dimensions must match the canvas" unless image.width == @width && image.height == @height

        seconds = Timing.duration(delay)
        if @buffered
          @frames << [image.dup, seconds]
        else
          write_frame(image, seconds)
        end
        @frame_count += 1
        @previous_image = image.dup
        self
      end

      def close
        return self if @closed
        raise Error, "APNG contains no frames" if @frame_count.zero?

        if @buffered
          output = StringIO.new("".b)
          writer = self.class.new(output, width: @width, height: @height, loop: @loop, optimize: @optimize, buffered: false)
          @frames.each { |image, delay| writer.add(image, delay:) }
          writer.close
          @io.write(output.string)
        else
          write_chunk("IEND", "".b)
          patch_animation_control
        end
        @closed = true
        Output.finish(@io, @target_path, @target_mode) if @owns_io
        self
      end

      private

      def seekable?(io)
        io.respond_to?(:pos) && io.respond_to?(:seek)
      rescue IOError, SystemCallError
        false
      end

      def loop_count(value)
        return 0 if value == true
        return 1 if value == false
        return value if value.is_a?(Integer) && value.between?(0, 0xffff_ffff)

        raise ArgumentError, "loop must be true, false, or an integer from 0 to 4294967295"
      end

      def write_header
        @io << Tessel::SIGNATURE
        write_chunk("IHDR", [@width, @height, 8, 6, 0, 0, 0].pack("N2C5"))
        @actl_data_position = @io.pos + 8
        write_chunk("acTL", [1, @loop].pack("N2"))
      end

      def write_frame(image, delay)
        rectangle = if @frame_count.zero? || !@optimize
          [0, 0, @width, @height]
        else
          Diff.bounds(@previous_image, image) || [0, 0, 1, 1]
        end
        x, y, width, height = rectangle
        frame = rectangle == [0, 0, @width, @height] ? image : image.crop(x, y, width, height)
        numerator, denominator = delay_fraction(delay)
        alpha = frame.bytes.bytes.each_slice(4).any? { |_, _, _, channel| channel < 255 }
        blend = @frame_count.zero? || alpha ? 0 : 1
        control = [@sequence, width, height, x, y].pack("N5") + [numerator, denominator, 0, blend].pack("n2C2")
        write_chunk("fcTL", control)
        @sequence += 1

        png = Tessel::PNG::Encoder.encode(frame)
        idat = png_chunks(png).select { |type, _| type == "IDAT" }.map(&:last).join
        if @frame_count.zero?
          write_chunk("IDAT", idat)
        else
          write_chunk("fdAT", [@sequence].pack("N") + idat)
          @sequence += 1
        end
      end

      def delay_fraction(delay)
        raise ArgumentError, "APNG frame delay cannot exceed 65535 seconds" if delay > 65_535

        if delay.numerator <= 65_535 && delay.denominator <= 65_535
          return [delay.numerator, delay.denominator]
        end

        denominator = [65_535, (65_535 / delay).floor].min
        denominator = 65_535 if denominator < 1
        numerator = (delay * denominator).round.clamp(1, 65_535)
        [numerator, denominator]
      end

      def png_chunks(png)
        chunks = []
        offset = Tessel::SIGNATURE.bytesize
        while offset < png.bytesize
          length = png.unpack1("N", offset:)
          type = png.byteslice(offset + 4, 4)
          data = png.byteslice(offset + 8, length)
          chunks << [type, data]
          offset += length + 12
          break if type == "IEND"
        end
        chunks
      end

      def write_chunk(type, data)
        Tessel::PNG::Chunk.write(@io, type, data)
      end

      def patch_animation_control
        end_position = @io.pos
        data = [@frame_count, @loop].pack("N2")
        @io.seek(@actl_data_position)
        @io.write(data)
        @io.write([Zlib.crc32("acTL".b + data)].pack("N"))
        @io.seek(end_position)
      end
    end
  end
end
