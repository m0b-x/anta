# Alarm evidence

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

Pointer: "the one-swipe recipe below" in the last line of this file is "Notification-shade actions" in `traps.md`.

## Alarm-clock evidence (event alerts, Android)

The Alarm tier is armed with `AlarmManager.setAlarmClock` (the `alarm` fork,
event-alerts session OS-1, 2026-09-22), and the platform's own record is the
evidence — there is no `qa alerts` verb yet (the parent roadmap's Session 7).
Three **read-only** shell queries, run from the host, are the accepted
exception to "never drive adb by hand": they neither touch the app nor its
data.

```bash
adb shell dumpsys alarm | grep -A9 "RTC_WAKEUP #.*com.alexzamfir.anta"
adb shell settings get system next_alarm_formatted   # legacy key; may be empty on some ROMs
adb shell run-as com.alexzamfir.anta ls files        # debug builds only
```

What a passing entry looks like (emulator, API 36.1, 2026-09-22): the ANTA
entry prints an `Alarm clock:` block (`triggerTime=…` and
`showIntent=PendingIntent{… com.alexzamfir.anta startActivity}`), a
`flags=` mask that includes `0x2` (`WAKE_FROM_IDLE`), an `idle-options`
bundle with `temporaryAppAllowlistReasonCode=301`
(`REASON_ALARM_MANAGER_ALARM_CLOCK`), and it is listed under `Next wake from
idle:`. The `0x8` bit (`ALLOW_WHILE_IDLE_UNRESTRICTED`) the owner's-phone
checklist mentions is **not** in the mask on API 36 — the exemption rides the
idle options instead — so read the block, not one bit. A reminder entry
(`ScheduledNotificationReceiver`) prints no such block. The status bar's
alarm icon reads `"Alarm set for <time>."` in a native dump, and the
Quick Settings header row with the same text opens the Alerts hub. Locking
the emulator needs a keyguard: `locksettings get-disabled` prints `true` on
a stock AVD, `locksettings set-disabled false` gives it the swipe lock
screen for the check, and `set-disabled true` puts it back.

## A ring on a locked phone (2026-10-04)

`locksettings set-disabled false` only gives the swipe lock screen; the
cases that matter need a **PIN**, and a ring in a **dead process**. The
recipe, the by-hand calls it sanctions (all device-UI or read-only, none
touching app data) and what each proves are in
`docs/event-alerts-os-integration-roadmap.md` §13.4. In short:

- `locksettings set-pin 1234` after `set-disabled false`; **put it back**
  with `locksettings clear --old 1234` and `set-disabled true`.
- The screen times out on the lock screen in about ten seconds, so wake
  first: `input keyevent KEYCODE_WAKEUP`, `wm dismiss-keyguard`, `input
  text 1234`, `KEYCODE_ENTER`. A `qa launch` behind a keyguard brings
  nothing to the front, and the agent then sees "nothing labelled".
- `am kill` does not kill the app that was in front when the screen went
  off (it is top-sleeping, not cached); `run-as com.alexzamfir.anta kill -9
  <pid>` does, and keeps the task — which is what a system kill looks like.
  `qa relaunch` force-stops instead: the task and the alarms go, and on
  Android 15+ the next launch gets `BOOT_COMPLETED`, so the fork re-rings any
  stored alarm under 30 minutes late.
- After a kill the VM service is gone; the next agent verb recovers the URI
  from logcat. The agent's tap on Stop over a keyguard can report a 30 s
  driver timeout although the tap landed — the app is paused the moment the
  ring ends.
- `dumpsys activity service com.android.systemui/.SystemUIService
  NotifInterruptLog` prints SystemUI's verdict per notification (`FSI
  allowed: …`, `FSI suppressed: …`, `PEEK suppressed: …`); `dumpsys
  notification --noredact` shows each record's `flags=` (a force-grouped one
  carries `SILENT`).
- A screenshot of the PIN prompt is black. On the lock screen, an app above
  the keyguard shows a nav bar with no Recents button.
- **A locked phone gets the full-screen intent and no heads-up**
  (`PEEK suppressed: just launched FSI`), so "Snooze on the heads-up" is
  pressed from the shade there; and the agent's taps are not user activity,
  so after Stop the locked screen sleeps ten seconds later on its own
  (2026-10-10).
- **`qa boot --phone -d <attached serial>` boots nothing**: on an attached
  emulator it only sets `wm size 1080x2400` (360 × 800 dp); `qa unphone`
  puts the size back. That is how the alarm page's 360 dp cells were read on
  the 427 × 952 image when no phone-sized AVD was usable (2026-10-10).
- `cmd statusbar expand-notifications` / `collapse` open and close the
  shade when the one-swipe recipe below lands inside the app instead.
