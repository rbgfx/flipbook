# frozen_string_literal: true

require "tessel"

require_relative "flipbook/version"
require_relative "flipbook/timing"
require_relative "flipbook/output"
require_relative "flipbook/gif/bit_writer"
require_relative "flipbook/gif/lzw"
require_relative "flipbook/gif/reader"
require_relative "flipbook/gif/writer"
require_relative "flipbook/apng/writer"
require_relative "flipbook/diff"

module Flipbook
  class Error < StandardError; end

  module_function

  def write(path, frames, fps: nil, delay: nil, loop: true, colors: 256, palette: :global, dither: :floyd_steinberg, optimize: true)
    raise TypeError, "frames must be an array of Tessel::Image values" unless frames.is_a?(Array) && frames.all? { |frame| frame.is_a?(Tessel::Image) }
    raise ArgumentError, "at least one frame is required" if frames.empty?
    raise ArgumentError, "frame dimensions must match" unless frames.all? { |frame| frame.width == frames.first.width && frame.height == frames.first.height }

    extension = File.extname(String(path)).downcase
    raise ArgumentError, "output path must end in .gif, .png, or .apng" unless %w[.gif .png .apng].include?(extension)

    delays = Timing.delays(frames.length, fps:, delay:, warn_short: extension == ".gif")
    if extension == ".gif"
      write_gif(path, frames, delays, loop:, colors:, palette:, dither:, optimize:)
    else
      APNG::Writer.open(path, width: frames.first.width, height: frames.first.height, loop:, optimize:) do |writer|
        frames.zip(delays).each do |frame, frame_delay|
          writer.add(frame, delay: frame_delay)
        end
      end
    end
  end

  def read(path, **options)
    GIF::Reader.read(path, **options)
  end

  def write_gif(path, frames, delays, loop:, colors:, palette:, dither:, optimize:)
    has_transparency = frames.any? { |frame| frame.bytes.bytes.each_slice(4).any? { |_, _, _, alpha| alpha.zero? } }
    transparent = has_transparency
    global_palette = if palette == :per_frame
      raise ArgumentError, "per-frame palettes cannot preserve transparency across frames" if has_transparency
      :per_frame
    elsif palette == :global
      opaque_count = transparent ? [colors - 1, 1].max : colors
      opaque = Tessel::Quantize.palette_for(frames, colors: [opaque_count, 2].max).first(opaque_count)
      transparent ? opaque + [[0, 0, 0]] : opaque
    elsif palette.is_a?(Array)
      if transparent
        raise ArgumentError, "palette needs one free entry for transparency" if palette.length >= 256
        palette + [[0, 0, 0]]
      else
        palette
      end
    else
      raise ArgumentError, "palette must be :global, :per_frame, or an RGB array"
    end
    transparent_index = global_palette.is_a?(Array) && transparent ? global_palette.length - 1 : nil

    GIF::Writer.open(path, width: frames.first.width, height: frames.first.height, loop:, palette: global_palette, colors:, dither:, transparent_index:, optimize:) do |writer|
      frames.zip(delays).each { |frame, frame_delay| writer.add(frame, delay: frame_delay) }
    end
  end
  private_class_method :write_gif

end
