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
    private var encoding = C.ENCODING_PCM_16BIT

    fun setEpicenterEnabled(value: Boolean) {
        enabled = value
        if (!value) dsp?.reset()
    }

    fun setSweepFreq(value: Float) { sweepFreq = value.coerceIn(27f, 63f) }
    fun setWidth(value: Float) { width = value.coerceIn(0f, 100f) }
    fun setIntensity(value: Float) { intensity = value.coerceIn(0f, 100f) }
    fun setVolume(value: Float) { volume = value.coerceIn(0f, 100f) }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_24BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_32BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT
        ) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        channelCount = inputAudioFormat.channelCount
        encoding = inputAudioFormat.encoding
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
        val bytesPerSample = when (encoding) {
            C.ENCODING_PCM_16BIT -> 2
            C.ENCODING_PCM_24BIT -> 3
            C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT -> 4
            else -> throw AudioProcessor.UnhandledAudioFormatException(
                AudioProcessor.AudioFormat(0, 0, encoding)
            )
        }
        if (byteCount % bytesPerSample != 0) {
            throw IllegalStateException("PCM buffer is not aligned to the configured encoding")
        }
        val samples = byteCount / bytesPerSample
        val input = FloatArray(samples)
        for (i in 0 until samples) {
            val sample = when (encoding) {
                C.ENCODING_PCM_16BIT -> inSlice.short.toFloat() / 32768f
                C.ENCODING_PCM_24BIT -> {
                    val value = inSlice.get().toInt() and 0xff or
                        ((inSlice.get().toInt() and 0xff) shl 8) or
                        (inSlice.get().toInt() shl 16)
                    value.toFloat() / 8388608f
                }
                C.ENCODING_PCM_32BIT -> inSlice.int.toFloat() / 2147483648f
                C.ENCODING_PCM_FLOAT -> inSlice.float
                else -> error("Unsupported PCM encoding")
            }
            if (encoding == C.ENCODING_PCM_FLOAT && !sample.isFinite()) {
                throw IllegalArgumentException("FLOAT PCM sample must be finite")
            }
            input[i] = sample
        }
        inputBuffer.position(inputBuffer.position() + byteCount)

        val output = FloatArray(samples)
        val params = EpicenterParams(
            sweepFreq = sweepFreq,
            width = width,
            intensity = intensity,
            volume = volume,
        )
        dsp?.processInterleaved(input, output, channelCount, params)

        outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
        writeSamples(outputBuffer, output)
        outputBuffer.flip()
    }

    private fun writeSamples(outputBuffer: ByteBuffer, samples: FloatArray) {
        for (sample in samples) {
            when (encoding) {
                C.ENCODING_PCM_16BIT -> {
                    val intSample = (sample.coerceIn(-1f, 1f) * 32767f).toInt().coerceIn(-32768, 32767)
                    outputBuffer.put((intSample and 0xff).toByte())
                    outputBuffer.put(((intSample shr 8) and 0xff).toByte())
                }
                C.ENCODING_PCM_24BIT -> {
                    val intSample = (sample.coerceIn(-1f, 1f) * 8388607f).toInt().coerceIn(-8388608, 8388607)
                    outputBuffer.put((intSample and 0xff).toByte())
                    outputBuffer.put(((intSample shr 8) and 0xff).toByte())
                    outputBuffer.put(((intSample shr 16) and 0xff).toByte())
                }
                C.ENCODING_PCM_32BIT -> {
                    val intSample = (sample.coerceIn(-1f, 1f) * 2147483647f).toLong()
                        .coerceIn(-2147483648L, 2147483647L).toInt()
                    outputBuffer.putInt(intSample)
                }
                C.ENCODING_PCM_FLOAT -> outputBuffer.putFloat(sample.coerceIn(-1f, 1f))
                else -> error("Unsupported PCM encoding")
            }
        }
    }

    override fun onFlush() {
        dsp?.reset()
    }

    override fun onReset() {
        dsp = null
        channelCount = 0
        encoding = C.ENCODING_PCM_16BIT
    }
}
