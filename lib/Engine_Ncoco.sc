// Engine_Ncoco.sc v2.08
// CHANGELOG v2.08:
// 1. NEW: 5th bit-depth mode "ADPCM" (G.726 leaky step adaptation).
// 2. NEW: 4th bit-depth mode "μ-law" (8-bit companded, buffer decode table).
// 3. NEW: Dither (TPDF on μ-law, adaptive on ADPCM) per channel.
// 4. NEW: Noise Shaping (1st/2nd Order) for all non-linear modes.
// 5. NEW: Encode sub-params inside bitDepthL/bitDepthR (zero new engine commands).
// 6. ARCH: Expanded LocalIn/LocalOut from 10 to 20 channels (ADPCM + NS state).
// 7. OPT: Select.ar tables (indexed by bdInt) replace if/else chain for noise/SR/etc.
// CHANGELOG v2.06:
// 1. FIX: DFM1 LPF now 2-stage cascade with pre-attenuation (0.7) to tame nonlinearity.
// 2. FIX: HPF is ALWAYS Classic (HPF.ar) in both modes - 15kHz max, closes properly.
// 3. TWEAK: Default DFM1 gain 0.15 (conservative for 2-stage LPF cascade).
// CHANGELOG v2.04:
// 1. ENHANCEMENT: DJ Filter now has DFM1 option (menu param, default=Classic).
// 2. FIX: Removed dead ampL/ampR commands (overwritten by "both" commands below).
// CHANGELOG v2.01:
// 1. META: Version bump to 2.01 (project-wide alignment).
// CHANGELOG v10017 (BLEED ROUTING):
// 1. ARCHITECTURE: Added 'b_bleed' audio bus to transport Clock Noise separately from Core to Out.
// 2. LOGIC: Added 'bleedPost' parameter in NcocoOut.
//    - 0 (Pre): Bleed is mixed before the DJ Filter (gets dark).
//    - 1 (Post): Bleed is mixed after the DJ Filter (stays bright/digital).

Engine_Ncoco : CroneEngine {
	var <synth_core, <synth_out;
	var <bufL, <bufR;
	var <b_tape, <b_mon, <b_bleed, <b_mod_vol, <b_mod_filt; // Added b_bleed
	var <osc_responder; 
	var <norns_addr;
	var <muLawDecodeBuf; // [v2.08] μ-law decode lookup table

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
		b_bleed = Bus.audio(context.server, 2);     // [NEW] Bleed signal isolated
		b_mod_vol = Bus.control(context.server, 2); 
		b_mod_filt = Bus.control(context.server, 2);
		
		norns_addr = NetAddr("127.0.0.1", 10111);
		
		// Barrier 1
		context.server.sync;
		bufL.zero; bufR.zero;
		context.server.sync;

		// -----------------------------------------------------------
		// PRE-ALLOC: μ-law decode table (256 entries, 16-bit linear)
		// -----------------------------------------------------------
		muLawDecodeBuf = Buffer.alloc(context.server, 256, 1);
		context.server.sync;
		muLawDecodeBuf.setn(0, Array.series(256, 0, 1).collect { |i|
			var x = i / 127.5 - 1;
			x.sign * ((256 ** x.abs - 1) / 255);
		});

		// -----------------------------------------------------------
		// SYNTH 1: CORE
		// -----------------------------------------------------------
		SynthDef(\NcocoCore, {
			arg bufL, bufR, inL, inR,
			bus_tape_out, bus_mon_out, bus_bleed_out, // Added bleed out
			bus_mvol_out, bus_mfilt_out,
			
			recL=0, recR=0, fbL=0.85, fbR=0.85, speedL=1.0, speedR=1.0,     
			flipL=0, flipR=0, skipL=0, skipR=0,           
			volInL=1.0, volInR=1.0,     
			
			bitDepthL=8, bitDepthR=8, interp=2,                   
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

			slew_speed=0.1, slew_amp=0.05, slew_misc=0;

			// --- VARS (ALL DECLARED AT TOP) ---
			var dest_gains = NamedControl.kr(\dest_gains, 1!24); 
			
			// Matrix Amounts
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

			// Logic & Signals (existing)
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
			var is8L, is12L, is8R, is12R, fixedFiltFreqL, fixedFiltFreqR;
			var endL, endR, yellowL, yellowR;
			var driftL, driftR, bleedL, bleedR, baseSpeedL, baseSpeedR;
			var flipLogicL, flipLogicR, flipStateL, flipStateR, recLogicL, recLogicR;
			var feedbackL, feedbackR, osc_trigger; 
			var preampNoiseL, preampNoiseR, feedback_in, fb_petals, fb_yellow;
			var gateSkipL, gateSkipR, freezePosL, freezePosR, rawPtrL, rawPtrR;
			var minTime, maxTime, lowerL, upperL, lowerR, upperR;
			var demandL, demandR, autoTrigL, autoTrigR, finalJumpTrigL, finalJumpTrigR;
			var resetPosL, resetPosR, jitterAmountL, jitterAmountR;
            var clean_preampL, clean_preampR;
            var relInL, relInR, atkInL, atkInR; 
            var relCoL, relCoR, atkCoL, atkCoR; 
            var envFbL, envFbR;
            var src11_ar, src12_ar; 
            var fb_src11, fb_src12; 
			var bleedAmpL, bleedAmpR;

			// [v2.08] Mode detection & extended vars
			var bdIntL, bdIntR;
			var is16L, is16R, isUlawL, isUlawR, isAdpcmL, isAdpcmR;
			var isLowResL, isLowResR;
			var ulawFracL, ulawFracR, ulawDitherL, ulawDitherR, ulawNSL, ulawNSR;
			var adpcmFracL, adpcmFracR;
			var adpcmBitsL, adpcmBitsR, adpcmPredL, adpcmPredR;
			var adpcmDitherL, adpcmDitherR, adpcmNSL, adpcmNSR;
			var adpcmSR_L, adpcmSR_R;
			var fixFiltL, fixFiltR;            // fixed filter freq indexed by bdInt
			var jitterAmtL, jitterAmtR;        // jitter amount indexed by bdInt
			var bleedAmtL, bleedAmtR;          // bleed amount indexed by bdInt

			// [v2.08] ADPCM state
			var adpcmPredState1L, adpcmPredState2L, adpcmStepL;
			var adpcmPredState1R, adpcmPredState2R, adpcmStepR;
			var adpcmPredValL, adpcmPredValR;
			var adpcmDiffL, adpcmDiffR;
			var adpcmScaleL, adpcmScaleR;
			var adpcmQDiffL, adpcmQDiffR;
			var adpcmIdxL, adpcmIdxR, newStepL, newStepR;
			var adpcmDecodedL, adpcmDecodedR;
			var stepBaseL, stepBaseR, stepMinL, stepMinR, stepMaxL, stepMaxR;
			var stepMultL, stepMultR;
			var adpcmCodeAbsL, adpcmCodeAbsR;
			var adpcmDitherSigL, adpcmDitherSigR;
			var qIndexL, qIndexR;

			// [v2.08] μ-law intermediate
			var quantBitsL, quantBitsR;        // actual quantization bits (8 for ulaw)
			var ulawInL, ulawInR, ulawDitherSigL, ulawDitherSigR;
			var compandedL, compandedR, qCompL, qCompR;
			var ulawExpL, ulawExpR;
			var ulawIdxL, ulawIdxR;

			// [v2.08] Noise shaping state
			var nsErrorL, nsError2L, nsErrorR, nsError2R;
			var nsFbL, nsFbR;
			var qNSInL, qNSInR, qNSOutL, qNSOutR;
			var qErrorL, qErrorR;

			// [v2.08] ADPCM error for NS feedback
			var adpcmErrorL, adpcmErrorR;

			// [v2.08] Final quantization selector
			var writeQL, writeQR;

			// // [v2.08] Select.ar tables (indexed by bdInt)
			// — these are just reference arrays, they must be computed per-sample
			// noiseL/PinkNoise.ar(level) done below
			// baseSR_L/Select.ar(...) done below
			// fixedFiltFreqL/Select.ar(...) done below
			// interpL/Select.ar(...) done below
			// jitterAmountL/Select.ar(...) done below
			// bleedAmpL/Select.ar(...) done below

			// --- CORE DSP ---
			
            feedback_in = LocalIn.ar(20); // [v2.08] Expanded: 10→20
			fb_petals = feedback_in[0..5].tanh; 
			fb_yellow = feedback_in[6..7]; 
            fb_src11 = feedback_in[8];
            fb_src12 = feedback_in[9];
			
			// [v2.08] ADPCM & NS state from feedback
			// First sample: feedback_in is 0 (default), so state initializes cleanly.
			adpcmPredState1L = feedback_in[10];   // ADPCM decoded L (used as prev sample)
			adpcmPredState2L = feedback_in[11];   // ADPCM prev2 L (for 2nd order predictor)
			adpcmStepL = max(feedback_in[12], 0.0001);  // ADPCM step L
			adpcmPredState1R = feedback_in[13];   // ADPCM decoded R
			adpcmPredState2R = feedback_in[14];   // ADPCM prev2 R
			adpcmStepR = max(feedback_in[15], 0.0001);  // ADPCM step R
			nsErrorL = feedback_in[16];           // NS previous error L
			nsError2L = feedback_in[17];          // NS previous2 error L
			nsErrorR = feedback_in[18];           // NS previous error R
			nsError2R = feedback_in[19];          // NS previous2 error R

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

			// [v2.08] MODE DETECTION — decode bitDepth float
			bdIntL = trunc(bitDepthL); bdIntR = trunc(bitDepthR);
			is8L = bdIntL == 8; is8R = bdIntR == 8;
			is12L = bdIntL == 12; is12R = bdIntR == 12;
			is16L = bdIntL >= 14; is16R = bdIntR >= 14;
			isUlawL = bdIntL == 6; isUlawR = bdIntR == 6;
			isAdpcmL = bdIntL == 7; isAdpcmR = bdIntR == 7;

			isLowResL = (is8L + isUlawL + isAdpcmL) > 0;
			isLowResR = (is8R + isUlawR + isAdpcmR) > 0;

			// μ-law sub-params: bitDepth = 6.dd (d=dither, ns=ns)
			ulawFracL = isUlawL * (bitDepthL - 6);
			ulawFracR = isUlawR * (bitDepthR - 6);
			ulawDitherL = trunc(ulawFracL * 10 + 0.0001);
			ulawDitherR = trunc(ulawFracR * 10 + 0.0001);
			ulawNSL = trunc(ulawFracL * 100 + 0.0001) % 10;
			ulawNSR = trunc(ulawFracR * 100 + 0.0001) % 10;

			// ADPCM sub-params: bitDepth = 7.abpd (a=bits, b=predictor, p=dither, d=ns)
			adpcmFracL = isAdpcmL * (bitDepthL - 7);
			adpcmFracR = isAdpcmR * (bitDepthR - 7);
			adpcmBitsL = trunc(adpcmFracL * 100 + 0.0001);       // 4, 5, 6
			adpcmBitsR = trunc(adpcmFracR * 100 + 0.0001);
			adpcmPredL = trunc(adpcmFracL * 1000 + 0.0001) % 10; // 1 or 2
			adpcmPredR = trunc(adpcmFracR * 1000 + 0.0001) % 10;
			adpcmDitherL = trunc(adpcmFracL * 10000 + 0.0001) % 10; // 0 or 1
			adpcmDitherR = trunc(adpcmFracR * 10000 + 0.0001) % 10;
			adpcmNSL = trunc(adpcmFracL * 100000 + 0.0001) % 10; // 0, 1, 2
			adpcmNSR = trunc(adpcmFracR * 100000 + 0.0001) % 10;

			// [v2.08] Select.ar tables indexed by bdInt (pn=positive, nz=nonzero guard)
			// noise level: index 6=ulaw, 7=adpcm, 8=8bit, 12=12bit, 16=16bit
			noiseL = PinkNoise.ar(
				Select.ar(bdIntL, [
					0,0,0,0,0,0,        // 0-5
					0.006,               // 6: μ-law
					0.003,               // 7: ADPCM
					0.008,               // 8: 8-bit
					0,0,0,               // 9-11
					0.0016,              // 12: 12-bit
					0,0,0,               // 13-15
					0.00016              // 16: 16-bit
				])
			);
			noiseR = PinkNoise.ar(
				Select.ar(bdIntR, [
					0,0,0,0,0,0,
					0.006,
					0.003,
					0.008,
					0,0,0,
					0.0016,
					0,0,0,
					0.00016
				])
			);
			
			baseSR_L = Select.ar(bdIntL, [
				0,0,0,0,0,0,
				22000,               // 6: μ-law
				0,                   // placeholder for ADPCM (overridden below)
				16000,               // 8: 8-bit
				0,0,0,
				31250,               // 12: 12-bit
				0,0,0,
				39000                // 16: 16-bit
			]);
			baseSR_R = Select.ar(bdIntR, [
				0,0,0,0,0,0,
				22000,
				0,
				16000,
				0,0,0,
				31250,
				0,0,0,
				39000
			]) * 1.002;
			
			// Override ADPCM SR: 14kHz/16kHz/16kHz for 4/5/6 bit
			adpcmSR_L = Select.ar(adpcmBitsL - 4, [14000, 16000, 16000]);
			adpcmSR_R = Select.ar(adpcmBitsR - 4, [14000, 16000, 16000]);
			baseSR_L = Select.ar(isAdpcmL, [baseSR_L, adpcmSR_L]);
			baseSR_R = Select.ar(isAdpcmR, [baseSR_R, adpcmSR_R]);

			fixFiltL = Select.ar(bdIntL, [
				0,0,0,0,0,0,
				9000,                // 6: μ-law
				8000,                // 7: ADPCM
				7000,                // 8: 8-bit
				0,0,0,
				12800,               // 12: 12-bit
				0,0,0,
				18000                // 16: 16-bit
			]);
			fixFiltR = Select.ar(bdIntR, [
				0,0,0,0,0,0,
				9000,
				8000,
				7000,
				0,0,0,
				12800,
				0,0,0,
				18000
			]) * 1.04;

			interpL = Select.ar(bdIntL, [
				0,0,0,0,0,0,
				1,                   // 6: μ-law (no interp, lo-fi)
				1,                   // 7: ADPCM (no interp, lo-fi)
				1,                   // 8: 8-bit
				0,0,0,
				2,                   // 12: 12-bit
				0,0,0,
				3                    // 16: 16-bit (cubic)
			]);
			interpR = Select.ar(bdIntR, [
				0,0,0,0,0,0,
				1,
				1,
				1,
				0,0,0,
				2,
				0,0,0,
				3
			]);

			jitterAmtL = Select.ar(bdIntL, [
				0,0,0,0,0,0,
				0.02,                // 6: μ-law
				0.015,               // 7: ADPCM
				0.02,                // 8: 8-bit
				0,0,0,
				0.004,               // 12: 12-bit
				0,0,0,
				0.001                // 16: 16-bit
			]);
			jitterAmtR = Select.ar(bdIntR, [
				0,0,0,0,0,0,
				0.02,
				0.015,
				0.02,
				0,0,0,
				0.004,
				0,0,0,
				0.001
			]);

			bleedAmtL = Select.ar(bdIntL, [
				0,0,0,0,0,0,
				0.002,               // 6: μ-law
				0.0015,              // 7: ADPCM
				0.0025,              // 8: 8-bit
				0,0,0,
				0.001,               // 12: 12-bit
				0,0,0,
				0                    // 16: 16-bit
			]);
			bleedAmtR = Select.ar(bdIntR, [
				0,0,0,0,0,0,
				0.002,
				0.0015,
				0.0025,
				0,0,0,
				0.001,
				0,0,0,
				0
			]);

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
			out1=Select.ar(p1shape,[p1,c1]); out2=Select.ar(p2shape,[p2,c2]); out3=Select.ar(p3shape,[p3,c3]);
			out4=Select.ar(p4shape,[p4,c4]); out5=Select.ar(p5shape,[p5,c5]); out6=Select.ar(p6shape,[p6,c6]);
			
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
			flipStateL = flipLogicL; flipStateR = flipLogicR;

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
			autoTrigL = TDuty.ar(demandL, reset: K2A.ar(gateSkipL)) * K2A.ar(gateSkipL);
			lowerR = stutterRateR - (stutterChaosR * (stutterRateR - minTime));
			upperR = stutterRateR + (stutterChaosR * (maxTime - stutterRateR));
			demandR = Dwhite(lowerR, upperR);
			autoTrigR = TDuty.ar(demandR, reset: K2A.ar(gateSkipR)) * K2A.ar(gateSkipR);
			
			finalJumpTrigL = Select.ar(skipModeL, [Changed.ar(K2A.ar(gateSkipL)), autoTrigL]);
			finalJumpTrigR = Select.ar(skipModeR, [Changed.ar(K2A.ar(gateSkipR)), autoTrigR]);
			
			rawPtrL = fb_yellow[0] * endL; rawPtrR = fb_yellow[1] * endR;
			freezePosL = Latch.ar(rawPtrL, K2A.ar(gateSkipL)); freezePosR = Latch.ar(rawPtrR, K2A.ar(gateSkipR));
			
			resetPosL = Select.ar(skipModeL, [TRand.ar(0, endL, finalJumpTrigL), freezePosL]);
			resetPosR = Select.ar(skipModeR, [TRand.ar(0, endR, finalJumpTrigR), freezePosR]);
			
			ptrL = Phasor.ar(finalJumpTrigL, finalRateL * BufRateScale.kr(bufL), 0, endL, resetPosL);
			ptrR = Phasor.ar(finalJumpTrigR, finalRateR * BufRateScale.kr(bufR), 0, endR, resetPosR);
			
			yellowL = (ptrL / endL.max(1)); yellowR = (ptrR / endR.max(1));
			
            // Bleed Logic
			bleedL = SinOsc.ar((baseSR_L * finalRateL.abs).clip(20, 20000)) * bleedAmtL;
			bleedR = SinOsc.ar((baseSR_R * finalRateR.abs).clip(20, 20000)) * bleedAmtR;

			readL = BufRd.ar(1, bufL, ptrL, loop:1, interpolation: interpL);
			readR = BufRd.ar(1, bufR, ptrR, loop:1, interpolation: interpR);
			
            readL = readL + (noiseL * 0.5); // NEW: Only noise here
            readR = readR + (noiseR * 0.5);

            // Coco Env Logic
            relCoL = cocoSlewL.linexp(0, 1, 0.05, 2.5); relCoR = cocoSlewR.linexp(0, 1, 0.05, 2.5);
            atkCoL = (relCoL * 0.1).max(0.002); atkCoR = (relCoR * 0.1).max(0.002);
            envFbL = Amplitude.kr(LeakDC.ar(readL), atkCoL, relCoL) * 2.0; 
            envFbR = Amplitude.kr(LeakDC.ar(readR), atkCoR, relCoR) * 2.0;
            src11_ar = Select.ar(coco1OutMode, [K2A.ar(envFbL), readL]);
            src12_ar = Select.ar(coco2OutMode, [K2A.ar(envFbR), readR]);
            
            // Calc Modulations for Output
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
			gateRecL = Select.ar(recLogicL > 0.5, [K2A.ar(0), K2A.ar(1)]);
			gateRecR = Select.ar(recLogicR > 0.5, [K2A.ar(0), K2A.ar(1)]);

			dryL = inputL_sig * (volInL + mod_val_ampL).clip(0, 2);
			dryR = inputR_sig * (volInR + mod_val_ampR).clip(0, 2);

			feedbackL = readL * (fbL + mod_val_fbL).clip(0, 1.2) * 1.15;
			feedbackR = readR * (fbR + mod_val_fbR).clip(0, 1.2) * 1.15;
			feedbackL = LPF.ar(feedbackL, fixFiltL).softclip;
			feedbackR = LPF.ar(feedbackR, fixFiltR).softclip;
			
			writeL = ((dryL) + mod_val_audioInL) * gateRecL + (feedbackL);
			writeR = ((dryR) + mod_val_audioInR) * gateRecR + (feedbackR);

			// ============================================================
			// [v2.08] QUANTIZATION ENGINE (Linear / μ-law / ADPCM)
			// ============================================================

			// --- Noise Shaping Feedback ---
			// nsFb = Select(nsType, [0, prev*0.5, 2*prev*0.5 - prev2*0.25])
			nsFbL = Select.ar(Select.ar(isUlawL, [adpcmNSL, ulawNSL]), [
				DC.ar(0),                  // Off
				nsErrorL * 0.5,            // 1st Order
				nsErrorL * 1.0 - nsError2L * 0.25  // 2nd Order
			]);
			nsFbR = Select.ar(Select.ar(isUlawR, [adpcmNSR, ulawNSR]), [
				DC.ar(0),
				nsErrorR * 0.5,
				nsErrorR * 1.0 - nsError2R * 0.25
			]);

			// --- Linear quantization (16, 12, 8 bit) ---
			quantBitsL = Select.ar(bdIntL, [
				0,0,0,0,0,0,
				8,                   // 6: μ-law (quant to 8)
				0,                   // 7: ADPCM (not used here)
				8,                   // 8: linear 8
				0,0,0,
				12,                  // 12: linear 12
				0,0,0,
				16                   // 16: linear 16
			]);
			quantBitsR = Select.ar(bdIntR, [
				0,0,0,0,0,0,
				8,
				0,
				8,
				0,0,0,
				12,
				0,0,0,
				16
			]);

			// Linear quantized (for display/timing, but we route to Select at end)
			// We compute all three paths then select.

			// --- PATH 1: Linear (8/12/16bit) ---
			// (no dither, NS already applied to input)
			writeQL = (writeL + nsFbL).round(0.5 ** quantBitsL);

			// --- PATH 2: μ-law ---
			// Dither signal (TPDF: sum of two uniform RVs)
			ulawDitherSigL = Select.ar(ulawDitherL, [
				DC.ar(0),                                          // Off
				(WhiteNoise.ar(1) + WhiteNoise.ar(1)) * (0.5 ** 9) // TPDF: 1 LSB p-p = 2^-8
			]) * 0.5;
			ulawDitherSigR = Select.ar(ulawDitherR, [
				DC.ar(0),
				(WhiteNoise.ar(1) + WhiteNoise.ar(1)) * (0.5 ** 9)
			]) * 0.5;

			// μ-law compand: sign * log(1 + 255*|x|) / log(256)
			ulawInL = writeL + nsFbL + ulawDitherSigL;
			ulawInR = writeR + nsFbR + ulawDitherSigR;
			compandedL = (ulawInL.sign * ((1 + 255 * ulawInL.abs).log / (256).log)).clip(-1, 1);
			compandedR = (ulawInR.sign * ((1 + 255 * ulawInR.abs).log / (256).log)).clip(-1, 1);

			// Quantize companded signal to 8-bit (256 steps, -1..1 → 0..255)
			// Store error for NS BEFORE table lookup
			qCompL = (compandedL * 127 + 127).round(1).clip(0, 255);
			qCompR = (compandedR * 127 + 127).round(1).clip(0, 255);
			qErrorL = (compandedL * 127 + 127) - qCompL;
			qErrorR = (compandedR * 127 + 127) - qCompR;

			// μ-law expand via lookup table (index 0..255)
			ulawIdxL = qCompL.round.asInteger;
			ulawIdxR = qCompR.round.asInteger;
			ulawExpL = Index(muLawDecodeBuf, ulawIdxL);
			ulawExpR = Index(muLawDecodeBuf, ulawIdxR);

			// Store μ-law error for NS feedback (normalize back to signal domain)
			// Error in companded domain rescaled: approximated as signal error

			// --- PATH 3: ADPCM ---
			// Predictor
			adpcmPredValL = Select.ar(adpcmPredL, [
				adpcmPredState1L,                     // 1st Order: prev sample
				2 * adpcmPredState1L - adpcmPredState2L  // 2nd Order: linear extrapolation
			]);
			adpcmPredValR = Select.ar(adpcmPredR, [
				adpcmPredState1R,
				2 * adpcmPredState1R - adpcmPredState2R
			]);

			// Step-size base, min, max per ADPCM bits
			stepBaseL = Select.ar(adpcmBitsL - 4, [0.05, 0.025, 0.0125]);
			stepBaseR = Select.ar(adpcmBitsR - 4, [0.05, 0.025, 0.0125]);
			stepMinL = stepBaseL * 0.1;
			stepMinR = stepBaseR * 0.1;
			stepMaxL = stepBaseL * 10;
			stepMaxR = stepBaseR * 10;

			// Adaptive step-size dither
			adpcmDitherSigL = Select.ar(adpcmDitherL, [
				DC.ar(0),
				WhiteNoise.ar(adpcmStepL * 0.5)
			]);
			adpcmDitherSigR = Select.ar(adpcmDitherR, [
				DC.ar(0),
				WhiteNoise.ar(adpcmStepR * 0.5)
			]);

			// ADPCM encode: diff = input + nsFb + dither - predictor
			adpcmDiffL = writeL + nsFbL + adpcmDitherSigL - adpcmPredValL;
			adpcmDiffR = writeR + nsFbR + adpcmDitherSigR - adpcmPredValR;

			// Quantize diff using current step-size
			adpcmQDiffL = (adpcmDiffL / adpcmStepL).round(0.5 ** adpcmBitsL) * adpcmStepL;
			adpcmQDiffR = (adpcmDiffR / adpcmStepR).round(0.5 ** adpcmBitsR) * adpcmStepR;

			// ADPCM decode: output = predictor + quantized diff
			adpcmDecodedL = adpcmPredValL + adpcmQDiffL;
			adpcmDecodedR = adpcmPredValR + adpcmQDiffR;

			// G.726 leaky step adaptation
			// Index encodes: |quantized_code| maps to multiplier
			// For code of 0..(2^n - 1): normalized |code| maps to table
			adpcmCodeAbsL = abs(adpcmQDiffL / adpcmStepL.max(0.0001)).clip(0, 2 ** adpcmBitsL - 1);
			adpcmCodeAbsR = abs(adpcmQDiffR / adpcmStepR.max(0.0001)).clip(0, 2 ** adpcmBitsR - 1);

			// G.726-like table: larger code → larger multiplier
			// Index normalized to 0..1, expanded to 2^bits range
			qIndexL = (adpcmCodeAbsL / (2 ** adpcmBitsL - 1).max(1));
			qIndexR = (adpcmCodeAbsR / (2 ** adpcmBitsR - 1).max(1));
			stepMultL = (qIndexL * 1.5 + 0.5).max(0.5).min(2.5);  // 0.5..2.5 range
			stepMultR = (qIndexR * 1.5 + 0.5).max(0.5).min(2.5);

			// Apply with leak: step = step * leakFactor + (step * multiplier - step) * adaptRate
			newStepL = adpcmStepL * 0.98 + ((adpcmStepL * stepMultL - adpcmStepL) * 0.5);
			newStepR = adpcmStepR * 0.98 + ((adpcmStepR * stepMultR - adpcmStepR) * 0.5);
			newStepL = newStepL.clip(stepMinL, stepMaxL);
			newStepR = newStepR.clip(stepMinR, stepMaxR);

			// Update predictor state
			// (stored via LocalOut for next sample)

			// Store ADPCM error for NS feedback
			// (error = re-quantized diff - original diff, i.e. quantization noise)
			adpcmErrorL = adpcmQDiffL - adpcmDiffL;
			adpcmErrorR = adpcmQDiffR - adpcmDiffR;

			// --- SELECT FINAL QUANTIZED OUTPUT ---
			writeQL = Select.ar(isUlawL, [
				Select.ar(isAdpcmL, [
					writeL.round(0.5 ** quantBitsL),  // Linear
					adpcmDecodedL                     // ADPCM
				]),
				ulawExpL                              // μ-law
			]);
			writeQR = Select.ar(isUlawR, [
				Select.ar(isAdpcmR, [
					writeR.round(0.5 ** quantBitsR),  // Linear
					adpcmDecodedR                     // ADPCM
				]),
				ulawExpR                              // μ-law
			]);

			// Compute quantization error for NS (on selected path)
			qErrorL = Select.ar(isUlawL, [
				Select.ar(isAdpcmL, [
					writeL - writeQL,       // Linear error
					adpcmErrorL             // ADPCM error already computed
				]),
				qErrorL / 127               // μ-law error (normalize back)
			]);
			qErrorR = Select.ar(isUlawR, [
				Select.ar(isAdpcmR, [
					writeR - writeQR,
					adpcmErrorR
				]),
				qErrorR / 127
			]);

			// --- SAMPLE RATE REDUCTION (Latch for non-16bit modes) ---
			// For 8bit, μ-law, ADPCM: Latch at reduced SR
			writeQL = Select.ar(is8L + isUlawL + isAdpcmL, [
				writeQL, // 16bit/12bit: no SR reduction (interp handles it)
				Latch.ar(writeQL, Impulse.ar(
					(baseSR_L * finalRateL.abs).clip(100, 48000) *
					(1 + WhiteNoise.ar(jitterAmtL))
				))
			]);
			writeQR = Select.ar(is8R + isUlawR + isAdpcmR, [
				writeQR,
				Latch.ar(writeQR, Impulse.ar(
					(baseSR_R * finalRateR.abs).clip(100, 48000) *
					(1 + WhiteNoise.ar(jitterAmtR))
				))
			]);

			// --- WRITE TO BUFFER ---
			BufWr.ar(writeQL, bufL, ptrL);
			BufWr.ar(writeQR, bufR, ptrR);

			// --- LOCALOUT (20 channels) ---
			LocalOut.ar([
				p1, p2, p3, p4, p5, p6,          // 0-5: petals
				yellowL, yellowR,                  // 6-7: yellow
				src11_ar, src12_ar,                // 8-9: coco outs
				adpcmDecodedL * isAdpcmL,           // 10: ADPCM decoded L (state for next pred)
				adpcmPredState1L * isAdpcmL,        // 11: ADPCM prev2 L (2nd order needs 2 prevs)
				newStepL * isAdpcmL,                // 12: ADPCM step L
				adpcmDecodedR * isAdpcmR,           // 13: ADPCM decoded R
				adpcmPredState1R * isAdpcmR,        // 14: ADPCM prev2 R
				newStepR * isAdpcmR,                // 15: ADPCM step R
				qErrorL,                            // 16: NS error L (prev)
				nsErrorL,                           // 17: NS error2 L (prev2)
				qErrorR,                            // 18: NS error R (prev)
				nsErrorR                            // 19: NS error2 R (prev2)
			]);

			// Send OSC
			osc_trigger = Impulse.kr(30);
			SendReply.kr(osc_trigger, '/update', [
				A2K.kr(ptrL/endL.max(1)), A2K.kr(ptrR/endR.max(1)),
				A2K.kr(gateRecL), A2K.kr(gateRecR),
				K2A.ar(flipStateL), K2A.ar(flipStateR),
				K2A.ar((skipL + mod_val_skipL).clip(0,1)),
				K2A.ar((skipR + mod_val_skipR).clip(0,1)),
				A2K.kr(out1), A2K.kr(out2), A2K.kr(out3),
				A2K.kr(out4), A2K.kr(out5), A2K.kr(out6),
				envL, envR,
				A2K.kr(yellowL), A2K.kr(yellowR),
				K2A.ar(finalRateL), K2A.ar(finalRateR),
				A2K.kr(Amplitude.ar(readL*ampL)),
				A2K.kr(Amplitude.ar(readR*ampR)),
				A2K.kr(src11_ar), A2K.kr(src12_ar)
			]);

            // BRIDGE: OUTPUT TO BUSES
            Out.ar(bus_tape_out, [readL, readR]);
            Out.ar(bus_mon_out, [clean_preampL + mod_val_audioInL, clean_preampR + mod_val_audioInR]);
            Out.ar(bus_bleed_out, [bleedL, bleedR]); // Send Bleed separately
            Out.kr(bus_mvol_out, [mod_val_volL, mod_val_volR]);
            Out.kr(bus_mfilt_out, [mod_val_filtL, mod_val_filtR]);

		}).add;

		// -----------------------------------------------------------
		// SYNTH 2: OUT (Mix, Filter, Amp)
		// -----------------------------------------------------------
		SynthDef(\NcocoOut, {
            arg out, bus_tape_in, bus_mon_in, bus_bleed_in, // Added bleed in
            bus_mvol_in, bus_mfilt_in,
            filtL=0, filtR=0, ampL=1.0, ampR=1.0, panL= -0.5, panR=0.5, monitorLevel=0,
            bleedPost=0,
            djFilterType=0,
            dfm1Gain=0.32;

            // --- VARS (ALL DECLARED AT TOP) ---
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

            // --- CODE BODY ---
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

            // Pre-Filter Mix
            sigL = readL + (bleedL * (1.0 - bleedPost));
            sigR = readR + (bleedR * (1.0 - bleedPost));

            // DJ Filter with Classic/DFM1 selection
            lpfFreqL = (totalFiltL.min(0)+1).linexp(0,1,100,20000);
            hpfFreqL = totalFiltL.max(0).linexp(0,1,20,15000);
            lpfFreqR = (totalFiltR.min(0)+1).linexp(0,1,100,20000);
            hpfFreqR = totalFiltR.max(0).linexp(0,1,20,15000);

            // Classic path (original LPF/HPF, 12dB/oct each)
            classicL = HPF.ar(LPF.ar(sigL, lpfFreqL), hpfFreqL);
            classicR = HPF.ar(LPF.ar(sigR, lpfFreqR), hpfFreqR);

// [v2.06] DFM1 path: LPF x2 (pre-attenuated) + HPF always Classic
            // L channel
            dfm1L = DFM1.ar(sigL * 0.7, lpfFreqL, 0, 1.0, 0, 0.0003);  // LPF stage 1
            dfm1L = DFM1.ar(dfm1L, lpfFreqL, 0, 1.0, 0, 0.0003);       // LPF stage 2
            dfm1L = HPF.ar(dfm1L, hpfFreqL) * dfm1Gain;                  // HPF Classic
            // R channel
            dfm1R = DFM1.ar(sigR * 0.7, lpfFreqR, 0, 1.0, 0, 0.0003);  // LPF stage 1
            dfm1R = DFM1.ar(dfm1R, lpfFreqR, 0, 1.0, 0, 0.0003);       // LPF stage 2
            dfm1R = HPF.ar(dfm1R, hpfFreqR) * dfm1Gain;                  // HPF Classic

            // Select filter type when filter is active (|totalFilt| >= 0.05)
			sigL = Select.ar(totalFiltL.abs < 0.05, [
				Select.ar(djFilterType, [classicL, dfm1L]),
				sigL
			]);
			sigR = Select.ar(totalFiltR.abs < 0.05, [
				Select.ar(djFilterType, [classicR, dfm1R]),
				sigR
			]);
            
            // Post-Filter Mix
            sigL = sigL + (bleedL * bleedPost);
            sigR = sigR + (bleedR * bleedPost);
            
            finalVolL = (ampL + mod_val_volL).clip(0, 2); 
            finalVolR = (ampR + mod_val_volR).clip(0, 2);
            
			master_out = Pan2.ar(sigL*finalVolL, panL) + Pan2.ar(sigR*finalVolR, panR);
            
            Out.ar(out, Limiter.ar(master_out + [monL * monitorLevel, monR * monitorLevel], 0.95)); 
        }).add;

		// BARRIER 2
		context.server.sync;
		
        // INSTANTIATE SPLIT SYNTHS
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

        // COMMANDS MAPPING (unchanged from v2.06 — no new commands added)
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

        // PARAMS -> CORE
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
		this.addCommand("bitDepthL", "f", { |msg| synth_core.set(\bitDepthL, msg[1]) });
		this.addCommand("bitDepthR", "f", { |msg| synth_core.set(\bitDepthR, msg[1]) });
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

        // PARAMS -> OUT
		this.addCommand("filtL", "f", { |msg| synth_out.set(\filtL, msg[1]) });
		this.addCommand("filtR", "f", { |msg| synth_out.set(\filtR, msg[1]) });
		this.addCommand("panL", "f", { |msg| synth_out.set(\panL, msg[1]) });
		this.addCommand("panR", "f", { |msg| synth_out.set(\panR, msg[1]) });
		this.addCommand("monitorLevel", "f", { |msg| synth_out.set(\monitorLevel, msg[1]) });
        this.addCommand("bleedPost", "f", { |msg| synth_out.set(\bleedPost, msg[1]) });
        this.addCommand("dj_filter_type", "f", { |msg| synth_out.set(\djFilterType, msg[1]) });
        this.addCommand("dj_filter_gain", "f", { |msg| synth_out.set(\dfm1Gain, msg[1]) });

        // PARAMS -> BOTH (Amp controls visual in Core and audio in Out)
        this.addCommand("ampL", "f", { |msg| 
            synth_core.set(\ampL, msg[1]); 
            synth_out.set(\ampL, msg[1]); 
        });
        this.addCommand("ampR", "f", { |msg| 
            synth_core.set(\ampR, msg[1]); 
            synth_out.set(\ampR, msg[1]); 
        });

        // MODULATION MATRICES (All Core)
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
        muLawDecodeBuf.free; // [v2.08] Free μ-law table
    }
}