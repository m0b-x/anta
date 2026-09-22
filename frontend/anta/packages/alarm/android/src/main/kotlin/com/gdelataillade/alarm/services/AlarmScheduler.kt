package com.gdelataillade.alarm.services

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.gdelataillade.alarm.alarm.AlarmReceiver
import com.gdelataillade.alarm.alarm.AlarmService
import com.gdelataillade.alarm.models.AlarmSettings
import io.flutter.Log
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Persists an alarm and arms the platform to deliver it.
 *
 * Deliberately context-only and free of any stop path: it never touches
 * `AlarmApiImpl.alarmIds`, never calls `AlarmApiImpl.stopAlarm`,
 * `AlarmService.handleStopAlarmCommand` or `AlarmService.unsaveAlarm`, and never
 * reports anything to Flutter. Those all announce a *stop*, which is exactly
 * wrong for a snooze — the alarm is still owed. Callers that do want the
 * replace-then-reschedule behaviour layer it on top themselves.
 */
object AlarmScheduler {
    private const val TAG = "AlarmScheduler"

    /**
     * Delay at or below which the platform is armed with a plain
     * `Handler.postDelayed` instead of `AlarmManager`.
     *
     * That fallback lives only as long as the process and cannot be cancelled
     * through `AlarmManager.cancel`, so it is unusable for anything that has to
     * survive termination.
     */
    const val IMMEDIATE_THRESHOLD_MILLIS = 5000L

    /**
     * Saves [alarm] and arms its delivery.
     *
     * When [requireDurable] is set, refuses rather than falling back to the
     * in-process timer, so a caller that needs the alarm to survive process
     * death finds out instead of silently getting a weaker guarantee.
     *
     * Returns whether the alarm is now both stored and armed. An exact-alarm
     * permission downgrade to an inexact alarm still counts as success: the
     * alarm may ring late, but it will ring.
     */
    fun schedule(
        context: Context,
        alarm: AlarmSettings,
        requireDurable: Boolean = false,
    ): Boolean {
        val delayInMillis = alarm.dateTime.time - System.currentTimeMillis()

        if (delayInMillis <= IMMEDIATE_THRESHOLD_MILLIS && requireDurable) {
            Log.e(
                TAG,
                "Refusing to schedule alarm ${alarm.id} durably: it is due in " +
                    "${delayInMillis}ms, which is below the ${IMMEDIATE_THRESHOLD_MILLIS}ms " +
                    "AlarmManager threshold."
            )
            return false
        }

        AlarmStorage(context).saveAlarm(alarm)

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("id", alarm.id)
            putExtra("alarmSettings", Json.encodeToString(alarm))
        }

        val armed = if (delayInMillis <= IMMEDIATE_THRESHOLD_MILLIS) {
            Handler(Looper.getMainLooper()).postDelayed(
                { context.sendBroadcast(intent) },
                delayInMillis.coerceAtLeast(0L)
            )
            true
        } else {
            armAlarmManager(context, intent, alarm.dateTime.time, alarm.id)
        }

        // Every path that adds a pending alarm has to leave the kill warning
        // consistent with it, including the snooze path, which reaches here
        // without going through the plugin.
        WarningNotificationState.refresh(context)

        return armed
    }

    /**
     * Arms `AlarmManager` for [triggerTimeMillis].
     *
     * Unlike the code this replaced, a genuine failure is reported rather than
     * logged and swallowed — a caller that has silenced a ringing alarm on the
     * strength of a successful reschedule has to be able to tell.
     */
    private fun armAlarmManager(
        context: Context,
        intent: Intent,
        triggerTimeMillis: Long,
        id: Int,
    ): Boolean {
        return try {
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (alarmManager == null) {
                Log.e(TAG, "Cannot arm alarm $id: AlarmManager is not available.")
                return false
            }

            setExactAlarm(context, alarmManager, triggerTimeMillis, pendingIntent, id)
            true
        } catch (e: IllegalStateException) {
            // Reporting this as "service not available" was misleading: a missing
            // service is handled above, and what reaches here is AlarmManager
            // refusing the alarm — documented for an app that already holds the
            // maximum number of scheduled alarms (500).
            Log.e(
                TAG,
                "AlarmManager refused to arm alarm $id. The likely cause is this " +
                    "app having reached the per-app limit on scheduled alarms.",
                e
            )
            false
        } catch (e: Exception) {
            Log.e(TAG, "Error while arming alarm $id", e)
            false
        }
    }

    /**
     * Arms the exact delivery as an **alarm clock** (ANTA fork, Patch 1).
     *
     * `setAlarmClock` is the one `AlarmManager` entry point that carries alarm
     * semantics through the platform: it is exempt from Doze and the standby
     * buckets by definition, it is what the status-bar icon, the lock screen,
     * Quick Settings and `getNextAlarmClock()` show as the device's next
     * alarm, and its show intent is what those surfaces open. It needs the
     * same exact-alarm permission on Android 12–13 as `setExactAndAllowWhileIdle`
     * did, so the guard and both inexact fallbacks are exactly what upstream
     * ships. Below API 21 there is no alarm clock to arm, so `setExact` stays.
     */
    private fun setExactAlarm(
        context: Context,
        alarmManager: AlarmManager,
        triggerTimeMillis: Long,
        pendingIntent: PendingIntent,
        id: Int,
    ) {
        // On Android 12+ the user can revoke the exact alarm permission at any
        // time. Fall back to an inexact alarm instead of silently scheduling
        // nothing: the alarm may ring a few minutes late, but it will ring.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            Log.w(
                TAG,
                "SCHEDULE_EXACT_ALARM permission not granted. Falling back to an " +
                    "inexact alarm, which may ring late. Ask the user to grant the " +
                    "'Alarms & reminders' permission for exact scheduling."
            )
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerTimeMillis,
                pendingIntent
            )
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerTimeMillis, showIntent(context, id)),
                    pendingIntent
                )
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            }
        } catch (e: SecurityException) {
            // Defensive: the permission state changed between the check above
            // and the call, or an OEM enforces it on older API levels.
            Log.e(TAG, "Exact alarm scheduling rejected; falling back to inexact alarm", e)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerTimeMillis,
                    pendingIntent
                )
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            }
        }
    }

    /**
     * What the lock-screen line and Quick Settings open for alarm [id]: the
     * application's own launch intent, carrying [AlarmService.ACTION_SHOW] and
     * the alarm id under [AlarmService.EXTRA_ALARM_ID], so the app can land on
     * its alarm list rather than on a cold start. The launch intent names an
     * explicit component, so the custom action changes nothing about where it
     * resolves; a `singleTop` activity that is already up receives it through
     * `onNewIntent`. Null when the package has no launch intent, which
     * `AlarmClockInfo` allows.
     */
    private fun showIntent(context: Context, id: Int): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return null
        launch.action = AlarmService.ACTION_SHOW
        launch.putExtra(AlarmService.EXTRA_ALARM_ID, id)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            id,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
