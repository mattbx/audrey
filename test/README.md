# test

off-device checks for audrey. there are no behaviour tests yet, only screen previews.

## screen previews

`screens.lua` lists the screen states worth seeing: just loaded, feedback raised,
body and frequency turned with the plate reverb, frequency at the top (the longest
value the screen shows) and an LFO on feedback. it drives the real script with the
encoders and params, and nothing in it is random, so every run draws the same pixels.
add a shot there for whatever you're working on.

the LFOs don't move off the device, so the LFO shot shows the `~` marker beside the
setting, not a modulated value.

the previews come from Weft's preview tool. it runs from a checkout of **Weft**
(github.com/mattbx/weft, private) rather than this repo, and replays every
`redraw()` through Cairo with the norns font, so shapes and text match the device.
best in Weft's bullseye image, which has the device's Cairo 1.16:

```
docker run --rm -v "$PWD":/weft -v ~/Github/audio-apps/audrey/norns/audrey:/scripts/audrey -w /weft \
  weft-bullseye-cairo python3 tools/norns-harness/screens.py /scripts/audrey
```

or straight on the Mac, with lua 5.3 and pycairo installed (shapes exact, text at
half-pixel positions can come out a little bolder with a newer Cairo):

```
python3 tools/norns-harness/screens.py ~/Github/audio-apps/audrey/norns/audrey
```

both write `screens/` here (gitignored): a PNG per state and `sheet.png` with all of them.

install lua 5.3: `brew install lua@5.3` (mac) or `apt install lua5.3`.
