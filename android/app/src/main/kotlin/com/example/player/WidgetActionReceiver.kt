package com.example.player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Recibe los Intents de los botones del widget y los reenvía a la MainActivity
 * para que Flutter los procese a través de MethodChannel.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        // Reenviar a MainActivity con un Intent que Flutter puede leer
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("widget_action", action)
        }
        context.startActivity(launchIntent)
    }
}
