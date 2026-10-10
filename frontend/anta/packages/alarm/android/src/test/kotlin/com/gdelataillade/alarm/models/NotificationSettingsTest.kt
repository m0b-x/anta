package com.gdelataillade.alarm.models

import com.gdelataillade.alarm.generated.NotificationSettingsWire
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The icon colour a ring's notification is drawn in, from the four channels
 * Dart sends (ANTA fork, Patch 8).
 *
 * Upstream handed them to `android.graphics.Color.argb(float, float, float,
 * float)`, an API 26 overload, from a plugin whose `minSdk` is 19 inside an
 * application whose `minSdk` is 24: on Android 7.0 and 7.1 every `Alarm.set`
 * that named a colour threw `NoSuchMethodError` and took the process down. The
 * int is now packed by the plugin itself, with the platform's own arithmetic,
 * and this suite holds it to what API 26 and later have always been handed.
 */
class NotificationSettingsTest {
    /** The wire form of a notification whose colour is [channels], in order a, r, g, b. */
    private fun wire(channels: List<Double?>) = NotificationSettingsWire(
        title = "Title",
        body = "Body",
        iconColorAlpha = channels[0],
        iconColorRed = channels[1],
        iconColorGreen = channels[2],
        iconColorBlue = channels[3],
        keepNotificationAfterAlarmEnds = false,
        androidStopAlarmOnDismiss = true,
    )

    /**
     * ANTA's purple, `0xFF6750A4`, as Flutter's `Color` reads it out: each
     * channel a double, its byte over 255.
     */
    private val purple = listOf(1.0, 0x67 / 255.0, 0x50 / 255.0, 0xA4 / 255.0)

    @Test
    fun `the four channels Dart sends are the colour they were in Dart`() {
        assertEquals(
            0xFF6750A4.toInt(),
            NotificationSettings.fromWire(wire(purple)).iconColor,
        )
    }

    @Test
    fun `a channel left out names no colour`() {
        for (missing in 0..3) {
            val channels = purple.toMutableList<Double?>().apply { set(missing, null) }

            assertNull(
                "channel $missing left out",
                NotificationSettings.fromWire(wire(channels)).iconColor,
            )
        }
    }

    @Test
    fun `a channel is narrowed to a float first, as the platform's overload took it`() {
        // Just under a half. As a float it is a half, which scales and rounds
        // up to 128; as a double, scaled and with the half added, it is
        // 127.99999999974, which a pack done in doubles would cut to 127. The
        // colour API 26 and later were handed came through the float overload,
        // so 128 is the byte to keep.
        val color = NotificationSettings.fromWire(wire(listOf(1.0, 0.5 - 1e-12, 0.0, 0.0)))
            .iconColor

        assertEquals(0xFF800000.toInt(), color)
    }

    @Test
    fun `each channel lands in its own byte, alpha highest`() {
        assertEquals(
            0xFF6750A4.toInt(),
            NotificationSettings.packArgb(1f, 0x67 / 255f, 0x50 / 255f, 0xA4 / 255f),
        )
    }

    @Test
    fun `the ends of the range are the ends of the int`() {
        assertEquals(0, NotificationSettings.packArgb(0f, 0f, 0f, 0f))
        // All four bytes 0xFF, the sign bit among them.
        assertEquals(-1, NotificationSettings.packArgb(1f, 1f, 1f, 1f))
    }

    @Test
    fun `a half rounds up, as the platform rounds it`() {
        // 0.5 * 255 is 127.5, the one exact tie the range holds: the platform
        // adds a half and truncates, so 128. A pack that only truncated would
        // say 127 here, and a step under the platform for about half of all
        // values.
        assertEquals(0x80808080.toInt(), NotificationSettings.packArgb(0.5f, 0.5f, 0.5f, 0.5f))
    }
}
