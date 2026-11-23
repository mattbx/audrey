-- audrey's screens, for Weft's preview tool (tools/norns-harness/screens.py in
-- mattbx/weft). It runs the real redraw() in each state below and renders every
-- shot with the same Cairo replay Weft's references come from, with the norns
-- font, so text is exact. From a Weft checkout:
--
--   python3 tools/norns-harness/screens.py ~/Github/audio-apps/audrey/norns/audrey
--
-- Output goes to screens/ (git-ignored): one PNG per shot plus sheet.png.
--
-- The states are reached with the encoders a player would use, and the option
-- params with params:set. Nothing here is random and time never moves, so every
-- run draws the same pixels on any machine. The offline LFOs never move either:
-- the "LFO on feedback" shot shows the ~ marker with the setting, not a
-- modulated value. Add a shot here for whatever state you're working on.

return {
  script = "audrey.lua",
  scenes = function(sim, shot)
    -- just loaded: feedback all the way down, so it starts silent
    shot("just loaded, silent")

    -- E1 up past the wake-up point (about -24 dB, halfway): 110 clicks of 0.005
    sim.enc(1, 110)
    shot("E1 feedback raised")

    -- E2 and E3 turned, with the Plate reverb named top right
    sim.enc(2, 20)
    sim.enc(3, -15)
    params:set("verbType", 3)
    shot("body, frequency, plate")

    -- E3 at the top: the longest value the screen shows, against its label
    sim.enc(3, 100)
    shot("E3 at the top")

    -- LFO 1 on, pointed at feedback: the value gets its ~ marker
    params:set("audrey_lfo_target_1", 2)
    params:set("lfo_audrey_1", 2)
    shot("LFO on feedback")
  end,
}
