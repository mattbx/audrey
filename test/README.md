# test

off-device checks for audrey. there are no behaviour tests yet, only screen previews.

## screen previews

`screens.lua` lists the screen states worth seeing: just loaded, feedback raised,
body and frequency turned with the plate reverb, frequency at the top, an LFO on
feedback, and an LFO on frequency at the top (the longest value the screen shows). it drives the real script with the
encoders and params, and nothing in it is random, so every run draws the same pixels.
add a shot there for whatever you're working on.

the LFOs don't move off the device, so the LFO shots show the `~` marker beside the
setting, not a modulated value.

the previews come from Weft's preview tool. it runs from a checkout of **Weft**
(github.com/mattbx/weft, private) rather than this repo, and replays every
`redraw()` through Cairo with the norns font, so shapes and text match the device.
it needs Weft's harness stubs for `params:string` and the `lfo` library (mattbx/weft#9,
2026-11-23); an older Weft stops in `init()`. best in Weft's bullseye image, which has
the device's Cairo 1.16:

```
docker run --rm -v "$PWD":/weft -v ~/Github/audio-apps/audrey/norns/audrey:/scripts/audrey -w /weft \
  weft-bullseye-cairo python3 tools/norns-harness/screens.py /scripts/audrey
```

or straight on the Mac, with lua 5.3 and pycairo installed (shapes exact, text at
half-pixel positions can come out a little bolder with a newer Cairo):

```
python3 tools/norns-harness/screens.py ~/Github/audio-apps/audrey/norns/audrey
```

both write `screens/` at the top of this repo (gitignored): a PNG per state and `sheet.png` with all of them.

lua 5.3 on linux: `apt install lua5.3`. on the mac, Homebrew no longer has `lua@5.3`:
build it from lua.org as Weft's `tools/norns-harness/README.md` (Setup) shows, and if it
isn't on your PATH as `lua5.3`, run with `LUA=/path/to/lua5.3 python3 tools/norns-harness/screens.py ...`.
