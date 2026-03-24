package com.example.player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.widget.RemoteViews

class MusicWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_PREVIOUS = "com.example.player.WIDGET_PREVIOUS"
        const val ACTION_PLAY_PAUSE = "com.example.player.WIDGET_PLAY_PAUSE"
        const val ACTION_NEXT = "com.example.player.WIDGET_NEXT"
        const val PREFS_NAME = "HomeWidgetPreferences"

        fun updateWidget(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MusicWidgetProvider::class.java))
            val intent = Intent(context, MusicWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, widgetId)
        }
    }

    private fun updateAppWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val title = prefs.getString("title", "Sin canción") ?: "Sin canción"
        val artist = prefs.getString("artist", "Artista desconocido") ?: "Artista desconocido"
        val isPlaying = prefs.getBoolean("isPlaying", false)

        val views = RemoteViews(context.packageName, R.layout.widget_layout)

        // Datos de la canción
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)

        // Ícono de play/pause
        val playIcon = if (isPlaying)
            android.R.drawable.ic_media_pause
        else
            android.R.drawable.ic_media_play
        views.setImageViewResource(R.id.widget_btn_play_pause, playIcon)

        // Carátula desde archivo guardado
        try {
            val artPath = prefs.getString("artPath", null)
            if (artPath != null) {
                val bitmap: Bitmap = BitmapFactory.decodeFile(artPath)
                views.setImageViewBitmap(R.id.widget_artwork, bitmap)
            } else {
                views.setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
            }
        } catch (e: Exception) {
            views.setImageViewResource(R.id.widget_artwork, R.mipmap.ic_launcher)
        }

        // Intents para los botones
        fun makePendingIntent(action: String): PendingIntent {
            val intent = Intent(context, WidgetActionReceiver::class.java).apply { this.action = action }
            return PendingIntent.getBroadcast(
                context, action.hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        views.setOnClickPendingIntent(R.id.widget_btn_previous, makePendingIntent(ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.widget_btn_play_pause, makePendingIntent(ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.widget_btn_next, makePendingIntent(ACTION_NEXT))

        // Tap en el widget abre la app
        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            context, 0, openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_title, openPending)
        views.setOnClickPendingIntent(R.id.widget_artwork, openPending)

        manager.updateAppWidget(widgetId, views)
    }
}
