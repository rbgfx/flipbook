# frozen_string_literal: true

require "fileutils"
require "flipbook"

output = ARGV.fetch(0, "examples/output")
FileUtils.mkdir_p(output)

frames = 24.times.map do |frame|
  image = Tessel::Image.new(160, 120, fill: "#111827")
  angle = frame * Math::PI / 12
  cos = Math.cos(angle)
  sin = Math.sin(angle)
  (35...125).each do |y|
    (55...105).each do |x|
      dx = x - 80
      dy = y - 60
      next unless (dx * cos + dy * sin).abs <= 17 && (-dx * sin + dy * cos).abs <= 17

      image[x, y] = [56, 189, 248, 255]
    end
  end
  image
end
Flipbook.write(File.join(output, "spinning-square.gif"), frames, fps: 12)

gradient = Tessel::Image.new(128, 32)
gradient.height.times do |y|
  gradient.width.times do |x|
    gradient[x, y] = [x * 2, 100, 255 - x * 2, 255]
  end
end
Flipbook.write(File.join(output, "gradient.gif"), [gradient], delay: 1)

transparent = 16.times.map do |frame|
  image = Tessel::Image.new(96, 96)
  center_x = 48 + (25 * Math.cos(frame * Math::PI / 8)).round
  center_y = 48 + (25 * Math.sin(frame * Math::PI / 8)).round
  96.times do |y|
    96.times do |x|
      image[x, y] = [251, 113, 133, 255] if (x - center_x)**2 + (y - center_y)**2 <= 14**2
    end
  end
  image
end
Flipbook.write(File.join(output, "transparent.gif"), transparent, fps: 8)
Flipbook.write(File.join(output, "transparent.png"), transparent, fps: 8)

puts "Wrote GIF and APNG examples to #{output}"
