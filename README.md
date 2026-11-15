# audrey

feedback drone for norns - a port of the [Synthux Academy Audrey II](https://www.synthux.academy/store/audrey-ii), with extra reverbs, crush, sub and LFOs.

a Karplus-Strong string sits inside a feedback loop fed by inaudible noise. nothing sounds until you raise the feedback, then the loop wakes up and settles into a drone, and every other control shapes what it settles on. the original Audrey II is a "horrorscape" synth by Synthux Academy, with its concept and engine by Nick Donaldson (Infrasonic Audio). this port follows its Daisy firmware closely and adds swappable reverbs, a crush section with a position switch, a sub-octave divider and four LFOs. the same engine also runs in SuperCollider on a laptop.

**work in progress** - playable and stable on norns, but the UI is minimal and things will change.

turn your volume down before you start. it's a feedback instrument, fool.

## requirements

- norns (tested on a CM3+ norns, where it uses about 15% of one core)
- optional: a source in the left line input. it's mixed into the loop, so audrey works as an effect too
- no extra SuperCollider plugins

## install

```
;install https://github.com/mattbx/audrey
```

it's a new engine, so do SYSTEM > RESTART after installing.

## controls

- E1 - feedback (the big knob)
- E2 - body (the delay in the loop, 1-100 ms)
- E3 - frequency (string pitch)
- everything else lives in PARAMS

### params

- **reverb** - Audrey (the original), Stautner, Plate. the reverb is inside the loop, so changing it changes which overtones the drone locks onto. switch it live, it crossfades.
- **crush position** - pre-verb (in the loop), post-verb (in the loop), output (not fed back)
- **echo halve** - the Audrey II delay switch, halves the echo time for a doppler warp
- **feedback, frequency, body, low pass, high pass** - the loop
- **reverb mix, reverb decay**
- **echo send, echo time, echo feedback** - tape-ish echo after the loop. feedback goes past 1 on purpose
- **output volume, input gain** - line in (left) is mixed into the loop, so it works as an effect too
- **crush** - centre is clean. left is a raw sample rate reducer (16 kHz down to 1 kHz). right is a soft clip drive
- **sub** - flip-flop octave divider in the loop. first half fades in one octave down, second half adds two. pairs badly (well) with crush

### LFOs

four LFOs in PARAMS > LFOs, using the norns lfo library. pick a target, switch it on. they move around your setting rather than replacing it, so turning one off puts the param back where you left it. while an LFO is running its target shows the live value with a `~`.

## how it works

a Karplus-Strong string sits inside a big feedback loop: string -> overdrive -> filters -> reverb -> body delay -> back into the string. the loop is fed a constant, inaudible (-90 dB) noise, so nothing happens until you raise the feedback. with the default settings it starts to build at around **-24 dB** and is usually fully awake by about **-17 dB**. it swells in over a few seconds rather than snapping on, so take it slowly through that range (each E1 click is roughly 0.4 dB). there's a limiter on the output, but start with your volume low anyway. heavy crush or sub can make it wake a little earlier. everything else shapes what the loop locks onto.

the DSP follows the original Daisy firmware closely: same signal order, parameter ranges, curves and smoothing. the extras are on top.

## laptop version

`sketch/audrey_sketch.scd` runs the same engine in SuperCollider on a computer with a slider window. open it, turn down, run the block.

## differences from the hardware

- reverb types, crush, sub and LFOs are additions
- the string's DC blocker and 8 kHz damping sit just after the comb filter rather than inside it
- the body delay has a ~1.3 ms floor (one SuperCollider control block)

## credits

- **Audrey II** - concept and engine by [Nick Donaldson / Infrasonic Audio](https://github.com/ndonald2), instrument and hardware design by Roey Tsemah / [Synthux Academy](https://www.synthux.academy). source: [Synthux-Academy/Audrey-II](https://github.com/Synthux-Academy/Audrey-II), [AudreyTouch](https://github.com/Synthux-Academy/AudreyTouch). MIT.
- **reverbs** - Stautner (Gerzon/Stautner/Puckette FDN) and Plate (Dattorro) are ported from [Tom Erbe](http://soundhack.com)'s pd-reverb lecture patches, BSD-3-Clause, (c) 2025 Tom Erbe. `lib/reverbs.scd` also has his Schroeder, Moorer and Space Station designs, not used here.
- **Audrey reverb** - a port of Sean Costello's reverbsc from Csound, as used in [DaisySP-LGPL](https://github.com/electro-smith/DaisySP-LGPL). LGPL-2.1.
- **crush** - inspired by the Crush knob on the Old Blood Noise Endeavors Dark Star.

this is an unofficial port, not affiliated with or endorsed by Synthux Academy, Infrasonic Audio or Tom Erbe.

## licence

MIT for the code here, with the parts above under their own licences. see `LICENSE` and `licenses/`.
