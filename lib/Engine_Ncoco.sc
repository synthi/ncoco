// Engine_Ncoco.sc v600 (GOLD MASTER - FIXED LOGIC)
Engine_Ncoco : CroneEngine {
	var <synth;
	var <bufL, <bufR;
	var <osc_responder; 

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		bufL = Buffer.alloc(context.server, 48000 * 60, 1);
		bufR = Buffer.alloc(context.server, 48000 * 60, 1);
		context.server.sync;
		bufL.zero; bufR.zero;
		context.server.sync;

		SynthDef(\NcocoDSP, {
			arg out, inL, inR, bufL, bufR,
			recL=0, recR=0, fbL=0.8, fbR=0.8, speedL=1.0, speedR=1.0,     
			flipL=1, flipR=1, skipL=0, skipR=0,           
			volInL=1.0, volInR=1.0, volFbL=1.0, volFbR=1.0,     
			filtL=15000, filtR=15000, ampL=1.0, ampR=1.0,
			
			bitDepthL=8, bitDepthR=8, interp=2,                   
			dolbyL=0, dolbyR=0, loopLen=8.0,
			preampL=1.0, preampR=1.0, envSlewL=0.05, envSlewR=0.05,

			p1f=0.5, p2f=0.6, p3f=0.7, p4f=0.8, p5f=0.9, p6f=1.0,
			p1chaos=0, p2chaos=0, p3chaos=0, p4chaos=0, p5chaos=0, p6chaos=0,
			p1shape=0, p2shape=0, p3shape=0, p4shape=0, p5shape=0, p6shape=0,
			
			slew_speed=0.1, slew_amp=0.05, slew_misc=0;

			// --- NAMED CONTROLS (CRITICAL FOR MODULATION) ---
			var mod_speedL_Amts=NamedControl.kr(\mod_speedL_Amts, 0!8);
			var mod_speedR_Amts=NamedControl.kr(\mod_speedR_Amts, 0!8);
			var mod_flipL_Amts=NamedControl.kr(\mod_flipL_Amts, 0!8);
			var mod_flipR_Amts=NamedControl.kr(\mod_flipR_Amts, 0!8);
			var mod_skipL_Amts=NamedControl.kr(\mod_skipL_Amts, 0!8);
			var mod_skipR_Amts=NamedControl.kr(\mod_skipR_Amts, 0!8);
			var mod_ampL_Amts=NamedControl.kr(\mod_ampL_Amts, 0!8);
			var mod_ampR_Amts=NamedControl.kr(\mod_ampR_Amts, 0!8);
			var mod_fbL_Amts=NamedControl.kr(\mod_fbL_Amts, 0!8);
			var mod_fbR_Amts=NamedControl.kr(\mod_fbR_Amts, 0!8);
			var mod_filtL_Amts=NamedControl.kr(\mod_filtL_Amts, 0!8);
			var mod_filtR_Amts=NamedControl.kr(\mod_filtR_Amts, 0!8);
			var mod_recL_Amts=NamedControl.kr(\mod_recL_Amts, 0!8);
			var mod_recR_Amts=NamedControl.kr(\mod_recR_Amts, 0!8);
			var mod_p1_Amts=NamedControl.kr(\mod_p1_Amts, 0!8);
			var mod_p2_Amts=NamedControl.kr(\mod_p2_Amts, 0!8);
			var mod_p3_Amts=NamedControl.kr(\mod_p3_Amts, 0!8);
			var mod_p4_Amts=NamedControl.kr(\mod_p4_Amts, 0!8);
			var mod_p5_Amts=NamedControl.kr(\mod_p5_Amts, 0!8);
			var mod_p6_Amts=NamedControl.kr(\mod_p6_Amts, 0!8);

			var inputL_sig, inputR_sig, envL, envR;
			var p1, p2, p3, p4, p5, p6, c1, c2, c3, c4, c5, c6; 
			var out1, out2, out3, out4, out5, out6;
			var fb_mod, sources_sig; 
			var mod_val_speedL, mod_val_speedR, mod_val_flipL, mod_val_flipR;
			var mod_val_skipL, mod_val_skipR, mod_val_ampL, mod_val_ampR;
			var mod_val_fbL, mod_val_fbR, mod_val_filtL, mod_val_filtR;
			var mod_val_recL, mod_val_recR;
			var mod_p1, mod_p2, mod_p3, mod_p4, mod_p5, mod_p6;
			var dryL, dryR, finalRateL, finalRateR, ptrL, ptrR;
			var trigSkipL, trigSkipR, readL, readR, writeL, writeR;
			var envInL, envFbL, dolby_gainL, envInR, envFbR, dolby_gainR;
			var gateRecL, gateRecR, effFlipL, effFlipR, osc_trigger;
			var noiseL, noiseR, baseSR_L, baseSR_R, interpL, interpR;
			var is8L, is12L, is8R, is12R;
			var filtFreqL_LP, filtFreqL_HP, filtFreqR_LP, filtFreqR_HP;
			var endL, endR, feedbackL, feedbackR;

			inputL_sig = In.ar(inL); inputR_sig = In.ar(inR);
			inputL_sig = (inputL_sig * preampL).tanh; inputR_sig = (inputR_sig * preampR).tanh;
			envL = Amplitude.kr(inputL_sig, 0.05, envSlewL); envR = Amplitude.kr(inputR_sig, 0.05, envSlewR);

			is8L = bitDepthL < 10; is12L = (bitDepthL >= 10) * (bitDepthL < 14);
			is8R = bitDepthR < 10; is12R = (bitDepthR >= 10) * (bitDepthR < 14);
			noiseL = PinkNoise.ar((is8L * 0.0039) + (is12L * 0.00025));
			noiseR = PinkNoise.ar((is8R * 0.0039) + (is12R * 0.00025));
			baseSR_L = (is8L * 22050) + (is12L * 32000) + ((1 - is8L - is12L) * 48000);
			baseSR_R = (is8R * 22050) + (is12R * 32000) + ((1 - is8R - is12R) * 48000);
			interpL = 1 + (1 - is8L); interpR = 1 + (1 - is8R);
			inputL_sig = inputL_sig + noiseL; inputR_sig = inputR_sig + noiseR;

			fb_mod = LocalIn.ar(6); 
			sources_sig = [fb_mod[0], fb_mod[1], fb_mod[2], fb_mod[3], fb_mod[4], fb_mod[5], K2A.ar(envL*2-1), K2A.ar(envR*2-1)];
			
			mod_p1=(sources_sig*mod_p1_Amts).sum*10; mod_p2=(sources_sig*mod_p2_Amts).sum*10;
			mod_p3=(sources_sig*mod_p3_Amts).sum*10; mod_p4=(sources_sig*mod_p4_Amts).sum*10;
			mod_p5=(sources_sig*mod_p5_Amts).sum*10; mod_p6=(sources_sig*mod_p6_Amts).sum*10;

			p1=LFTri.ar(p1f+mod_p1,(fb_mod[5]*p1chaos*20).clip(-4,4)); p2=LFTri.ar(p2f+mod_p2,(p1*p2chaos*20).clip(-4,4));
			p3=LFTri.ar(p3f+mod_p3,(p2*p3chaos*20).clip(-4,4)); p4=LFTri.ar(p4f+mod_p4,(p3*p4chaos*20).clip(-4,4));
			p5=LFTri.ar(p5f+mod_p5,(p4*p5chaos*20).clip(-4,4)); p6=LFTri.ar(p6f+mod_p6,(p5*p6chaos*20).clip(-4,4));
			
			c1=Latch.ar(p6,p1).slew(500,500); c2=Latch.ar(p1,p2).slew(500,500); c3=Latch.ar(p2,p3).slew(500,500);
			c4=Latch.ar(p3,p4).slew(500,500); c5=Latch.ar(p4,p5).slew(500,500); c6=Latch.ar(p5,p6).slew(500,500);
			
			out1=Select.ar(p1shape,[p1,c1]); out2=Select.ar(p2shape,[p2,c2]); out3=Select.ar(p3shape,[p3,c3]);
			out4=Select.ar(p4shape,[p4,c4]); out5=Select.ar(p5shape,[p5,c5]); out6=Select.ar(p6shape,[p6,c6]);
			LocalOut.ar([p1,p2,p3,p4,p5,p6]); 
			sources_sig = [out1, out2, out3, out4, out5, out6, K2A.ar(envL*2-1), K2A.ar(envR*2-1)];

			// Matrix - SENSITIVE
			mod_val_speedL=(sources_sig*mod_speedL_Amts).sum.tanh.lag(slew_speed);
			mod_val_speedR=(sources_sig*mod_speedR_Amts).sum.tanh.lag(slew_speed);
			mod_val_ampL=(sources_sig*mod_ampL_Amts).sum.tanh.lag(slew_amp);
			mod_val_ampR=(sources_sig*mod_ampR_Amts).sum.tanh.lag(slew_amp);
			mod_val_fbL=(sources_sig*mod_fbL_Amts).sum.tanh.lag(slew_amp);
			mod_val_fbR=(sources_sig*mod_fbR_Amts).sum.tanh.lag(slew_amp);
			mod_val_filtL=(sources_sig*mod_filtL_Amts).sum.tanh.lag(slew_misc);
			mod_val_filtR=(sources_sig*mod_filtR_Amts).sum.tanh.lag(slew_misc);
			
			mod_val_flipL=Schmidt.ar((sources_sig*mod_flipL_Amts).sum, 0.1, 0.05);
			mod_val_flipR=Schmidt.ar((sources_sig*mod_flipR_Amts).sum, 0.1, 0.05);
			mod_val_skipL=Schmidt.ar((sources_sig*mod_skipL_Amts).sum, 0.1, 0.05);
			mod_val_skipR=Schmidt.ar((sources_sig*mod_skipR_Amts).sum, 0.1, 0.05);
			mod_val_recL=Schmidt.ar((sources_sig*mod_recL_Amts).sum, 0.1, 0.05);
			mod_val_recR=Schmidt.ar((sources_sig*mod_recR_Amts).sum, 0.1, 0.05);

			// --- COCO LOGIC ---
			
			// Rec Gate Logic: REC only gates the INPUT
			gateRecL = ((recL + mod_val_recL) > 0.5).lag(0.01);
			gateRecR = ((recR + mod_val_recR) > 0.5).lag(0.01);
			dryL = inputL_sig * (volInL + mod_val_ampL).clip(0, 2) * gateRecL; // Gated Input
			dryR = inputR_sig * (volInR + mod_val_ampR).clip(0, 2) * gateRecR;
			
			effFlipL = flipL * Select.ar(mod_val_flipL, [K2A.ar(1), K2A.ar(-1)]);
			effFlipR = flipR * Select.ar(mod_val_flipR, [K2A.ar(1), K2A.ar(-1)]);
			
			finalRateL = (speedL + mod_val_speedL).lag(0.05) * effFlipL;
			finalRateR = (speedR + mod_val_speedR).lag(0.05) * effFlipR;
			
			endL = BufFrames.kr(bufL) * (loopLen/60);
			endR = BufFrames.kr(bufR) * (loopLen/60);
			ptrL = Phasor.ar(0, finalRateL * BufRateScale.kr(bufL), 0, endL);
			ptrR = Phasor.ar(0, finalRateR * BufRateScale.kr(bufR), 0, endR);
			
			trigSkipL = (skipL + mod_val_skipL) > 0.5;
			trigSkipR = (skipR + mod_val_skipR) > 0.5;
			ptrL = ptrL + (trigSkipL * TRand.ar(0, 48000, Impulse.ar(15)));
			ptrR = ptrR + (trigSkipR * TRand.ar(0, 48000, Impulse.ar(15)));
			
			readL = BufRd.ar(1, bufL, ptrL, loop:1, interpolation: interpL);
			readR = BufRd.ar(1, bufR, ptrR, loop:1, interpolation: interpR);
			
			envInL = Amplitude.kr(dryL, 0.01, 0.05); envFbL = Amplitude.kr(readL, 0.01, 0.05);
			dolby_gainL = Select.kr(dolbyL, [DC.kr(1.0), envInL.linexp(0.001, 1, 0.1, 2.0), (1 / (envFbL + 0.01)).clip(0, 1)]);
			// Note: We don't apply dolby to dryL here because dryL is input to tape. Dolby acts on output or pre-tape? 
			// Original schematic: Input -> Dolby -> Tape.
			// Let's apply Dolby Gain to the signal going to tape.
			dryL = dryL * dolby_gainL;
			
			envInR = Amplitude.kr(dryR, 0.01, 0.05); envFbR = Amplitude.kr(readR, 0.01, 0.05);
			dolby_gainR = Select.kr(dolbyR, [DC.kr(1.0), envInR.linexp(0.001, 1, 0.1, 2.0), (1 / (envFbR + 0.01)).clip(0, 1)]);
			dryR = dryR * dolby_gainR;

			// FEEDBACK & WRITE
			// Feedback is always running, modulated by FB knob/cv
			feedbackL = readL * (fbL + mod_val_fbL).clip(0, 1.2) * 1.15; // Gain Comp
			feedbackR = readR * (fbR + mod_val_fbR).clip(0, 1.2) * 1.15;
			
			// FIXED FILTER in Feedback (7kHz)
			feedbackL = LPF.ar(feedbackL, 7000).softclip;
			feedbackR = LPF.ar(feedbackR, 7000).softclip;
			
			// SUM Input + Feedback
			writeL = dryL + feedbackL;
			writeR = dryR + feedbackR;
			
			// Bitcrush & SR Reduction
			writeL = writeL.round(0.5 ** bitDepthL);
			writeR = writeR.round(0.5 ** bitDepthR);
			writeL = Latch.ar(writeL, Impulse.ar((baseSR_L * finalRateL.abs).clip(100, 48000)));
			writeR = Latch.ar(writeR, Impulse.ar((baseSR_R * finalRateR.abs).clip(100, 48000)));
			
			// ALWAYS WRITE (Rec button only gated dryL)
			BufWr.ar(writeL, bufL, ptrL);
			BufWr.ar(writeR, bufR, ptrR);
			
			// OUTPUT FILTER (Variable)
			filtFreqL_LP = (filtL.min(0) + 1).linexp(0, 1, 100, 20000);
			filtFreqL_HP = filtL.max(0).linexp(0, 1, 20, 15000);
			readL = HPF.ar(LPF.ar(readL, filtFreqL_LP), filtFreqL_HP);
			filtFreqR_LP = (filtR.min(0) + 1).linexp(0, 1, 100, 20000);
			filtFreqR_HP = filtR.max(0).linexp(0, 1, 20, 15000);
			readR = HPF.ar(LPF.ar(readR, filtFreqR_LP), filtFreqR_HP);

			Out.ar(out, [readL * ampL, readR * ampR]);
			
			osc_trigger = Impulse.kr(15);
			SendReply.kr(osc_trigger, '/update', [ptrL/endL, ptrR/endR, gateRecL, gateRecR, effFlipL, effFlipR, trigSkipL, trigSkipR, out1, out2, out3, out4, out5, out6, envL, envR]);
		}).add;

		context.server.sync;
		synth = Synth.new(\NcocoDSP, [\out, context.out_b.index, \bufL, bufL, \bufR, bufR, \inL, context.in_b[0].index, \inR, context.in_b[1].index], context.xg);
		osc_responder = OSCFunc({ |msg| NetAddr("127.0.0.1", 10111).sendMsg("/update", *msg.drop(3)); }, '/update', context.server.addr).fix;

		// (Copy all addCommands from previous version here - Standard block)
		this.addCommand("write_tape", "isf", { |msg| var b=if(msg[1]==0,{bufL},{bufR}); b.write(msg[2],"wav","int16",0,msg[3]*48000) });
		this.addCommand("read_tape", "is", { |msg| var b=if(msg[1]==0,{bufL},{bufR}); b.read(msg[2]) });
		this.addCommand("speedL", "f", { |msg| synth.set(\speedL, msg[1]) });
		this.addCommand("speedR", "f", { |msg| synth.set(\speedR, msg[1]) });
		this.addCommand("fbL", "f", { |msg| synth.set(\fbL, msg[1]) });
		this.addCommand("fbR", "f", { |msg| synth.set(\fbR, msg[1]) });
		this.addCommand("volInL", "f", { |msg| synth.set(\volInL, msg[1]) });
		this.addCommand("volInR", "f", { |msg| synth.set(\volInR, msg[1]) });
		this.addCommand("recL", "i", { |msg| synth.set(\recL, msg[1]) });
		this.addCommand("recR", "i", { |msg| synth.set(\recR, msg[1]) });
		this.addCommand("flipL", "i", { |msg| synth.set(\flipL, msg[1]) });
		this.addCommand("flipR", "i", { |msg| synth.set(\flipR, msg[1]) });
		this.addCommand("skipL", "i", { |msg| synth.set(\skipL, msg[1]) });
		this.addCommand("skipR", "i", { |msg| synth.set(\skipR, msg[1]) });
		this.addCommand("bitDepthL", "f", { |msg| synth.set(\bitDepthL, msg[1]) });
		this.addCommand("bitDepthR", "f", { |msg| synth.set(\bitDepthR, msg[1]) });
		this.addCommand("dolbyL", "i", { |msg| synth.set(\dolbyL, msg[1]) });
		this.addCommand("dolbyR", "i", { |msg| synth.set(\dolbyR, msg[1]) });
		this.addCommand("filtL", "f", { |msg| synth.set(\filtL, msg[1]) });
		this.addCommand("filtR", "f", { |msg| synth.set(\filtR, msg[1]) });
		this.addCommand("ampL", "f", { |msg| synth.set(\ampL, msg[1]) });
		this.addCommand("ampR", "f", { |msg| synth.set(\ampR, msg[1]) });
		this.addCommand("slew_speed", "f", { |msg| synth.set(\slew_speed, msg[1]) });
		this.addCommand("loopLen", "f", { |msg| synth.set(\loopLen, msg[1]) });
		this.addCommand("preampL", "f", { |msg| synth.set(\preampL, msg[1]) });
		this.addCommand("preampR", "f", { |msg| synth.set(\preampR, msg[1]) });
		this.addCommand("envSlewL", "f", { |msg| synth.set(\envSlewL, msg[1]) });
		this.addCommand("envSlewR", "f", { |msg| synth.set(\envSlewR, msg[1]) });
		this.addCommand("p1f", "f", { |msg| synth.set(\p1f, msg[1]) });
		this.addCommand("p2f", "f", { |msg| synth.set(\p2f, msg[1]) });
		this.addCommand("p3f", "f", { |msg| synth.set(\p3f, msg[1]) });
		this.addCommand("p4f", "f", { |msg| synth.set(\p4f, msg[1]) });
		this.addCommand("p5f", "f", { |msg| synth.set(\p5f, msg[1]) });
		this.addCommand("p6f", "f", { |msg| synth.set(\p6f, msg[1]) });
		this.addCommand("p1chaos", "f", { |msg| synth.set(\p1chaos, msg[1]) });
		this.addCommand("p2chaos", "f", { |msg| synth.set(\p2chaos, msg[1]) });
		this.addCommand("p3chaos", "f", { |msg| synth.set(\p3chaos, msg[1]) });
		this.addCommand("p4chaos", "f", { |msg| synth.set(\p4chaos, msg[1]) });
		this.addCommand("p5chaos", "f", { |msg| synth.set(\p5chaos, msg[1]) });
		this.addCommand("p6chaos", "f", { |msg| synth.set(\p6chaos, msg[1]) });
		this.addCommand("p1shape", "f", { |msg| synth.set(\p1shape, msg[1]) });
		this.addCommand("p2shape", "f", { |msg| synth.set(\p2shape, msg[1]) });
		this.addCommand("p3shape", "f", { |msg| synth.set(\p3shape, msg[1]) });
		this.addCommand("p4shape", "f", { |msg| synth.set(\p4shape, msg[1]) });
		this.addCommand("p5shape", "f", { |msg| synth.set(\p5shape, msg[1]) });
		this.addCommand("p6shape", "f", { |msg| synth.set(\p6shape, msg[1]) });
		
		this.addCommand("mod_speedL", "ffffffff", { |msg| synth.setn(\mod_speedL_Amts, msg.drop(1)) });
		this.addCommand("mod_speedR", "ffffffff", { |msg| synth.setn(\mod_speedR_Amts, msg.drop(1)) });
		this.addCommand("mod_flipL", "ffffffff", { |msg| synth.setn(\mod_flipL_Amts, msg.drop(1)) });
		this.addCommand("mod_flipR", "ffffffff", { |msg| synth.setn(\mod_flipR_Amts, msg.drop(1)) });
		this.addCommand("mod_skipL", "ffffffff", { |msg| synth.setn(\mod_skipL_Amts, msg.drop(1)) });
		this.addCommand("mod_skipR", "ffffffff", { |msg| synth.setn(\mod_skipR_Amts, msg.drop(1)) });
		this.addCommand("mod_ampL", "ffffffff", { |msg| synth.setn(\mod_ampL_Amts, msg.drop(1)) });
		this.addCommand("mod_ampR", "ffffffff", { |msg| synth.setn(\mod_ampR_Amts, msg.drop(1)) });
		this.addCommand("mod_fbL", "ffffffff", { |msg| synth.setn(\mod_fbL_Amts, msg.drop(1)) });
		this.addCommand("mod_fbR", "ffffffff", { |msg| synth.setn(\mod_fbR_Amts, msg.drop(1)) });
		this.addCommand("mod_filtL", "ffffffff", { |msg| synth.setn(\mod_filtL_Amts, msg.drop(1)) });
		this.addCommand("mod_filtR", "ffffffff", { |msg| synth.setn(\mod_filtR_Amts, msg.drop(1)) });
		this.addCommand("mod_recL", "ffffffff", { |msg| synth.setn(\mod_recL_Amts, msg.drop(1)) });
		this.addCommand("mod_recR", "ffffffff", { |msg| synth.setn(\mod_recR_Amts, msg.drop(1)) });
		this.addCommand("mod_p1", "ffffffff", { |msg| synth.setn(\mod_p1_Amts, msg.drop(1)) });
		this.addCommand("mod_p2", "ffffffff", { |msg| synth.setn(\mod_p2_Amts, msg.drop(1)) });
		this.addCommand("mod_p3", "ffffffff", { |msg| synth.setn(\mod_p3_Amts, msg.drop(1)) });
		this.addCommand("mod_p4", "ffffffff", { |msg| synth.setn(\mod_p4_Amts, msg.drop(1)) });
		this.addCommand("mod_p5", "ffffffff", { |msg| synth.setn(\mod_p5_Amts, msg.drop(1)) });
		this.addCommand("mod_p6", "ffffffff", { |msg| synth.setn(\mod_p6_Amts, msg.drop(1)) });
	}

	free { osc_responder.free; synth.free; bufL.free; bufR.free; }
}