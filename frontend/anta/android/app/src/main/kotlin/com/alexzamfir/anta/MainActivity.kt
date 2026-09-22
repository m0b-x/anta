package com.alexzamfir.anta

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

private const val ALERTS_CHANNEL = "com.alexzamfir.anta/alerts"
private const val PERMISSIONS_CHANNEL = "com.alexzamfir.anta/permissions"

/**
 * The stored literal meaning "the phone's current default alarm sound".
 *
 * Spelled on both sides of the channel (`AlertSound.systemDefaultValue` in Dart)
 * because it is a persisted value, not a message: it rides backups and syncs to
 * other devices, so neither side may invent its own spelling.
 */
private const val ALARM_SOUND_SYSTEM_DEFAULT = "system:default"

/** Answered when the device has no ringtone picker activity at all. */
private const val ERROR_NO_PICKER = "no_picker"

/** Answered when a pick is already in flight — see [MainActivity.pendingSoundPicker]. */
private const val ERROR_PICKER_BUSY = "picker_busy"

private const val PICK_ALARM_SOUND_REQUEST = 0x5A17

/** Where a picked sound is copied to, under `filesDir`. */
private const val ALARM_SOUND_DIR = "alert_sounds"

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
 * **Alerts** is what a ring needs from the activity itself, and what no plugin
 * can answer. `setShowWhenLocked` lifts the app over the keyguard **for the
 * length of a ring and no longer** — the manifest attribute would hold for the
 * activity's whole life and put the notes on top of a PIN. `processStartedAt`
 * is the wall-clock start of this process, which is how the scheduler tells an
 * alarm that rang while no Dart was running from one that never fired.
 * `alarmStreamVolume` reports the user's own alarm level so the app can follow
 * it instead of overriding it, and only take it over when it is so low that an
 * alarm would not wake anyone.
 *
 * The three **sound** methods exist because the `alarm` package plays a Flutter
 * asset or a file path and nothing else. `pickAlarmSound` runs the system
 * ringtone picker (alarm type, its own "Default" entry mapped to
 * [ALARM_SOUND_SYSTEM_DEFAULT] so the stored value keeps following the Clock
 * app rather than freezing today's choice), `alarmSoundTitle` names a stored
 * value for the UI, and `resolveAlarmSound` copies a `content://` sound into
 * `filesDir` — a content URI can never reach `MediaPlayer.setDataSource(String)`,
 * so the copy is the only way such a sound rings at all. Everything here is
 * failure-tolerant by design: a sound that cannot be resolved answers null and
 * the app rings the phone's default alarm, because an alarm that does not sound
 * is far worse than an alarm that sounds wrong.
 */
class MainActivity : FlutterActivity() {
    /**
     * The one in-flight [pickAlarmSound] answer.
     *
     * `startActivityForResult` has a single result callback and no way to carry
     * a token, so a second pick while one is open could only be answered by
     * guessing which caller the result belonged to. It is refused instead.
     */
    private var pendingSoundPicker: MethodChannel.Result? = null

    /** Copies run here; the answer is posted back to the main thread. */
    private val soundExecutor = Executors.newSingleThreadExecutor()

    private val mainHandler = Handler(Looper.getMainLooper())

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
                    "alarmStreamVolume" -> result.success(alarmStreamVolume())
                    "pickAlarmSound" -> pickAlarmSound(call.arguments as? String, result)
                    "alarmSoundTitle" ->
                        result.success(alarmSoundTitle(call.arguments as? String))
                    "resolveAlarmSound" ->
                        resolveAlarmSound(call.arguments as? String, result)
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

    // ── Alarm sound ──────────────────────────────────────────────────────

    /** The alarm stream's level over its maximum, or null when it cannot be read. */
    private fun alarmStreamVolume(): Double? {
        return try {
            val manager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return null
            val max = manager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            if (max <= 0) return null
            manager.getStreamVolume(AudioManager.STREAM_ALARM).toDouble() / max.toDouble()
        } catch (e: Exception) {
            null
        }
    }

    private fun pickAlarmSound(current: String?, result: MethodChannel.Result) {
        if (pendingSoundPicker != null) {
            result.error(ERROR_PICKER_BUSY, "A sound picker is already open", null)
            return
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            // The picker's own "Default" row, and what it stands for. Without
            // the explicit default URI the row resolves to the notification
            // default on some ROMs.
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            .putExtra(
                RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                Settings.System.DEFAULT_ALARM_ALERT_URI
            )
            // "Silent" is not an option the app offers: an alarm that plays
            // nothing is indistinguishable from one that failed.
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, storedUri(current))
        pendingSoundPicker = result
        try {
            startActivityForResult(intent, PICK_ALARM_SOUND_REQUEST)
        } catch (e: Exception) {
            pendingSoundPicker = null
            result.error(ERROR_NO_PICKER, "No ringtone picker on this device", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PICK_ALARM_SOUND_REQUEST) {
            val result = pendingSoundPicker
            pendingSoundPicker = null
            // The picker is the app's own request code, so nothing else in the
            // engine is waiting on it and there is nothing to forward.
            result?.success(pickedSound(resultCode, data))
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** `{value, title}`, or null for a cancelled pick. */
    private fun pickedSound(resultCode: Int, data: Intent?): Map<String, Any?>? {
        if (resultCode != Activity.RESULT_OK) return null
        val uri = try {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        } catch (e: Exception) {
            null
        } ?: return null
        val value = if (uri == Settings.System.DEFAULT_ALARM_ALERT_URI) {
            ALARM_SOUND_SYSTEM_DEFAULT
        } else {
            uri.toString()
        }
        return mapOf("value" to value, "title" to ringtoneTitle(uri))
    }

    /**
     * The phone's own name for a stored value, or null when it cannot resolve it.
     *
     * Openability is checked first because `Ringtone.getTitle` never says "no":
     * for a media id this phone's provider has never heard of — a sound picked
     * on another device — it answers the URI's last path segment, and the row
     * would read "1234" instead of saying the sound is not on this phone.
     */
    private fun alarmSoundTitle(value: String?): String? {
        val uri = storedUri(value) ?: return null
        if (value != ALARM_SOUND_SYSTEM_DEFAULT && !canOpen(uri)) return null
        return ringtoneTitle(uri)
    }

    private fun canOpen(uri: Uri): Boolean {
        return try {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { true } ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun ringtoneTitle(uri: Uri?): String? {
        if (uri == null) return null
        return try {
            RingtoneManager.getRingtone(this, uri)?.getTitle(this)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * The URI a stored value names, or null when it names none — "nothing
     * chosen" is the app's own business.
     */
    private fun storedUri(value: String?): Uri? {
        if (value.isNullOrEmpty()) return null
        if (value == ALARM_SOUND_SYSTEM_DEFAULT) return Settings.System.DEFAULT_ALARM_ALERT_URI
        return try {
            Uri.parse(value)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Copies a picked sound into `filesDir` once and answers its absolute path.
     *
     * Off the main thread because it reads a stream through a content provider,
     * and back on it because a `MethodChannel.Result` may only be answered
     * there. Null on every failure, including a URI this device cannot open —
     * the sound of another phone, which the app then rings the default alarm
     * instead of.
     */
    private fun resolveAlarmSound(value: String?, result: MethodChannel.Result) {
        val uri = storedUri(value)
        if (uri == null) {
            result.success(null)
            return
        }
        soundExecutor.execute {
            val path = try {
                copyAlarmSound(uri)
            } catch (e: Exception) {
                null
            }
            mainHandler.post { result.success(path) }
        }
    }

    private fun copyAlarmSound(uri: Uri): String? {
        val dir = File(filesDir, ALARM_SOUND_DIR)
        if (!dir.isDirectory && !dir.mkdirs()) return null
        val name = sha1(uri.toString())
        val target = File(dir, name)
        if (target.isFile && target.length() > 0L) return target.absolutePath
        // A half-written file that a killed process left behind would otherwise
        // "resolve" forever and ring a fraction of a second of noise.
        if (target.exists() && !target.delete()) return null
        val temp = File(dir, "$name.part")
        val copied = contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(temp).use { output -> input.copyTo(output) }
            true
        } ?: false
        if (!copied || temp.length() == 0L) {
            temp.delete()
            return null
        }
        if (!temp.renameTo(target)) {
            temp.delete()
            return null
        }
        return target.absolutePath
    }

    private fun sha1(value: String): String {
        val digest = MessageDigest.getInstance("SHA-1").digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
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
