package com.gdelataillade.alarm.services

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which sound values reach `MediaPlayer.setDataSource(Context, Uri)` untouched
 * (ANTA fork, Patch 2).
 *
 * The asset and path branches rewrite anything that does not start with `/`
 * into a path under the app's files directory, so a `content://` URI that
 * fell through to them would name nothing and the alarm would ring the
 * fallback error path rather than the sound the user picked.
 */
class AudioServiceTest {
    @Test
    fun `content, resource and file URIs are URI sources`() {
        assertTrue(AudioService.isUriSource("content://media/internal/audio/media/7"))
        assertTrue(AudioService.isUriSource("content://settings/system/alarm_alert"))
        assertTrue(AudioService.isUriSource("android.resource://com.example/raw/ring"))
        assertTrue(AudioService.isUriSource("file:///sdcard/Alarms/ring.ogg"))
    }

    @Test
    fun `assets and absolute paths keep their own branches`() {
        assertFalse(AudioService.isUriSource("assets/sounds/ring.mp3"))
        assertFalse(AudioService.isUriSource("/data/user/0/com.example/files/ring.mp3"))
        assertFalse(AudioService.isUriSource("sounds/ring.mp3"))
        assertFalse(AudioService.isUriSource(""))
    }
}
