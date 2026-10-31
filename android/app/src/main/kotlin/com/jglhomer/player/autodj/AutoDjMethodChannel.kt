package com.jglhomer.player.autodj

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.Future

class AutoDjMethodChannel(context: Context, messenger: BinaryMessenger) {
    private val analyzer = AutoDjAnalyzer(context.applicationContext)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, CHANNEL)
    @Volatile private var activeTask: Future<*>? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "analyzeAudio" -> {
                    val path = call.argument<String>("path")
                    val size = call.argument<Number>("fileSize")?.toLong()
                    val modified = call.argument<Number>("modifiedAtMs")?.toLong()
                    val version = call.argument<Number>("analyzerVersion")?.toInt()
                    if (path == null || size == null || modified == null || version == null) {
                        result.error("INVALID_ARGUMENT", "path and file identity are required", null)
                        return@setMethodCallHandler
                    }
                    if (activeTask?.isDone == false) {
                        result.error("BUSY", "An AutoDJ analysis is already running", null)
                        return@setMethodCallHandler
                    }
                    activeTask = executor.submit {
                        try {
                            val analysis = analyzer.analyze(path, size, modified, version)
                            mainHandler.post { result.success(analysis) }
                        } catch (_: AutoDjAnalyzer.AnalysisCancelledException) {
                            mainHandler.post { result.error("CANCELLED", "Analysis cancelled", null) }
                        } catch (error: Throwable) {
                            mainHandler.post {
                                result.error("ANALYSIS_FAILED", error.message, error.stackTraceToString())
                            }
                        }
                    }
                }
                "cancelAnalysis" -> {
                    analyzer.cancel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        analyzer.cancel()
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    companion object {
        private const val CHANNEL = "com.jglhomer.player/autodj"
    }
}
