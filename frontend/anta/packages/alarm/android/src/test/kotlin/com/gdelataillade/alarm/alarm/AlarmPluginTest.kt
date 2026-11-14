package com.gdelataillade.alarm.alarm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Which engine a ring is reported to when the process holds more than one
 * (ANTA fork, Patch 4).
 *
 * The second engine is real: `flutter_local_notifications` starts a headless
 * one for a notification action handled in the background and keeps it for the
 * life of the process. Reporting to it is reporting to nobody — its isolate
 * never initialised the plugin — so the app's own isolate saw no ring.
 */
class AlarmPluginTest {
    private data class Engine(
        val name: String,
        val hasActivity: Boolean = false,
        val hadActivity: Boolean = false,
        val presents: Boolean = true,
    )

    private fun presenter(vararg engines: Engine): String? =
        AlarmPlugin.presenterOf(engines.toList(), { it.hasActivity }, { it.hadActivity })?.name

    /**
     * What [AlarmPlugin.alarmTriggerApi] itself asks: the one function its
     * getter is, so a getter that stopped setting resigned engines aside
     * fails here.
     */
    private fun presenterAmong(vararg engines: Engine): String? =
        AlarmPlugin.presenterAmong(
            engines.toList(),
            { it.presents },
            { it.hasActivity },
            { it.hadActivity },
        )?.name

    // Patch 10: an engine started for background work resigns, and a ring is
    // then reported as if that engine were not there.

    @Test
    fun `an engine that resigned is never told, even alone`() {
        assertNull(presenterAmong(Engine("work", presents = false)))
    }

    @Test
    fun `beside a resigned engine the app's engine is told, whichever attached first`() {
        val app = Engine("app", hasActivity = true, hadActivity = true)
        val work = Engine("work", presents = false)

        assertEquals("app", presenterAmong(work, app))
        assertEquals("app", presenterAmong(app, work))
    }

    @Test
    fun `a headless engine that did not resign is still told, as before`() {
        assertEquals(
            "background",
            presenterAmong(Engine("work", presents = false), Engine("background")),
        )
    }

    @Test
    fun `the channel's names are the ones Dart says`() {
        assertEquals("com.gdelataillade.alarm/presenter", AlarmPlugin.PRESENTER_CHANNEL)
        assertEquals("resign", AlarmPlugin.RESIGN)
    }

    @Test
    fun `no engine, nobody to tell`() {
        assertNull(presenter())
    }

    @Test
    fun `the only engine is told, headless or not`() {
        assertEquals("background", presenter(Engine("background")))
    }

    @Test
    fun `a headless engine attached later does not take the ring`() {
        assertEquals(
            "app",
            presenter(Engine("app", hasActivity = true, hadActivity = true), Engine("background")),
        )
    }

    @Test
    fun `the app's engine wins even when the headless one came first`() {
        // The process was started by a notification action, then the app was
        // opened: attach order says "background", the activity says "app".
        assertEquals(
            "app",
            presenter(Engine("background"), Engine("app", hasActivity = true, hadActivity = true)),
        )
    }

    @Test
    fun `an engine between activities keeps the ring across a configuration change`() {
        assertEquals(
            "app",
            presenter(Engine("background"), Engine("app", hadActivity = true)),
        )
    }
}
