package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

const val TONE_BAND_COUNT = 5

object ToneControlsProcessorController {
    val processor = ToneControlsAudioProcessor()

    fun setControls(
        equalizerEnabled: Boolean,
        bandGainsDb: FloatArray,
        replayGainEnabled: Boolean,
        replayGainDb: Float,
        replayPeak: Float,
    ) = processor.setControls(
        equalizerEnabled,
        bandGainsDb,
        replayGainEnabled,
        replayGainDb,
        replayPeak,
    )
}

class ToneControlsAudioProcessor : BaseAudioProcessor() {
    private data class Control(
        val equalizerEnabled: Boolean = false,
        val bandGainsDb: FloatArray = FloatArray(TONE_BAND_COUNT),
        val replayGainEnabled: Boolean = false,
        val replayGainDb: Float = 0f,
        val replayPeak: Float = 0f,
        val revision: Int = 0,
    )

    @Volatile private var control = Control()
    private val filters = Array(TONE_BAND_COUNT) { SmoothBiquad() }
    private val frameInput = FloatArray(32)
    private val frameOutput = FloatArray(32)
    private var sampleRate = 0
    private var channelCount = 0
    private var encoding = C.ENCODING_INVALID
    private var bits = 16
    private var appliedRevision = -1
    private var processingRequested = false
    private var bypassed = true
    private var wet = 0f
    private var wetTarget = 0f
    private var inputGain = 1f
    private var inputGainTarget = 1f
    private var limiterGain = 1f
    private var wetAttack = 1f
    private var wetRelease = 1f
    private var parameterSmoothing = 1f
    private var limiterRelease = 1f

    internal val isBypassed: Boolean get() = bypassed

    fun setControls(
        equalizerEnabled: Boolean,
        bandGainsDb: FloatArray,
        replayGainEnabled: Boolean,
        replayGainDb: Float,
        replayPeak: Float,
    ) {
        val safeBands = FloatArray(TONE_BAND_COUNT)
        for (index in safeBands.indices) {
            safeBands[index] = bandGainsDb.getOrNull(index)
                ?.takeIf { it.isFinite() }
                ?.coerceIn(-6f, 6f) ?: 0f
        }
        val previous = control
        control = Control(
            equalizerEnabled = equalizerEnabled,
            bandGainsDb = safeBands,
            replayGainEnabled = replayGainEnabled,
            replayGainDb = replayGainDb.takeIf { it.isFinite() }
                ?.coerceIn(-24f, 12f) ?: 0f,
            replayPeak = replayPeak.takeIf { it.isFinite() && it > 0f }
                ?.coerceAtMost(8f) ?: 0f,
            revision = previous.revision + 1,
        )
    }

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat,
    ): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_24BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_32BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ||
            inputAudioFormat.channelCount !in 1..32 ||
            inputAudioFormat.sampleRate < 8000
        ) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun isActive(): Boolean = true

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        val outputBuffer = replaceOutputBuffer(byteCount).order(ByteOrder.LITTLE_ENDIAN)
        if (byteCount == 0) {
            outputBuffer.flip()
            return
        }
        applyControlIfNeeded()
        if (bypassed) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }

        val bytesPerSample = if (bits == 0) 4 else bits / 8
        val frameBytes = bytesPerSample * channelCount
        require(byteCount % frameBytes == 0) {
            "PCM buffer must contain complete frames"
        }
        inputBuffer.order(ByteOrder.LITTLE_ENDIAN)

        while (inputBuffer.hasRemaining()) {
            applyControlIfNeeded()
            val frameStart = inputBuffer.position()
            for (channel in 0 until channelCount) {
                frameInput[channel] = EpicenterPcm.read(inputBuffer, bits)
            }

            updateSmoothedParameters()
            var peak = 0f
            for (channel in 0 until channelCount) {
                val dry = frameInput[channel]
                var processed = dry * inputGain
                for (filter in filters) {
                    processed = filter.process(processed, channel)
                }
                val mixed = dry + wet * (processed - dry)
                frameOutput[channel] = mixed
                peak = max(peak, abs(mixed))
            }

            val requiredGain = if (peak > LIMITER_CEILING) {
                LIMITER_CEILING / peak
            } else {
                1f
            }
            limiterGain = if (requiredGain < limiterGain) {
                requiredGain
            } else {
                limiterGain + limiterRelease * (requiredGain - limiterGain)
            }

            for (channel in 0 until channelCount) {
                val value = frameOutput[channel] * limiterGain
                val sourcePosition = frameStart + channel * bytesPerSample
                if (value == frameInput[channel] &&
                    (bits != 0 || inputBuffer.getFloat(sourcePosition).isFinite())
                ) {
                    for (offset in 0 until bytesPerSample) {
                        outputBuffer.put(inputBuffer.get(sourcePosition + offset))
                    }
                } else {
                    EpicenterPcm.write(outputBuffer, value, bits)
                }
            }

            if (!processingRequested && wet == 0f && limiterGain >= 0.99999f) {
                enterBypass()
                if (inputBuffer.hasRemaining()) outputBuffer.put(inputBuffer)
                break
            }
        }
        outputBuffer.flip()
    }

    override fun onFlush() {
        val format = inputAudioFormat
        if (format == AudioProcessor.AudioFormat.NOT_SET) {
            resetState()
            return
        }
        sampleRate = format.sampleRate
        channelCount = format.channelCount
        encoding = format.encoding
        bits = when (encoding) {
            C.ENCODING_PCM_16BIT -> 16
            C.ENCODING_PCM_24BIT -> 24
            C.ENCODING_PCM_32BIT -> 32
            else -> 0
        }
        wetAttack = onePoleCoefficient(8f)
        wetRelease = onePoleCoefficient(15f)
        parameterSmoothing = onePoleCoefficient(20f)
        limiterRelease = onePoleCoefficient(100f)
        resetState()
        appliedRevision = -1
    }

    override fun onReset() {
        sampleRate = 0
        channelCount = 0
        encoding = C.ENCODING_INVALID
        resetState()
        appliedRevision = -1
    }

    private fun applyControlIfNeeded() {
        val state = control
        if (state.revision == appliedRevision || sampleRate <= 0) return
        appliedRevision = state.revision

        var maxPositiveEqDb = 0f
        var hasEq = false
        for (index in 0 until TONE_BAND_COUNT) {
            val gain = if (state.equalizerEnabled) state.bandGainsDb[index] else 0f
            hasEq = hasEq || abs(gain) > 0.001f
            maxPositiveEqDb = max(maxPositiveEqDb, gain)
            when (index) {
                0 -> filters[index].setLowShelf(sampleRate, BAND_FREQUENCIES[index], gain)
                TONE_BAND_COUNT - 1 -> filters[index].setHighShelf(
                    sampleRate,
                    BAND_FREQUENCIES[index],
                    gain,
                )
                else -> filters[index].setPeaking(
                    sampleRate,
                    BAND_FREQUENCIES[index],
                    gain,
                    0.9f,
                )
            }
        }

        var replayDb = if (state.replayGainEnabled) state.replayGainDb else 0f
        if (state.replayGainEnabled && state.replayPeak > 0f) {
            val peakSafeDb = (20.0 * ln((LIMITER_CEILING / state.replayPeak).toDouble()) /
                ln(10.0)).toFloat()
            replayDb = min(replayDb, peakSafeDb)
        }
        val hasReplayGain = state.replayGainEnabled && abs(replayDb) > 0.001f
        val automaticEqHeadroomDb = maxPositiveEqDb * 0.75f
        inputGainTarget = 10.0.pow(((replayDb - automaticEqHeadroomDb) / 20f).toDouble())
            .toFloat()
        processingRequested = hasEq || hasReplayGain
        wetTarget = if (processingRequested) 1f else 0f
        if (processingRequested) bypassed = false
    }

    private fun updateSmoothedParameters() {
        val wetCoefficient = if (wetTarget > wet) wetAttack else wetRelease
        wet += wetCoefficient * (wetTarget - wet)
        if (abs(wetTarget - wet) < 0.00001f) wet = wetTarget
        inputGain += parameterSmoothing * (inputGainTarget - inputGain)
        if (abs(inputGainTarget - inputGain) < 0.000001f) {
            inputGain = inputGainTarget
        }
        for (filter in filters) filter.step(parameterSmoothing)
    }

    private fun enterBypass() {
        bypassed = true
        wet = 0f
        wetTarget = 0f
        inputGain = 1f
        inputGainTarget = 1f
        limiterGain = 1f
        filters.forEach { it.resetToIdentity() }
    }

    private fun resetState() {
        bypassed = true
        processingRequested = false
        wet = 0f
        wetTarget = 0f
        inputGain = 1f
        inputGainTarget = 1f
        limiterGain = 1f
        filters.forEach { it.resetToIdentity() }
    }

    private fun onePoleCoefficient(milliseconds: Float): Float {
        if (sampleRate <= 0) return 1f
        return (1.0 - exp(-1.0 / (milliseconds * 0.001 * sampleRate))).toFloat()
    }

    companion object {
        private const val LIMITER_CEILING = 0.98f
        private val BAND_FREQUENCIES = floatArrayOf(60f, 230f, 910f, 3600f, 14000f)
    }
}

private class SmoothBiquad {
    private var b0 = 1f
    private var b1 = 0f
    private var b2 = 0f
    private var a1 = 0f
    private var a2 = 0f
    private var targetB0 = 1f
    private var targetB1 = 0f
    private var targetB2 = 0f
    private var targetA1 = 0f
    private var targetA2 = 0f
    private val z1 = FloatArray(32)
    private val z2 = FloatArray(32)

    fun process(input: Float, channel: Int): Float {
        val output = b0 * input + z1[channel]
        z1[channel] = b1 * input - a1 * output + z2[channel]
        z2[channel] = b2 * input - a2 * output
        return if (output.isFinite()) output else 0f
    }

    fun step(amount: Float) {
        b0 += amount * (targetB0 - b0)
        b1 += amount * (targetB1 - b1)
        b2 += amount * (targetB2 - b2)
        a1 += amount * (targetA1 - a1)
        a2 += amount * (targetA2 - a2)
    }

    fun setPeaking(sampleRate: Int, frequency: Float, gainDb: Float, q: Float) {
        if (abs(gainDb) < 0.001f) {
            setIdentityTarget()
            return
        }
        val omega = omega(sampleRate, frequency)
        val cosine = cos(omega)
        val alpha = sin(omega) / (2.0 * q)
        val amplitude = 10.0.pow(gainDb / 40.0)
        setNormalized(
            1.0 + alpha * amplitude,
            -2.0 * cosine,
            1.0 - alpha * amplitude,
            1.0 + alpha / amplitude,
            -2.0 * cosine,
            1.0 - alpha / amplitude,
        )
    }

    fun setLowShelf(sampleRate: Int, frequency: Float, gainDb: Float) {
        if (abs(gainDb) < 0.001f) {
            setIdentityTarget()
            return
        }
        val omega = omega(sampleRate, frequency)
        val cosine = cos(omega)
        val sine = sin(omega)
        val amplitude = 10.0.pow(gainDb / 40.0)
        val alpha = sine / 2.0 * sqrt(2.0)
        val beta = 2.0 * sqrt(amplitude) * alpha
        setNormalized(
            amplitude * ((amplitude + 1) - (amplitude - 1) * cosine + beta),
            2 * amplitude * ((amplitude - 1) - (amplitude + 1) * cosine),
            amplitude * ((amplitude + 1) - (amplitude - 1) * cosine - beta),
            (amplitude + 1) + (amplitude - 1) * cosine + beta,
            -2 * ((amplitude - 1) + (amplitude + 1) * cosine),
            (amplitude + 1) + (amplitude - 1) * cosine - beta,
        )
    }

    fun setHighShelf(sampleRate: Int, frequency: Float, gainDb: Float) {
        if (abs(gainDb) < 0.001f) {
            setIdentityTarget()
            return
        }
        val omega = omega(sampleRate, frequency)
        val cosine = cos(omega)
        val sine = sin(omega)
        val amplitude = 10.0.pow(gainDb / 40.0)
        val alpha = sine / 2.0 * sqrt(2.0)
        val beta = 2.0 * sqrt(amplitude) * alpha
        setNormalized(
            amplitude * ((amplitude + 1) + (amplitude - 1) * cosine + beta),
            -2 * amplitude * ((amplitude - 1) + (amplitude + 1) * cosine),
            amplitude * ((amplitude + 1) + (amplitude - 1) * cosine - beta),
            (amplitude + 1) - (amplitude - 1) * cosine + beta,
            2 * ((amplitude - 1) - (amplitude + 1) * cosine),
            (amplitude + 1) - (amplitude - 1) * cosine - beta,
        )
    }

    fun resetToIdentity() {
        b0 = 1f
        b1 = 0f
        b2 = 0f
        a1 = 0f
        a2 = 0f
        setIdentityTarget()
        z1.fill(0f)
        z2.fill(0f)
    }

    private fun omega(sampleRate: Int, frequency: Float): Double {
        val safeFrequency = min(frequency.toDouble(), sampleRate * 0.45)
        return 2.0 * PI * safeFrequency / sampleRate
    }

    private fun setIdentityTarget() {
        targetB0 = 1f
        targetB1 = 0f
        targetB2 = 0f
        targetA1 = 0f
        targetA2 = 0f
    }

    private fun setNormalized(
        rawB0: Double,
        rawB1: Double,
        rawB2: Double,
        rawA0: Double,
        rawA1: Double,
        rawA2: Double,
    ) {
        targetB0 = (rawB0 / rawA0).toFloat()
        targetB1 = (rawB1 / rawA0).toFloat()
        targetB2 = (rawB2 / rawA0).toFloat()
        targetA1 = (rawA1 / rawA0).toFloat()
        targetA2 = (rawA2 / rawA0).toFloat()
    }
}
