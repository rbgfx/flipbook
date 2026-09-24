# frozen_string_literal: true

module Flipbook
  module GIF
    class Writer
      def self.open(path, **options)
        io = File.open(path, "wb")
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

      def initialize(io, width:, height:, loop: true, palette: :per_frame, colors: 256, dither: :floyd_steinberg, optimize: true, transparent_index: nil, clear_background: false)
        @io = io
        @width = Integer(width)
        @height = Integer(height)
        raise ArgumentError, "GIF dimensions must be between 1 and 65535" unless @width.between?(1, 65_535) && @height.between?(1, 65_535)
        raise ArgumentError, "colors must be between 2 and 256" unless colors.is_a?(Integer) && colors.between?(2, 256)
        raise ArgumentError, "unknown dither: #{dither}" unless %i[none ordered floyd_steinberg].include?(dither)

        @loop = loop_value(loop)
        @colors = colors
        @dither = dither
        @clear_background = clear_background
        @optimize = optimize && !clear_background
        @previous = nil
        @elapsed = Rational(0)
        @rounded_delay = 0
        @closed = false
        @warned_short_delay = false
        @frame_count = 0
        @palette_mode = palette
        if palette == :per_frame
          raise ArgumentError, "clear_background requires a global palette" if clear_background
          raise ArgumentError, "transparent_index is only valid with a global palette" unless transparent_index.nil?
          @global_palette = nil
        else
          raise TypeError, "palette must be :per_frame or an RGB array" unless palette.is_a?(Array)
          @global_palette = validate_palette(palette)
          if (@optimize || clear_background) && transparent_index.nil?
            raise ArgumentError, "global palettes need room for a transparent color when optimize is enabled" if @global_palette.length == 256
            @global_palette = @global_palette + [[0, 0, 0]]
            transparent_index = @global_palette.length - 1
          end
          if transparent_index
            raise ArgumentError, "transparent_index must be the last palette entry" unless transparent_index == @global_palette.length - 1
            raise ArgumentError, "transparent_index is out of range" unless transparent_index.between?(0, @global_palette.length - 1)
            raise ArgumentError, "global palette must include opaque and transparent colors" if @global_palette.length < 2
          end
          @global_transparent_index = transparent_index
        end
        write_header
      end

      def add(image, delay:)
        raise IOError, "GIF writer is closed" if @closed
        raise TypeError, "frame must be a Tessel::Image" unless image.is_a?(Tessel::Image)
        raise ArgumentError, "frame dimensions must match the logical screen" unless image.width == @width && image.height == @height

        seconds = Timing.duration(delay)
        if seconds < Rational(1, 50) && !@warned_short_delay
          warn("Flipbook: delays below 1/50 second may be clamped by GIF viewers")
          @warned_short_delay = true
        end
        transparent_pixels = image.bytes.bytes.each_slice(4).any? { |_, _, _, alpha| alpha.zero? }
        if @palette_mode == :per_frame && @frame_count.positive? && (@previous_transparency || transparent_pixels)
          raise ArgumentError, "transparent multi-frame GIFs require a global palette"
        end
        elapsed = @elapsed + seconds
        target_delay = (elapsed * 100).floor
        frame_delay = target_delay - @rounded_delay
        raise ArgumentError, "GIF frame delays cannot exceed 655.35 seconds" if frame_delay > 65_535
        palette, opaque_palette, transparent_index = frame_palette(image, transparent_pixels)
        indices, = Tessel::Quantize.quantize(image, palette: opaque_palette, dither: @dither)
        if transparent_pixels
          raise ArgumentError, "palette has no transparent entry" unless transparent_index
          image.bytes.bytes.each_slice(4).with_index do |(_, _, _, alpha), index|
            indices.setbyte(index, transparent_index) if alpha.zero?
          end
        end

        left, top, width, height = @optimize ? Diff.bounds(@previous, image) : [0, 0, @width, @height]
        if @previous && @optimize && transparent_index
          image_bytes = image.bytes
          old_bytes = @previous.bytes
          (top...(top + height)).each do |y|
            (left...(left + width)).each do |x|
              offset = (y * @width + x) * 4
              indices.setbyte(y * @width + x, transparent_index) if image_bytes.byteslice(offset, 4) == old_bytes.byteslice(offset, 4)
            end
          end
        end
        frame_indices = crop_indices(indices, left, top, width, height)
        write_control(frame_delay, transparent_index)
        write_image(left, top, width, height, frame_indices, palette)
        @elapsed = elapsed
        @rounded_delay = target_delay
        @frame_count += 1
        @previous_transparency = transparent_pixels
        @previous = image.dup
        self
      end

      def close
        return if @closed
        raise Error, "GIF contains no frames" if @frame_count.zero?

        @io << ";".b
        @closed = true
        @io.close if @owns_io && !@io.closed?
        self
      end

      private

      def loop_value(value)
        return nil if value == false
        return 0 if value == true
        return value if value.is_a?(Integer) && value.between?(0, 65_535)

        raise ArgumentError, "loop must be true, false, or an integer from 0 to 65535"
      end

      def validate_palette(palette)
        raise ArgumentError, "palette must contain 1 to 256 colors" unless palette.length.between?(1, 256)
        palette.map do |color|
          unless color.is_a?(Array) && color.length == 3 && color.all? { |channel| channel.is_a?(Integer) && channel.between?(0, 255) }
            raise TypeError, "palette colors must be RGB triples"
          end
          color.dup
        end
      end

      def frame_palette(image, transparent_pixels)
        if @global_palette
          opaque = @global_transparent_index ? @global_palette[0...-1] : @global_palette
          raise ArgumentError, "transparent pixels need a transparent palette entry" if transparent_pixels && !@global_transparent_index
          return [@global_palette, opaque, @global_transparent_index]
        end

        reserve = @optimize || transparent_pixels
        opaque_count = reserve ? [@colors - 1, 1].max : @colors
        opaque = Tessel::Quantize.palette_for(image, colors: [opaque_count, 2].max).first(opaque_count)
        palette = reserve ? opaque + [[0, 0, 0]] : opaque
        [palette, opaque, reserve ? opaque.length : nil]
      end

      def write_header
        @io << "GIF89a".b << [@width, @height].pack("v2")
        if @global_palette
          bits, size = table_size(@global_palette.length)
          background = @clear_background ? @global_transparent_index : 0
          @io << [0x80 | 0x70 | (bits - 1), background, 0].pack("C3")
          write_palette(@global_palette, size)
        else
          @io << "\0\0\0".b
        end
        if @loop
          @io << "!\xFF\x0BNETSCAPE2.0\x03\x01".b << [@loop].pack("v") << "\0".b
        end
      end

      def write_control(delay, transparent_index)
        packed = @clear_background ? 0x08 : (@optimize ? 0x04 : 0)
        packed |= 0x01 if transparent_index
        @io << "!\xF9\x04".b << [packed, delay, transparent_index || 0, 0].pack("CvCC")
      end

      def write_image(left, top, width, height, indices, palette)
        local = !@global_palette
        bits, size = table_size(palette.length)
        descriptor_flags = local ? 0x80 | (bits - 1) : 0
        @io << ",".b << [left, top, width, height, descriptor_flags].pack("v4C")
        write_palette(palette, size) if local
        minimum = [bits, 2].max
        @io << minimum.chr(Encoding::BINARY) << LZW.encode(indices, minimum)
      end

      def table_size(count)
        bits = [[(count - 1).bit_length, 1].max, 8].min
        [bits, 1 << bits]
      end

      def write_palette(palette, size)
        palette.each { |rgb| @io << rgb.pack("C3") }
        (size - palette.length).times { @io << "\0\0\0".b }
      end

      def crop_indices(indices, left, top, width, height)
        output = String.new(capacity: width * height, encoding: Encoding::BINARY)
        height.times do |row|
          output << indices.byteslice((top + row) * @width + left, width)
        end
        output
      end
    end
  end
end
