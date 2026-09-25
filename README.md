<h1 align="center">Flipbook</h1>

<p align="center">Write optimized animated GIF and APNG files from Ruby images.</p>

<p align="center">
  <a href="https://rubygems.org/gems/flipbook"><img src="https://badge.fury.io/rb/flipbook.svg" alt="Gem version"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D3.1-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-750014.svg" alt="License"></a>
</p>

[Formats](#formats) · [Installation](#installation) · [API](#api) · [Examples](#examples) · [Development](#development)

---

Flipbook writes animated GIFs and APNGs from [`Tessel::Image`](https://github.com/rbgfx/tessel) frames. GIF palettes use Tessel's shared quantizer; APNG keeps full RGBA color. Both writers can crop unchanged frame regions.

## Formats

| Format | Colors | Transparency | Encoding |
| --- | --- | --- | --- |
| GIF | Up to 256 palette entries | One transparent palette index | GIF89a output with global or per-frame palettes and LZW |
| APNG (`.png`, `.apng`) | Full RGBA | Full alpha | PNG-compatible first frame, `acTL` / `fcTL` / `fdAT` animation chunks |

GIF uses a single global palette by default so colors stay stable across frames. Use `palette: :per_frame` when streaming frames with different color ranges. Delta cropping is most effective for opaque GIF frames; APNG supports alpha-safe cropped updates.

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
~~~

Use `delay:` in seconds instead of `fps:`. It accepts one duration or one duration per frame; `Rational(1, 30)` avoids floating-point timing drift. GIF delays use cumulative centisecond rounding. Viewers may lengthen delays below 1/50 second.

For streaming GIF output, choose a per-frame palette:

~~~ruby
Flipbook::GIF::Writer.open("recording.gif", width: 320, height: 240, palette: :per_frame) do |writer|
  writer.add(frame, delay: Rational(1, 30))
end
~~~

Use a `.png` or `.apng` path for full-color animation. The first frame remains a valid PNG for viewers that do not animate APNG:

~~~ruby
Flipbook.write("animation.png", frames, fps: 30, loop: true)
~~~

`optimize: false` writes full-size frames. The default crops each changed frame to its smallest bounding rectangle. GIF cropping is used for opaque frames; APNG cropping preserves alpha changes.

### API contracts

- `Flipbook.write(path, frames, fps: or delay:)` requires one or more same-sized `Tessel::Image` objects and a `.gif`, `.png`, or `.apng` output path.
- `GIF::Writer#add` raises `TypeError` for non-image frames and `ArgumentError` for invalid dimensions or timing.
- `APNG::Writer#add` accepts positive numeric delays in seconds and raises for frames that do not match the canvas dimensions.
- GIF palette colors are RGB triples of integer channels from 0 to 255. GIF transparency is binary; partial alpha is encoded as an opaque palette color.

## Examples

Generate a rotating square, a color gradient, and transparent GIF/APNG samples:

~~~sh
ruby examples/generate.rb
~~~

Pass an output directory as the first argument to choose where the files are written.

GIF format acknowledgement: The Graphics Interchange Format© is the Copyright property of CompuServe Incorporated. GIF® is a Service Mark property of CompuServe Incorporated.

## Development

~~~sh
bundle install
bundle exec rake verify
~~~

Optional external checks for generated files are listed in [docs/verification.md](docs/verification.md).

## License

[MIT](LICENSE.txt)
