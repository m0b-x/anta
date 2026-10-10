package com.gdelataillade.alarm.models

import com.gdelataillade.alarm.generated.NotificationSettingsWire
import kotlinx.serialization.Serializable

@Serializable
data class NotificationSettings(
    val title: String,
    val body: String,
    val stopButton: String? = null,
    val icon: String? = null,
    val iconColor: Int? = null,
    val keepNotificationAfterAlarmEnds: Boolean = false,
    val androidSnoozeButton: String? = null,
    // Defaults to true so alarms persisted before this flag existed, which
    // decode without the key, keep stopping on a dismiss as they did.
    val androidStopAlarmOnDismiss: Boolean = true,
) {
    companion object {
        fun fromWire(e: NotificationSettingsWire): NotificationSettings {
            val a = e.iconColorAlpha?.toFloat()
            val r = e.iconColorRed?.toFloat()
            val g = e.iconColorGreen?.toFloat()
            val b = e.iconColorBlue?.toFloat()

            var iconColor: Int? = null
            if (a != null && r != null && g != null && b != null) {
                iconColor = packArgb(a, r, g, b)
            }

            return NotificationSettings(
                e.title,
                e.body,
                e.stopButton,
                e.icon,
                iconColor,
                e.keepNotificationAfterAlarmEnds,
                e.androidSnoozeButton,
                e.androidStopAlarmOnDismiss,
            )
        }

        /**
         * The colour int `android.graphics.Color.argb(float, float, float,
         * float)` returns for four channels in 0..1, worked out here
         * (ANTA fork, Patch 8).
         *
         * That overload came in API 26, and this plugin's `minSdk` is 19 —
         * ANTA's 24: below 26 the call threw `NoSuchMethodError` from every
         * `Alarm.set` that named a colour, which on Android 7.0 and 7.1 was
         * every alarm ANTA set, and took the process down. The body is the
         * platform's own, float arithmetic and rounding half up included, so
         * API 26 and later get the very int they were always handed. Not the
         * `int` overload, which every level has: the module's JVM tests run on
         * a stubbed `android.jar` that answers 0 for any `Color` call, so a
         * colour that went through one could never be pinned
         * (`NotificationSettingsTest`).
         */
        internal fun packArgb(alpha: Float, red: Float, green: Float, blue: Float): Int =
            ((alpha * 255.0f + 0.5f).toInt() shl 24) or
                ((red * 255.0f + 0.5f).toInt() shl 16) or
                ((green * 255.0f + 0.5f).toInt() shl 8) or
                (blue * 255.0f + 0.5f).toInt()
    }
}