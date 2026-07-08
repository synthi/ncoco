// Engine_Ncoco.sc v2.51
// CHANGELOG v2.51:
// 1. FIX: Extensive Select.ar vs Select.kr rate mismatches resolved across entire SynthDef.
// 2. FIX: Critical ADPCM matrix lookup restored to per-sample Audio Rate using DC.ar arrays, avoiding A2K downsampling destruction.
// 3. FIX: Removed fatal .asInteger calls on UGens, replaced with pure BinaryOpUGen math.
// 4. FIX: SendReply.kr OSC payload corrected (proper K2A -> A2K downsampling for trigger broadcast).
// 5. FIX: Synth 2 DJ Filter routing protected with K2A.ar wrappers.

Engine_Ncoco : CroneEngine {
	var <synth_core, <synth_out;
	var <bufL, <bufR;
	var <b_tape, <b_mon, <b_bleed, <b_mod_vol, <b_mod_filt; 
	var <osc_responder; 
	var <norns_addr;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		// 1. Allocate RAM & BUSES
		bufL = Buffer.alloc(context.server, 48000 * 60, 1);
		bufR = Buffer.alloc(context.server, 48000 * 60, 1);
		
		// Internal Interconnects
		b_tape = Bus.audio(context.server, 2);      // Tape signal (Clean)
		b_mon = Bus.audio(context.server, 2);       // Monitor signal
		b_bleed = Bus.audio(context.server, 2);     // Bleed signal isolated
		b_mod_vol = Bus.control(context.server, 2); 
		b_mod_filt = Bus.control(context.server, 2);
		
		norns_addr = NetAddr("127.0.0.1", 10111);
		
		// Barrier 1
		context.server.sync;
		bufL.zero; bufR.zero;
		context.server.sync;

		// -----------------------------------------------------------
		// SYNTH 1: CORE
		// -----------------------------------------------------------
		SynthDef(\NcocoCore, {
			arg bufL, bufR, inL, inR,
			bus_tape_out, bus_mon_out, bus_bleed_out,
			bus_mvol_out, bus_mfilt_out,
			
			recL=0, recR=0, fbL=0.85, fbR=0.85, speedL=1.0, speedR=1.0,     
			flipL=0, flipR=0, skipL=0, skipR=0,           
			volInL=1.0, volInR=1.0,     
			
			loopLenL=8.0, loopLenR=8.0,
			
			skipModeL=0, skipModeR=0, 
			stutterRateL=0.1, stutterRateR=0.1,
			stutterChaosL=0, stutterChaosR=0,
			driftAmt=0.005,
			
			preampL=1.0, preampR=1.0, envSlewL=0.05, envSlewR=0.05,
            ampL=1.0, ampR=1.0,
			
			p1f=0.5, p2f=0.6, p3f=0.7, p4f=0.8, p5f=0.9, p6f=1.0,
			p1chaos=0, p2chaos=0, p3chaos=0, p4chaos=0, p5chaos=0, p6chaos=0,
			p1shape=0, p2shape=0, p3shape=0, p4shape=0, p5shape=0, p6shape=0,
			
            globalChaos=0, 
            coco1OutMode=0, coco2OutMode=0, 
            cocoSlewL=0.1, cocoSlewR=0.1,
            
            slew_speed=0.1, slew_amp=0.05, slew_misc=0,
            modeL=0, modeR=0;

			// --- VARS ---
			var dest_gains = NamedControl.kr(\dest_gains, 1!24); 
			
			var mod_speedL_Amts=NamedControl.kr(\mod_speedL_Amts, 0!12); 
			var mod_speedR_Amts=NamedControl.kr(\mod_speedR_Amts, 0!12);
			var mod_flipL_Amts=NamedControl.kr(\mod_flipL_Amts, 0!12); 
			var mod_flipR_Amts=NamedControl.kr(\mod_flipR_Amts, 0!12);
			var mod_skipL_Amts=NamedControl.kr(\mod_skipL_Amts, 0!12); 
			var mod_skipR_Amts=NamedControl.kr(\mod_skipR_Amts, 0!12);
			var mod_ampL_Amts=NamedControl.kr(\mod_ampL_Amts, 0!12); 
			var mod_ampR_Amts=NamedControl.kr(\mod_ampR_Amts, 0!12);
			var mod_fbL_Amts=NamedControl.kr(\mod_fbL_Amts, 0!12); 
			var mod_fbR_Amts=NamedControl.kr(\mod_fbR_Amts, 0!12);
			var mod_filtL_Amts=NamedControl.kr(\mod_filtL_Amts, 0!12); 
			var mod_filtR_Amts=NamedControl.kr(\mod_filtR_Amts, 0!12);
			var mod_recL_Amts=NamedControl.kr(\mod_recL_Amts, 0!12); 
			var mod_recR_Amts=NamedControl.kr(\mod_recR_Amts, 0!12);
			var mod_volL_Amts=NamedControl.kr(\mod_volL_Amts, 0!12); 
			var mod_volR_Amts=NamedControl.kr(\mod_volR_Amts, 0!12);
			var mod_audioInL_Amts=NamedControl.kr(\mod_audioInL_Amts, 0!12); 
			var mod_audioInR_Amts=NamedControl.kr(\mod_audioInR_Amts, 0!12);
			var mod_p1_Amts=NamedControl.kr(\mod_p1_Amts, 0!12); 
			var mod_p2_Amts=NamedControl.kr(\mod_p2_Amts, 0!12);
			var mod_p3_Amts=NamedControl.kr(\mod_p3_Amts, 0!12); 
			var mod_p4_Amts=NamedControl.kr(\mod_p4_Amts, 0!12);
			var mod_p5_Amts=NamedControl.kr(\mod_p5_Amts, 0!12); 
			var mod_p6_Amts=NamedControl.kr(\mod_p6_Amts, 0!12);

			var inputL_sig, inputR_sig, envL, envR, envL_raw, envR_raw;
			var p1, p2, p3, p4, p5, p6, c1, c2, c3, c4, c5, c6; 
			var b_ph1, b_ph2, b_ph3, b_ph4, b_ph5, b_ph6, t1, t2, t3, t4, t5, t6; 
			var out1, out2, out3, out4, out5, out6, sources_sig; 
            var p1c, p2c, p3c, p4c, p5c, p6c;
			
			var raw_mod_flipL, raw_mod_flipR, mod_val_flipL, mod_val_flipR;
			var raw_mod_skipL, raw_mod_skipR, mod_val_skipL, mod_val_skipR;
			var raw_mod_recL, raw_mod_recR, mod_val_recL, mod_val_recR;
			var mod_val_speedL, mod_val_speedR, mod_val_ampL, mod_val_ampR;
			var mod_val_fbL, mod_val_fbR, mod_val_filtL, mod_val_filtR;
			var mod_val_volL, mod_val_volR, mod_val_audioInL, mod_val_audioInR;
			var mod_p1, mod_p2, mod_p3, mod_p4, mod_p5, mod_p6;
			
			var dryL, dryR, finalRateL, finalRateR, ptrL, ptrR, readL, readR, writeL, writeR;
			var gateRecL, gateRecR, noiseL, noiseR, baseSR_L, baseSR_R, interpL, interpR;
			var endL, endR, yellowL, yellowR;
			var driftL, driftR, bleedL, bleedR, baseSpeedL, baseSpeedR;
			var flipLogicL, flipLogicR, flipStateL, flipStateR, recLogicL, recLogicR;
			var feedbackL, feedbackR, osc_trigger; 
			var preampNoiseL, preampNoiseR, feedback_in, fb_petals, fb_yellow;
			var gateSkipL, gateSkipR, freezePosL, freezePosR, rawPtrL, rawPtrR;
			var minTime, maxTime, lowerL, upperL, lowerR, upperR;
			var demandL, demandR, autoTrigL, autoTrigR, finalJumpTrigL, finalJumpTrigR;
			var resetPosL, resetPosR;
            var clean_preampL, clean_preampR;
            var relInL, relInR, atkInL, atkInR; 
            var relCoL, relCoR, atkCoL, atkCoR; 
            var envFbL, envFbR;
            var src11_ar, src12_ar; 
            var fb_src11, fb_src12; 
			var isNot16BitL, isNot16BitR;
			
			// ADPCM state vars
			var adpcmStepL, adpcmPredL, adpcmDiffL, adpcmQuantL, adpcmReconL, adpcmNewStepL, adpcmNewPredL;
			var adpcmStepR, adpcmPredR, adpcmDiffR, adpcmQuantR, adpcmReconR, adpcmNewStepR, adpcmNewPredR;
			var isAdpcmL, isAdpcmR;

			// --- CORE DSP ---
			
            feedback_in = LocalIn.ar(14); 
			fb_petals = feedback_in[0..5].tanh; 
			fb_yellow = feedback_in[6..7]; 
            fb_src11 = feedback_in[8];
            fb_src12 = feedback_in[9];

			preampNoiseL = PinkNoise.ar(((preampL - 6).max(0) * 0.0714).pow(2));
			preampNoiseR = PinkNoise.ar(((preampR - 6).max(0) * 0.0714).pow(2));
			inputL_sig = In.ar(inL); inputR_sig = In.ar(inR);
			
            inputL_sig = HPF.ar(inputL_sig, 20); inputR_sig = HPF.ar(inputR_sig, 20);
			inputL_sig = ((inputL_sig * preampL) + preampNoiseL).tanh; 
			inputR_sig = ((inputR_sig * preampR) + preampNoiseR).tanh;
			
            relInL = envSlewL.linexp(0, 1, 0.05, 2.5); relInR = envSlewR.linexp(0, 1, 0.05, 2.5);
            atkInL = (relInL * 0.1).max(0.002); atkInR = (relInR * 0.1).max(0.002);
			envL_raw = Amplitude.kr(inputL_sig, atkInL, relInL); 
			envR_raw = Amplitude.kr(inputR_sig, atkInR, relInR);
			envL = envL_raw * 2.0; envR = envR_raw * 2.0;

            clean_preampL = inputL_sig; clean_preampR = inputR_sig;

			// Fixed Select to .kr for scalars
			noiseL = PinkNoise.ar(Select.kr(modeL, [0.008, 0.0016, 0.00016, 0.004, 0.002]));
			noiseR = PinkNoise.ar(Select.kr(modeR, [0.008, 0.0016, 0.00016, 0.004, 0.002]));
			
			baseSR_L = Select.kr(modeL, [16000, 31250, 39000, 22000, 14000]);
			baseSR_R = Select.kr(modeR, [16000, 31250, 39000, 22000, 14000]) * 1.002;
            interpL = Select.kr(modeL, [1, 1, 2, 1, 1]);
            interpR = Select.kr(modeR, [1, 1, 2, 1, 1]);
			
			inputL_sig = inputL_sig + (noiseL * 0.5); 
			inputR_sig = inputR_sig + (noiseR * 0.5);

			yellowL = DC.ar(0); yellowR = DC.ar(0);
             
            sources_sig = [fb_petals[0], fb_petals[1], fb_petals[2], fb_petals[3], fb_petals[4], fb_petals[5], K2A.ar(envL), K2A.ar(envR), fb_yellow[0], fb_yellow[1], fb_src11, fb_src12];

            p1c = (p1chaos + globalChaos).clip(0, 1); p2c = (p2chaos + globalChaos).clip(0, 1);
            p3c = (p3chaos + globalChaos).clip(0, 1); p4c = (p4chaos + globalChaos).clip(0, 1);
            p5c = (p5chaos + globalChaos).clip(0, 1); p6c = (p6chaos + globalChaos).clip(0, 1);

			mod_p1=((sources_sig*mod_p1_Amts).sum * dest_gains[14] * 10);
			mod_p2=((sources_sig*mod_p2_Amts).sum * dest_gains[15] * 10);
			mod_p3=((sources_sig*mod_p3_Amts).sum * dest_gains[16] * 10);
			mod_p4=((sources_sig*mod_p4_Amts).sum * dest_gains[17] * 10);
			mod_p5=((sources_sig*mod_p5_Amts).sum * dest_gains[18] * 10);
			mod_p6=((sources_sig*mod_p6_Amts).sum * dest_gains[19] * 10);

			b_ph1 = Phasor.ar(0, (p1f + mod_p1).abs * SampleDur.ir, 0, 1); t1 = Trig1.ar(b_ph1 > 0.05, SampleDur.ir); 
			p1 = ((b_ph1 + (fb_petals[5] * p1c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			b_ph2 = Phasor.ar(0, (p2f + mod_p2).abs * SampleDur.ir, 0, 1); t2 = Trig1.ar(b_ph2 > 0.05, SampleDur.ir); p2 = ((b_ph2 + (p1 * p2c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			b_ph3 = Phasor.ar(0, (p3f + mod_p3).abs * SampleDur.ir, 0, 1); t3 = Trig1.ar(b_ph3 > 0.05, SampleDur.ir); p3 = ((b_ph3 + (p2 * p3c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			b_ph4 = Phasor.ar(0, (p4f + mod_p4).abs * SampleDur.ir, 0, 1); t4 = Trig1.ar(b_ph4 > 0.05, SampleDur.ir); p4 = ((b_ph4 + (p3 * p4c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			b_ph5 = Phasor.ar(0, (p5f + mod_p5).abs * SampleDur.ir, 0, 1); t5 = Trig1.ar(b_ph5 > 0.05, SampleDur.ir); p5 = ((b_ph5 + (p4 * p5c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			b_ph6 = Phasor.ar(0, (p6f + mod_p6).abs * SampleDur.ir, 0, 1); t6 = Trig1.ar(b_ph6 > 0.05, SampleDur.ir); p6 = ((b_ph6 + (p5 * p6c.pow(3) * 4.0)).wrap(0,1) * 2 - 1).abs;
			
			c1=Latch.ar(p6,t1); c2=Latch.ar(p1,t2); c3=Latch.ar(p2,t3);
			c4=Latch.ar(p3,t4); c5=Latch.ar(p4,t5); c6=Latch.ar(p5,t6);
            
            // K2A added for scalar/control rate 'which' with Audio arrays
			out1=Select.ar(K2A.ar(p1shape),[p1,c1]); out2=Select.ar(K2A.ar(p2shape),[p2,c2]); out3=Select.ar(K2A.ar(p3shape),[p3,c3]);
			out4=Select.ar(K2A.ar(p4shape),[p4,c4]); out5=Select.ar(K2A.ar(p5shape),[p5,c5]); out6=Select.ar(K2A.ar(p6shape),[p6,c6]);
			
			driftL = LFDNoise3.ar(0.08, driftAmt); driftR = LFDNoise3.ar(0.08, driftAmt);

			mod_val_speedL=((sources_sig*mod_speedL_Amts).sum * dest_gains[0]).tanh.lag(0.01);
			mod_val_speedR=((sources_sig*mod_speedR_Amts).sum * dest_gains[7]).tanh.lag(0.01);
             
            baseSpeedL = (speedL + mod_val_speedL + driftL).lag(0.01);
			baseSpeedR = (speedR + mod_val_speedR + driftR).lag(0.01);

			raw_mod_flipL = (sources_sig*mod_flipL_Amts).sum * dest_gains[4];
			raw_mod_flipR = (sources_sig*mod_flipR_Amts).sum * dest_gains[11];
			mod_val_flipL = Slew.ar(Schmidt.ar(raw_mod_flipL, 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_flipR = Slew.ar(Schmidt.ar(raw_mod_flipR, 0.6, 0.4), 10000, 20) > 0.01;
            flipLogicL = (flipL + mod_val_flipL).mod(2); flipLogicR = (flipR + mod_val_flipR).mod(2);
			flipStateL = flipLogicL; flipStateR = flipLogicR; // These are AR signals

			finalRateL = Select.ar(flipLogicL > 0.5, [baseSpeedL, baseSpeedL * -1]);
			finalRateR = Select.ar(flipLogicR > 0.5, [baseSpeedR, baseSpeedR * -1]);
			
			endL = (loopLenL.lag(0.1) * 48000).min(BufFrames.kr(bufL));
			endR = (loopLenR.lag(0.1) * 48000).min(BufFrames.kr(bufR));
             
			raw_mod_skipL = (sources_sig*mod_skipL_Amts).sum * dest_gains[5];
			raw_mod_skipR = (sources_sig*mod_skipR_Amts).sum * dest_gains[12];
			mod_val_skipL = Slew.ar(Schmidt.ar(raw_mod_skipL, 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_skipR = Slew.ar(Schmidt.ar(raw_mod_skipR, 0.6, 0.4), 10000, 20) > 0.01;
			
			gateSkipL = ((skipL + mod_val_skipL) > 0.5); gateSkipR = ((skipR + mod_val_skipR) > 0.5);
			minTime = 0.001; maxTime = 0.350;
			lowerL = stutterRateL - (stutterChaosL * (stutterRateL - minTime));
			upperL = stutterRateL + (stutterChaosL * (maxTime - stutterRateL));
			demandL = Dwhite(lowerL, upperL);
			autoTrigL = TDuty.ar(demandL, reset: gateSkipL) * gateSkipL;
			lowerR = stutterRateR - (stutterChaosR * (stutterRateR - minTime));
			upperR = stutterRateR + (stutterChaosR * (maxTime - stutterRateR));
			demandR = Dwhite(lowerR, upperR);
			autoTrigR = TDuty.ar(demandR, reset: gateSkipR) * gateSkipR;
			
			finalJumpTrigL = Select.ar(K2A.ar(skipModeL), [Changed.ar(gateSkipL), autoTrigL]);
			finalJumpTrigR = Select.ar(K2A.ar(skipModeR), [Changed.ar(gateSkipR), autoTrigR]);
			
			rawPtrL = fb_yellow[0] * endL; rawPtrR = fb_yellow[1] * endR;
			freezePosL = Latch.ar(rawPtrL, gateSkipL); freezePosR = Latch.ar(rawPtrR, gateSkipR);
			
			resetPosL = Select.ar(K2A.ar(skipModeL), [TRand.ar(0, endL, finalJumpTrigL), freezePosL]);
			resetPosR = Select.ar(K2A.ar(skipModeR), [TRand.ar(0, endR, finalJumpTrigR), freezePosR]);
			
			ptrL = Phasor.ar(finalJumpTrigL, finalRateL * BufRateScale.kr(bufL), 0, endL, resetPosL);
			ptrR = Phasor.ar(finalJumpTrigR, finalRateR * BufRateScale.kr(bufR), 0, endR, resetPosR);
			
			yellowL = (ptrL / endL.max(1)); yellowR = (ptrR / endR.max(1));
			
			bleedL = SinOsc.ar((baseSR_L * finalRateL.abs).clip(20, 20000)) * Select.kr(modeL, [0.0025, 0.001, 0, 0.002, 0.003]);
			bleedR = SinOsc.ar((baseSR_R * finalRateR.abs).clip(20, 20000)) * Select.kr(modeR, [0.0025, 0.001, 0, 0.002, 0.003]);

			readL = BufRd.ar(1, bufL, ptrL, loop:1, interpolation: interpL);
			readR = BufRd.ar(1, bufR, ptrR, loop:1, interpolation: interpR);

			readL = Select.ar(K2A.ar(modeL), [
				readL,  
				readL,  
				readL,  
				readL.sign * (((2.pow(readL.abs * 128)) - 1) / 255),  
				adpcmReconL                                               
			]);
			readR = Select.ar(K2A.ar(modeR), [
				readR,
				readR,
				readR,
				readR.sign * (((2.pow(readR.abs * 128)) - 1) / 255),
				adpcmReconR
			]);
			
            readL = readL + (noiseL * 0.5); 
            readR = readR + (noiseR * 0.5);

            relCoL = cocoSlewL.linexp(0, 1, 0.05, 2.5); relCoR = cocoSlewR.linexp(0, 1, 0.05, 2.5);
            atkCoL = (relCoL * 0.1).max(0.002); atkCoR = (relCoR * 0.1).max(0.002);
            envFbL = Amplitude.kr(LeakDC.ar(readL), atkCoL, relCoL) * 2.0; 
            envFbR = Amplitude.kr(LeakDC.ar(readR), atkCoR, relCoR) * 2.0;
            src11_ar = Select.ar(K2A.ar(coco1OutMode), [K2A.ar(envFbL), readL]);
            src12_ar = Select.ar(K2A.ar(coco2OutMode), [K2A.ar(envFbR), readR]);
            
			mod_val_ampL=((sources_sig*mod_ampL_Amts).sum * dest_gains[1]).tanh.lag(slew_amp);
			mod_val_ampR=((sources_sig*mod_ampR_Amts).sum * dest_gains[8]).tanh.lag(slew_amp);
			mod_val_fbL=((sources_sig*mod_fbL_Amts).sum * dest_gains[2]).tanh.lag(slew_amp);
			mod_val_fbR=((sources_sig*mod_fbR_Amts).sum * dest_gains[9]).tanh.lag(slew_amp);
			mod_val_filtL=((sources_sig*mod_filtL_Amts).sum * dest_gains[3]).tanh.lag(slew_misc);
			mod_val_filtR=((sources_sig*mod_filtR_Amts).sum * dest_gains[10]).tanh.lag(slew_misc);
			mod_val_volL=((sources_sig*mod_volL_Amts).sum * dest_gains[20]).tanh.lag(slew_amp);
			mod_val_volR=((sources_sig*mod_volR_Amts).sum * dest_gains[21]).tanh.lag(slew_amp);
			mod_val_audioInL = LeakDC.ar((sources_sig*mod_audioInL_Amts).sum);
			mod_val_audioInL = (mod_val_audioInL * dest_gains[22] * 4.0).tanh;
			mod_val_audioInR = LeakDC.ar((sources_sig*mod_audioInR_Amts).sum);
			mod_val_audioInR = (mod_val_audioInR * dest_gains[23] * 4.0).tanh;
             
			raw_mod_recL = (sources_sig*mod_recL_Amts).sum * dest_gains[6];
			raw_mod_recR = (sources_sig*mod_recR_Amts).sum * dest_gains[13];
			mod_val_recL = Slew.ar(Schmidt.ar(raw_mod_recL, 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_recR = Slew.ar(Schmidt.ar(raw_mod_recR, 0.6, 0.4), 10000, 20) > 0.01;

			recLogicL = (recL + mod_val_recL).mod(2); recLogicR = (recR + mod_val_recR).mod(2);
			gateRecL = Select.ar(recLogicL > 0.5, [DC.ar(0), DC.ar(1)]);
			gateRecR = Select.ar(recLogicR > 0.5, [DC.ar(0), DC.ar(1)]);

			dryL = inputL_sig * (volInL + mod_val_ampL).clip(0, 2);
			dryR = inputR_sig * (volInR + mod_val_ampR).clip(0, 2);

			feedbackL = readL * (fbL + mod_val_fbL).clip(0, 1.2) * 1.15;
			feedbackR = readR * (fbR + mod_val_fbR).clip(0, 1.2) * 1.15;
			feedbackL = LPF.ar(feedbackL, Select.kr(modeL, [7000, 12800, 18000, 10000, 6500])).softclip;
			feedbackR = LPF.ar(feedbackR, Select.kr(modeR, [7000, 12800, 18000, 10000, 6500]) * 1.04).softclip;
			
			writeL = ((dryL) + mod_val_audioInL) * gateRecL + (feedbackL);
			writeR = ((dryR) + mod_val_audioInR) * gateRecR + (feedbackR);
			
			writeL = Select.ar(K2A.ar(modeL), [
				writeL.round(0.5**8),  
				writeL.round(0.5**12),  
				writeL.round(0.5**16),  
				writeL.sign * ((log(1 + (255 * writeL.abs)) / log(256)).round(1/128)),  
				adpcmQuantL / 7          
			]);
			writeR = Select.ar(K2A.ar(modeR), [
				writeR.round(0.5**8),
				writeR.round(0.5**12),
				writeR.round(0.5**16),
				writeR.sign * ((log(1 + (255 * writeR.abs)) / log(256)).round(1/128)),
				adpcmQuantR / 7
			]);
			
            isNot16BitL = (modeL < 1.5) + (modeL > 2.5);
            isNot16BitR = (modeR < 1.5) + (modeR > 2.5);

			writeL = Select.ar(K2A.ar(isNot16BitL), [writeL, Latch.ar(writeL, Impulse.ar((baseSR_L * finalRateL.abs).clip(100, 48000) * (1 + WhiteNoise.ar(Select.kr(modeL, [0.02, 0.004, 0.001, 0.015, 0.01])))))]);
			writeR = Select.ar(K2A.ar(isNot16BitR), [writeR, Latch.ar(writeR, Impulse.ar((baseSR_R * finalRateR.abs).clip(100, 48000) * (1 + WhiteNoise.ar(Select.kr(modeR, [0.02, 0.004, 0.001, 0.015, 0.01])))))]);
			
			isAdpcmL = (modeL > 3.5);
			isAdpcmR = (modeR > 3.5);

			// L channel ADPCM 
			adpcmStepL = (feedback_in[10] * isAdpcmL).max(1);
			adpcmPredL = feedback_in[11] * isAdpcmL;
			adpcmDiffL = writeL - adpcmPredL;
			adpcmQuantL = (adpcmDiffL / (adpcmStepL * 0.00143)).clip(-7, 7).round(1);
			adpcmReconL = adpcmPredL + (adpcmQuantL * adpcmStepL * 0.00143);
			adpcmNewStepL = (adpcmStepL * Select.ar(adpcmQuantL + 7,
				[DC.ar(0.9), DC.ar(0.9), DC.ar(0.9), DC.ar(0.9), DC.ar(0.95), DC.ar(0.95), DC.ar(1.0), DC.ar(1.0), DC.ar(1.0), DC.ar(1.05), DC.ar(1.05), DC.ar(1.1), DC.ar(1.15), DC.ar(1.2), DC.ar(1.3), DC.ar(1.5)])).clip(1, 500);
			adpcmNewPredL = adpcmReconL.clip(-1, 1);

			// R channel ADPCM 
			adpcmStepR = (feedback_in[12] * isAdpcmR).max(1);
			adpcmPredR = feedback_in[13] * isAdpcmR;
			adpcmDiffR = writeR - adpcmPredR;
			adpcmQuantR = (adpcmDiffR / (adpcmStepR * 0.00143)).clip(-7, 7).round(1);
			adpcmReconR = adpcmPredR + (adpcmQuantR * adpcmStepR * 0.00143);
			adpcmNewStepR = (adpcmStepR * Select.ar(adpcmQuantR + 7,
				[DC.ar(0.9), DC.ar(0.9), DC.ar(0.9), DC.ar(0.9), DC.ar(0.95), DC.ar(0.95), DC.ar(1.0), DC.ar(1.0), DC.ar(1.0), DC.ar(1.05), DC.ar(1.05), DC.ar(1.1), DC.ar(1.15), DC.ar(1.2), DC.ar(1.3), DC.ar(1.5)])).clip(1, 500);
			adpcmNewPredR = adpcmReconR.clip(-1, 1);

			BufWr.ar(writeL, bufL, ptrL); BufWr.ar(writeR, bufR, ptrR);

			LocalOut.ar([p1, p2, p3, p4, p5, p6, yellowL, yellowR, src11_ar, src12_ar,
				adpcmNewStepL, adpcmNewPredL, adpcmNewStepR, adpcmNewPredR]);
				
			osc_trigger = Impulse.kr(30);
            
            // Fix SendReply to correctly A2K all internal Audio Signals
			SendReply.kr(osc_trigger, '/update', [
                A2K.kr(ptrL/endL.max(1)), A2K.kr(ptrR/endR.max(1)), 
                A2K.kr(gateRecL), A2K.kr(gateRecR), 
                A2K.kr(flipStateL), A2K.kr(flipStateR), 
                A2K.kr((skipL + mod_val_skipL).clip(0,1)), A2K.kr((skipR + mod_val_skipR).clip(0,1)), 
                A2K.kr(out1), A2K.kr(out2), A2K.kr(out3), A2K.kr(out4), A2K.kr(out5), A2K.kr(out6), 
                envL, envR, 
                A2K.kr(yellowL), A2K.kr(yellowR), 
                A2K.kr(finalRateL), A2K.kr(finalRateR), 
                A2K.kr(Amplitude.ar(readL*ampL)), A2K.kr(Amplitude.ar(readR*ampR)), 
                A2K.kr(src11_ar), A2K.kr(src12_ar)
            ]);

            Out.ar(bus_tape_out, [readL, readR]);
            Out.ar(bus_mon_out, [clean_preampL + mod_val_audioInL, clean_preampR + mod_val_audioInR]);
            Out.ar(bus_bleed_out, [bleedL, bleedR]); 
            Out.kr(bus_mvol_out, [mod_val_volL, mod_val_volR]);
            Out.kr(bus_mfilt_out, [mod_val_filtL, mod_val_filtR]);

		}).add;

		// -----------------------------------------------------------
		// SYNTH 2: OUT (Mix, Filter, Amp)
		// -----------------------------------------------------------
		SynthDef(\NcocoOut, {
            arg out, bus_tape_in, bus_mon_in, bus_bleed_in,
            bus_mvol_in, bus_mfilt_in,
            filtL=0, filtR=0, ampL=1.0, ampR=1.0, panL= -0.5, panR=0.5, monitorLevel=0,
            bleedPost=0, 
            djFilterType=0, 
            dfm1Gain=0.32; 

            var readL, readR, monL, monR, bleedL, bleedR;
            var mod_vol, mod_filt;
            var mod_val_volL, mod_val_volR, mod_val_filtL, mod_val_filtR;
            var totalFiltL, totalFiltR;
            var lpfFreqL, hpfFreqL, lpfFreqR, hpfFreqR;
            var classicL, classicR, dfm1L, dfm1R;
            var finalVolL, finalVolR;
            var master_out;
            var tape_in, mon_in, bleed_in;
            var sigL, sigR;

            tape_in = In.ar(bus_tape_in, 2);
            readL = tape_in[0]; readR = tape_in[1];
            
            mon_in = In.ar(bus_mon_in, 2);
            monL = mon_in[0]; monR = mon_in[1];
            
            bleed_in = In.ar(bus_bleed_in, 2);
            bleedL = bleed_in[0]; bleedR = bleed_in[1];

            mod_vol = In.kr(bus_mvol_in, 2);
            mod_val_volL = mod_vol[0]; mod_val_volR = mod_vol[1];

            mod_filt = In.kr(bus_mfilt_in, 2);
            mod_val_filtL = mod_filt[0]; mod_val_filtR = mod_filt[1];

			totalFiltL = (filtL + mod_val_filtL).clip(-1, 1);
			totalFiltR = (filtR + mod_val_filtR).clip(-1, 1);

            sigL = readL + (bleedL * (1.0 - bleedPost));
            sigR = readR + (bleedR * (1.0 - bleedPost));

            lpfFreqL = (totalFiltL.min(0)+1).linexp(0,1,100,20000);
            hpfFreqL = totalFiltL.max(0).linexp(0,1,20,15000);
            lpfFreqR = (totalFiltR.min(0)+1).linexp(0,1,100,20000);
            hpfFreqR = totalFiltR.max(0).linexp(0,1,20,15000);

            classicL = HPF.ar(LPF.ar(sigL, lpfFreqL), hpfFreqL);
            classicR = HPF.ar(LPF.ar(sigR, lpfFreqR), hpfFreqR);

            dfm1L = DFM1.ar(sigL * 0.7, lpfFreqL, 0, 1.0, 0, 0.0003);  
            dfm1L = DFM1.ar(dfm1L, lpfFreqL, 0, 1.0, 0, 0.0003);       
            dfm1L = HPF.ar(dfm1L, hpfFreqL) * dfm1Gain;                  
            
            dfm1R = DFM1.ar(sigR * 0.7, lpfFreqR, 0, 1.0, 0, 0.0003);  
            dfm1R = DFM1.ar(dfm1R, lpfFreqR, 0, 1.0, 0, 0.0003);       
            dfm1R = HPF.ar(dfm1R, hpfFreqR) * dfm1Gain;                  

            // Guarded DJ filter topology with safe rate bridging 
			sigL = Select.ar(K2A.ar(totalFiltL.abs < 0.05), [
				Select.ar(K2A.ar(djFilterType), [classicL, dfm1L]),
				sigL
			]);
			sigR = Select.ar(K2A.ar(totalFiltR.abs < 0.05), [
				Select.ar(K2A.ar(djFilterType), [classicR, dfm1R]),
				sigR
			]);
            
            sigL = sigL + (bleedL * bleedPost);
            sigR = sigR + (bleedR * bleedPost);
            
            finalVolL = (ampL + mod_val_volL).clip(0, 2); 
            finalVolR = (ampR + mod_val_volR).clip(0, 2);
            
			master_out = Pan2.ar(sigL*finalVolL, panL) + Pan2.ar(sigR*finalVolR, panR);
            
            Out.ar(out, Limiter.ar(master_out + [monL * monitorLevel, monR * monitorLevel], 0.95)); 
        }).add;

		// BARRIER 2
		context.server.sync;
		
		synth_core = Synth.new(\NcocoCore, [
            \bufL, bufL, \bufR, bufR, \inL, context.in_b[0].index, \inR, context.in_b[1].index,
            \bus_tape_out, b_tape.index, \bus_mon_out, b_mon.index,
            \bus_bleed_out, b_bleed.index, 
            \bus_mvol_out, b_mod_vol.index, \bus_mfilt_out, b_mod_filt.index,
            \ampL, 1.0, \ampR, 1.0 
        ], context.xg, \addToHead);
        
        synth_out = Synth.new(\NcocoOut, [
            \out, context.out_b.index,
            \bus_tape_in, b_tape.index, \bus_mon_in, b_mon.index,
            \bus_bleed_in, b_bleed.index, 
            \bus_mvol_in, b_mod_vol.index, \bus_mfilt_in, b_mod_filt.index
        ], context.xg, \addToTail);

		osc_responder = OSCFunc({ |msg| NetAddr("127.0.0.1", 10111).sendMsg("/update", *msg.drop(3)); }, '/update', nil).fix;

		this.addCommand("clear_tape", "i", { |msg| var b=if(msg[1]==0,{bufL},{bufR}); b.zero; });
		this.addCommand("dest_gains", "ffffffffffffffffffffffff", { |msg| synth_core.setn(\dest_gains, msg.drop(1)) });
		
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

        this.addCommand("coco1_out_mode", "i", { |msg| synth_core.set(\coco1OutMode, msg[1]) });
        this.addCommand("coco2_out_mode", "i", { |msg| synth_core.set(\coco2OutMode, msg[1]) });
        this.addCommand("global_chaos", "f", { |msg| synth_core.set(\globalChaos, msg[1]) });
        this.addCommand("cocoSlewL", "f", { |msg| synth_core.set(\cocoSlewL, msg[1]) });
        this.addCommand("cocoSlewR", "f", { |msg| synth_core.set(\cocoSlewR, msg[1]) });
		this.addCommand("skipModeL", "i", { |msg| synth_core.set(\skipModeL, msg[1]) });
		this.addCommand("skipModeR", "i", { |msg| synth_core.set(\skipModeR, msg[1]) });
		this.addCommand("stutterRateL", "f", { |msg| synth_core.set(\stutterRateL, msg[1]) });
		this.addCommand("stutterRateR", "f", { |msg| synth_core.set(\stutterRateR, msg[1]) });
		this.addCommand("stutterChaosL", "f", { |msg| synth_core.set(\stutterChaosL, msg[1]) });
		this.addCommand("stutterChaosR", "f", { |msg| synth_core.set(\stutterChaosR, msg[1]) });
		this.addCommand("driftAmt", "f", { |msg| synth_core.set(\driftAmt, msg[1]) });
        this.addCommand("loopLenL", "f", { |msg| synth_core.set(\loopLenL, msg[1]) });
        this.addCommand("loopLenR", "f", { |msg| synth_core.set(\loopLenR, msg[1]) });
		this.addCommand("speedL", "f", { |msg| synth_core.set(\speedL, msg[1]) });
		this.addCommand("speedR", "f", { |msg| synth_core.set(\speedR, msg[1]) });
		this.addCommand("fbL", "f", { |msg| synth_core.set(\fbL, msg[1]) });
		this.addCommand("fbR", "f", { |msg| synth_core.set(\fbR, msg[1]) });
		this.addCommand("volInL", "f", { |msg| synth_core.set(\volInL, msg[1]) });
		this.addCommand("volInR", "f", { |msg| synth_core.set(\volInR, msg[1]) });
		this.addCommand("recL", "i", { |msg| synth_core.set(\recL, msg[1]) });
		this.addCommand("recR", "i", { |msg| synth_core.set(\recR, msg[1]) });
		this.addCommand("flipL", "i", { |msg| synth_core.set(\flipL, msg[1]) });
		this.addCommand("flipR", "i", { |msg| synth_core.set(\flipR, msg[1]) });
		this.addCommand("skipL", "i", { |msg| synth_core.set(\skipL, msg[1]) });
		this.addCommand("skipR", "i", { |msg| synth_core.set(\skipR, msg[1]) });
		this.addCommand("modeL", "f", { |msg| synth_core.set(\modeL, msg[1]) });  
		this.addCommand("modeR", "f", { |msg| synth_core.set(\modeR, msg[1]) });  
		this.addCommand("slew_speed", "f", { |msg| synth_core.set(\slew_speed, msg[1]) });
		this.addCommand("preampL", "f", { |msg| synth_core.set(\preampL, msg[1]) });
		this.addCommand("preampR", "f", { |msg| synth_core.set(\preampR, msg[1]) });
		this.addCommand("envSlewL", "f", { |msg| synth_core.set(\envSlewL, msg[1]) });
		this.addCommand("envSlewR", "f", { |msg| synth_core.set(\envSlewR, msg[1]) });

		this.addCommand("p1f", "f", { |msg| synth_core.set(\p1f, msg[1]) });
		this.addCommand("p2f", "f", { |msg| synth_core.set(\p2f, msg[1]) });
		this.addCommand("p3f", "f", { |msg| synth_core.set(\p3f, msg[1]) });
		this.addCommand("p4f", "f", { |msg| synth_core.set(\p4f, msg[1]) });
		this.addCommand("p5f", "f", { |msg| synth_core.set(\p5f, msg[1]) });
		this.addCommand("p6f", "f", { |msg| synth_core.set(\p6f, msg[1]) });
		this.addCommand("p1chaos", "f", { |msg| synth_core.set(\p1chaos, msg[1]) });
		this.addCommand("p2chaos", "f", { |msg| synth_core.set(\p2chaos, msg[1]) });
		this.addCommand("p3chaos", "f", { |msg| synth_core.set(\p3chaos, msg[1]) });
		this.addCommand("p4chaos", "f", { |msg| synth_core.set(\p4chaos, msg[1]) });
		this.addCommand("p5chaos", "f", { |msg| synth_core.set(\p5chaos, msg[1]) });
		this.addCommand("p6chaos", "f", { |msg| synth_core.set(\p6chaos, msg[1]) });
		this.addCommand("p1shape", "f", { |msg| synth_core.set(\p1shape, msg[1]) });
		this.addCommand("p2shape", "f", { |msg| synth_core.set(\p2shape, msg[1]) });
		this.addCommand("p3shape", "f", { |msg| synth_core.set(\p3shape, msg[1]) });
		this.addCommand("p4shape", "f", { |msg| synth_core.set(\p4shape, msg[1]) });
		this.addCommand("p5shape", "f", { |msg| synth_core.set(\p5shape, msg[1]) });
		this.addCommand("p6shape", "f", { |msg| synth_core.set(\p6shape, msg[1]) });

		this.addCommand("filtL", "f", { |msg| synth_out.set(\filtL, msg[1]) });
		this.addCommand("filtR", "f", { |msg| synth_out.set(\filtR, msg[1]) });
		this.addCommand("panL", "f", { |msg| synth_out.set(\panL, msg[1]) });
		this.addCommand("panR", "f", { |msg| synth_out.set(\panR, msg[1]) });
		this.addCommand("monitorLevel", "f", { |msg| synth_out.set(\monitorLevel, msg[1]) });
        this.addCommand("bleedPost", "f", { |msg| synth_out.set(\bleedPost, msg[1]) });
        this.addCommand("dj_filter_type", "f", { |msg| synth_out.set(\djFilterType, msg[1]) }); 
        this.addCommand("dj_filter_gain", "f", { |msg| synth_out.set(\dfm1Gain, msg[1]) }); 

        this.addCommand("ampL", "f", { |msg| 
            synth_core.set(\ampL, msg[1]); 
            synth_out.set(\ampL, msg[1]); 
        });
        this.addCommand("ampR", "f", { |msg| 
            synth_core.set(\ampR, msg[1]); 
            synth_out.set(\ampR, msg[1]); 
        });

		this.addCommand("mod_speedL", "ffffffffffff", { |msg| synth_core.setn(\mod_speedL_Amts, msg.drop(1)) });
		this.addCommand("mod_speedR", "ffffffffffff", { |msg| synth_core.setn(\mod_speedR_Amts, msg.drop(1)) });
		this.addCommand("mod_flipL", "ffffffffffff", { |msg| synth_core.setn(\mod_flipL_Amts, msg.drop(1)) });
		this.addCommand("mod_flipR", "ffffffffffff", { |msg| synth_core.setn(\mod_flipR_Amts, msg.drop(1)) });
		this.addCommand("mod_skipL", "ffffffffffff", { |msg| synth_core.setn(\mod_skipL_Amts, msg.drop(1)) });
		this.addCommand("mod_skipR", "ffffffffffff", { |msg| synth_core.setn(\mod_skipR_Amts, msg.drop(1)) });
		this.addCommand("mod_ampL", "ffffffffffff", { |msg| synth_core.setn(\mod_ampL_Amts, msg.drop(1)) });
		this.addCommand("mod_ampR", "ffffffffffff", { |msg| synth_core.setn(\mod_ampR_Amts, msg.drop(1)) });
		this.addCommand("mod_fbL", "ffffffffffff", { |msg| synth_core.setn(\mod_fbL_Amts, msg.drop(1)) });
		this.addCommand("mod_fbR", "ffffffffffff", { |msg| synth_core.setn(\mod_fbR_Amts, msg.drop(1)) });
		this.addCommand("mod_filtL", "ffffffffffff", { |msg| synth_core.setn(\mod_filtL_Amts, msg.drop(1)) });
		this.addCommand("mod_filtR", "ffffffffffff", { |msg| synth_core.setn(\mod_filtR_Amts, msg.drop(1)) });
		this.addCommand("mod_recL", "ffffffffffff", { |msg| synth_core.setn(\mod_recL_Amts, msg.drop(1)) });
		this.addCommand("mod_recR", "ffffffffffff", { |msg| synth_core.setn(\mod_recR_Amts, msg.drop(1)) });
		this.addCommand("mod_volL", "ffffffffffff", { |msg| synth_core.setn(\mod_volL_Amts, msg.drop(1)) });
		this.addCommand("mod_volR", "ffffffffffff", { |msg| synth_core.setn(\mod_volR_Amts, msg.drop(1)) });
		this.addCommand("mod_p1", "ffffffffffff", { |msg| synth_core.setn(\mod_p1_Amts, msg.drop(1)) });
		this.addCommand("mod_p2", "ffffffffffff", { |msg| synth_core.setn(\mod_p2_Amts, msg.drop(1)) });
		this.addCommand("mod_p3", "ffffffffffff", { |msg| synth_core.setn(\mod_p3_Amts, msg.drop(1)) });
		this.addCommand("mod_p4", "ffffffffffff", { |msg| synth_core.setn(\mod_p4_Amts, msg.drop(1)) });
		this.addCommand("mod_p5", "ffffffffffff", { |msg| synth_core.setn(\mod_p5_Amts, msg.drop(1)) });
		this.addCommand("mod_p6", "ffffffffffff", { |msg| synth_core.setn(\mod_p6_Amts, msg.drop(1)) });
		this.addCommand("mod_audioInL", "ffffffffffff", { |msg| synth_core.setn(\mod_audioInL_Amts, msg.drop(1)) });
		this.addCommand("mod_audioInR", "ffffffffffff", { |msg| synth_core.setn(\mod_audioInR_Amts, msg.drop(1)) });
	}

	free { 
        osc_responder.free; 
        synth_core.free; 
        synth_out.free; 
        bufL.free; bufR.free; 
        b_tape.free; b_mon.free; b_mod_vol.free; b_mod_filt.free; 
        b_bleed.free; 
    }
}
