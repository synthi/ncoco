// Engine_Ncoco.sc v4003-HiRes
// CHANGELOG v4003-HiRes:
// 1. HI-RES MODULATION: Upgraded Envelope Followers (Amplitude) and Drift LFOs (LFDNoise3) from Control Rate (.kr) to Audio Rate (.ar).
//    - Result: Matrix modulations and tape speed changes are now sample-accurate (no zipper noise).
// 2. CLEAN MONITOR: Monitor signal is tapped immediately after Preamp/Saturation but BEFORE Digital Bit-Noise addition.
// 3. STEREO TOPOLOGY: Replaced Balance2 with Pan2.ar for independent Equal Power panning (fixes Loop vs Input volume discrepancy).
// 4. SAFETY: Added .max(1) to yellowL/R calculation to prevent Division by Zero (NaN) on buffer initialization.

Engine_Ncoco : CroneEngine {
	var <synth;
	var <bufL, <bufR;
	var <osc_responder; 
	var <norns_addr;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
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
			dolbyL=0, dolbyR=0, 
            loopLenL=8.0, loopLenR=8.0,
			
			skipModeL=0, skipModeR=0, 
			stutterRateL=0.1, stutterRateR=0.1,
			stutterChaosL=0, stutterChaosR=0,
			driftAmt=0.005,
			
			preampL=1.0, preampR=1.0, envSlewL=0.05, envSlewR=0.05,
			dolbyBoostL=0, dolbyBoostR=0,
			monitorLevel=0,

			p1f=0.5, p2f=0.6, p3f=0.7, p4f=0.8, p5f=0.9, p6f=1.0,
			p1chaos=0, p2chaos=0, p3chaos=0, p4chaos=0, p5chaos=0, p6chaos=0,
			p1shape=0, p2shape=0, p3shape=0, p4shape=0, p5shape=0, p6shape=0,
			
			slew_speed=0.1, slew_amp=0.05, slew_misc=0;

			// --- VARS DEFINITION ---
			var dest_gains;
			var mod_speedL_Amts, mod_speedR_Amts, mod_flipL_Amts, mod_flipR_Amts;
			var mod_skipL_Amts, mod_skipR_Amts, mod_ampL_Amts, mod_ampR_Amts;
			var mod_fbL_Amts, mod_fbR_Amts, mod_filtL_Amts, mod_filtR_Amts;
			var mod_recL_Amts, mod_recR_Amts, mod_volL_Amts, mod_volR_Amts; 
			var mod_audioInL_Amts, mod_audioInR_Amts;
			var mod_p1_Amts, mod_p2_Amts, mod_p3_Amts, mod_p4_Amts, mod_p5_Amts, mod_p6_Amts;

			var inputL_sig, inputR_sig, envL, envR, envL_raw, envR_raw;
			var p1, p2, p3, p4, p5, p6, c1, c2, c3, c4, c5, c6; 
			var b_ph1, b_ph2, b_ph3, b_ph4, b_ph5, b_ph6, t1, t2, t3, t4, t5, t6; 
			var out1, out2, out3, out4, out5, out6, sources_sig; 
			
			var raw_mod_flipL, raw_mod_flipR, mod_val_flipL, mod_val_flipR;
			var raw_mod_skipL, raw_mod_skipR, mod_val_skipL, mod_val_skipR;
			var raw_mod_recL, raw_mod_recR, mod_val_recL, mod_val_recR;
			var mod_val_speedL, mod_val_speedR, mod_val_ampL, mod_val_ampR;
			var mod_val_fbL, mod_val_fbR, mod_val_filtL, mod_val_filtR;
			var mod_val_volL, mod_val_volR, mod_val_audioInL, mod_val_audioInR;
			var mod_p1, mod_p2, mod_p3, mod_p4, mod_p5, mod_p6;
			
			var dryL, dryR, finalRateL, finalRateR, ptrL, ptrR, readL, readR, writeL, writeR;
			var gateRecL, gateRecR, noiseL, noiseR, baseSR_L, baseSR_R, interpL, interpR;
			var is8L, is12L, is8R, is12R, fixedFiltFreq;
			var endL, endR, yellowL, yellowR, totalFiltL, totalFiltR;
			
			var driftL, driftR, bleedL, bleedR, baseSpeedL, baseSpeedR;
			var flipLogicL, flipLogicR, flipStateL, flipStateR, recLogicL, recLogicR;
			var feedbackL, feedbackR, osc_trigger, finalVolL, finalVolR, master_out; 
			var monitorL, monitorR, preampNoiseL, preampNoiseR, feedback_in, fb_petals, fb_yellow;
			
			var gateSkipL, gateSkipR, freezePosL, freezePosR, rawPtrL, rawPtrR;
			var minTime, maxTime, lowerL, upperL, lowerR, upperR;
			var demandL, demandR, autoTrigL, autoTrigR, finalJumpTrigL, finalJumpTrigR;
			var resetPosL, resetPosR, jitterAmountL, jitterAmountR;

            // NEW VARS for Clean Monitor Tap
            var clean_preampL, clean_preampR;

			// --- DSP ---
			dest_gains = NamedControl.kr(\dest_gains, 1!24); 
			feedback_in = LocalIn.ar(8);
			fb_petals = feedback_in[0..5].tanh; 
			fb_yellow = feedback_in[6..7]; 

            // INPUT STAGE
			preampNoiseL = PinkNoise.ar(((preampL - 6).max(0) * 0.0714).pow(2));
			preampNoiseR = PinkNoise.ar(((preampR - 6).max(0) * 0.0714).pow(2));
			inputL_sig = In.ar(inL); inputR_sig = In.ar(inR);
			
            // Protection HPF
            inputL_sig = HPF.ar(inputL_sig, 20); inputR_sig = HPF.ar(inputR_sig, 20);
            
			inputL_sig = ((inputL_sig * preampL) + preampNoiseL).tanh; 
			inputR_sig = ((inputR_sig * preampR) + preampNoiseR).tanh;
			
            // HI-RES UPDATE: Amplitude.ar instead of .kr for fast envelope following
			envL_raw = Amplitude.ar(inputL_sig, 0.01, 0.08); 
			envR_raw = Amplitude.ar(inputR_sig, 0.01, 0.08);
			envL = envL_raw * 2.0; envR = envR_raw * 2.0;

            // MONITOR TAP: Capture signal before digital noise
            clean_preampL = inputL_sig;
            clean_preampR = inputR_sig;

            // DIGITAL LO-FI STAGE
			is8L = bitDepthL < 10; is12L = (bitDepthL >= 10) * (bitDepthL < 14);
			is8R = bitDepthR < 10; is12R = (bitDepthR >= 10) * (bitDepthR < 14);
			noiseL = PinkNoise.ar((is8L * 0.008) + (is12L * 0.00025));
			noiseR = PinkNoise.ar((is8R * 0.008) + (is12R * 0.00025));
			baseSR_L = (is8L * 16000) + (is12L * 24000) + ((1 - is8L - is12L) * 32000);
			baseSR_R = (is8R * 16000) + (is12R * 24000) + ((1 - is8R - is12R) * 32000);
			fixedFiltFreq = (is8L * 7000) + (is12L * 11000) + ((1 - is8L - is12L) * 16000);
			interpL = 1 + (1 - is8L); interpR = 1 + (1 - is8R);
			
            // Add noise to the recording path
            inputL_sig = inputL_sig + noiseL; inputR_sig = inputR_sig + noiseR;

			yellowL = DC.ar(0); yellowR = DC.ar(0);
			
			sources_sig = [fb_petals[0], fb_petals[1], fb_petals[2], fb_petals[3], fb_petals[4], fb_petals[5], K2A.ar(envL), K2A.ar(envR), fb_yellow[0], fb_yellow[1]];
			
			mod_p1_Amts=NamedControl.kr(\mod_p1_Amts, 0!10); mod_p2_Amts=NamedControl.kr(\mod_p2_Amts, 0!10);
			mod_p3_Amts=NamedControl.kr(\mod_p3_Amts, 0!10); mod_p4_Amts=NamedControl.kr(\mod_p4_Amts, 0!10);
			mod_p5_Amts=NamedControl.kr(\mod_p5_Amts, 0!10); mod_p6_Amts=NamedControl.kr(\mod_p6_Amts, 0!10);

            // Matrix sums will be Audio Rate because sources_sig is now Audio Rate
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
			
			sources_sig = [out1, out2, out3, out4, out5, out6, K2A.ar(envL), K2A.ar(envR), fb_yellow[0], fb_yellow[1]];

            // HI-RES UPDATE: LFDNoise3.ar instead of .kr for smoother tape drift
			driftL = LFDNoise3.ar(0.08, driftAmt); driftR = LFDNoise3.ar(0.08, driftAmt);

			mod_speedL_Amts=NamedControl.kr(\mod_speedL_Amts, 0!10); mod_speedR_Amts=NamedControl.kr(\mod_speedR_Amts, 0!10);
			mod_val_speedL=((sources_sig*mod_speedL_Amts).sum * dest_gains[0]).tanh.lag(0.01);
			mod_val_speedR=((sources_sig*mod_speedR_Amts).sum * dest_gains[7]).tanh.lag(0.01);
			
			mod_ampL_Amts=NamedControl.kr(\mod_ampL_Amts, 0!10); mod_ampR_Amts=NamedControl.kr(\mod_ampR_Amts, 0!10);
			mod_val_ampL=((sources_sig*mod_ampL_Amts).sum * dest_gains[1]).tanh.lag(slew_amp);
			mod_val_ampR=((sources_sig*mod_ampR_Amts).sum * dest_gains[8]).tanh.lag(slew_amp);

			mod_fbL_Amts=NamedControl.kr(\mod_fbL_Amts, 0!10); mod_fbR_Amts=NamedControl.kr(\mod_fbR_Amts, 0!10);
			mod_val_fbL=((sources_sig*mod_fbL_Amts).sum * dest_gains[2]).tanh.lag(slew_amp);
			mod_val_fbR=((sources_sig*mod_fbR_Amts).sum * dest_gains[9]).tanh.lag(slew_amp);

			mod_filtL_Amts=NamedControl.kr(\mod_filtL_Amts, 0!10); mod_filtR_Amts=NamedControl.kr(\mod_filtR_Amts, 0!10);
			mod_val_filtL=((sources_sig*mod_filtL_Amts).sum * dest_gains[3]).tanh.lag(slew_misc);
			mod_val_filtR=((sources_sig*mod_filtR_Amts).sum * dest_gains[10]).tanh.lag(slew_misc);
            
			mod_volL_Amts=NamedControl.kr(\mod_volL_Amts, 0!10); mod_volR_Amts=NamedControl.kr(\mod_volR_Amts, 0!10);
			mod_val_volL=((sources_sig*mod_volL_Amts).sum * dest_gains[20]).tanh.lag(slew_amp);
			mod_val_volR=((sources_sig*mod_volR_Amts).sum * dest_gains[21]).tanh.lag(slew_amp);
			
			mod_audioInL_Amts=NamedControl.kr(\mod_audioInL_Amts, 0!10); mod_audioInR_Amts=NamedControl.kr(\mod_audioInR_Amts, 0!10);
			mod_val_audioInL = LeakDC.ar((sources_sig*mod_audioInL_Amts).sum);
			mod_val_audioInL = (mod_val_audioInL * dest_gains[22] * 4.0).tanh;
			mod_val_audioInR = LeakDC.ar((sources_sig*mod_audioInR_Amts).sum);
			mod_val_audioInR = (mod_val_audioInR * dest_gains[23] * 4.0).tanh;
			
			mod_flipL_Amts=NamedControl.kr(\mod_flipL_Amts, 0!10); mod_flipR_Amts=NamedControl.kr(\mod_flipR_Amts, 0!10);
			raw_mod_flipL = (sources_sig*mod_flipL_Amts).sum * dest_gains[4];
			raw_mod_flipR = (sources_sig*mod_flipR_Amts).sum * dest_gains[11];
			mod_val_flipL = Slew.ar(Schmidt.ar(raw_mod_flipL, 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_flipR = Slew.ar(Schmidt.ar(raw_mod_flipR, 0.6, 0.4), 10000, 20) > 0.01;
			
			mod_skipL_Amts=NamedControl.kr(\mod_skipL_Amts, 0!10); mod_skipR_Amts=NamedControl.kr(\mod_skipR_Amts, 0!10);
			raw_mod_skipL = (sources_sig*mod_skipL_Amts).sum * dest_gains[5];
			raw_mod_skipR = (sources_sig*mod_skipR_Amts).sum * dest_gains[12];
			mod_val_skipL = Slew.ar(Schmidt.ar(raw_mod_skipL, 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_skipR = Slew.ar(Schmidt.ar(raw_mod_skipR, 0.6, 0.4), 10000, 20) > 0.01;

			mod_recL_Amts=NamedControl.kr(\mod_recL_Amts, 0!10); mod_recR_Amts=NamedControl.kr(\mod_recR_Amts, 0!10);
			raw_mod_recL = (sources_sig*mod_recL_Amts).sum * dest_gains[6];
			raw_mod_recR = (sources_sig*mod_recR_Amts).sum * dest_gains[13];
			mod_val_recL = Slew.ar(Schmidt.ar(raw_mod_recL, 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_recR = Slew.ar(Schmidt.ar(raw_mod_recR, 0.6, 0.4), 10000, 20) > 0.01;

			recLogicL = (recL + mod_val_recL).mod(2); recLogicR = (recR + mod_val_recR).mod(2);
			gateRecL = Select.ar(recLogicL > 0.5, [K2A.ar(0), K2A.ar(1)]);
			gateRecR = Select.ar(recLogicR > 0.5, [K2A.ar(0), K2A.ar(1)]);

			dryL = inputL_sig * (volInL + mod_val_ampL).clip(0, 2);
			dryR = inputR_sig * (volInR + mod_val_ampR).clip(0, 2);
			
			baseSpeedL = (speedL + mod_val_speedL + driftL).lag(0.01);
			baseSpeedR = (speedR + mod_val_speedR + driftR).lag(0.01);

			flipLogicL = (flipL + mod_val_flipL).mod(2); flipLogicR = (flipR + mod_val_flipR).mod(2);
			flipStateL = flipLogicL; flipStateR = flipLogicR;

			finalRateL = Select.ar(flipLogicL > 0.5, [baseSpeedL, baseSpeedL * -1]);
			finalRateR = Select.ar(flipLogicR > 0.5, [baseSpeedR, baseSpeedR * -1]);
			
            // Use independent loopLenL/R
			endL = (loopLenL.lag(0.1) * 48000).min(BufFrames.kr(bufL));
			endR = (loopLenR.lag(0.1) * 48000).min(BufFrames.kr(bufR));
			
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
			
			finalJumpTrigL = Select.ar(skipModeL, [Changed.ar(gateSkipL), autoTrigL]);
			finalJumpTrigR = Select.ar(skipModeR, [Changed.ar(gateSkipR), autoTrigR]);
			
			rawPtrL = fb_yellow[0] * endL; rawPtrR = fb_yellow[1] * endR;
			freezePosL = Latch.ar(rawPtrL, gateSkipL); freezePosR = Latch.ar(rawPtrR, gateSkipR);
			
			resetPosL = Select.ar(skipModeL, [TRand.ar(0, endL, finalJumpTrigL), freezePosL]);
			resetPosR = Select.ar(skipModeR, [TRand.ar(0, endR, finalJumpTrigR), freezePosR]);
			
			ptrL = Phasor.ar(finalJumpTrigL, finalRateL * BufRateScale.kr(bufL), 0, endL, resetPosL);
			ptrR = Phasor.ar(finalJumpTrigR, finalRateR * BufRateScale.kr(bufR), 0, endR, resetPosR);
			
            // SAFETY FIX: .max(1) to prevent Division By Zero on init (NaN protection)
			yellowL = (ptrL / endL.max(1)); yellowR = (ptrR / endR.max(1));
			
			LocalOut.ar([p1, p2, p3, p4, p5, p6, yellowL, yellowR]);

			bleedL = SinOsc.ar((baseSR_L * finalRateL.abs).clip(20, 20000)) * 0.001;
			bleedR = SinOsc.ar((baseSR_R * finalRateR.abs).clip(20, 20000)) * 0.001;

			readL = BufRd.ar(1, bufL, ptrL, loop:1, interpolation: interpL);
			readR = BufRd.ar(1, bufR, ptrR, loop:1, interpolation: interpR);
			
			readL = readL + bleedL; readR = readR + bleedR;
			
            // Original Feedback Logic (v4003)
			feedbackL = readL * (fbL + mod_val_fbL).clip(0, 1.2) * 1.15;
			feedbackR = readR * (fbR + mod_val_fbR).clip(0, 1.2) * 1.15;
			feedbackL = LPF.ar(feedbackL, fixedFiltFreq).softclip;
			feedbackR = LPF.ar(feedbackR, fixedFiltFreq).softclip;
			
			writeL = ((dryL) + mod_val_audioInL) * gateRecL + (feedbackL);
			writeR = ((dryR) + mod_val_audioInR) * gateRecR + (feedbackR);
			
			writeL = writeL.round(0.5 ** bitDepthL);
			writeR = writeR.round(0.5 ** bitDepthR);
			
			jitterAmountL = (is8L * 0.02) + (is12L * 0.01) + ((1 - is8L - is12L) * 0.005);
			jitterAmountR = (is8R * 0.02) + (is12R * 0.01) + ((1 - is8R - is12R) * 0.005);
			
			writeL = Latch.ar(writeL, Impulse.ar((baseSR_L * finalRateL.abs).clip(100, 48000) * (1 + WhiteNoise.ar(jitterAmountL))));
			writeR = Latch.ar(writeR, Impulse.ar((baseSR_R * finalRateR.abs).clip(100, 48000) * (1 + WhiteNoise.ar(jitterAmountR))));
			
			BufWr.ar(writeL, bufL, ptrL); BufWr.ar(writeR, bufR, ptrR);
			
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
            
            finalVolL = (ampL + mod_val_volL).clip(0, 2); finalVolR = (ampR + mod_val_volR).clip(0, 2);
            
            // TOPOLOGY UPDATE: Pan2.ar for Equal Power positioning
			master_out = Pan2.ar(readL*finalVolL, panL) + Pan2.ar(readR*finalVolR, panR);
            
            // MONITOR UPDATE: Use clean_preamp signals
            monitorL = clean_preampL + mod_val_audioInL; 
            monitorR = clean_preampR + mod_val_audioInR;
            
            Out.ar(out, Limiter.ar(master_out + [monitorL * monitorLevel, monitorR * monitorLevel], 0.95)); 
			
			osc_trigger = Impulse.kr(30);
			SendReply.kr(osc_trigger, '/update', [ptrL/endL, ptrR/endR, gateRecL, gateRecR, flipStateL, flipStateR, (skipL + mod_val_skipL).clip(0,1), (skipR + mod_val_skipR).clip(0,1), out1, out2, out3, out4, out5, out6, envL, envR, yellowL, yellowR, finalRateL, finalRateR, Amplitude.kr(readL*ampL), Amplitude.kr(readR*ampR)]);
		}).add;

		context.server.sync;
		synth = Synth.new(\NcocoDSP, [\out, context.out_b.index, \bufL, bufL, \bufR, bufR, \inL, context.in_b[0].index, \inR, context.in_b[1].index], context.xg);
		osc_responder = OSCFunc({ |msg| NetAddr("127.0.0.1", 10111).sendMsg("/update", *msg.drop(3)); }, '/update', context.server.addr).fix;

		this.addCommand("clear_tape", "i", { |msg| var b=if(msg[1]==0,{bufL},{bufR}); b.zero; });
		this.addCommand("dest_gains", "ffffffffffffffffffffffff", { |msg| synth.setn(\dest_gains, msg.drop(1)) });
		
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

		this.addCommand("skipModeL", "i", { |msg| synth.set(\skipModeL, msg[1]) });
		this.addCommand("skipModeR", "i", { |msg| synth.set(\skipModeR, msg[1]) });
		this.addCommand("stutterRateL", "f", { |msg| synth.set(\stutterRateL, msg[1]) });
		this.addCommand("stutterRateR", "f", { |msg| synth.set(\stutterRateR, msg[1]) });
		this.addCommand("stutterChaosL", "f", { |msg| synth.set(\stutterChaosL, msg[1]) });
		this.addCommand("stutterChaosR", "f", { |msg| synth.set(\stutterChaosR, msg[1]) });
		this.addCommand("driftAmt", "f", { |msg| synth.set(\driftAmt, msg[1]) });
        
        // FIXED: Loop Length Independent Commands
        this.addCommand("loopLenL", "f", { |msg| synth.set(\loopLenL, msg[1]) });
        this.addCommand("loopLenR", "f", { |msg| synth.set(\loopLenR, msg[1]) });

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
		// Old LoopLen removed (replaced by L/R)
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
		this.addCommand("mod_audioInL", "ffffffffff", { |msg| synth.setn(\mod_audioInL_Amts, msg.drop(1)) });
		this.addCommand("mod_audioInR", "ffffffffff", { |msg| synth.setn(\mod_audioInR_Amts, msg.drop(1)) });
		this.addCommand("monitorLevel", "f", { |msg| synth.set(\monitorLevel, msg[1]) });
	}

	free { osc_responder.free; synth.free; bufL.free; bufR.free; }
}
