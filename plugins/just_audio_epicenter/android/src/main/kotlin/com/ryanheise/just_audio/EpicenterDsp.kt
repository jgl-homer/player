package com.ryanheise.just_audio

import kotlin.math.*

data class EpicenterParams(
    val sweepFreq: Float = 40f,
    val width: Float = 60f,
    val intensity: Float = 65f,
    val volume: Float = 100f,
    val peakProtectionEnabled: Boolean = true,
)

enum class EpicenterEngine { SMART, LEGACY }

/** Mutable, audio-thread-owned telemetry. Enable only in tests/debug tooling. */
class EpicenterDebugState {
    var detectedF0 = 0f; var smoothedF0 = 0f; var confidence = 0f
    var bassEnvelope = 0f; var smartMix = 0f; var legacyMix = 0f
    var generatedGain = 1f; var limiterGain = 1f
    var inputPeak = 0f; var generatedPeak = 0f; var outputPeak = 0f; var rms = 0f
}

class EpicenterDsp(
    private val sampleRate: Int,
    private val engine: EpicenterEngine = EpicenterEngine.SMART,
    private val debugEnabled: Boolean = false,
) {
    private val legacy = LegacyEpicenterDsp(sampleRate)
    private val analyzer = BassAnalyzer(sampleRate)
    private val tracker = BassPitchTracker()
    private val pfm1 = BassFilter(sampleRate.toDouble())
    private val pfm2 = BassFilter(sampleRate.toDouble())
    private val shape = BassFilter(sampleRate.toDouble())
    private val lowpass = BassFilter(sampleRate.toDouble())
    private var generated = FloatArray(4096)
    private val attack = coefficient(12f)
    private val release = coefficient(160f)
    private val confidenceAttack = coefficient(30f)
    private val confidenceRelease = coefficient(35f)
    private val glide = coefficient(45f)
    private val smooth = coefficient(30f)
    private val headroomRelease = coefficient(120f)
    private val peakRelease = coefficient(80f)
    private val rampStep = 1f / (sampleRate * 0.025f)
    private var phase = 0.0
    private var pitch = 0f
    private var envelope = 0f
    private var confidence = 0f
    private var smartMix = 0f
    private var smartActive = false
    private var restoration = 0f
    private var intensity = 0f
    private var volume = 1f
    private var sweep = 40f
    private var width = 60f
    private var effectMix = 0f
    private var originalPeak = 0f
    private var generatedPeak = 0f
    private var headroomGain = 1f
    private var limiterGain = 1f
    private var filterCounter = 0
    private var lastFilterSweep = Float.NaN
    private var lastFilterWidth = Float.NaN
    private var debugCounter = 0
    private var measuredInput = 0f; private var measuredGenerated = 0f; private var measuredOutput = 0f
    private var measuredSquare = 0.0; private var measuredSamples = 0
    val debugState = EpicenterDebugState()
    val isBypassed: Boolean get() = effectMix == 0f

    init {
        require(sampleRate >= 8000)
        // Fourth-order Butterworth high pass, -3 dB at 24 Hz.
        pfm1.configure(1, 24.0, 0.5411961)
        pfm2.configure(1, 24.0, 1.306563)
        updateFilters()
    }
    fun prepare(channelCount: Int, params: EpicenterParams) {
        legacy.prepare(channelCount, params)
    }
    fun reset() {
        legacy.reset(); analyzer.reset(); tracker.reset()
        pfm1.reset(); pfm2.reset(); shape.reset(); lowpass.reset()
        phase = 0.0; pitch = 0f; envelope = 0f; confidence = 0f; smartMix = 0f
        smartActive = false; restoration = 0f; intensity = 0f; volume = 1f; effectMix = 0f
        originalPeak = 0f; generatedPeak = 0f; headroomGain = 1f; limiterGain = 1f
        filterCounter = 0; debugCounter = 0
        measuredInput = 0f; measuredGenerated = 0f; measuredOutput = 0f
        measuredSquare = 0.0; measuredSamples = 0
        debugState.detectedF0 = 0f; debugState.smoothedF0 = 0f; debugState.confidence = 0f
        debugState.bassEnvelope = 0f; debugState.smartMix = 0f; debugState.legacyMix = 0f
        debugState.generatedGain = 1f; debugState.limiterGain = 1f
        debugState.inputPeak = 0f; debugState.generatedPeak = 0f; debugState.outputPeak = 0f; debugState.rms = 0f
    }
    fun processInterleaved(input: FloatArray, output: FloatArray, channelCount: Int,
        params: EpicenterParams, sampleCount: Int = min(input.size, output.size), enabled: Boolean = true) {
        require(channelCount > 0 && sampleCount >= 0 && sampleCount <= min(input.size, output.size))
        require(sampleCount % channelCount == 0)
        val active = enabled && params.intensity > 0f
        if (!active && isBypassed) { input.copyInto(output, endIndex = sampleCount); return }
        val frames = sampleCount / channelCount
        if (engine == EpicenterEngine.LEGACY) {
            legacy.processInterleaved(input, output, channelCount, params, sampleCount)
        } else {
            if (generated.size < frames) generated = FloatArray(frames)
            legacy.processInterleaved(input, generated, channelCount, params, sampleCount, generatedOnly = true)
        }
        for (frame in 0 until frames) {
            val base = frame * channelCount
            effectMix = if (active) min(1f, effectMix + rampStep) else max(0f, effectMix - rampStep)
            if (engine == EpicenterEngine.LEGACY) {
                for (ch in 0 until channelCount) output[base + ch] =
                    input[base + ch] + effectMix * (output[base + ch] - input[base + ch])
                continue
            }
            val left = clean(input[base])
            val right = if (channelCount > 1) clean(input[base + 1]) else left
            sweep = params.sweepFreq.coerceIn(27f, 63f) + smooth * (sweep - params.sweepFreq.coerceIn(27f, 63f))
            width = params.width.coerceIn(0f, 100f) + smooth * (width - params.width.coerceIn(0f, 100f))
            if (++filterCounter >= max(1, sampleRate / 200)) { filterCounter = 0; updateFilters() }
            if (analyzer.push((left + right) * 0.5f, (left - right) * 0.5f, sweep, width)) {
                tracker.update(analyzer.targetHz, analyzer.confidence)
                if (analyzer.confidence > 0.72f && tracker.stableFrames >= 3) smartActive = true
                if (analyzer.confidence < 0.50f) smartActive = false
            }
            val c = if (tracker.stableFrames >= 3) analyzer.confidence else 0f
            confidence = c + (if (c > confidence) confidenceAttack else confidenceRelease) * (confidence - c)
            smartMix = (if (smartActive) 1f else 0f) + smooth * (smartMix - if (smartActive) 1f else 0f)
            restoration = analyzer.restoration + smooth * (restoration - analyzer.restoration)
            val x = abs(analyzer.bandSample)
            envelope = x + (if (x > envelope) attack else release) * (envelope - x)
            if (tracker.stableF0 > 0f) {
                if (pitch == 0f) pitch = tracker.stableF0
                pitch = tracker.stableF0 + glide * (pitch - tracker.stableF0)
            }
            phase += 2 * PI * pitch / sampleRate
            if (phase >= 2 * PI) phase -= 2 * PI
            val targetIntensity = params.intensity.coerceIn(0f, 100f) / 100f
            intensity = targetIntensity + smooth * (intensity - targetIntensity)
            val targetVolume = params.volume.coerceIn(0f, 100f) / 100f
            volume = targetVolume + smooth * (volume - targetVolume)
            val evidence = ((confidence - 0.4f) / 0.6f).coerceIn(0f, 1f)
            val smartWeight = sin(smartMix * PI * 0.5).toFloat()
            val legacyWeight = cos(smartMix * PI * 0.5).toFloat() * 0.25f
            val synthesized = sin(phase).toFloat() * envelope * restoration * 2.5f
            // Both branches share the evidence gate: uncertain noise must not leak through fallback.
            var sub = (synthesized * smartWeight + generated[frame] * legacyWeight * restoration) *
                evidence * intensity * intensity
            sub = lowpass.process(shape.process(pfm2.process(pfm1.process(sub))))
            sub *= effectMix
            var peak = 0f
            for (ch in 0 until channelCount) peak = max(peak, abs(clean(input[base + ch])))
            originalPeak = max(peak, originalPeak * peakRelease)
            generatedPeak = max(abs(sub), generatedPeak * headroomRelease)
            val available = max(0f, 0.96f - originalPeak)
            val allowed = min(1f, available / (generatedPeak + 1e-12f))
            headroomGain = if (allowed < headroomGain) allowed else allowed + headroomRelease * (headroomGain - allowed)
            sub *= headroomGain
            val outputVolume = 1f + effectMix * (volume - 1f)
            var mixedPeak = 0f
            for (ch in 0 until channelCount) {
                val mixed = (clean(input[base + ch]) + sub) * outputVolume
                output[base + ch] = mixed
                mixedPeak = max(mixedPeak, abs(mixed))
            }
            val targetGain = if (params.peakProtectionEnabled && mixedPeak > 0.96f) 0.96f / mixedPeak else 1f
            limiterGain = if (targetGain < limiterGain) targetGain else targetGain + peakRelease * (limiterGain - targetGain)
            if (limiterGain > 0.99999f) limiterGain = 1f
            val linkedGain = 1f + effectMix * (limiterGain - 1f)
            for (ch in 0 until channelCount) {
                val index = base + ch
                val mixed = output[index]
                val protected = if (params.peakProtectionEnabled) lastDefense(mixed * linkedGain) else mixed
                output[index] = if (effectMix == 0f) input[index] else mixed + effectMix * (protected - mixed)
            }
            if (debugEnabled) measure(peak, sub, output, base, channelCount, smartWeight, legacyWeight)
        }
        if (!active && isBypassed) reset()
    }
    private fun updateFilters() {
        if (abs(sweep - lastFilterSweep) < 0.001f && abs(width - lastFilterWidth) < 0.001f) return
        val q = 2.8 - 2.1 * width / 100.0
        shape.configure(2, sweep.toDouble(), q)
        lowpass.configure(0, (sweep + sweep / q).coerceIn(55.0, 100.0))
        lastFilterSweep = sweep; lastFilterWidth = width
    }
    private fun measure(peak: Float, sub: Float, output: FloatArray, base: Int, channels: Int, sw: Float, lw: Float) {
        measuredInput = max(measuredInput, peak); measuredGenerated = max(measuredGenerated, abs(sub))
        for (ch in 0 until channels) {
            val x = output[base + ch]
            measuredOutput = max(measuredOutput, abs(x)); measuredSquare += x * x; measuredSamples++
        }
        if (++debugCounter < sampleRate / 10) return
        debugCounter = 0
        debugState.detectedF0 = analyzer.detectedF0; debugState.smoothedF0 = pitch
        debugState.confidence = confidence; debugState.bassEnvelope = envelope
        debugState.smartMix = sw; debugState.legacyMix = lw
        debugState.generatedGain = headroomGain; debugState.limiterGain = limiterGain
        debugState.inputPeak = measuredInput; debugState.generatedPeak = measuredGenerated
        debugState.outputPeak = measuredOutput; debugState.rms = sqrt(measuredSquare / max(1, measuredSamples)).toFloat()
        measuredInput = 0f; measuredGenerated = 0f; measuredOutput = 0f; measuredSquare = 0.0; measuredSamples = 0
    }
    private fun coefficient(ms: Float) = exp(-1f / (ms * sampleRate / 1000f))
    private fun clean(x: Float) = if (x.isFinite()) x else 0f
    private fun lastDefense(x: Float): Float {
        if (abs(x) <= 0.985f) return x
        val n = ((abs(x) - 0.985f) / 0.015f).coerceIn(0f, 1f)
        return sign(x) * (0.985f + (n - n * n * n / 3f) * 0.015f)
    }
}
