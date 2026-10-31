package com.jglhomer.player.autodj

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

object AutoDjTempoDetector {
    data class Result(val bpm: Double, val confidence: Double, val phase: Int)

    fun estimate(rawEnvelope: DoubleArray, framesPerSecond: Double): Result {
        if (rawEnvelope.size < 32) return Result(0.0, 0.0, 0)
        val envelope = rawEnvelope.copyOf()
        val mean = envelope.average()
        for (index in envelope.indices) {
            envelope[index] = max(0.0, envelope[index] - mean * 0.5)
        }
        var bestLag = 0
        var bestScore = Double.NEGATIVE_INFINITY
        var secondScore = Double.NEGATIVE_INFINITY
        val minLag = (framesPerSecond * 60.0 / 200.0).roundToInt()
        val maxLag = min(
            envelope.size / 3,
            (framesPerSecond * 60.0 / 60.0).roundToInt(),
        )
        for (lag in minLag..maxLag) {
            var product = 0.0
            var left = 0.0
            var right = 0.0
            for (index in lag until envelope.size) {
                product += envelope[index] * envelope[index - lag]
                left += envelope[index] * envelope[index]
                right += envelope[index - lag] * envelope[index - lag]
            }
            val normalized =
                if (left <= 0 || right <= 0) 0.0 else product / sqrt(left * right)
            val bpm = 60.0 * framesPerSecond / lag
            val weighted = normalized * if (bpm in 75.0..150.0) 1.03 else 1.0
            if (weighted > bestScore) {
                secondScore = bestScore
                bestScore = weighted
                bestLag = lag
            } else if (weighted > secondScore) {
                secondScore = weighted
            }
        }
        if (bestLag == 0) return Result(0.0, 0.0, 0)

        var bestPhase = 0
        var phaseScore = Double.NEGATIVE_INFINITY
        for (phase in 0 until bestLag) {
            var score = 0.0
            var index = phase
            while (index < envelope.size) {
                score += envelope[index]
                index += bestLag
            }
            if (score > phaseScore) {
                phaseScore = score
                bestPhase = phase
            }
        }
        val separation = if (bestScore <= 0) {
            0.0
        } else {
            (bestScore - max(0.0, secondScore)) / bestScore
        }
        val confidence = (bestScore * 0.78 + separation * 0.22).coerceIn(0.0, 1.0)
        return Result(60.0 * framesPerSecond / bestLag, confidence, bestPhase)
    }
}
