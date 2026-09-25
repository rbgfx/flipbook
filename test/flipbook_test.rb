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
    assert_equal bytes, decode_lzw(unwrap_sub_blocks(encoded), 8, expected_size: bytes.bytesize)
  end

  def test_gif_write_uses_cumulative_centisecond_rounding
    images = [solid([255, 0, 0, 255]), solid([255, 0, 0, 255]), solid([255, 0, 0, 255])]
    images[1][1, 0] = [0, 0, 255, 255]
    images[2][1, 0] = [0, 255, 0, 255]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "test.gif")
      Flipbook.write(path, images, fps: 30)
      bytes = File.binread(path)

      assert bytes.start_with?("GIF89a")
      assert bytes.end_with?(";".b)
      delays = bytes.scan(/!\xF9\x04(.{4})\x00/mn).map { |data| data.first.byteslice(1, 2).unpack1("v") }
      assert_equal [3, 3, 4], delays
      assert_equal 3, bytes.scan(/!\xF9\x04/n).length
    end
  end

  def test_gif_marks_transparent_pixels
    first = solid([255, 0, 0, 255])
    second = first.dup
    second[0, 0] = [0, 0, 0, 0]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "alpha.gif")
      Flipbook.write(path, [first, second], fps: 10)
      bytes = File.binread(path)

      controls = bytes.scan(/!\xF9\x04(.{4})\x00/mn).map(&:first)
      assert_equal 2, controls.length
      assert_equal 1, controls.last.getbyte(0) & 1
      assert_raise(ArgumentError) { Flipbook.write(File.join(directory, "alpha.png"), [first], fps: 10) }
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

  def decode_lzw(bytes, minimum_code_size, expected_size: nil)
    clear_code = 1 << minimum_code_size
    end_code = clear_code + 1
    dictionary = Array.new(clear_code) { |index| [index] } + [nil, nil]
    next_code = end_code + 1
    code_width = minimum_code_size + 1
    bit_offset = 0
    previous = nil
    output = "".b
    ended = false
    loop do
      code = read_lzw_code(bytes, bit_offset, code_width)
      break if code.nil?

      bit_offset += code_width
      if code == clear_code
        dictionary = Array.new(clear_code) { |index| [index] } + [nil, nil]
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
                raise "invalid test GIF LZW code"
              end
      output << entry.pack("C*")
      raise "test GIF LZW output exceeded frame size" if expected_size && output.bytesize > expected_size

      if previous && next_code < 4096
        dictionary[next_code] = previous + [entry.first]
        next_code += 1
        code_width += 1 if next_code == (1 << code_width) && code_width < 12
      end
      previous = entry
    end
    raise "test GIF LZW stream was truncated" unless ended && (!expected_size || output.bytesize == expected_size)

    output
  end

  def read_lzw_code(bytes, bit_offset, width)
    return nil if bit_offset + width > bytes.bytesize * 8

    value = 0
    width.times do |bit|
      value |= ((bytes.getbyte((bit_offset + bit) / 8) >> ((bit_offset + bit) % 8)) & 1) << bit
    end
    value
  end

end
