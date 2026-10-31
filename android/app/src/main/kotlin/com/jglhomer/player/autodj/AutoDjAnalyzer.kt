package com.jglhomer.player.autodj

import android.content.Context
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.ReturnCode
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Offline, deterministic analysis used by AutoDJ. It never touches playback DSP. */
class AutoDjAnalyzer(private val context: Context) {
    private val cancelled = AtomicBoolean(false)

    fun cancel() {
        cancelled.set(true)
    }

    fun analyze(
        path: String,
        fileSize: Long,
        modifiedAtMs: Long,
        analyzerVersion: Int,
    ): Map<String, Any?> {
        cancelled.set(false)
        val source = File(path)
        require(source.isFile) { "Audio file does not exist: $path" }

        val pcm = File.createTempFile("autodj_", ".pcm", context.cacheDir)
        try {
            decodeToPcm(source, pcm)
            checkCancelled()
            val signal = readSignal(pcm)
            check(signal.frames.isNotEmpty()) { "Decoded audio contains no PCM samples" }
            checkCancelled()

            val tempo = estimateTempo(signal.frames)
            val beatGrid = buildBeatGrid(signal.durationMs, tempo)
            val downbeats = chooseDownbeats(beatGrid, signal.frames)
            val silenceRegions = regionsBelow(signal.frames, signal.silenceThreshold, 900)
            val lowEnergyRegions = regionsBelow(signal.frames, signal.lowEnergyThreshold, 1800)
            val introEnd = findIntroEnd(signal.frames, signal.lowEnergyThreshold)
            val outroStart = findOutroStart(signal.frames, signal.lowEnergyThreshold)
            val cues = recommendedCues(
                beatGrid = beatGrid,
                downbeats = downbeats,
                introEndMs = introEnd,
                outroStartMs = outroStart,
                durationMs = signal.durationMs,
            )

            return linkedMapOf(
                "fileIdentity" to identity(source, fileSize, modifiedAtMs),
                "path" to path,
                "fileSize" to fileSize,
                "modifiedAtMs" to modifiedAtMs,
                "analyzerVersion" to analyzerVersion,
                "durationMs" to signal.durationMs,
                "bpm" to tempo.bpm,
                "bpmConfidence" to tempo.confidence,
                "beatGridMs" to beatGrid,
                "downbeatsMs" to downbeats,
                "energy" to signal.energy,
                "rmsDb" to amplitudeToDb(signal.rms),
                "peakDb" to amplitudeToDb(signal.peak),
                // A mono RMS estimate. It is intentionally labelled as an approximation
                // in the UI rather than presented as EBU R128 integrated loudness.
                "loudnessLufs" to amplitudeToDb(signal.rms) - 0.691,
                "lowEnergyRegionsMs" to lowEnergyRegions,
                "silenceRegionsMs" to silenceRegions,
                "introEndMs" to introEnd,
                "outroStartMs" to outroStart,
                "recommendedCuePointsMs" to cues,
                "musicalKey" to null,
                "analyzedAtMs" to System.currentTimeMillis(),
            )
        } finally {
            pcm.delete()
        }
    }

    private fun decodeToPcm(source: File, output: File) {
        val command = listOf(
            "-y", "-v", "error", "-i", quote(source.absolutePath),
            "-map", "0:a:0", "-vn", "-ac", "1", "-ar", SAMPLE_RATE.toString(),
            "-f", "s16le", quote(output.absolutePath),
        ).joinToString(" ")
        val session = FFmpegKit.execute(command)
        check(ReturnCode.isSuccess(session.returnCode)) {
            "FFmpeg decode failed: ${session.failStackTrace ?: session.output}"
        }
    }

    private fun readSignal(file: File): SignalSummary {
        val frames = ArrayList<FrameEnergy>()
        var totalSquares = 0.0
        var sampleCount = 0L
        var peak = 0.0
        var frameSquares = 0.0
        var framePeak = 0.0
        var frameSamples = 0
        var previousRms = 0.0
        val bytes = ByteArray(64 * 1024)

        BufferedInputStream(FileInputStream(file)).use { input ->
            var carried: Int? = null
            while (true) {
                checkCancelled()
                val count = input.read(bytes)
                if (count < 0) break
                var index = 0
                if (carried != null && count > 0) {
                    val value = ((bytes[0].toInt() shl 8) or carried).toShort().toInt()
                    val amplitude = abs(value / 32768.0)
                    frameSquares += amplitude * amplitude
                    totalSquares += amplitude * amplitude
                    framePeak = max(framePeak, amplitude)
                    peak = max(peak, amplitude)
                    frameSamples++
                    sampleCount++
                    index = 1
                    carried = null
                }
                while (index + 1 < count) {
                    val value = ((bytes[index + 1].toInt() shl 8) or
                        (bytes[index].toInt() and 0xff)).toShort().toInt()
                    val amplitude = abs(value / 32768.0)
                    frameSquares += amplitude * amplitude
                    totalSquares += amplitude * amplitude
                    framePeak = max(framePeak, amplitude)
                    peak = max(peak, amplitude)
                    frameSamples++
                    sampleCount++
                    if (frameSamples == FRAME_SAMPLES) {
                        val rms = sqrt(frameSquares / frameSamples)
                        frames += FrameEnergy(
                            rms = rms,
                            peak = framePeak,
                            onset = max(0.0, rms - previousRms),
                        )
                        previousRms = rms
                        frameSquares = 0.0
                        framePeak = 0.0
                        frameSamples = 0
                    }
                    index += 2
                }
                if (index < count) carried = bytes[index].toInt() and 0xff
            }
        }
        if (frameSamples > 0) {
            val rms = sqrt(frameSquares / frameSamples)
            frames += FrameEnergy(rms, framePeak, max(0.0, rms - previousRms))
        }

        val rms = if (sampleCount == 0L) 0.0 else sqrt(totalSquares / sampleCount)
        val sorted = frames.map { it.rms }.sorted()
        val median = percentile(sorted, 0.5)
        val p20 = percentile(sorted, 0.2)
        val p80 = percentile(sorted, 0.8)
        val dynamic = max(1e-5, p80 - p20)
        val energy = ((rms * 8.0) + (dynamic * 4.0)).coerceIn(0.0, 1.0)
        return SignalSummary(
            frames = frames,
            durationMs = (sampleCount * 1000L / SAMPLE_RATE).toInt(),
            rms = rms,
            peak = peak,
            energy = energy,
            silenceThreshold = min(0.008, max(0.0015, median * 0.16)),
            lowEnergyThreshold = max(0.006, p20 + dynamic * 0.18),
        )
    }

    private fun estimateTempo(frames: List<FrameEnergy>): TempoEstimate {
        val envelope = frames.map { it.onset }.toDoubleArray()
        val fps = SAMPLE_RATE.toDouble() / FRAME_SAMPLES
        val result = AutoDjTempoDetector.estimate(envelope, fps)
        return TempoEstimate(result.bpm, result.confidence, result.phase)
    }

    private fun buildBeatGrid(durationMs: Int, tempo: TempoEstimate): List<Int> {
        if (tempo.bpm <= 0) return emptyList()
        val interval = 60000.0 / tempo.bpm
        var position = tempo.phase * FRAME_MS
        val beats = ArrayList<Int>()
        while (position < durationMs) {
            beats += position.roundToInt()
            position += interval
        }
        return beats
    }

    private fun chooseDownbeats(beats: List<Int>, frames: List<FrameEnergy>): List<Int> {
        if (beats.size < 4) return beats
        var bestOffset = 0
        var bestScore = Double.NEGATIVE_INFINITY
        for (offset in 0..3) {
            var score = 0.0
            var index = offset
            while (index < beats.size) {
                val frame = (beats[index] / FRAME_MS).roundToInt().coerceIn(0, frames.lastIndex)
                score += frames[frame].rms
                index += 4
            }
            if (score > bestScore) {
                bestScore = score
                bestOffset = offset
            }
        }
        return beats.filterIndexed { index, _ -> index % 4 == bestOffset }
    }

    private fun regionsBelow(
        frames: List<FrameEnergy>,
        threshold: Double,
        minimumMs: Int,
    ): List<List<Int>> {
        val regions = ArrayList<List<Int>>()
        var start = -1
        for (index in 0..frames.size) {
            val below = index < frames.size && frames[index].rms <= threshold
            if (below && start < 0) start = index
            if (!below && start >= 0) {
                val startMs = (start * FRAME_MS).roundToInt()
                val endMs = (index * FRAME_MS).roundToInt()
                if (endMs - startMs >= minimumMs) regions += listOf(startMs, endMs)
                start = -1
            }
        }
        return regions
    }

    private fun findIntroEnd(frames: List<FrameEnergy>, threshold: Double): Int {
        val sustained = max(1, (1400.0 / FRAME_MS).roundToInt())
        for (index in 0..max(0, frames.size - sustained)) {
            if ((index until min(frames.size, index + sustained)).all { frames[it].rms > threshold }) {
                return (index * FRAME_MS).roundToInt()
            }
        }
        return 0
    }

    private fun findOutroStart(frames: List<FrameEnergy>, threshold: Double): Int {
        val sustained = max(1, (2200.0 / FRAME_MS).roundToInt())
        for (index in max(0, frames.size - sustained) downTo 0) {
            if ((index until min(frames.size, index + sustained)).all { frames[it].rms <= threshold }) {
                return (index * FRAME_MS).roundToInt()
            }
        }
        return (frames.size * FRAME_MS * 0.78).roundToInt()
    }

    private fun recommendedCues(
        beatGrid: List<Int>,
        downbeats: List<Int>,
        introEndMs: Int,
        outroStartMs: Int,
        durationMs: Int,
    ): List<Int> {
        val cues = linkedSetOf(0)
        nearest(downbeats.ifEmpty { beatGrid }, introEndMs)?.let(cues::add)
        nearest(downbeats.ifEmpty { beatGrid }, outroStartMs)?.let(cues::add)
        downbeats.filterIndexed { index, value -> index % 8 == 0 && value in 1 until durationMs }
            .forEach(cues::add)
        return cues.sorted()
    }

    private fun nearest(values: List<Int>, target: Int): Int? =
        values.minByOrNull { abs(it - target) }

    private fun identity(file: File, size: Long, modified: Long): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("${file.absolutePath}:$size:$modified".toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun percentile(sorted: List<Double>, percentile: Double): Double {
        if (sorted.isEmpty()) return 0.0
        return sorted[(sorted.lastIndex * percentile).roundToInt().coerceIn(0, sorted.lastIndex)]
    }

    private fun amplitudeToDb(amplitude: Double): Double =
        if (amplitude <= 1e-9) -120.0 else 20.0 * ln(amplitude) / ln(10.0)

    private fun quote(value: String): String = "'${value.replace("'", "'\\''")}'"

    private fun checkCancelled() {
        if (cancelled.get()) throw AnalysisCancelledException()
    }

    private data class FrameEnergy(val rms: Double, val peak: Double, val onset: Double)
    private data class TempoEstimate(val bpm: Double, val confidence: Double, val phase: Int)
    private data class SignalSummary(
        val frames: List<FrameEnergy>,
        val durationMs: Int,
        val rms: Double,
        val peak: Double,
        val energy: Double,
        val silenceThreshold: Double,
        val lowEnergyThreshold: Double,
    )

    class AnalysisCancelledException : RuntimeException("Analysis cancelled")

    companion object {
        private const val SAMPLE_RATE = 11025
        private const val FRAME_SAMPLES = 512
        private const val FRAME_MS = FRAME_SAMPLES * 1000.0 / SAMPLE_RATE
    }
}
