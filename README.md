<h1 align="center">Flipbook</h1>

<p align="center">Turn a sequence of RGBA images into animated GIF or APNG files.</p>

<p align="center">
  <a href="https://rubygems.org/gems/flipbook"><img src="https://badge.fury.io/rb/flipbook.svg" alt="Gem version"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="License"></a>
</p>

[Formats](#formats) · [Installation](#installation) · [API](#api) · [Development](#development)

---

Flipbook writes animated GIF and APNG from [`Tessel::Image`](https://github.com/rbgfx/tessel) frames. GIF palettes use Tessel's shared quantizer. The library has no runtime dependency beyond Tessel and Ruby's standard library.

## Formats

| Format | Color | Transparency | Reading |
| --- | --- | --- | --- |
| GIF | Up to 256 palette entries | One transparent palette index | GIF87a/GIF89a frames, local and global palettes, interlace, and disposal methods |
| APNG | RGBA8 | Full alpha | First frame through Tessel's PNG reader |

GIF uses a single global palette by default so colors stay stable across frames. Animated frames with transparent pixels are written as full frames with background disposal so pixels can become transparent correctly. Opaque animations use difference rectangles by default.

## Installation

~~~ruby
gem "flipbook"
~~~

Then run `bundle install`. Flipbook requires Ruby 3.1 or newer and Tessel 0.2 or newer.

## API

~~~ruby
require "flipbook"

frames = 60.times.map do |index|
  image = Tessel::Image.new(320, 240, fill: "#101827")
  image.fill_rect(index * 4 % 320, 100, 32, 32, "#38bdf8")
  image
end

Flipbook.write("animation.gif", frames, fps: 30, loop: true)
Flipbook.write("animation.png", frames, fps: 30, loop: true)

decoded_frames = Flipbook.read("animation.gif")
~~~

Use `delay:` in seconds instead of `fps:`. It accepts one duration or one duration per frame; `Rational(1, 30)` avoids floating-point timing drift. GIF delays use cumulative centisecond rounding. Viewers may lengthen delays below 1/50 second.

For streaming GIF output, choose a per-frame palette:

~~~ruby
Flipbook::GIF::Writer.open("recording.gif", width: 320, height: 240, palette: :per_frame) do |writer|
  writer.add(frame, delay: Rational(1, 30))
end
~~~

APNG also supports streaming output and patches its frame count when the destination can seek. Otherwise it buffers the animation until close.

### API contracts

- `Flipbook.write(path, frames, fps: or delay:)` requires one or more same-sized `Tessel::Image` objects. The `.gif` extension selects GIF; `.png` and `.apng` select APNG.
- `Flipbook.read(path)` returns composited GIF frames as `Tessel::Image` objects. `Flipbook::GIF::Reader#delays` returns each frame delay as a `Rational` in seconds.
- `GIF::Writer#add` and `APNG::Writer#add` raise `TypeError` for non-image frames and `ArgumentError` for invalid dimensions or timing.
- GIF palette colors are RGB triples of integer channels from 0 to 255. GIF transparency is binary; partial alpha is encoded as an opaque palette color.
- APNG chunks use RGBA8 pixels. The first frame is also a valid static PNG image.

GIF format acknowledgement: The Graphics Interchange Format© is the Copyright property of CompuServe Incorporated. GIF® is a Service Mark property of CompuServe Incorporated.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

Optional external checks for generated files are listed in [docs/verification.md](docs/verification.md).

## License

[MIT](LICENSE.txt)
