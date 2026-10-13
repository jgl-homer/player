package com.ryanheise.just_audio

import kotlin.math.*

/** RBJ biquad, transposed direct form II. Only analysis/generated paths use it. */
internal class BassFilter(private val rate: Double) {
    private var b0 = 1.0; private var b1 = 0.0; private var b2 = 0.0
    private var a1 = 0.0; private var a2 = 0.0
    private var z1 = 0.0; private var z2 = 0.0
    fun configure(type: Int, frequency: Double, q: Double = 0.70710678) {
        val w = 2 * PI * frequency.coerceIn(5.0, rate * 0.45) / rate
        val c = cos(w); val alpha = sin(w) / (2 * q)
        val scale = 1 / (1 + alpha)
        when (type) {
            0 -> { b0 = (1 - c) * 0.5 * scale; b1 = (1 - c) * scale; b2 = b0 }
            1 -> { b0 = (1 + c) * 0.5 * scale; b1 = -(1 + c) * scale; b2 = b0 }
            else -> { b0 = alpha * scale; b1 = 0.0; b2 = -b0 }
        }
        a1 = -2 * c * scale; a2 = (1 - alpha) * scale
    }
    fun process(x: Float): Float {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        if (abs(z1) < 1e-24) z1 = 0.0
        if (abs(z2) < 1e-24) z2 = 0.0
        return y.toFloat()
    }
    fun reset() { z1 = 0.0; z2 = 0.0 }
}

/** Bounded autocorrelation + harmonic projections; no work arrays per hop. */
internal class BassAnalyzer(sampleRate: Int) {
    private val decimation = max(1, sampleRate / 2400)
    private val rate = sampleRate.toDouble() / decimation
    private val size = (rate * 0.096).roundToInt()
    private val hop = (rate * 0.010).roundToInt()
    private val maxLag = ceil(rate / 27).toInt() + 1
    private val minLag = floor(rate / 180).toInt()
    private val ring = FloatArray(size)
    private val window = FloatArray(size)
    private val hann = DoubleArray(size) { 0.5 - 0.5 * cos(2 * PI * it / (size - 1)) }
    private val hannSum = hann.sum()
    private val correlation = DoubleArray(maxLag + 1)
    private val candidates = DoubleArray(8)
    private val ranks = DoubleArray(8)
    // Eighth-order anti-alias filter before decimation, separate lower cutoff.
    private val low = Array(4) { BassFilter(sampleRate.toDouble()) }
    private val high = BassFilter(sampleRate.toDouble())
    private val sideLow = BassFilter(sampleRate.toDouble())
    private var cursor = 0; private var filled = 0; private var count = 0; private var hopCount = 0
    private var midEnergy = 0.0; private var sideEnergy = 0.0; private var fullEnergy = 0.0
    private val energyStep = 1 - exp(-1.0 / (sampleRate * 0.096))
    var detectedF0 = 0f; private set
    var targetHz = 0f; private set
    var confidence = 0f; private set
    var hybridConfidence = 0f; private set
    var restoration = 0f; private set
    var bandSample = 0f; private set
    var periodicity = 0f; private set
    var harmonicFit = 0f; private set
    var bassRatio = 0f; private set
    var coherence = 0f; private set
    init {
        val qs = doubleArrayOf(0.50979558, 0.60134489, 0.89997622, 2.56291545)
        for (i in low.indices) low[i].configure(0, 200.0, qs[i])
        high.configure(1, 25.0)
        sideLow.configure(0, 200.0)
    }
    fun reset() {
        ring.fill(0f); window.fill(0f); correlation.fill(0.0)
        low.forEach { it.reset() }; high.reset(); sideLow.reset()
        cursor = 0; filled = 0; count = 0; hopCount = 0
        midEnergy = 0.0; sideEnergy = 0.0; fullEnergy = 0.0
        detectedF0 = 0f; targetHz = 0f; confidence = 0f; hybridConfidence = 0f; restoration = 0f
        bandSample = 0f; periodicity = 0f; harmonicFit = 0f; bassRatio = 0f; coherence = 0f
    }
    fun push(mid: Float, side: Float, sweep: Float, width: Float): Boolean {
        var x = high.process(mid)
        for (filter in low) x = filter.process(x)
        bandSample = x
        val s = sideLow.process(side)
        // Match energy time constants to the pitch window, not the 10 ms hop.
        midEnergy += energyStep * (x * x - midEnergy)
        sideEnergy += energyStep * (s * s - sideEnergy)
        fullEnergy += energyStep * (mid * mid - fullEnergy)
        if (++count < decimation) return false
        count = 0
        ring[cursor] = x
        cursor = (cursor + 1) % size
        if (filled < size) filled++
        if (++hopCount < hop || filled < size) return false
        hopCount = 0
        analyze(sweep, width)
        return true
    }
    private fun analyze(sweep: Float, width: Float) {
        for (i in 0 until size) window[i] = ring[(cursor + i) % size]
        var energy = 0.0
        var mean = 0.0
        for (x in window) mean += x
        mean /= size
        for (i in window.indices) { window[i] = (window[i] - mean).toFloat(); energy += window[i] * window[i] }
        energy /= size
        confidence = 0f; hybridConfidence = 0f; restoration = 0f; bassRatio = 0f; coherence = 0f
        if (energy < 1e-8 || midEnergy < 1e-10) { detectedF0 = 0f; targetHz = 0f; return }
        for (lag in minLag - 1..maxLag) {
            var xy = 0.0; var xx = 0.0; var yy = 0.0
            for (i in 0 until size - lag) {
                val x = window[i].toDouble(); val y = window[i + lag].toDouble()
                xy += x * y; xx += x * x; yy += y * y
            }
            correlation[lag] = (xy / sqrt(max(1e-30, xx * yy))).coerceIn(-1.0, 1.0)
        }
        candidates.fill(0.0); ranks.fill(-1.0)
        for (lag in minLag until maxLag) {
            val c = correlation[lag]
            if (c < 0.65 || c < correlation[lag - 1] || c < correlation[lag + 1]) continue
            val denominator = correlation[lag - 1] - 2 * c + correlation[lag + 1]
            val offset = if (abs(denominator) > 1e-12)
                (0.5 * (correlation[lag - 1] - correlation[lag + 1]) / denominator).coerceIn(-0.5, 0.5) else 0.0
            val frequency = rate / (lag + offset)
            if (frequency !in 27.0..180.0) continue
            for (j in candidates.indices) {
                if (c > ranks[j]) {
                    for (k in candidates.lastIndex downTo j + 1) { ranks[k] = ranks[k - 1]; candidates[k] = candidates[k - 1] }
                    ranks[j] = c; candidates[j] = frequency
                    break
                }
            }
        }
        var best = -1.0; var bestF = 0.0; var bestPeriodic = 0.0; var bestFit = 0.0
        var bestFundamental = 0.0; var bestHarmonics = 0.0
        for (j in candidates.indices) {
            val f = candidates[j]
            if (f == 0.0) continue
            val fundamental = power(f)
            var harmonics = 0.0
            for (h in 2..4) if (f * h <= 195) harmonics += power(f * h)
            val fit = ((fundamental + harmonics) / energy).coerceIn(0.0, 1.0)
            val restorationHz = if (f > 63) f / 2 else f
            val q = 2.8 - 2.1 * width / 100.0
            val preference = 1 / (1 + ((restorationHz - sweep) / (sweep / q)).pow(2))
            val continuity = if (detectedF0 > 0 && abs(ln(f / detectedF0)) < 0.07) 0.012 else 0.0
            // Prefer the shortest supported period when harmonics cannot distinguish octaves.
            val score = 0.52 * ranks[j] + 0.43 * fit + 0.018 * f / 180 + 0.015 * preference + continuity
            if (score > best) {
                best = score; bestF = f; bestPeriodic = ranks[j]; bestFit = fit
                bestFundamental = fundamental; bestHarmonics = harmonics
            }
        }
        if (bestF == 0.0) { detectedF0 = 0f; targetHz = 0f; return }
        detectedF0 = bestF.toFloat()
        periodicity = bestPeriodic.toFloat(); harmonicFit = bestFit.toFloat()
        val coherenceValue = (midEnergy / (midEnergy + sideEnergy + 1e-20)).coerceIn(0.0, 1.0)
        val bassRatioValue = (midEnergy / (fullEnergy + 1e-20)).coerceIn(0.0, 1.0)
        coherence = coherenceValue.toFloat()
        bassRatio = bassRatioValue.toFloat()
        val tonal = ((bestPeriodic - 0.80) / 0.18).coerceIn(0.0, 1.0)
        val fitGate = ((bestFit - 0.50) / 0.40).coerceIn(0.0, 1.0)
        val vocalGuard = ((bassRatioValue - 0.08) / 0.45).coerceIn(0.0, 1.0)
        confidence = (tonal * fitGate * coherenceValue * vocalGuard).toFloat()
        // HYBRID may confirm bass under a loud centered mix without weakening the
        // conservative SMART reference. Absolute bass presence complements the
        // ratio guard; pitch/harmonic and MID coherence remain mandatory.
        val bassAmplitude = sqrt(midEnergy)
        val presence = ((bassAmplitude - 0.002) / 0.030).coerceIn(0.0, 1.0)
        val ratioSupport = ((bassRatioValue - 0.015) / 0.22).coerceIn(0.0, 1.0)
        val hybridTonal = ((bestPeriodic - 0.72) / 0.24).coerceIn(0.0, 1.0)
        val hybridFit = ((bestFit - 0.35) / 0.48).coerceIn(0.0, 1.0)
        // Absolute presence may rescue a true multi-harmonic missing fundamental
        // under a loud mix. Ambiguous octave-down candidates above 63 Hz must
        // still occupy a meaningful share of the program (voice guard).
        val hybridBassSupport = if (bestF <= 63.0) max(presence * 0.82, ratioSupport) else ratioSupport
        hybridConfidence = (hybridTonal * hybridFit * coherenceValue * hybridBassSupport).toFloat()
        targetHz = (if (bestF > 63) bestF / 2 else bestF).toFloat()
        if (targetHz !in 27f..63f) { confidence = 0f; hybridConfidence = 0f; restoration = 0f; return }
        restoration = if (bestF > 63) 0.55f else
            ((bestHarmonics / (bestFundamental + bestHarmonics + 1e-20) - 0.45) / 0.5).coerceIn(0.0, 1.0).toFloat()
    }
    private fun power(frequency: Double): Double {
        val coefficient = 2 * cos(2 * PI * frequency / rate)
        var a = 0.0; var b = 0.0
        for (i in window.indices) {
            val next = window[i] * hann[i] + coefficient * a - b
            b = a; a = next
        }
        return max(0.0, 2 * (a * a + b * b - coefficient * a * b) / (hannSum * hannSum))
    }
}

internal class BassPitchTracker {
    var stableF0 = 0f; private set
    var candidateF0 = 0f; private set
    var previousF0 = 0f; private set
    var stableFrames = 0; private set
    private var octaveFrames = 0
    fun reset() { stableF0 = 0f; candidateF0 = 0f; previousF0 = 0f; stableFrames = 0; octaveFrames = 0 }
    fun update(frequency: Float, confidence: Float, requiredFrames: Int = 3, minimumConfidence: Float = 0.5f) {
        if (confidence < minimumConfidence || frequency <= 0f) { stableFrames = 0; return }
        if (candidateF0 > 0f && abs(ln(frequency / candidateF0)) < 0.06f) stableFrames++ else stableFrames = 1
        candidateF0 = frequency
        if (stableFrames < requiredFrames) return
        val octave = stableF0 > 0f && abs(abs(ln(frequency / stableF0)) - ln(2f)) < 0.06f
        if (octave && ++octaveFrames < 12) return
        octaveFrames = 0
        previousF0 = stableF0
        stableF0 = frequency
    }
}
