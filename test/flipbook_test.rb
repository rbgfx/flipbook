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
    assert_equal bytes.bytes, Flipbook::GIF::LZW.decode(unwrap_sub_blocks(encoded), 8, bytes.bytesize)
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
      assert_equal images.map(&:bytes), Flipbook.read(path).map(&:bytes)
    end
  end

  def test_gif_delta_frames_are_cropped_and_identical_frames_round_trip
    first = Tessel::Image.new(8, 6, fill: [10, 20, 30, 255])
    second = first.dup
    second[6, 4] = [200, 100, 40, 255]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "delta.gif")
      Flipbook.write(path, [first, second, second], fps: 10)
      bytes = File.binread(path)
      descriptors = gif_descriptors(bytes)
      assert_equal [[0, 0, 8, 6], [6, 4, 1, 1], [0, 0, 1, 1]], descriptors
      assert_equal [first.bytes, second.bytes, second.bytes], Flipbook.read(path).map(&:bytes)

      full_path = File.join(directory, "full.gif")
      Flipbook.write(full_path, [first, second, second], fps: 10, optimize: false)
      assert_operator bytes.bytesize, :<, File.size(full_path)
    end
  end

  def test_gif_transparency_clears_previous_frames_for_global_and_streaming_palettes
    first = Tessel::Image.new(4, 3, fill: [255, 0, 0, 255])
    transparent = Tessel::Image.new(4, 3)
    last = Tessel::Image.new(4, 3, fill: [0, 0, 255, 255])

    Dir.mktmpdir do |directory|
      global_path = File.join(directory, "global.gif")
      Flipbook.write(global_path, [first, transparent, last], fps: 10)
      assert_equal [first.bytes, transparent.bytes, last.bytes], Flipbook.read(global_path).map(&:bytes)

      local_path = File.join(directory, "local.gif")
      Flipbook::GIF::Writer.open(local_path, width: 4, height: 3, palette: :per_frame) do |writer|
        [first, transparent, last].each { |image| writer.add(image, delay: 0.1) }
      end
      assert_equal [first.bytes, transparent.bytes, last.bytes], Flipbook.read(local_path).map(&:bytes)
    end
  end

  def test_gif_reader_applies_restore_to_previous_disposal
    first = Tessel::Image.new(3, 2, fill: [255, 0, 0, 255])
    second = first.dup
    second[1, 0] = [0, 0, 255, 255]
    background = [0, 255, 0, 255]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "restore.gif")
      Flipbook.write(path, [first, second], fps: 10, palette: [[0, 255, 0], [255, 0, 0], [0, 0, 255]], dither: :none)
      bytes = File.binread(path)
      control = bytes.index("!\xF9\x04".b) + 3
      bytes.setbyte(control, (bytes.getbyte(control) & 0xe3) | (3 << 2))
      File.binwrite(path, bytes)

      restored = Tessel::Image.new(3, 2, fill: background)
      restored[1, 0] = [0, 0, 255, 255]
      assert_equal [first.bytes, restored.bytes], Flipbook.read(path).map(&:bytes)
    end
  end

  def test_gif_reader_rejects_truncated_and_over_limit_files
    image = solid([255, 0, 0, 255])
    Dir.mktmpdir do |directory|
      path = File.join(directory, "small.gif")
      Flipbook.write(path, [image, image], fps: 10)
      bytes = File.binread(path)
      assert_raise(Flipbook::Error) { Flipbook::GIF::Reader.new(bytes.byteslice(0, bytes.bytesize - 1)).read }
      assert_raise(Flipbook::Error) { Flipbook::GIF::Reader.new(bytes, max_pixels: 1).read }
      assert_raise(Flipbook::Error) { Flipbook.read(path, max_frames: 1) }
      assert_raise(Flipbook::Error) { Flipbook.read(path, max_total_pixels: 1) }
    end
  end

  def test_apng_writes_valid_chunks_delays_and_optimized_frames
    first = Tessel::Image.new(8, 6, fill: [255, 0, 0, 255])
    second = first.dup
    second[6, 4] = [0, 0, 255, 255]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "animation.png")
      Flipbook.write(path, [first, second, second], fps: 30)
      chunks = png_chunks(File.binread(path))
      controls = chunks.select { |type, _| type == "fcTL" }.map(&:last)
      data = chunks.select { |type, _| type == "fdAT" }.map(&:last)

      assert_equal 3, chunks.find { |type, _| type == "acTL" }.last.unpack1("N")
      assert_equal [0, 1, 3], controls.map { |chunk| chunk.unpack1("N") }
      assert_equal [2, 4], data.map { |chunk| chunk.unpack1("N") }
      assert_equal [[8, 6, 0, 0], [1, 1, 6, 4], [1, 1, 0, 0]], controls.map { |chunk| chunk.byteslice(4, 16).unpack("N4") }
      assert_equal [[1, 30], [1, 30], [1, 30]], controls.map { |chunk| chunk.byteslice(20, 4).unpack("n2") }
      assert_equal first.bytes, Tessel.decode(File.binread(path)).bytes
      chunks.each { |type, data_bytes| assert_equal Zlib.crc32(type + data_bytes), chunk_crc(File.binread(path), type, data_bytes) }

      full_path = File.join(directory, "full.png")
      Flipbook.write(full_path, [first, second, second], fps: 30, optimize: false)
      assert_operator File.size(path), :<, File.size(full_path)
    end
  end

  def test_apng_streaming_falls_back_for_non_seekable_io
    writer_io = Class.new do
      attr_reader :bytes

      def initialize
        @bytes = "".b
      end

      def write(value)
        @bytes << value
        value.bytesize
      end
    end.new
    image = solid([1, 2, 3, 255])
    writer = Flipbook::APNG::Writer.new(writer_io, width: 2, height: 1)
    writer.add(image, delay: Rational(1, 10))
    writer.close

    assert_equal Tessel::SIGNATURE, writer_io.bytes.byteslice(0, 8)
    assert_equal 1, png_chunks(writer_io.bytes).find { |type, _| type == "acTL" }.last.unpack1("N")
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
      apng_path = File.join(directory, "alpha.png")
      Flipbook.write(apng_path, [first], fps: 10)
      assert_equal first.bytes, Tessel.decode(File.binread(apng_path)).bytes
    end
  end

  def test_timing_rejects_invalid_delays
    assert_raise(ArgumentError) { Flipbook::Timing.delays(2, fps: 0) }
    assert_raise(ArgumentError) { Flipbook::Timing.delays(2, delay: [0.1]) }
    assert_raise(ArgumentError) { Flipbook::Timing.delays(1, fps: 24, delay: 0.1) }
  end

  def test_failed_writes_preserve_existing_gif_and_apng_files
    image = solid([255, 0, 0, 255])
    Dir.mktmpdir do |directory|
      gif = File.join(directory, "existing.gif")
      apng = File.join(directory, "existing.png")
      [gif, apng].each { |path| File.binwrite(path, "original") }

      assert_raise(ArgumentError) { Flipbook::GIF::Writer.open(gif, width: 2, height: 1, colors: 1) }
      assert_equal "original", File.binread(gif)
      assert_raise(ArgumentError) { Flipbook::APNG::Writer.open(apng, width: 2, height: 1, loop: -1) }
      assert_equal "original", File.binread(apng)

      assert_raise(RuntimeError) do
        Flipbook::GIF::Writer.open(gif, width: 2, height: 1) do |writer|
          writer.add(image, delay: 0.1)
          raise "interrupted"
        end
      end
      assert_equal "original", File.binread(gif)
      assert_raise(RuntimeError) do
        Flipbook::APNG::Writer.open(apng, width: 2, height: 1) do |writer|
          writer.add(image, delay: 0.1)
          raise "interrupted"
        end
      end
      assert_equal "original", File.binread(apng)
    end
  end

  def test_streamed_gif_replaces_existing_file_only_after_close
    Dir.mktmpdir do |directory|
      path = File.join(directory, "recording.gif")
      File.binwrite(path, "original")
      writer = Flipbook::GIF::Writer.open(path, width: 2, height: 1)
      assert_equal "original", File.binread(path)

      writer.add(solid([255, 0, 0, 255]), delay: 0.1)
      writer.close
      assert_equal 1, Flipbook.read(path).length
      assert_equal ["recording.gif"], Dir.children(directory)
    end
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

  def gif_descriptors(bytes)
    offset = 13
    packed = bytes.getbyte(10)
    offset += 3 * (1 << ((packed & 7) + 1)) if (packed & 0x80).positive?
    descriptors = []
    until offset >= bytes.bytesize || bytes.getbyte(offset) == 0x3b
      case bytes.getbyte(offset)
      when 0x21
        offset += 2
        loop do
          length = bytes.getbyte(offset)
          offset += 1 + length
          break if length.zero?
        end
      when 0x2c
        left, top, width, height, flags = bytes.byteslice(offset + 1, 9).unpack("v4C")
        descriptors << [left, top, width, height]
        offset += 10
        offset += 3 * (1 << ((flags & 7) + 1)) if (flags & 0x80).positive?
        offset += 1
        loop do
          length = bytes.getbyte(offset)
          offset += 1 + length
          break if length.zero?
        end
      else
        raise "invalid test GIF"
      end
    end
    descriptors
  end

  def png_chunks(bytes)
    chunks = []
    offset = 8
    while offset < bytes.bytesize
      length = bytes.unpack1("N", offset:)
      type = bytes.byteslice(offset + 4, 4)
      data = bytes.byteslice(offset + 8, length)
      crc = bytes.unpack1("N", offset: offset + 8 + length)
      raise "invalid PNG CRC" unless Zlib.crc32(type + data) == crc

      chunks << [type, data]
      offset += length + 12
    end
    chunks
  end

  def chunk_crc(bytes, wanted_type, wanted_data)
    offset = 8
    while offset < bytes.bytesize
      length = bytes.unpack1("N", offset:)
      type = bytes.byteslice(offset + 4, 4)
      data = bytes.byteslice(offset + 8, length)
      return bytes.unpack1("N", offset: offset + 8 + length) if type == wanted_type && data == wanted_data

      offset += length + 12
    end
    nil
  end

end
