package com.jglhomer.player.autodj

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class AutoDjTempoDetectorTest {
    @Test
    fun detectsRegular120BpmPulseTrain() {
        val fps = 40.0
        val envelope = pulseTrain(fps, bpm = 120.0, seconds = 30)
        val result = AutoDjTempoDetector.estimate(envelope, fps)

        assertEquals(120.0, result.bpm, 0.5)
        assertTrue(result.confidence > 0.5)
    }

    @Test
    fun normalizes70BpmPulseTrainToMusicallyEquivalent140() {
        val fps = 40.0
        val envelope = pulseTrain(fps, bpm = 70.0, seconds = 40)
        val result = AutoDjTempoDetector.estimate(envelope, fps)

        assertTrue(abs(result.bpm - 70.0) < 1.5 || abs(result.bpm - 140.0) < 1.5)
        assertTrue(result.confidence > 0.45)
    }

    private fun pulseTrain(fps: Double, bpm: Double, seconds: Int): DoubleArray {
        val frames = DoubleArray((fps * seconds).toInt())
        val interval = fps * 60.0 / bpm
        var position = 3.0
        var beat = 0
        while (position < frames.size) {
            frames[position.toInt()] = if (beat % 4 == 0) 1.0 else 0.72
            position += interval
            beat++
        }
        return frames
    }
}
