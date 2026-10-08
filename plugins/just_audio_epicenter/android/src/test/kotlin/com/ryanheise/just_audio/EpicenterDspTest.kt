package com.ryanheise.just_audio

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Random
import kotlin.math.*

class EpicenterDspTest {
    private val defaults = EpicenterParams()
    private fun missing(t: Double, f: Double = 36.0): Float =
        (0.16 * sin(2 * PI * 2 * f * t) + 0.14 * sin(2 * PI * 3 * f * t) + 0.12 * sin(2 * PI * 4 * f * t)).toFloat()

    private data class Run(val dsp: EpicenterDsp, val input: FloatArray, val output: FloatArray, val ns: Long) {
        fun deltaRms(): Double {
            var sum = 0.0
            for (i in output.size / 2 until output.size) sum += (output[i] - input[i]).toDouble().pow(2)
            return sqrt(sum / (output.size - output.size / 2))
        }
    }
    private fun run(rate: Int = 48000, seconds: Double = 2.0, params: EpicenterParams = defaults,
        opposite: Boolean = false, block: Int = 512, signal: (Double) -> Float): Run {
        val frames = (rate * seconds).toInt()
        val input = FloatArray(frames * 2)
        val output = FloatArray(input.size)
        val chunk = FloatArray(block * 2)
        val out = FloatArray(chunk.size)
        val dsp = EpicenterDsp(rate, debugEnabled = true)
        dsp.prepare(2, params)
        for (i in 0 until frames) {
            input[2 * i] = signal(i.toDouble() / rate)
            input[2 * i + 1] = input[2 * i] * if (opposite) -1 else 1
        }
        val start = System.nanoTime()
        var offset = 0
        while (offset < input.size) {
            val count = min(chunk.size, input.size - offset)
            input.copyInto(chunk, 0, offset, offset + count)
            dsp.processInterleaved(chunk, out, 2, params, count)
            out.copyInto(output, offset, 0, count)
            offset += count
        }
        val ns = System.nanoTime() - start
        assertTrue(output.all { it.isFinite() })
        val d = dsp.debugState
        println("rate=$rate f0=${d.detectedF0} smooth=${d.smoothedF0} confidence=${d.confidence} inputPeak=${d.inputPeak} generatedPeak=${d.generatedPeak} outputPeak=${d.outputPeak} rms=${d.rms} limiterReduction=${1 - d.limiterGain} realtimeRatio=${ns / 1e9 / seconds}")
        return Run(dsp, input, output, ns)
    }
    private fun magnitude(data: FloatArray, rate: Int, frequency: Double): Double {
        var real = 0.0; var imaginary = 0.0
        val start = data.size / 2 / 2
        val frames = data.size / 2
        for (i in start until frames) {
            val phase = 2 * PI * frequency * i / rate
            real += data[i * 2] * cos(phase); imaginary += data[i * 2] * sin(phase)
        }
        return 2 * hypot(real, imaginary) / (frames - start)
    }
    @Test fun missingFundamentalAcrossRates() {
        for (rate in intArrayOf(44100, 48000, 96000, 192000)) {
            val result = run(rate = rate, signal = { missing(it) })
            assertEquals("missing f0 at $rate", 36f, result.dsp.debugState.detectedF0, 1f)
            assertTrue("confidence at $rate", result.dsp.debugState.confidence > 0.72f)
            assertTrue("36 Hz must actually be generated", magnitude(result.output, rate, 36.0) > 0.012)
            assertTrue(result.dsp.debugState.smartMix > 0.95f)
        }
    }
    @Test fun silenceNoiseVoiceAndSideAreRejected() {
        val silence = run { 0f }
        assertEquals(0.0, silence.deltaRms(), 0.0)
        val random = Random(12345)
        val noise = run(seconds = 4.0) { (random.nextFloat() - 0.5f) * 0.5f }
        assertTrue("noise confidence", noise.dsp.debugState.confidence < 0.2f)
        assertTrue("noise generated rms ${noise.deltaRms()}", noise.deltaRms() < 0.002)
        val voice = run { t -> (0.08 * sin(2 * PI * 145 * t) + 0.2 * sin(2 * PI * 290 * t) + 0.2 * sin(2 * PI * 870 * t)).toFloat() }
        assertTrue("vocal proxy", voice.deltaRms() < 0.002)
        val side = run(opposite = true, signal = { missing(it) })
        assertEquals(0.0, side.deltaRms(), 1e-8)
        assertEquals(0f, side.dsp.debugState.confidence, 1e-6f)
    }
    @Test fun pure72IsStableAndExisting40IsNotHalved() {
        val sine = run { (0.3 * sin(2 * PI * 72 * it)).toFloat() }
        assertEquals(72f, sine.dsp.debugState.detectedF0, 1f)
        assertEquals(36f, sine.dsp.debugState.smoothedF0, 1f)
        val existing = run { (0.3 * sin(2 * PI * 40 * it)).toFloat() }
        assertTrue(existing.deltaRms() < 0.002)
        assertTrue(magnitude(existing.output, 48000, 20.0) < 0.001)
    }
    @Test fun followsNotesAndLocksAlternatingOctaves() {
        val result = run(seconds = 3.0) { t -> missing(t, if (t < 1.5) 36.0 else 42.0) }
        assertEquals(42f, result.dsp.debugState.smoothedF0, 1f)
        val tracker = BassPitchTracker()
        repeat(5) { tracker.update(36f, 1f) }
        repeat(50) { tracker.update(if (it % 2 == 0) 72f else 36f, 1f) }
        assertEquals(36f, tracker.stableF0, 0f)
        repeat(20) { tracker.update(42f, 1f) }
        assertEquals(42f, tracker.stableF0, 0f)
    }
    @Test fun intensityIsProgressiveAndDryPathIsUntouched() {
        var previous = -1.0
        for (level in floatArrayOf(0f, 1f, 10f, 25f, 50f, 75f, 100f)) {
            val r = run(params = defaults.copy(intensity = level)) { missing(it) }
            assertTrue("intensity $level", r.deltaRms() >= previous)
            previous = r.deltaRms()
            if (level == 0f) assertArrayEquals(r.input, r.output, 0f)
            // Generated is centered; original stereo difference is untouched below limiting.
            assertEquals(1f, r.dsp.debugState.limiterGain, 0f)
        }
        val mid = run { (0.4 * sin(2 * PI * 1000 * it)).toFloat() }
        assertArrayEquals(mid.input, mid.output, 1e-7f)
    }
    @Test fun headroomReducesGeneratedFirstAndLimiterIsLinked() {
        val low = run { missing(it) }
        val high = run { t -> (missing(t) * 0.05f + 0.94f * sin(2 * PI * 36 * t).toFloat()) }
        assertTrue(high.output.all { abs(it) <= 0.96001f })
        assertTrue(high.dsp.debugState.generatedPeak < low.dsp.debugState.generatedPeak)
        val dsp = EpicenterDsp(48000)
        val input = FloatArray(4096) { if (it % 2 == 0) 1.1f else 0.55f }
        val output = FloatArray(input.size)
        repeat(20) { dsp.processInterleaved(input, output, 2, defaults) }
        assertEquals(2f, output[4000] / output[4001], 1e-5f)
        assertTrue(abs(output[4000]) <= 0.96001f)
    }
    @Test fun bufferPartitionAndResetAreDeterministic() {
        val a = run(block = 128, signal = { missing(it) })
        val b = run(block = 1024, signal = { missing(it) })
        assertArrayEquals(a.output, b.output, 1e-6f)
        val input = FloatArray(2048)
        val output = FloatArray(2048)
        a.dsp.reset()
        a.dsp.processInterleaved(input, output, 2, defaults)
        assertTrue(output.all { it == 0f })
        repeat(2) { a.dsp.processInterleaved(input, output, 2, defaults, enabled = false) }
        assertTrue(a.dsp.isBypassed)
    }
    @Test fun pcmEndpointsAndNegative24SignExtension() {
        val buffer = ByteBuffer.allocate(64).order(ByteOrder.LITTLE_ENDIAN)
        for (bits in intArrayOf(16, 24, 32, 0)) {
            for (x in floatArrayOf(-1f, -0.75f, -0.0001f, 0f, 0.75f, 1f)) {
                buffer.clear(); EpicenterPcm.write(buffer, x, bits); buffer.flip()
                assertEquals("PCM$bits $x", x, EpicenterPcm.read(buffer, bits), if (bits == 16) 1f / 32768 else 2e-7f)
            }
        }
        buffer.clear(); buffer.put(0.toByte()); buffer.put(0.toByte()); buffer.put(0x80.toByte()); buffer.flip()
        assertEquals(-1f, EpicenterPcm.read(buffer, 24), 0f)
        buffer.clear(); repeat(3) { buffer.put(0xff.toByte()) }; buffer.flip()
        assertEquals(-1f / 8388608f, EpicenterPcm.read(buffer, 24), 0f)
    }
    @Test fun nonFiniteInputDoesNotPoisonDsp() {
        val dsp = EpicenterDsp(48000)
        val input = FloatArray(1024)
        input[0] = Float.NaN; input[1] = Float.POSITIVE_INFINITY
        val output = FloatArray(input.size)
        dsp.processInterleaved(input, output, 2, defaults)
        assertTrue(output.all { it.isFinite() })
    }

    @Test fun sweepDoesNotForcePitchAndWidthIsRealBandwidth() {
        val narrow = run(params = defaults.copy(sweepFreq = 63f, width = 0f)) { missing(it) }
        val wide = run(params = defaults.copy(sweepFreq = 63f, width = 100f)) { missing(it) }
        assertEquals(36f, narrow.dsp.debugState.smoothedF0, 1f)
        assertEquals(36f, wide.dsp.debugState.smoothedF0, 1f)
        assertTrue("wider filter admits off-center bass", wide.deltaRms() > narrow.deltaRms() * 1.5)
    }

    @Test fun hotOriginalUsesGeneratedHeadroomWithoutGlobalLimiting() {
        val result = run(params = defaults.copy(intensity = 100f)) { missing(it) * 2.45f }
        assertTrue(result.dsp.debugState.confidence > 0.9f)
        assertTrue("generated gain ${result.dsp.debugState.generatedGain}", result.dsp.debugState.generatedGain < 0.2f)
        assertEquals(1f, result.dsp.debugState.limiterGain, 1e-6f)
        assertTrue(result.output.all { abs(it) <= 0.96001f })
    }

    @Test fun generatedTransitionHasNoSingleSampleSteps() {
        val rate = 48000
        val dsp = EpicenterDsp(rate)
        val input = FloatArray(512 * 2)
        val output = FloatArray(input.size)
        var frame = 0; var previous = 0f; var maxStep = 0f
        var params = defaults
        repeat(400) { block ->
            if (block == 130) params = defaults.copy(sweepFreq = 63f, width = 0f, intensity = 100f)
            if (block == 220) params = defaults.copy(sweepFreq = 27f, width = 100f, intensity = 10f)
            for (i in 0 until 512) { input[2 * i] = missing((frame + i).toDouble() / rate); input[2 * i + 1] = input[2 * i] }
            dsp.processInterleaved(input, output, 2, params, enabled = block < 300)
            for (i in 0 until 512) {
                val delta = output[2 * i] - input[2 * i]
                maxStep = max(maxStep, abs(delta - previous)); previous = delta
            }
            frame += 512
        }
        println("generated maximum adjacent-sample step=$maxStep")
        assertTrue(maxStep < 0.015f)
        assertTrue(dsp.isBypassed)
        assertArrayEquals(input, output, 0f)
    }

    @Test fun steadyStateDoesNotAllocateAndReportsCallbackBudget() {
        // Reflection keeps the Android compile classpath independent of desktop JDK modules.
        val factory = Class.forName("java.lang.management.ManagementFactory")
        val bean = factory.getMethod("getThreadMXBean").invoke(null)
        val type = Class.forName("com.sun.management.ThreadMXBean")
        type.getMethod("setThreadAllocatedMemoryEnabled", Boolean::class.javaPrimitiveType).invoke(bean, true)
        val allocated = type.getMethod("getThreadAllocatedBytes", Long::class.javaPrimitiveType)
        val id = Thread.currentThread().id
        fun allocatedBytes() = allocated.invoke(bean, id) as Long
        val input = FloatArray(1024) { missing((it / 2).toDouble() / 48000) }
        val output = FloatArray(input.size)
        val dsp = EpicenterDsp(48000)
        dsp.prepare(2, defaults)
        repeat(500) { dsp.processInterleaved(input, output, 2, defaults) }
        val times = LongArray(1000)
        // Warm reflection and the timed loop as well as the DSP before measuring.
        repeat(1000) {
            allocatedBytes()
            val start = System.nanoTime()
            dsp.processInterleaved(input, output, 2, defaults)
            times[it] = System.nanoTime() - start
        }
        val calibration = allocatedBytes()
        val meterOverhead = allocatedBytes() - calibration
        val allocations = LongArray(3)
        repeat(allocations.size) { pass ->
            val before = allocatedBytes()
            repeat(times.size) {
                val start = System.nanoTime()
                dsp.processInterleaved(input, output, 2, defaults)
                times[it] = System.nanoTime() - start
            }
            allocations[pass] = allocatedBytes() - before - meterOverhead
        }
        times.sort()
        println("allocation bytes by warmed 1000-callback pass=${allocations.contentToString()}; callback p50=${times[500]}ns p95=${times[950]}ns p99=${times[990]}ns; budget=10666667ns (desktop JVM)")
        assertEquals("DSP recurring hot path allocation", 0L, allocations.last())
        assertTrue("p99 real-time budget on test host", times[990] < 10666667L)
    }
}
