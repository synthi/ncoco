/// Engine_Ncoco.sc v2.09
// CHANGELOG v2.09:
// 1. FIX: Eliminadas 4 variables muertas (is12L/R, fixedFiltFreqL/R, jitterAmountL/R, bleedAmpL/R).
// 2. OPT: Empaquetadas todas las variables L/R en arreglos [L,R] para reducir el conteo de vars.
//    - 82 vars v2.08 → 38 arreglos, 24 vars modulación → 12 arreglos, ~70 vars señales → ~35 arreglos.
//    - NcocoCore: 56 args + 170 vars = 226 total (bajo el límite de 246).
// CHANGELOG v2.08:
// 1. NEW: 5th bit-depth mode "ADPCM" (G.726 leaky step adaptation).
// 2. NEW: 4th bit-depth mode "u-law" (8-bit companded).
// 3. NEW: Dither (TPDF on u-law, adaptive on ADPCM) per channel.
// 4. NEW: Noise Shaping (1st/2nd Order) with LocalIn state tracking.
// 5. NEW: Encode sub-params inside bitDepthL/bitDepthR (zero new commands).
// 6. ARCH: Expanded LocalIn/LocalOut from 10 to 20 channels (NS + ADPCM state).
// 7. OPT: Select.ar tables (indexed by bdInt) replace if/else chain.
// CHANGELOG v2.06:
// 1. FIX: DFM1 LPF now 2-stage cascade with pre-attenuation (0.7) to tame nonlinearity.
// 2. FIX: HPF is ALWAYS Classic (HPF.ar) in both modes — 15kHz max, closes properly.
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

			// --- VARS ---
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

			// Logic & Signals
			var inputL_sig, inputR_sig, envL, envR, envL_raw, envR_raw;
			var p1, p2, p3, p4, p5, p6, c1, c2, c3, c4, c5, c6; 
			var b_ph1, b_ph2, b_ph3, b_ph4, b_ph5, b_ph6, t1, t2, t3, t4, t5, t6; 
			var out1, out2, out3, out4, out5, out6, sources_sig; 
			var p1c, p2c, p3c, p4c, p5c, p6c;
			
			var raw_mod_flip = [0, 0], mod_val_flip = [0, 0];
			var raw_mod_skip = [0, 0], mod_val_skip = [0, 0];
			var raw_mod_rec = [0, 0], mod_val_rec = [0, 0];
			var mod_val_speed = [0, 0], mod_val_amp = [0, 0];
			var mod_val_fb = [0, 0], mod_val_filt = [0, 0];
			var mod_val_vol = [0, 0], mod_val_audioIn = [0, 0];
			var mod_p1, mod_p2, mod_p3, mod_p4, mod_p5, mod_p6;
			
			var dry = [0, 0], finalRate = [0, 0], ptr = [0, 0], read = [0, 0], write = [0, 0];
			var gateRec = [0, 0], noise = [0, 0], baseSR = [0, 0], interpVals = [0, 0];
			var is8L, is8R;
			var end = [0, 0], yellow = [0, 0];
			var drift = [0, 0], bleed = [0, 0], baseSpeed = [0, 0];
			var flipLogic = [0, 0], flipState = [0, 0], recLogic = [0, 0];
			var feedback = [0, 0], osc_trigger; 
			var preampNoise = [0, 0], feedback_in, fb_petals, fb_yellow;
			var gateSkip = [0, 0], freezePos = [0, 0], rawPtr = [0, 0];
			var minTime, maxTime, lower = [0, 0], upper = [0, 0];
			var demand = [0, 0], autoTrig = [0, 0], finalJumpTrig = [0, 0];
			var resetPos = [0, 0];
			var clean_preamp = [0, 0];
			var relIn = [0, 0], atkIn = [0, 0]; 
			var relCo = [0, 0], atkCo = [0, 0]; 
			var envFb = [0, 0];
			var src11_ar, src12_ar; 
			var fb_src11, fb_src12; 
			// [v2.08] VARS EMPAQUETADAS EN ARREGLOS [L, R]
			var bdInt = [0, 0];
			var is16 = [0, 0], isUlaw = [0, 0], isAdpcm = [0, 0];
			var ulawFrac = [0, 0], ulawDither = [0, 0], ulawNS = [0, 0];
			var adpcmFrac = [0, 0];
			var adpcmBits = [0, 0], adpcmPred = [0, 0];
			var adpcmDither = [0, 0], adpcmNS = [0, 0];
			var adpcmSR = [0, 0];
			var fixFilt = [0, 0];
			var jitterAmt = [0, 0];
			var bleedAmt = [0, 0];
			var quantBits = [0, 0];
			var ulawDitherSig = [0, 0];
			var ulawIn = [0, 0], companded = [0, 0], qComp = [0, 0];
			var ulawExp = [0, 0], ulawIdx = [0, 0];
			var adpcmPredVal = [0, 0];
			var adpcmDiff = [0, 0], adpcmQDiff = [0, 0];
			var adpcmDecoded = [0, 0];
			var stepBase = [0, 0], stepMin = [0, 0], stepMax = [0, 0];
			var newStep = [0, 0], stepMult = [0, 0];
			var adpcmDitherSig = [0, 0];
			var writeQ = [0, 0];
			// FEEDBACK STATE: nsError = [L_err, L_err2, R_err, R_err2]  (feedback_in[10..13])
			var nsError = [0, 0, 0, 0];
			var nsFb = [0, 0];
			// adpcmStateL = [state1, state2, stepState]  (feedback_in[14..16])
			var adpcmStateL = [0, 0, 0];
			// adpcmStateR = [state1, state2, stepState]  (feedback_in[17..19])
			var adpcmStateR = [0, 0, 0];

			// --- CORE DSP ---
			
			feedback_in = LocalIn.ar(20); // [v2.08] Expanded for NS + ADPCM state
			fb_petals = feedback_in[0..5].tanh; 
			fb_yellow = feedback_in[6..7]; 
            fb_src11 = feedback_in[8];
            fb_src12 = feedback_in[9];
			// [v2.08] Noise Shaping state
			nsError[0] = feedback_in[10]; nsError[1] = feedback_in[11];
			nsError[2] = feedback_in[12]; nsError[3] = feedback_in[13];
			// [v2.08] ADPCM state (persistent predictor + step)
			adpcmStateL[0] = feedback_in[14]; adpcmStateL[1] = feedback_in[15];
			adpcmStateL[2] = max(feedback_in[16], 0.0001);
			adpcmStateR[0] = feedback_in[17]; adpcmStateR[1] = feedback_in[18];
			adpcmStateR[2] = max(feedback_in[19], 0.0001);

			preampNoise[0] = PinkNoise.ar(((preampL - 6).max(0) * 0.0714).pow(2));
			preampNoise[1] = PinkNoise.ar(((preampR - 6).max(0) * 0.0714).pow(2));
			inputL_sig = In.ar(inL); inputR_sig = In.ar(inR);
			
            inputL_sig = HPF.ar(inputL_sig, 20); inputR_sig = HPF.ar(inputR_sig, 20);
			inputL_sig = ((inputL_sig * preampL) + preampNoise[0]).tanh; 
			inputR_sig = ((inputR_sig * preampR) + preampNoise[1]).tanh;
			
            relIn[0] = envSlewL.linexp(0, 1, 0.05, 2.5); relIn[1] = envSlewR.linexp(0, 1, 0.05, 2.5);
            atkIn[0] = (relIn[0] * 0.1).max(0.002); atkIn[1] = (relIn[1] * 0.1).max(0.002);
			envL_raw = Amplitude.kr(inputL_sig, atkIn[0], relIn[0]); 
			envR_raw = Amplitude.kr(inputR_sig, atkIn[1], relIn[1]);
			envL = envL_raw * 2.0; envR = envR_raw * 2.0;

            clean_preamp[0] = inputL_sig; clean_preamp[1] = inputR_sig;

			// [v2.08] MODE DETECTION
			bdInt[0] = bitDepthL.trunc; bdInt[1] = bitDepthR.trunc;
			is8L = (bdInt[0] == 8).asInteger; is8R = (bdInt[1] == 8).asInteger;
			is16[0] = (bdInt[0] >= 14).asInteger; is16[1] = (bdInt[1] >= 14).asInteger;
			isUlaw[0] = (bdInt[0] == 6).asInteger; isUlaw[1] = (bdInt[1] == 6).asInteger;
			isAdpcm[0] = (bdInt[0] == 7).asInteger; isAdpcm[1] = (bdInt[1] == 7).asInteger;
			// u-law sub-params
			ulawFrac[0] = isUlaw[0] * (bitDepthL - 6);
			ulawFrac[1] = isUlaw[1] * (bitDepthR - 6);
			ulawDither[0] = (ulawFrac[0] * 10 + 0.0001).trunc;
			ulawDither[1] = (ulawFrac[1] * 10 + 0.0001).trunc;
			ulawNS[0] = ((ulawFrac[0] * 100 + 0.0001).trunc) % 10;
			ulawNS[1] = ((ulawFrac[1] * 100 + 0.0001).trunc) % 10;
			// ADPCM sub-params
			adpcmFrac[0] = isAdpcm[0] * (bitDepthL - 7);
			adpcmFrac[1] = isAdpcm[1] * (bitDepthR - 7);
			adpcmBits[0] = (adpcmFrac[0] * 100 + 0.0001).trunc;
			adpcmBits[1] = (adpcmFrac[1] * 100 + 0.0001).trunc;
			adpcmPred[0] = ((adpcmFrac[0] * 1000 + 0.0001).trunc) % 10;
			adpcmPred[1] = ((adpcmFrac[1] * 1000 + 0.0001).trunc) % 10;
			adpcmDither[0] = ((adpcmFrac[0] * 10000 + 0.0001).trunc) % 10;
			adpcmDither[1] = ((adpcmFrac[1] * 10000 + 0.0001).trunc) % 10;
			adpcmNS[0] = ((adpcmFrac[0] * 100000 + 0.0001).trunc) % 10;
			adpcmNS[1] = ((adpcmFrac[1] * 100000 + 0.0001).trunc) % 10;
			// Select.ar tables
			noise[0] = PinkNoise.ar(Select.ar(bdInt[0], [0,0,0,0,0,0, 0.006,0.003, 0.008,0,0,0, 0.0016,0,0,0, 0.00016]));
			noise[1] = PinkNoise.ar(Select.ar(bdInt[1], [0,0,0,0,0,0, 0.006,0.003, 0.008,0,0,0, 0.0016,0,0,0, 0.00016]));
			baseSR[0] = Select.ar(bdInt[0], [0,0,0,0,0,0, 22000,0, 16000,0,0,0, 31250,0,0,0, 39000]);
			baseSR[1] = (Select.ar(bdInt[1], [0,0,0,0,0,0, 22000,0, 16000,0,0,0, 31250,0,0,0, 39000])) * 1.002;
			adpcmSR[0] = Select.ar(adpcmBits[0] - 4, [14000, 16000, 16000]);
			adpcmSR[1] = Select.ar(adpcmBits[1] - 4, [14000, 16000, 16000]);
			baseSR[0] = Select.ar(isAdpcm[0], [baseSR[0], adpcmSR[0]]);
			baseSR[1] = Select.ar(isAdpcm[1], [baseSR[1], adpcmSR[1]]);
			fixFilt[0] = Select.ar(bdInt[0], [0,0,0,0,0,0, 9000,8000, 7000,0,0,0, 12800,0,0,0, 18000]);
			fixFilt[1] = (Select.ar(bdInt[1], [0,0,0,0,0,0, 9000,8000, 7000,0,0,0, 12800,0,0,0, 18000])) * 1.04;
			interpVals[0] = Select.ar(bdInt[0], [0,0,0,0,0,0, 1,1, 1,0,0,0, 2,0,0,0, 3]);
			interpVals[1] = Select.ar(bdInt[1], [0,0,0,0,0,0, 1,1, 1,0,0,0, 2,0,0,0, 3]);
			jitterAmt[0] = Select.ar(bdInt[0], [0,0,0,0,0,0, 0.02,0.015, 0.02,0,0,0, 0.004,0,0,0, 0.001]);
			jitterAmt[1] = Select.ar(bdInt[1], [0,0,0,0,0,0, 0.02,0.015, 0.02,0,0,0, 0.004,0,0,0, 0.001]);
			bleedAmt[0] = Select.ar(bdInt[0], [0,0,0,0,0,0, 0.002,0.0015, 0.0025,0,0,0, 0.001,0,0,0, 0]);
			bleedAmt[1] = Select.ar(bdInt[1], [0,0,0,0,0,0, 0.002,0.0015, 0.0025,0,0,0, 0.001,0,0,0, 0]);
			
			inputL_sig = inputL_sig + (noise[0] * 0.5); 
			inputR_sig = inputR_sig + (noise[1] * 0.5);

			yellow[0] = DC.ar(0); yellow[1] = DC.ar(0);
            
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
			
			drift[0] = LFDNoise3.ar(0.08, driftAmt); drift[1] = LFDNoise3.ar(0.08, driftAmt);

			mod_val_speed[0]=((sources_sig*mod_speedL_Amts).sum * dest_gains[0]).tanh.lag(0.01);
			mod_val_speed[1]=((sources_sig*mod_speedR_Amts).sum * dest_gains[7]).tanh.lag(0.01);
            
            baseSpeed[0] = (speedL + mod_val_speed[0] + drift[0]).lag(0.01);
			baseSpeed[1] = (speedR + mod_val_speed[1] + drift[1]).lag(0.01);

			raw_mod_flip[0] = (sources_sig*mod_flipL_Amts).sum * dest_gains[4];
			raw_mod_flip[1] = (sources_sig*mod_flipR_Amts).sum * dest_gains[11];
			mod_val_flip[0] = Slew.ar(Schmidt.ar(raw_mod_flip[0], 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_flip[1] = Slew.ar(Schmidt.ar(raw_mod_flip[1], 0.6, 0.4), 10000, 20) > 0.01;
            flipLogic[0] = (flipL + mod_val_flip[0]).mod(2); flipLogic[1] = (flipR + mod_val_flip[1]).mod(2);
			flipState[0] = flipLogic[0]; flipState[1] = flipLogic[1];

			finalRate[0] = Select.ar(flipLogic[0] > 0.5, [baseSpeed[0], baseSpeed[0] * -1]);
			finalRate[1] = Select.ar(flipLogic[1] > 0.5, [baseSpeed[1], baseSpeed[1] * -1]);
			
			end[0] = (loopLenL.lag(0.1) * 48000).min(BufFrames.kr(bufL));
			end[1] = (loopLenR.lag(0.1) * 48000).min(BufFrames.kr(bufR));
            
			raw_mod_skip[0] = (sources_sig*mod_skipL_Amts).sum * dest_gains[5];
			raw_mod_skip[1] = (sources_sig*mod_skipR_Amts).sum * dest_gains[12];
			mod_val_skip[0] = Slew.ar(Schmidt.ar(raw_mod_skip[0], 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_skip[1] = Slew.ar(Schmidt.ar(raw_mod_skip[1], 0.6, 0.4), 10000, 20) > 0.01;
			
			gateSkip[0] = ((skipL + mod_val_skip[0]) > 0.5); gateSkip[1] = ((skipR + mod_val_skip[1]) > 0.5);
			minTime = 0.001; maxTime = 0.350;
			lower[0] = stutterRateL - (stutterChaosL * (stutterRateL - minTime));
			upper[0] = stutterRateL + (stutterChaosL * (maxTime - stutterRateL));
			demand[0] = Dwhite(lower[0], upper[0]);
			autoTrig[0] = TDuty.ar(demand[0], reset: K2A.ar(gateSkip[0])) * K2A.ar(gateSkip[0]);
			lower[1] = stutterRateR - (stutterChaosR * (stutterRateR - minTime));
			upper[1] = stutterRateR + (stutterChaosR * (maxTime - stutterRateR));
			demand[1] = Dwhite(lower[1], upper[1]);
			autoTrig[1] = TDuty.ar(demand[1], reset: K2A.ar(gateSkip[1])) * K2A.ar(gateSkip[1]);
			
			finalJumpTrig[0] = Select.ar(skipModeL, [Changed.ar(K2A.ar(gateSkip[0])), autoTrig[0]]);
			finalJumpTrig[1] = Select.ar(skipModeR, [Changed.ar(K2A.ar(gateSkip[1])), autoTrig[1]]);
			
			rawPtr[0] = fb_yellow[0] * end[0]; rawPtr[1] = fb_yellow[1] * end[1];
			freezePos[0] = Latch.ar(rawPtr[0], K2A.ar(gateSkip[0])); freezePos[1] = Latch.ar(rawPtr[1], K2A.ar(gateSkip[1]));
			
			resetPos[0] = Select.ar(skipModeL, [TRand.ar(0, end[0], finalJumpTrig[0]), freezePos[0]]);
			resetPos[1] = Select.ar(skipModeR, [TRand.ar(0, end[1], finalJumpTrig[1]), freezePos[1]]);
			
			ptr[0] = Phasor.ar(finalJumpTrig[0], finalRate[0] * BufRateScale.kr(bufL), 0, end[0], resetPos[0]);
			ptr[1] = Phasor.ar(finalJumpTrig[1], finalRate[1] * BufRateScale.kr(bufR), 0, end[1], resetPos[1]);
			
			yellow[0] = (ptr[0] / end[0].max(1)); yellow[1] = (ptr[1] / end[1].max(1));
			
            // Bleed Logic
			// Bleed amounts already set via Select.ar tables above
			bleed[0] = SinOsc.ar((baseSR[0] * finalRate[0].abs).clip(20, 20000)) * bleedAmt[0];
			bleed[1] = SinOsc.ar((baseSR[1] * finalRate[1].abs).clip(20, 20000)) * bleedAmt[1];

			read[0] = BufRd.ar(1, bufL, ptr[0], loop:1, interpolation: interpVals[0]);
			read[1] = BufRd.ar(1, bufR, ptr[1], loop:1, interpolation: interpVals[1]);
			
            // [FIX] Bleed is NOT mixed here anymore. It's sent to Out via b_bleed.
            // read[0] = read[0] + bleed[0] + (noise[0] * 0.5); // OLD
            read[0] = read[0] + (noise[0] * 0.5); // NEW: Only noise here
            read[1] = read[1] + (noise[1] * 0.5);

            // Coco Env Logic
            relCo[0] = cocoSlewL.linexp(0, 1, 0.05, 2.5); relCo[1] = cocoSlewR.linexp(0, 1, 0.05, 2.5);
            atkCo[0] = (relCo[0] * 0.1).max(0.002); atkCo[1] = (relCo[1] * 0.1).max(0.002);
            envFb[0] = Amplitude.kr(LeakDC.ar(read[0]), atkCo[0], relCo[0]) * 2.0; 
            envFb[1] = Amplitude.kr(LeakDC.ar(read[1]), atkCo[1], relCo[1]) * 2.0;
            src11_ar = Select.ar(coco1OutMode, [K2A.ar(envFb[0]), read[0]]);
            src12_ar = Select.ar(coco2OutMode, [K2A.ar(envFb[1]), read[1]]);
            
            // Calc Modulations for Output
			mod_val_amp[0]=((sources_sig*mod_ampL_Amts).sum * dest_gains[1]).tanh.lag(slew_amp);
			mod_val_amp[1]=((sources_sig*mod_ampR_Amts).sum * dest_gains[8]).tanh.lag(slew_amp);
			mod_val_fb[0]=((sources_sig*mod_fbL_Amts).sum * dest_gains[2]).tanh.lag(slew_amp);
			mod_val_fb[1]=((sources_sig*mod_fbR_Amts).sum * dest_gains[9]).tanh.lag(slew_amp);
			mod_val_filt[0]=((sources_sig*mod_filtL_Amts).sum * dest_gains[3]).tanh.lag(slew_misc);
			mod_val_filt[1]=((sources_sig*mod_filtR_Amts).sum * dest_gains[10]).tanh.lag(slew_misc);
			mod_val_vol[0]=((sources_sig*mod_volL_Amts).sum * dest_gains[20]).tanh.lag(slew_amp);
			mod_val_vol[1]=((sources_sig*mod_volR_Amts).sum * dest_gains[21]).tanh.lag(slew_amp);
			mod_val_audioIn[0] = LeakDC.ar((sources_sig*mod_audioInL_Amts).sum);
			mod_val_audioIn[0] = (mod_val_audioIn[0] * dest_gains[22] * 4.0).tanh;
			mod_val_audioIn[1] = LeakDC.ar((sources_sig*mod_audioInR_Amts).sum);
			mod_val_audioIn[1] = (mod_val_audioIn[1] * dest_gains[23] * 4.0).tanh;
            
			raw_mod_rec[0] = (sources_sig*mod_recL_Amts).sum * dest_gains[6];
			raw_mod_rec[1] = (sources_sig*mod_recR_Amts).sum * dest_gains[13];
			mod_val_rec[0] = Slew.ar(Schmidt.ar(raw_mod_rec[0], 0.6, 0.4), 10000, 20) > 0.01;
			mod_val_rec[1] = Slew.ar(Schmidt.ar(raw_mod_rec[1], 0.6, 0.4), 10000, 20) > 0.01;

			recLogic[0] = (recL + mod_val_rec[0]).mod(2); recLogic[1] = (recR + mod_val_rec[1]).mod(2);
			gateRec[0] = Select.ar(recLogic[0] > 0.5, [K2A.ar(0), K2A.ar(1)]);
			gateRec[1] = Select.ar(recLogic[1] > 0.5, [K2A.ar(0), K2A.ar(1)]);

			dry[0] = inputL_sig * (volInL + mod_val_amp[0]).clip(0, 2);
			dry[1] = inputR_sig * (volInR + mod_val_amp[1]).clip(0, 2);

			feedback[0] = read[0] * (fbL + mod_val_fb[0]).clip(0, 1.2) * 1.15;
			feedback[1] = read[1] * (fbR + mod_val_fb[1]).clip(0, 1.2) * 1.15;
			feedback[0] = LPF.ar(feedback[0], fixFilt[0]).softclip;
			feedback[1] = LPF.ar(feedback[1], fixFilt[1]).softclip;
			
			write[0] = ((dry[0]) + mod_val_audioIn[0]) * gateRec[0] + (feedback[0]);
			write[1] = ((dry[1]) + mod_val_audioIn[1]) * gateRec[1] + (feedback[1]);
			
			// [v2.08] QUANTIZATION ENGINE
			quantBits[0] = Select.ar(bdInt[0], [0,0,0,0,0,0, 8,0, 8,0,0,0, 12,0,0,0, 16]);
			quantBits[1] = Select.ar(bdInt[1], [0,0,0,0,0,0, 8,0, 8,0,0,0, 12,0,0,0, 16]);
			
			// Noise Shaping feedback
			nsFb[0] = Select.ar(Select.ar(isUlaw[0], [adpcmNS[0], ulawNS[0]]), [DC.ar(0), nsError[0] * 0.5, (nsError[0] * 1.0) - (nsError[1] * 0.25)]);
			nsFb[1] = Select.ar(Select.ar(isUlaw[1], [adpcmNS[1], ulawNS[1]]), [DC.ar(0), nsError[2] * 0.5, (nsError[2] * 1.0) - (nsError[3] * 0.25)]);
			
			// PATH 1: Linear
			writeQ[0] = write[0].round(0.5.pow(quantBits[0]));
			writeQ[1] = write[1].round(0.5.pow(quantBits[1]));
			
			// PATH 2: u-law with TPDF dither
			ulawDitherSig[0] = Select.ar(ulawDither[0], [DC.ar(0), (WhiteNoise.ar(1) + WhiteNoise.ar(1)) * (0.5.pow(9)) * 0.5]);
			ulawDitherSig[1] = Select.ar(ulawDither[1], [DC.ar(0), (WhiteNoise.ar(1) + WhiteNoise.ar(1)) * (0.5.pow(9)) * 0.5]);
			ulawIn[0] = write[0] + nsFb[0] + ulawDitherSig[0];
			ulawIn[1] = write[1] + nsFb[1] + ulawDitherSig[1];
			companded[0] = (ulawIn[0].sign * ((1 + 255 * ulawIn[0].abs).log / 256.log)).clip(-1, 1);
			companded[1] = (ulawIn[1].sign * ((1 + 255 * ulawIn[1].abs).log / 256.log)).clip(-1, 1);
			qComp[0] = (companded[0] * 127 + 127).round(1).clip(0, 255);
			qComp[1] = (companded[1] * 127 + 127).round(1).clip(0, 255);
			ulawIdx[0] = (qComp[0] - 127) / 127;
			ulawIdx[1] = (qComp[1] - 127) / 127;
			ulawExp[0] = ulawIdx[0].sign * ((256.pow(ulawIdx[0].abs) - 1) / 255);
			ulawExp[1] = ulawIdx[1].sign * ((256.pow(ulawIdx[1].abs) - 1) / 255);
			
			// PATH 3: ADPCM with predictor + G.726 leaky step
			adpcmPredVal[0] = Select.ar(adpcmPred[0], [adpcmStateL[0], (2 * adpcmStateL[0]) - adpcmStateL[1]]);
			adpcmPredVal[1] = Select.ar(adpcmPred[1], [adpcmStateR[0], (2 * adpcmStateR[0]) - adpcmStateR[1]]);
			stepBase[0] = Select.ar(adpcmBits[0] - 4, [0.05, 0.025, 0.0125]);
			stepBase[1] = Select.ar(adpcmBits[1] - 4, [0.05, 0.025, 0.0125]);
			stepMin[0] = stepBase[0] * 0.1; stepMin[1] = stepBase[1] * 0.1;
			stepMax[0] = stepBase[0] * 10; stepMax[1] = stepBase[1] * 10;
			adpcmDitherSig[0] = Select.ar(adpcmDither[0], [DC.ar(0), WhiteNoise.ar(adpcmStateL[2] * 0.5)]);
			adpcmDitherSig[1] = Select.ar(adpcmDither[1], [DC.ar(0), WhiteNoise.ar(adpcmStateR[2] * 0.5)]);
			adpcmDiff[0] = write[0] + nsFb[0] + adpcmDitherSig[0] - adpcmPredVal[0];
			adpcmDiff[1] = write[1] + nsFb[1] + adpcmDitherSig[1] - adpcmPredVal[1];
			adpcmQDiff[0] = (adpcmDiff[0] / adpcmStateL[2].max(0.0001)).round(0.5.pow(adpcmBits[0])) * adpcmStateL[2];
			adpcmQDiff[1] = (adpcmDiff[1] / adpcmStateR[2].max(0.0001)).round(0.5.pow(adpcmBits[1])) * adpcmStateR[2];
			adpcmDecoded[0] = adpcmPredVal[0] + adpcmQDiff[0];
			adpcmDecoded[1] = adpcmPredVal[1] + adpcmQDiff[1];
			stepMult[0] = (adpcmQDiff[0].abs / adpcmStateL[2].max(0.0001)).clip(0, 10) * 0.3 + 0.8;
			stepMult[1] = (adpcmQDiff[1].abs / adpcmStateR[2].max(0.0001)).clip(0, 10) * 0.3 + 0.8;
			newStep[0] = (adpcmStateL[2] * 0.98 + (adpcmStateL[2] * stepMult[0] - adpcmStateL[2]) * 0.5).clip(stepMin[0], stepMax[0]);
			newStep[1] = (adpcmStateR[2] * 0.98 + (adpcmStateR[2] * stepMult[1] - adpcmStateR[2]) * 0.5).clip(stepMin[1], stepMax[1]);
			
			// SELECT FINAL PATH
			writeQ[0] = Select.ar(isUlaw[0], [Select.ar(isAdpcm[0], [write[0].round(0.5.pow(quantBits[0])), adpcmDecoded[0]]), ulawExp[0]]);
			writeQ[1] = Select.ar(isUlaw[1], [Select.ar(isAdpcm[1], [write[1].round(0.5.pow(quantBits[1])), adpcmDecoded[1]]), ulawExp[1]]);
			
			// SR REDUCTION
			writeQ[0] = Select.ar(is8L + isUlaw[0] + isAdpcm[0], [writeQ[0], Latch.ar(writeQ[0], Impulse.ar((baseSR[0] * finalRate[0].abs).clip(100, 48000) * (1 + WhiteNoise.ar(jitterAmt[0]))))]);
			writeQ[1] = Select.ar(is8R + isUlaw[1] + isAdpcm[1], [writeQ[1], Latch.ar(writeQ[1], Impulse.ar((baseSR[1] * finalRate[1].abs).clip(100, 48000) * (1 + WhiteNoise.ar(jitterAmt[1]))))]);
			
			BufWr.ar(writeQ[0], bufL, ptr[0]); BufWr.ar(writeQ[1], bufR, ptr[1]);

			LocalOut.ar([p1, p2, p3, p4, p5, p6, yellow[0], yellow[1], src11_ar, src12_ar,
				nsError[0], nsError[1], nsError[2], nsError[3],
				adpcmDecoded[0], adpcmDecoded[1], newStep[0], newStep[1], adpcmStateL[0], adpcmStateR[0]]);
			osc_trigger = Impulse.kr(30);
			SendReply.kr(osc_trigger, '/update', [A2K.kr(ptr[0]/end[0].max(1)), A2K.kr(ptr[1]/end[1].max(1)), A2K.kr(gateRec[0]), A2K.kr(gateRec[1]), K2A.ar(flipState[0]), K2A.ar(flipState[1]), K2A.ar((skipL + mod_val_skip[0]).clip(0,1)), K2A.ar((skipR + mod_val_skip[1]).clip(0,1)), A2K.kr(out1), A2K.kr(out2), A2K.kr(out3), A2K.kr(out4), A2K.kr(out5), A2K.kr(out6), envL, envR, A2K.kr(yellow[0]), A2K.kr(yellow[1]), K2A.ar(finalRate[0]), K2A.ar(finalRate[1]), A2K.kr(Amplitude.ar(read[0]*ampL)), A2K.kr(Amplitude.ar(read[1]*ampR)), A2K.kr(src11_ar), A2K.kr(src12_ar)]);

            // BRIDGE: OUTPUT TO BUSES
			Out.ar(bus_tape_out, [read[0], read[1]]);
			Out.ar(bus_mon_out, [clean_preamp[0] + mod_val_audioIn[0], clean_preamp[1] + mod_val_audioIn[1]]);
			Out.ar(bus_bleed_out, [bleed[0], bleed[1]]); // [NEW] Send Bleed separately
			Out.kr(bus_mvol_out, [mod_val_vol[0], mod_val_vol[1]]);
			Out.kr(bus_mfilt_out, [mod_val_filt[0], mod_val_filt[1]]);

		}).add;

		// -----------------------------------------------------------
		// SYNTH 2: OUT (Mix, Filter, Amp)
		// -----------------------------------------------------------
		SynthDef(\NcocoOut, {
            arg out, bus_tape_in, bus_mon_in, bus_bleed_in, // Added bleed in
            bus_mvol_in, bus_mfilt_in,
            filtL=0, filtR=0, ampL=1.0, ampR=1.0, panL= -0.5, panR=0.5, monitorLevel=0,
            bleedPost=0, // [NEW] Param
            djFilterType=0, // [v2.04] 0=Classic LPF/HPF, 1=DFM1
            dfm1Gain=0.15; // [v2.06] DFM1 gain compensation (2-stage LPF cascade, real-time adjustable)

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

            // [NEW] Bleed Routing Logic
            // Pre-Filter Mix
            sigL = readL + (bleedL * (1.0 - bleedPost));
            sigR = readR + (bleedR * (1.0 - bleedPost));

            // [v2.04] DJ Filter with Classic/DFM1 selection
            // Frequency calculations (identical for both paths)
            lpfFreqL = (totalFiltL.min(0)+1).linexp(0,1,100,20000);
            hpfFreqL = totalFiltL.max(0).linexp(0,1,20,15000);
            lpfFreqR = (totalFiltR.min(0)+1).linexp(0,1,100,20000);
            hpfFreqR = totalFiltR.max(0).linexp(0,1,20,15000);

            // Classic path (original LPF/HPF, 12dB/oct each)
            classicL = HPF.ar(LPF.ar(sigL, lpfFreqL), hpfFreqL);
            classicR = HPF.ar(LPF.ar(sigR, lpfFreqR), hpfFreqR);

            // [v2.06] DFM1 path: LPF×2 (pre-attenuated) + HPF always Classic
            // L channel
            dfm1L = DFM1.ar(sigL * 0.7, lpfFreqL, 0, 1.0, 0, 0.0003);  // LPF stage 1 (pre-atten -3dB)
            dfm1L = DFM1.ar(dfm1L, lpfFreqL, 0, 1.0, 0, 0.0003);       // LPF stage 2
            dfm1L = HPF.ar(dfm1L, hpfFreqL) * dfm1Gain;                  // HPF Classic (same freq as Classic mode)
            // R channel
            dfm1R = DFM1.ar(sigR * 0.7, lpfFreqR, 0, 1.0, 0, 0.0003);  // LPF stage 1 (pre-atten -3dB)
            dfm1R = DFM1.ar(dfm1R, lpfFreqR, 0, 1.0, 0, 0.0003);       // LPF stage 2
            dfm1R = HPF.ar(dfm1R, hpfFreqR) * dfm1Gain;                  // HPF Classic (same freq as Classic mode)

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
            \bus_bleed_out, b_bleed.index, // [NEW]
            \bus_mvol_out, b_mod_vol.index, \bus_mfilt_out, b_mod_filt.index,
            \ampL, 1.0, \ampR, 1.0 
        ], context.xg, \addToHead);
        
        synth_out = Synth.new(\NcocoOut, [
            \out, context.out_b.index,
            \bus_tape_in, b_tape.index, \bus_mon_in, b_mon.index,
            \bus_bleed_in, b_bleed.index, // [NEW]
            \bus_mvol_in, b_mod_vol.index, \bus_mfilt_in, b_mod_filt.index
        ], context.xg, \addToTail);

        // [FIX v10016] OSCFunc Promiscuous Mode (nil srcID)
		osc_responder = OSCFunc({ |msg| NetAddr("127.0.0.1", 10111).sendMsg("/update", *msg.drop(3)); }, '/update', nil).fix;

        // COMMANDS MAPPING (Split Routing)
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
        this.addCommand("dj_filter_type", "f", { |msg| synth_out.set(\djFilterType, msg[1]) }); // [v2.04]
        this.addCommand("dj_filter_gain", "f", { |msg| synth_out.set(\dfm1Gain, msg[1]) }); // [v2.04]

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
        b_bleed.free; // [NEW]
    }
}
