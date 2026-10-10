package com.ryanheise.just_audio

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

/** Characterization, not a perceptual acceptance test or a target tuning curve. */
class EpicenterComparisonTest {
    private val rate = 48000
    private fun tone(t: Double, hz: Double, amplitude: Double) = amplitude * sin(2 * PI * hz * t)
    private fun missing(t: Double) = tone(t, 72.0, .16) + tone(t, 108.0, .14) + tone(t, 144.0, .12)

    private data class Measurement(val sub36: Double, val deltaRms: Double, val confidence: Double)

    private fun measure(name: String, engine: EpicenterEngine, params: EpicenterParams,
        signal: (Double, Int) -> Double): Measurement {
        val dsp = EpicenterDsp(rate, engine, debugEnabled = true)
        dsp.prepare(2, params)
        val input = FloatArray(960)
        val output = FloatArray(input.size)
        var re = 0.0; var im = 0.0; var deltaEnergy = 0.0; var measured = 0
        var confidence = 0.0; var smart = 0.0; var headroom = 0.0; var readings = 0
        repeat(300) { block ->
            for (i in 0 until 480) {
                val t = (block * 480 + i).toDouble() / rate
                for (ch in 0..1) input[2 * i + ch] = signal(t, ch).toFloat()
            }
            dsp.processInterleaved(input, output, 2, params)
            assertTrue("$name $engine finite", output.all { it.isFinite() })
            if (block >= 100) {
                for (i in 0 until 480) {
                    val t = (block * 480 + i).toDouble() / rate
                    val delta = (output[2 * i] - input[2 * i]).toDouble()
                    re += delta * cos(2 * PI * 36 * t)
                    im += delta * sin(2 * PI * 36 * t)
                    deltaEnergy += delta * delta
                    measured++
                }
                confidence += dsp.debugState.confidence
                smart += dsp.debugState.smartMix
                headroom += dsp.debugState.generatedGain
                readings++
            }
        }
        val result = Measurement(2 * hypot(re, im) / measured, sqrt(deltaEnergy / measured), confidence / readings)
        println("CASE=$name ENGINE=$engine sweep=${params.sweepFreq} width=${params.width} intensity=${params.intensity} sub36=${result.sub36} deltaRms=${result.deltaRms}" +
            if (engine != EpicenterEngine.LEGACY) " confidence=${result.confidence} smartWeight=${smart / readings} headroomGain=${headroom / readings}" else "")
        return result
    }

    @Test fun compareRestorationUnderControlledMixtures() {
        val cases = linkedMapOf<String, (Double, Int) -> Double>(
            "missing36" to { t, _ -> missing(t) },
            "missing36_plus_mid" to { t, _ -> missing(t) * .35 + tone(t, 1000.0, .40) },
            "missing36_plus_other_bass" to { t, _ -> missing(t) * .65 + tone(t, 83.0, .16) + tone(t, 117.0, .12) },
            "missing36_plus_stereo_mid" to { t, ch -> missing(t) * .35 + tone(t, 1000.0, if (ch == 0) .40 else -.40) },
            "hot_missing36" to { t, _ -> missing(t) * 2.45 },
            "existing40" to { t, _ -> tone(t, 40.0, .30) },
        )
        for (params in listOf(EpicenterParams(), EpicenterParams(sweepFreq = 32f, width = 67f, intensity = 67f))) {
            for ((name, signal) in cases) {
                val legacy = measure(name, EpicenterEngine.LEGACY, params, signal)
                val smart = measure(name, EpicenterEngine.SMART, params, signal)
                val hybrid = measure(name, EpicenterEngine.HYBRID, params, signal)
                if (name == "missing36") {
                    assertTrue("LEGACY generates missing sub", legacy.sub36 > .001)
                    assertTrue("SMART generates missing sub", smart.sub36 > .001)
                    assertTrue("HYBRID generates missing sub", hybrid.sub36 > .001)
                }
                if (name == "missing36_plus_mid") assertTrue("HYBRID survives centered program", hybrid.deltaRms > .002)
                if (name == "existing40") assertTrue("SMART preserves existing bass", smart.deltaRms < .002)
                if (name == "existing40") assertTrue("HYBRID preserves existing bass", hybrid.deltaRms < .002)
            }
        }
    }
}
