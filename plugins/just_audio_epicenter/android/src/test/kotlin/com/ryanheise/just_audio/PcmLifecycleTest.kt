package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class PcmLifecycleTest {
    @Test fun allProcessorsSurviveFormatsChannelsFlushAndReset() {
        for (engine in EpicenterEngine.values()) {
            val epicenter = EpicenterAudioProcessor()
            epicenter.setEngine(engine)
            val tone = ToneControlsAudioProcessor()
            for (channels in intArrayOf(1, 2, 6)) {
                for (rate in intArrayOf(44100, 48000, 96000, 192000)) {
                    for (bits in intArrayOf(16, 24, 32, 0)) {
                        val encoding = when (bits) {
                            16 -> C.ENCODING_PCM_16BIT
                            24 -> C.ENCODING_PCM_24BIT
                            32 -> C.ENCODING_PCM_32BIT
                            else -> C.ENCODING_PCM_FLOAT
                        }
                        val format = AudioProcessor.AudioFormat(rate, channels, encoding)
                        for (processor in listOf(epicenter, tone)) {
                            processor.configure(format)
                            processor.flush()
                            val size = 8192 * channels * (if (bits == 0) 4 else bits / 8)
                            val original = ByteArray(size) { (it * 13).toByte() }
                            processor.queueInput(ByteBuffer.wrap(original))
                            val copy = ByteArray(size)
                            processor.output.get(copy)
                            assertArrayEquals(original, copy)
                        }
                        epicenter.setEpicenterEnabled(true)
                        tone.setControls(true, floatArrayOf(2f, 0f, 0f, 0f, 0f), true, -3f, 0f)
                        for (processor in listOf(epicenter, tone)) {
                            val input = ByteBuffer.allocate(8192 * channels * (if (bits == 0) 4 else bits / 8))
                                .order(ByteOrder.LITTLE_ENDIAN)
                            repeat(8192 * channels) { EpicenterPcm.write(input, 0.1f, bits) }
                            input.flip()
                            processor.queueInput(input)
                            val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)
                            assertEquals(input.capacity(), output.remaining())
                            while (output.hasRemaining()) assertTrue(EpicenterPcm.read(output, bits).isFinite())
                            processor.flush() // seek/new track: no signal tail survives
                            processor.queueInput(ByteBuffer.allocate(input.capacity()))
                            val silence = ByteArray(input.capacity())
                            processor.output.get(silence)
                            assertTrue(silence.all { it == 0.toByte() })
                            processor.reset()
                        }
                        epicenter.setEpicenterEnabled(false)
                        tone.setControls(false, FloatArray(5), false, 0f, 0f)
                    }
                }
            }
        }
    }
}
