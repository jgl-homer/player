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
import android.media.audiofx.Virtualizer
import android.media.audiofx.BassBoost

class MainActivity : AudioServiceActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.example.player/media_utils"
    private val WIDGET_CHANNEL = "com.example.player/widget_actions"
    private var pendingResult: MethodChannel.Result? = null
    private val DELETE_REQUEST_CODE = 1001
    private var widgetMethodChannel: MethodChannel? = null
    private val EFFECTS_CHANNEL = "com.example.player/audio_effects"
    private var environmentalReverb: EnvironmentalReverb? = null
    private var virtualizer: Virtualizer? = null
    private var bassBoost: BassBoost? = null
    private var myFlutterEngine: FlutterEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        this.myFlutterEngine = flutterEngine

        // Canal para acciones del widget
        widgetMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)

        // Canal para efectos (Native DSP)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EFFECTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initDSP" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    if (sessionId != null) {
                        try {
                            if (environmentalReverb == null || environmentalReverb?.hasControl() == false || environmentalReverb?.id != sessionId) {
                                environmentalReverb?.release()
                                environmentalReverb = EnvironmentalReverb(0, sessionId)
                            }
                            if (virtualizer == null || virtualizer?.hasControl() == false || virtualizer?.id != sessionId) {
                                virtualizer?.release()
                                virtualizer = Virtualizer(0, sessionId)
                            }
                            if (bassBoost == null || bassBoost?.hasControl() == false || bassBoost?.id != sessionId) {
                                bassBoost?.release()
                                bassBoost = BassBoost(0, sessionId)
                            }
                            
                            // Load config parameters but don't force enable yet
                            environmentalReverb?.apply {
                                decayTime = call.argument<Int>("decayTime") ?: 1800
                                decayHFRatio = call.argument<Int>("decayHFRatio")?.toShort() ?: 600
                                reflectionsLevel = call.argument<Int>("reflectionsLevel")?.toShort() ?: -1500
                                reverbLevel = call.argument<Int>("reverbLevel")?.toShort() ?: -1200
                                roomLevel = call.argument<Int>("roomLevel")?.toShort() ?: -400
                                density = call.argument<Int>("density")?.toShort() ?: 1000
                                diffusion = call.argument<Int>("diffusion")?.toShort() ?: 1000
                            }
                            virtualizer?.setStrength((call.argument<Int>("virtualizerStrength") ?: 700).toShort())
                            bassBoost?.setStrength((call.argument<Int>("bassBoostStrength") ?: 400).toShort())

                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error initializing DSP: \${e.message}", e)
                            result.error("DSP_INIT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "sessionId required", null)
                    }
                }
                "toggleReverb" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    environmentalReverb?.enabled = enable
                    if (enable && environmentalReverb != null) {
                        applyAuxEffect(environmentalReverb!!.id, 1.0f)
                    } else if (!enable && environmentalReverb != null) {
                        applyAuxEffect(0, 0.0f)
                    }
                    result.success(true)
                }
                "toggleVirtualizer" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    virtualizer?.enabled = enable
                    result.success(true)
                }
                "toggleBass" -> {
                    val enable = call.argument<Boolean>("enable") ?: false
                    bassBoost?.enabled = enable
                    result.success(true)
                }
                "releaseEffects" -> {
                    environmentalReverb?.release()
                    environmentalReverb = null
                    virtualizer?.release()
                    virtualizer = null
                    bassBoost?.release()
                    bassBoost = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

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
                else -> result.notImplemented()
            }
        }
    }

    private fun applyAuxEffect(effectId: Int, sendLevel: Float) {
        try {
            val pluginClass = Class.forName("com.ryanheise.just_audio.JustAudioPlugin")
            @Suppress("UNCHECKED_CAST")
            val plugin = myFlutterEngine?.plugins?.get(pluginClass as Class<out io.flutter.embedding.engine.plugins.FlutterPlugin>)
            if (plugin != null) {
                val playersField = pluginClass.getDeclaredField("players")
                playersField.isAccessible = true
                val players = playersField.get(plugin) as Map<*, *>
                for (playerEntry in players.values) {
                    if (playerEntry != null) {
                        val exoPlayerField = playerEntry::class.java.getDeclaredField("player")
                        exoPlayerField.isAccessible = true
                        val exoPlayer = exoPlayerField.get(playerEntry)
                        
                        if (exoPlayer != null) {
                            try {
                                val auxEffectInfoClass = Class.forName("com.google.android.exoplayer2.audio.AuxEffectInfo")
                                val auxEffectInfoConstructor = auxEffectInfoClass.getConstructor(Int::class.java, Float::class.java)
                                val auxInfo = auxEffectInfoConstructor.newInstance(effectId, sendLevel)
                                
                                val setMethod = exoPlayer::class.java.getMethod("setAuxEffectInfo", auxEffectInfoClass)
                                setMethod.invoke(exoPlayer, auxInfo)
                                Log.d(TAG, "Successfully injected AuxEffectInfo effectId=$effectId to ExoPlayer2 (sendLevel=$sendLevel)")
                            } catch(e: ClassNotFoundException) {
                                val auxEffectInfoClass = Class.forName("androidx.media3.exoplayer.audio.AuxEffectInfo")
                                val auxEffectInfoConstructor = auxEffectInfoClass.getConstructor(Int::class.java, Float::class.java)
                                val auxInfo = auxEffectInfoConstructor.newInstance(effectId, sendLevel)
                                
                                val setMethod = exoPlayer::class.java.getMethod("setAuxEffectInfo", auxEffectInfoClass)
                                setMethod.invoke(exoPlayer, auxInfo)
                                Log.d(TAG, "Successfully injected AuxEffectInfo effectId=$effectId to Media3 ExoPlayer (sendLevel=$sendLevel)")
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to inject AuxEffectInfo via reflection: ${e.message}", e)
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
}
