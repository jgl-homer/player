package com.jglhomer.player

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.KeyEvent

/**
 * Receptor para despertar el reproductor y reproducir automáticamente
 * cuando se conecta un dispositivo Bluetooth (estéreo de auto, audífonos, etc.)
 * incluso si la aplicación fue completamente cerrada.
 */
class BluetoothAutoPlayReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BTAutoPlayReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "Bluetooth event received: $action")

        val shouldPlay = when (action) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> true
            BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED -> {
                val state = intent.getIntExtra(BluetoothProfile.EXTRA_STATE, BluetoothProfile.STATE_DISCONNECTED)
                state == BluetoothProfile.STATE_CONNECTED
            }
            "android.media.action.HDMI_AUDIO_PLUG" -> {
                intent.getIntExtra("state", 0) == 1
            }
            else -> false
        }

        if (shouldPlay) {
            Log.d(TAG, "Bluetooth audio connected while app closed — dispatching play")
            sendMediaPlayEvent(context)
        }
    }

    private fun sendMediaPlayEvent(context: Context) {
        try {
            val mediaButtonReceiverComponent = ComponentName(
                context,
                "com.ryanheise.audioservice.MediaButtonReceiver"
            )

            val downIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = mediaButtonReceiverComponent
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY))
            }
            context.sendBroadcast(downIntent)

            val upIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = mediaButtonReceiverComponent
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY))
            }
            context.sendBroadcast(upIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending media play event: ${e.message}")
        }
    }
}
