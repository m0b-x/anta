package com.alexzamfir.anta

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val ALERTS_CHANNEL = "com.alexzamfir.anta/alerts"
private const val PERMISSIONS_CHANNEL = "com.alexzamfir.anta/permissions"

/**
 * The two app-owned channels.
 *
 * **Permissions** answers every permission question in one round trip and
 * opens the system page where each one is granted. No plugin offers the
 * queries as queries: `flutter_local_notifications` only has a "request" for
 * the full-screen intent and for exact alarms, which navigates to the system
 * settings page when the answer is no — useless for a status row — and holds a
 * plugin-wide "request in progress" flag until the activity result comes back.
 * Battery optimisation has no Dart binding at all. A permission the running
 * Android version gives the user no switch for is left out of the answer
 * rather than reported as held, and one whose query throws answers null, so
 * Dart can tell "not a thing here" and "could not ask" from "granted".
 * Everything here is read-only except the settings pages the user asked for,
 * and each of those falls back to the app's own details page on a ROM that
 * lacks the screen.
 *
 * **Alerts** is the two things a ring needs from the activity itself.
 * `setShowWhenLocked` lifts the app over the keyguard **for the length of a
 * ring and no longer** — the manifest attribute would hold for the activity's
 * whole life and put the notes on top of a PIN. `processStartedAt` is the
 * wall-clock start of this process, which is how the scheduler tells an alarm
 * that rang while no Dart was running from one that never fired.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, ALERTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setShowWhenLocked" -> {
                        setShowWhenLockedCompat(call.arguments == true)
                        result.success(null)
                    }
                    "processStartedAt" -> result.success(processStartedAt())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(messenger, PERMISSIONS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        permissionStatus(call.argument<List<String>>("channels") ?: emptyList())
                    )
                    "shouldExplainNotifications" ->
                        result.success(shouldExplainNotifications())
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    "openExactAlarmSettings" -> result.success(openExactAlarmSettings())
                    "openFullScreenIntentSettings" ->
                        result.success(openFullScreenIntentSettings())
                    "openAppSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }
    }

    private fun permissionStatus(channelIds: List<String>): Map<String, Boolean?> {
        val status = HashMap<String, Boolean?>()
        fun put(key: String, applies: Boolean, query: () -> Boolean?) {
            if (!applies) return
            status[key] = try {
                query()
            } catch (e: Exception) {
                null
            }
        }
        val sdk = Build.VERSION.SDK_INT
        put("notifications", true) { canPostNotifications(channelIds) }
        put("exactAlarms", sdk in Build.VERSION_CODES.S..Build.VERSION_CODES.S_V2) {
            canScheduleExactAlarms()
        }
        put("fullScreenIntent", sdk >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            canUseFullScreenIntent()
        }
        put("batteryOptimization", true) { isIgnoringBatteryOptimizations() }
        return status
    }

    private fun canPostNotifications(channelIds: List<String>): Boolean? {
        val manager = getSystemService(NotificationManager::class.java) ?: return null
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return channelIds.none { id ->
            manager.getNotificationChannel(id)?.importance ==
                NotificationManager.IMPORTANCE_NONE
        }
    }

    private fun shouldExplainNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        return shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun canScheduleExactAlarms(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms()
    }

    private fun canUseFullScreenIntent(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return null
        return getSystemService(NotificationManager::class.java)?.canUseFullScreenIntent()
    }

    private fun isIgnoringBatteryOptimizations(): Boolean? {
        val manager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return manager?.isIgnoringBatteryOptimizations(packageName)
    }

    private fun setShowWhenLockedCompat(show: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        setShowWhenLocked(show)
        setTurnScreenOn(show)
    }

    private fun processStartedAt(): Long {
        val aliveFor = SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()
        return System.currentTimeMillis() - aliveFor
    }

    private fun packageUri(): Uri = Uri.fromParts("package", packageName, null)

    private fun launch(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openAppSettings(): Boolean =
        launch(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri()))

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent("android.settings.APP_NOTIFICATION_SETTINGS")
                .putExtra("app_package", packageName)
                .putExtra("app_uid", applicationInfo.uid)
        }
        return launch(intent) || openAppSettings()
    }

    private fun openExactAlarmSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri())
            if (launch(intent)) return true
        }
        return openAppSettings()
    }

    private fun openFullScreenIntentSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val intent =
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri())
            if (launch(intent)) return true
        }
        return openAppSettings()
    }
}
