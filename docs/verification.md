# File verification

The test suite checks GIF LZW code-width growth and dictionary resets, decodes generated animations, and validates APNG chunk ordering and sequence numbers.

For an independent local check, install ImageMagick or gifsicle and inspect sample output:

~~~sh
identify animation.gif animation.png
magick animation.gif -coalesce /tmp/flipbook-gif-%02d.png
magick animation.png -coalesce /tmp/flipbook-apng-%02d.png
gifsicle --info animation.gif
~~~

These tools are optional and are not runtime dependencies.
