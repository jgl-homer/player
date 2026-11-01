package com.ryanheise.just_audio

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sign
import kotlin.math.tanh

/**
 * Generated-only divide-down texture. The V2 analyzer remains responsible for
 * sustained authorization and pitch; this class never processes the dry path.
 */
internal class HybridLegacyCore(private val sampleRate: Int) {
    private val detector60 = BassFilter(sampleRate.toDouble())
    private val detector80 = BassFilter(sampleRate.toDouble())
    private val detector110 = BassFilter(sampleRate.toDouble())
    private val detectorLowpass = BassFilter(sampleRate.toDouble())
    private val sideLowpass = BassFilter(sampleRate.toDouble())
    private val punchBand = BassFilter(sampleRate.toDouble())
    private val punchLowpass1 = BassFilter(sampleRate.toDouble())
    private val punchLowpass2 = BassFilter(sampleRate.toDouble())
    private val detectorEnvelope = HybridEnvelope(sampleRate, 4f, 92f)
    private val levelEnvelope = HybridEnvelope(sampleRate, 6f, 90f)
    private val fastBassEnvelope = HybridEnvelope(sampleRate, 3f, 38f)
    private val slowBassEnvelope = HybridEnvelope(sampleRate, 34f, 92f)
    private val sideEnvelope = HybridEnvelope(sampleRate, 4f, 45f)
    private val fullEnvelope = HybridEnvelope(sampleRate, 3f, 45f)
    private val transientEnvelope = HybridEnvelope(sampleRate, 4f, 72f)
    private val notePeakRelease = exp(-1f / max(1f, 100f * sampleRate / 1000f))
    private var lastDetector = 0f
    private var flipState = 1f
    private var samplesSinceToggle = Int.MAX_VALUE / 2
    private var unsupervisedCrossingSeen = false
    private var unsupervisedReady = false
    private var transientSamples = 0
    private var onsetArmed = true
    private var notePeak = 0f
    private var lastSweep = Float.NaN
    private var lastWidth = Float.NaN

    var coreSample = 0f
        private set
    var punchSample = 0f
        private set
    var transientMix = 0f
        private set
    var onsetStrength = 0f
        private set
    var sustainSupport = 0f
        private set

    init {
        detector60.configure(2, 58.0, 1.35)
        detector80.configure(2, 80.0, 1.55)
        detector110.configure(2, 108.0, 1.8)
        detectorLowpass.configure(0, 125.0)
        sideLowpass.configure(0, 125.0)
        punchLowpass1.configure(0, 120.0)
        punchLowpass2.configure(0, 120.0)
        updateFilters(40f, 60f)
    }

    fun reset() {
        detector60.reset(); detector80.reset(); detector110.reset()
        detectorLowpass.reset(); sideLowpass.reset(); punchBand.reset()
        punchLowpass1.reset(); punchLowpass2.reset()
        detectorEnvelope.reset(); levelEnvelope.reset()
        fastBassEnvelope.reset(); slowBassEnvelope.reset()
        sideEnvelope.reset(); fullEnvelope.reset(); transientEnvelope.reset()
        lastDetector = 0f; flipState = 1f
        samplesSinceToggle = Int.MAX_VALUE / 2
        unsupervisedCrossingSeen = false; unsupervisedReady = false
        transientSamples = 0; onsetArmed = true; notePeak = 0f
        coreSample = 0f; punchSample = 0f; transientMix = 0f; onsetStrength = 0f; sustainSupport = 0f
    }

    fun process(
        mid: Float,
        side: Float,
        expectedHz: Float,
        pitchValid: Boolean,
        smartEvidence: Float,
        sweep: Float,
        width: Float,
        intensity: Float,
    ) {
        updateFilters(sweep, width)
        val detector = detector60.process(mid) * 0.60f +
            detector80.process(mid) * 0.68f +
            detector110.process(mid) * 0.42f + detectorLowpass.process(mid) * 0.10f
        val detectorLevel = detectorEnvelope.process(detector)
        val fast = fastBassEnvelope.process(detector)
        val slow = slowBassEnvelope.process(detector)
        val sideLevel = sideEnvelope.process(sideLowpass.process(side))
        val fullLevel = fullEnvelope.process(mid)
        val coherence = fast / (fast + sideLevel + 1e-8f)
        val bassRatio = fast / (fullLevel + 1e-8f)
        val rise = ((fast - slow * 1.10f) / (fast + 1e-8f)).coerceIn(0f, 1f)
        notePeak = max(fast, notePeak * notePeakRelease)
        sustainSupport = ((fast / (notePeak + 1e-8f) - 0.60f) / 0.32f).coerceIn(0f, 1f)
        onsetStrength = (rise * ((coherence - 0.68f) / 0.25f).coerceIn(0f, 1f) *
            ((bassRatio - 0.10f) / 0.45f).coerceIn(0f, 1f) *
            ((fast - 0.0015f) / 0.018f).coerceIn(0f, 1f)).coerceIn(0f, 1f)

        if (fast < 0.002f || rise < 0.06f) onsetArmed = true
        if (onsetArmed && onsetStrength > 0.18f) {
            transientSamples = (sampleRate * (0.060f + 0.030f * onsetStrength)).toInt()
            onsetArmed = false
        }
        if (transientSamples > 0) transientSamples--
        transientMix = transientEnvelope.process(if (transientSamples > 0) 1f else 0f)

        if (samplesSinceToggle < Int.MAX_VALUE) samplesSinceToggle++
        val positiveCrossing = lastDetector <= 0f && detector > 0f
        lastDetector = detector
        val requested = detectorLevel > 0.0005f && (transientMix > 0.001f || smartEvidence > 0.001f)
        if (requested) {
            if (pitchValid && expectedHz in 27f..63f) {
                val expected = sampleRate / (2f * expectedHz)
                val early = max(4, (expected * 0.55f).toInt())
                val late = max(early + 1, (expected * 1.45f).toInt())
                if ((positiveCrossing && samplesSinceToggle >= early) || samplesSinceToggle >= late) toggle()
            } else if (positiveCrossing) {
                val interval = samplesSinceToggle
                val minimum = sampleRate / 126
                val maximum = sampleRate / 54
                if (unsupervisedCrossingSeen && interval in minimum..maximum) {
                    unsupervisedReady = true
                    toggle()
                } else {
                    unsupervisedCrossingSeen = true
                    samplesSinceToggle = 0
                }
            }
        }

        if (transientMix < 0.001f && smartEvidence <= 0f) {
            unsupervisedCrossingSeen = false
            unsupervisedReady = false
        }
        val active = requested && (pitchValid || unsupervisedReady)
        val raw = if (active) flipState * detectorLevel else 0f
        val leveled = levelEnvelope.process(raw) * sign(raw)
        val intensityNorm = intensity.coerceIn(0f, 1f)
        val drive = 1.15f + 0.85f * intensityNorm.pow(1.35f)
        val texture = tanh((raw * 0.62f + leveled * 0.38f) * drive) / tanh(drive)
        coreSample = texture * 0.92f

        val transientCurve = min(1f, intensityNorm * 1.35f)
        val punchAuthority = max(transientMix, smartEvidence * 0.28f)
        val punch = punchLowpass2.process(punchLowpass1.process(punchBand.process(mid)))
        punchSample = punch * punchAuthority * transientCurve * 0.24f
    }

    private fun toggle() {
        flipState *= -1f
        samplesSinceToggle = 0
    }

    private fun updateFilters(sweep: Float, width: Float) {
        if (abs(sweep - lastSweep) < 0.01f && abs(width - lastWidth) < 0.01f) return
        val sweepNorm = ((sweep.coerceIn(27f, 63f) - 27f) / 36f).toDouble()
        val widthNorm = (width.coerceIn(0f, 100f) / 100f).toDouble()
        val bodyHz = 82.0 + sweepNorm * 22.0 + widthNorm * 8.0
        punchBand.configure(2, bodyHz.coerceIn(70.0, 112.0), 1.20 + (1.0 - widthNorm) * 0.60)
        lastSweep = sweep
        lastWidth = width
    }
}

private class HybridEnvelope(sampleRate: Int, attackMs: Float, releaseMs: Float) {
    private val attack = exp(-1f / max(1f, attackMs * sampleRate / 1000f))
    private val release = exp(-1f / max(1f, releaseMs * sampleRate / 1000f))
    private var value = 0f

    fun reset() { value = 0f }

    fun process(input: Float): Float {
        val magnitude = abs(input)
        val coefficient = if (magnitude > value) attack else release
        value = magnitude + coefficient * (value - magnitude)
        return value
    }
}
