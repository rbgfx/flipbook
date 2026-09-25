# File verification

The test suite checks GIF LZW code-width growth and dictionary resets, frame timing, and transparent palette entries.

For an independent local check, install ImageMagick or gifsicle and inspect sample output:

~~~sh
identify animation.gif
magick animation.gif -coalesce /tmp/flipbook-gif-%02d.png
gifsicle --info animation.gif
~~~

These tools are optional and are not runtime dependencies.
