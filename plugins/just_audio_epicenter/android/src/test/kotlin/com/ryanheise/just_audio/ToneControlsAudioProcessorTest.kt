package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

class ToneControlsAudioProcessorTest {
    @Test
    fun disabledProcessorCopiesEveryPcmFormatByteExact() {
        for (encoding in intArrayOf(
            C.ENCODING_PCM_16BIT,
            C.ENCODING_PCM_24BIT,
            C.ENCODING_PCM_32BIT,
            C.ENCODING_PCM_FLOAT,
        )) {
            val processor = configured(encoding)
            val bytesPerSample = if (encoding == C.ENCODING_PCM_16BIT) 2
                else if (encoding == C.ENCODING_PCM_24BIT) 3 else 4
            val source = ByteArray(257 * 2 * bytesPerSample) { index ->
                (index * 61 + 17).toByte()
            }
            processor.queueInput(ByteBuffer.wrap(source))
            val result = ByteArray(source.size)
            processor.output.get(result)
            assertArrayEquals(source, result)
            assertTrue(processor.isBypassed)
        }
    }

    @Test
    fun replayGainRampsToRequestedLevel() {
        val processor = configured(C.ENCODING_PCM_FLOAT)
        processor.setControls(false, FloatArray(5), true, -6.0206f, 0f)
        var result = FloatArray(2048)
        repeat(60) { result = processFloat(processor, 1024, 0.5f, 0.5f) }
        assertEquals(0.25f, result[result.size - 2], 0.004f)
        assertEquals(0.25f, result[result.size - 1], 0.004f)
    }

    @Test
    fun limiterIsStereoLinkedAndStaysBelowCeiling() {
        val processor = configured(C.ENCODING_PCM_FLOAT)
        processor.setControls(false, FloatArray(5), true, 12f, 0f)
        var result = FloatArray(2048)
        repeat(80) { result = processFloat(processor, 1024, 0.8f, 0.4f) }
        val left = result[result.size - 2]
        val right = result[result.size - 1]
        assertTrue(abs(left) <= 0.981f)
        assertTrue(abs(right) <= 0.981f)
        assertEquals(2f, left / right, 0.01f)
    }

    @Test
    fun equalizerChangesSignalWithoutProducingInvalidSamples() {
        val processor = configured(C.ENCODING_PCM_FLOAT)
        processor.setControls(true, floatArrayOf(6f, 0f, 0f, 0f, 0f), false, 0f, 0f)
        var result = FloatArray(2048)
        var dry = FloatArray(2048)
        var phase = 0.0
        repeat(80) {
            val input = ByteBuffer.allocate(1024 * 2 * 4).order(ByteOrder.LITTLE_ENDIAN)
            val currentDry = FloatArray(2048)
            repeat(1024) { frame ->
                val sample = (0.25 * kotlin.math.sin(phase)).toFloat()
                phase += 2.0 * Math.PI * 20.0 / 48000.0
                input.putFloat(sample).putFloat(sample)
                currentDry[frame * 2] = sample
                currentDry[frame * 2 + 1] = sample
            }
            dry = currentDry
            input.flip()
            processor.queueInput(input)
            val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)
            for (index in result.indices) result[index] = output.float
        }
        assertTrue(result.all { it.isFinite() && abs(it) <= 0.981f })
        val meanDifference = result.indices.sumOf {
            abs(result[it] - dry[it]).toDouble()
        } / result.size
        assertTrue(meanDifference > 0.005)
    }

    @Test
    fun disablingFinishesFadeThenReturnsToByteExactBypass() {
        val processor = configured(C.ENCODING_PCM_32BIT)
        processor.setControls(true, floatArrayOf(0f, 3f, 0f, 0f, 0f), false, 0f, 0f)
        val source = ByteBuffer.allocate(8192).order(ByteOrder.LITTLE_ENDIAN)
        repeat(2048) { source.putInt(0x12345678) }
        repeat(20) {
            source.rewind()
            processor.queueInput(source)
            processor.output
        }
        processor.setControls(false, FloatArray(5), false, 0f, 0f)
        repeat(80) {
            source.rewind()
            processor.queueInput(source)
            processor.output
        }
        source.rewind()
        processor.queueInput(source)
        val result = ByteArray(source.capacity())
        processor.output.get(result)
        assertArrayEquals(source.array(), result)
        assertTrue(processor.isBypassed)
    }

    private fun configured(encoding: Int): ToneControlsAudioProcessor {
        return ToneControlsAudioProcessor().also {
            it.configure(AudioProcessor.AudioFormat(48000, 2, encoding))
            it.flush()
        }
    }

    private fun processFloat(
        processor: ToneControlsAudioProcessor,
        frames: Int,
        left: Float,
        right: Float,
    ): FloatArray {
        val input = ByteBuffer.allocate(frames * 2 * 4).order(ByteOrder.LITTLE_ENDIAN)
        repeat(frames) { input.putFloat(left).putFloat(right) }
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)
        return FloatArray(frames * 2) { output.float }
    }
}
