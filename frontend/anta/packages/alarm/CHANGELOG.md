## ANTA fork of alarm 5.13.2 (2026-09-22)

Base: `alarm` 5.13.2 from pub.dev, copied verbatim into `packages/alarm/` and
referenced by path — the `re_editor` precedent: owned, upstream watched.
Cherry-picks from upstream are one-off decisions recorded in
`docs/event-alerts-os-integration-roadmap.md` (§2, B1/B3/B4; §13 for Patches
3 and 4) and, for Patches 5 to 9, in
`docs/alert-surfaces-redesign-roadmap.md` (D19 for 5 and 6; 7 came out of
that rework's review; 8 and 9 are findings of the same review that it left to
the owner, §8, decided on 2026-10-10). Nine patches. Seven are Android: six
live in Kotlin files the Pigeon-generated bindings never reference, one in
the library's manifest. Two are Dart: the seventh in
`lib/src/platform_timers.dart`, the ninth in `lib/alarm.dart`.

* **[Android] Patch 1 — alarm-clock scheduling.** `AlarmScheduler.setExactAlarm`
  arms the exact branch with
  `AlarmManager.setAlarmClock(AlarmClockInfo(triggerTimeMillis, showIntent), pendingIntent)`
  instead of `setExactAndAllowWhileIdle`, so an alarm is exempt from Doze and
  the standby buckets by the platform's own definition and is shown as the
  device's next alarm (status-bar icon, lock screen, Quick Settings,
  `AlarmManager.getNextAlarmClock()`). The show intent is the package's launch
  intent carrying the action `com.gdelataillade.alarm.action.SHOW`
  (`AlarmService.ACTION_SHOW`) and the alarm id under
  `AlarmService.EXTRA_ALARM_ID`; a package with no launch intent gets a null
  show intent, which `AlarmClockInfo` allows. The `canScheduleExactAlarms`
  guard, the `SecurityException` fallback and both inexact fallbacks are
  unchanged.
* **[Android] Patch 2 — content URIs.** `AudioService.playAudio` hands a
  `content://`, `android.resource://` or `file://` path to
  `MediaPlayer.setDataSource(context, Uri)` before the asset and path branches,
  so a sound picked from the phone's own list plays without being copied into
  the app's files first.
* **[Android] Patch 3 — a colorized ring notification (2026-10-04).**
  `NotificationHandler.buildNotification` calls `setColorized(true)` on the
  notification that carries the full-screen intent. Android 16 force-groups an
  app's loose notifications as soon as it holds two, flags every one it groups
  as silent, and refuses a silent notification its full-screen intent — so a
  ring posted while the app had anything else on the shade rang behind a dark
  screen with nothing launched. A colorized foreground-service notification is
  one of the three kinds that grouping leaves alone (the others are calls and
  media), and the ring is a foreground-service notification already. No test:
  the JVM-only suite cannot build a `Notification`.
* **[Android] Patch 4 — the trigger channel resolved per engine (2026-10-04).**
  `AlarmPlugin.alarmTriggerApi` was one static that every `onAttachedToEngine`
  overwrote and every detach nulled. `flutter_local_notifications` starts a
  second, headless engine for a notification action handled in the background
  and never destroys it, so from then on a ring, a stop and a host event were
  reported to an isolate that never called `Alarm.init()`. The channel is now
  resolved per call from the attached plugin instances — the one bound to an
  activity, else one that has been, else the oldest (`AlarmPlugin.presenterOf`,
  pinned by `AlarmPluginTest`).
* **[Android] Patch 5 — `AlarmReceiver` is not exported (2026-10-05).** The
  manifest declared it `android:exported="true"` with no permission, so any
  other app that knew an alarm's id could stop that alarm or snooze it. Every
  intent the receiver answers is the application's own — the `AlarmManager`
  entry `AlarmScheduler` arms, the Stop, Snooze and restore `PendingIntent`s on
  the ring notification, the in-process broadcast of an alarm due within five
  seconds — and a `PendingIntent` is sent as the application that made it, so
  none of them needs the receiver exported. `BootReceiver` is unchanged.
* **[Android] Patch 6 — the ring's wake lock is released (2026-10-05).**
  `AlarmService` took a five-minute `PARTIAL_WAKE_LOCK` into a local at every
  ring start and never released it: the CPU stayed awake for five minutes
  after a ring that was stopped at once, and each queued alarm promoted in its
  turn took another. `AlarmService.RingWakeLock` holds one at a time —
  released before the next is taken, when the last ring ends and in
  `onDestroy`, and never twice — with the five minutes kept as the upper bound
  (`RingWakeLockTest`).
* **[Dart] Patch 7 — the fallback timer does not announce a ring that is over
  (2026-10-05).** While the application is in front, `PlatformTimers` runs a
  timer beside every alarm: at the due time, if the platform has not reported
  the ring yet, it waits 700 ms and, when the alarm is not in `Alarm.ringing`
  at the end of them, announces the ring itself. An alarm the platform did
  report and that was stopped inside those 700 ms is not in that set either,
  so a Stop or a Snooze that quick was followed by a second announcement of
  the ring it had just ended: `Alarm.ringing` held an alarm that was silent,
  and `Alarm.scheduled` lost whatever a snooze had armed under the same id.
  `_alarmRang` now gives up when `Alarm.scheduled` no longer holds the very
  settings its timer was started with. `Alarm.alarmRang` takes an alarm out of
  that set as it puts it into the ringing one, and every stop takes it out of
  both, so only an alarm the platform never told of is still there when the
  wait ends — the case the fallback exists for, the alarm the host holds back
  while another one sounds included (`alarm_fallback_timer_test.dart`).
* **[Android] Patch 8 — the icon colour is packed without an API 26 call
  (2026-10-10).** `NotificationSettings.fromWire` built the ring notification's
  colour with `android.graphics.Color.argb(float, float, float, float)`, an
  overload Android added in API 26, while the plugin's `minSdk` is 19 and
  ANTA's 24: on Android 7.0 and 7.1 every `Alarm.set` that names an
  `iconColor` — every one ANTA makes — threw `NoSuchMethodError` on the
  platform thread and took the process down. `NotificationSettings.packArgb`
  now packs the four channels with that overload's own arithmetic (each scaled
  by 255 in floats, a half added, truncated), so API 26 and later get the very
  int they always got, and the file no longer touches `android.graphics.Color`.
  Packed there rather than handed to the `int` overload, which every level
  has, because the module's JVM tests run with `unitTests.returnDefaultValues`,
  under which any `Color` call answers 0 and nothing could pin the colour
  (`NotificationSettingsTest`).
* **[Dart] Patch 9 — an alarm held back behind a ring is not stopped at start
  (2026-10-10).** The host rings one alarm at a time: with `allowAlarmOverlap`
  off and `allowSameSecondScheduling` on, an alarm that comes due while another
  sounds is queued in `AlarmService` and rings when that one ends, and Dart is
  told nothing in between. An isolate started more than 30 s
  (`_ringStartGrace`) after the queued alarm's instant — the application
  started from the sounding alarm's heads-up — found it in `Alarm.init()`'s
  `checkAlarm` stored, past due and not ringing, and stopped it, which takes it
  out of the host's queue: it never rang. `_checkAlarm` now asks the host
  whether any alarm is ringing before it re-reads such an alarm and stops it,
  and while one is it leaves the alarm stored, where the ring the host reports
  later is looked up. A pass with nothing ringing still stops a dead alarm, and
  so does one whose host cannot answer (`alarm_check_test.dart`, through
  `FakeHost.anyRingingError`).

## 5.13.2
* **[Android] `Alarm.stopAll()` now reaches every actively ringing alarm (#437),** even after an earlier stop failure removed it from native storage.

## 5.13.1
* **[Android] A non-looping alarm is no longer reported as ringing after its sound has finished.** `Alarm.isRinging` said so until something stopped it, and a later alarm was queued or silently dropped as overlapping.

## 5.13.0
* **[Android] Fixed a crash when stopping an alarm with `volumeEnforced: true` (#437).** A second ring left the previous volume-enforcement runnable queued and uncancellable, killing the process on stop.
* [Android] A same-id `Alarm.set` no longer reports a stop to Flutter, which deleted the alarm it had just saved and left it armed with no Dart record.
* **[Android] `Alarm.stop()` now actually stops an alarm due within 5 seconds (#440).** Those are armed with an uncancellable timer, so one could ring after being stopped, or at its old time after being re-set.
* [Android] Volume enforcement no longer leaks into the next alarm, and the user's own volume is restored after overlapping alarms rather than a level a previous alarm forced (#444).
* **[Android] `volumeEnforced: true` now works without a `volume` (#438).** It pins the level read at ring start, so an alarm at the user's own volume can no longer be turned down mid-ring. A muted stream is left alone.

## 5.12.0
* **Deprecated `Alarm.snoozed` (#435).** Listen to `Alarm.events` and filter on `AlarmEventCause.snooze` instead: same deferrals, plus the `recordedAt` that `Alarm.acknowledgeEvent()` needs. No removal version.

## 5.11.0
* **[Android] An alarm whose time passed while the device was off is now discarded instead of ringing at boot (#418).** Reported on `Alarm.events` as an `AlarmDropped` with cause `staleAtBoot`.
* Added `AlarmSettings.androidStaleAfter`, the cutoff for that: 15 minutes by default, `null` never discards.
* Added `Alarm.acknowledgeEvent()` and `Alarm.init(acknowledgeEventsAutomatically: false)`, so an app can keep a host event until it has durably recorded it (#429).

## 5.10.0
* [Android] Fixed an alarm due within ~45s of a reboot never ringing (#424).
* Added `Alarm.events`, reporting deferrals and discards the host made on its own.
* **`Alarm.snoozed` is now buffered**, so listeners subscribing after `Alarm.init()` still get replayed deferrals.

## 5.9.0
* [Android] Fixed `Alarm.init()` cancelling an alarm that was due but had not started ringing yet, which silently lost the alarm. Past-due alarms are now left alone for 30 seconds before being stopped.
* [Android] A failed alarm arm is now reported to Flutter as an error instead of success, and no longer leaves an alarm stored that the platform never armed. **`Alarm.set()` now throws `AlarmException` where it previously returned `true`.** A failed re-arm after a reboot keeps the alarm stored instead, so a later `Alarm.init()` can retry it.
* [Android] `NotificationSettings.androidStopAlarmOnDismiss: false` now re-posts the notification while the alarm is still ringing, instead of letting the swipe remove the only on-screen control over a sounding alarm.

## 5.8.0
* [Android] Added `NotificationSettings.androidStopAlarmOnDismiss` to control whether swiping the notification away also stops the alarm. Enabled by default, matching the behavior added in 5.0.3.

## 5.7.1
* [Android] Fixed the lock screen asking for authentication before the alarm could be stopped: the keyguard is now only dismissed on devices without a PIN, pattern or password.

## 5.7.0
* [Android] Added a snooze action to the alarm notification, via `AlarmSettings.androidSnoozeDuration` and `NotificationSettings.androidSnoozeButton`. Snoozing defers the alarm rather than stopping it, and is reported on the new `Alarm.snoozed` stream as well as through `Alarm.scheduled`. A snooze taken with no Flutter engine running is applied on the next `Alarm.init()`.
* [Android] Alarms can now be presented on the app's own activity by declaring an intent filter for `com.gdelataillade.alarm.action.RING`, instead of always opening the launcher activity.
* Fixed `build_runner` being unable to regenerate `lib/model/*.g.dart`, which also removes the only `dart format` violation in the package.

## 5.6.0
* [Android] Added support for Android Gradle Plugin 9, while keeping AGP 8 compatibility.
* [Android] Fixed several alarm scheduling, foreground service, and audio playback crashes.
* [Android] Stop actions now dismiss the alarm notification when the alarm service is not running.
* [iOS] Fixed alarm timing precision, volume fades, and background refresh scheduling.
* [iOS] Migrated the example app from CocoaPods to Swift Package Manager.
* Fixed `AlarmSettings.copyWith` not clearing `payload`, and a debug-mode assert in `NotificationSettings.copyWith`; deprecated legacy `copyWith` parameters that were silently ignored.
* Fixed the v4 → v5 migration misparsing `fadeDuration`.
* Added a Dart unit test suite, now run in CI.

## 5.5.0
* [iOS] Added Swift Package Manager support.
* Added `AlarmSettings.allowSameSecondScheduling` to allow multiple alarms to ring in the same second.
* **Requires Flutter 3.41.0 or later.** Older Flutter projects will continue to resolve to 5.4.1.

## 5.4.1
* [Android] Added `AlarmSettings.preferConnectedAudioDevice` to route alarm audio through connected earphones or Bluetooth.
* [Android] Fixed `androidStopAlarmOnTermination` not persisting across app restarts.

## 5.4.0
* [Android] Added `VolumeSettings.showSystemUI` to suppress the system volume bar when the alarm sets or restores volume.

## 5.3.0
* [Android] Route alarm audio through the alarm volume stream so it responds to the alarm slider instead of media volume.

## 5.2.1
* [iOS] Added `NotificationSettings.keepNotificationAfterAlarmEnds` to control whether the notification should stay after alarm ends or not.

## 5.2.0
* Using device's default alarm sound when `assetAudioPath` is null.
* [Android] Added support for Android Gradle Plugin 8.

## 5.1.5
* [Android] Fixed stream not firing.

## 5.1.4
* [Android] Simplified plugin lifecycle.

## 5.1.3
* [Android] Added `androidStopAlarmOnTermination` parameter.
* [Android] Improved [installation steps](https://github.com/gdelataillade/alarm/blob/main/help/INSTALL-ANDROID.md).

## 5.1.2
* Updated `AlarmSettings.assetAudioPath` documentation.

## 5.1.1
* [Android] Added icon color parameter for notification.

## 5.1.0
* [iOS] Added native refactoring to fix alarm that didn't ring.
* [Android] Fixed imports.

## 5.0.3
* Added CodeCanvas diagram to documentation (see [here](https://www.code-canvas.com/?session=unauthenticatedGithub&repo=alarm&owner=gdelataillade&branch=main)).
* [Android] Added alarm stop on notification dismiss.

## 5.0.2
* [Android] Improved stop alarm process.

## 5.0.1
* Updated README.

## 5.0.0
**💥 Breaking Changes**
**🔧 Android installation steps were updated [here](https://github.com/gdelataillade/alarm/blob/main/help/INSTALL-ANDROID.md).**
* Some API parameters have been renamed.
* Fixed multiple minor bugs.

## 5.0.0-dev.11
* Added payload parameter.
* Updated dependencies.
* Improved alarm events streams.
* Fixed duplicated alarms issue.

## 5.0.0-dev.10
* Fixed backward compatibility for v4 Dart JSON structures.

## 5.0.0-dev.9
* Fixed backward compatibility for v4 Dart JSON structures.

## 5.0.0-dev.8
* Added debug logs to understand why backward compatibility fails.

## 5.0.0-dev.7
* [Android] Fixed collition between package and FCM.

## 5.0.0-dev.6
* Updated README.

## 5.0.0-dev.5
* [iOS] Added `iOSBackgroundAudio` parameter to disable background silent audio player, which is not necessary if your app already has a background process that keeps app active in the background.

## 5.0.0-dev.4
* Added backward compatibility with package versions below 5.

## 5.0.0-dev.3
* [Android] Fixed build error & downgrade datastore.

## 5.0.0-dev.2
* Handles `stopAll` on the platform side for improved reliability.

## 5.0.0-dev.1
**💥 Breaking Changes**
* Old alarms (alarms created pre v5) will be deleted and some API parameters have been renamed, this update requires a small amount of refactoring for users. No features have been removed.
* Added support for fading the alarm volume using a staircase function.
* Fixed a bug where `isRinging` might return FALSE immediately after alarm starts to ring.
* Handled alarm events on the platform side, increasing efficiency.

## 4.1.1
* [Android] Show app on lock screen when alarm rings.

## 4.1.0
* Migrated to Pigeon.

## 4.0.12
* [iOS] Fixed `isRinging` method for specific `id`.

## 4.0.11
* [iOS] Fixed `isRinging` method.

## 4.0.10
* [Android] Fixed `androidFullScreenIntent` parameter.

## 4.0.9
* Added new alarm parameter `volumeEnforced`.
* [iOS] Reopen killed app when tap on notification stop button.

## 4.0.8
* Fixed and improved isRinging method.
* [iOS] Add support for longer volume fade durations.
* [iOS] Dismiss notification on alarm stop.

## 4.0.7
* [iOS] Added iOS notification category handling.
* [iOS] Fixed handleMethodCall cast error in IOSAlarm.

## 4.0.6
* [iOS] Fixed vibration interruption during overlapping alarms.

## 4.0.5
* [Android] Fixed crash when incoming alarm is ignored.

## 4.0.4
* [Android] Fixed crash on older Android versions.

## 4.0.3
* [Android] Fixed error when rescheduling old version alarm after reboot.

## 4.0.2
* [iOS] Improve thread safety.
* [Android] Add native backward compatibility with older versions.

## 4.0.1
* [iOS] Fixed crash on iOS when setting warning notification on kill.

## 4.0.0
**💥 Breaking Changes**
* Added notification action stop button.
* Refactored `AlarmSettings` model.
* Ignore oncoming alarm if another alarm is ringing.
* [Android] Updated kotlin version to `1.8.0`.
* [Android] Added customizable notification icon.
* [Android] Reschedule alarms after device reboot.
* [iOS] Removed notification permission request. Must be handled in-app to match Android behaviour.

## 4.0.0-dev.5
**💥 Breaking Changes**
* [iOS] Removed notification permission request. Must be handled in-app to match Android behaviour.

## 4.0.0-dev.4
* [Android] Reschedule alarms after device reboot.

## 4.0.0-dev.3
**💥 Breaking Changes**
* Refactored `AlarmSettings` model.
* Ignore oncoming alarm if another alarm is ringing.
* [Android] Add customizable notification icon.
* [Android] Update kotlin version to `1.8.0`.

## 4.0.0-dev.2
* [Android] Fix native GSON parsing error.
* Update `flutter_fgbg` dependency.

## 4.0.0-dev.1
* Add notification action stop button.

## 3.1.7
* [Android] Update kotlin version to `1.7.10`.

## 3.1.6
* Update `flutter_fgbg` dependency to `0.6.0`.
* Update `shared_preferences` dependency to `2.3.2`.

## 3.1.5
* [Android] Fix volume/focus post-alarm.
* Export `AlarmSettings` class in `Alarm` class.

## 3.1.4
* [Android] Add more type safety.

## 3.1.3
**🔧 Android installation steps were updated [here](https://github.com/gdelataillade/alarm/blob/main/help/INSTALL-ANDROID.md).**
* [Android] Remove notification large icon.

## 3.1.2
* [Android] Fix alarm stop on app open.

## 3.1.1
* [Android] Fix notifications icon for some OEM.

## 3.1.0
* [Android] Fix ring stream issue.
* [Android] Increment compileSdkVersion to 34.
* [Android] Update installation steps & documentation.

## 3.0.14
* [Android] Update PendingIntent flags in AlarmReceiver.

## 3.0.13
* [iOS] Fix EXC_BAD_ACCESS errors.
* [Android] Improve error handling.
* Improve Dart code quality: apply [very_good_analysis](https://pub.dev/packages/very_good_analysis) lint rules.
* Add minor updates in documentation.

## 3.0.12
* [Android] Fix BackgroundServiceStartNotAllowedException.
* [Android] Fix alarm ring on app launch.

## 3.0.11
* Improve alarm reschedule on init.

## 3.0.10
* [Android] Add relative audio path support.

## 3.0.9
* [iOS] Add concurrency handling.
* [iOS] Make iOS notification show in foreground.

## 3.0.8
* Fix alarm id verification.

## 3.0.7
* Prevent if integer overflow.
* [Android] Improve error handling. Add exceptions with better messages.
* [iOS] Add support for subfolder local audio path.

## 3.0.6
* [Android] Add notification large icon.
* [Android] Add Gradle 8 support.
* [Android] Fix delay integer overflow when delay is more than a month.

## 3.0.5
* Keep notification when audio's over.

## 3.0.4
* [Android] Add `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission.
* [Android] Fix vibrations for versions below API 26.

## 3.0.3
* [Android] Fix errors with specific Android versions.
* Call `stopAlarm` when `loopAudio` is false and audio ends.

## 3.0.2
* [Android] Fix local audio file playback. Add `READ_EXTERNAL_STORAGE` permission in the manifest and request it at runtime to prevent access errors.

## 3.0.1
* Only override an existing alarm if it's scheduled for the identical second.

## 3.0.0
**💥 Breaking Changes**
**🔧 Android installation steps were updated [here](https://github.com/gdelataillade/alarm/blob/main/help/INSTALL-ANDROID.md).**
* [Android] Alarm will work even if app was killed.
* [Android] Notification are now mandatory so foreground services can be used.
* [iOS] Notifications are now native. `flutter_local_notifications` dependency was removed.
* Remove [stopOnNotificationOpen] property.
* Replace [volumeMax] with [volume] double property.

## 3.0.0-dev.8
* [Android] Fix notification delay for Android 12 and above.
* [Android] Abandon audio focus + stop vibrating when loopAudio is false and audio is over.

## 3.0.0-dev.7
* [Android] Fix notification delay and sound.

## 3.0.0-dev.6
* [Android] Fix alarms for Android API 31 and above.
* [iOS] Fix audio player fade duration.
* [iOS] Fix on-app-kill notification.

## 3.0.0-dev.5
* Improve README and installation guides.
* [iOS] Add more error handling.
* [Android] Fix alarm for Android 12 and above.

## 3.0.0-dev.4
* [iOS] Remove notification sound.
* Throw exception if alarm settings are invalid.
* Improve README.

## 3.0.0-dev.3
* Update README.
* Add minor improvements.

## 3.0.0-dev.2
* [iOS] Make native iOS notifications to remove `flutter_local_notifications` dependency.

## 3.0.0-dev.1
**💥 Breaking Changes**
**🔧 Android installation steps were updated [here](https://github.com/gdelataillade/alarm/blob/main/help/INSTALL-ANDROID.md).**
* Remove [stopOnNotificationOpen] property.
* Make notification mandatory so android foreground services can be used.
* [Android] Refactor alarm to native android services.
* Replace [volumeMax] with [volume] double property.

## 2.2.0
* [Android] Move alarm service to native code.

## 2.1.1
* Fix `AlarmSettings.fromJson` method with missing [androidFullScreenIntent].

## 2.1.0
**🔧 Android installation steps were updated [here](https://github.com/gdelataillade/alarm/blob/main/help/INSTALL-ANDROID.md).**
* [Android] Add parameter [androidFullScreenIntent] that turns screen on when alarm notification is triggered.
* [Android] Fix 'ring now' alarm delay.
* [Android] Fix fadeDuration cast error.
* Disable [stopOnNotificationOpen] by default.

## 2.0.1
* Update README.
* Fix example app's ring now button.
* Refactor set alarm methods.

## 2.0.0
**💥 Breaking Changes**
* Installation steps were updated in the README. Please make sure to follow them.
* [iOS] Add Background Fetch to periodically make sure alarms are still active in the background.

## 2.0.0-release-candidate-1
* Add minor improvements.

## 2.0.0-dev.5
* [iOS] Move background fetch to native.
* [Android] Fix build errors.

## 2.0.0-dev.4
* [iOS] Improve background fetch & audio interruptions

## 2.0.0-dev.3
* [iOS] Improve alarm reliability.

## 2.0.0-dev.2
* [iOS] Improve silent audio interruption handling.
* Add a shortcut button in example app.

## 2.0.0-dev.1
* [iOS] Play silent audio until alarm rings to keep app active.
* [iOS] Add Background Fetch to periodically check if app is still active.
* [iOS] Add new installation steps.

## 1.2.2
* Upgrade plugin's dependencies.
* Prove plugin ownership for winning OnePub competition: 961eace7-3bbb-11ee-ade6-42010ab60008

## 1.2.1
* Fix fromJson error on plugin init.

## 1.2.0
* Add [volumeMax] parameter.
* [iOS] Keep app active in background by playing silent sound in a loop.

## 1.1.8
* [Android] Add missing isRinging method.

## 1.1.7
* [iOS] Fix alarm stop.

## 1.1.6
* Improve error handling and coding style.

## 1.1.5
* [Android] Fix null isolate SendPort error on stop.

## 1.1.4
* Add Flutter audio asset import from Swift. It's no longer needed to import your assets in Xcode too.

## 1.1.3
* Remove unecessary exception on init.

## 1.1.2
* Fix notification schedule date.

## 1.1.1
* Update plugin's dependencies.
* Increment Android minimum version to API 19 (4.4).

## 1.1.0
* Add support for downloaded audio local files.
* Remove support for network audio files, which was unstable.

## 1.0.5
* Update plugin's dependencies.

## 1.0.4
* Add a FAQ item in README

## 1.0.3
* Add optional [stopOnNotificationOpen] parameter to stop alarm when notification is opened.

## 1.0.2
* Add `getAlarm(id)` method.
* [Android] Fix isolate unfound port error.

## 1.0.1
* [iOS] Fix alarm sound from background mode.

## 1.0.0
* Alarm plugin is now ready for production. Breaking changes will be released in major version releases from now.
* Add some minor improvements.
* Update README.md

## 0.2.9
* Add custom debug print method.

## 0.2.8
* [iOS] Prevent unnecessary callbacks when alarm is stopped.

## 0.2.7
* If [loopAudio] is set to false, stop vibrations when audio ends.
* [iOS] Avoid crash if provided audio url is wrong.

## 0.2.6
* [Android] Fix vibrations which were triggered even when disabled.

## 0.2.5
* [iOS] Fix vibrations: cancel callback if alarm is stopped.

## 0.2.4
* Fix zoned notification schedule date shift

## 0.2.3
* [Android] Fix [NotificationOnKillService] for API 31+

## 0.2.2
* Improve documentation.
* Add [showDebugLogs] optional parameter to [Alarm.init] method.

## 0.2.1
* Add optional [vibrate] parameter, to toggle vibrations when alarm rings.

## 0.2.0
* **💥 Breaking changes**: Add multiple alarm management. Now, you have to provide a unique [id] to [AlarmSettings].
* Update example application.
* [Android] Fix potential delay between notification and alarm sound.

## 0.1.5
* Schedule notification with precision to the given second.

## 0.1.4
* [Android] Fix notification permission for Android 13.

## 0.1.3
* Add optional [fadeDuration] parameter, which is the duration, in seconds, over which to fade the alarm volume.

## 0.1.2
* Add more Android installation steps in the README.
* Add alarm behaviour details in the README.
* [Android] Fix alarm while screen is locked.

## 0.1.1
* Add [Alarm.hasAlarm] method.
* Fix: cancel on-application-kill notification warning when alarm starts ringing, instead of when user stops alarm. 
* Export [AlarmSettings] model in [Alarm] service so it's not necessary to import it separately anymore.

## 0.1.0
* **💥 Breaking changes**: [Alarm.set] method now takes a [AlarmSettings] as only parameter.
* **💥 Breaking changes**: You will have to create a `StreamSubscription` attached to [Alarm.ringStream.stream] in order to listen to the alarm ringing state now. This way, even if your app was previously killed, your custom callback can still be triggered.
* By default, if an alarm was set and the app is killed, a notification will be shown to warn
the user that the alarm may not ring, with the possibility to reopen the app and automatically reschedule the alarm.
To disable this feature, you can call the method [Alarm.toggleNotificationOnAppKill(false)].
* Add notification on kill notification switch button in example app.
* Add some minor fixes and improvements.

## 0.0.5
* Add [a Gist](https://gist.github.com/gdelataillade/68834caacdd6727f1418e46788f70b53) in the README.md to explain how to import assets on Xcode without adding weight to your app.

## 0.0.4
* [Android] Fix notification parameters.

## 0.0.3
* Add more documentation.
* Add plugin description in pubspec.yaml.
* Refactor some Swift code.

## 0.0.2
* Update links in the README.md.

## 0.0.1
* Initial development release.
