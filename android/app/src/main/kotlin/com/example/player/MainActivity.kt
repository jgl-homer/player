package com.example.player

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import android.media.audiofx.EnvironmentalReverb

class MainActivity : AudioServiceActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.example.player/media_utils"
    private val WIDGET_CHANNEL = "com.example.player/widget_actions"
    private var pendingResult: MethodChannel.Result? = null
    private val DELETE_REQUEST_CODE = 1001
    private var widgetMethodChannel: MethodChannel? = null
    private var myFlutterEngine: FlutterEngine? = null

    private var reverb: EnvironmentalReverb? = null
    private var currentSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        this.myFlutterEngine = flutterEngine

        // Canal para acciones del widget
        widgetMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "delete_media" -> {
                    val idArg = call.argument<Any>("id")
                    val id = when (idArg) {
                        is Int -> idArg.toLong()
                        is Long -> idArg
                        is Number -> idArg.toLong()
                        is String -> idArg.toLongOrNull()
                        else -> null
                    }
                    
                    Log.d(TAG, "delete_media request for ID: $id (raw: $idArg)")
                    
                    if (id != null) {
                        deleteMedia(id, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Song ID is required and must be a number (got: $idArg)", null)
                    }
                }
                "extract_metadata" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val metadata = MediaUtils.getSongMetadata(path)
                        result.success(metadata)
                    } else {
                        result.error("INVALID_ARGUMENT", "Path is required", null)
                    }
                }
                "init_reverb" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    if (sessionId != 0) {
                        setupReverb(sessionId)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Session ID is required", null)
                    }
                }
                "enableReverb" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    if (sessionId != 0) {
                        setupReverb(sessionId)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Session ID is required", null)
                    }
                }
                "update_reverb" -> {
                    val params = call.arguments as? Map<String, Any>
                    if (params != null) {
                        applyReverbParams(params)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Params are required", null)
                    }
                }
                "setReverbParams" -> {
                    val params = call.arguments as? Map<String, Any>
                    if (params != null) {
                        applyReverbParams(params)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Params are required", null)
                    }
                }
                "toggle_reverb" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    reverb?.enabled = enabled
                    result.success(true)
                }
                "setBypass" -> {
                    val bypass = call.argument<Boolean>("bypass") ?: false
                    reverb?.enabled = !bypass
                    result.success(true)
                }
                "releaseReverb" -> {
                    reverb?.release()
                    reverb = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun deleteMedia(id: Long, result: MethodChannel.Result) {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        Log.d(TAG, "Deleting media URI: $uri")
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Android 11+ require createDeleteRequest for Scoped Storage
                val pendingIntent = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                pendingResult = result
                startIntentSenderForResult(pendingIntent.intentSender, DELETE_REQUEST_CODE, null, 0, 0, 0)
            } else {
                // Older Android or Legacy Storage
                val deletedRows = contentResolver.delete(uri, null, null)
                Log.d(TAG, "Deleted rows: $deletedRows")
                if (deletedRows > 0) {
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in deleteMedia: ${e.message}", e)
            result.error("DELETE_FAILED", e.message, null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.getStringExtra("widget_action") ?: return
        val dartAction = when (action) {
            MusicWidgetProvider.ACTION_PREVIOUS -> "previous"
            MusicWidgetProvider.ACTION_PLAY_PAUSE -> "play_pause"
            MusicWidgetProvider.ACTION_NEXT -> "next"
            else -> return
        }
        widgetMethodChannel?.invokeMethod("widget_action", dartAction)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == DELETE_REQUEST_CODE) {
            Log.d(TAG, "onActivityResult for delete request. ResultCode: $resultCode")
            if (resultCode == Activity.RESULT_OK) {
                pendingResult?.success(true)
            } else {
                // Often RESULT_CANCELED if the user denies the system dialog
                pendingResult?.success(false)
            }
            pendingResult = null
        }
    }

    private fun setupReverb(sessionId: Int) {
        if (reverb != null && currentSessionId == sessionId) return
        
        try {
            reverb?.release()
            reverb = EnvironmentalReverb(0, sessionId)
            currentSessionId = sessionId
            reverb?.enabled = true
            Log.d(TAG, "Reverb initialized for session: $sessionId")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up reverb: ${e.message}")
        }
    }

    private fun applyReverbParams(params: Map<String, Any>) {
        val r = reverb ?: return
        try {
            (params["decayTime"] as? Number)?.let { r.decayTime = it.toInt() }
            (params["reflectionsDelay"] as? Number)?.let { r.reflectionsDelay = it.toInt() }
            (params["reverbDelay"] as? Number)?.let { r.reverbDelay = it.toInt() }
            (params["roomLevel"] as? Number)?.let { r.roomLevel = it.toInt().toShort() }
            (params["density"] as? Number)?.let { r.density = it.toInt().toShort() }
            (params["diffusion"] as? Number)?.let { r.diffusion = it.toInt().toShort() }
            (params["decayHFRatio"] as? Number)?.let { r.decayHFRatio = it.toInt().toShort() }
            (params["reverbLevel"] as? Number)?.let { r.reverbLevel = it.toInt().toShort() }
            Log.d(TAG, "Reverb parameters applied: $params")
        } catch (e: Exception) {
            Log.e(TAG, "Error applying reverb params: ${e.message}")
        }
    }
}
