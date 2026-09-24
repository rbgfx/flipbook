# frozen_string_literal: true

require "stringio"

module Flipbook
  module APNG
    class Writer
      def self.open(path, **options)
        io = File.open(path, "wb+")
        writer = new(io, **options)
        writer.instance_variable_set(:@owns_io, true)
        return writer unless block_given?

        begin
          yield writer
        ensure
          writer.close
        end
        path
      rescue StandardError
        io&.close unless io&.closed?
        raise
      end

      def initialize(io, width:, height:, loop: true, optimize: true, level: Zlib::DEFAULT_COMPRESSION, filter: :none)
        @io = io
        @width = Integer(width)
        @height = Integer(height)
        raise ArgumentError, "APNG dimensions must be positive" unless @width.positive? && @height.positive?
        raise ArgumentError, "unknown PNG filter: #{filter}" unless %i[none sub up average paeth adaptive].include?(filter)

        @loop = plays(loop)
        @optimize = optimize
        @level = level
        @filter = filter
        @seekable = io.respond_to?(:pos) && io.respond_to?(:seek)
        @storage = @seekable ? io : StringIO.new("".b)
        @frames = 0
        @sequence = 0
        @previous = nil
        @closed = false
        @storage << Tessel::SIGNATURE
        Tessel::PNG::Chunk.write(@storage, "IHDR", [@width, @height, 8, 6, 0, 0, 0].pack("N2C5"))
        @animation_offset = @storage.pos
        write_chunk("acTL", [0, @loop].pack("N2"))
      end

      def add(image, delay:)
        raise IOError, "APNG writer is closed" if @closed
        raise TypeError, "frame must be a Tessel::Image" unless image.is_a?(Tessel::Image)
        raise ArgumentError, "frame dimensions must match the animation" unless image.width == @width && image.height == @height

        seconds = Timing.duration(delay)
        left, top, width, height = @optimize ? Diff.bounds(@previous, image) : [0, 0, @width, @height]
        frame = image.crop(left, top, width, height)
        numerator, denominator = Timing.apng_fraction(seconds)
        compressed = idat_data(frame)
        raise Error, "APNG frame count exceeds the format limit" if @frames >= 0xFFFF_FFFF
        control = [@sequence, width, height, left, top, numerator, denominator, 0, 0].pack("N5n2C2")
        write_chunk("fcTL", control)
        @sequence += 1
        if @frames.zero?
          write_chunk("IDAT", compressed)
        else
          write_chunk("fdAT", [@sequence].pack("N") + compressed)
          @sequence += 1
        end
        @frames += 1
        @previous = image.dup
        self
      end

      def close
        return if @closed
        raise Error, "APNG contains no frames" if @frames.zero?

        write_chunk("IEND", "".b)
        finish_animation_control
        @io << @storage.string if @storage != @io
        @closed = true
        @io.close if @owns_io && !@io.closed?
        self
      end

      private

      def plays(value)
        return 0 if value == true
        return 1 if value == false
        return value if value.is_a?(Integer) && value.between?(0, 0xFFFF_FFFF)

        raise ArgumentError, "loop must be true, false, or an integer from 0 to 4294967295"
      end

      def write_chunk(type, data)
        Tessel::PNG::Chunk.write(@storage, type, data)
      end

      def idat_data(image)
        png = Tessel::PNG.encode(image, color_type: :rgba, filter: @filter, level: @level, metadata: {})
        output = "".b
        cursor = Tessel::SIGNATURE.bytesize
        while cursor + 12 <= png.bytesize
          length = png.byteslice(cursor, 4).unpack1("N")
          type = png.byteslice(cursor + 4, 4)
          output << png.byteslice(cursor + 8, length) if type == "IDAT"
          cursor += length + 12
          break if type == "IEND"
        end
        raise Error, "Tessel produced a PNG without image data" if output.empty?

        output
      end

      def finish_animation_control
        control = [@frames, @loop].pack("N2")
        ending = @storage.pos
        @storage.seek(@animation_offset)
        write_chunk("acTL", control)
        @storage.seek(ending)
      end
    end
  end
end
