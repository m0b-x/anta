package com.alexzamfir.anta

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

/**
 * Answers the two alert permission questions no plugin exposes as a query.
 *
 * `flutter_local_notifications` only offers a "request" for the full-screen
 * intent, which navigates to the system settings page when the answer is no —
 * useless for a status row — and battery optimisation has no Dart binding at
 * all. Both are read-only here; the only thing that leaves the app is the
 * settings page the user asked for.
 *
 * Also the two things a ring needs from the activity itself. `setShowWhenLocked`
 * lifts the app over the keyguard **for the length of a ring and no longer** —
 * the manifest attribute would hold for the activity's whole life and put the
 * notes on top of a PIN. `processStartedAt` is the wall-clock start of this
 * process, which is how the scheduler tells an alarm that rang while no Dart
 * was running from one that never fired.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALERTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    "setShowWhenLocked" -> {
                        setShowWhenLockedCompat(call.arguments == true)
                        result.success(null)
                    }
                    "processStartedAt" -> result.success(processStartedAt())
                    else -> result.notImplemented()
                }
            }
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = getSystemService(android.app.NotificationManager::class.java)
        return manager?.canUseFullScreenIntent() ?: true
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val manager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return manager?.isIgnoringBatteryOptimizations(packageName) ?: true
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

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
