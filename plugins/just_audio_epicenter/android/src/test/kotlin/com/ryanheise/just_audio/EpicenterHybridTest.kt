package com.ryanheise.just_audio

import org.junit.Assert.*
import org.junit.Test
import java.util.Random
import kotlin.math.*

class EpicenterHybridTest {
    private val rate = 48000
    private val params = EpicenterParams()

    private data class Run(
        val input: FloatArray,
        val output: FloatArray,
        val detectedF0: Float,
        val confidence: Float,
        val minimumHeadroomGain: Float,
        val minimumLimiterGain: Float,
    ) {
        fun delta(frame: Int) = ((output[2 * frame] - input[2 * frame]) +
            (output[2 * frame + 1] - input[2 * frame + 1])) * 0.5f
    }

    private fun missing(t: Double, fundamental: Double = 36.0, gain: Double = 1.0): Double = gain *
        (0.16 * sin(2 * PI * 2 * fundamental * t) +
            0.14 * sin(2 * PI * 3 * fundamental * t) +
            0.12 * sin(2 * PI * 4 * fundamental * t))

    private fun run(seconds: Double, engine: EpicenterEngine, settings: EpicenterParams = params,
        signal: (Double, Int) -> Double): Run {
        val frames = (seconds * rate).roundToInt()
        val input = FloatArray(frames * 2)
        val output = FloatArray(input.size)
        val chunk = FloatArray(960)
        val chunkOutput = FloatArray(chunk.size)
        val dsp = EpicenterDsp(rate, engine, debugEnabled = true)
        dsp.prepare(2, settings)
        var maxConfidence = 0f
        var detected = 0f
        var minHeadroom = 1f
        var minLimiter = 1f
        for (frame in 0 until frames) {
            val t = frame.toDouble() / rate
            input[2 * frame] = signal(t, 0).toFloat()
            input[2 * frame + 1] = signal(t, 1).toFloat()
        }
        var offset = 0
        while (offset < input.size) {
            val count = min(chunk.size, input.size - offset)
            input.copyInto(chunk, 0, offset, offset + count)
            dsp.processInterleaved(chunk, chunkOutput, 2, settings, count)
            chunkOutput.copyInto(output, offset, 0, count)
            if (dsp.debugState.detectedF0 > 0f) detected = dsp.debugState.detectedF0
            maxConfidence = max(maxConfidence, dsp.debugState.confidence)
            minHeadroom = min(minHeadroom, dsp.debugState.generatedGain)
            minLimiter = min(minLimiter, dsp.debugState.limiterGain)
            offset += count
        }
        assertTrue(output.all { it.isFinite() })
        return Run(input, output, detected, maxConfidence, minHeadroom, minLimiter)
    }

    private fun rms(run: Run, fromSeconds: Double, toSeconds: Double): Double {
        val from = (fromSeconds * rate).roundToInt().coerceAtLeast(0)
        val to = (toSeconds * rate).roundToInt().coerceAtMost(run.input.size / 2)
        var sum = 0.0
        for (frame in from until to) sum += run.delta(frame).toDouble().pow(2)
        return sqrt(sum / max(1, to - from))
    }

    private fun peak(run: Run): Double {
        var peak = 0.0
        for (frame in 0 until run.input.size / 2) peak = max(peak, abs(run.delta(frame).toDouble()))
        return peak
    }

    private fun magnitude(run: Run, frequency: Double, fromSeconds: Double, toSeconds: Double): Double {
        val from = (fromSeconds * rate).roundToInt()
        val to = (toSeconds * rate).roundToInt().coerceAtMost(run.input.size / 2)
        var re = 0.0; var im = 0.0
        for (frame in from until to) {
            val phase = 2 * PI * frequency * frame / rate
            val value = run.delta(frame)
            re += value * cos(phase); im += value * sin(phase)
        }
        return 2 * hypot(re, im) / max(1, to - from)
    }

    private fun onsetLatencyMs(run: Run, onsetSeconds: Double, noteEndSeconds: Double): Double {
        val steady = rms(run, onsetSeconds + 0.035, min(noteEndSeconds, onsetSeconds + 0.105))
        if (steady < 1e-7) return Double.POSITIVE_INFINITY
        val threshold = steady * 0.1 // -20 dB amplitude relative to in-note generated RMS.
        val window = (rate * 0.002).roundToInt()
        val start = (onsetSeconds * rate).roundToInt()
        val end = (noteEndSeconds * rate).roundToInt()
        var square = 0.0
        for (frame in start until end) {
            val value = run.delta(frame).toDouble()
            square += value * value
            if (frame >= start + window) {
                val old = run.delta(frame - window).toDouble()
                square -= old * old
                if (sqrt(max(0.0, square) / window) >= threshold) {
                    return (frame - window - start).toDouble() * 1000 / rate
                }
            }
        }
        return Double.POSITIVE_INFINITY
    }

    @Test fun shortNoteAttacksDuringNoteAndDropsBeforeLateTail() {
        val onset = 0.050
        val end = onset + 0.120
        fun fixture(t: Double, @Suppress("UNUSED_PARAMETER") channel: Int) =
            if (t in onset..<end) missing(t - onset) else 0.0
        val smart = run(0.45, EpicenterEngine.SMART, signal = ::fixture)
        val hybrid = run(0.45, EpicenterEngine.HYBRID, signal = ::fixture)
        val latency = onsetLatencyMs(hybrid, onset, end)
        val earlyHybrid = rms(hybrid, onset + .005, onset + .070)
        val earlySmart = rms(smart, onset + .005, onset + .070)
        val tail = rms(hybrid, end + .150, end + .250)
        println("SHORT_NOTE hybridLatencyMs=$latency earlyHybridRms=$earlyHybrid earlySmartRms=$earlySmart tail150to250Rms=$tail")
        assertTrue("hybrid onset latency $latency ms", latency < 20.0)
        assertTrue("generated must exist during 120 ms note", earlyHybrid > 0.002)
        assertTrue("hybrid fast path must beat SMART early", earlyHybrid > earlySmart * 2 + 0.001)
        assertTrue("late tail $tail", tail < earlyHybrid * 0.12)
    }

    @Test fun repeatedNortenaLikeNotesAttackAndLeaveGaps() {
        val fundamentals = doubleArrayOf(36.0, 42.0, 39.0, 46.0, 34.0)
        val run = run(1.10, EpicenterEngine.HYBRID) { t, _ ->
            val slot = (t / .200).toInt()
            val local = t - slot * .200
            if (slot in fundamentals.indices && local < .120) missing(local, fundamentals[slot]) else 0.0
        }
        for (slot in fundamentals.indices) {
            val start = slot * .200
            val note = rms(run, start + .010, start + .110)
            val lateGap = rms(run, start + .175, start + .195)
            println("REPEATED slot=$slot f=${fundamentals[slot]} noteRms=$note lateGapRms=$lateGap")
            assertTrue("note $slot generated", note > 0.002)
            assertTrue("gap $slot tail", lateGap < note * 0.42)
        }
    }

    @Test fun existingFundamentalVoiceNoiseAndSideStayRejected() {
        val existing40 = run(.55, EpicenterEngine.HYBRID) { t, _ -> 0.3 * sin(2 * PI * 40 * t) }
        assertTrue("must not generate 20 Hz", magnitude(existing40, 20.0, .15, .50) < 0.002)

        val voice = run(.70, EpicenterEngine.HYBRID) { t, _ ->
            0.08 * sin(2 * PI * 145 * t) + 0.2 * sin(2 * PI * 290 * t) + 0.2 * sin(2 * PI * 870 * t)
        }
        assertTrue("voice must not trigger transient punch ${rms(voice, 0.0, .65)}", rms(voice, 0.0, .65) < 0.002)
        assertTrue("voice persistent generated ${rms(voice, .3, .65)}", rms(voice, .3, .65) < 0.002)

        val random = Random(24680)
        val noiseSamples = DoubleArray((.70 * rate).toInt()) { (random.nextDouble() - .5) * .5 }
        val noise = run(.70, EpicenterEngine.HYBRID) { t, _ -> noiseSamples[(t * rate).toInt().coerceAtMost(noiseSamples.lastIndex)] }
        assertTrue("noise persistent generated ${rms(noise, .3, .65)}", rms(noise, .3, .65) < 0.002)

        val side = run(.55, EpicenterEngine.HYBRID) { t, channel -> missing(t) * if (channel == 0) 1 else -1 }
        assertTrue("L=-R generated ${rms(side, .2, .5)}", rms(side, .2, .5) < 1e-7)
    }

    @Test fun masteredSignalKeepsGeneratedPunchAndLinkedProtection() {
        val mastered = run(1.0, EpicenterEngine.HYBRID, params.copy(intensity = 85f)) { t, _ ->
            missing(t, gain = .72) + .58 * sin(2 * PI * 997 * t)
        }
        val generated = rms(mastered, .35, .95)
        val outputPeak = mastered.output.maxOf { abs(it) }
        println("MASTERED generatedRms=$generated outputPeak=$outputPeak headroomGain=${mastered.minimumHeadroomGain} limiterReduction=${1 - mastered.minimumLimiterGain}")
        assertTrue("generated survives mastered signal", generated > 0.004)
        assertTrue("headroom does not mute generated", mastered.minimumHeadroomGain >= 0.30f)
        assertTrue("protected output peak $outputPeak", outputPeak <= 0.9601f)

        val dsp = EpicenterDsp(rate, EpicenterEngine.HYBRID)
        val input = FloatArray(4096) { if (it % 2 == 0) 1.1f else 0.55f }
        val output = FloatArray(input.size)
        repeat(20) { dsp.processInterleaved(input, output, 2, params) }
        assertEquals("linked gain preserves L/R ratio", 2f, output[4000] / output[4001], 1e-5f)
    }

    @Test fun reportsComparableEngineMetricsForShortNotes() {
        val onset = .05; val end = .17
        for (engine in EpicenterEngine.entries) {
            val result = run(.45, engine) { t, _ -> if (t in onset..<end) missing(t - onset) else 0.0 }
            println("AB engine=$engine generatedRms=${rms(result, onset, end)} peak=${peak(result)} " +
                "onsetLatencyMs=${onsetLatencyMs(result, onset, end)} tail150to250Rms=${rms(result, end + .15, end + .25)} " +
                "detectedF0=${result.detectedF0} confidence=${result.confidence} " +
                "limiterReduction=${1 - result.minimumLimiterGain} headroomGain=${result.minimumHeadroomGain}")
        }
    }
}
