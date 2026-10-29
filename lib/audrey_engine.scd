// Audrey II engine - SuperCollider sketch v0.2
//
// A SuperCollider version of the Audrey II feedback engine, with swappable
// reverb types inside the loop.
// Original engine and concept: Nick Donaldson / Infrasonic Audio (MIT licence).
// Instrument and hardware design: Roey Tsemah / Synthux Academy.
// Reference: source/Audrey-II/Source/FeedbackSynthEngine.cpp
//
// v0.2 splits the engine into three synths that run in order every block:
//
//   head   noise + input + body delay + string + overdrive + LPF/HPF  -> preBus
//   verb   one of the reverb types (audrey_reverbs.scd)  preBus -> postBus
//   tail   tape echo + output level + limiter            postBus -> out
//
// The loop closes because head reads postBus with InFeedback (last block's
// value) - the same one-block delay LocalIn gave us in v0.1. Because the
// reverb is its own synth, it can be swapped live with a crossfade while
// the loop keeps running.
//
// Helpers live in the ~audrey event and are called method-style, e.g.
// ~audrey.mapKnob(\pitch, 0.5). (~audrey.mapKnob.(...) would pass the event
// itself as the first argument.)
//
// This file only defines things. Run audrey_sketch.scd to play.

(
~audrey = ~audrey ? ();
~audrey.defs = ();   // every SynthDef, by name (used by the offline tools)

// ---------------------------------------------------------------------------
// DSP helpers (ported from DaisySP / stmlib)
// ---------------------------------------------------------------------------

// DaisySP SoftLimit: rational soft limiter
~audrey.softLimit = { |self, x|
	x * (27 + x.squared) / (27 + (9 * x.squared))
};

// DaisySP SoftClip: SoftLimit, hard-limited at +/-3 (reaches exactly +/-1 there)
~audrey.softClip = { |self, x|
	self.softLimit(x.clip2(3))
};

// DaisySP Overdrive gain staging. Audrey uses drive 0.4 -> SoftClip(~5.18 * x).
~audrey.overdriveGains = { |self, drive = 0.4|
	var d = 2 * drive.clip(0, 1);
	var d2 = d * d;
	var preA = d * 0.5;
	var preB = d2 * d2 * d * 24;
	var pre = preA + ((preB - preA) * d2);
	var squashed = d * (2 - d);
	var x = (0.33 + (squashed * (pre - 0.33))).clip2(3);
	var post = 1 / (x * (27 + x.squared) / (27 + (9 * x.squared)));
	[pre, post]
};

// Infrasonic ftension: expm1(x * f) / expm1(f)
~audrey.ftension = { |self, x, f|
	if(f == 0) { x } { ((x * f).exp - 1) / (f.exp - 1) }
};

// ---------------------------------------------------------------------------
// Parameter table - ranges, curves and smoothing from
// source/Audrey-II/Source/FeedbackSynthControls.cpp (registerParams)
//   \lin      min + x * (max - min)
//   \squared  min + x^2 * (max - min)        (DaisySP "EXP")
//   \logscale min * (max/min)^x              (DaisySP "LOG")
// lag = firmware smoothing time (60 dB time, same as SC Lag)
// ---------------------------------------------------------------------------

~audrey.params = [
	// key          label                 min     max     curve      lag   start knob pos (0-1)
	[\fbGain,     "FEEDBACK (big knob)",  -60,    12,     \lin,      0.05, 0.0 ],
	[\pitch,      "frequency",             16,    72,     \lin,      0.2,  0.43],
	[\body,       "body",                  0.001, 0.1,    \squared,  1.0,  0.3 ],
	[\lpf,        "low pass",              100,   18000,  \logscale, 0.05, 1.0 ],
	[\hpf,        "high pass",             10,    4000,   \logscale, 0.05, 0.4 ],
	[\verbMix,    "reverb mix",            0,     1,      \lin,      0.05, 0.3 ],
	[\verbDecay,  "reverb decay",          0.2,   1,      \lin,      0.05, 0.5 ],
	[\echoSend,   "echo send",             0,     1,      \squared,  0.05, 0.0 ],
	[\echoTime,   "echo time",             0.05,  5,      \squared,  0.1,  0.3 ],
	[\echoFb,     "echo feedback",         0,     1.5,    \lin,      0.05, 0.0 ],
	[\amp,        "output volume",         0,     1,      \squared,  0.05, 0.7 ],
	[\inGain,     "input gain (Touch)",    0,     5,      \lin,      0.05, 0.0 ],
	[\crush,      "crush  SR < 0 > drive", -1,    1,      \lin,      0.05, 0.5 ],
	[\sub,        "sub (octaves down)",     0,    1,      \lin,      0.05, 0.0 ]
];

~audrey.paramSpec = { |self, key|
	self.params.detect { |p| p[0] == key }
};

~audrey.lagFor = { |self, key| self.paramSpec(key)[5] };

// Normalised knob position (0-1) -> parameter value, using the firmware's curves
~audrey.mapKnob = { |self, key, x|
	var p = self.paramSpec(key);
	var min = p[2], max = p[3], curve = p[4];
	x = x.clip(0, 1);
	// Reverb decay knob goes through an anti-exponential "tension" curve first
	if(key == \verbDecay) { x = self.ftension(x, -3) };
	switch(curve,
		\lin,      { min + (x * (max - min)) },
		\squared,  { min + (x.squared * (max - min)) },
		\logscale, { min * ((max / min) ** x) }
	)
};

// Synth args for every parameter at its start knob position
~audrey.startArgs = { |self|
	self.params.collect { |p| [p[0], self.mapKnob(p[0], p[6])] }.flatten
};

// ---------------------------------------------------------------------------
// Crush - Dark Star style bipolar effect (graph function, used in 3 places)
//   -1..0  raw sample-rate reduction 16 kHz -> 1 kHz (v0.7)
//    0     clean (exact bypass)
//    0..1  soft-clip overdrive up to +24 dB, level-compensated (small-signal
//          gain rises only ~+6 dB at full); make-up gain is added at the output
// crushPos (set on every synth):
//    0 pre-verb   in the loop, before the reverb (head)  - reverb smooths the grit
//    1 post-verb  in the loop, right after the reverb (\audreyCrush) - the reverb
//                 wash itself gets crushed on every pass
//    2 output     after the loop, before the echo (tail) - never fed back
// ---------------------------------------------------------------------------
~audrey.crushFx = { |self, sig, crush|
	var srAmt = crush.neg.clip(0, 1);
	var odAmt = crush.clip(0, 1);
	// Raw sample-rate reduction (classic decimator, no smoothing filter):
	// 16 kHz -> 1 kHz, exponential. Note Latch only samples on a rising edge,
	// so the trigger rate must stay below SampleRate/2 - above that Impulse is
	// "on" almost every sample and Latch fires only on the rare gaps (the v0.4-
	// v0.6 bug that made 2% the heaviest setting).
	var rate = 16000 * ((1/16) ** srAmt);
	var crushed = Latch.ar(sig, Impulse.ar(rate));
	var driveG = (odAmt * 24).dbamp;
	var driven;
	sig = sig + ((crushed - sig) * (srAmt > 0.001));
	driven = self.softClip(sig * driveG) * (driveG ** -0.75);
	sig + ((driven - sig) * (odAmt * 10).clip(0, 1))
};

// Sub - flip-flop octave divider (Boss OC-2 style), inside the loop before the
// reverb, so the drone feeds back through its own sub-octaves and locks lower.
//   0 off, 0-0.5 fades in one octave down, 0.5-1 adds two octaves down.
~audrey.subFx = { |self, sig, sub|
	sig.collect { |ch|
		var det = LPF.ar(LPF.ar(ch, 400), 400);           // track the low end
		var f1 = ToggleFF.ar(det > 0);                       // 1 octave down
		var f2 = ToggleFF.ar(f1);                            // 2 octaves down
		var env = Amplitude.ar(ch, 0.01, 0.15);              // follow the drone's level
		var subSig = (((f1 * 2) - 1) * sub.min(0.5) * 2) + (((f2 * 2) - 1) * (sub - 0.5).max(0) * 2);
		ch + (LPF.ar(LPF.ar(subSig, 900), 900) * env * 1.5)
	}
};

// Output make-up gain per position, in dB per dB of drive (measured offline)
~audrey.crushMakeup = [0.78, 0.78, 0.78];

// ---------------------------------------------------------------------------
// head: everything in the loop before the reverb
// ---------------------------------------------------------------------------

~audrey.defs[\audreyHead] = SynthDef(\audreyHead, {
	arg preBus = 16, postBus = 18, inBus = 2, inGain = 0,
	pitch = 40, fbGain = -60, body = 0.01, lpf = 18000, hpf = 250, crush = 0, crushPos = 0, sub = 0;

	var sr = SampleRate.ir;
	var blk = ControlDur.ir; // InFeedback = one block of delay in the loop
	var od = ~audrey.overdriveGains(0.4);
	var ret, noise, input, bodyT, freq, period, sig;

	pitch  = Lag.kr(pitch,  ~audrey.lagFor(\pitch));
	fbGain = Lag.kr(fbGain, ~audrey.lagFor(\fbGain));
	lpf    = Lag.kr(lpf,    ~audrey.lagFor(\lpf));
	hpf    = Lag.kr(hpf,    ~audrey.lagFor(\hpf));
	inGain = Lag.kr(inGain, ~audrey.lagFor(\inGain));
	crush  = Lag.kr(crush,  ~audrey.lagFor(\crush));
	sub    = Lag.kr(sub,    ~audrey.lagFor(\sub));

	// Body delay: param smoothing, then the engine's audio-rate one-pole
	// (tau 0.2 s = ~1.38 s to -60 dB) - the pitch-warp when turning Body.
	bodyT = Lag.ar(K2A.ar(Lag.kr(body, ~audrey.lagFor(\body))), 1.38);

	// Loop return: last block's post-reverb signal, scaled by feedback gain
	// (firmware writes sig * fb_gain into the body delay).
	ret = InFeedback.ar(postBus, 2) * fbGain.dbamp;

	// Constant inaudible noise (-90 dBFS), shared by both channels.
	noise = WhiteNoise.ar(-90.dbamp);
	// inBus is an absolute bus number (hardware input 1 = numOutputBusChannels;
	// on norns the engine passes context.in_b[0])
	input = In.ar(inBus) * inGain;

	// Body delay read. R is 4 samples shorter than L (the stereo).
	sig = [
		DelayC.ar(ret[0], 0.25, (bodyT - blk).max(0)),
		DelayC.ar(ret[1], 0.25, (bodyT - blk - (4 / sr)).max(0))
	] + noise + input;

	// Karplus-Strong string: s[n] = 0.8 x[n] + 0.8 s[n - D]
	// CombC gives c = x[n-D] + 0.8 c[n-D], so s = 0.8 x + 0.64 c.
	freq = pitch.midicps;
	period = freq.reciprocal;
	sig = (0.8 * sig) + (0.64 * CombC.ar(sig, 0.1, period, period * (0.001.log / 0.8.log)));
	sig = sig.clip2(20);
	sig = LeakDC.ar(sig, 0.995);
	sig = OnePole.ar(sig, exp(-2pi * 8000 / sr));

	// Overdrive (DaisySP, drive 0.4)
	sig = ~audrey.softClip(sig * od[0]) * od[1];

	// Loop filters: 12 dB biquads, Q 0.9
	sig = BLowPass.ar(sig, lpf, 0.9.reciprocal);
	sig = BHiPass.ar(sig, hpf, 0.9.reciprocal);

	// Sub-octave divider (always in the loop, before crush and reverb)
	sig = ~audrey.subFx(sig, sub);

	// Crush, position 0 = pre-verb (inside the loop, before the reverb)
	sig = ~audrey.crushFx(sig, crush * (crushPos < 0.5));

	Out.ar(preBus, sig);
}).add;

// ---------------------------------------------------------------------------
// crush (post-verb position): sits between the reverb and the tail and
// rewrites postBus in place, so both the loop return and the output hear it
// ---------------------------------------------------------------------------

~audrey.defs[\audreyCrush] = SynthDef(\audreyCrush, {
	arg postBus = 18, crush = 0, crushPos = 0;
	var sig = In.ar(postBus, 2);
	crush = Lag.kr(crush, ~audrey.lagFor(\crush));
	ReplaceOut.ar(postBus, ~audrey.crushFx(sig, crush * (crushPos > 0.5) * (crushPos < 1.5)));
}).add;

// ---------------------------------------------------------------------------
// tail: tape echo + output (outside the loop)
// ---------------------------------------------------------------------------

~audrey.defs[\audreyTail] = SynthDef(\audreyTail, {
	arg postBus = 18, out = 0, echoSend = 0, echoTime = 0.5, echoFb = 0, amp = 0.5, crush = 0, crushPos = 0, sub = 0;

	var blk = ControlDur.ir;
	var sig, fb, echoT, echo, outSig, peak;

	echoSend = Lag.kr(echoSend, ~audrey.lagFor(\echoSend));
	echoFb   = Lag.kr(echoFb,   ~audrey.lagFor(\echoFb));
	amp      = Lag.kr(amp,      ~audrey.lagFor(\amp));
	// param smoothing, then the echo's 0.5 s tau lag (~3.45 s to -60 dB)
	echoT = Lag.ar(K2A.ar(Lag.kr(echoTime, ~audrey.lagFor(\echoTime))), 3.45);

	sig = In.ar(postBus, 2);
	crush = Lag.kr(crush, ~audrey.lagFor(\crush));

	// Crush, position 2 = output (after the loop, before the echo)
	sig = ~audrey.crushFx(sig, crush * (crushPos > 1.5));

	// Tape echo: read -> BPF 800 Hz Q1 -> SoftClip -> write(out * fb + in).
	// Feedback goes to 1.5 on purpose; the soft clip keeps it in check.
	fb = LocalIn.ar(2);
	echo = DelayC.ar(fb, 5.1, (echoT - blk).max(0));
	echo = BPF.ar(echo, 800, 1);
	echo = ~audrey.softClip(echo);
	LocalOut.ar((echo * echoFb) + (sig * echoSend));

	outSig = 0.5 * (sig + echo) * amp;

	// Crush drive make-up (output only, outside the loop): the loop settles
	// ~0.78 dB quieter per dB of drive, so give it back here.
	outSig = outSig * ((crush.clip(0, 1) * 24 * Select.kr(crushPos.round, ~audrey.crushMakeup)).dbamp);
	// Sub level trim (output only): the sub-octaves add ~9 dB from halfway up
	outSig = outSig * ((-9 * ((Lag.kr(sub, ~audrey.lagFor(\sub)) * 2).min(1) ** 1.6)).dbamp);

	// DaisySP Limiter(pre_gain 0.7)
	outSig = outSig * 0.7;
	peak = Amplitude.ar(outSig, 0.003, 7.2).max(1);
	outSig = ~audrey.softLimit(outSig * peak.reciprocal * 0.7);

	Out.ar(out, outSig);
}).add;

// ---------------------------------------------------------------------------
// Reverb types
// ---------------------------------------------------------------------------

(thisProcess.nowExecutingPath.dirname +/+ "audrey_reverbs.scd").load;

"Audrey II engine v0.7 loaded".postln;
)
