package com.ryanheise.just_audio

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.sin
import kotlin.math.cos
import kotlin.math.tanh

private const val DENORMAL_FLOOR = 1e-24f
private const val TWO_PI = Math.PI * 2.0
private const val EPICENTER_INTENSITY_HEADROOM = 0.75f
private const val FIXED_BALANCE = 82f
private const val LIMITER_THRESHOLD = 0.96f
private const val LIMITER_RELEASE_MS = 80f
private const val SOFT_CLIP_START = 0.985f

// Frozen signal equations from e895d95; SMART uses only the generated branch.
class LegacyEpicenterDsp(private val sampleRate: Int) {
    private val channels = mutableListOf<ChannelState>()
    private var monoState: MonoState? = null
    private var lastSweepFreq = -1f
    private var lastWidth = -1f
    private var protectionGain = 1f
    private var generatedRawSignal = FloatArray(4096)
    private val derivedState = Derived()

    fun reset() {
        for (i in channels.indices) channels[i].reset()
        monoState?.reset()
        protectionGain = 1f
    }

    fun prepare(channelCount: Int, params: EpicenterParams) = ensureState(channelCount, params)

    fun processInterleaved(input: FloatArray, output: FloatArray, channelCount: Int, params: EpicenterParams,
        sampleCount: Int = min(input.size, output.size), generatedOnly: Boolean = false) {
        if (input.isEmpty() || output.isEmpty() || channelCount <= 0) return
        val frames = sampleCount / channelCount
        if (frames <= 0) return

        if (params.intensity <= 0.01f) {
            if (generatedOnly) output.fill(0f, 0, frames)
            else input.copyInto(output, endIndex = sampleCount)
            return
        }

        ensureState(channelCount, params)
        val mono = monoState ?: return
        val originalSignal = input
        if (generatedRawSignal.size < frames) generatedRawSignal = FloatArray(frames)
        val intensityNorm = clamp(params.intensity, 0f, 100f) / 100f * EPICENTER_INTENSITY_HEADROOM
        val balanceNorm = FIXED_BALANCE / 100f
        val widthNorm = clamp(params.width, 0f, 100f) / 100f
        val volumeGain = clamp(params.volume / 100f, 0f, 1f)
        val synthAmount = intensityNorm * 1.84f
        val bassProgramAmount = 0.68f + balanceNorm * 0.38f
        val lowMidBodyAmount = 0.12f + balanceNorm * 0.08f
        val lowMidDipAmount = (0.08f + intensityNorm * 0.16f) * (0.45f + widthNorm * 0.3f)
        val gateHoldSamples = (sampleRate * (0.025f + intensityNorm * 0.06f)).toInt()

        for (i in 0 until frames) {
            val base = i * channelCount
            val left = originalSignal[base]
            val right = if (channelCount > 1) originalSignal[base + 1] else left
            val monoSample = floor((left + right) * 0.5f)
            val diff = floor((left - right) * 0.5f)
            val monoBand = mono.band60.process(monoSample) +
                mono.band80.process(monoSample) * 0.68f +
                mono.band110.process(monoSample) * 0.42f
            val weightedDetector = floor(monoBand * 0.6f + mono.monoLowpass.process(monoSample) * 0.12f)
            val detectorEnv = mono.detectorEnv.process(weightedDetector)
            val monoEnv = mono.monoEnv.process(monoSample)
            val diffEnv = mono.diffEnv.process(mono.diffHighpass.process(diff))

            if (mono.lastDetector <= 0f && weightedDetector > 0f) mono.flipState *= -1f
            mono.lastDetector = weightedDetector

            val rawHalf = mono.flipState * detectorEnv
            var synth = mono.synthHighpass.process(rawHalf)
            synth = mono.synthLowpass.process(synth)
            val gateTarget = computeGate(monoEnv, diffEnv, detectorEnv)
            val gateValue = mono.gateEnv.process(gateTarget)
            if (gateTarget > 0.3f) {
                mono.holdSamples = gateHoldSamples
            } else if (mono.holdSamples > 0) {
                mono.holdSamples--
            }
            val remixGate = max(gateValue, if (mono.holdSamples > 0) 0.45f else 0f)
            val leveledSynth = mono.synthLevelEnv.process(synth) * sign(synth)
            val protectedSynth = tanh((synth * 0.65f + leveledSynth * 0.35f) * 2.1f) * 0.72f
            generatedRawSignal[i] = floor(protectedSynth * synthAmount * remixGate)
        }

        if (generatedOnly) {
            for (i in 0 until frames) output[i] = channels[0].subLowpass.process(generatedRawSignal[i])
            return
        }

        for (ch in 0 until channelCount) {
            val state = channels[ch]
            for (i in 0 until frames) {
                val index = i * channelCount + ch
                val originalSample = floor(originalSignal[index])
                val voicePath = state.voiceHighpass.process(originalSample)
                val voicePresence = state.voiceEnv.process(voicePath)
                val voiceProtection = max(0.5f, 1f - voicePresence * (0.85f + intensityNorm * 0.3f))
                val bassProgram = state.bassLowpass.process(originalSample)
                val body = state.lowMidBody.process(originalSample)
                val dip = state.lowMidDip.process(originalSample)
                val shapedBassProgram = bassProgram * bassProgramAmount +
                    body * lowMidBodyAmount * (0.45f + voiceProtection * 0.55f) -
                    dip * lowMidDipAmount
                val generatedSignal = state.subLowpass.process(generatedRawSignal[i])
                val originalProcessingSignal = voicePath + shapedBassProgram
                var mixed = originalProcessingSignal + generatedSignal
                mixed *= volumeGain * (0.94f + voiceProtection * 0.06f)
                mixed = tanh(mixed * 0.94f) / tanh(0.94f)
                val currentDspOutput = floor(state.outputDcHighpass.process(mixed))
                output[index] = if (params.peakProtectionEnabled) {
                    currentDspOutput
                } else {
                    currentDspOutput.coerceIn(-1f, 1f)
                }
            }
        }

        if (params.peakProtectionEnabled) {
            applyPeakProtection(output, frames, channelCount)
        } else {
            protectionGain = 1f
        }
    }

    private fun applyPeakProtection(output: FloatArray, frames: Int, channelCount: Int) {
        val releaseCoeff = coeffFromMs(LIMITER_RELEASE_MS)
        for (i in 0 until frames) {
            val base = i * channelCount
            var peak = 0f
            for (ch in 0 until channelCount) {
                peak = max(peak, abs(output[base + ch]))
            }

            val targetGain = if (peak > LIMITER_THRESHOLD) LIMITER_THRESHOLD / peak else 1f
            protectionGain = if (targetGain < protectionGain) {
                targetGain
            } else {
                targetGain + releaseCoeff * (protectionGain - targetGain)
            }

            if (protectionGain < 0.9999f) {
                for (ch in 0 until channelCount) {
                    val index = base + ch
                    output[index] = softClipLastDefense(output[index] * protectionGain)
                }
            } else {
                protectionGain = 1f
                for (ch in 0 until channelCount) {
                    val index = base + ch
                    val sample = output[index]
                    output[index] = if (abs(sample) > SOFT_CLIP_START) softClipLastDefense(sample) else sample
                }
            }
        }
    }

    private fun softClipLastDefense(sample: Float): Float {
        val magnitude = abs(sample)
        if (magnitude <= SOFT_CLIP_START) return sample
        val normalized = ((magnitude - SOFT_CLIP_START) / (1f - SOFT_CLIP_START)).coerceIn(0f, 1f)
        val curved = normalized - (normalized * normalized * normalized) / 3f
        val defended = SOFT_CLIP_START + curved * (1f - SOFT_CLIP_START)
        return sign(sample) * min(defended, 1f)
    }

    private fun ensureState(channelCount: Int, params: EpicenterParams) {
        while (channels.size < channelCount) channels.add(createChannelState(params))
        if (monoState == null) {
            monoState = createMonoState(params)
            lastSweepFreq = params.sweepFreq
            lastWidth = params.width
            return
        }
        if (params.sweepFreq == lastSweepFreq && params.width == lastWidth) return

        val d = derived(params.sweepFreq, params.width)
        for (i in channels.indices) {
            val state = channels[i]
            state.voiceHighpass.update("highpass", d.crossoverHz, 0.707f)
            state.bassLowpass.update("lowpass", d.crossoverHz * 1.15f, 0.707f)
            state.lowMidBody.update("bandpass", d.bodyHz, 0.85f)
            state.lowMidDip.update("bandpass", d.bodyHz * 1.18f, 1.1f)
            state.subLowpass.update("lowpass", d.subTopHz, 0.707f)
        }
        monoState?.let { state ->
            state.band60.update("bandpass", d.detector60, 1.35f)
            state.band80.update("bandpass", d.detector80, 1.55f)
            state.band110.update("bandpass", d.detector110, 1.8f)
            state.synthHighpass.update("highpass", d.synthHighHz, 0.707f)
            state.synthLowpass.update("lowpass", d.synthLowHz, 0.707f)
        }
        lastSweepFreq = params.sweepFreq
        lastWidth = params.width
    }

    private fun createChannelState(params: EpicenterParams): ChannelState {
        val d = derived(params.sweepFreq, params.width)
        return ChannelState(
            voiceHighpass = Biquad("highpass", d.crossoverHz, sampleRate, 0.707f),
            bassLowpass = Biquad("lowpass", d.crossoverHz * 1.15f, sampleRate, 0.707f),
            lowMidBody = Biquad("bandpass", d.bodyHz, sampleRate, 0.85f),
            lowMidDip = Biquad("bandpass", d.bodyHz * 1.18f, sampleRate, 1.1f),
            subLowpass = Biquad("lowpass", d.subTopHz, sampleRate, 0.707f),
            outputDcHighpass = Biquad("highpass", 18f, sampleRate, 0.707f),
            voiceEnv = Envelope(coeffFromMs(6f), coeffFromMs(110f)),
        )
    }

    private fun createMonoState(params: EpicenterParams): MonoState {
        val d = derived(params.sweepFreq, params.width)
        return MonoState(
            band60 = Biquad("bandpass", d.detector60, sampleRate, 1.35f),
            band80 = Biquad("bandpass", d.detector80, sampleRate, 1.55f),
            band110 = Biquad("bandpass", d.detector110, sampleRate, 1.8f),
            monoLowpass = Biquad("lowpass", 120f, sampleRate, 0.707f),
            diffHighpass = Biquad("highpass", 140f, sampleRate, 0.707f),
            synthHighpass = Biquad("highpass", d.synthHighHz, sampleRate, 0.707f),
            synthLowpass = Biquad("lowpass", d.synthLowHz, sampleRate, 0.707f),
            detectorEnv = Envelope(coeffFromMs(7f), coeffFromMs(95f)),
            monoEnv = Envelope(coeffFromMs(12f), coeffFromMs(160f)),
            diffEnv = Envelope(coeffFromMs(12f), coeffFromMs(160f)),
            gateEnv = Envelope(coeffFromMs(25f), coeffFromMs(240f)),
            synthLevelEnv = Envelope(coeffFromMs(18f), coeffFromMs(180f)),
        )
    }

    private fun derived(sweepFreq: Float, width: Float): Derived {
        val sweepNorm = (clamp(sweepFreq, 27f, 63f) - 27f) / 36f
        val widthNorm = clamp(width, 0f, 100f) / 100f
        derivedState.detector60 = 55f + sweepNorm * 10f
        derivedState.detector80 = 75f + sweepNorm * 10f
        derivedState.detector110 = 100f + sweepNorm * 15f
        derivedState.crossoverHz = 105f + widthNorm * 30f
        derivedState.bodyHz = 95f + sweepNorm * 20f
        derivedState.subTopHz = 58f + widthNorm * 10f
        derivedState.synthLowHz = 55f + widthNorm * 10f
        derivedState.synthHighHz = 22f + sweepNorm * 6f
        return derivedState
    }

    private fun computeGate(monoEnv: Float, diffEnv: Float, detectorEnv: Float): Float {
        val musicRatio = diffEnv / (monoEnv + 1e-6f)
        val detectorActivity = min(1f, detectorEnv * 9.5f)
        val musicScore = clamp(musicRatio * 3.2f, 0f, 1f)
        return detectorActivity * (0.25f + musicScore * 0.75f)
    }

    private fun coeffFromMs(ms: Float): Float {
        val samples = max(1f, ms * sampleRate / 1000f)
        return exp(-1f / samples)
    }

    private fun floor(value: Float): Float = if (!value.isFinite() || abs(value) < DENORMAL_FLOOR) 0f else value
    private fun clamp(value: Float, minValue: Float, maxValue: Float): Float = max(minValue, min(maxValue, value))
}

private class Derived(
    var detector60: Float = 0f,
    var detector80: Float = 0f,
    var detector110: Float = 0f,
    var crossoverHz: Float = 0f,
    var bodyHz: Float = 0f,
    var subTopHz: Float = 0f,
    var synthLowHz: Float = 0f,
    var synthHighHz: Float = 0f,
)

private data class ChannelState(
    val voiceHighpass: Biquad,
    val bassLowpass: Biquad,
    val lowMidBody: Biquad,
    val lowMidDip: Biquad,
    val subLowpass: Biquad,
    val outputDcHighpass: Biquad,
    val voiceEnv: Envelope,
) {
    fun reset() {
        voiceHighpass.reset(); bassLowpass.reset(); lowMidBody.reset()
        lowMidDip.reset(); subLowpass.reset(); outputDcHighpass.reset(); voiceEnv.reset()
    }
}

private data class MonoState(
    val band60: Biquad,
    val band80: Biquad,
    val band110: Biquad,
    val monoLowpass: Biquad,
    val diffHighpass: Biquad,
    val synthHighpass: Biquad,
    val synthLowpass: Biquad,
    val detectorEnv: Envelope,
    val monoEnv: Envelope,
    val diffEnv: Envelope,
    val gateEnv: Envelope,
    val synthLevelEnv: Envelope,
    var lastDetector: Float = 0f,
    var flipState: Float = 1f,
    var holdSamples: Int = 0,
) {
    fun reset() {
        band60.reset(); band80.reset(); band110.reset(); monoLowpass.reset()
        diffHighpass.reset(); synthHighpass.reset(); synthLowpass.reset()
        detectorEnv.reset(); monoEnv.reset(); diffEnv.reset(); gateEnv.reset(); synthLevelEnv.reset()
        lastDetector = 0f; flipState = 1f; holdSamples = 0
    }
}

private class Envelope(private val attackCoeff: Float, private val releaseCoeff: Float) {
    private var value = 0f
    fun reset() { value = 0f }

    fun process(input: Float): Float {
        val x = abs(input)
        val coeff = if (x > value) attackCoeff else releaseCoeff
        value = x + coeff * (value - x)
        return value
    }
}

private class Biquad(type: String, freq: Float, private val sampleRate: Int, q: Float) {
    private var b0 = 0f
    private var b1 = 0f
    private var b2 = 0f
    private var a1 = 0f
    private var a2 = 0f
    private var x1 = 0f
    private var x2 = 0f
    private var y1 = 0f
    private var y2 = 0f
    fun reset() { x1 = 0f; x2 = 0f; y1 = 0f; y2 = 0f }

    init {
        update(type, freq, q)
    }

    fun update(type: String, freq: Float, q: Float) {
        val clampedFreq = max(10f, min(freq, sampleRate * 0.45f))
        val clampedQ = max(0.2f, min(q, 12f))
        val omega = TWO_PI * clampedFreq / sampleRate
        val sinOmega = sin(omega).toFloat()
        val cosOmega = cos(omega).toFloat()
        val alpha = sinOmega / (2f * clampedQ)
        var nb0 = 0f
        var nb1 = 0f
        var nb2 = 0f
        var na0 = 1f
        var na1 = 0f
        var na2 = 0f

        when (type) {
            "lowpass" -> {
                nb0 = (1f - cosOmega) * 0.5f
                nb1 = 1f - cosOmega
                nb2 = (1f - cosOmega) * 0.5f
                na0 = 1f + alpha
                na1 = -2f * cosOmega
                na2 = 1f - alpha
            }
            "highpass" -> {
                nb0 = (1f + cosOmega) * 0.5f
                nb1 = -(1f + cosOmega)
                nb2 = (1f + cosOmega) * 0.5f
                na0 = 1f + alpha
                na1 = -2f * cosOmega
                na2 = 1f - alpha
            }
            "bandpass" -> {
                nb0 = alpha
                nb1 = 0f
                nb2 = -alpha
                na0 = 1f + alpha
                na1 = -2f * cosOmega
                na2 = 1f - alpha
            }
        }
        b0 = nb0 / na0
        b1 = nb1 / na0
        b2 = nb2 / na0
        a1 = na1 / na0
        a2 = na2 / na0
    }

    fun process(sample: Float): Float {
        val clean = floor(sample)
        val y0 = b0 * clean + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = floor(x1)
        x1 = clean
        y2 = floor(y1)
        y1 = floor(y0)
        return floor(y0)
    }

    private fun floor(value: Float): Float = if (abs(value) < DENORMAL_FLOOR) 0f else value
}
