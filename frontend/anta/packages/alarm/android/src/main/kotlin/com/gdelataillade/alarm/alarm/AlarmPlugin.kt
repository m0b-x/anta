package com.gdelataillade.alarm.alarm

import com.gdelataillade.alarm.generated.AlarmApi
import com.gdelataillade.alarm.generated.AlarmTriggerApi
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.Observer
import com.gdelataillade.alarm.api.AlarmApiImpl
import com.gdelataillade.alarm.services.AlarmRingingLiveData
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

class AlarmPlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null

    /** This engine's own channel to Dart, held per instance — see [alarmTriggerApi]. */
    private var triggerApi: AlarmTriggerApi? = null

    /**
     * Whether this instance has ever been bound to an activity, which is what
     * tells the engine that draws the app from one started headless.
     */
    private var hadActivity = false

    /**
     * Whether alarms may be presented to this engine (ANTA fork, Patch 10).
     *
     * True until the engine's own Dart says otherwise over
     * [PRESENTER_CHANNEL]: an engine started for background work — no
     * activity, a life of seconds — sets and stops alarms through the same
     * API as any other, and must never be where a ring is reported. With no
     * app in the process it was the only engine attached, so [presenterOf]
     * chose it: the ring's page and its silence timer went to an isolate
     * that ended a moment later.
     */
    @Volatile
    private var presents = true

    /** The fork's own channel beside the generated bindings: one word, [RESIGN]. */
    private var presenterChannel: MethodChannel? = null

    companion object {
        private const val TAG = "AlarmPlugin"

        /** The channel an engine resigns on, and the one method it carries. */
        internal const val PRESENTER_CHANNEL = "com.gdelataillade.alarm/presenter"
        internal const val RESIGN = "resign"

        /** Every engine this plugin is attached to, in attach order. */
        private val attached = mutableListOf<AlarmPlugin>()

        /**
         * The channel to the isolate that presents alarms (ANTA fork, Patch 4).
         *
         * Upstream keeps one static that every attach overwrites and every
         * detach nulls, which is only right while a process has one engine. It
         * does not: `flutter_local_notifications` starts a second, headless
         * engine for a notification action handled in the background and never
         * destroys it, and plugins register on that engine too. From then on a
         * ring, a stop and a host event were all reported to an isolate that
         * never called `Alarm.init()` and has no handler — the app's own
         * isolate heard nothing, so a ringing alarm showed no page and a Stop
         * on the notification was never settled.
         *
         * Resolved per call instead, by [presenterOf]. A lone headless engine
         * is still answered — the reply is an error nobody is waiting on, as
         * before — unless it has resigned ([presenters], Patch 10): then
         * there is nobody to tell, exactly as in a process with no engine.
         */
        @JvmStatic
        val alarmTriggerApi: AlarmTriggerApi?
            get() = synchronized(attached) {
                presenterAmong(
                    attached,
                    { it.presents },
                    { it.activity != null },
                    { it.hadActivity },
                )?.triggerApi
            }

        /**
         * [alarmTriggerApi]'s whole choice in one pure function, so the unit
         * test asks what the getter asks: the engines that resigned are set
         * aside ([presenters]), and [presenterOf] picks among the rest. A
         * test that composed the two itself went on passing with the filter
         * gone from the getter.
         */
        internal fun <T> presenterAmong(
            attached: List<T>,
            presents: (T) -> Boolean,
            hasActivity: (T) -> Boolean,
            hadActivity: (T) -> Boolean,
        ): T? = presenterOf(presenters(attached, presents), hasActivity, hadActivity)

        /**
         * The engines a ring may be reported to: every attached one that has
         * not resigned (ANTA fork, Patch 10), in attach order. Pure, like
         * [presenterOf], and pinned the same way.
         */
        internal fun <T> presenters(
            attached: List<T>,
            presents: (T) -> Boolean,
        ): List<T> = attached.filter(presents)

        /**
         * Which of the [attached] engines presents alarms: the one bound to an
         * activity, else one that has been (a configuration change unbinds it
         * for a moment), else the oldest. Pure, so the order is pinned by a
         * unit test rather than by a device.
         */
        internal fun <T> presenterOf(
            attached: List<T>,
            hasActivity: (T) -> Boolean,
            hadActivity: (T) -> Boolean,
        ): T? = attached.firstOrNull(hasActivity)
            ?: attached.firstOrNull(hadActivity)
            ?: attached.firstOrNull()
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        AlarmApi.setUp(binding.binaryMessenger, AlarmApiImpl(binding.applicationContext))
        triggerApi = AlarmTriggerApi(binding.binaryMessenger)
        val channel = MethodChannel(binding.binaryMessenger, PRESENTER_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == RESIGN) {
                presents = false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        presenterChannel = channel
        synchronized(attached) { attached.add(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        AlarmApi.setUp(binding.binaryMessenger, null)
        presenterChannel?.setMethodCallHandler(null)
        presenterChannel = null
        synchronized(attached) { attached.remove(this) }
        triggerApi = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        hadActivity = true
        activity = binding.activity
        AlarmRingingLiveData.instance.observe(
            binding.activity as LifecycleOwner,
            notificationObserver
        )
    }

    override fun onDetachedFromActivity() {
        activity = null
        AlarmRingingLiveData.instance.removeObserver(notificationObserver)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    private val notificationObserver = Observer<Boolean> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            Log.w(TAG, "Making app visible on lock screen is not supported on this version of Android.")
            return@Observer
        }
        val activity = activity ?: return@Observer
        if (it) {
            Log.d(TAG, "Making app visible on lock screen...")
            activity.setShowWhenLocked(true)
            activity.setTurnScreenOn(true)
            // The calls above already show the alarm over the lock screen; dismissing a
            // secure keyguard on top of that would only prompt the user to authenticate.
            val keyguardManager =
                activity.applicationContext.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (!keyguardManager.isDeviceSecure) {
                keyguardManager.requestDismissKeyguard(activity, null)
            }
        } else {
            Log.d(TAG, "Reverting making app visible on lock screen...")
            activity.setShowWhenLocked(false)
            activity.setTurnScreenOn(false)
        }
    }
}
