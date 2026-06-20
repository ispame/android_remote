package com.openclaw.remote.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.openclaw.remote.MainActivity
import com.openclaw.remote.R
import kotlin.math.absoluteValue

object BosonPushNotifications {
    const val CHANNEL_ID = "boson_relay_messages"
    private const val TAG = "BosonPush"

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Boson Relay",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Boson Relay messages and scheduled task updates"
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun showRemoteMessage(context: Context, message: RemoteMessage) {
        val title = message.notification?.title
            ?: message.data["title"]
            ?: "Boson Relay 新消息"
        val body = message.notification?.body
            ?: message.data["body"]
            ?: "打开 Boson Relay 查看详情"
        val messageId = message.data["message_id"] ?: message.messageId ?: body
        val deepLink = message.data["deep_link"] ?: message.data["deeplink"]
        show(context, title, body, messageId, deepLink)
    }

    private fun show(context: Context, title: String, body: String, messageId: String, deepLink: String?) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.i(TAG, "notification skipped because POST_NOTIFICATIONS is not granted")
            return
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            deepLink
                ?.trim()
                ?.takeIf { it.startsWith("openclaw://") }
                ?.let {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse(it)
                }
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            messageId.hashCode().absoluteValue,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(messageId.hashCode().absoluteValue, notification)
    }
}

object BosonPushTokenReporter {
    private const val TAG = "BosonPushToken"
    private const val PREFS = "boson_push_tokens"
    private const val KEY_FCM_TOKEN = "fcm_token"

    fun cachedToken(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_FCM_TOKEN, null)
            ?.takeIf { it.isNotBlank() }

    fun refresh(context: Context, onToken: (String) -> Unit) {
        cachedToken(context)?.let(onToken)
        runCatching {
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    save(context, token)
                    onToken(token)
                }
                .addOnFailureListener { error ->
                    Log.w(TAG, "FCM token refresh failed", error)
                }
        }.onFailure { error ->
            Log.w(TAG, "FCM is not configured; push token refresh skipped", error)
        }
    }

    fun save(context: Context, token: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_FCM_TOKEN, token)
            .apply()
    }
}

class BosonFirebaseMessagingService : FirebaseMessagingService() {
    override fun onCreate() {
        super.onCreate()
        BosonPushNotifications.createChannel(this)
    }

    override fun onNewToken(token: String) {
        BosonPushTokenReporter.save(this, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        BosonPushNotifications.showRemoteMessage(this, message)
    }
}
