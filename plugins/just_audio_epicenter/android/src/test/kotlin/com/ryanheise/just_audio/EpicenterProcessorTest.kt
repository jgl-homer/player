package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class EpicenterProcessorTest {
    @Test fun selectionReallySwitchesEnginesAndPreservesOffBypass() {
        val p = configured(C.ENCODING_PCM_FLOAT)
        val input = ByteBuffer.allocate(4096).order(ByteOrder.LITTLE_ENDIAN)
        repeat(1024) { input.putFloat(0.2f) }
        val result = FloatArray(1024)
        fun process() {
            input.rewind()
            p.queueInput(input)
            val output = p.output.order(ByteOrder.LITTLE_ENDIAN)
            for (i in result.indices) result[i] = output.float
            assertTrue(result.all { it.isFinite() })
        }
        p.setEpicenterEnabled(true)
        repeat(30) { process() }
        assertEquals(0.2f, result.last(), 1e-6f)
        p.setEngine(EpicenterEngine.LEGACY)
        var previous = result.last()
        repeat(60) {
            process()
            for (frame in 0 until 512) {
                val value = result[2 * frame]
                assertTrue("switch discontinuity", kotlin.math.abs(value - previous) < 0.02f)
                previous = value
            }
        }
        // The full legacy engine retains its original DC highpass, SMART does not.
        assertTrue(kotlin.math.abs(result.last()) < 0.01f)
        p.setEngine(EpicenterEngine.SMART)
        repeat(40) { process() }
        assertEquals(0.2f, result.last(), 1e-6f)
        p.setEngine(EpicenterEngine.HYBRID)
        repeat(40) { process() }
        assertEquals(0.2f, result.last(), 1e-6f)
        p.setEpicenterEnabled(false)
        repeat(10) { process() }
        p.setEngine(EpicenterEngine.LEGACY)
        process()
        assertTrue(result.all { it == 0.2f })
        p.flush()
        p.setEpicenterEnabled(true)
        repeat(60) { process() }
        assertTrue(kotlin.math.abs(result.last()) < 0.01f)
    }

    private fun configured(encoding: Int, rate: Int = 48000): EpicenterAudioProcessor {
        val p = EpicenterAudioProcessor()
        p.configure(AudioProcessor.AudioFormat(rate, 2, encoding))
        p.flush()
        return p
    }
    @Test fun bypassCopiesAllPcmBytesIncluding32BitLowBits() {
        for (encoding in intArrayOf(C.ENCODING_PCM_16BIT, C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT)) {
            val p = configured(encoding)
            val bytes = ByteArray(24000) { (it * 73 + 19).toByte() }
            p.queueInput(ByteBuffer.wrap(bytes))
            val out = ByteArray(bytes.size)
            p.output.get(out)
            assertArrayEquals(bytes, out)
            p.setEpicenterEnabled(true); p.setIntensity(0f)
            p.queueInput(ByteBuffer.wrap(bytes)); p.output.get(out)
            assertArrayEquals(bytes, out)
        }
    }
    @Test fun disableFinishesRampThenCopiesBytesAndFlushClearsTail() {
        val p = configured(C.ENCODING_PCM_FLOAT)
        p.setEpicenterEnabled(true)
        val input = ByteBuffer.allocate(24000).order(ByteOrder.LITTLE_ENDIAN)
        repeat(6000) { input.putFloat(0.25f) }
        input.flip()
        p.queueInput(input); p.output
        p.setEpicenterEnabled(false)
        input.rewind(); p.queueInput(input); p.output
        input.rewind(); p.queueInput(input)
        val actual = ByteArray(24000); p.output.get(actual)
        assertArrayEquals(input.array(), actual)
        p.flush(); p.setEpicenterEnabled(true)
        val zeros = ByteBuffer.allocate(24000)
        p.queueInput(zeros); p.output.get(actual)
        assertTrue(actual.all { it == 0.toByte() })
    }
    @Test fun configureDoesNotMutateDrainingStreamUntilFlush() {
        val p = configured(C.ENCODING_PCM_16BIT)
        p.setEpicenterEnabled(true)
        p.configure(AudioProcessor.AudioFormat(96000, 2, C.ENCODING_PCM_24BIT))
        // Valid old-format frame, not a valid 24-bit frame.
        p.queueInput(ByteBuffer.allocate(4))
        assertEquals(4, p.output.remaining())
        p.flush()
        p.queueInput(ByteBuffer.allocate(6))
        assertEquals(6, p.output.remaining())
        p.reset()
    }
    @Test fun activePcmAllRatesHandlesChangingBufferSizes() {
        for (encoding in intArrayOf(C.ENCODING_PCM_16BIT, C.ENCODING_PCM_24BIT, C.ENCODING_PCM_32BIT, C.ENCODING_PCM_FLOAT)) {
            for (rate in intArrayOf(44100, 48000, 96000, 192000)) {
                val p = configured(encoding, rate)
                p.setEpicenterEnabled(true)
                val bytes = if (encoding == C.ENCODING_PCM_16BIT) 2 else if (encoding == C.ENCODING_PCM_24BIT) 3 else 4
                for (frames in intArrayOf(1, 128, 4096, 17, 256)) {
                    p.queueInput(ByteBuffer.allocate(frames * 2 * bytes))
                    assertEquals(frames * 2 * bytes, p.output.remaining())
                }
            }
        }
    }

    @Test fun activeWithoutGeneratedPreservesPcm32LowBits() {
        val p = configured(C.ENCODING_PCM_32BIT)
        p.setEpicenterEnabled(true)
        val input = ByteBuffer.allocate(8192).order(ByteOrder.LITTLE_ENDIAN)
        repeat(2048) { input.putInt(0x01234567) }
        input.flip(); p.queueInput(input)
        val output = ByteArray(8192); p.output.get(output)
        assertArrayEquals(input.array(), output)
    }
}
