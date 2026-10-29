// Reverb library (SuperCollider) - shared across projects
//
// Seven algorithmic reverbs as plain functions: { |in (stereo array), g| -> [L, R] }
//   g = decay as "gain per 62.5 ms" (0.2 short ... 1.0 near-infinite). Every type
//       translates it to its own internals so the same g gives a similar tail.
// They are graph functions, not SynthDefs: call them inside your own SynthDef, e.g.
//   ~reverbLib.funcs[\plate].value(sig, 0.85) * ~reverbLib.trim(\plate)
// Each uses at most one LocalIn, so use one reverb per SynthDef (and no other LocalIn).
//
// Load:  (path +/+ "reverb-library/reverbs.scd").load;
//
// Keys:
//   reverbsc     DaisySP ReverbSc (Sean Costello / Csound) - 8-line FDN, random wobble
//   stautner     Gerzon/Stautner/Puckette 4-line FDN with rotation matrix (Erbe)
//   plate        Dattorro plate (Erbe)
//   schroeder    Schroeder 1962 - 2 allpasses -> 4 combs (Erbe)
//   moorer       Moorer 1979 - allpass -> 6 lowpass combs (Erbe)
//   spacestation Chris Moore / Ursa Major Space Station SST-282 style (Erbe)
//   freeverb     SC FreeVerb2 wrapper
// "(Erbe)" = ported from Tom Erbe's pd-reverb lecture patches, BSD-3,
// (c) 2025 Tom Erbe - LICENSE-pd-reverb.txt must travel with this file.
//
// Origin: built for the Audrey II port (Supercollider/audrey), 2026-10.

(
var blk = { ControlDur.ir };
var kRef = 0.0625;  // reference loop length for decay equivalence (s)

// verbDecay (per-62.5 ms gain) -> RT60 in seconds
var rt60 = { |g| kRef * 0.001.log / g.clip(0.01, 0.99999).log };

// SC AllpassC decaytime that gives feedback coefficient g for delay d
var apDecay = { |d, g| d * 0.001.log / g.log };

// Erbe's stereo trick: run one mono reverb per input channel, then cross
// sums and alternating differences of their taps to the opposite side.
var crossStereo = { |tapsL, tapsR, scale|
	var sum = { |t| t.sum };
	var dif = { |t| t.collect { |v, i| if(i.even) { v } { v.neg } }.sum };
	[sum.(tapsL) + dif.(tapsR), dif.(tapsL) + sum.(tapsR)] * scale
};

~reverbLib = ~reverbLib ? ();
~reverbLib.funcs = ();

// ---------------------------------------------------------------------------
// audrey - DaisySP ReverbSc, line by line
// ---------------------------------------------------------------------------
~reverbLib.funcs[\reverbsc] = { |in, g|
	// [delay (samples @ 48k), random variation (s), variation rate (Hz)]
	var p = [
		[2473, 0.0010, 3.100], [2767, 0.0011, 3.500], [3217, 0.0017, 1.110],
		[3557, 0.0006, 3.973], [3907, 0.0010, 2.341], [4127, 0.0011, 1.897],
		[2143, 0.0017, 0.891], [1933, 0.0006, 3.221]
	];
	var damp = { var c = 2 - cos(2pi * 12000 / SampleRate.ir); c - sqrt(c.squared - 1) }.value;
	var y = LocalIn.ar(8);
	var jp = y.sum * 0.25;                // "junction pressure"
	var out = p.collect { |q, n|
		var x = in[n % 2] + jp - y[n];    // even lines get L, odd get R
		var dt = (q[0] / 48000) + (LFNoise1.ar(q[2]) * q[1]) - blk.value;
		OnePole.ar(DelayC.ar(x, 0.1, dt) * g, damp)
	};
	LocalOut.ar(out);
	[out[0, 2..].sum, out[1, 3..].sum] * 0.35
};

// ---------------------------------------------------------------------------
// schroeder - Erbe 01schroeder: 2 allpasses -> 4 parallel combs (1962)
// ---------------------------------------------------------------------------
~reverbLib.funcs[\schroeder] = { |in, g|
	var rt = rt60.(g);
	var apg = -6.dbamp;                   // wrapper default ap_gain -6 dB
	var combs = [29.7, 37.1, 41.1, 43.7] / 1000;
	var mono = { |x|
		x = AllpassC.ar(x, 0.01, 0.005, apDecay.(0.005, apg));
		x = AllpassC.ar(x, 0.01, 0.0017, apDecay.(0.0017, apg));
		// comb gain = -60 * delay / RT dB, which is exactly CombC's decaytime
		combs.collect { |d| CombC.ar(x, 0.05, d, rt) }
	};
	crossStereo.(mono.(in[0]), mono.(in[1]), 0.25)
};

// ---------------------------------------------------------------------------
// moorer - Erbe 02moorer: allpass -> 6 lowpass-combs (1979)
// ---------------------------------------------------------------------------
~reverbLib.funcs[\moorer] = { |in, g|
	var rt = rt60.(g);
	var apg = -6.dbamp;
	var combs = [50, 56, 61, 68, 72, 78] / 1000;
	var fb = LocalIn.ar(12);
	var mono = { |x, off|
		x = AllpassC.ar(x, 0.01, 0.006, apDecay.(0.006, apg));
		combs.collect { |d, i|
			// lowpass inside the loop: g1 = sqrt(dt / 250 ms) ("fudge based on
			// Moorer's table"); loop gain normalised by (1 - g1)
			var g1 = (d * 1000 / 250).sqrt;
			var gain = 10 ** (-3 * d / rt);
			var y = DelayC.ar(fb[off + i], 0.1, d - blk.value);
			[y, x + (OnePole.ar(y, g1) * gain)]
		}
	};
	var l = mono.(in[0], 0), r = mono.(in[1], 6);
	LocalOut.ar(l.collect(_[1]) ++ r.collect(_[1]));
	crossStereo.(l.collect(_[0]), r.collect(_[0]), 0.16)
};

// ---------------------------------------------------------------------------
// spacestation - Erbe 03chrismoore: Ursa Major Space Station SST-282 style
// One 500 ms line, 16 slowly wobbling taps summed back in, 8 fixed output taps.
// ---------------------------------------------------------------------------
~reverbLib.funcs[\spacestation] = { |in, g|
	var modTaps = [47, 120, 134, 146, 158, 169, 180, 190, 200, 209, 217, 225, 233, 240, 244, 247] / 1000;
	var rates = [0.666, 0.666, 0.625, 0.625, 0.555, 0.555, 0.476, 0.476,
		0.435, 0.435, 0.303, 0.303, 0.181, 0.181, 0.122, 0.122];
	// Erbe's fbgain runs 0-3 (default 2.4). 16 uncorrelated taps x 0.0625
	// pass (fb/4)^2 of the power, so fb = 4 * g^(T/62.5ms) matches the
	// decay of the other types (T = mean tap ~194 ms). Capped at his max of 3.
	var fbAmt = (4 * (g ** (0.194 / kRef))).min(3);
	var lp = { |x, f| OnePole.ar(x, exp(-2pi * f / SampleRate.ir)) };
	var hp = { |x, f| x - lp.(x, f) };
	var w = LocalIn.ar(1);
	var x = hp.(lp.((in[0] + in[1]) * 0.5, 12500), 8);
	var fbSum = modTaps.collect { |t, i|
		DelayC.ar(w, 0.3, t + (SinOsc.ar(rates[i]) * 0.004) - blk.value)
	}.sum * 0.0625;
	var line;
	fbSum = hp.(lp.(fbSum, 12500), 20);
	line = x + (fbSum * fbAmt);
	LocalOut.ar(line);
	[
		[60, 137, 175, 190].collect { |t| DelayC.ar(line, 0.3, t / 1000) }.sum,
		[77, 112, 160, 212].collect { |t| DelayC.ar(line, 0.3, t / 1000) }.sum
	] * 0.25
};

// ---------------------------------------------------------------------------
// fdn - Erbe 04gerzonstautnerpuckette: 4-line feedback delay network (1982)
// Two stages of 2x2 rotations = orthogonal (energy-preserving) matrix.
// ---------------------------------------------------------------------------
~reverbLib.funcs[\stautner] = { |in, g|
	var dl = [40.635, 62.346, 99.203, 135] / 1000;
	var gain = g ** (dl.mean / kRef);
	var damp = 0.3;
	var c1 = cos(0.25pi), s1 = sin(0.25pi);   // first rotation fixed at 45 deg
	var c2 = cos(0.25pi), s2 = sin(0.25pi);   // "coupling" default 45 deg
	var v = LocalIn.ar(4);
	var a, b, c, d, u1, u2, u3, u4, r1, r2, r3, r4;
	#a, b, c, d = 4.collect { |i| DelayC.ar(v[i], 0.2, dl[i] - blk.value) };
	u1 = (a * c1) - (b * s1);  u2 = (a * s1) + (b * c1);
	u3 = (c * c1) - (d * s1);  u4 = (c * s1) + (d * c1);
	r1 = (u1 * c2) - (u3 * s2);  r2 = (u1 * s2) + (u3 * c2);
	r3 = (u2 * c2) - (u4 * s2);  r4 = (u2 * s2) + (u4 * c2);
	LocalOut.ar([
		in[0] + (gain * r1),
		in[1] + (gain * r3),
		OnePole.ar(gain * r2, damp),
		OnePole.ar(gain * r4, damp)
	]);
	[r1 + r2, r3 + r4]
};

// ---------------------------------------------------------------------------
// plate - Erbe 05dattorro: Dattorro plate (1997)
// predelay -> bandwidth -> 4 input diffusers -> figure-of-eight tank
// ---------------------------------------------------------------------------
~reverbLib.funcs[\plate] = { |in, g|
	var bw = 0.6, damp = 0.25;
	// decay is applied twice per tank half (~358 ms), so match the decay
	// per 62.5 ms: decay^2 = g^(358/62.5)
	var decay = g ** (0.3577 / (2 * kRef));
	// SC AllpassC: w = x + g*d(w), y = d(w) - g*w  (same as Erbe's allpass100ms).
	// The tank's two-tap allpasses need their internal w for output taps,
	// which can be rebuilt from input and output: w = (x + g*y) / (1 - g^2).
	var ap = { |x, d, gg| AllpassC.ar(x, d + 0.01, d, apDecay.(d, gg)) };
	var modAp = { |x, d, gg, rate|
		var dt = d + (SinOsc.ar(rate) * 0.004);
		AllpassC.ar(x, d + 0.01, dt, apDecay.(dt, gg))
	};
	var tap = { |sig, ms| DelayC.ar(sig, 0.2, ms / 1000) };
	var fb = LocalIn.ar(2);  // [delc write, delf write]
	var x, inA, modA, lpA, ap53, w53, fW, inB, modB, lpB, ap36, w36, cW, l, r;

	x = (in[0] + in[1]) * 0.5 * 0.5;
	x = DelayC.ar(x, 0.2, 0.03);                 // predelay 30 ms
	x = OnePole.ar(x, 1 - bw);                   // bandwidth 0.6
	x = ap.(x, 0.004771, 0.75);
	x = ap.(x, 0.003595, 0.75);
	x = ap.(x, 0.01273, 0.625);
	x = ap.(x, 0.009307, 0.625);

	// tank half A: <- delc
	inA = x + (decay * DelayC.ar(fb[0], 0.2, 0.10628 - blk.value));
	modA = modAp.(inA, 0.02258, 0.7, 0.07);                // -> line "deld"
	lpA = OnePole.ar(DelayC.ar(modA, 0.2, 0.14962), damp);
	ap53 = ap.(lpA, 0.06048, 0.5);
	w53 = (lpA + (0.5 * ap53)) / 0.75;
	fW = decay * ap53;                                       // -> line "delf"

	// tank half B: <- delf
	inB = x + (decay * DelayC.ar(fb[1], 0.2, 0.125 - blk.value));
	modB = modAp.(inB, 0.03051, 0.7, 0.1);                  // -> line "dela"
	lpB = OnePole.ar(DelayC.ar(modB, 0.2, 0.14169), damp);
	ap36 = ap.(lpB, 0.08924, 0.5);
	w36 = (lpB + (0.5 * ap36)) / 0.75;
	cW = decay * ap36;                                       // -> line "delc"

	LocalOut.ar([cW, fW]);

	l = tap.(modB, 8.9) + tap.(modB, 99.8) - tap.(w36, 64.2) + tap.(cW, 67)
		- tap.(modA, 66.8) - tap.(w53, 6.3) - tap.(fW, 35.8);
	r = tap.(modA, 11.8) + tap.(modA, 121.7) - tap.(w53, 41.2) + tap.(fW, 89.7)
		- tap.(modB, 70.8) - tap.(w36, 11.2) - tap.(cW, 4.1);
	[l, r] * 0.125
};

// ---------------------------------------------------------------------------
// freeverb - the v0.1 stand-in
// ---------------------------------------------------------------------------
~reverbLib.funcs[\freeverb] = { |in, g|
	FreeVerb2.ar(in[0], in[1], mix: 1, room: g, damp: 0.3)
};

// Level trims: multiply the wet output so every type passes about the same
// wet level as reverbsc for white noise at g = 0.854 (measured offline).
~reverbLib.trims = (
	reverbsc: 1.0, stautner: 0.437, plate: 10.0, schroeder: 0.543,
	moorer: 0.955, spacestation: 1.905, freeverb: 1.035
);
~reverbLib.trim = { |self, key| self.trims[key] ? 1.0 };
~reverbLib.typeOrder = [\reverbsc, \stautner, \plate, \schroeder, \moorer, \spacestation, \freeverb];
"reverb library loaded: ".post; ~reverbLib.typeOrder.postln;
)
