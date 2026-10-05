package com.gdelataillade.alarm.alarm

import com.gdelataillade.alarm.alarm.AlarmService.RingWakeLock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * When the service's wake lock is taken and when it is let go (ANTA fork,
 * Patch 6).
 *
 * Upstream took a five-minute lock at every ring start and kept no reference
 * to it, so nothing could release it: a ring stopped after two seconds kept
 * the CPU awake for the other four minutes and fifty-eight, and every queued
 * alarm promoted in its turn added a lock of its own.
 */
class RingWakeLockTest {
    /** A `PowerManager.WakeLock`, as far as the holder can tell the two apart. */
    private class FakeLock(
        private val name: String,
        private val log: MutableList<String>,
    ) : RingWakeLock.Lock {
        override var isHeld = false
            private set

        override fun acquire(timeoutMillis: Long) {
            isHeld = true
            log += "acquire $name for $timeoutMillis"
        }

        override fun release() {
            // What the platform does with a release it was not owed.
            if (!isHeld) throw RuntimeException("WakeLock under-locked $name")
            isHeld = false
            log += "release $name"
        }

        /** The platform letting go by itself, once the timeout has run out. */
        fun timeOut() {
            isHeld = false
        }
    }

    private val log = mutableListOf<String>()
    private val made = mutableListOf<FakeLock>()
    private val wakeLock = RingWakeLock {
        FakeLock("lock${made.size + 1}", log).also { made += it }
    }

    @Test
    fun `a ring takes one lock, for five minutes at most`() {
        wakeLock.acquire()

        assertEquals(listOf("acquire lock1 for 300000"), log)
        assertTrue(made.single().isHeld)
        assertEquals(5 * 60 * 1000L, RingWakeLock.MAX_HOLD_MILLIS)
    }

    @Test
    fun `the end of the ring lets it go`() {
        wakeLock.acquire()
        wakeLock.release()

        assertEquals(listOf("acquire lock1 for 300000", "release lock1"), log)
        assertFalse(made.single().isHeld)
    }

    @Test
    fun `a second release is not passed on`() {
        // The last ring's cleanup releases, and the service's destruction, which
        // that cleanup asks for, releases again.
        wakeLock.acquire()
        wakeLock.release()
        wakeLock.release()

        assertEquals(listOf("acquire lock1 for 300000", "release lock1"), log)
    }

    @Test
    fun `a lock the platform let go at its bound is not released again`() {
        // A ring left alone for more than five minutes, then stopped.
        wakeLock.acquire()
        made.single().timeOut()
        wakeLock.release()

        assertEquals(listOf("acquire lock1 for 300000"), log)
    }

    @Test
    fun `with nothing held, a release makes no lock and releases none`() {
        // A service destroyed without having rung: every start it was given
        // was out of date.
        wakeLock.release()

        assertTrue(log.isEmpty())
        assertTrue(made.isEmpty())
    }

    @Test
    fun `a ring promoted from the queue lets the last lock go before it takes its own`() {
        wakeLock.acquire()
        wakeLock.acquire()

        assertEquals(
            listOf(
                "acquire lock1 for 300000",
                "release lock1",
                "acquire lock2 for 300000",
            ),
            log,
        )
        assertFalse(made[0].isHeld)
        assertTrue(made[1].isHeld)
    }

    @Test
    fun `a promoted ring leaves a lock that had already timed out alone`() {
        wakeLock.acquire()
        made.single().timeOut()
        wakeLock.acquire()

        assertEquals(listOf("acquire lock1 for 300000", "acquire lock2 for 300000"), log)
        assertTrue(made[1].isHeld)
    }

    @Test
    fun `after the last ring, the next one takes a lock of its own`() {
        wakeLock.acquire()
        wakeLock.release()
        wakeLock.acquire()
        wakeLock.release()

        assertEquals(
            listOf(
                "acquire lock1 for 300000",
                "release lock1",
                "acquire lock2 for 300000",
                "release lock2",
            ),
            log,
        )
        assertTrue(made.none { it.isHeld })
    }
}
