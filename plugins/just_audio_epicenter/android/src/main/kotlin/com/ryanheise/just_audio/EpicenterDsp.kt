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

data class EpicenterParams(
    val sweepFreq: Float = 45f,
    val width: Float = 50f,
    val intensity: Float = 50f,
    val balance: Float = 50f,
    val volume: Float = 100f,
)

class EpicenterDsp(private val sampleRate: Int) {
    private val channels = mutableListOf<ChannelState>()
    private var monoState: MonoState? = null
    private var lastSweepFreq = -1f
    private var lastWidth = -1f

    fun reset() {
        channels.clear()
        monoState = null
        lastSweepFreq = -1f
        lastWidth = -1f
    }

    fun processInterleaved(input: FloatArray, output: FloatArray, channelCount: Int, params: EpicenterParams) {
        if (input.isEmpty() || output.isEmpty() || channelCount <= 0) return
        val frames = min(input.size, output.size) / channelCount
        if (frames <= 0) return

        if (params.intensity <= 0.01f) {
            input.copyInto(output, endIndex = min(input.size, output.size))
            return
        }

        ensureState(channelCount, params)
        val mono = monoState ?: return
        val subBuffer = FloatArray(frames)
        val intensityNorm = clamp(params.intensity, 0f, 100f) / 100f * EPICENTER_INTENSITY_HEADROOM
        val balanceNorm = clamp(params.balance, 0f, 100f) / 100f
        val widthNorm = clamp(params.width, 0f, 100f) / 100f
        val volumeGain = clamp(params.volume / 100f, 0f, 1f)
        val synthAmount = 0.42f + intensityNorm * 1.28f
        val bassProgramAmount = 0.68f + balanceNorm * 0.38f
        val lowMidBodyAmount = 0.12f + balanceNorm * 0.08f
        val lowMidDipAmount = (0.08f + intensityNorm * 0.16f) * (0.45f + widthNorm * 0.3f)
        val gateHoldSamples = (sampleRate * (0.025f + intensityNorm * 0.06f)).toInt()

        for (i in 0 until frames) {
            val base = i * channelCount
            val left = input[base]
            val right = if (channelCount > 1) input[base + 1] else left
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
            subBuffer[i] = floor(protectedSynth * synthAmount * remixGate)
        }

        for (ch in 0 until channelCount) {
            val state = channels[ch]
            for (i in 0 until frames) {
                val index = i * channelCount + ch
                val sample = floor(input[index])
                val voicePath = state.voiceHighpass.process(sample)
                val voicePresence = state.voiceEnv.process(voicePath)
                val voiceProtection = max(0.5f, 1f - voicePresence * (0.85f + intensityNorm * 0.3f))
                val bassProgram = state.bassLowpass.process(sample)
                val body = state.lowMidBody.process(sample)
                val dip = state.lowMidDip.process(sample)
                val shapedBassProgram = bassProgram * bassProgramAmount +
                    body * lowMidBodyAmount * (0.45f + voiceProtection * 0.55f) -
                    dip * lowMidDipAmount
                val generatedSub = state.subLowpass.process(subBuffer[i]) * (0.4f + voiceProtection * 0.6f)
                var mixed = voicePath + shapedBassProgram + generatedSub
                mixed *= volumeGain * (0.94f + voiceProtection * 0.06f)
                mixed = tanh(mixed * 0.94f) / tanh(0.94f)
                output[index] = floor(state.outputDcHighpass.process(mixed))
            }
        }
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
        channels.forEach { state ->
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
        return Derived(
            detector60 = 55f + sweepNorm * 10f,
            detector80 = 75f + sweepNorm * 10f,
            detector110 = 100f + sweepNorm * 15f,
            crossoverHz = 105f + widthNorm * 30f,
            bodyHz = 95f + sweepNorm * 20f,
            subTopHz = 58f + widthNorm * 10f,
            synthLowHz = 55f + widthNorm * 10f,
            synthHighHz = 22f + sweepNorm * 6f,
        )
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

    private fun floor(value: Float): Float = if (abs(value) < DENORMAL_FLOOR) 0f else value
    private fun clamp(value: Float, minValue: Float, maxValue: Float): Float = max(minValue, min(maxValue, value))
}

private data class Derived(
    val detector60: Float,
    val detector80: Float,
    val detector110: Float,
    val crossoverHz: Float,
    val bodyHz: Float,
    val subTopHz: Float,
    val synthLowHz: Float,
    val synthHighHz: Float,
)

private data class ChannelState(
    val voiceHighpass: Biquad,
    val bassLowpass: Biquad,
    val lowMidBody: Biquad,
    val lowMidDip: Biquad,
    val subLowpass: Biquad,
    val outputDcHighpass: Biquad,
    val voiceEnv: Envelope,
)

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
)

private class Envelope(private val attackCoeff: Float, private val releaseCoeff: Float) {
    private var value = 0f

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