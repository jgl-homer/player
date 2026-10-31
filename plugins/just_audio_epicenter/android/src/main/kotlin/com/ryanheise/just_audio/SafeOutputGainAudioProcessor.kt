package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.pow

/** Independent post-DSP gain. Disabled means a bit-for-bit PCM pass-through. */
object SafeOutputGainController {
    private val processors = linkedSetOf<SafeOutputGainAudioProcessor>()
    @Volatile private var enabled = false
    @Volatile private var gainDb = 0f
    @Volatile private var limiterEnabled = true
    @Volatile var inputPeak = 0f
        private set
    @Volatile var outputPeak = 0f
        private set

    @Synchronized
    fun createProcessor(): SafeOutputGainAudioProcessor = SafeOutputGainAudioProcessor().also {
        it.configure(enabled, gainDb, limiterEnabled)
        processors += it
    }

    @Synchronized
    fun releaseProcessor(processor: SafeOutputGainAudioProcessor) {
        processors -= processor
    }

    @Synchronized
    fun configure(isEnabled: Boolean, db: Float, limiter: Boolean) {
        enabled = isEnabled
        gainDb = db.coerceIn(-12f, 12f)
        limiterEnabled = limiter
        processors.forEach { it.configure(enabled, gainDb, limiterEnabled) }
    }

    fun meter(): Map<String, Float> = mapOf(
        "inputPeak" to (processors.maxOfOrNull { it.lastInputPeak } ?: 0f),
        "outputPeak" to (processors.maxOfOrNull { it.lastOutputPeak } ?: 0f),
    )

    @Synchronized
    fun report(input: Float, output: Float) {
        inputPeak = input
        outputPeak = output
    }
}

class SafeOutputGainAudioProcessor : BaseAudioProcessor() {
    @Volatile private var enabled = false
    @Volatile private var gainDb = 0f
    @Volatile private var limiterEnabled = true
    private var encoding = C.ENCODING_PCM_16BIT
    private var limiterGain = 1f
    private var currentLinearGain = 1f
    @Volatile var lastInputPeak = 0f
        private set
    @Volatile var lastOutputPeak = 0f
        private set

    fun configure(isEnabled: Boolean, db: Float, limiter: Boolean) {
        enabled = isEnabled
        gainDb = db.coerceIn(-12f, 12f)
        limiterEnabled = limiter
        if (!isEnabled) limiterGain = 1f
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding !in SUPPORTED_ENCODINGS) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        encoding = inputAudioFormat.encoding
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
        if (!enabled || (abs(gainDb) < 0.001f && !limiterEnabled)) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            lastInputPeak = 0f
            lastOutputPeak = 0f
            return
        }

        val input = inputBuffer.slice().order(ByteOrder.LITTLE_ENDIAN)
        val sampleCount = byteCount / bytesPerSample(encoding)
        val requestedGain = 10f.pow(gainDb / 20f)
        var inputPeak = 0f
        var outputPeak = 0f
        repeat(sampleCount) {
            val sample = readSample(input, encoding)
            inputPeak = maxOf(inputPeak, abs(sample))
            currentLinearGain += (requestedGain - currentLinearGain) * GAIN_SMOOTHING
            var gained = sample * currentLinearGain
            if (limiterEnabled) {
                val target = if (abs(gained) > LIMIT) LIMIT / abs(gained) else 1f
                limiterGain = if (target < limiterGain) {
                    target
                } else {
                    limiterGain + (target - limiterGain) * RELEASE
                }
                gained *= limiterGain
            }
            outputPeak = maxOf(outputPeak, abs(gained))
            writeSample(outputBuffer, encoding, gained.coerceIn(-1f, 1f))
        }
        lastInputPeak = inputPeak
        lastOutputPeak = outputPeak
        SafeOutputGainController.report(inputPeak, outputPeak)
        inputBuffer.position(inputBuffer.position() + byteCount)
        outputBuffer.flip()
    }

    override fun onFlush() {
        limiterGain = 1f
        currentLinearGain = 10f.pow(gainDb / 20f)
    }

    override fun onReset() {
        limiterGain = 1f
        encoding = C.ENCODING_PCM_16BIT
    }

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
        private const val LIMIT = 0.98f
        private const val RELEASE = 0.00012f
        private const val GAIN_SMOOTHING = 0.00025f
        private val SUPPORTED_ENCODINGS = setOf(
            C.ENCODING_PCM_16BIT,
            C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT,
            C.ENCODING_PCM_FLOAT,
        )
    }
}
