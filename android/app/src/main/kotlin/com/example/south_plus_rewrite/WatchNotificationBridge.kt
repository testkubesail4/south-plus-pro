package com.example.south_plus_rewrite

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

internal class WatchNotificationBridge(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger
) {
    private val channel = MethodChannel(messenger, "south_plus_rewrite/watch_notifications")
    private val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val taps = WatchNotificationTapState()
    private var pendingPermission: MethodChannel.Result? = null
    private val tapAction = "${activity.packageName}.WATCH_NOTIFICATION"

    init {
        receiveIntent(activity.intent, false)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> result.success(permission())
                "requestPermission" -> requestPermission(result)
                "show" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val owner = arguments?.get("owner")
                    val eventId = arguments?.get("eventId")
                    val kind = WatchNotificationTapState.kind(arguments?.get("kind"))
                    if (!WatchNotificationTapState.valid(owner) ||
                        !WatchNotificationTapState.valid(eventId) || kind == null) {
                        result.error("invalid_event", "通知标识无效", null)
                    } else {
                        show(owner as String, eventId as String, kind, result)
                    }
                }
                "cancelKind" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val owner = arguments?.get("owner")
                    val kind = WatchNotificationTapState.kind(arguments?.get("kind"))
                    if (!WatchNotificationTapState.valid(owner) ||
                        (kind != "pm" && kind != "reply")) {
                        result.error("invalid_event", "通知标识无效", null)
                    } else {
                        // A clicked cold tap may still be awaiting Dart after this shade slot is cleared.
                        manager.cancel(identity(owner as String, kind, null), 0)
                        result.success(null)
                    }
                }
                "openSettings" -> result.success(openSettings())
                "cancelAll" -> {
                    manager.cancelAll()
                    taps.clear()
                    clearTapExtras()
                    result.success(null)
                }
                "takeTap" -> {
                    val tap = taps.take()
                    clearTapExtras()
                    result.success(tap)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun receiveIntent(intent: Intent?, notify: Boolean = true) {
        if (intent?.action != tapAction) return
        val received = try {
            taps.receive(
                intent.getStringExtra(EXTRA_OWNER), intent.getStringExtra(EXTRA_EVENT),
                intent.extras?.get(EXTRA_KIND)
            )
        } catch (_: RuntimeException) {
            false
        }
        if (received) {
            activity.intent = intent
            if (notify) channel.invokeMethod("tap", null)
        }
    }

    private fun clearTapExtras() {
        activity.intent?.removeExtra(EXTRA_OWNER)
        activity.intent?.removeExtra(EXTRA_EVENT)
        activity.intent?.removeExtra(EXTRA_KIND)
    }

    private fun permission(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) return false
        return NotificationManagerCompat.from(activity).areNotificationsEnabled()
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (pendingPermission != null) {
            result.error("permission_in_progress", "通知权限请求正在处理", null)
            return
        }
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) {
            result.success(permission())
            return
        }
        pendingPermission = result
        try {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
        } catch (_: RuntimeException) {
            pendingPermission = null
            result.success(false)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = pendingPermission
        pendingPermission = null
        result?.success(permission())
        return true
    }

    private fun show(owner: String, eventId: String, kind: String, result: MethodChannel.Result) {
        if (!permission()) {
            result.success(false)
            return
        }
        try {
            val (channelId, channelName, channelDescription) = when (kind) {
                "pm" -> Triple("pm_messages", "短消息", "App 打开时检查到的新短消息")
                "reply" -> Triple("reply_notices", "回复提醒", "App 打开时检查到的新回复提醒")
                else -> Triple(CHANNEL_ID, "关注动态", "本机关注检查发现的新动态")
            }
            if (Build.VERSION.SDK_INT >= 26) {
                val notificationChannel = NotificationChannel(
                    channelId, channelName, NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = channelDescription
                    lockscreenVisibility = Notification.VISIBILITY_SECRET
                }
                manager.createNotificationChannel(notificationChannel)
                if (manager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) {
                    result.success(false)
                    return
                }
            }
            val eventIdentity = identity(owner, kind, eventId)
            val tag = if (kind == "watch") eventIdentity else identity(owner, kind, null)
            val intent = Intent(activity, MainActivity::class.java)
                .setAction(tapAction)
                .addCategory("${activity.packageName}.watch.$eventIdentity")
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(EXTRA_OWNER, owner)
                .putExtra(EXTRA_EVENT, eventId)
                .putExtra(EXTRA_KIND, kind)
            val pendingIntent = PendingIntent.getActivity(
                activity, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(activity, channelId)
            } else {
                Notification.Builder(activity)
            }
            val notification = builder
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("南+")
                .setContentText(when (kind) {
                    "pm" -> "你有新的短消息，打开 App 查看"
                    "reply" -> "你有新的回复提醒，打开 App 查看"
                    else -> "你关注的内容有新动态，打开 App 查看"
                })
                .setOnlyAlertOnce(kind != "watch" && manager.activeNotifications.any {
                    it.tag == tag && it.notification.contentIntent == pendingIntent
                })
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build()
            manager.notify(tag, 0, notification)
            result.success(true)
        } catch (_: SecurityException) {
            result.success(false)
        } catch (_: RuntimeException) {
            result.error("notification_failed", "无法显示本机通知", null)
        }
    }

    private fun identity(owner: String, kind: String, eventId: String?): String =
        MessageDigest.getInstance("SHA-256")
            .digest(listOfNotNull(owner, kind, eventId).joinToString("\u0000").toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun openSettings(): Boolean = try {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", activity.packageName, null))
        }
        activity.startActivity(intent)
        true
    } catch (_: RuntimeException) {
        false
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pendingPermission?.success(false)
        pendingPermission = null
    }

    private companion object {
        const val CHANNEL_ID = "watch_updates"
        const val PERMISSION_REQUEST = 4109
        const val EXTRA_OWNER = "watch_notification_owner"
        const val EXTRA_EVENT = "watch_notification_event"
        const val EXTRA_KIND = "watch_notification_kind"
    }
}
