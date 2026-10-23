# Alerts pass

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

## The alerts pass (2026-10-05)

The alarm page and the alert notifications have a device pass of their own
(design record `docs/alert-surfaces-redesign-roadmap.md`), on fixtures whose
events ring **minutes after the seed is resolved**:

```bash
./tool/qa/qa pass alerts -d emulator-5556        # since 2026-10-23: the seed goes in once (reseed=suite), the five flows run in order on one device (shard=no), about five minutes, one report
./tool/qa/qa pass alerts_pair -d emulator-5556   # one flow, about two minutes
./tool/qa/qa pass alerts --only 00_test_alarm -d emulator-5556   # the one flow that rings within seconds

./tool/qa/qa relaunch --fresh --seed tool/qa/fixtures/alerts.json   # the hand-driven way, then `flows alerts`
```

The suites' `_suite.txt` say `reseed=suite` and `shard=no` because the
fixtures' events sit minutes ahead of the one seed and the flows consume
them in order; `fleet pass alerts` therefore runs on its first device only
and says so. Never interrupt the wait for a ring.

- **`alerts.json`** seeds three events with `{{minute+N}}` /
  `{{minuteday+N}}`, the upcoming notice off (`alert_notice_lead_minutes`
  0) and Snooze at five minutes: "Leg day" at +3 (an Alarm-tier alert at its
  start, an end time, a description, a linked note), "Tea timer" at +5 (an
  alarm with "remove after it rings") and "Stretch" at +7 (a Reminder-tier
  alert, which the flows leave armed for a look at the shade by hand).
  `test/qa/alerts_fixture_test.dart` pins it. Its flows: `00_test_alarm`
  (Calendar settings' test ring: the page read by its ids, Stop),
  `01_event_alarm` (Leg day's ring, read and stopped) and `02_remove_after`
  (Tea timer: the remove row, Keep, Stop, then the calendar's row no longer
  saying "removed after it rings").
- **`alerts_pair.json`** seeds two Alarm-tier events on the same minute
  (+2). The plugin sounds one and holds the other, the app pushes a page for
  each within a second — the held alarm's on top — and
  `alerts_pair/00_two_in_a_minute` stops them one after the other — both
  Stops land on the page in front; that a page closes its own route from
  underneath is the page suite's to show ("closing its own route").
  `test/qa/alerts_pair_fixture_test.dart` pins the fixture.
- **The seed goes in with `relaunch`, never with `run`.** `run` resolves the
  fixture's minutes and then builds, so the build comes out of the lead: the
  first alarm rings inside flow 00, or is already in the past when the app
  imports it, where nothing is armed and flow 01 has nothing to wait for.
  After a `lib/` change it is two commands — a plain `qa run`, then `qa
  relaunch --fresh --seed …` — with the flows straight after.
- Add `--setting alert_notice_lead_minutes=1` to the relaunch to see the
  upcoming notice; the fixtures keep it off so nothing but the rings is on
  the shade. On the Windows emulator run the pass with `ANTA_QA_VIA=agent`.
- **Targets**: the page's `alarm-stop`, `alarm-snooze`, `alarm-open-event`
  (`alarm-open-database` while the Open row is the switch to another
  database), `alarm-keep-event`, and `alarm-body`, its scroll region — a
  reversed scroll hides its start, so `scroll-to --up --in id:alarm-body`
  brings the time back on a short screen; Calendar settings' test ring is
  `alerts-test-alarm`. Two stacked pages both carry `alarm-stop`, so nothing
  can be waited for between their two Stops: the pair flow pauses instead.
- A flow's `shot` is adb's: with ANTA in front and unlocked it shows the
  ring's heads-up over the page, and flows 00 and 01 wait 3.5 s before theirs
  (`key back --settle 3500`, a verb the page swallows) so the page is on
  screen. When done, press Done on the session chip flow 02 leaves standing
  (the kept "Tea timer" has no end, so nothing else clears it), then re-seed
  `basic.json` with `relaunch --fresh --seed tool/qa/fixtures/basic.json`:
  the first reconcile over the fresh database cancels whatever the alerts
  seed left armed (the force-stop alone does not — the plugins re-arm what
  they stored at the next launch).

Seven things the rework's device work had to find out:

- **A VM-service `evaluate` needs `qa attach` after a bare `relaunch`**
  ("No compilation service available" otherwise): `flutter attach` brings
  the compiler. That is how a call the UI cannot make is staged —
  `getIt<AlertGateway>().cancel(<os id>)` while the id rings.
- **`adb shell cmd package query-receivers -n <component>`** is the
  read-only call that prints a receiver's `exported=`; `dumpsys package`
  lists only receivers with intent filters on this image.
- **`dumpsys power` has a "Partial Wakelock Log"** with an `ACQ` and a `REL`
  line per lock, time-stamped to the millisecond — better evidence of a
  wake lock's life than one reading of `Wake Locks: size=`.
- **`adb logcat -b events -d | grep notification_alert`** says, per
  notification key, whether it buzzed or beeped (the two numbers after the
  key), and `dumpsys notification`'s `Notification attention state` names
  the record that last did. **Read both before the shade is opened** —
  opening it clears the attention state.
- **With the alarm page in front, the native dump lists the page's own Stop
  and Snooze under the same labels as the heads-up's.** Press the heads-up's
  buttons by raw coordinates read off a screenshot; the app's log (`qa log
  --all`: `AlarmReceiver: Received snooze alarm command`) is what proves
  which one was hit.
- **`qa flows calendar` on the 952 dp emulator**: `19_fasting_schedule` fails
  at step 17 with its sheet still open, and `20`–`22` then fail at their first
  step in the same run — run them again from a fresh calendar.
- **The fork's own Dart suite** runs with `cd packages/alarm && flutter test`,
  one run at a time, like the app's.

## Category alerts and digests (2026-10-15)

2026-10-15 — category alerts and digests: `tool/qa/fixtures/alerts.json` seeds a yearly birthday "Ana" two days out, a Birthday category alert (the day before at 09:00, Reminder — Ana inherits it, so it fires tomorrow at 09:00), a monthly digest (Birthday, the 1st, 09:00, also when empty — on most days its notification reads "No events this month") and a daily digest "Next days" whose fire is `{{minute+9}}` after the relaunch with a two-day lead, so it lists Ana and lands on the shade nine minutes into the pass; `test/qa/alerts_fixture_test.dart` pins all four. Flows `tool/qa/flows/alerts/03_category_alerts.txt` (the category editor's Alerts group, the alert sheet's two When rows, the hub's inherited row, the event editor's inherited row and switch) and `04_digests.txt` (the hub's Digests group, the sheet, the cadence round trip, the fire rows); 04's header carries the ring sequence the runner does by hand — wait for the "Next days" fire, open the shade, screenshot the inbox notification, tap it by `#N`, expect the overview's list on the span with Birthday. There is no `qa fire` / `qa alerts` verb (Session 7 of `docs/event-alerts-roadmap.md` was never built); the timed daily digest stands in for it.
