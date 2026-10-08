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
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.media.AudioDeviceCallback
import java.io.File

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
                "cacheNotificationArtwork" -> {
                    val songId = call.argument<Any>("songId")?.toString()
                    val bytes = call.argument<ByteArray>("bytes")
                    if (songId == null || bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "songId and artwork bytes are required", null)
                    } else {
                        try {
                            result.success(cacheNotificationArtwork(songId, bytes))
                        } catch (e: Exception) {
                            Log.e(TAG, "cacheNotificationArtwork error: ${e.message}", e)
                            result.success(null)
                        }
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

    private fun cacheNotificationArtwork(songId: String, bytes: ByteArray): String? {
        val safeId = songId.replace(Regex("[^A-Za-z0-9_-]"), "_")
        val artworkDir = File(cacheDir, "artwork_cache")
        if (!artworkDir.exists()) artworkDir.mkdirs()

        val artworkFile = File(artworkDir, "artwork_$safeId.jpg")
        artworkFile.writeBytes(bytes)

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            artworkFile
        )

        grantUriPermission(
            "com.android.systemui",
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        return uri.toString()
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
        (params["volume"] as? Number)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setVolume(it.toFloat()) }
        (params["peakProtectionEnabled"] as? Boolean)?.let { com.ryanheise.just_audio.EpicenterProcessorController.setPeakProtectionEnabled(it) }
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
