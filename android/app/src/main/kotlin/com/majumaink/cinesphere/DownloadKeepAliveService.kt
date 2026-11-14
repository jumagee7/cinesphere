package com.majumaink.cinesphere

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Data-sync foreground service that keeps the Flutter engine alive while media
 * is downloading and the app is not in the foreground.
 *
 * Android freezes background network work (app standby / Doze) and can kill a
 * cached process at will. An active foreground service raises the process
 * priority and, together with a partial wake lock, keeps the CPU and sockets
 * running with the screen off. It is started with the first active download
 * and stopped with the last one.
 */
class DownloadKeepAliveService : Service() {
    companion object {
        const val EXTRA_LABEL = "label"
        private const val CHANNEL_ID = "cinesphere_downloads"
        private const val CHANNEL_NAME = "Vyro downloads"
        private const val CHANNEL_DESC = "Ongoing media download progress."
        private const val NOTIFICATION_ID = 90210
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60L * 60L * 1000L

        fun start(context: Context, label: String) {
            val intent = Intent(context, DownloadKeepAliveService::class.java)
                .putExtra(EXTRA_LABEL, label)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadKeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var label = "Downloading media…"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.getStringExtra(EXTRA_LABEL)?.let { label = it }
        startInForeground()
        acquireWakeLock()
        // Not sticky: if the process dies, restarting a bare service without
        // the Dart queue would only leave a stale notification behind. The
        // queue resumes from SharedPreferences on the next app launch.
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = CHANNEL_DESC
                    setShowBadge(false)
                }
            )
        }

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_icon)
            .setContentTitle("Vyro")
            .setContentText(label)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openApp)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Vyro:downloads").apply {
            setReferenceCounted(false)
            // A cap keeps a forgotten service from pinning the CPU forever.
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }
}
