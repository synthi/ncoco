// Engine_Ncoco.sc v2026
// CHANGELOG v2026:
// 1. CRASH FIX: Restored Dual Definition of 'sources_sig'.
//    - Def 1 uses feedback signals (for internal Petal FM).
//    - Def 2 uses live signals (for external parameter modulation).
//    - Solves "Variable not defined" crash during init.
// 2. ENVELOPE: Maintained Split logic (Raw for Dolby, Boost for Mod/UI).

Engine_Ncoco : CroneEngine {
	var <synth;
	var <bufL, <bufR;
	var <osc_responder; 
	var <norns_addr;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		// FIXED 60s BUFFER
		bufL = Buffer.alloc(context.server, 48000 * 60, 1);
		bufR = Buffer.alloc(context.server, 48000 * 60, 1);
		norns_addr = NetAddr("127.0.0.1", 10111);
		
		context.server.sync;
		bufL.zero; bufR.zero;
		context.server.sync;

		SynthDef(\NcocoDSP, {
			arg out, inL, inR, bufL, bufR,
			recL=0, recR=0, fbL=0.85, fbR=0.85, speedL=1.0, speedR=1.0,     
			flipL=0, flipR=0, skipL=0, skipR=0,           
			volInL=1.0, volInR=1.0,     
			filtL=0, filtR=0, ampL=1.0, ampR=1.0,
			panL= -0.5, panR=0.5,
			
			bitDepthL=8, bitDepthR=8, interp=2,                   
			dolbyL=0, dolbyR=0, loopLen=8.0, skipMode=0,
			preampL=1.0, preampR=1.0, envSlewL=0.05, envSlewR=0.05,
			dolbyBoostL=0, dolbyBoostR=0, 

			p1f=0.5, p2f=0.6, p3f=0.7, p4f=0.8, p5f=0.9, p6f=1.0,
			p1chaos=0, p2chaos=0, p3chaos=0, p4chaos=0, p5chaos=0, p6chaos=0,
			p1shape=0, p2shape=0, p3shape=0, p4shape=0, p5shape=0, p6shape=0,
			
			slew_speed=0.1, slew_amp=0.05, slew_misc=0;

			// --- VARS ---
			var dest_gains;
			var mod_speedL_Amts, mod_speedR_Amts;
			var mod_flipL_Amts, mod_flipR_Amts;
			var mod_skipL_Amts, mod_skipR_Amts;
			var mod_ampL_Amts, mod_ampR_Amts;
			var mod_fbL_Amts, mod_fbR_Amts;
			var mod_filtL_Amts, mod_filtR_Amts;
			var mod_recL_Amts, mod_recR_Amts;
			var mod_p1_Amts, mod_p2_Amts, mod_p3_Amts, mod_p4_Amts, mod_p5_Amts, mod_p6_Amts;
			var mod_volL_Amts, mod_volR_Amts; 

			var inputL_sig, inputR_sig, envL, envR;
			var envL_raw, envR_raw, envL_dolby, envR_dolby;

			var p1, p2, p3, p4, p5, p6;
			var c1, c2, c3, c4, c5, c6; 
			var b_ph1, b_ph2, b_ph3, b_ph4, b_ph5, b_ph6; 
			var t1, t2, t3, t4, t5, t6; 
			var out1, out2, out3, out4, out5, out6;
			var fb_mod, sources_sig; 
			
			var mod_val_speedL, mod_val_speedR, mod_val_flipL, mod_val_flipR;
			var mod_val_skipL, mod_val_skipR, mod_val_ampL, mod_val_ampR;
			var mod_val_fbL, mod_val_fbR, mod_val_filtL, mod_val_filtR;
			var mod_val_recL, mod_val_recR;
			var mod_val_volL, mod_val_volR;
			var mod_p1, mod_p2, mod_p3, mod_p4, mod_p5, mod_p6;
			
			var dryL, dryR, finalRateL, finalRateR, ptrL, ptrR;
			var trigSkipL, trigSkipR, readL, readR, writeL, writeR;
			var gateRecL, gateRecR; 
			var noiseL, noiseR, baseSR_L, baseSR_R, interpL, interpR;
			var is8L, is12L, is8R, is12R, fixedFiltFreq;
			var endL, endR;
			var jumpTrigL, jumpTrigR;
			var yellowL, yellowR;
			var totalFiltL, totalFiltR;
			
			var d_lin_inL, d_exp_inL, d_duck_inL;
			var d_lin_fbL, d_exp_fbL, d_duck_fbL;
			var d_lin_inR, d_exp_inR, d_duck_inR;
			var d_lin_fbR, d_exp_fbR, d_duck_fbR;
			var gainInL, gainFbL, gainInR, gainFbR;
			var envFbL, envFbR;
			
			var driftL, driftR, bleedL, bleedR;
			var baseSpeedL, baseSpeedR;
			var flipLogicL, flipLogicR; 
			var flipStateL, flipStateR;
			var recLogicL, recLogicR;
			var feedbackL, feedbackR;
			var osc_trigger; 
			var finalVolL, finalVolR;
			var master_out; 

			var feedback_in, fb_petals, fb_yellow;

			// --- DSP ---

			dest_gains = NamedControl.kr(\dest_gains, 1!22); 
			
			mod_speedL_Amts=NamedControl.kr(\mod_speedL_Amts, 0!10);
			mod_speedR_Amts=NamedControl.kr(\mod_speedR_Amts, 0!10);
			mod_flipL_Amts=NamedControl.kr(\mod_flipL_Amts, 0!10);
			mod_flipR_Amts=NamedControl.kr(\mod_flipR_Amts, 0!10);
			mod_skipL_Amts=NamedControl.kr(\mod_skipL_Amts, 0!10);
			mod_skipR_Amts=NamedControl.kr(\mod_skipR_Amts, 0!10);
			mod_ampL_Amts=NamedControl.kr(\mod_ampL_Amts, 0!10);
			mod_ampR_Amts=NamedControl.kr(\mod_ampR_Amts, 0!10);
			mod_fbL_Amts=NamedControl.kr(\mod_fbL_Amts, 0!10);
			mod_fbR_Amts=NamedControl.kr(\mod_fbR_Amts, 0!10);
			mod_filtL_Amts=NamedControl.kr(\mod_filtL_Amts, 0!10);
			mod_filtR_Amts=NamedControl.kr(\mod_filtR_Amts, 0!10);
			mod_recL_Amts=NamedControl.kr(\mod_recL_Amts, 0!10);
			mod_recR_Amts=NamedControl.kr(\mod_recR_Amts, 0!10);
			mod_volL_Amts=NamedControl.kr(\mod_volL_Amts, 0!10); 
			mod_volR_Amts=NamedControl.kr(\mod_volR_Amts, 0!10); 
			mod_p1_Amts=NamedControl.kr(\mod_p1_Amts, 0!10);
			mod_p2_Amts=NamedControl.kr(\mod_p2_Amts, 0!10);
			mod_p3_Amts=NamedControl.kr(\mod_p3_Amts, 0!10);
			mod_p4_Amts=NamedControl.kr(\mod_p4_Amts, 0!10);
			mod_p5_Amts=NamedControl.kr(\mod_p5_Amts, 0!10);
			mod_p6_Amts=NamedControl.kr(\mod_p6_Amts, 0!10);

			feedback_in = LocalIn.ar(8);
			fb_petals = feedback_in[0..5].tanh; 
			fb_yellow = feedback_in[6..7]; 

			inputL_sig = In.ar(inL); inputR_sig = In.ar(inR);
			inputL_sig = (inputL_sig * preampL).tanh; inputR_sig = (inputR_sig * preampR).tanh;
			
			// ENVELOPES
			envL_raw = Amplitude.kr(inputL_sig, 0.01, 0.08); 
			envR_raw = Amplitude.kr(inputR_sig, 0.01, 0.08);

			// BOOSTED (UI/Mod)
			envL = envL_raw * 2.0;
			envR = envR_raw * 2.0;
			
			// DOLBY SELECTOR
			envL_dolby = Select.kr(dolbyBoostL, [envL_raw, envL]);
			envR_dolby = Select.kr(dolbyBoostR, [envR_raw, envR]);

			is8L = bitDepthL < 10; is12L = (bitDepthL >= 10) * (bitDepthL < 14);
			is8R = bitDepthR < 10; is12R = (bitDepthR >= 10) * (bitDepthR < 14);
			noiseL = PinkNoise.ar((is8L * 0.008) + (is12L * 0.00025));
			noiseR = PinkNoise.ar((is8R * 0.008) + (is12R * 0.00025));
			baseSR_L = (is8L * 16000) + (is12L * 24000) + ((1 - is8L - is12L) * 32000);
			baseSR_R = (is8R * 16000) + (is12R * 24000) + ((1 - is8R - is12R) * 32000);
			fixedFiltFreq = (is8L * 7000) + (is12L * 11000) + ((1 - is8L - is12L) * 16000);
			interpL = 1 + (1 - is8L); interpR = 1 + (1 - is8R);
			inputL_sig = inputL_sig + noiseL; inputR_sig = inputR_sig + noiseR;

			yellowL = DC.ar(0); yellowR = DC.ar(0);
			
			// --- SOURCE SIG 1: FOR PETAL FM (Uses Feedback/Past Signals) ---
			// CRITICAL FIX: Defined here before Petal Phasors
			sources_sig = [fb_petals[0], fb_petals[1], fb_petals[2], fb_petals[3], fb_petals[4], fb_petals[5], K2A.ar(envL), K2A.ar(envR), fb_yellow[0], fb_yellow[1]];
			
			mod_p1=((sources_sig*mod_p1_Amts).sum * dest_gains[14] * 10);
			mod_p2=((sources_sig*mod_p2_Amts).sum * dest_gains[15] * 10);
			mod_p3=((sources_sig*mod_p3_Amts).sum * dest_gains[16] * 10);
			mod_p4=((sources_sig*mod_p4_Amts).sum * dest_gains[17] * 10);
			mod_p5=((sources_sig*mod_p5_Amts).sum * dest_gains[18] * 10);
			mod_p6=((sources_sig*mod_p6_Amts).sum * dest_gains[19] * 10);

			b_ph1 = Phasor.ar(0, (p1f + mod_p1).abs * SampleDur.ir, 0, 1);
			t1 = Trig1.ar(b_ph1 > 0.05, SampleDur.ir); 
			p1 = ((b_ph1 + (fb_petals[5] * p1chaos.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;

			b_ph2 = Phasor.ar(0, (p2f + mod_p2).abs * SampleDur.ir, 0, 1);
			t2 = Trig1.ar(b_ph2 > 0.05, SampleDur.ir);
			p2 = ((b_ph2 + (p1 * p2chaos.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;

			b_ph3 = Phasor.ar(0, (p3f + mod_p3).abs * SampleDur.ir, 0, 1);
			t3 = Trig1.ar(b_ph3 > 0.05, SampleDur.ir);
			p3 = ((b_ph3 + (p2 * p3chaos.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;

			b_ph4 = Phasor.ar(0, (p4f + mod_p4).abs * SampleDur.ir, 0, 1);
			t4 = Trig1.ar(b_ph4 > 0.05, SampleDur.ir);
			p4 = ((b_ph4 + (p3 * p4chaos.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;

			b_ph5 = Phasor.ar(0, (p5f + mod_p5).abs * SampleDur.ir, 0, 1);
			t5 = Trig1.ar(b_ph5 > 0.05, SampleDur.ir);
			p5 = ((b_ph5 + (p4 * p5chaos.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;

			b_ph6 = Phasor.ar(0, (p6f + mod_p6).abs * SampleDur.ir, 0, 1);
			t6 = Trig1.ar(b_ph6 > 0.05, SampleDur.ir);
			p6 = ((b_ph6 + (p5 * p6chaos.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			
			c1=Latch.ar(p6,t1); c2=Latch.ar(p1,t2); c3=Latch.ar(p2,t3);
			c4=Latch.ar(p3,t4); c5=Latch.ar(p4,t5); c6=Latch.ar(p5,t6);
			
			out1=Select.ar(p1shape,[p1,c1]); out2=Select.ar(p2shape,[p2,c2]); out3=Select.ar(p3shape,[p3,c3]);
			out4=Select.ar(p4shape,[p4,c4]); out5=Select.ar(p5shape,[p5,c5]); out6=Select.ar(p6shape,[p6,c6]);
			
			// --- SOURCE SIG 2: FOR GENERAL MODULATION (Uses Live Signals) ---
			// CRITICAL FIX: Redefined here after Oscillators exist
			sources_sig = [out1, out2, out3, out4, out5, out6, K2A.ar(envL), K2A.ar(envR), fb_yellow[0], fb_yellow[1]];

			driftL = LFNoise2.kr(0.5, 0.005); 
			driftR = LFNoise2.kr(0.5, 0.005);

			mod_val_speedL=((sources_sig*mod_speedL_Amts).sum * dest_gains[0]).tanh.lag(0.01);
			mod_val_speedR=((sources_sig*mod_speedR_Amts).sum * dest_gains[7]).tanh.lag(0.01);
			
			mod_val_ampL=((sources_sig*mod_ampL_Amts).sum * dest_gains[1]).tanh.lag(slew_amp);
			mod_val_ampR=((sources_sig*mod_ampR_Amts).sum * dest_gains[8]).tanh.lag(slew_amp);
			mod_val_fbL=((sources_sig*mod_fbL_Amts).sum * dest_gains[2]).tanh.lag(slew_amp);
			mod_val_fbR=((sources_sig*mod_fbR_Amts).sum * dest_gains[9]).tanh.lag(slew_amp);
			mod_val_filtL=((sources_sig*mod_filtL_Amts).sum * dest_gains[3]).tanh.lag(slew_misc);
			mod_val_filtR=((sources_sig*mod_filtR_Amts).sum * dest_gains[10]).tanh.lag(slew_misc);
            
			mod_val_volL=((sources_sig*mod_volL_Amts).sum * dest_gains[20]).tanh.lag(slew_amp);
			mod_val_volR=((sources_sig*mod_volR_Amts).sum * dest_gains[21]).tanh.lag(slew_amp);
			
			mod_val_flipL = (sources_sig*mod_flipL_Amts).sum * dest_gains[4];
			mod_val_flipR = (sources_sig*mod_flipR_Amts).sum * dest_gains[11];
			
			mod_val_skipL=Schmidt.ar((sources_sig*mod_skipL_Amts).sum * dest_gains[5], 0.6, 0.4);
			mod_val_skipR=Schmidt.ar((sources_sig*mod_skipR_Amts).sum * dest_gains[12], 0.6, 0.4);
			mod_val_recL=Schmidt.ar((sources_sig*mod_recL_Amts).sum * dest_gains[6], 0.6, 0.4);
			mod_val_recR=Schmidt.ar((sources_sig*mod_recR_Amts).sum * dest_gains[13], 0.6, 0.4);

			recLogicL = (recL + mod_val_recL).mod(2);
			recLogicR = (recR + mod_val_recR).mod(2);
			gateRecL = Select.ar(recLogicL > 0.5, [K2A.ar(0), K2A.ar(1)]);
			gateRecR = Select.ar(recLogicR > 0.5, [K2A.ar(0), K2A.ar(1)]);

			dryL = inputL_sig * (volInL + mod_val_ampL).clip(0, 2);
			dryR = inputR_sig * (volInR + mod_val_ampR).clip(0, 2);
			
			baseSpeedL = (speedL + mod_val_speedL + driftL).lag(0.01);
			baseSpeedR = (speedR + mod_val_speedR + driftR).lag(0.01);

			flipLogicL = (flipL + (mod_val_flipL > 0.1)).mod(2);
			flipLogicR = (flipR + (mod_val_flipR > 0.1)).mod(2);
			flipStateL = flipLogicL; flipStateR = flipLogicR;

			finalRateL = Select.ar(flipLogicL > 0.5, [baseSpeedL, baseSpeedL * -1]);
			finalRateR = Select.ar(flipLogicR > 0.5, [baseSpeedR, baseSpeedR * -1]);
			
			jumpTrigL = Changed.ar(skipL + mod_val_skipL);
			jumpTrigR = Changed.ar(skipR + mod_val_skipR);
			
			endL = (loopLen * 48000).min(BufFrames.kr(bufL));
			endR = (loopLen * 48000).min(BufFrames.kr(bufR));
			
			ptrL = Phasor.ar(jumpTrigL, finalRateL * BufRateScale.kr(bufL), 0, endL, TRand.ar(0, endL, jumpTrigL));
			ptrR = Phasor.ar(jumpTrigR, finalRateR * BufRateScale.kr(bufR), 0, endR, TRand.ar(0, endR, jumpTrigR));
			
			yellowL = (ptrL / endL);
			yellowR = (ptrR / endR);
			
			LocalOut.ar([p1, p2, p3, p4, p5, p6, yellowL, yellowR]);

			bleedL = SinOsc.ar((baseSR_L * finalRateL.abs).clip(20, 20000)) * 0.001;
			bleedR = SinOsc.ar((baseSR_R * finalRateR.abs).clip(20, 20000)) * 0.001;

			readL = BufRd.ar(1, bufL, ptrL, loop:1, interpolation: interpL);
			readR = BufRd.ar(1, bufR, ptrR, loop:1, interpolation: interpR);
			
			envFbL = Amplitude.kr(readL, 0.01, 0.08); 
			envFbR = Amplitude.kr(readR, 0.01, 0.08);
			
			d_lin_inL = DC.kr(1.0);
			d_exp_inL = envL_dolby.pow(2);
			d_duck_inL = (1 - envFbL).clip(0,1);
			d_lin_inR = DC.kr(1.0);
			d_exp_inR = envR_dolby.pow(2);
			d_duck_inR = (1 - envFbR).clip(0,1);

			d_lin_fbL = DC.kr(1.0);
			d_exp_fbL = envFbL.pow(2);
			d_duck_fbL = (1 - envL_dolby).clip(0,1);
			d_lin_fbR = DC.kr(1.0);
			d_exp_fbR = envFbR.pow(2);
			d_duck_fbR = (1 - envR_dolby).clip(0,1);

			gainInL = Select.kr(dolbyL, [d_lin_inL, d_exp_inL, d_lin_inL, d_exp_inL, d_lin_inL, d_duck_inL, d_exp_inL, d_duck_inL, d_duck_inL]);
			gainFbL = Select.kr(dolbyL, [d_lin_fbL, d_lin_fbL, d_exp_fbL, d_exp_fbL, d_duck_fbL, d_lin_fbL, d_duck_fbL, d_exp_fbL, d_duck_fbL]);
			
			gainInR = Select.kr(dolbyR, [d_lin_inR, d_exp_inR, d_lin_inR, d_exp_inR, d_lin_inR, d_duck_inR, d_exp_inR, d_duck_inR, d_duck_inR]);
			gainFbR = Select.kr(dolbyR, [d_lin_fbR, d_lin_fbR, d_exp_fbR, d_exp_fbR, d_duck_fbR, d_lin_fbR, d_duck_fbR, d_exp_fbR, d_duck_fbR]);

			feedbackL = readL * (fbL + mod_val_fbL).clip(0, 1.2) * 1.15;
			feedbackR = readR * (fbR + mod_val_fbR).clip(0, 1.2) * 1.15;
			feedbackL = LPF.ar(feedbackL, fixedFiltFreq).softclip;
			feedbackR = LPF.ar(feedbackR, fixedFiltFreq).softclip;
			
			writeL = (dryL * gainInL * gateRecL) + (feedbackL * gainFbL);
			writeR = (dryR * gainInR * gateRecR) + (feedbackR * gainFbR);
			
			writeL = writeL.round(0.5 ** bitDepthL);
			writeR = writeR.round(0.5 ** bitDepthR);
			
			writeL = Latch.ar(writeL, Impulse.ar((baseSR_L * finalRateL.abs).clip(100, 48000) * (1 + WhiteNoise.ar(0.02))));
			writeR = Latch.ar(writeR, Impulse.ar((baseSR_R * finalRateR.abs).clip(100, 48000) * (1 + WhiteNoise.ar(0.02))));
			
			BufWr.ar(writeL, bufL, ptrL);
			BufWr.ar(writeR, bufR, ptrR);
			
			totalFiltL = (filtL + mod_val_filtL).clip(-1, 1);
			totalFiltR = (filtR + mod_val_filtR).clip(-1, 1);

			readL = Select.ar(totalFiltL.abs < 0.05, [
				HPF.ar(LPF.ar(readL, (totalFiltL.min(0)+1).linexp(0,1,100,20000)), totalFiltL.max(0).linexp(0,1,20,15000)),
				readL
			]);
			readR = Select.ar(totalFiltR.abs < 0.05, [
				HPF.ar(LPF.ar(readR, (totalFiltR.min(0)+1).linexp(0,1,100,20000)), totalFiltR.max(0).linexp(0,1,20,15000)),
				readR
			]);
            
            finalVolL = (ampL + mod_val_volL).clip(0, 2);
            finalVolR = (ampR + mod_val_volR).clip(0, 2);

			master_out = Balance2.ar((readL + bleedL)*finalVolL, (readL + bleedL)*finalVolL, panL) + Balance2.ar((readR + bleedR)*finalVolR, (readR + bleedR)*finalVolR, panR);
            Out.ar(out, Limiter.ar(master_out, 0.95)); 
			
			osc_trigger = Impulse.kr(30);
			SendReply.kr(osc_trigger, '/update', [ptrL/endL, ptrR/endR, gateRecL, gateRecR, flipStateL, flipStateR, (skipL + mod_val_skipL).clip(0,1), (skipR + mod_val_skipR).clip(0,1), out1, out2, out3, out4, out5, out6, envL, envR, yellowL, yellowR, finalRateL, finalRateR, Amplitude.kr(readL*ampL), Amplitude.kr(readR*ampR)]);
		}).add;

		context.server.sync;
		synth = Synth.new(\NcocoDSP, [\out, context.out_b.index, \bufL, bufL, \bufR, bufR, \inL, context.in_b[0].index, \inR, context.in_b[1].index], context.xg);
		osc_responder = OSCFunc({ |msg| NetAddr("127.0.0.1", 10111).sendMsg("/update", *msg.drop(3)); }, '/update', context.server.addr).fix;

		this.addCommand("clear_tape", "i", { |msg| var b=if(msg[1]==0,{bufL},{bufR}); b.zero; });
		this.addCommand("dest_gains", "ffffffffffffffffffffff", { |msg| synth.setn(\dest_gains, msg.drop(1)) });
		
		this.addCommand("write_tape", "isf", { |msg| 
			var b=if(msg[1]==1,{bufL},{bufR}); 
			var len_frames = (msg[3] * 48000).asInteger;
			b.write(msg[2], "wav", "int16", numFrames: len_frames); 
		});
		
		this.addCommand("read_tape", "is", { |msg| 
			var target_buf = if(msg[1]==1,{bufL},{bufR}); 
			var path = msg[2];
			var maxFrames = target_buf.numFrames; 
			
			if(File.exists(path)) {
				Buffer.read(context.server, path, 0, maxFrames, action: { |temp|
					temp.copyData(target_buf, 0, 0, temp.numFrames);
					norns_addr.sendMsg("/buffer_info", msg[1], temp.numFrames / 48000.0);
					temp.free;
				});
			}
		});

		this.addCommand("skipMode", "i", { |msg| synth.set(\skipMode, msg[1]) });
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
		this.addCommand("panL", "f", { |msg| synth.set(\panL, msg[1]) });
		this.addCommand("panR", "f", { |msg| synth.set(\panR, msg[1]) });
		this.addCommand("slew_speed", "f", { |msg| synth.set(\slew_speed, msg[1]) });
		this.addCommand("loopLen", "f", { |msg| synth.set(\loopLen, msg[1]) });
		this.addCommand("preampL", "f", { |msg| synth.set(\preampL, msg[1]) });
		this.addCommand("preampR", "f", { |msg| synth.set(\preampR, msg[1]) });
		this.addCommand("envSlewL", "f", { |msg| synth.set(\envSlewL, msg[1]) });
		this.addCommand("envSlewR", "f", { |msg| synth.set(\envSlewR, msg[1]) });
		this.addCommand("dolbyBoostL", "i", { |msg| synth.set(\dolbyBoostL, msg[1]); });
		this.addCommand("dolbyBoostR", "i", { |msg| synth.set(\dolbyBoostR, msg[1]); });

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
		this.addCommand("mod_speedL", "ffffffffff", { |msg| synth.setn(\mod_speedL_Amts, msg.drop(1)) });
		this.addCommand("mod_speedR", "ffffffffff", { |msg| synth.setn(\mod_speedR_Amts, msg.drop(1)) });
		this.addCommand("mod_flipL", "ffffffffff", { |msg| synth.setn(\mod_flipL_Amts, msg.drop(1)) });
		this.addCommand("mod_flipR", "ffffffffff", { |msg| synth.setn(\mod_flipR_Amts, msg.drop(1)) });
		this.addCommand("mod_skipL", "ffffffffff", { |msg| synth.setn(\mod_skipL_Amts, msg.drop(1)) });
		this.addCommand("mod_skipR", "ffffffffff", { |msg| synth.setn(\mod_skipR_Amts, msg.drop(1)) });
		this.addCommand("mod_ampL", "ffffffffff", { |msg| synth.setn(\mod_ampL_Amts, msg.drop(1)) });
		this.addCommand("mod_ampR", "ffffffffff", { |msg| synth.setn(\mod_ampR_Amts, msg.drop(1)) });
		this.addCommand("mod_fbL", "ffffffffff", { |msg| synth.setn(\mod_fbL_Amts, msg.drop(1)) });
		this.addCommand("mod_fbR", "ffffffffff", { |msg| synth.setn(\mod_fbR_Amts, msg.drop(1)) });
		this.addCommand("mod_filtL", "ffffffffff", { |msg| synth.setn(\mod_filtL_Amts, msg.drop(1)) });
		this.addCommand("mod_filtR", "ffffffffff", { |msg| synth.setn(\mod_filtR_Amts, msg.drop(1)) });
		this.addCommand("mod_recL", "ffffffffff", { |msg| synth.setn(\mod_recL_Amts, msg.drop(1)) });
		this.addCommand("mod_recR", "ffffffffff", { |msg| synth.setn(\mod_recR_Amts, msg.drop(1)) });
		this.addCommand("mod_volL", "ffffffffff", { |msg| synth.setn(\mod_volL_Amts, msg.drop(1)) });
		this.addCommand("mod_volR", "ffffffffff", { |msg| synth.setn(\mod_volR_Amts, msg.drop(1)) });
		this.addCommand("mod_p1", "ffffffffff", { |msg| synth.setn(\mod_p1_Amts, msg.drop(1)) });
		this.addCommand("mod_p2", "ffffffffff", { |msg| synth.setn(\mod_p2_Amts, msg.drop(1)) });
		this.addCommand("mod_p3", "ffffffffff", { |msg| synth.setn(\mod_p3_Amts, msg.drop(1)) });
		this.addCommand("mod_p4", "ffffffffff", { |msg| synth.setn(\mod_p4_Amts, msg.drop(1)) });
		this.addCommand("mod_p5", "ffffffffff", { |msg| synth.setn(\mod_p5_Amts, msg.drop(1)) });
		this.addCommand("mod_p6", "ffffffffff", { |msg| synth.setn(\mod_p6_Amts, msg.drop(1)) });
	}

	free { osc_responder.free; synth.free; bufL.free; bufR.free; }
}
