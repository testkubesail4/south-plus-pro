package com.example.south_plus_rewrite

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat

class WatchPollingService : Service() {
    private var foreground = false
    private var lease: Start? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requestId = intent?.getLongExtra(EXTRA_REQUEST, -1) ?: -1
        val request = pending?.takeIf { it.requestId == requestId }
        if (request == null) {
            if (!foreground) stopSelfResult(startId)
            return START_NOT_STICKY
        }
        pending = null
        if (!notificationsAllowed(this)) {
            request.complete(false)
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        try {
            val notification = statusNotification()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(STATUS_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(STATUS_ID, notification)
            }
            foreground = true
            lease = request
            request.complete(true)
        } catch (_: RuntimeException) {
            finishLease()
            request.complete(false)
            stopSelfResult(startId)
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        finishLease()
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        finishLease()
        stopSelf()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        finishLease()
        super.onDestroy()
    }

    private fun finishLease() {
        if (foreground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        val stopped = lease
        lease = null
        stopped?.onStopped?.invoke(stopped.requestId)
    }

    private fun statusNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val settings = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "关注检查", NotificationManager.IMPORTANCE_LOW
            ).apply {
                setSound(null, null)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            })
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL_ID)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
        }
        val pendingIntent = PendingIntent.getActivity(
            this, STATUS_ID, settings,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("南+")
            .setContentText("关注检查中")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setPriority(Notification.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setContentIntent(pendingIntent)
            .build()
    }

    private class Start(
        val host: Any,
        val requestId: Long,
        val onReady: (Boolean) -> Unit,
        val onStopped: (Long) -> Unit
    ) {
        private var completed = false
        fun complete(running: Boolean) {
            if (completed) return
            completed = true
            onReady(running)
        }
    }

    internal companion object {
        const val CHANNEL_ID = "watch_service_status"
        private const val STATUS_ID = 4911
        private const val EXTRA_REQUEST = "watch_polling_request"
        private var instance: WatchPollingService? = null
        private var pending: Start? = null

        fun runningFor(host: Any): Boolean =
            instance?.let { it.foreground && it.lease?.host === host } == true

        fun notificationsAllowed(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED) return false
            return NotificationManagerCompat.from(context).areNotificationsEnabled()
        }

        fun start(
            context: Context,
            host: Any,
            requestId: Long,
            onReady: (Boolean) -> Unit,
            onStopped: (Long) -> Unit
        ) {
            val request = Start(host, requestId, onReady, onStopped)
            val current = instance
            if (current?.foreground == true) {
                if (!notificationsAllowed(context)) {
                    stop(context, host)
                    request.complete(false)
                    return
                }
                val previous = current.lease
                current.lease = request
                if (previous?.host !== host) previous?.onStopped?.invoke(previous.requestId)
                request.complete(true)
                return
            }
            if (pending != null) {
                request.complete(false)
                return
            }
            pending = request
            val intent = Intent(context, WatchPollingService::class.java)
                .putExtra(EXTRA_REQUEST, requestId)
            try {
                // New starts are resumed-only; cancelled requests need no foreground-start deadline.
                context.startService(intent)
            } catch (_: RuntimeException) {
                if (pending === request) pending = null
                request.complete(false)
            }
        }

        fun stop(context: Context, host: Any) {
            val queued = pending?.takeIf { it.host === host }
            if (queued != null) {
                pending = null
                queued.complete(false)
            }
            val current = instance
            if (current?.lease?.host === host) current.finishLease()
            if (pending == null && instance?.lease == null) {
                context.stopService(Intent(context, WatchPollingService::class.java))
            }
        }
    }
}
