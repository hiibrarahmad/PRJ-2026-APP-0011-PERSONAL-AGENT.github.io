package inc.buddie.memx

import android.app.Notification
import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

class NotificationCaptureService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val notification = sbn.notification ?: return
        appendNotification(this, sbn, notification)
    }

    companion object {
        private const val PREFS_NAME = "ia_agent_device_context"
        private const val KEY_NOTIFICATIONS = "captured_notifications"
        private const val MAX_ITEMS = 500

        fun isNotificationAccessEnabled(context: Context): Boolean {
            val enabledPackages =
                NotificationManagerCompat.getEnabledListenerPackages(context)
            if (enabledPackages.contains(context.packageName)) {
                return true
            }

            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false

            return enabled.split(':').any { flattened ->
                flattened.contains(context.packageName, ignoreCase = true)
            }
        }

        fun getCapturedNotifications(
            context: Context,
            limit: Int = 100
        ): List<Map<String, Any?>> {
            val sharedPrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = sharedPrefs.getString(KEY_NOTIFICATIONS, "[]") ?: "[]"
            val array = try {
                JSONArray(raw)
            } catch (_: Throwable) {
                JSONArray()
            }

            val out = ArrayList<Map<String, Any?>>(minOf(limit, array.length()))
            val start = maxOf(0, array.length() - limit)
            for (i in start until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                out.add(
                    mapOf(
                        "packageName" to item.optString("packageName", ""),
                        "title" to item.optString("title", ""),
                        "text" to item.optString("text", ""),
                        "postedAt" to item.optLong("postedAt", 0L),
                    )
                )
            }
            return out
        }

        fun clearCapturedNotifications(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_NOTIFICATIONS, "[]")
                .apply()
        }

        private fun appendNotification(
            context: Context,
            sbn: StatusBarNotification,
            notification: Notification
        ) {
            val extras = notification.extras
            val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

            if (title.isBlank() && text.isBlank()) return

            val sharedPrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = sharedPrefs.getString(KEY_NOTIFICATIONS, "[]") ?: "[]"
            val array = try {
                JSONArray(raw)
            } catch (_: Throwable) {
                JSONArray()
            }

            val item = JSONObject()
                .put("packageName", sbn.packageName ?: "")
                .put("title", title)
                .put("text", text)
                .put("postedAt", sbn.postTime)

            array.put(item)
            while (array.length() > MAX_ITEMS) {
                array.remove(0)
            }

            sharedPrefs.edit().putString(KEY_NOTIFICATIONS, array.toString()).apply()
        }
    }
}
