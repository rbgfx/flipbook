# frozen_string_literal: true

require "test/unit"
require "tmpdir"
require "flipbook"

class FlipbookTest < Test::Unit::TestCase
  def test_gif_lzw_round_trips_code_width_growth_and_dictionary_reset
    bytes = String.new(capacity: 20_000, encoding: Encoding::BINARY)
    state = 1
    20_000.times do
      state = (state * 1_103_515_245 + 12_345) & 0x7fff_ffff
      bytes << (state & 255)
    end

    encoded = Flipbook::GIF::LZW.encode(bytes, 8)
    assert_equal bytes, Flipbook::GIF::LZW.decode(unwrap_sub_blocks(encoded), 8, expected_size: bytes.bytesize)
  end

  def test_gif_uses_cumulative_centisecond_rounding_and_reads_optimized_frames
    images = [solid([255, 0, 0, 255]), solid([255, 0, 0, 255]), solid([255, 0, 0, 255])]
    images[1][1, 0] = [0, 0, 255, 255]
    images[2][1, 0] = [0, 255, 0, 255]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "test.gif")
      Flipbook.write(path, images, fps: 30)
      reader = Flipbook::GIF::Reader.new(File.binread(path))

      assert_equal [Rational(3, 100), Rational(3, 100), Rational(4, 100)], reader.delays
      assert_equal [255, 0, 0, 255], reader.frames[0][0, 0]
      assert_equal [0, 0, 255, 255], reader.frames[1][1, 0]
      assert_equal [0, 255, 0, 255], reader.frames[2][1, 0]
    end
  end

  def test_gif_clears_to_transparency_when_a_pixel_becomes_transparent
    first = solid([255, 0, 0, 255])
    second = first.dup
    second[0, 0] = [0, 0, 0, 0]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "alpha.gif")
      Flipbook.write(path, [first, second], fps: 10)
      decoded = Flipbook.read(path)

      assert_equal [255, 0, 0, 255], decoded[0][0, 0]
      assert_equal [0, 0, 0, 0], decoded[1][0, 0]
      assert_equal [255, 0, 0, 255], decoded[1][1, 0]
    end
  end

  def test_apng_has_valid_chunk_sequence_and_keeps_the_first_frame_as_png
    first = solid([255, 0, 0, 255])
    second = first.dup
    second[1, 0] = [0, 0, 255, 255]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "test.png")
      Flipbook.write(path, [first, second], fps: 24)
      chunks = png_chunks(File.binread(path))
      animation = chunks.select { |type, _| type == "acTL" }.fetch(0).last.unpack("N2")
      controls = chunks.select { |type, _| type == "fcTL" }.map { |_, data| data.unpack1("N") }
      frame_data = chunks.select { |type, _| type == "fdAT" }.map { |_, data| data.unpack1("N") }

      assert_equal [2, 0], animation
      assert_equal [0, 1], controls
      assert_equal [2], frame_data
      assert_equal first.bytes, Tessel.read(path).bytes
    end
  end

  def test_timing_rejects_invalid_delays
    assert_raise(ArgumentError) { Flipbook::Timing.delays(2, fps: 0) }
    assert_raise(ArgumentError) { Flipbook::Timing.delays(2, delay: [0.1]) }
    assert_raise(ArgumentError) { Flipbook::Timing.delays(1, fps: 24, delay: 0.1) }
  end

  private

  def solid(color)
    Tessel::Image.new(2, 1, fill: color)
  end

  def unwrap_sub_blocks(bytes)
    output = "".b
    offset = 0
    loop do
      length = bytes.getbyte(offset)
      offset += 1
      break if length.zero?

      output << bytes.byteslice(offset, length)
      offset += length
    end
    output
  end

  def png_chunks(bytes)
    chunks = []
    offset = Tessel::SIGNATURE.bytesize
    while offset + 12 <= bytes.bytesize
      length = bytes.byteslice(offset, 4).unpack1("N")
      type = bytes.byteslice(offset + 4, 4)
      chunks << [type, bytes.byteslice(offset + 8, length)]
      offset += length + 12
      break if type == "IEND"
    end
    chunks
  end
end
