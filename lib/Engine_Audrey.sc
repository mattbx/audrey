// Engine_Audrey - norns engine for the Audrey II port
//
// Loads the same SuperCollider files as the laptop sketch (sketch/):
// audrey_engine.scd -> audrey_reverbs.scd -> reverbs.scd.
// Audrey II engine: Nick Donaldson / Infrasonic Audio, Synthux Academy (MIT).
// Reverbs: see reverbs.scd and licenses/ (Tom Erbe BSD-3, Csound reverbsc LGPL-2.1).
//
// Commands: knob_<param> f (0-1 knob position, mapped with the firmware's
// curves in ~audrey.mapKnob), verbType i (0-2), crushPos i (0-2), echoHalve i.

Engine_Audrey : CroneEngine {
	var group, head, verb, crushNode, tail, preBus, postBus;
	var knobs, echoHalve = false, verbKeys;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		var s = context.server;
		var dir = PathName(this.class.filenameSymbol.asString).pathOnly;
		(dir ++ "audrey_engine.scd").load;
		s.sync;

		knobs = ();
		~audrey.params.do { |p| knobs[p[0]] = p[6] };
		verbKeys = ~audrey.verbTypes.collect(_[0]);

		preBus = Bus.audio(s, 2);
		postBus = Bus.audio(s, 2);
		group = Group.new(context.xg);

		// head -> verb -> crush -> tail
		head = Synth(\audreyHead, ~audrey.startArgs ++ this.busArgs ++ [\inBus, context.in_b[0].index], group, \addToHead);
		tail = Synth(\audreyTail, ~audrey.startArgs ++ this.busArgs ++ [\out, context.out_b.index], group, \addToTail);
		crushNode = Synth(\audreyCrush, this.busArgs, tail, \addBefore);
		verb = Synth(~audrey.verbDefName(verbKeys[0]), this.verbArgs, crushNode, \addBefore);

		~audrey.params.do { |p|
			var key = p[0];
			this.addCommand(("knob_" ++ key).asSymbol, "f", { |msg| this.setKnob(key, msg[1]) });
		};
		this.addCommand(\verbType, "i", { |msg| this.setVerbType(msg[1]) });
		this.addCommand(\crushPos, "i", { |msg| group.set(\crushPos, msg[1].clip(0, 2)) });
		this.addCommand(\echoHalve, "i", { |msg|
			echoHalve = msg[1] > 0;
			this.setKnob(\echoTime, knobs[\echoTime]);
		});
	}

	busArgs { ^[\preBus, preBus.index, \postBus, postBus.index] }

	verbArgs {
		^this.busArgs ++ [
			\verbMix, ~audrey.mapKnob(\verbMix, knobs[\verbMix]),
			\verbDecay, ~audrey.mapKnob(\verbDecay, knobs[\verbDecay])
		]
	}

	setKnob { |key, x|
		knobs[key] = x;
		// Audrey II delay switch: echo time knob halved before mapping
		if(key == \echoTime and: { echoHalve }) { x = x * 0.5 };
		group.set(key, ~audrey.mapKnob(key, x));
	}

	setVerbType { |i|
		var old = verb;
		var key = verbKeys[i.clip(0, verbKeys.size - 1)];
		verb = Synth(~audrey.verbDefName(key), this.verbArgs ++ [\fade, 0.3], crushNode, \addBefore);
		old.set(\fade, 0.3, \gate, 0);
	}

	free {
		group.free;
		preBus.free;
		postBus.free;
	}
}
