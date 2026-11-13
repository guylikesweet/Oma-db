package com.omagroup.salesapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createOmaNotificationChannels()
    }

    override fun onStart() {
        Log.i("OmaStartup", "MainActivity.onStart entering")
        super.onStart()
        Log.i("OmaStartup", "MainActivity.onStart completed")
    }

    private fun createOmaNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager == null) {
                Log.w("OmaStartup", "NotificationManager unavailable; continuing without custom channels")
                return
            }
            val audio = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channels = listOf(
                Triple("oma_scanner_v3", "Oma scanner", "scanner_beep"),
                Triple("oma_arrival_sea_v3", "Sea shipment arrivals", "ship_horn"),
                Triple("oma_arrival_air_v3", "Air shipment arrivals", "airport_arrival"),
                Triple("oma_chat_v3", "Oma team chat", "chat_message")
            )
            for ((id, name, soundName) in channels) {
                try {
                    val sound = resources.getIdentifier(soundName, "raw", packageName)
                    val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH)
                    channel.enableVibration(true)
                    if (sound != 0) {
                        val uri = android.net.Uri.parse("android.resource://" + packageName + "/" + sound)
                        channel.setSound(uri, audio)
                    }
                    manager.createNotificationChannel(channel)
                } catch (error: Exception) {
                    Log.w("OmaStartup", "Unable to create notification channel $id; continuing", error)
                }
            }
        } catch (error: Exception) {
            Log.w("OmaStartup", "Notification channel setup failed; continuing app startup", error)
        }
    }
}
