package com.nativephp.microphone.services

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service to enable audio recording while the device is locked.
 *
 * Uses microphone foreground service type (Android 14+) and acquires a partial
 * wake lock to keep the CPU active during recording. This ensures audio recording
 * continues even when the screen is off or the app is in the background.
 */
class AudioRecordingService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Recording Audio")
            .setContentText("Tap to return to app")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ requires foreground service type
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Acquire partial wake lock to keep CPU active during recording
        acquireWakeLock()

        return START_NOT_STICKY
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "NativePHP::AudioRecording"
            ).apply {
                acquire(10 * 60 * 1000L) // 10 minutes max
                Log.d(TAG, "✅ Wake lock acquired")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to acquire wake lock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "✅ Wake lock released")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing wake lock: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        Log.d(TAG, "🧹 Audio recording service destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Audio Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifications shown while recording audio"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "AudioRecordingService"
        private const val CHANNEL_ID = "audio_recording_channel"
        private const val NOTIFICATION_ID = 1002

        fun start(context: Context) {
            val intent = Intent(context, AudioRecordingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(TAG, "🚀 Starting audio recording service")
        }

        fun stop(context: Context) {
            val intent = Intent(context, AudioRecordingService::class.java)
            context.stopService(intent)
            Log.d(TAG, "⏹️ Stopping audio recording service")
        }
    }
}