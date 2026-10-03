package com.jglhomer.player

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import android.media.MediaMetadataRetriever
import android.view.WindowManager
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.media.AudioDeviceCallback

class MainActivity : AudioServiceActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.jglhomer.player/media_utils"
    private val WIDGET_CHANNEL = "com.jglhomer.player/widget_actions"
    private val SAF_CHANNEL = "com.jglhomer.player/saf_utils"
    private var pendingResult: MethodChannel.Result? = null
    private val DELETE_REQUEST_CODE = 1001
    private val SAF_REQUEST_CODE = 1002
    private var pendingSafResult: MethodChannel.Result? = null
    private var widgetMethodChannel: MethodChannel? = null
    private var mediaMethodChannel: MethodChannel? = null
    private var safMethodChannel: MethodChannel? = null
    private var mediaObserver: ContentObserver? = null
    private var myFlutterEngine: FlutterEngine? = null
    private var bluetoothReceiver: BroadcastReceiver? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null

    private var reverb: EnvironmentalReverb? = null
    private var virtualizer: Virtualizer? = null
    private var equalizer: Equalizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var currentSessionId: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        this.myFlutterEngine = flutterEngine

        widgetMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)

        mediaMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        mediaMethodChannel?.setMethodCallHandler { call, result ->
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
                "extractEmbeddedArtwork" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(filePath)
                            val bytes = retriever.embeddedPicture
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.success(null)
                        } finally {
                            retriever.release()
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
                    }
                }
                "extractEmbeddedLyrics" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        result.success(MediaUtils.getEmbeddedLyrics(filePath))
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is required", null)
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
                    setConcertHallEnabled(enabled)
                    result.success(true)
                }
                "setBypass" -> {
                    val bypass = call.argument<Boolean>("bypass") ?: false
                    setConcertHallEnabled(!bypass)
                    result.success(true)
                }
                "toggle_epicenter" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    com.ryanheise.just_audio.EpicenterProcessorController.setEpicenterEnabled(enabled)
                    Log.d(TAG, "Epicenter realtime enabled: $enabled")
                    result.success(true)
                }
                "set_epicenter_params" -> {
                    val params = call.arguments as? Map<String, Any>
                    if (params == null) {
                        result.error("INVALID_ARGUMENT", "Params are required", null)
                    } else {
                        applyEpicenterParams(params)
                        result.success(true)
                    }
                }
                "set_keep_screen_on" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }
                "releaseReverb" -> {
                    releaseConcertHallEffects()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        registerMediaObserver()
        registerBluetoothReceiver()
        registerAudioDeviceObserver()

        // ── Bug #3: SAF Channel para escritura en SD Card ─────────────────────
        safMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL
        )
        safMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSdCardAccess" -> {
                    pendingSafResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                        )
                    }
                    startActivityForResult(intent, SAF_REQUEST_CODE)
                }
                "hasPersistedPermission" -> {
                    val treeUriStr = call.argument<String>("treeUri")
                    if (treeUriStr == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val treeUri = Uri.parse(treeUriStr)
                    val persisted = contentResolver.persistedUriPermissions
                        .any { it.uri == treeUri && it.isWritePermission }
                    result.success(persisted)
                }
                "getPersistedTreeUri" -> {
                    val uri = contentResolver.persistedUriPermissions
                        .firstOrNull { it.isWritePermission }
                        ?.uri?.toString()
                    result.success(uri)
                }
                "writeFileViaSaf" -> {
                    val filePath = call.argument<String>("filePath")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (filePath == null || bytes == null) {
                        result.error("INVALID_ARGUMENT", "filePath and bytes are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val success = writeFileViaSaf(filePath, bytes)
                        result.success(success)
                    } catch (e: Exception) {
                        Log.e(TAG, "writeFileViaSaf error: ${e.message}", e)
                        result.error("WRITE_FAILED", e.message, null)
                    }
                }
                "writeByDocumentUri" -> {
                    val documentUriStr = call.argument<String>("documentUri")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (documentUriStr == null || bytes == null) {
                        result.error("INVALID_ARGUMENT", "documentUri and bytes are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val documentUri = Uri.parse(documentUriStr)
                        contentResolver.openOutputStream(documentUri, "wt")?.use { out ->
                            out.write(bytes)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "writeByDocumentUri error: ${e.message}", e)
                        result.error("WRITE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerMediaObserver() {
        if (mediaObserver != null) return

        mediaObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                Log.d(TAG, "MediaStore changed: $uri")
                runOnUiThread {
                    mediaMethodChannel?.invokeMethod("media_changed", null)
                }
            }
        }

        contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            true,
            mediaObserver!!
        )
    }


    private fun applyEpicenterParams(params: Map<String, Any>) {
        (params["sweepFreq"] as? Number)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setSweepFreq(it.toFloat()) }
        (params["width"] as? Number)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setWidth(it.toFloat()) }
        (params["intensity"] as? Number)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setIntensity(it.toFloat()) }
        (params["balance"] as? Number)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setBalance(it.toFloat()) }
        (params["volume"] as? Number)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setVolume(it.toFloat()) }
    }
    private fun deleteMedia(id: Long, result: MethodChannel.Result) {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        Log.d(TAG, "Deleting media URI: $uri")

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val pendingIntent = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                pendingResult = result
                startIntentSenderForResult(pendingIntent.intentSender, DELETE_REQUEST_CODE, null, 0, 0, 0)
            } else {
                val deletedRows = contentResolver.delete(uri, null, null)
                Log.d(TAG, "Deleted rows: $deletedRows")
                result.success(deletedRows > 0)
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
        when (requestCode) {
            DELETE_REQUEST_CODE -> {
                Log.d(TAG, "onActivityResult for delete request. ResultCode: $resultCode")
                if (resultCode == Activity.RESULT_OK) {
                    pendingResult?.success(true)
                } else {
                    pendingResult?.success(false)
                }
                pendingResult = null
            }
            SAF_REQUEST_CODE -> {
                // Bug #3: Persistir el URI de árbol SAF que el usuario concedió
                if (resultCode == Activity.RESULT_OK) {
                    val treeUri = data?.data
                    if (treeUri != null) {
                        // Persistir el permiso para que sobreviva reinicios de la app
                        contentResolver.takePersistableUriPermission(
                            treeUri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        )
                        Log.d(TAG, "SAF tree URI persisted: $treeUri")
                        pendingSafResult?.success(treeUri.toString())
                    } else {
                        pendingSafResult?.success(null)
                    }
                } else {
                    pendingSafResult?.success(null)
                }
                pendingSafResult = null
            }
        }
    }

    override fun onDestroy() {
        mediaObserver?.let { contentResolver.unregisterContentObserver(it) }
        mediaObserver = null
        bluetoothReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        bluetoothReceiver = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioDeviceCallback?.let {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                try { audioManager?.unregisterAudioDeviceCallback(it) } catch (_: Exception) {}
            }
            audioDeviceCallback = null
        }
        super.onDestroy()
    }

    private fun registerAudioDeviceObserver() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (audioDeviceCallback != null) return
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return

        audioDeviceCallback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                super.onAudioDevicesAdded(addedDevices)
                val hasAudioOutput = addedDevices?.any { device ->
                    device.isSink && (
                        device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                        device.type == AudioDeviceInfo.TYPE_USB_HEADSET
                    )
                } ?: false

                if (hasAudioOutput) {
                    Log.d(TAG, "Audio output device connected — notifying Dart")
                    runOnUiThread {
                        mediaMethodChannel?.invokeMethod("bluetooth_connected", null)
                    }
                }
            }
        }
        audioManager.registerAudioDeviceCallback(audioDeviceCallback, Handler(Looper.getMainLooper()))
    }

    private fun registerBluetoothReceiver() {
        if (bluetoothReceiver != null) return
        bluetoothReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == BluetoothDevice.ACTION_ACL_CONNECTED) {
                    Log.d(TAG, "Bluetooth device connected — notifying Dart")
                    runOnUiThread {
                        mediaMethodChannel?.invokeMethod("bluetooth_connected", null)
                    }
                }
            }
        }
        val filter = IntentFilter(BluetoothDevice.ACTION_ACL_CONNECTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(bluetoothReceiver, filter)
        }
    }

    private fun setupReverb(sessionId: Int) {
        if (reverb != null && currentSessionId == sessionId) return

        releaseConcertHallEffects()
        currentSessionId = sessionId
        reverb = createEffect("EnvironmentalReverb") { EnvironmentalReverb(0, sessionId) }
        virtualizer = createEffect("Virtualizer") { Virtualizer(0, sessionId) }
        equalizer = createEffect("Equalizer") { Equalizer(0, sessionId) }
        loudnessEnhancer = createEffect("LoudnessEnhancer") { LoudnessEnhancer(sessionId) }
        setConcertHallEnabled(true)
        Log.d(TAG, "Concert Hall FX initialized for session: $sessionId")
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

            (params["virtualizerStrength"] as? Number)?.let { strength ->
                virtualizer?.setStrength(strength.toInt().coerceIn(0, 1000).toShort())
            }

            (params["loudnessGainMb"] as? Number)?.let { gain ->
                loudnessEnhancer?.setTargetGain(gain.toInt().coerceIn(0, 2000))
            }

            (params["eqGains"] as? List<*>)?.let { gains ->
                applyEqGains(gains)
            }

            Log.d(TAG, "Concert Hall parameters applied: $params")
        } catch (e: Exception) {
            Log.e(TAG, "Error applying Concert Hall params: ${e.message}")
        }
    }

    private fun <T> createEffect(name: String, factory: () -> T): T? {
        return try {
            factory()
        } catch (e: Exception) {
            Log.e(TAG, "$name is not available: ${e.message}")
            null
        }
    }

    private fun setConcertHallEnabled(enabled: Boolean) {
        setEffectEnabled("EnvironmentalReverb") { reverb?.enabled = enabled }
        setEffectEnabled("Virtualizer") { virtualizer?.enabled = enabled }
        setEffectEnabled("Equalizer") { equalizer?.enabled = enabled }
        setEffectEnabled("LoudnessEnhancer") { loudnessEnhancer?.enabled = enabled }
    }

    private fun setEffectEnabled(name: String, setter: () -> Unit) {
        try {
            setter()
        } catch (e: Exception) {
            Log.e(TAG, "Error toggling $name: ${e.message}")
        }
    }

    private fun applyEqGains(gains: List<*>) {
        val eq = equalizer ?: return
        val bandCount = eq.numberOfBands.toInt()
        if (bandCount <= 0 || gains.isEmpty()) return

        val minLevel = eq.bandLevelRange[0].toInt()
        val maxLevel = eq.bandLevelRange[1].toInt()
        val lastGainIndex = gains.lastIndex.coerceAtLeast(0)

        for (band in 0 until bandCount) {
            val sourceIndex = if (bandCount == 1) 0 else
                ((band * lastGainIndex).toFloat() / (bandCount - 1)).toInt()
            val db = (gains[sourceIndex] as? Number)?.toDouble() ?: 0.0
            val millibels = (db * 100).toInt().coerceIn(minLevel, maxLevel)
            eq.setBandLevel(band.toShort(), millibels.toShort())
        }
    }

    private fun releaseConcertHallEffects() {
        try {
            reverb?.release()
            virtualizer?.release()
            equalizer?.release()
            loudnessEnhancer?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing Concert Hall FX: ${e.message}")
        } finally {
            reverb = null
            virtualizer = null
            equalizer = null
            loudnessEnhancer = null
        }
    }

    // ── Bug #3: SAF helpers para escritura en SD Card ─────────────────────────

    /**
     * Resuelve [filePath] (ej: /storage/ABCD-1234/Music/song.mp3) a un
     * Document URI SAF usando el árbol de permisos persistido, y escribe
     * [bytes] en ese archivo.
     *
     * Algoritmo:
     * 1. Encuentra el treeUri persistido que cubre el volumen de [filePath].
     * 2. Convierte la ruta relativa dentro del volumen a un Document URI.
     * 3. Abre un OutputStream y escribe los bytes.
     */
    private fun writeFileViaSaf(filePath: String, bytes: ByteArray): Boolean {
        // Extraer el ID del volumen y la ruta relativa del filePath
        // Ejemplo: /storage/ABCD-1234/Music/song.mp3
        //   -> volumeId = "ABCD-1234", relativePath = "Music/song.mp3"
        val storageParts = filePath.removePrefix("/storage/").split("/", limit = 2)
        if (storageParts.size < 2) {
            Log.e(TAG, "Cannot parse filePath for SAF: $filePath")
            return false
        }
        val volumeId = storageParts[0] // "ABCD-1234" o "emulated"
        val relativePath = storageParts[1] // "Music/song.mp3"

        // Buscar el treeUri persistido para este volumen
        val persistedUri = contentResolver.persistedUriPermissions
            .firstOrNull { perm ->
                perm.isWritePermission &&
                perm.uri.toString().contains(volumeId, ignoreCase = true)
            }?.uri

        if (persistedUri == null) {
            Log.e(TAG, "No persisted SAF permission for volume: $volumeId")
            return false
        }

        // Construir el Document URI para el archivo
        // El docId tiene formato "ABCD-1234:Music/song.mp3"
        val docId = "$volumeId:$relativePath"
        val docUri = DocumentsContract.buildDocumentUriUsingTree(
            persistedUri,
            docId
        )

        return try {
            contentResolver.openOutputStream(docUri, "wt")?.use { out ->
                out.write(bytes)
            }
            Log.d(TAG, "SAF write success: $docUri")
            true
        } catch (e: Exception) {
            // El documento puede no existir todavía: intentar crearlo
            Log.w(TAG, "SAF write failed (${e.message}), trying to create file...")
            try {
                // Encontrar o crear la carpeta padre
                val pathSegments = relativePath.split("/")
                val fileName = pathSegments.last()
                val parentRelative = pathSegments.dropLast(1).joinToString("/")
                val parentDocId = if (parentRelative.isEmpty()) volumeId else "$volumeId:$parentRelative"
                val parentUri = DocumentsContract.buildDocumentUriUsingTree(persistedUri, parentDocId)
                val parentDir = DocumentFile.fromTreeUri(this, persistedUri)
                    ?.let { root ->
                        pathSegments.dropLast(1).fold(root) { dir, segment ->
                            dir.findFile(segment) ?: dir.createDirectory(segment) ?: return false
                        }
                    } ?: return false

                val newFile = parentDir.findFile(fileName)
                    ?: parentDir.createFile("application/octet-stream", fileName)
                    ?: return false

                contentResolver.openOutputStream(newFile.uri, "wt")?.use { out ->
                    out.write(bytes)
                }
                Log.d(TAG, "SAF create+write success: ${newFile.uri}")
                true
            } catch (ex: Exception) {
                Log.e(TAG, "SAF create+write failed: ${ex.message}", ex)
                false
            }
        }
    }
}
