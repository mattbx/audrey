// Audrey II - reverb types (v0.3)
//
// Loaded by audrey_engine.scd. The reverbs themselves live in the shared
// library: ../../reverb-library/reverbs.scd (all seven types, with credits
// and licence). Audrey's menu uses the three that suit the loop best.
//
// Shared controls: verbMix 0-1 (dry/wet crossfade, as in the firmware),
// verbDecay 0.2-1 (the firmware's ReverbSc feedback; each type maps it so
// the same knob gives a similar tail length).
//
// The full seven-type v0.2 version is kept in v0.2/audrey_reverbs_7types.scd.

(
{
	// Shared library next to the Audrey folder; on norns a copy sits in lib/
	var here = thisProcess.nowExecutingPath.dirname;
	var local = here +/+ "reverbs.scd";
	(if(File.exists(local)) { local } { here +/+ "../../reverb-library/reverbs.scd" }).load;
}.value;

~audrey.verbTypes = [
	// key        label        library function
	[\audrey,   "Audrey",    \reverbsc],
	[\stautner, "Stautner",  \stautner],
	[\plate,    "Plate",     \plate]
];

~audrey.verbDefName = { |self, key| ("audreyVerb_" ++ key).asSymbol };

// One SynthDef per type: shared dry/wet + crossfade envelope for live swapping.
~audrey.makeVerbDefs = { |self|
	self.verbTypes.do { |t|
		var key = t[0], libKey = t[2], trim = ~reverbLib.trim(libKey);
		self.defs[self.verbDefName(key)] = SynthDef(self.verbDefName(key), {
			arg preBus = 16, postBus = 18, verbMix = 0, verbDecay = 0.5, gate = 1, fade = 0.3;
			var dry = In.ar(preBus, 2);
			var mix = Lag.kr(verbMix, ~audrey.lagFor(\verbMix));
			var dec = Lag.kr(verbDecay, ~audrey.lagFor(\verbDecay));
			var wet = ~reverbLib.funcs[libKey].value(dry, dec) * trim;
			// linear fades: an outgoing and incoming reverb always sum to 1
			var env = EnvGen.kr(Env.asr(fade, 1, fade, \lin), gate, doneAction: 2);
			Out.ar(postBus, (dry + ((wet - dry) * mix)) * env);
		}).add;
	};
};

~audrey.makeVerbDefs;
)
