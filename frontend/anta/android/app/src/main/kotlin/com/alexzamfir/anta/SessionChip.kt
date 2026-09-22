package com.alexzamfir.anta

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * The session chip (OS-5, B8): one ongoing notification saying a session is
 * under way, posted after an alarm is acknowledged.
 *
 * On Android 16 it asks to be **promoted** — the status-bar chip and the
 * lock-screen card Live Updates get — with a [NotificationCompat.ProgressStyle]
 * bar: elapsed over the event's duration when Dart knows it, indeterminate
 * otherwise. The request is made only when [NotificationManagerCompat.canPostPromotedNotifications]
 * says the user allows it — which needs the manifest's
 * `POST_PROMOTED_NOTIFICATIONS` (a `normal|appop` permission, "Show live
 * updates", granted at install and switchable per app) — and everywhere else,
 * and when they do not, the same notification stands as a plain ongoing one
 * whose chronometer counts up from the acknowledgement. Both shapes carry the same two actions: *Open note*
 * launches [MainActivity] with [ACTION_OPEN] and the alarm's payload, which
 * the activity reports to Dart like the alarm-clock show intent; *Done* is a
 * broadcast to [SessionChipReceiver], which takes the chip down with no Dart
 * involved.
 *
 * Every string comes from Dart: the labels are localized there, and the
 * platform is only asked to draw them. The one thing kept here is the end
 * instant, in the activity's own preferences, so a launch after the process
 * died can take down a chip whose session is over ([clearIfStale]) — Dart
 * has no record of what an earlier process posted.
 */
object SessionChip {
    /**
     * Spells "SESS", negated: every id the Dart side derives — an os id, a
     * notice id, a Missed id — is masked to 31 bits and so never negative,
     * which is the one way to be sure no alert's notification shares this id.
     */
    const val NOTIFICATION_ID = -0x53455353

    const val ACTION_OPEN = "com.alexzamfir.anta.OPEN_SESSION"
    const val ACTION_DONE = "com.alexzamfir.anta.SESSION_DONE"
    const val EXTRA_PAYLOAD = "payload"

    private const val PREFS = "session_chip"
    private const val KEY_ENDS_AT = "ends_at"
    private const val REQUEST_OPEN = 0x5E55
    private const val REQUEST_DONE = 0x5E56
    private const val SMALL_ICON = "ic_alert"

    /**
     * Posts or refreshes the chip from the method-channel arguments. Answers
     * whether the chip stands on the shade afterwards.
     *
     * A refresh (`refresh = true`) of a chip that is no longer active is
     * refused: the user pressed *Done*, which [SessionChipReceiver] handles
     * with no Dart running, and the periodic re-post from Dart would
     * otherwise bring the chip straight back. The refusal is what tells the
     * Dart side to stop.
     */
    fun show(context: Context, args: Map<*, *>): Boolean {
        val payload = args["payload"] as? String ?: return false
        val channelId = args["channelId"] as? String ?: return false
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return false
        if (args["refresh"] == true && !isActive(manager)) {
            prefs(context).edit().remove(KEY_ENDS_AT).apply()
            return false
        }
        val startedAt = (args["startedAtMs"] as? Number)?.toLong() ?: System.currentTimeMillis()
        val endsAt = (args["endsAtMs"] as? Number)?.toLong()
        val progress = (args["progress"] as? Number)?.toInt()
        val color = (args["color"] as? Number)?.toInt()

        val open = PendingIntent.getActivity(
            context,
            REQUEST_OPEN,
            Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .putExtra(EXTRA_PAYLOAD, payload)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val done = PendingIntent.getBroadcast(
            context,
            REQUEST_DONE,
            Intent(context, SessionChipReceiver::class.java).setAction(ACTION_DONE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(smallIcon(context))
            .setContentTitle(args["title"] as? String ?: "")
            .setContentText(args["text"] as? String)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setWhen(startedAt)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setContentIntent(open)
            .addAction(0, args["openLabel"] as? String ?: "", open)
            .addAction(0, args["doneLabel"] as? String ?: "", done)
        if (color != null) builder.setColor(color)
        if (canPromote(manager)) {
            builder.setRequestPromotedOngoing(true)
            val style = NotificationCompat.ProgressStyle()
                .setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(100)))
            if (progress == null) {
                style.setProgressIndeterminate(true)
            } else {
                style.setProgress(progress.coerceIn(0, 100))
            }
            builder.setStyle(style)
        }
        return try {
            manager.notify(NOTIFICATION_ID, builder.build())
            prefs(context).edit().apply {
                if (endsAt == null) remove(KEY_ENDS_AT) else putLong(KEY_ENDS_AT, endsAt)
            }.apply()
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /** Takes the chip down and forgets its end. Safe when there is none. */
    fun clear(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        prefs(context).edit().remove(KEY_ENDS_AT).apply()
    }

    /**
     * Takes down a chip whose session ended while no Dart was running. A chip
     * with no recorded end is left alone: only Done or the next ring ends it.
     */
    fun clearIfStale(context: Context) {
        val endsAt = prefs(context).getLong(KEY_ENDS_AT, 0L)
        if (endsAt > 0L && System.currentTimeMillis() >= endsAt) clear(context)
    }

    /** Whether the chip is on the shade right now. */
    fun isActive(manager: NotificationManagerCompat): Boolean =
        manager.activeNotifications.any { it.id == NOTIFICATION_ID }

    /** Whether the platform would honour a promotion request right now. */
    fun canPromote(manager: NotificationManagerCompat): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
            manager.canPostPromotedNotifications()

    private fun smallIcon(context: Context): Int {
        val id = context.resources.getIdentifier(SMALL_ICON, "drawable", context.packageName)
        return if (id != 0) id else context.applicationInfo.icon
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
