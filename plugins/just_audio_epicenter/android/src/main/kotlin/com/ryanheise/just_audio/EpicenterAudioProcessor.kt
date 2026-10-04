package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder

object EpicenterProcessorController {
    val processor = EpicenterAudioProcessor()

    fun setEpicenterEnabled(enabled: Boolean) = processor.setEpicenterEnabled(enabled)
    fun setSweepFreq(value: Float) = processor.setSweepFreq(value)
    fun setWidth(value: Float) = processor.setWidth(value)
    fun setIntensity(value: Float) = processor.setIntensity(value)
    fun setVolume(value: Float) = processor.setVolume(value)
}

class EpicenterAudioProcessor : BaseAudioProcessor() {
    @Volatile private var enabled = false
    @Volatile private var sweepFreq = 45f
    @Volatile private var width = 50f
    @Volatile private var intensity = 50f
    @Volatile private var volume = 100f

    private var dsp: EpicenterDsp? = null
    private var channelCount = 0
    private var inputSamples = FloatArray(0)
    private var outputSamples = FloatArray(0)

    fun setEpicenterEnabled(value: Boolean) {
        enabled = value
        if (!value) dsp?.reset()
    }

    fun setSweepFreq(value: Float) { sweepFreq = value.coerceIn(27f, 63f) }
    fun setWidth(value: Float) { width = value.coerceIn(0f, 100f) }
    fun setIntensity(value: Float) { intensity = value.coerceIn(0f, 100f) }
    fun setVolume(value: Float) { volume = value.coerceIn(0f, 100f) }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        channelCount = inputAudioFormat.channelCount
        dsp = EpicenterDsp(inputAudioFormat.sampleRate)
        return inputAudioFormat
    }

    override fun isActive(): Boolean = true

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        val outputBuffer = replaceOutputBuffer(byteCount)
        if (byteCount == 0) {
            outputBuffer.flip()
            return
        }

        if (!enabled || intensity <= 0.01f) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }

        val inSlice = inputBuffer.slice().order(ByteOrder.LITTLE_ENDIAN)
        val samples = byteCount / 2
        ensureSampleCapacity(samples)
        for (i in 0 until samples) {
            inputSamples[i] = inSlice.short.toFloat() / 32768f
        }
        inputBuffer.position(inputBuffer.position() + byteCount)

        val params = EpicenterParams(
            sweepFreq = sweepFreq,
            width = width,
            intensity = intensity,
            volume = volume,
        )
        dsp?.processInterleaved(inputSamples, outputSamples, channelCount, params)

        outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until samples) {
            val sample = outputSamples[i]
            val intSample = (sample.coerceIn(-1f, 1f) * 32767f).toInt().coerceIn(-32768, 32767)
            outputBuffer.put((intSample and 0xff).toByte())
            outputBuffer.put(((intSample shr 8) and 0xff).toByte())
        }
        outputBuffer.flip()
    }

    private fun ensureSampleCapacity(samples: Int) {
        if (inputSamples.size < samples) inputSamples = FloatArray(samples)
        if (outputSamples.size < samples) outputSamples = FloatArray(samples)
    }

    override fun onFlush() {
        dsp?.reset()
    }

    override fun onReset() {
        dsp = null
        channelCount = 0
        inputSamples = FloatArray(0)
        outputSamples = FloatArray(0)
    }
}
