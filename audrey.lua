-- audrey
-- Audrey II feedback drone
-- port of Synthux Academy's
-- Audrey II (Infrasonic Audio)
--
-- E1 feedback (the big knob)
-- E2 body   E3 frequency
-- everything else: PARAMS
-- 4 LFOs: PARAMS > LFOs
--
-- turn the volume down first!

engine.name = 'Audrey'

local lfo = require 'lfo'
local NUM_LFOS = 4

-- mirrors ~audrey.params in audrey_engine.scd
-- {id, label, min, max, curve, default knob, unit}
local P = {
  {"fbGain",    "feedback",      -60,   12,    "lin",   0.0,  "dB"},
  {"pitch",     "frequency",      16,   72,    "lin",   0.43, "note"},
  {"body",      "body",           0.001, 0.1,  "sq",    0.3,  "ms"},
  {"lpf",       "low pass",       100,  18000, "log",   1.0,  "Hz"},
  {"hpf",       "high pass",      10,   4000,  "log",   0.4,  "Hz"},
  {"verbMix",   "reverb mix",     0,    1,     "lin",   0.3,  ""},
  {"verbDecay", "reverb decay",   0.2,  1,     "lin",   0.5,  ""},
  {"echoSend",  "echo send",      0,    1,     "sq",    0.0,  ""},
  {"echoTime",  "echo time",      0.05, 5,     "sq",    0.3,  "s"},
  {"echoFb",    "echo feedback",  0,    1.5,   "lin",   0.0,  ""},
  {"amp",       "output volume",  0,    1,     "sq",    0.7,  ""},
  {"inGain",    "input gain",     0,    5,     "lin",   0.0,  ""},
  {"crush",     "crush",          -1,   1,     "lin",   0.5,  ""},
  {"sub",       "sub",            0,    1,     "lin",   0.0,  ""},
}

local function ftension(x, f)
  return (math.exp(x * f) - 1) / (math.exp(f) - 1)
end

-- knob (0-1) -> value, same curves as the firmware / ~audrey.mapKnob
local function map_knob(p, x)
  local id, min, max, curve = p[1], p[3], p[4], p[5]
  if id == "verbDecay" then x = ftension(x, -3) end
  if curve == "lin" then return min + x * (max - min)
  elseif curve == "sq" then return min + x * x * (max - min)
  else return min * (max / min) ^ x end
end

local function fmt(p, v)
  local unit = p[7]
  if unit == "dB" then return string.format("%.1f dB", v)
  elseif unit == "ms" then return string.format("%.1f ms", v * 1000)
  elseif unit == "Hz" then return string.format("%d Hz", math.floor(v + 0.5))
  elseif unit == "s" then return string.format("%.2f s", v)
  elseif unit == "note" then return string.format("%.1f (%.1f Hz)", v, 440 * 2 ^ ((v - 69) / 12))
  elseif p[1] == "crush" then
    if v < -0.01 then return string.format("SR %.1fk", 16 * (1 / 16) ^ (-v))
    elseif v > 0.01 then return string.format("drive %d%%", math.floor(v * 100 + 0.5))
    else return "clean" end
  else return string.format("%.2f", v) end
end

local by_id = {}

-- LFO modulation: each LFO adds an offset (in knob units, 0-1) to its target.
-- The param keeps your setting; the engine gets setting + LFO offsets.
local lfos = {}
local lfo_target = {}   -- lfo index -> param id (or nil)
local lfo_offset = {}   -- lfo index -> current offset
local last_sent = {}    -- param id -> last value sent (skip repeats)
local live = {}         -- param id -> current modulated value (for display)
local targets = {"none"}
local target_ids = {false}

local function send(id)
  local v = params:get(id)
  for i = 1, NUM_LFOS do
    if lfo_target[i] == id then v = v + (lfo_offset[i] or 0) end
  end
  v = util.clamp(v, 0, 1)
  live[id] = v
  if last_sent[id] == nil or math.abs(last_sent[id] - v) > 0.0005 then
    last_sent[id] = v
    engine["knob_" .. id](v)
  end
end

-- is an active (switched on) LFO pointing at this param?
local function modulated(id)
  for i = 1, NUM_LFOS do
    if lfo_target[i] == id and params.lookup["lfo_audrey_" .. i]
      and params:get("lfo_audrey_" .. i) == 2 then return true end
  end
  return false
end

-- offset relative to where the LFO starts (min / centre / max)
local function lfo_mod(i, scaled)
  local base = lfos[i]:get("baseline")
  local anchor = base == "center" and 0.5 or (base == "max" and 1 or 0)
  return scaled - anchor
end

local function add_lfos()
  params:add_group("audrey_lfos", "LFOs", NUM_LFOS * 17)
  for i = 1, NUM_LFOS do
    lfos[i] = lfo:add{
      shape = "sine", min = 0, max = 1, depth = 0.3, mode = "free", period = 8,
      baseline = "center",
      action = function(scaled, raw)
        lfo_offset[i] = lfo_mod(i, scaled)
        if lfo_target[i] then send(lfo_target[i]) end
      end
    }
    params:add_separator("audrey_lfo_sep_" .. i, "LFO " .. i)
    params:add_option("audrey_lfo_target_" .. i, "target", targets, 1)
    params:set_action("audrey_lfo_target_" .. i, function(x)
      local old = lfo_target[i]
      lfo_target[i] = target_ids[x] or nil
      lfo_offset[i] = 0
      if old then send(old) end   -- release the old target back to its setting
    end)
    lfos[i]:add_params("audrey_" .. i)
    -- when an LFO is switched off, release its target
    local state_action = params:lookup_param("lfo_audrey_" .. i).action
    params:set_action("lfo_audrey_" .. i, function(x)
      state_action(x)
      if x == 1 then
        lfo_offset[i] = 0
        if lfo_target[i] then send(lfo_target[i]) end
      end
    end)
  end
end

function init()
  params:add_separator("AUDREY")
  params:add_option("verbType", "reverb", {"Audrey", "Stautner", "Plate"}, 1)
  params:set_action("verbType", function(i) engine.verbType(i - 1) end)
  params:add_option("crushPos", "crush position", {"pre-verb", "post-verb", "output"}, 1)
  params:set_action("crushPos", function(i) engine.crushPos(i - 1) end)
  params:add_option("echoHalve", "echo halve", {"off", "on"}, 1)
  params:set_action("echoHalve", function(i) engine.echoHalve(i - 1) end)

  for _, p in ipairs(P) do
    by_id[p[1]] = p
    params:add_control(p[1], p[2], controlspec.new(0, 1, "lin", 0, p[6], ""),
      function(param)
        -- while an LFO is on this param, show the live value with a ~
        if modulated(p[1]) and live[p[1]] then
          return "~ " .. fmt(p, map_knob(p, live[p[1]]))
        end
        return fmt(p, map_knob(p, param:get()))
      end)
    params:set_action(p[1], function(x)
      send(p[1])
      redraw()
    end)
    table.insert(targets, p[2])
    table.insert(target_ids, p[1])
  end

  add_lfos()

  params:bang()
  params:set("fbGain", 0) -- always start silent

  -- refresh the screen ~15x a second while any LFO is running, so the
  -- modulated values visibly move (PARAMS menu or the main screen)
  display_metro = metro.init(function()
    for i = 1, NUM_LFOS do
      if lfo_target[i] and params:get("lfo_audrey_" .. i) == 2 then
        if _menu.mode then _menu.redraw() else redraw() end
        return
      end
    end
  end, 1 / 15)
  display_metro:start()
  redraw()
end

function enc(n, d)
  if n == 1 then params:delta("fbGain", d * 0.5)
  elseif n == 2 then params:delta("body", d)
  elseif n == 3 then params:delta("pitch", d) end
end

local function line(y, label, id)
  screen.move(2, y); screen.level(4); screen.text(label)
  screen.move(126, y); screen.level(15)
  screen.text_right(params:string(id))
end

function redraw()
  screen.clear()
  screen.font_size(8)
  screen.move(2, 10); screen.level(15); screen.text("AUDREY")
  screen.move(126, 10); screen.level(4)
  screen.text_right(params:string("verbType"))
  line(28, "E1 feedback", "fbGain")
  line(40, "E2 body", "body")
  line(52, "E3 frequency", "pitch")
  screen.update()
end

function cleanup()
  if display_metro then display_metro:stop() end
  for i = 1, NUM_LFOS do
    if lfos[i] then lfos[i]:stop() end
  end
end
