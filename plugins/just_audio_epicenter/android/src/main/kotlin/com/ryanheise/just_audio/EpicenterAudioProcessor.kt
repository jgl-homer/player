package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

object EpicenterProcessorController {
    val processor = EpicenterAudioProcessor()
    fun setEpicenterEnabled(enabled: Boolean) = processor.setEpicenterEnabled(enabled)
    fun setSweepFreq(value: Float) = processor.setSweepFreq(value)
    fun setWidth(value: Float) = processor.setWidth(value)
    fun setIntensity(value: Float) = processor.setIntensity(value)
    fun setVolume(value: Float) = processor.setVolume(value)
    fun setPeakProtectionEnabled(enabled: Boolean) = processor.setPeakProtectionEnabled(enabled)
    fun setEngine(engine: EpicenterEngine) = processor.setEngine(engine)
}

class EpicenterAudioProcessor : BaseAudioProcessor() {
    private data class Control(
        val enabled: Boolean = false,
        val params: EpicenterParams = EpicenterParams(),
        val engine: EpicenterEngine = EpicenterEngine.HYBRID,
    )
    // Setters run on the platform thread. Audio sees one immutable snapshot per callback.
    @Volatile private var control = Control()
    private var dsp: EpicenterDsp? = null
    private var hybridDsp: EpicenterDsp? = null
    private var smartDsp: EpicenterDsp? = null
    private var legacyDsp: EpicenterDsp? = null
    private var selectedEngine = EpicenterEngine.HYBRID
    private var channelCount = 0
    private var sampleRate = 0
    private var encoding = C.ENCODING_INVALID
    private var bits = 16
    private val inputSamples = FloatArray(4096)
    private val outputSamples = FloatArray(4096)

    fun setEpicenterEnabled(value: Boolean) { control = control.copy(enabled = value) }
    fun setEngine(value: EpicenterEngine) { control = control.copy(engine = value) }
    fun setSweepFreq(value: Float) { if (value.isFinite()) control = control.copy(params = control.params.copy(sweepFreq = value.coerceIn(27f, 63f))) }
    fun setWidth(value: Float) { if (value.isFinite()) control = control.copy(params = control.params.copy(width = value.coerceIn(0f, 100f))) }
    fun setIntensity(value: Float) { if (value.isFinite()) control = control.copy(params = control.params.copy(intensity = value.coerceIn(0f, 100f))) }
    fun setVolume(value: Float) { if (value.isFinite()) control = control.copy(params = control.params.copy(volume = value.coerceIn(0f, 100f))) }
    fun setPeakProtectionEnabled(value: Boolean) { control = control.copy(params = control.params.copy(peakProtectionEnabled = value)) }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_24BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_32BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT ||
            inputAudioFormat.channelCount !in 1..32 || inputAudioFormat.sampleRate < 8000) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        // Media3 may configure the next stream while the current one is draining.
        return inputAudioFormat
    }

    override fun isActive(): Boolean = true

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        val outputBuffer = replaceOutputBuffer(byteCount).order(ByteOrder.LITTLE_ENDIAN)
        val state = control
        selectEngineWhenBypassed(state.engine)
        val initialProcessor = dsp
        val active = state.enabled && state.params.intensity > 0f
        if (byteCount == 0) { outputBuffer.flip(); return }
        if (initialProcessor == null || (!active && initialProcessor.isBypassed)) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }
        var processor: EpicenterDsp = initialProcessor
        val bytesPerSample = if (bits == 0) 4 else bits / 8
        require(byteCount % (bytesPerSample * channelCount) == 0) { "PCM buffer must contain complete frames" }
        inputBuffer.order(ByteOrder.LITTLE_ENDIAN)
        val capacity = inputSamples.size / channelCount * channelCount
        while (inputBuffer.hasRemaining()) {
            selectEngineWhenBypassed(state.engine)
            processor = dsp ?: processor
            if (!active && processor.isBypassed) { outputBuffer.put(inputBuffer); break }
            val count = min(capacity, inputBuffer.remaining() / bytesPerSample)
            val sourcePosition = inputBuffer.position()
            for (i in 0 until count) inputSamples[i] = EpicenterPcm.read(inputBuffer, bits)
            // Fade to dry, switch a prepared engine, then fade in. No allocation or UI-thread reset.
            processor.processInterleaved(inputSamples, outputSamples, channelCount, state.params, count,
                state.enabled && selectedEngine == state.engine)
            for (i in 0 until count) {
                val position = sourcePosition + i * bytesPerSample
                // Preserve PCM32 low bits too when the float-domain mix is unchanged.
                if (outputSamples[i] == inputSamples[i] && (bits != 0 || inputBuffer.getFloat(position).isFinite())) {
                    for (b in 0 until bytesPerSample) outputBuffer.put(inputBuffer.get(position + b))
                } else EpicenterPcm.write(outputBuffer, outputSamples[i], bits)
            }
        }
        outputBuffer.flip()
    }

    override fun onFlush() {
        val format = inputAudioFormat
        if (format == AudioProcessor.AudioFormat.NOT_SET) { dsp?.reset(); return }
        if (sampleRate != format.sampleRate || channelCount != format.channelCount || encoding != format.encoding || dsp == null) {
            sampleRate = format.sampleRate
            channelCount = format.channelCount
            encoding = format.encoding
            bits = when (encoding) {
                C.ENCODING_PCM_16BIT -> 16
                C.ENCODING_PCM_24BIT -> 24
                C.ENCODING_PCM_32BIT -> 32
                else -> 0
            }
            hybridDsp = EpicenterDsp(sampleRate, EpicenterEngine.HYBRID).also { it.prepare(channelCount, control.params) }
            smartDsp = EpicenterDsp(sampleRate, EpicenterEngine.SMART).also { it.prepare(channelCount, control.params) }
            legacyDsp = EpicenterDsp(sampleRate, EpicenterEngine.LEGACY).also { it.prepare(channelCount, control.params) }
        } else {
            hybridDsp?.reset()
            smartDsp?.reset()
            legacyDsp?.reset()
        }
        selectedEngine = control.engine
        dsp = selectedDsp(selectedEngine)
    }

    private fun selectEngineWhenBypassed(requested: EpicenterEngine) {
        if (selectedEngine == requested || dsp?.isBypassed != true) return
        selectedEngine = requested
        dsp = selectedDsp(requested)
        dsp?.reset()
    }

    private fun selectedDsp(engine: EpicenterEngine): EpicenterDsp? = when (engine) {
        EpicenterEngine.HYBRID -> hybridDsp
        EpicenterEngine.SMART -> smartDsp
        EpicenterEngine.LEGACY -> legacyDsp
    }

    override fun onReset() {
        dsp = null; channelCount = 0; sampleRate = 0; encoding = C.ENCODING_INVALID
        hybridDsp = null; smartDsp = null; legacyDsp = null
    }
}
