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

class AlarmPlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null

    /** This engine's own channel to Dart, held per instance — see [alarmTriggerApi]. */
    private var triggerApi: AlarmTriggerApi? = null

    /**
     * Whether this instance has ever been bound to an activity, which is what
     * tells the engine that draws the app from one started headless.
     */
    private var hadActivity = false

    companion object {
        private const val TAG = "AlarmPlugin"

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
         * before.
         */
        @JvmStatic
        val alarmTriggerApi: AlarmTriggerApi?
            get() = synchronized(attached) {
                presenterOf(attached, { it.activity != null }, { it.hadActivity })?.triggerApi
            }

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
        synchronized(attached) { attached.add(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        AlarmApi.setUp(binding.binaryMessenger, null)
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
