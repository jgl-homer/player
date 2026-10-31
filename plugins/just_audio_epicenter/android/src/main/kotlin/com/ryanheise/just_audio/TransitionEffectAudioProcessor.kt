package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.exp

/** Small original DSP effects used only while a two-deck transition is active. */
class TransitionEffectAudioProcessor : BaseAudioProcessor() {
    @Volatile private var mode = "smooth"
    @Volatile private var role = "outgoing"
    @Volatile private var progress = 0f
    @Volatile private var intensity = 0.65f
    private var encoding = C.ENCODING_PCM_16BIT
    private var sampleRate = 44100
    private var channelCount = 2
    private var lowState = FloatArray(2)
    private var filterState = FloatArray(2)
    private var echoBuffer = FloatArray(44100)
    private var echoIndex = 0

    fun begin(effect: String, deckRole: String, effectIntensity: Float) {
        mode = effect
        role = deckRole
        intensity = effectIntensity.coerceIn(0f, 1f)
        progress = 0f
        clearState()
    }

    fun update(value: Float) {
        progress = value.coerceIn(0f, 1f)
    }

    fun end() {
        mode = "smooth"
        progress = 0f
        clearState()
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding !in SUPPORTED_ENCODINGS) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        encoding = inputAudioFormat.encoding
        sampleRate = inputAudioFormat.sampleRate
        channelCount = inputAudioFormat.channelCount.coerceAtLeast(1)
        lowState = FloatArray(channelCount)
        filterState = FloatArray(channelCount)
        echoBuffer = FloatArray((sampleRate * 0.24f).toInt().coerceAtLeast(channelCount) * channelCount)
        echoIndex = 0
        return inputAudioFormat
    }

    override fun isActive(): Boolean = true

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        val output = replaceOutputBuffer(byteCount).order(ByteOrder.LITTLE_ENDIAN)
        if (byteCount == 0) {
            output.flip()
            return
        }
        val effect = mode
        if (effect != "bassSwap" && effect != "filterSweep" && effect != "echoOut") {
            output.put(inputBuffer)
            output.flip()
            return
        }

        val input = inputBuffer.slice().order(ByteOrder.LITTLE_ENDIAN)
        val samples = byteCount / bytesPerSample(encoding)
        val currentProgress = progress
        val currentIntensity = intensity
        repeat(samples) { sampleIndex ->
            val channel = sampleIndex % channelCount
            val sample = readSample(input, encoding)
            val processed = when (effect) {
                "bassSwap" -> bassSwap(sample, channel, currentProgress, currentIntensity)
                "filterSweep" -> filterSweep(sample, channel, currentProgress, currentIntensity)
                "echoOut" -> echoOut(sample, currentProgress, currentIntensity)
                else -> sample
            }
            writeSample(output, encoding, processed.coerceIn(-1f, 1f))
        }
        inputBuffer.position(inputBuffer.position() + byteCount)
        output.flip()
    }

    private fun bassSwap(sample: Float, channel: Int, value: Float, amount: Float): Float {
        val alpha = onePoleAlpha(180f)
        lowState[channel] += alpha * (sample - lowState[channel])
        val low = lowState[channel]
        val high = sample - low
        val lowGain = if (role == "outgoing") {
            1f - value * amount
        } else {
            1f - (1f - value) * amount
        }
        return high + low * lowGain
    }

    private fun filterSweep(sample: Float, channel: Int, value: Float, amount: Float): Float {
        val phase = if (role == "outgoing") 1f - value else value
        val effective = (phase * amount + (1f - amount)).coerceIn(0f, 1f)
        val cutoff = 260f + 17740f * effective * effective
        val alpha = onePoleAlpha(cutoff)
        filterState[channel] += alpha * (sample - filterState[channel])
        return filterState[channel]
    }

    private fun echoOut(sample: Float, value: Float, amount: Float): Float {
        if (role != "outgoing") return sample
        val delayed = echoBuffer[echoIndex]
        echoBuffer[echoIndex] = (sample + delayed * (0.30f + amount * 0.35f)).coerceIn(-1f, 1f)
        echoIndex = (echoIndex + 1) % echoBuffer.size
        val wet = amount * (0.25f + value * 0.65f)
        return sample * (1f - value * 0.65f) + delayed * wet
    }

    private fun onePoleAlpha(cutoff: Float): Float =
        (1.0 - exp(-2.0 * PI * cutoff / sampleRate)).toFloat()

    private fun clearState() {
        lowState.fill(0f)
        filterState.fill(0f)
        echoBuffer.fill(0f)
        echoIndex = 0
    }

    override fun onFlush() = clearState()
    override fun onReset() = clearState()

    private fun bytesPerSample(value: Int): Int = when (value) {
        C.ENCODING_PCM_16BIT -> 2
        C.ENCODING_PCM_24BIT -> 3
        C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT -> 4
        else -> error("Unsupported PCM encoding")
    }

    private fun readSample(buffer: ByteBuffer, value: Int): Float = when (value) {
        C.ENCODING_PCM_16BIT -> buffer.short / 32768f
        C.ENCODING_PCM_24BIT -> {
            val raw = (buffer.get().toInt() and 0xff) or
                ((buffer.get().toInt() and 0xff) shl 8) or
                (buffer.get().toInt() shl 16)
            raw / 8388608f
        }
        C.ENCODING_PCM_32BIT -> buffer.int / 2147483648f
        C.ENCODING_PCM_FLOAT -> buffer.float
        else -> error("Unsupported PCM encoding")
    }

    private fun writeSample(buffer: ByteBuffer, value: Int, sample: Float) {
        when (value) {
            C.ENCODING_PCM_16BIT -> buffer.putShort((sample * 32767f).toInt().toShort())
            C.ENCODING_PCM_24BIT -> {
                val raw = (sample * 8388607f).toInt()
                buffer.put((raw and 0xff).toByte())
                buffer.put(((raw shr 8) and 0xff).toByte())
                buffer.put(((raw shr 16) and 0xff).toByte())
            }
            C.ENCODING_PCM_32BIT -> buffer.putInt((sample * 2147483647f).toInt())
            C.ENCODING_PCM_FLOAT -> buffer.putFloat(sample)
        }
    }

    companion object {
        private val SUPPORTED_ENCODINGS = setOf(
            C.ENCODING_PCM_16BIT,
            C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT,
            C.ENCODING_PCM_FLOAT,
        )
    }
}
