// Audrey II - SuperCollider sketch v0.7
//
// HOW TO RUN
// 1. Open this file in the SuperCollider IDE.
// 2. Turn your speakers DOWN first. Feedback synths jump.
// 3. Click anywhere inside the big ( ... ) block below and press Cmd+Return.
// 4. Slowly bring up FEEDBACK until the loop wakes up (around 0.5).
//    Then explore - and try the reverb type menu while it's droning.
//    Each type changes which overtones the loop locks onto.
//
// Stop everything: Cmd+. (Cmd+period)
//
// Based on Audrey II by Nick Donaldson / Infrasonic Audio and Synthux Academy (MIT).
// Reverb types ported from Tom Erbe's Pd reverb patches (BSD-3, see LICENSE-pd-reverb.txt).

(
s.options.numInputBusChannels = 2;
s.options.numOutputBusChannels = 2;

s.waitForBoot {
	"../lib/audrey_engine.scd".loadRelative;
	s.sync;

	~audrey.preBus = Bus.audio(s, 2);
	~audrey.postBus = Bus.audio(s, 2);
	~audrey.nodeGroup = Group(s);

	~audrey.knobState = ();
	~audrey.params.do { |p| ~audrey.knobState[p[0]] = p[6] };
	~audrey.echoHalve = false;
	~audrey.verbType = \audrey;

	~audrey.busArgs = { |self|
		[\preBus, self.preBus.index, \postBus, self.postBus.index, \inBus, s.options.numOutputBusChannels]
	};
	~audrey.verbArgs = { |self|
		self.busArgs ++ [
			\verbMix, self.mapKnob(\verbMix, self.knobState[\verbMix]),
			\verbDecay, self.mapKnob(\verbDecay, self.knobState[\verbDecay])
		]
	};

	// head -> verb -> tail, in that order inside the group
	~audrey.head = Synth(\audreyHead, ~audrey.startArgs ++ ~audrey.busArgs, ~audrey.nodeGroup, \addToHead);
	~audrey.tail = Synth(\audreyTail, ~audrey.startArgs ++ ~audrey.busArgs, ~audrey.nodeGroup, \addToTail);
	~audrey.crushNode = Synth(\audreyCrush, ~audrey.busArgs, ~audrey.tail, \addBefore);
	~audrey.verb = Synth(~audrey.verbDefName(\audrey), ~audrey.verbArgs, ~audrey.crushNode, \addBefore);

	// Swap reverb type: new one fades in just before the tail, old one fades out
	~audrey.setVerbType = { |self, key, fade = 0.3|
		var old = self.verb;
		self.verb = Synth(self.verbDefName(key), self.verbArgs ++ [\fade, fade], self.crushNode, \addBefore);
		old.set(\fade, fade, \gate, 0);
		self.verbType = key;
	};

	// Send one knob to every synth in the group (each ignores what it doesn't use).
	// Echo time is halved *before* mapping, like the Audrey II delay switch.
	~audrey.setKnob = { |self, key, x|
		var v;
		self.knobState[key] = x;
		if(key == \echoTime and: { self.echoHalve }) { x = x * 0.5 };
		v = self.mapKnob(key, x);
		self.nodeGroup.set(key, v);
		v
	};

	{
		var win, rows, fmt, y0;
		fmt = { |key, v|
			switch(key,
				\fbGain, { v.round(0.1).asString ++ " dB" },
				\pitch, { v.round(0.1).asString ++ " (" ++ v.midicps.round(0.1) ++ " Hz)" },
				\body, { (v * 1000).round(0.1).asString ++ " ms" },
				\lpf, { v.round(1).asString ++ " Hz" },
				\hpf, { v.round(1).asString ++ " Hz" },
				\echoTime, { v.round(0.01).asString ++ " s" },
				{ v.round(0.001).asString }
			)
		};

		win = Window("Audrey II sketch v0.7", Rect(100, 100, 560, 90 + (~audrey.params.size * 34) + 84))
			.background_(Color.grey(0.12));

		// reverb type menu
		StaticText(win, Rect(16, 16, 150, 24))
			.string_("REVERB TYPE").stringColor_(Color(0.6, 0.85, 1)).font_(Font.sansSerif(13, true));
		PopUpMenu(win, Rect(170, 16, 250, 24))
			.items_(~audrey.verbTypes.collect(_[1]))
			.action_({ |m| ~audrey.setVerbType(~audrey.verbTypes[m.value][0]) });

		StaticText(win, Rect(16, 46, 150, 24))
			.string_("CRUSH POSITION").stringColor_(Color(1, 0.75, 0.5)).font_(Font.sansSerif(13, true));
		PopUpMenu(win, Rect(170, 46, 250, 24))
			.items_(["pre-verb (in loop)", "post-verb (in loop)", "output (not fed back)"])
			.action_({ |m| ~audrey.nodeGroup.set(\crushPos, m.value) });

		y0 = 86;
		rows = ~audrey.params.collect { |p, i|
			var key = p[0], y = y0 + (i * 34), slider, readout;
			StaticText(win, Rect(16, y, 150, 24))
				.string_(p[1])
				.stringColor_(if(key == \fbGain) { Color(1, 0.6, 0.3) } { Color.grey(0.85) })
				.font_(Font.sansSerif(if(key == \fbGain) { 13 } { 12 }, key == \fbGain));
			readout = StaticText(win, Rect(430, y, 120, 24)).stringColor_(Color.grey(0.7));
			slider = Slider(win, Rect(170, y, 250, 24))
				.value_(p[6])
				.action_({ |sl| readout.string_(fmt.(key, ~audrey.setKnob(key, sl.value))) });
			readout.string_(fmt.(key, ~audrey.mapKnob(key, p[6])));
			[key, slider]
		};

		CheckBox(win, Rect(16, y0 + 10 + (~audrey.params.size * 34), 260, 24))
			.string_("echo time halve (delay switch)")
			.palette_(QPalette.dark.windowText_(Color.white).buttonText_(Color.white))
			.action_({ |cb|
				~audrey.echoHalve = cb.value;
				~audrey.setKnob(\echoTime, ~audrey.knobState[\echoTime]);
			});

		Button(win, Rect(290, y0 + 10 + (~audrey.params.size * 34), 160, 24))
			.states_([["eeek, make it stop!", Color.white, Color(0.5, 0.15, 0.1)]])
			.action_({
				var r = rows.detect { |r| r[0] == \fbGain };
				r[1].valueAction_(0);
			});

		win.onClose_({
			~audrey.nodeGroup.free;
			~audrey.preBus.free;
			~audrey.postBus.free;
		});
		win.front;
	}.defer;
};
)

// Handy extras (run one line at a time):
// s.meter;   // level meters
// s.scope;   // oscilloscope
// ~audrey.setVerbType(\plate, 2);       // switch reverb with a slower 2 s crossfade
// ~audrey.nodeGroup.set(\fbGain, -10);      // set a raw value directly
// ~audrey.verbTypes.collect(_[0]);      // list reverb type keys
