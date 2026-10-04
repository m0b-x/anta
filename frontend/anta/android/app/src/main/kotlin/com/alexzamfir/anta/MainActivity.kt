package com.alexzamfir.anta

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.Observer
import com.gdelataillade.alarm.alarm.AlarmService
import com.gdelataillade.alarm.services.AlarmRingingLiveData
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

private const val ALERTS_CHANNEL = "com.alexzamfir.anta/alerts"
private const val PERMISSIONS_CHANNEL = "com.alexzamfir.anta/permissions"
private const val WINDOW_CHANNEL = "com.alexzamfir.anta/window"

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

/**
 * Where builds before OS-1 (2026-09-22) copied a picked sound to, under
 * `filesDir`. Nothing reads it any more — the `alarm` fork plays a `content://`
 * URI directly — so it is deleted once on the next launch and the name survives
 * only for that.
 */
private const val LEGACY_ALARM_SOUND_DIR = "alert_sounds"

/**
 * The three app-owned channels.
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
 * alarm would not wake anyone. `consumeShowAlarmsRequest` answers whether this
 * activity was started by the show intent an alarm-clock entry carries
 * ([AlarmService.ACTION_SHOW], the `alarm` fork's Patch 1 — what the lock
 * screen's alarm line and Quick Settings launch): true once, then false. A warm
 * activity receives the same intent through [onNewIntent] and pushes
 * `showAlarms` to Dart instead, since nothing on the Dart side is asking then.
 * `showSessionChip` and `clearSessionChip` draw and take down the session
 * chip ([SessionChip], OS-5), and `consumeSessionOpenRequest` answers the
 * chip's *Open note* the way the show intent is answered — the payload it
 * carried once, then null — with a warm activity pushing `openSession`.
 * `consumeQuickAlarmRequest` is the same pair for the Quick Settings tile and
 * the launcher shortcut ([QuickAlarmTileService.ACTION_QUICK_ALARM], OS-5):
 * true once for a cold start, `quickAlarm` pushed for a warm one.
 *
 * `keyguardLocked` answers whether the lock screen is up, and `keyguardChanged`
 * is pushed to Dart whenever that may have moved — the activity starting or
 * resuming, a ring starting or ending, the user unlocking. While a ring holds
 * the app above the keyguard, that answer is what keeps everything but the
 * alarm page behind a curtain on the Dart side. `dismissKeyguard` asks the
 * user to unlock from there — the PIN bouncer over the alarm page — and
 * answers whether they did, which is how *Open event* leaves a locked phone.
 *
 * The two **sound** methods exist because the platform's ringtone picker and
 * titles have no Dart binding. `pickAlarmSound` runs the system picker (alarm
 * type, its own "Default" entry mapped to [ALARM_SOUND_SYSTEM_DEFAULT] so the
 * stored value keeps following the Clock app rather than freezing today's
 * choice) and `alarmSoundTitle` names a stored value for the UI. A picked
 * `content://` URI is handed to the `alarm` fork as it is — its `AudioService`
 * opens a URI through `MediaPlayer.setDataSource(Context, Uri)` and falls back
 * to the phone's default alarm when the device cannot open it, so the copy
 * into `filesDir` that older builds made is gone and its directory is deleted
 * once ([LEGACY_ALARM_SOUND_DIR]). Everything here is failure-tolerant by
 * design: a sound that cannot be resolved answers null and the app rings the
 * phone's default alarm, because an alarm that does not sound is far worse
 * than an alarm that sounds wrong.
 *
 * **Window** has one method, [resyncInsets], which repairs a keyboard inset
 * the engine left behind after the keyboard itself had gone.
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

    /** The alerts channel, kept so the activity can push to Dart unprompted. */
    private var alertsChannel: MethodChannel? = null

    /**
     * Whether an [AlarmService.ACTION_SHOW] intent has reached this activity
     * and not been consumed yet. Set from both [onCreate] and [onNewIntent];
     * read and cleared by `consumeShowAlarmsRequest`.
     */
    private var showAlarmsRequested = false

    /**
     * The payload the session chip's *Open note* started this activity with,
     * until Dart has consumed it — [showAlarmsRequested] with a value, since
     * the chip names the alarm whose note to open.
     */
    private var pendingSessionOpen: String? = null

    /**
     * Whether the Quick Settings tile or the launcher shortcut started this
     * activity and Dart has not been told — [showAlarmsRequested] for the
     * quick-alarm sheet.
     */
    private var quickAlarmRequested = false

    /**
     * Follows the `alarm` fork's "a ring is in progress" value for the whole
     * life of the activity — **forever**, not bound to the lifecycle.
     *
     * The fork's own observer is lifecycle-bound, so it hears nothing while
     * the activity is stopped. A ring that ended behind a dark screen therefore
     * left `showWhenLocked` raised until the next start, and the next wake put
     * the app on top of the lock screen with no ring to show for it. See
     * [onRingingChanged].
     */
    private val ringObserver = Observer<Boolean> { ringing -> onRingingChanged(ringing == true) }

    /** Tells Dart the moment the user gets past the lock screen. */
    private val userPresentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            reportKeyguard()
        }
    }

    /**
     * A re-created activity is handed the intent it was **first** started
     * with, and every request an intent can carry here is a one-shot: the
     * quick-alarm tile and shortcut, the alarm-clock show intent, the session
     * chip's *Open note*, a tapped notification. Read again, each one is
     * replayed — and a replay lands on top of whatever the app is showing.
     * The case that mattered: an alarm rings in a process the system had
     * killed, its full-screen intent re-creates the activity, the old
     * quick-alarm request collapses the stack onto the calendar, and the alarm
     * page is gone while the phone is still ringing.
     *
     * So a restore starts from a plain launch intent, swapped in **before**
     * `super.onCreate`: `flutter_local_notifications` reads the activity's
     * intent as soon as it is attached, and again whenever Dart asks which
     * notification launched the app.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        if (isRestore(savedInstanceState, intent)) intent = plainLaunchIntent()
        // Before `super.onCreate`, which attaches the plugins: LiveData calls
        // its observers in the order they registered, and [onRingingChanged]
        // has to leave the lock screen while the fork's observer has not yet
        // lowered the flags.
        AlarmRingingLiveData.instance.observeForever(ringObserver)
        super.onCreate(savedInstanceState)
        SessionChip.clearIfStale(this)
        recordShowAlarmsRequest(intent)
        recordSessionOpenRequest(intent)
        recordQuickAlarmRequest(intent)
    }

    override fun onStart() {
        super.onStart()
        ContextCompat.registerReceiver(
            this,
            userPresentReceiver,
            IntentFilter(Intent.ACTION_USER_PRESENT),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        reportKeyguard()
    }

    override fun onResume() {
        super.onResume()
        reportKeyguard()
    }

    /**
     * An unlock can resume the activity while the keyguard is still animating
     * away, when it still answers "locked", and `USER_PRESENT` can go out
     * before [onStart] has registered for it. Focus arrives once the keyguard
     * window has let go of it, which makes this the report that cannot be
     * early — without it the curtain could stay over an unlocked app.
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) reportKeyguard()
    }

    override fun onStop() {
        runCatching { unregisterReceiver(userPresentReceiver) }
        super.onStop()
    }

    override fun onDestroy() {
        AlarmRingingLiveData.instance.removeObserver(ringObserver)
        super.onDestroy()
    }

    /**
     * Whether this creation is the system putting an old activity back rather
     * than something asking for it now: saved state to restore, or a launch
     * out of Recents, which re-sends the task's first intent.
     */
    private fun isRestore(savedInstanceState: Bundle?, intent: Intent?): Boolean {
        if (savedInstanceState != null) return true
        val flags = intent?.flags ?: return false
        return flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
    }

    private fun plainLaunchIntent(): Intent =
        Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setClass(this, MainActivity::class.java)

    /**
     * Keeps the lock-screen flags in step with the ring, whatever state the
     * activity is in.
     *
     * Raised the moment a ring starts — before the full-screen intent arrives,
     * so the launch finds an activity already allowed above the keyguard
     * instead of depending on it being started first. `turnScreenOn` goes
     * first because `setShowWhenLocked` is the call that makes the system
     * look at both.
     *
     * Lowered the moment it ends, stopped or not. Lowering alone is not
     * enough when the app is in front of a locked keyguard: the platform
     * parks the un-occlusion until the next key press, and until then the
     * page under the alarm — notes, the ledger, the calendar — stays on
     * screen and takes touches without a PIN (seen on API 36, 2026-10-04).
     * So the task is sent to the back **first, with the flags still up**:
     * leaving is a real transition away from an occluding activity, which is
     * what brings the keyguard back. Lowering first and leaving second moves
     * a task the system already counts as hidden, and nothing changes on
     * screen.
     */
    private fun onRingingChanged(ringing: Boolean) {
        if (!ringing && isOverKeyguard()) moveTaskToBack(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setTurnScreenOn(ringing)
            setShowWhenLocked(ringing)
        }
        reportKeyguard()
    }

    /** Whether this activity is on screen in front of a locked keyguard. */
    private fun isOverKeyguard(): Boolean =
        lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) && isKeyguardLocked()

    private fun isKeyguardLocked(): Boolean {
        val manager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return manager?.isKeyguardLocked == true
    }

    /** Pushes the lock-screen state to Dart; a push with no handler yet is lost, and Dart asks at launch. */
    private fun reportKeyguard() {
        alertsChannel?.invokeMethod("keyguardChanged", isKeyguardLocked())
    }

    /**
     * Asks the user to unlock and answers whether they did. True at once when
     * nothing is locked; false where the platform cannot ask (below API 26).
     */
    private fun dismissKeyguard(result: MethodChannel.Result) {
        if (!isKeyguardLocked()) {
            result.success(true)
            return
        }
        val manager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (manager == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        manager.requestDismissKeyguard(
            this,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    reportKeyguard()
                    result.success(true)
                }

                override fun onDismissCancelled() {
                    result.success(false)
                }

                override fun onDismissError() {
                    result.success(false)
                }
            }
        )
    }

    /**
     * The warm half. The flag is recorded first so a push that finds no Dart
     * handler yet — the engine attached, the gateway not — is still answered by
     * the next `consumeShowAlarmsRequest`; a push Dart acknowledged clears it,
     * or a hot restart's fresh `launchIntent()` would open the hub a second
     * time.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (recordQuickAlarmRequest(intent)) {
            alertsChannel?.invokeMethod(
                "quickAlarm",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        quickAlarmRequested = false
                    }

                    override fun error(code: String, message: String?, details: Any?) {}

                    override fun notImplemented() {}
                }
            )
            return
        }
        if (recordSessionOpenRequest(intent)) {
            alertsChannel?.invokeMethod(
                "openSession",
                pendingSessionOpen,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        pendingSessionOpen = null
                    }

                    override fun error(code: String, message: String?, details: Any?) {}

                    override fun notImplemented() {}
                }
            )
            return
        }
        if (!recordShowAlarmsRequest(intent)) return
        alertsChannel?.invokeMethod(
            "showAlarms",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    showAlarmsRequested = false
                }

                override fun error(code: String, message: String?, details: Any?) {}

                override fun notImplemented() {}
            }
        )
    }

    private fun recordShowAlarmsRequest(intent: Intent?): Boolean {
        if (intent?.action != AlarmService.ACTION_SHOW) return false
        showAlarmsRequested = true
        return true
    }

    private fun consumeShowAlarmsRequest(): Boolean {
        val requested = showAlarmsRequested
        showAlarmsRequested = false
        return requested
    }

    private fun recordSessionOpenRequest(intent: Intent?): Boolean {
        if (intent?.action != SessionChip.ACTION_OPEN) return false
        pendingSessionOpen = intent.getStringExtra(SessionChip.EXTRA_PAYLOAD) ?: return false
        return true
    }

    private fun consumeSessionOpenRequest(): String? {
        val payload = pendingSessionOpen
        pendingSessionOpen = null
        return payload
    }

    private fun recordQuickAlarmRequest(intent: Intent?): Boolean {
        if (intent?.action != QuickAlarmTileService.ACTION_QUICK_ALARM) return false
        quickAlarmRequested = true
        return true
    }

    private fun consumeQuickAlarmRequest(): Boolean {
        val requested = quickAlarmRequested
        quickAlarmRequested = false
        return requested
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val alerts = MethodChannel(messenger, ALERTS_CHANNEL)
        alertsChannel = alerts
        alerts.setMethodCallHandler { call, result ->
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
                "consumeShowAlarmsRequest" -> result.success(consumeShowAlarmsRequest())
                "consumeSessionOpenRequest" -> result.success(consumeSessionOpenRequest())
                "consumeQuickAlarmRequest" -> result.success(consumeQuickAlarmRequest())
                "keyguardLocked" -> result.success(isKeyguardLocked())
                "dismissKeyguard" -> dismissKeyguard(result)
                "showSessionChip" ->
                    result.success(SessionChip.show(this, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
                "clearSessionChip" -> {
                    SessionChip.clear(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        deleteLegacyAlarmSoundCopies()
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
        MethodChannel(messenger, WINDOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "resyncInsets" -> result.success(resyncInsets())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Has the window dispatch its insets again, so the Flutter view hears the
     * current ones. Answers whether a dispatch was asked for.
     *
     * The engine's `ImeSyncDeferringInsetsCallback` consumes every inset
     * dispatch while a keyboard animation runs and, when the animation ends,
     * replays the insets it saved as the animation began. An inset change
     * that landed in between is lost, and the view is left reporting a
     * keyboard the window no longer has until the insets next change — which
     * can be a long time, since nothing is wrong as far as the window knows.
     * Once the replay is over the callback passes dispatches through again,
     * and the view sends viewport metrics for every one it is handed, changed
     * or not; asking for a dispatch is therefore the whole repair.
     *
     * It has to be a dispatch through the hierarchy. Handing the view its
     * root insets with `onApplyWindowInsets` looks equivalent and is not:
     * outside a dispatch, `View.onApplyWindowInsets` falls back to
     * `fitSystemWindows`, which dispatches a compatibility `WindowInsets`
     * that has no IME type — the view reports a keyboard as system-bar
     * padding first and the real insets a moment later (two metric packets
     * per call, measured on the emulator), and an animation that starts in
     * that moment can save the compatibility object as the insets to replay.
     * Root insets also differ from what a child is dispatched: the display
     * cutout is still in them, and so is the navigation bar on a window that
     * is not edge-to-edge.
     *
     * Nothing defers insets below API 30, so there is nothing to repair
     * there. A callback that never saw its animation end keeps consuming and
     * is out of reach from here; the next keyboard animation releases it.
     */
    private fun resyncInsets(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        window.decorView.requestApplyInsets()
        return true
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
     * Removes the sound copies builds before OS-1 kept under
     * [LEGACY_ALARM_SOUND_DIR]. Idempotent, off the main thread, and silent
     * about a directory that is already gone.
     */
    private fun deleteLegacyAlarmSoundCopies() {
        val dir = File(filesDir, LEGACY_ALARM_SOUND_DIR)
        if (!dir.exists()) return
        Thread { runCatching { dir.deleteRecursively() } }.start()
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
