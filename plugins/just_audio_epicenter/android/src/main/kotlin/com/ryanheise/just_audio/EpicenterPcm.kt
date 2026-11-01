package com.ryanheise.just_audio

import java.nio.ByteBuffer
import kotlin.math.roundToLong

/** Little-endian PCM; bits == 0 denotes IEEE float32. */
internal object EpicenterPcm {
    fun read(buffer: ByteBuffer, bits: Int): Float = when (bits) {
        16 -> buffer.short / 32768f
        24 -> {
            val value = (buffer.get().toInt() and 255) or
                ((buffer.get().toInt() and 255) shl 8) or (buffer.get().toInt() shl 16)
            value / 8388608f
        }
        32 -> buffer.int / 2147483648f
        else -> buffer.float.let { if (it.isFinite()) it else 0f }
    }
    fun write(buffer: ByteBuffer, value: Float, bits: Int) {
        val x = if (value.isFinite()) value else 0f
        if (bits == 0) { buffer.putFloat(x); return }
        val scale = when (bits) { 16 -> 32768.0; 24 -> 8388608.0; else -> 2147483648.0 }
        val n = (x.coerceIn(-1f, 1f) * scale).roundToLong().coerceIn(-scale.toLong(), scale.toLong() - 1).toInt()
        when (bits) {
            16 -> buffer.putShort(n.toShort())
            24 -> { buffer.put(n.toByte()); buffer.put((n shr 8).toByte()); buffer.put((n shr 16).toByte()) }
            else -> buffer.putInt(n)
        }
    }
}
