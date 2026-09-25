# File verification

The test suite checks GIF LZW code-width growth and dictionary resets, frame composition and disposal, resource limits, frame timing, transparent palette entries, cropped frame bounds, APNG sequence numbers, and PNG chunk CRCs.

For an independent local check, install ImageMagick, FFmpeg, or gifsicle and inspect sample output:

~~~sh
identify animation.gif
magick animation.gif -coalesce /tmp/flipbook-gif-%02d.png
gifsicle --info animation.gif
magick identify animation.png
ffprobe -v error -count_frames -select_streams v:0 \\
  -show_entries stream=codec_name,nb_read_frames animation.png
~~~

These tools are optional and are not runtime dependencies.
