# Alert Surfaces Redesign — the ring screen and the alert notifications (2026-10-04)

**Status: IMPLEMENTED 2026-10-10, uncommitted — the close of the rework COMMITTED `3cb8d49` (2026-10-05, Slices 0 to 6a and the fix batches), on disk on top of `0c65424`: the rest of batch B (C32, the token at `~g4`), the three items the review had left to the owner (Patches 8 and 9, the de/ro channel names — C33 to C36), the final review's eleven fixes (C37 to C42 and the fix review's round), the final device pass of Slice 6 and the documents. Nothing of §8's "Deferred on 2026-10-05" remains; what is still owed is the device list under its device-pass entry and the quiet channel's importance to confirm (D20). The owner asked for the commit and the fast-forward merge into `main` at the end of the session; the ledger's last row records them.**

A detour from the calendar tiers, asked for by the owner on 2026-10-04: the
full-screen alarm page and everything the phone shows when an alert comes —
the ring heads-up, the reminder and its snoozed re-post, the upcoming notice,
the Missed notice, the session chip — plus the blank lock-screen cover, so it
matches. Settings pages, the Alerts hub, the alert / sound / offset sheets,
the quick-alarm sheet, the badges and the two Undo snackbars are out of scope.

This record settles open decision 7 of
[ui-language-adoption-roadmap.md](ui-language-adoption-roadmap.md) ("the
full-screen alarm — a ring screen is not a form"). Line numbers are as of
`a0a82ba` and will drift — re-grep before editing.

## 0. How to run this

- **Skills:** `anta-context`, `ui-language`, `ui-revamp`, `calendar-events`,
  `calendar-ui`, `l10n`, `verify`, `qa-emulator`.
- **Models:** Opus for design, implementation and review, Sonnet for
  mechanical runs. The "never Fable" of 2026-10-04 was a usage limit, lifted
  by the owner on 2026-10-10: since then Fable leads and reads the final
  review's lenses.
- **One implementer per slice, in order**, briefed "load the skills, read
  this record whole, do slice N, run the gate, report what the record got
  wrong". The lead corrects the record between slices. Reviewers are
  read-only: they write nothing into the tree, not even a probe test.
- **The gate, after every slice:** `dart analyze lib test tool test_driver`
  clean; the whole `flutter test`, one run, after `tool/qa/qa kill-run` (the
  one accepted failure is `test/qa/host_devices_test.dart`, the macOS
  product-name case); `flutter gen-l10n` and `untranslated.txt` `{}` when an
  ARB changed; §4.1 re-read against the diff. After fork Kotlin:
  `cd android && ./gradlew :alarm:testDebugUnitTest` (`AlarmStorageTest` and
  `BootReceiverTest` fail on this Windows machine with or without changes).
  After the fork's Dart: `dart analyze packages/alarm/lib` and
  `cd packages/alarm && flutter test` (its own suite; the app's `flutter test`
  never reaches it).
- **The device:** `ANTA_QA_VIA=agent`. After a `lib/` change `qa run` first,
  then **`qa relaunch --fresh --seed tool/qa/fixtures/alerts.json`** and
  `qa flows alerts` back to back. The seed goes in with `relaunch`, never
  with `run`: `run` resolves the fixture's minutes before it builds, and a
  build that outlasts the lead leaves the first alarm in the past.
- **The widget-test font is about twice Roboto's width** and the suites load
  no other. A claim about a label fitting on one line is the emulator's to
  show, never the matrix's.
- Anything about the keyguard, the activity lifecycle or notification policy
  is **seen on the emulator, never predicted** (`qa-emulator`, "A ring on a
  locked phone").
- **`pubspec.lock` does not resolve as committed on the Windows machine**
  (its Flutter pins older `intl`, `meta`, `matcher`, `test_api` and
  `vector_math`): a `flutter pub get` there rewrites five entries. Do not run
  one unless `pubspec.yaml` changed, and put those entries back afterwards so
  the lock's diff is the intended line.
- **Do not commit.** The owner reviews and commits — on 2026-10-10 they asked
  the lead to make the one commit after the final gate, the docs commit and
  the fast-forward merge into `main`, as the ledger records.

## 1. Why

What ships at `a0a82ba`, with the evidence.

**The alarm page** (`lib/pages/alarm_page.dart`).

- It is a non-scrolling `Column` with a `Spacer`. In the widget-test font it
  overflows on 360 × 780 in the plain state at text scale 2.0 in all three
  locales, and in the fullest state from 1.3 (Slice 0's probe).
- **Android draws the ring notification as a sticky heads-up over the page
  when ANTA is in front and unlocked.** It covers about 60–195 dp from the
  top of a 427 × 952 dp screen — the eyebrow, the time and the date
  (`build/qa/shots/20261004_204641_02_before_test_dark.png`). The page cannot
  remove it: it is the foreground service's notification.
- Keep sits below the `Spacer` and disappears when pressed, so Stop, Snooze
  and Open event move down by one button under the finger; the database chip
  arrives after the first frame and shifts the captions.
- `_close()` pops the navigator's **top** route. When two alarms are due in
  the same minute the service sounds one and holds the other, and the
  plugin's own Dart timer announces the held one about 0.8 s later — so two
  pages stack at once, the held alarm's on top. When the lower page closes
  first (Stop on the heads-up, which names the sounding alarm), its close
  removes the upper one — leaving a dead page with Stop and Snooze inert and
  back disabled. The same pop takes the restart dialog instead of the page.
  Both were pinned as defects in `test/widgets/alarm_page_test.dart` and
  staged on the emulator in Slice 2.
- The page reads the generic `AppSpacing` scale nine times and carries seven
  literals; its ground is `surface`, which is the *group* tone in light; it
  hand-rolls a 48 dp avatar beside the shared `EventAvatar`.
- It declares no system-bar style: after Calendar settings its status-bar
  icons are white on the light ground, and under the dark theme the
  navigation bar is a light band.
- A ringing test alarm is titled "Test alarm in 10 s", the settings button's
  label. The time is always 24-hour, whatever the phone says, and for an
  alert "10 minutes before" it is the minute the alert fired above the day of
  the event.
- Another database's alarm that is set to "remove after it rings" says the
  event will be removed and offers Keep; neither can happen there.
- "Kept" is drawn before the write has happened, and after Keep the calendar
  still shows the event as "removed after it rings" until a relaunch.

**The notifications** (`lib/services/android_alert_gateway.dart`,
`SessionChip.kt`, the fork's `NotificationService.kt`).

- Three title grammars: event then time (ring, reminder); "Alarm at {time}"
  then the event (upcoming notice); "Missed: {title}" then a sentence.
- The text is the minute the notification fired — which the header already
  shows — never the event's own time: a "10 min before" reminder for an
  18:00 event reads "17:50".
- Expanding a reminder replaces the time with the description's first line.
- The upcoming notice and the snoozed re-post carry no colour and no icon;
  the large icon is a fixed 64 px bitmap.
- The snoozed re-post is in the device's language, not the app's.
- The Missed notice asks for low importance on a channel whose importance is
  frozen at high, so it is not the quiet notice the record describes.
- On Android 16 a reminder posted while a session chip or an upcoming notice
  stands is force-grouped, flagged silent and does not peek (seen again in
  Slice 0: flag `SILENT` under an `Aggregate_AlertingSection` summary).
- No test pins a single title, text or action of any notification: the
  gateway cannot be constructed in a test.

## 2. Decisions

**Delegated.** The owner asked for the redesign without being shown options
("don't show me all possible ways, this time you can not show me anything and
just revamp them", 2026-10-04), so every decision below is the lead's, taken
after three independent proposals (one optimised for a half-asleep person
with one thumb, one for the UI language, one for truth in every state) were
judged by three reviewers (the person at ring time, the language and the
copy, the engineer against the code). Where the judges disagreed the row says
which way it went and why. The record itself was then checked against the
tree by two more reviewers before any slice was built from it.

| # | Decision | Why |
| --- | --- | --- |
| D1 | **The ring screen is the language's fourth idiom: a takeover page.** A full-bleed page on `pageGround`: one large time, one read-only row group that names the event as the detail sheet names it, and a pinned pair of buttons. It reads the language's tokens and row kit; it has no sheet chrome, no app bar, no chevrons and no form controls. Its few own numbers live in `AlarmMetrics`, as the bars' live in `AppBarMetrics`. | "A ring screen is not a form" (both masters), and it is not a list or a settings page either. One judge wanted the numbers in `FormMetrics`; they are not a form's, and `FormMetrics` is "every number a form uses". |
| D2 | **Everything that matters sits low.** A pinned dock (Stop over Snooze) under the event card under the time; the content is bottom-anchored in a reversed scroll view, so short content rests on the dock and tall content loses its top first. No reserved band and no lock-state input. | The top is where Android draws its heads-up and where a thumb does not reach. All three judges; a measured 144 dp band was rejected because it comes from one emulator at one font scale and overflows a short window. |
| D3 | **The time is a display numeral above the card**, 64 px, unscaled and fitted, in the phone's 12/24-hour style: the instant this ring was due. Under it the alarm's own day. Above it an eyebrow that names the route. | Read first, at arm's length (two judges). The language judge preferred the form's 40 px hero row inside the card; a ring screen's clock is the one place a display numeral belongs, and the page already had one. |
| D4 | **The event is one row group**: the detail sheet's title row, hoisted into the kit at its own 20 / 500 as `FormReadTitleRow(leading:, title:, caption:)` with a nullable caption — here the event's own time; the description's first line under it; the Open row last. | Same event, same drawing as the detail sheet; the hoist gives the kit a row the sheet kept private. A 24 px title was turned down: it would be a second size for the same row. |
| D5 | **"Remove after it rings" is a row pinned directly above Stop**, with a one-way Keep that stays in place, disabled, once pressed. The claim and Keep are drawn only once the open database is known to be the alarm's — one frame after the page in practice — and never for another database's alarm; "kept" is drawn when the write has returned. | The fact changes what Stop does, so it sits beside Stop. A two-way switch (the language judge's choice) was turned down: a second brush would re-arm a deletion that has no visible Undo on a locked phone, and it changes what `alarm-keep-event` does. |
| D6 | **Open event is a labelled row at the end of the card**, off the bottom edge. For another database's alarm the same row reads "Switch to {name}" under its own id; the flow behind it is today's, with a dialog that says what happened. The chip goes. | Open event stops the ring and may delete the event: it must not be the last thing a grabbing hand lands on. The switch takes a slot that is dead for those alarms anyway. A confirm-first dialog (one judge) and a stop-first flow (one proposal) were turned down: that state cannot be staged on the QA build, so its flow does not change. |
| D7 | **The dock: Stop filled, 64 dp, over Snooze tonal, 56 dp, Snooze on the bottom edge.** Labels 20 and 17 px, text scale clamped at 1.4 inside the dock. No outlined button. | A stray grab on the edge costs ten minutes, not an event. One learned order, the notification's. The clamp keeps both labels on one line in German at 200 % on a 360-wide phone; 1.4 is the time pad's precedent. |
| D8 | **The page and the lock-screen cover share one ground**: `pageGround` under one `AnnotatedRegion` that makes both system bars transparent with icons by theme. The cover draws nothing else. | No tone step from cover to page to cover; legible status icons whatever page was underneath; no light band under the dark page. Scoped to these two widgets — the app-wide bar decision stays open. |
| D9 | **The page closes its own route**: `pop` when it is on top, `removeRoute` otherwise. | Fixes the dead page of two same-minute alarms and the popped restart dialog. `removeRoute` completes the route's future, which `main.dart` drains held intents from. |
| D10 | **One notification grammar.** The title is the event's title, always. The text is `{kind} · {time}`: the kind in the words the hub already uses, the time the event's own for an alert that is firing (ring, reminder, snoozed) and the alarm's own for an alarm that is ahead or was missed. Expanding adds the description's first line under the text and never replaces it. No sub text. | Title and text are the only two lines every presentation draws; a kind named only in the header is cut exactly where it is needed (two judges checked the platform's top-line view). The hub's words give correct German and Romanian for free. |
| D11 | **A time is written as the phone writes it, in the app's language, once, when the entry is armed, on the UI isolate.** The background isolate concatenates strings and formats nothing. | The isolate has no date symbols loaded and no database; a throw there loses a snooze. A language or 12/24 change re-arms planned entries through the arm token. |
| D12 | **The event's colour and avatar on every kind but the ring**, the avatar drawn on `EventAvatar`'s own proportions at the screen's density and handed over as a file, so the snoozed re-post and the chip keep it. The ring stays colour only. | Today only two kinds have decor, at 64 px. The ring is colorized: the avatar's tinted disc on its own tint would not show. |
| D13 | **The action that settles comes first**: Stop · Snooze N min; Done · Snooze N min; Skip · Open; Done · Open note (Open event when no note is linked). A reminder's Snooze names its length. | One order everywhere, the ring notification's. |
| D14 | **Missed is really quiet** (`silent`), dated by the alarm it reports. | It is what the record always called it. |
| D15 | **The payload gains optional facts** (§3.6): the due instant, the event's time as a stamped line, the resolved tint and glyph, the language, the icon file, a re-ring mark. Absence decodes to today's behaviour, for good: another database's entries and standing snoozes are never re-armed. | A page and an isolate that may read only the payload need the payload to say it. A stamped line was chosen over start / end minutes so that nothing has to format in the isolate. |
| D16 | **"Snoozed" is said only where it is known**: on the page's eyebrow, for a snooze taken on the page, and for one taken on the notification when this process saw the plugin's snooze move. It is never claimed from `payload.snooze` alone (true for every test alarm), never from a moved time alone (the platform defers rings too), and never on the ring notification (the fork re-arms it unchanged). | It may be absent; it is never false. The engineer judge would have dropped it; the other two kept it on that condition. |
| D17 | **Grouping is its own, last, gated slice**: one group for the kinds that must interrupt (reminder, snoozed re-post, the dormant fallback) with one silent summary; the quiet kinds and the ring stay outside. It ships only if the emulator shows the readings of §3.7. Nothing else depends on it. | The cure the OS roadmap names, on framework rules nobody can read here. "One tiny group per notification" was turned down: it doubles every pending schedule on a remembered threshold. |
| D18 | **No fork patch for looks, no second small icon, no standing "Snoozed" notification, no countdown on the chip, no spinner.** | Each is a new mechanism for a gain the page or the text line already gives; a spinner is a perpetual animation (§4.1). |
| D19 | **The debt of OS roadmap §13.3 is Slice 5**: `cancel`'s ring maps, the exported receiver, the wake lock, the fork's CHANGELOG, stale comments. The plugin's log output lands in Slice 1, so every device pass can see a dropped ring. Three items stay with the owner: what unlocking after Stop should land on, API 24–26 (a fallback nobody can verify here, or `minSdk` 27), and `Alarm.init()`'s re-arm (the only recovery after a force stop). | The list did not arrive with the request, so §13.3 was assumed and the owner told. |

| D20 | **Supersedes D17 (2026-10-05, after the investigation of §3.7).** The quiet kinds — the upcoming notice, Missed, the session chip — move to a **new channel of low importance**, `alerts_quiet`. The reminder and its snoozed re-post carry **a group key with `GROUP_ALERT_CHILDREN` and no summary**, on Android 16 and above only. No summary, no keeper. | Seen on the emulator in fifty experiments: a low channel is the only place where quiet notifications never sound, alone or bundled, and never share a bundle with reminders; a group key without a summary is not bundled at post, so the reminder sounds and peeks, and nothing app-owned can be stranded on the shade. D17's summary also works but strands (a row for up to 72 hours when its last child leaves by a timeout or a native Done) and takes standing reminders with it when it is cancelled. Below Android 16 nothing is bundled by force and the shape of a summary-less child was not run, so those phones keep today's loose reminder. The lead's, delegated; **the channel is the one decision to confirm before a release**, since a channel's importance is frozen on every phone that creates it. |

## 3. The spec

### 3.1 The page, top to bottom

```
360 x 780, a removable alarm with a description      a plain alarm
+------------------------------------+               +------------------------------------+
| 20:46                      ::: [=] |               | 06:50                      ::: [=] |
|                                    |               |                                    |
|        (bare pageGround: the       |               |                                    |
|        heads-up, when there is     |               |                                    |
|        one, is drawn here)         |               |                                    |
|                                    |               |                                    |
|  ALARM · SNOOZED                   |               |                                    |
|  20:46                             |               |                                    |
|  Sunday, October 4                 |               |  ALARM                             |
| +--------------------------------+ |               |  06:50                             |
| | (o)  Leg day - heavy squats    | |               |  Sunday, October 4                 |
| |      and accessory work        | |               | +--------------------------------+ |
| |      07:00 – 08:30             | |               | | (o)  Leg day                   | |
| |--------------------------------| |               | |      07:00 – 08:30             | |
| | Bring the belt and the chalk.  | |               | |--------------------------------| |
| | Warm up on the bike first, t.. | |               | | [>]  Open event                | |
| |--------------------------------| |               | +--------------------------------+ |
| | [>]  Open event                | |               | +--------------------------------+ |
| +--------------------------------+ |  scrolls      | |              Stop              | |
| +--------------------------------+ |  ----------   | +--------------------------------+ |
| | [x] Stop also removes     Keep | |  pinned       | +--------------------------------+ |
| |     this event                 | |               | |         Snooze 10 min          | |
| +--------------------------------+ |               | +--------------------------------+ |
| +--------------------------------+ |               |               ======               |
| |              Stop              | |               +------------------------------------+
| +--------------------------------+ |
| +--------------------------------+ |
| |         Snooze 10 min          | |
| +--------------------------------+ |
|               ======               |
+------------------------------------+
```

`PopScope(canPop: false)` → `AlarmGround` → `Semantics(scopesRoute: true,
explicitChildNodes: true)` → `Scaffold(backgroundColor: transparent)` at its
default resize (the Scaffold lifts its body over a keyboard inset) →
`SafeArea(bottom: false)` → a `LayoutBuilder` → a `Column` of the scroll
region (`Expanded`) and the dock. The route scope is the page's own:
`rootPushInstant` builds a bare `PageRouteBuilder`, under which the eyebrow's
`namesRoute` would name nothing.

| # | Element | Content | Text role | Geometry | Condition |
| --- | --- | --- | --- | --- | --- |
| 1 | Eyebrow | `alarmPageTitle`; with ` · ` + `alertsOutcomeSnoozed` on a re-ring (§3.3) | `FormSectionLabel` (11 / 500, 0.88, capitals, `onSurfaceVariant`); carries `header` and `namesRoute` | the label's own insets | always |
| 2 | Time | `payload.fireAtMs` in the phone's 12/24 style; absent, `payload.timeLabel` verbatim | `AlarmMetrics.heroFontSize` 64 on `heroLineHeight` 68, w400, tabular, `onSurface`; `MediaQuery.withNoTextScaling` inside a `FittedBox(scaleDown)`, one `Text`, the line held open when the string is empty | start at `RowMetrics.groupInset + RowMetrics.sectionLabelInset` | always |
| 3 | Day | `DateFormat.MMMMEEEEd` of the due instant's day; absent, of `payload.dayUtc` as today | `FormMetrics.labelSize` 15 on `labelLineHeight` 20, `onSurfaceVariant`, wraps | same start; `AlarmMetrics.heroGap` 16 below | always |
| 4 | Title row, `FormReadTitleRow` | `leading:` an `EventAvatar` (tint and glyph from the payload, the facade as fallback); title = `payload.title`, `alarmTestTitle` for a test, `eventAlertModeRing` when empty; caption = `payload.whenLabel` | the detail sheet's: 20 / 500 at 1.3 wrapping freely; caption 13 on 18 `onSurfaceVariant` | first row of one `FormRowGroup(trailingGap: false)`. With a caption the detail sheet's row unchanged (`twoLinePadding`, floor `twoLineRowMinHeight`): 64 dp at scale 1.0. Without one, `titleRowVerticalPadding` and floor `titleRowMinHeight`: 56 | always; caption when `whenLabel` is not empty |
| 5 | Excerpt | `payload.excerpt` | `FormMetrics.descriptionFontSize` 15 on 22, `onSurfaceVariant`, `AlarmMetrics.excerptMaxLines` 2 with an ellipsis | padding `groupInset` / `descriptionCellPadding`; wrapped in `FormIndentedRow(dividerIndent: FormMetrics.dividerIndentPlain)`, the detail sheet's description cell's indent | excerpt not empty |
| 6 | Open row, `FormActionRow` | `open_in_new_rounded` + `alarmOpenEvent`; for another database `storage_rounded` + `alarmSwitchDatabase(name)` | the action role, 15 / 500 `primary` | 48 dp minimum; last row of the group | always |
| 7 | Remove row | `auto_delete_outlined` + `alarmRemoveAfterCaption`, then `event_available_outlined` + `alarmKeptEvent`; a `FormHeaderTextButton` reading `alarmKeep` at its end | caption 13 on 18 `onSurfaceVariant` in a `FormCaptionSlot` over both texts; glyph 22 `onSurfaceVariant` | its own one-row `FormRowGroup`, the dock's first row. A page-private row: floor `FormMetrics.rowMinHeight`; `RowMetrics.twoLinePadding` above and below the caption; start `groupInset`; `FormMetrics.gap` between glyph, caption and button; end `FormMetrics.headerActionInset`; the glyph centred on the row. `AlarmMetrics.dockGap` 12 below | the slot exists when `payload.removeAfterAlert && !payload.isTest` (§3.3 says when it is filled) |
| 8 | Stop, `FilledButton.icon` | `alarm_off_rounded` + `alarmStop` | `AlarmMetrics.stopLabelSize` 20 / 500 | minimum height `AlarmMetrics.stopHeight` 64, full width inside `groupInset`; `dockGap` below; icon `AlarmMetrics.dockIconSize` 22 | always |
| 9 | Snooze, `FilledButton.tonalIcon` | `snooze_rounded` + `alarmSnoozeMinutes(n)` | `AlarmMetrics.snoozeLabelSize` 17 / 500 | minimum height `AlarmMetrics.snoozeHeight` 56; below it `AlarmMetrics.dockBottomPadding` 12 plus `viewPadding.bottom` (inside the Scaffold the keyboard inset is already taken) | always |

- **Scroll.** Elements 1–6 are one `SingleChildScrollView(reverse: true)`
  with `FormMetrics.bodyTop` above the eyebrow and `dockGap` under the group.
  Short content rests on the dock; when it is taller than the region, the
  eyebrow, time and day leave through the top first and one scroll brings
  them back.
- **A short window** (landscape, split screen, a keyboard up): under
  `AlarmMetrics.pinnedDockMinHeight` 480 of body height — the
  `LayoutBuilder`'s — the dock is not pinned: it becomes the end of the same
  reversed scroll, which takes the body's whole height so that a page shorter
  than its body still rests on the body's bottom edge.
- **Text scale.** Everything scales but the time. Inside the dock the scale
  is clamped at `AlarmMetrics.dockMaxTextScale` 1.4
  (`MediaQuery.withClampedTextScaling`); button heights are floors.
- **The heads-up.** Nothing is reserved for it. At scale 1.0 content with a
  title of up to two lines starts under it (by about 5 dp on 360 × 780, by
  arithmetic on the device font); at larger text what slides under it is the
  eyebrow and the time, which the heads-up itself repeats.
- **`AlarmGround`** (`lib/widgets/alarm_ground.dart`): an
  `AnnotatedRegion<SystemUiOverlayStyle>` over one `ColoredBox(pageGround)`.
  Both bars transparent, no divider, `systemNavigationBarContrastEnforced:
  false`, status and navigation icons dark in light and light in dark.
  **It hands the navigation bar back.** Android keeps a bar's style until
  another is set, and no other page sets one for the navigation bar, so a
  bare region would strip the contrast band from every later page. The
  ground counts the grounds on screen and sets the bar back in a microtask,
  so it follows the next page's own style instead of replacing it. When the
  last ground leaves, the navigation bar is handed back in the state the app
  has at launch: what `MaterialApp` itself sets on every theme build, read
  off `SystemUiOverlayStyle.light` (colour `0xFF000000`, light buttons), with
  the transparent divider and contrast enforcement on (C27). From Android 15
  Flutter's embedding no longer passes the colour on and the phone forces the
  buttons of a light window dark, so the API 36 emulator reads the same
  before and after a ring; below 15 it is light buttons on black, as before
  the ring — read from Flutter's sources, not seen on a device.
  On a phone in light mode Android forces dark navigation buttons on the dark
  page (`FORCE_LIGHT_NAVIGATION_BARS`): they come out `#666666` on `#141218`,
  with no band. The cure is under `android/` and app-wide (§8).
- **Semantics.** The avatar is excluded; the title row is one node; the
  remove row's text and its Keep are two; Keep's accessible name is the full
  `alarmKeepEvent` (`FormHeaderTextButton` gains `semanticsLabel:`). The Open
  row at 38 % is announced as a disabled button (`FormActionRow` wraps its
  well in `Semantics(button: true, enabled: onTap != null)` inside its
  merge). Ids: `alarm-stop`, `alarm-snooze`, `alarm-open-event`,
  `alarm-keep-event` unchanged; `alarm-open-database` new (the Open row while
  it is the switch); `alarm-body` new, on the scroll region, for a flow's
  `scroll-to --up --in id:alarm-body` (a reversed scroll hides its start).

### 3.2 `AlarmMetrics` (`lib/constants/alarm_metrics.dart`)

`heroFontSize` 64, `heroLineHeight` 68, `heroGap` 16, `excerptMaxLines` 2,
`dockGap` 12, `dockBottomPadding` 12, `stopHeight` 64, `snoozeHeight` 56,
`stopLabelSize` 20, `snoozeLabelSize` 17, `dockIconSize` 22,
`dockMaxTextScale` 1.4, `pinnedDockMinHeight` 480. Everything else on the
page is a `FormMetrics` or `RowMetrics` name. No `AppSpacing` read remains.

### 3.3 States

Which rows exist is a payload fact, fixed on the first frame. Later only
text, an enabled flag or a glyph changes — with the two exceptions below.

| State | Drawn |
| --- | --- |
| Plain | elements 1–4, 6, 8, 9 |
| Test alarm | title `alarmTestTitle`, no caption; the Open row at 38 % in place; no remove row; the avatar is the alarm glyph in **the theme's primary** (since Slice 3 — the stamped light-scheme purple was the dimmest thing on the dark page; the stamp stays for the notification's colour); from another database it shows the switch, as the chip did |
| Re-ring | eyebrow `ALARM · SNOOZED` when `payload.reRing`, or `payload.snooze && !payload.isTest`. A ring snoozed on the notification whose second ring cold-starts the app reads plain `ALARM` with its first time: known and left |
| Will remove, database not yet known | the remove row's slot is laid out and undrawn (`activeDatabase` is null until `load()` returns, one frame after the page in practice, and stays null if it throws) |
| Will remove | once `activeDatabase == payload.database` the slot is filled: caption and a live Keep, together |
| Keep pressed | the tap clears `willRemoveEvent` at once, as today, so a Stop, Snooze or Open event during the write removes nothing, and Keep is disabled. When the upsert returns the caption becomes `alarmKeptEvent`, the glyph `event_available_outlined`, and Keep stays, disabled. A write that throws, or finds no event to write to, restores `willRemoveEvent` and puts Keep back |
| Already kept | the event no longer carries the flag when the ring comes up (a Keep on an earlier ring: a Snooze taken on the notification, or a second alarm of the same event, rings from a payload armed before it). The row reads "The event will be kept" with Keep disabled from the page's first notification — the controller looks the event up before it notifies (C24). An event that is not found, or a lookup that throws, changes nothing. |
| Another database | the Open row becomes the switch (`alarm-open-database`); the remove row's slot is never filled — Stop removes nothing there and the page does not say otherwise |
| Busy (Stop or Snooze in flight) | Stop, Snooze, the Open row and Keep disabled in place; no spinner |
| Unlock pending | the Open row ignores a second tap (one flag in the page over `_openEvent` and `_openDatabase`) |
| Empty title | the tier word, `eventAlertModeRing` |
| Empty time | the line is held open; the day still shows |
| A second ring's page on top | each page closes its own route (D9) |
| Entry armed by an older build | today's content in the new layout: `timeLabel` as the time, `dayUtc` as the day, no caption, the facade's tint |

**The exceptions.** Both come with the database fact, which arrives after the
first frame. (1) The remove row's content is drawn then; its slot was sized
on the first frame, so no rect moves. (2) For another database's alarm the
Open row's label changes in place, and at large text its height can change
with it; that row is the last of the scroll region, so what moves is the
content above it. Nothing in the dock moves, ever: a test pins the rects of
Stop, Snooze and Keep before and after the database fact and before and after
Keep.

### 3.4 Page copy

| Key | en | de | ro | Status |
| --- | --- | --- | --- | --- |
| `alarmTestTitle` | Test alarm | Testalarm | Alarmă de test | new; the page and the composer title a test ring from `isTest`. `calendar_settings_page.dart:1214` keeps passing its button's label into the payload, where nothing reads it |
| `alarmKeep` | Keep | Behalten | Păstrează | new, the visible label; `alarmKeepEvent` stays as its accessible name |
| `alarmRemoveAfterCaption` | Stop also removes this event | Stopp entfernt auch diesen Termin | Oprirea elimină și evenimentul | same key, shorter text |
| `alarmSwitchDatabase` | Switch to {name} | Zu {name} wechseln | Comută la {name} | new; replaces the dead `alarmOpenDatabase` |
| `alarmDatabaseSwitchedTitle` | Switched to {name} | Zu {name} gewechselt | Ai comutat la {name} | new; replaces `restartRequired` as the dialog's title |
| `alarmDatabaseSwitchedBody` | Exit ANTA and open it again to see this event. The alarm keeps ringing until you stop it. | Beende ANTA und öffne es erneut, um diesen Termin zu sehen. Der Alarm klingelt weiter, bis du ihn stoppst. | Închide ANTA și deschide-o din nou ca să vezi evenimentul. Alarma sună până o oprești. | new; replaces `restartRequired` as its body |

Unchanged: `alarmPageTitle`, `alarmStop`, `alarmSnoozeMinutes`,
`alarmOpenEvent`, `alarmKeepEvent`, `alarmKeptEvent`. Retired:
`alarmFromDatabase`, `alarmOpenDatabase`.

### 3.5 The notifications

`{when}` is `payload.whenLabel`, or `payload.timeLabel` when that is empty —
since 2026-10-10 (B4, C32) a `whenLabel` for an occurrence on another day
leads with that day, "Mon, Sep 21 · 18:00 – 19:30", so the one-line row keeps
the day when it cuts the end. `{time}` is `payload.timeLabel`, the alarm's
own time. Text is composed with `alertsKindWhen`.

| Kind | Title | Text | Expanded | Colour | Large icon | Header clock | Actions | Silent |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ring (the fork) | title; `alarmTestTitle` | `Alarm · {when}` | — | tint, colorized (Patch 3) | — | post time | Stop · Snooze N min | — |
| Reminder | title | `Reminder · {when}` | text, new line, excerpt | tint | avatar | post time | Done · Snooze N min | no |
| Snoozed re-post | title | `Snoozed · {when}` | same | tint | avatar | post time | Done · Snooze N min | no |
| Upcoming notice | title | `Alarm at {time}` (`alertsUpcomingTitle`); with `alertsWhenOnDay` and the gateway's `dayLabel` when the alarm is not on the notice's day | text, new line, excerpt | tint | avatar | post time | Skip · Open | yes, as today |
| Missed | title | `Missed · {time}` | text, new line, excerpt | tint | avatar | `when` = the due instant | — | **yes** |
| Session chip | title | `Until {untilLabel}` / `Session in progress` | — | tint | avatar | chronometer, up, as today | Done · Open note; Open event (`alarmOpenEvent`) when no note is linked | yes, as today |
| Fallback alarm (dormant) | title; `alarmTestTitle` | `Alarm · {when}` | text, new line, excerpt | tint | avatar | post time | Stop | — |

Kind words are the app's own: `eventAlertModeRing`, `eventAlertModeNotify`,
`alertsOutcomeSnoozed`, `alertsOutcomeMissed`. An empty title is the tier
word. Action ids do not change. Lock-screen visibility is not changed (the
platform default is already private; the ring stays public in the fork).
"Silent" is the notification's own flag; what makes the quiet kinds quiet in
company is the channel they post on since Slice 4 (`alerts_quiet`, §3.7).

| Key | en | de | ro | Status |
| --- | --- | --- | --- | --- |
| `alertsKindWhen` | {kind} · {when} | {kind} · {when} | {kind} · {when} | new, Slice 3 |
| `alertsWhenOnDay` | {when}, {day} | {when}, {day} | {when}, {day} | new, **Slice 1**; since 2026-10-10 only the upcoming notice's "Alarm at 7:00 AM, Mon, Sep 21" (its description says so); `day` is `DateFormat.MMMEd` |
| `alertsDayThenWhen` | {day} · {when} | {day} · {when} | {day} · {when} | new, 2026-10-10 (B4, C32): what `AlertLabels.whenLabel` and the moved line's rescue write for an occurrence that is not on the due day, the day first |

Retired: `alertsSnoozeAction` (the reminder takes `alarmSnoozeMinutes`),
`alertsSnoozedBody`, `alertsMissedTitle`, `alertsMissedBody`. The `@`
descriptions of `alarmSnoozeMinutes`, `alertsDoneAction`,
`alertsUpcomingTitle`, `alertsTestAlarm` and `alarmOpenEvent` are rewritten
to what they now label.

One module composes all of it: `lib/utils/alert_notification_content.dart`,
a pure function from (kind, payload, strings, `{String? dayLabel, String?
untilLabel}`) to title, text, expanded text and action labels. The two named
labels are the only things a payload cannot say: the notice's day needs the
notice's own instant, and the chip's end is the session's — the gateway
writes both through `AlertLabels`. The gateway and the background isolate
both call the module. It is the first place a notification's words can be
tested.

### 3.6 Data

**Payload** (`lib/models/alert_payload.dart`). All optional, left out of the
JSON when absent; `copyWith` and `props` gain them and the missing
`tintIcon`.

| Field | Type | Key | Meaning | Absent means | Stamped by |
| --- | --- | --- | --- | --- | --- |
| `fireAtMs` | int? | `fireAt` | the instant this entry is due | the page draws `timeLabel` and `dayUtc`; Missed has no `when` | the scheduler (`_payloadFor`, `_payloadForRow`, a snooze restamps its own); the isolate's re-post stamps its own. When the gateway reports a ring whose payload **already carries one**, it replaces it with the plugin's `alarm.dateTime`; a payload without one is passed on untouched |
| `reRing` | bool | `reRing`, written only when true | this process saw the plugin move this ring by a snooze | false | the gateway, for a payload that carries `fireAtMs`, when it has received an `AlarmMoved` with cause `snooze` for that id since the entry was armed |
| `whenLabel` | String | `when` | the event's own time as a line: "18:00 – 19:30", "18:00", or `eventAllDay`; led by its day (`alertsDayThenWhen`, `DateFormat.MMMEd`) when the occurrence is not on the due day — until 2026-10-10 the day followed, through `alertsWhenOnDay`, and the platform's one-line cut took it (B4, C32); **empty when it would only repeat the due time** (compared as minutes, not as text) | the page draws no caption; notification text uses `timeLabel` | the scheduler |
| `tintValue` | int? | `tint` | the avatar's colour by the one icon rule, resolved at arm time | on the UI isolate `CalendarCategories.resolve`, as today; in the isolate's re-post no colour, as today — the facade is empty there | the scheduler |
| `glyphKey` | String? | `glyph` | the avatar's resolved icon key | `iconKey`, then the facade | the scheduler |
| `languageCode` | String? | `lang` | the language the entry's strings were written in | the device locale, as the isolate does today | the scheduler |
| `iconFile` | String? | `iconFile` | the rendered avatar's path | no large icon on the re-post | the gateway, Reminder tier only (Slice 3) |
| `grouped` | bool | `grp`, written only when true | the entry was armed with the reminders' group key (§3.7) | false: the re-post is loose, as the entry was | the gateway, Reminder tier, with what it armed (Slice 4) |

- **Labels.** One seam (`AlertLabels`, built once per pass from the stored
  language and `PlatformDispatcher.alwaysUse24HourFormat`) writes
  `whenLabel`, `timeLabel`, the notice's `dayLabel` and the chip's
  `untilLabel`. The scheduler takes it through the gateway, so its suite
  keeps a fixed 24-hour English one and the no-op gateway answers the same.
  **In Slice 1 `timeLabel` stays on today's neutral 24-hour skeleton**, so
  nothing the old page or today's notifications draw changes; Slice 3 turns
  it to the phone's style together with the token. "The phone's style" is
  Material's rule, the one every in-app surface follows: 24-hour when the
  phone says so, otherwise the app language's own convention — so German and
  Romanian stay 24-hour on a 12-hour phone. Every method is total: a format
  that throws leaves the label out and logs, because a write runs inside the
  pass that arms or the callback that announces a ring.
- **A test ring** is stamped in `_payloadFor` (for `AlertPayload.testEventId`,
  so its snooze gets it too) with a fixed tint
  (`AppTheme.lightScheme.primary`), the quick alarm's glyph and an empty
  `whenLabel` — its stand-in event has no time and would otherwise read
  "All day".
- **A moved entry** — a ring report whose instant moved, and a snooze rebuilt
  from a payload — is restamped by one function, `AlertLabels.moved(payload,
  fireAt)`: the new `fireAtMs`, `timeLabel` rewritten for it, and **the
  rescue**: an empty `whenLabel` takes the old `timeLabel`, the event's own
  time the entry was armed at. The rescue is gated on `languageCode`, not on
  `fireAtMs` — only a labelled arming stamps the language, while a
  payload-only snooze stamps `fireAtMs` on an older payload too, and a second
  snooze would otherwise caption the first snooze's time as the event's own.
  It is not made for a test ring (it has no event) or for a move inside the
  same minute (the platform's 30-second deferral). Since Slice 2 the rescued
  line carries its day when the move crossed midnight, by the rule
  `whenLabel` already applies; since Slice 3 "the same minute" is decided on
  the instants, not on label text.
- **A ring report** is one pure function, `ringReportPayload(stored,
  alarmDateTime, osId, labels, nativelySnoozed)`: `osId` as today; for a
  payload that carries `fireAtMs` and whose instant moved, the move above, in
  the payload's own language; `reRing` from the gateway's record of snooze
  moves, and only when the instant moved. The two report sites and the
  emit-once guard only call it. The record of snooze moves is filled from
  `AlarmMoved` with cause snooze and forgotten when an entry is armed under
  the id or the id is cancelled — not when the ring ends, because a ring that
  ends in a snooze is what creates it.
- **A snooze rebuilt from a payload** (another database's alarm, a
  registration that is gone) keeps its stand-in event and alert for the
  `PlannedFire`, and its payload is the ringing one moved as above, with
  `osId`, `snooze: true`, the snooze length in force and `reRing` cleared.
  Everything else is carried verbatim.
- **Keep's write reaches the calendar** through a process-global notice,
  `AlertKeepNotice` (`lib/services/alert_keep_notice.dart`) — a flag with no
  payload and no freshness window, since the calendar reloads everything and
  a reload owed an hour ago is still right: `keep()` publishes when the
  upsert returns, and `CalendarPage` answers with `LoadCalendarEvents`. A
  calendar mounted by Open event right after a Keep holds its initial target
  until that reload has replaced the event list, so the detail sheet it opens
  is the kept event's. The real `keep()` and `stop()` are tested through
  three injected functions — `findEvent`, `saveEvent` and `removeEvent` —
  (`AlertRingController.configureForTesting`). `load()` uses the lookup too
  (C24).
- **The arm token.** `alertArmContext(backend, volume, language, use24Hour)`,
  pure and public, spelled `<backend>[@floor]~g4.<lang>.<H|h>` (`g2` in
  Slice 3, `g3` since Slice 4 moved the content version for the group key and
  the quiet channel, `g4` since 2026-10-10 for B4's day-first line — the
  owner's phone carried `g3` entries by then);
  `refreshArmContext` returns it and re-reads the stored language each pass —
  through `SettingsService.getLocaleCode()`, never
  `AppDatabase.getInstance()`, which re-resolves which database is active and
  carries out a stored switch under the running app (C28); the binding's
  direct read happens at its first start only.
  `alertArmSignature` itself is not edited and its pinned literals stay. It
  lands **with the content it re-arms for** (Slice 3): the first pass after
  the upgrade re-arms every **planned** entry (`kind = scheduled`) of the
  open database once; snooze-kind rows, a test ring and a natively snoozed
  alarm are skipped, as the fast path always skips them. A notice already on
  the shade is taken down by the re-arm and not posted again. After a
  language or 12/24 change the re-arm comes with the next resume, launch or
  edit — no pass follows the change itself.
- **Old payloads live for good.** Another database's entries and standing
  snoozes are never re-armed, so every reader keeps its fallback.
- **The large icon.** `kAlertLargeIconDp` 48 × the device pixel ratio,
  `EventAvatar.backgroundAlpha` and its glyph-to-disc ratio; one PNG per
  glyph, colour, size, disc alpha and glyph size — the file's name ends
  `_<pixels>_a<alpha>_g<glyph>.png`, so a change of `EventAvatar`'s constants
  names new files by itself (C29) — under
  `<application support>/alert_icons/`, handed over as
  `FilePathAndroidBitmap`. Files are never cleared wholesale: a standing
  reminder holds the path. The raster and the write stay bounded
  (`_rasterPatience`); a failure posts without an icon.
- **Testable pieces.** Beside the composer, pure, top-level and public: one
  details function per kind returning `AndroidNotificationDetails`, and
  `snoozedRepost(payload, now, strings)`. The gateway and the isolate only
  call them — nothing else in `AndroidAlertGateway` can be reached from a
  test.
- **The isolate's re-post** takes strings from
  `alertGatewayStrings(payload.languageCode)`, composes its text **before**
  it cancels, and posts title-only if composing throws. Which language is
  asked for and what a failure falls back to are one function's,
  `snoozedRepostFor(payload, now)` — public, with the strings lookup a
  parameter, so that the suite pins both.
- **`SessionChip.kt`**: Done added before Open; the second label and a
  large-icon path arrive from Dart.
- **`VolumeSettings.fade(showSystemUI: false)`**, so the phone's volume
  panel does not land over the page when the ring is in the floor bucket.

### 3.7 Grouping (Slice 4) — as settled on the emulator (D20)

**What the platform does** (Android 16, SDK 36.0, build `BE2A.250530.026.D1`;
fifty experiments with probe notifications posted through the running QA
app, each read back from `dumpsys notification`, the `notification_alert`
event log and SystemUI's `NotifInterruptLog`, then audited line by line):

1. **Two sections.** A channel of importance default or high belongs to the
   alerting section, a low one to the silent section.
2. **Loose notifications are bundled as soon as two stand in a section**,
   about 200 ms after the second is enqueued and before the alert decision.
   Every child is flagged `SILENT`; one that joins at post makes no sound and
   reads `PEEK suppressed: notification isSilent`. A notification with the
   silent flag holds no group and counts as loose.
3. **The platform's summary takes its alert behaviour from its children** —
   summary-alerts when every child is silent — and is posted on the channel
   of the notification that created the bundle. On a channel that makes
   noise such a summary **sounds when the bundle is made and again when a
   member leaves it**. That is three wrongs in the build of `a0a82ba`: (a) a
   reminder beside a standing chip or notice is silenced; (b) two quiet
   notifications together sound; (c) dismissing a reminder that was bundled
   with the chip makes the summary sound and the chip peek.
4. **On a low channel nothing ever sounds**, alone or bundled, with the
   silent flag or without it, and quiet notifications there never share a
   bundle with a reminder.
5. **A group key without a summary is not bundled at post.** The child
   sounds, vibrates and peeks; alone it is left alone. When two ungrouped
   notifications stand in its section the platform bundles them 3.2 s after
   the enqueue, and a heads-up still showing is withdrawn — about 3.0 s on
   screen instead of 5.7 s. With the process dead it is the same.
6. **An app group with its own summary is left alone** (a full heads-up),
   but the summary stays as a row when its last child leaves by an app
   cancel, a native action or a timeout — it was watched for three minutes
   and its own timeout is 72 hours — and a summary that leaves takes its
   children with it. At six single-child groups the platform dissolves them
   all.
7. **The ring is untouched** by any bundle or group: `FSI allowed` with all
   of it standing.
8. Also seen: an alert under a minute after the previous one is attenuated,
   and of two posted in the same instant only the first sounds, in every
   arrangement; a heads-up swiped up withholds the package's next peeks
   (`package snoozed`); with the screen off a notification sounds and does
   not peek; **this image's lock screen does not draw the silent section**;
   and the chip is not promoted on this image on any channel (the permission
   is requested and not granted).

**The arrangement (D20).**

- **`alerts_quiet`**, a new channel of low importance, created beside the
  other two with a localized name and description (`alertsQuietChannel`,
  `alertsQuietChannelDesc`): the upcoming notice, Missed and the session chip
  post on it. They keep their silent flag — on a low channel it changes
  nothing. `alerts_reminder` is left with what its name says.
- **`kAlertGroupKey` (`'anta.alerts'`) with `GroupAlertBehavior.children`**
  on the reminder, the snoozed re-post and the title-only re-post, **on
  Android 16 and above** (`Build.VERSION.SDK_INT >= 36`, read once through
  the alerts channel). The isolate cannot ask, so an entry armed with the
  group carries it: one more optional payload field, `grouped` (key `grp`,
  written only when true), which `snoozedRepost` reads.
- **No summary and no keeper.** The dormant fallback alarm stays loose: its
  insistent sound across the regroup was not run, and flipping
  `kAlarmTierUsesNotifications` reopens the question.
- **The token's content version moves on (`g3`)**: a scheduled reminder is
  posted from the details frozen when it was armed, so planned reminders are
  re-armed once to carry the group key, and planned alarms once so that
  their notices are scheduled on the new channel.

**What it costs, as seen.** A reminder that fires while another ANTA
notification stands in the alerting section — now only another reminder —
keeps its sound and its peek, with about 3.0 s of heads-up. Of two reminders
due in the same minute the second makes no sound and its heads-up lasts
about 1.3 s; that holds under a summary too. On a phone whose lock screen
hides silent notifications, Missed and the chip are not on the lock screen.

**Known limits.** Entries the scheduler never re-arms — another database's,
and standing snoozes — keep the old shape for good: their loose reminders
are still silenced beside a standing one, and a notice of theirs still on
`alerts_reminder` can still make the platform's summary sound once.

**To be seen before the slice is done**, with the app's own code, the event
log cleared first and the process killed before each firing:

| # | Staged | Must be seen |
| --- | --- | --- |
| 1 | The chip and a notice standing on `alerts_quiet`, a reminder fires | the reminder's record keeps `g:anta.alerts`, `flags=` without `SILENT` at post, `notification_alert` buzz 1 beep 1 on its key, `PEEK allowed`; a native shot of the heads-up with Done · Snooze |
| 2 | A second reminder while the first stands | the same at post; then Done on one and Snooze on the other inside the platform's bundle, the snoozed one coming back and sounding |
| 3 | Missed beside a notice beside the chip, each then leaving (the notice by its timeout) | no buzz or beep on any ANTA key, the attention state naming none — read before the shade is opened |
| 4 | A test ring with all of it standing, the screen off | `FSI allowed` |
| 5 | The first launch over entries armed by the previous build | every planned entry re-armed once, a second launch none; the notices on the new channel |

**Owed, not stageable here:** the promoted chip on a low channel (an image
that grants promotion — API 36.1 on the Mac, or the phone; the Live Updates
documentation excludes only `IMPORTANCE_MIN`); the same readings on a second
platform build, since the reminder's shape leans on the 3-second wait before
the platform bundles; a reminder behind a PIN keyguard.

### 3.7a The plan before the investigation (superseded by D20, kept for the reasoning)

- **Members:** the reminder, the snoozed re-post, the dormant fallback —
  `groupKey: kAlertGroupKey` (`'anta.alerts'`), `GroupAlertBehavior.children`.
- **Summary:** one notification under a fixed negative id on
  `alerts_reminder`, `setAsGroupSummary`, silent, no payload (so a tap is
  ignored and it is never listed as a stray), titled `alertsTitle`.
- **Keeper:** one pure plan (standing members, pending members' own due
  instants → show / cancel / schedule-at) with an executor, run at the end
  of each reconcile pass, after a notification response, and in the isolate
  after Done and Snooze. The summary is scheduled at exactly the next
  member's instant, never earlier, and only when that instant is still
  ahead (the plugin refuses a past date).
- **The token's content version moves on (`g3`)** in this slice: a scheduled
  reminder is posted from the details frozen when it was armed, so standing
  members must be re-armed to carry the group key.
- **Outside:** the ring (a colorized foreground-service notification, exempt,
  and it carries the full-screen intent) and the quiet kinds — notice,
  Missed, chip — each of which can leave the shade with no code running and
  would strand a summary.
- **The quiet kinds are not quiet together** (seen in Slice 3's fix pass,
  2026-10-05, API 36). `silent` is `NotificationCompat.setSilent`: the
  record reads `flags=…|SILENT` and `groupAlertBehavior=1` and holds no
  group, and one such notification alone makes no sound (the event log's
  `notification_alert` for its key reads buzz 0, beep 0; both keys of
  `Notification attention state` stay null). When a second one of ANTA's
  stands, the platform bundles the two under an `Aggregate_AlertingSection`
  summary of its own — on `alerts_reminder`, `groupAlertBehavior=1`, not
  silent — and **that summary sounds and vibrates**: `notification_alert`
  for its key reads buzz 1, beep 1, and the attention state names it under
  both keys. Seen for a Missed beside a notice, a notice beside the chip and
  a notice beside a notice. The last two need nothing of this rework (the
  notice and the chip were posted this way at `a0a82ba`), and with the
  notice lead at its default of 120 minutes two alarms inside two hours are
  enough. Missed is the pair Slice 3 changed: it used to sound alone and, in
  company, to be silenced — inferred from what the forced grouping does to a
  notification that is not silent (a reminder posted beside a notice in the
  same pass was flagged `SILENT`, its summary read `groupAlertBehavior=2`
  and nothing sounded); the old build was not run — and it is now the other
  way round. So "outside" cannot mean loose on `alerts_reminder`. This slice
  settles the cure on the emulator, under row H. Two candidates, neither
  decided: an app-owned group with a silent app summary for the quiet kinds
  (what strands that summary has to be answered first), or a channel below
  `IMPORTANCE_DEFAULT` for them — a channel change, which §4.1 has to name
  before anything is built.

**It ships only if the emulator shows all of A–D**, process killed for each
(`dumpsys notification --noredact`; `dumpsys activity service
com.android.systemui/.SystemUIService NotifInterruptLog`). B and C need a
seed of their own (two reminders; a notice with `alert_notice_lead_minutes`
seeded at 1). Row H is the quiet kinds' own gate: it holds nothing of the
reminders' grouping back, and no kind is called quiet in company until it is
seen.

| Case | Must be seen |
| --- | --- |
| A. Chip standing, a reminder fires | the reminder's record keeps `g:anta.alerts`, no `Aggregate_` group, `flags=` without `SILENT`; no `PEEK suppressed` for its key; a native shot of the heads-up with Done · Snooze |
| B. Notice standing, a reminder fires | the same |
| C. A reminder standing, a second fires | the same for the second; one ANTA group of two on the shade |
| D. Summary and reminder scheduled for one instant | both records present; `dumpsys alarm` shows the two entries; under `dumpsys deviceidle force-idle` the reminder posts on the minute |
| E. The previous reminder swiped away, the next fires | record what the log says; a `PEEK suppressed` here is written down as a known limit |
| F. A ring while the group stands | `FSI allowed` |
| G. After Done, Snooze, or a swipe of the last member | no ANTA summary record remains |
| H. A quiet kind posted while another stands: a Missed beside a notice, a notice beside the chip, a second notice beside the first | no `notification_alert` with buzz or beep for any ANTA key (`adb logcat -b events -d`), and `Notification attention state` naming no ANTA record — read before the shade is opened, which clears both keys |

First of all the slice reads what group the quiet kinds really hold today
(`g:silent` or none) — it decides whether "outside" means loose or a
summary-less child. The dumps of Slice 3's fix pass say none on API 36: each
record's group key is its own key until the platform bundles it.

## 4. Behaviour

### 4.1 Must not change

- Back does nothing: one `PopScope(canPop: false)` under the page.
- The page renders from the payload alone. Two things are resolved after the
  first frame and arrive together, in one notification: which database is
  open and, for a remove-after alarm of that database, whether its event was
  already kept (C24). No text field, ever.
- Pushed with `AppNavigator.rootPushInstant`, never stamped as a
  `NavDestination`; the route's future completes when it leaves.
- The page reports itself to `LockScreenState` through `RouteAware`
  (`didPush`, `didPopNext`, `didPushNext`, `didPop`, `dispose`); a dialog it
  raises is a popup route and leaves it on top.
- **No perpetual animation.** The suite `pumpAndSettle`s and the QA agent
  settles frames before every verb.
- A ring that ends elsewhere closes the page; a native snooze closes it,
  settles nothing and removes nothing.
- Open event and the database switch ask `AlertRingController.unlock()`
  first, with the ring still going, and return on a refusal.
- Open event reads the removal flag, then stops, then closes, then opens the
  day (without the event id when Stop removed it).
- Stop's order: the scheduler's stop, the standing snooze of the same alert
  and day, the session chip, then the removal.
- Snooze silences first, and works for a test ring and for another
  database's alarm; one Snooze button whose length comes from the payload.
- Keep is one-way and persisted, not held in memory; from the press, Stop
  removes nothing.
- The database switch: unlock, switch the stored name, then the
  non-dismissible single-action dialog that exits the app. It does not stop
  the ring.
- The four ids `alarm-stop`, `alarm-snooze`, `alarm-open-event`,
  `alarm-keep-event`, each on its control's own node.
- The injected controller is test-only; the page disposes only one it made.
- The cover: opaque, touch-absorbing, out of the accessibility tree, exactly
  one `ColoredBox`, never remounting what is underneath, a touch re-asking
  the platform, changes mid-frame applied post-frame.
- The tiers: a reminder never reaches the `alarm` plugin and never becomes
  the phone's next alarm; the reminder's Snooze and Done run in the
  background isolate, which opens no database and loads no facade; its
  re-post is `snooze: true` under the snooze id; Skip is a foreground action.
- Notification ids, action ids, the three existing channels' ids, importance
  and sound (D20 adds a fourth, quiet one and moves three kinds onto it);
  what a tap on each notification opens; the notice's `timeoutAfter`.
- `Alarm.set`'s arguments other than the notification's text, a test ring's
  colour and `showSystemUI`; the fork's `setColorized(true)`; the fork's
  Pigeon bindings.
- `alertArmSignature`, the planner, the registry, the sound values.
- The chip: alarm tier only, never for a test or another database's alarm,
  once per ring, Done with no Dart running.
- The icon's raster and file write stay bounded and never block a schedule.
- Every A- and B-decision of [event-alerts-roadmap.md](event-alerts-roadmap.md)
  and [event-alerts-os-integration-roadmap.md](event-alerts-os-integration-roadmap.md),
  and the lock-screen rules of its §13 — but for the copy and the action
  order that C13 and C16 change on purpose (A10's "Missed: {title}", B8's
  "Open note and Done") and, since 2026-10-10, A10's in-flight band, which
  C36 holds open while a ring is in progress and Patch 9 (C34) completes in
  the fork, and A10's delivery evidence, which C39 widens by `kRingStartGrace`
  past the instant.

### 4.2 Deliberately changes

| # | Change | Tests that change on purpose |
| --- | --- | --- |
| C1 | The page closes its own route (D9) | the two `DEFECT, pinned as it stands` cases flip |
| C2 | Keep stays, disabled, after it is pressed; the caption changes in place | the Keep cases that assert "absent" |
| C3 | The remove claim and Keep are drawn only once the open database is known to be the alarm's; "kept" is drawn when the write has returned; a failed write puts Keep back | the removable-event case moves to the scripted controller; new cases |
| C4 | Keep's write reaches the calendar (§3.6) | the notice's suite beside `alert_skip_notice_test.dart`; one calendar-page case; flow 02 reads the row |
| C5 | Another database's alarm shows no remove claim and no Keep | new case: a removable alarm from another database |
| C6 | The chip becomes the Open row's second face, with its own id; the dialog's title and body say what happened | the two A9 cases, the three chip cases, the second `DEFECT` case; the robot's `databaseLabel` |
| C7 | The Open row ignores a second tap while its unlock is pending | new case |
| C8 | A test ring is titled "Test alarm" and wears a tint | the test-alarm case; flow 00 |
| C9 | The time follows the phone's 12/24 style and is this ring's due instant; the day is that instant's | the suite's `payload()` gains `fireAtMs`; one case keeps a payload without it and still reads `07:00` |
| C10 | The event's own time and the description's first line are drawn | new cases |
| C11 | The ground is `pageGround`, the bars are declared, and the cover matches | new theme cases; the curtain suite unchanged |
| C12 | An empty title falls back to the tier word | new case |
| C13 | Notification grammar, decor, expanded text, action order, the reminder's Snooze label, Missed's silence and clock (§3.5) | none exist; the composer's and the details functions' suites are new |
| C14 | The snoozed re-post keeps colour, icon, excerpt and the app's language | `snoozedRepost` cases; `snoozedRepostFor` cases for the language the isolate asks for and its title-only fallback |
| C15 | A language or 12/24 change re-arms planned entries | `alertArmContext` cases |
| C16 | The chip's actions swap; "Open event" when no note is linked; it carries the avatar | `session_chip_test` argument cases |
| C17 | No volume panel in the floor bucket | — (device) |
| C18 | A re-ring says so on the page when it is known | `ringReportPayload` cases; page cases |
| C19 | The notice, Missed and the chip post on the new low channel `alerts_quiet`; on Android 16 and above a reminder and its re-post carry a group key (D20) | the details functions' cases per channel and per SDK level; `snoozedRepost` with and without `grouped`; `alertArmContext` at `g3`; the chip's channel argument |
| C20 | A disabled `FormActionRow` is announced as a disabled button (kit) | `form_rows_test` |
| C21 | A ring the app itself cancels (Slice 5 stopped reading it as a dismissal, which had posted the chip and removed a remove-after event with nobody answering) ends with its own cause, `cancelled`: the page closes, held intents go out, and nothing is settled (Slice 6) | a page case; `main.dart`'s exhaustive switch; the gateway's source guard |
| C22 | A ring the binding is itself stopping is not announced again: when a stop promotes a queued alarm, the plugin can tell of the new ring before it has taken the stopped one out of its set, and the stopped ring was then tracked again and ended as a dismissal — which cancels a snooze just taken and runs the removal (read from the code in Slice 5's review; Slice 6 stages it with the pair) | the gateway's source guard; the pair on the emulator |
| C23 | The reconcile's diff loop leaves an entry in flight alone: its id is ringing, or its standing registration is for this same instant and that instant has passed since the pass read its clock. Before, the first pass of a build that moved the arm token re-armed an alarm that came due mid-pass over its own ring; the plugin stopped the ring it replaced and that was settled as a Stop on the notification — page closed, chip posted, a remove-after event deleted (fix batch A1). Since 2026-10-10 (C38) the ringing check needs no registration and a planned fire never lands on the id of a ringing or `fired` row | five cases in `alert_scheduler_test.dart` (the fake gateway's `onArmContextRead` hook moves the clock inside a pass) |
| C24 | A ring whose event was already kept says so from its first notification: `AlertRingController.load()` looks the event up before it notifies, and the row reads "The event will be kept" with Keep disabled instead of a claim Stop would not honour. Amends §4.1 (fix batch A2) | controller cases for the three outcomes and the single notification; two page cases; the scripted controller's `resolveDatabase(name, kept:)` |
| C25 | Stop decides the removal at the press and may only narrow it: a Keep whose write fails while Stop is in flight no longer widens the decision back to a removal (fix batch A2) | controller cases through `configureForTesting(removeEvent:)` |
| C26 | After a Keep, the calendar's detail-sheet trip takes the remove-after flag from the bloc's copy before it writes its own copy back or hands it to the editor, and every calendar on the navigator counts a Keep it hears (`lib/pages/calendar_page.dart`: `_keepsHeard`, `afterKeep`). Before, a task ticked in a sheet left open under the ring wrote the flag back and a later alarm removed the kept event (fix batch A2) | four cases in `calendar_keep_notice_test.dart`, one with two calendars stacked |
| C27 | The navigation bar is handed back in the state the app has at launch — `SystemUiOverlayStyle.light`'s colour and light buttons, which is what `MaterialApp` sets — instead of buttons by the phone's brightness on a transparent bar, a state the app never had below Android 15 (fix batch A2) | `alarm_ground_test.dart`: the hand-back for each phone and app brightness, and a pin against what a bare `MaterialApp` really sets |
| C28 | The per-pass language read goes through `SettingsService.getLocaleCode()`, never `AppDatabase.getInstance()`, which carries out a stored database switch under the running app; the binding's direct read happens at its first start only (fix batches A1 and A2) | the source guard in `alerts_channel_test.dart`; `locale_code_setting_test.dart` |
| C29 | `alerts_quiet` is created with no sound and no vibration; an avatar's file name carries the disc's alpha and the glyph's size; an excerpt's cut never leaves half a surrogate pair (fix batch A1) | the channel pin in `session_chip_channel_test.dart`; the name's cases in `android_alert_notifications_test.dart`; `alert_excerpt_test.dart` |
| C30 | The fork's seventh patch, in Dart: the plugin's fallback timer gives up on a ring the platform reported and that was stopped inside its 700 ms wait — it asked only "is it ringing now" and announced a ring that was over (fix batch A1) | `packages/alarm/test/alarm_fallback_timer_test.dart`, the fork's own suite |
| C31 | Wording: Romanian "Oprirea elimină și evenimentul" (one verb for the removal across the feature); the switch dialog says "Exit ANTA…" / "Beende ANTA…" like its button (batch B: B1, B3) | — |
| C32 | An alert whose occurrence is on another day leads with that day — "Reminder · Mon, Sep 21 · 18:00 – 19:30" (`alertsDayThenWhen`) — on every kind and on the page's caption; the token moves to `~g4` so standing planned entries are re-armed once (B4, 2026-10-10) | the label suites' literals, the composer's and the page's fixtures, the token pins |
| C33 | The fork's eighth patch, Kotlin: the icon colour is packed by `NotificationSettings.packArgb` instead of the float `Color.argb` overload (API 26; `minSdk` 24 — every `Alarm.set` naming a colour crashed on Android 7.0 and 7.1) (2026-10-10) | `NotificationSettingsTest.kt`; the Patch 8 group of `alarm_fork_test.dart` |
| C34 | The fork's ninth patch, Dart: `_checkAlarm` leaves a stored alarm that is past due and silent alone while the host reports another one sounding — the service's queue holds it and promotes it when the ring ends, where an isolate started more than 30 s late used to stop it (2026-10-10) | the Patch 9 group of `alarm_check_test.dart`; the Patch 9 group of `alarm_fork_test.dart` |
| C36 | While the gateway reports any ring in progress, a scheduling pass keeps every row past its instant in flight, whatever its lateness (`_settlePastFires`): the 30-minute band alone settled a held alarm as `fired` and cancelled its entry out of the service's queue (2026-10-10, from step 2's review) | "an alarm held back behind another ring is in flight past the grace" and its mirror in `alert_scheduler_test.dart` |
| C37 | A scheduling pass never cancels an entry whose registry row is `fired` unless the pass settled that row itself: such an entry is a ring the binding has not announced yet or a native snooze whose move has not been drained — before, a Snooze on the heads-up that landed while a pass was out (the launch pass that re-arms every planned entry when the token moves, a `resumed` pass, a sibling ring's pass) was cancelled by that pass's OS-entries loop, the move then met a `cancelled` row and was acknowledged, and the snooze never rang (the final review's must-fix, 2026-10-10) | "a Snooze on the heads-up while a pass is out is left to the next pass, which writes it down" in `alert_scheduler_test.dart`; `AlertRegistrationDao.firedOsIds` |
| C38 | A planned fire never lands on the id of a ringing or `fired` row, and the in-flight guard asks the gateway whether the id rings before it asks for a registration: a ring's row is `fired`, so a plan that moved the ringing occurrence later used to re-arm over the ring under the same id, which the binding read as a Stop on the notification (chip, A3's removal, nobody answering) — and, through `Alarm.set`, over a native snooze whose move a pass had not drained; the moved occurrence is now armed under an id of its own (`_assignOsIds` treats ringing and fired ids as taken, the fired ids read at most once a pass) and the ring is left to its handler (2026-10-10) | the group "an occurrence moved later while it rings" in `alert_scheduler_test.dart`, with its fired-but-silent case, its over-ring mirror and a statement-count pin on the fired read |
| C39 | The late band's delivery evidence counts a process that came up within `kRingStartGrace` (30 s, the plugin's own ring-start grace) after the instant as started by the delivery: a Stop on the heads-up with no engine, in the process the alarm's own broadcast started, used to leave the row `pending` and the first pass 30 minutes later marked it `missed` and posted a Missed notice for a ring the user stopped (2026-10-10; the full cure, a STOPPED host event in the fork, is not built) | "a process the alarm itself started proves it rang too" and "a process that came up past the delivery window proves nothing" in `alert_scheduler_test.dart` |
| C40 | `PendingNavigationQueue.enqueue` replaces a queued intent in place (its place kept, no notification) when the newcomer is a ring's page or of the queued intent's own kind: a re-ring after a native Snooze, with the app paused and the first `OpenAlarmIntent` still queued, used to open the page with the first ring's payload — the old time, no "Snoozed" eyebrow — although the binding held the restamped one; the double-delivery echo rule is unchanged, and a tap for the same id never displaces a waiting page, since only alarm intents are routed while anything rings (2026-10-10) | `pending_navigation_test.dart`: the flipped pin, the re-ring case, the echo case, "a tap under a waiting ring's id never takes its page's place" |
| C41 | An unanswered ring's Silence-after window counts from when the host sounds it: a held alarm the fork's fallback timer announces (foreground only, Patch 7 keeps it on purpose) gets no window while the host reports another alarm sounding, is re-asked at every ring emission and at its own expiry, and is stopped only after a full window of audible time — before, its window ran in the host's queue and the promoted ring was silenced after what was left of it and settled `timedOut`, a Missed for an alarm audible for seconds (`alertSilenceWindowRuns`, pure, says only what the two answers mean; the binding asks the host "is anything sounding" first and "is this one sounding" second, so a promotion landing between the two reads as a window, and asks again when the ringing set was emitted while it was asking — `_heldRings`, `_ringingEmissions`; a thrown host query answers "runs", so a host that cannot answer gets the window of before) (2026-10-10) | the pure group "the silence window" in `android_alert_gateway_test.dart`; the source guard `test/android/alert_silence_window_test.dart` (the query order and the re-ask among its six pins) |
| C42 | `AlertRingController.stop()` and `snooze()` end with the `_disposed` guard `keep()` and `load()` already carry: a ring that ended elsewhere while the page's Stop or Snooze waited on the scheduler's chain closed the page and disposed the controller, and the in-flight call then notified a disposed notifier (a `FlutterError` in debug and profile builds) (2026-10-10) | "a ring that ends elsewhere while Stop or Snooze is out" in `alert_ring_controller_test.dart` |
| C35 | German and Romanian name the reminder tier once: the channel, its description and the notifications permission's line take the tier word ("Mitteilungen", "Notificări"); the tier word itself stays — "Erinnerung" is the app's German umbrella word for an alert, and the neuter "Memento" would break the gender agreement of the shared `alertsOutcomeSnoozed` (2026-10-10) | `test/l10n/reminder_word_test.dart` |

## 5. Facts from the tree

- **Page:** `lib/pages/alarm_page.dart` (333 lines) — `_close` `:116-121`,
  `_stop` / `_snooze` `:123-131`, `_openEvent` `:136-149`, `_openDatabase`
  `:151-166`, `build` `:169-320`, `_dayLabel` `:327-332`. Single push site
  `lib/main.dart:499-503`.
- **Controller:** `lib/controllers/alert_ring_controller.dart` — `load`
  `:77-87`, `stop` `:116-132`, `snooze` `:136-151`, `keep` `:159-171` (sets
  the flag before the upsert), `unlock` `:183-186`, `activateDatabase`
  `:190-199`, `_resolveEvent` `:217-229`.
- **Calendar side of Keep:** `lib/services/calendar_event_service.dart:107`
  (`upsert` tells nobody); `lib/pages/calendar_page.dart:456-478` (the
  notices it listens to), `:536-551`; `lib/services/alert_skip_notice.dart`
  and `alert_removal_notice.dart` (the notice shape).
- **Cover:** `lib/widgets/lock_screen_curtain.dart:72-89` (`surface` at
  `:85`); state `lib/services/lock_screen_state.dart`.
- **Kit:** `lib/widgets/form_rows.dart` — `FormRowGroup` `:22-69`,
  `FormSectionLabel` `:199-249`, `FormHeaderTextButton` `:423-456`,
  `FormActionRow` `:1416-1472`, `FormCaptionSlot` `:2245-2274`. The row to
  hoist: `_TitleRow`, `lib/widgets/event_detail_sheet.dart:890-952`
  (`caption` is required there and it builds its own avatar). `EventAvatar`:
  `lib/widgets/event_avatar.dart:3-24` (20 / 24 / 0.16).
- **Tokens:** `lib/constants/form_metrics.dart`, `row_metrics.dart`,
  `app_colors.dart:81-98` (`SurfaceRoles`), `app_theme.dart`.
- **Payload:** `lib/models/alert_payload.dart` — fields `:51-110`,
  `iconColorValue` `:152-157`, codec `:190-281`, `props` `:284-301`.
- **Scheduler:** `lib/services/alert_scheduler.dart` — signature `:82-91`,
  fast path `:953-966` (compares `osId`, `fireAt` and the `backend` text),
  `_snooze` `:1315-1463` (the rebuild from a payload `:1376-1394`, the
  snooze's payload `:1431-1436`), `_payloadFor` `:1467-1493`,
  `_payloadForRow` `:1495-1525`, the time label `:1536-1540`, test alarm
  `:722-808`.
- **Gateway:** `lib/services/android_alert_gateway.dart` — the isolate
  handler `:126-183`, `_reminderDetails` `:195-229`, `alertGatewayStrings`
  `:236-255`, ring reports `:461-475` and `:583-600`, `_handleAlarmEvent`
  `:482-495`, `_handleResponse` `:681-725`, decor `:732-811`,
  `refreshArmContext` `:863-872`, `_armNotice` `:896-928`, `_noticeDetails`
  `:936-965`, `_scheduleAlarm` `:967-1034`, `_scheduleNotification`
  `:1036-1070`, `_alarmFallbackDetails` `:1072-1107`, `cancel` `:1121-1139`,
  `showMissed` `:1182-1213`, `showSessionChip` `:1354-1389`. Nothing in it is
  reachable from a test (`:267-269`).
- **Native:** `android/app/src/main/kotlin/com/alexzamfir/anta/SessionChip.kt:62-126`
  (actions at `:103-104`); the fork's
  `packages/alarm/android/src/main/kotlin/com/gdelataillade/alarm/services/NotificationService.kt:71-172`
  (untouched by Slices 1–4).
- **Formatter:** `lib/services/event_time_formatter.dart` — the neutral
  skeleton `:57-65`, `:89-95`; the context-aware forms `:36-55`, `:67-73`.
- **Tests:** `test/widgets/alarm_page_test.dart` (26 cases through
  `test/widgets/support/alarm_page_robot.dart` and `alarm_page_fakes.dart`),
  `test/widgets/lock_screen_curtain_test.dart`,
  `test/services/android_alert_gateway_test.dart` (the pure half),
  `test/services/alert_scheduler_test.dart`, `test/models/alert_payload_test.dart`,
  `test/services/session_chip_test.dart`, `test/widgets/form_rows_test.dart`.
- **Device:** `tool/qa/fixtures/alerts.json` (three events two minutes
  apart, the notice off), `tool/qa/flows/alerts/00–02`, `{{minute+N}}` /
  `{{minuteday+N}}` in `tool/qa/src/placeholders.dart`.

**To retire:** the page's nine `AppSpacing` reads and seven literals; its
`CircleAvatar`; the `ActionChip`; `OutlinedButton` on the page; the 64 px /
0.18 / 38 px icon literals in the gateway; the ARB keys of §3.4 and §3.5.

## 6. Slices

| # | Holds | Tests |
| --- | --- | --- |
| **0** | **The safety net.** `AlarmPageRobot` and its fakes; the page suite through the robot with eleven new pins (two of them defects, named so); `{{minute+N}}` / `{{minuteday+N}}`; `tool/qa/fixtures/alerts.json` with its suite; flows `alerts/00_test_alarm`, `01_event_alarm`, `02_remove_after`. Nothing under `lib/`. | green on the old page |
| **1** | **Facts.** The payload fields and codec (all but `iconFile`'s stamping); `AlertLabels` — `whenLabel` in the phone's style, `timeLabel` still on today's neutral skeleton; scheduler stamping; the snooze copy; `ringReportPayload` and the gateway's record of snooze moves; the test ring's tint, glyph and empty `whenLabel`; `props`; the ARB key `alertsWhenOnDay`. Also the plugin's log output printed: `logging` added to `pubspec.yaml`, one `Logger.root.onRecord` listener (WARNING and above, through `debugPrint`) set in `AndroidAlertGateway._initialize` before `Alarm.init()`. **No arm token and no visible change.** | codec (old payloads decode to today's behaviour), scheduler stamping, the labels, the snooze copy's exact list of restamped fields, the ring-report rule |
| **2** | **The page and the cover.** `AlarmMetrics`; `FormReadTitleRow` hoisted (the detail sheet adopts it); `FormHeaderTextButton(semanticsLabel:)`; `FormActionRow`'s disabled announcement; `AlarmGround`; the page; the controller's corrections (C3, C4, C7) with their seams; the cover's ground; the page's ARB keys; `SemanticsIds`. `alarm_page_fakes.dart`: the scripted controller's database is unknown until `resolveDatabase(name)`; `holdKeep()` / `releaseKeep({required bool ok})`; `holdUnlock()` / `releaseUnlock()`. The robot is rewritten (its surface gains a 24 dp top and bottom `viewPadding`), test bodies change only where §4.2 says, the suite's header paragraph on clearance is rewritten; flows 00–02 updated; `tool/qa/fixtures/alerts_pair.json` (two Alarm-tier events in one minute) with its suite and flow `alerts_pair/00_two_in_a_minute`. | every state; the matrix — en / de / ro × 1.0 / 1.3 / 2.0 × 360 × 780 and 412 × 915 × light / dark, plus one 780 × 360 cell — each cell asserting `takeException()` null, Stop and Snooze inside the surface and at least 48 dp tall, and at rest the Open row inside the scroll region; the rect-stability case; own-route close; `form_rows_test`: the read title row (one merged node with the avatar excluded, both heights, a long title wrapping at 360 dp and scale 2.0, hairline indent 70), the text button's accessible name, the action row's disabled node |
| **3** | **One grammar.** The content module, first pinned to today's strings, then changed; the details functions; the icon file and `iconFile`; `snoozedRepost` and the isolate; Missed; the notice (shot from `qa relaunch --fresh --seed tool/qa/fixtures/alerts.json --setting alert_notice_lead_minutes=1`); the ring's text; the chip (Dart and `SessionChip.kt`); `showSystemUI`; `timeLabel` in the phone's style; `alertArmContext` and the token; the notification ARB keys and the retired ones. Shade evidence for every kind. | content per kind and language; details per kind (silent, `when`, colour, large icon, action ids and order); the re-post; the token; the chip's arguments |
| **4** | **Grouping, as D20 settles it** (§3.7): the channel `alerts_quiet` with its two ARB keys, and the notice, Missed and the chip on it; the SDK level read once through the alerts channel; the group key on the reminder and both re-posts on Android 16 and above; the payload's `grouped`; the token's content version `g2` → `g3`. | the details functions per channel and per SDK level; `snoozedRepost` with and without `grouped`; the codec; `alertArmContext`; the chip's channel argument; the five readings of §3.7 on the emulator |
| **5** | **The debt** (D19): `cancel` clears its ring maps; the fork's `AlarmReceiver` not exported; the wake lock held in a field and released; the fork's CHANGELOG for Patches 3 and 4 and the new ones; `tool/upstream/alarm_pr.sh`'s header says what `AlarmService.kt` now carries; stale comments. | a source guard for the manifest line; a Kotlin test for the lock holder; the emulator: a ring, and Stop and Snooze on the notification with the process dead |
| **6** | **Device pass, review, docs.** The matrix on the emulator, the PIN-keyguard recipe, an independent review, and the documents: this record, both masters (decision 7; the stale Tier 3 lines), `COPILOT_CONTEXT.md`, `CLAUDE.md` (the fork paragraph, this record in the docs row, `qa flows alerts`), the `calendar-events` and `ui-language` skills (the idiom table's fourth row), `qa-emulator` (the alerts pass), OS roadmap §2 (the new patches) and §13.3. **Done in part** — the review, its fix batches and the documents; the device pass is deferred (§8, the ledger). | — |

## 7. Definition of done

As of 2026-10-10 items 1 to 8 hold on the final tree by the suites; items 9
and 10 were seen on the final build in the device pass of that day (the
ledger's row), with one reading not re-staged — the first pass over entries
armed by the previous build, which every fresh seed of the pass replaced:
the `g3` → `g4` re-arm is the mechanism seen for `g2` → `g3` on 2026-10-05
and the suites pin the token; item 11 holds but for
`calendar/19_fasting_schedule` (§8), with 20–22 green from a fresh calendar.

1. Stop, Snooze, Keep, Open event and the database switch do what they did
   (§4.1), through the suite's scripted controller and, where the QA build
   can stage it, on the emulator.
2. Every control is reachable one-handed on a 360-wide phone with a 48 dp
   target; Snooze is the control on the bottom edge.
3. Light and dark; en, de and ro; text scale 1.0, 1.3 and 2.0; 360 × 780 and
   412 × 915 (the matrix's sizes — the emulator shows 427 × 952 and
   `--phone` 360 × 800): no overflow and no clipped label.
4. A 360 dp-high window (the 780 × 360 cell) scrolls and never overflows.
5. Nothing in the dock moves between states (the rect case).
6. No number on the page is a literal or an `AppSpacing` read; nothing on
   the retire list is referenced (grep).
7. Every string is in all three ARBs; `untranslated.txt` is `{}`.
8. The eyebrow carries `header` and `namesRoute` (a semantics case); the
   title row is one node; ids as in §3.1.
9. The emulator shows: the heads-up over bare ground with eyebrow, time, day
   and title all visible at 1.0; dark status icons on the light page pushed
   from Calendar settings; no light band under the dark page; on a
   PIN-locked cold start the page above the keyguard and, after Stop, the
   lock screen (that cover and page share one ground is C11's theme case);
   German at 2.0 on `--phone` with the title whole at rest, both dock labels
   on one line and `qa errors` clean; a removable alarm kept and its row on
   the calendar saying so; two alarms in one minute with the second page
   stoppable.
10. `dumpsys notification --noredact` shows every kind but the dormant
    fallback (the composer's suite covers that one) with the title, text and
    action order of §3.5; a reminder snoozed with the process dead comes
    back with its colour, its icon and German buttons on an English phone;
    the first pass after the token re-arms every planned entry once and a
    second launch re-arms nothing; no ring in progress is cut by a re-arm —
    seen with `qa set locale=de` while a test ring is up, then a resume.
11. The suites of every surface touched pass unchanged where behaviour did
    not change; `flutter test` whole, `qa flows alerts` and `qa flows
    calendar` green.

## 8. Deferred and left alone

- **A swipe on the ring notification is a Stop** (the fork's default): it
  changes what a gesture does, so it is the owner's.
- **The ring notification cannot say "snoozed"**, and a ring snoozed on it
  whose second ring cold-starts the app shows its first time on the page
  (the warm case — the app paused with the first ring's intent still queued
  — shows the restamped time and "Snoozed" since C40).
- **The fork channel's English name** ("Alarm Notification") and its
  placeholder title: a fork patch for a string in system settings.
- **An excerpt on the ring heads-up** (a Kotlin-only patch that splits a
  two-line body): the one fork patch worth revisiting, for the phone-in-use
  case where the heads-up is the only ring surface.
- **A tier-specific small icon; a standing "Snoozed" notification with a
  countdown; the chip counting down to the event's end.**
- **A summary with a keeper for the reminders** (D17): it buys back about
  2.7 s of heads-up for a reminder that fires beside another, at the price of
  a keeper in two isolates and a summary that can strand. Its readings are in
  §3.7 (rule 6).
- **A default-importance channel with no sound for the quiet kinds**, which
  would keep Missed and the chip on a lock screen that hides silent
  notifications: it needs the silent flag off all three (with it kept the
  platform's summary beeped once), puts them back in the reminders' section,
  and one of its readings was never taken with the chip's flag removed.
- **The group key below Android 16**: how a summary-less child is drawn
  there was not run, and nothing is bundled by force there.
- **A confirm with a cancel before the database switch**: the better flow,
  on a state that cannot be staged.
- **A reconcile on the language change itself**: the re-arm waits for the
  next resume, launch or edit.
- **"Event removed · Undo" raised while the page is still on top**, and the
  snackbar layer as a whole (an open app-wide owner call).
- **The launch window** before Flutter's first frame follows the phone's
  night mode, not the app's theme.
- **The avatar's contrast on dark**, which is `EventAvatar`'s app-wide rule.
- **The reminder channel's name** carrying five kinds.
- **Dark navigation buttons on the dark page of a light-mode phone**
  (`#666666`, about 3.2:1): Android forces them on a window whose Android
  theme is light. The cure is under `android/` and belongs to the app-wide
  bar decision.
- **Open event on the upper of two stacked alarm pages opens the calendar
  over the other ring's page** while that alarm still sounds (seen in Slice
  2): `_openEvent` navigates directly instead of through the queue that holds
  navigation during a ring. It needs two alarms in one minute and a "day
  only" form of the queued intent.
- **`calendar/19_fasting_schedule` fails on the 952 dp emulator** at step 17
  (`fasting-extra-days` is below the fold there; the flow was only ever run
  on the 874 dp simulator, and `scroll-to id:fasting-extra-days` passes by
  hand). Tier 3's flow, not this rework's.
- **Other `rootPushInstant` routes scope no route** for a screen reader
  either; the alarm page now scopes its own.
- **Owner decisions of §13.3:** what unlocking after Stop lands on, API
  24–26 (the lock-screen flags need API 27: a fallback nobody can verify
  here, or `minSdk` 27) and `Alarm.init()`'s re-arm — all three still open.
  Patch 8 (C33) settles a different fault on API 24 and 25, the float
  `Color.argb` call that crashed every `Alarm.set` on Android 7.0 and 7.1;
  `minSdk` stays 24.
- **Not stageable on the QA build:** another database's alarm — widget tests
  only.

### Deferred on 2026-10-05 at the owner's call (usage)

Everything below was planned for Slice 6 and not run. Each entry is written
to be resumed from this file alone.

**The rest of batch B — done 2026-10-10** (the ledger's "close, step 1" row
says what each became): B4 is C32 and the token is `~g4`; B5 (a)–(f), B6, B7,
B9 and B10 are in the suites, the flows and their headers; B8 is the script's
own refusal (`tool/upstream/alarm_pr.sh` exits 1 with one line to stderr
before it clones or writes anything when a run is not `--dry-run` while the
fork's `AlarmService.kt` carries `RingWakeLock` or a "Patch 5)" / "Patch 6)"
mention — proven with stubbed `gh` and `git` on the PATH; whoever gives Patch
6 its own commit and paragraph takes the check out too); the pins B1 and B2
would have added are `test/l10n/alert_removal_verb_test.dart` and the eyebrow
literals of `alarm_page_test.dart`, with a Romanian case. B10's new shot is
read in the device pass below.

**A second review pass over the ring lifecycle — done 2026-10-10** as the
first lens of the final review (the ledger's "Close — the final review" row):
the walk it asked for found four more defects on that path, all confirmed
by a skeptic and fixed (C37 to C42).

**The final device pass of Slice 6 — done 2026-10-10** on the final build,
by its six points (the ledger's "Close — the device pass" row has the
evidence): the three flow sets green; the 72-cell matrix on 427 × 952 and
360 × 800 with no overflow and no clipped label; the PIN keyguard recipe
whole, C21 and C24 included; every notification kind read from the shade
with the words and the order of §3.5; the 360 dp readings, the day-ahead
reminder among them. **Still owed, not stageable on this emulator:** Android
below 16 (the group key without the forced bundling; C27's hand-back on 10
to 14), a clean install (C29's silent `alerts_quiet` — the emulator's
channel predates it), a 24-hour phone (de and ro rendered 24-hour through
Material's rule on this 12-hour image), the phone's own font scale on
notification buttons (`qa set text-scale` scales the app only), the
promoted chip (this image grants no promotion), and a real phone of any
make.

**Found by the review; decided by the owner on 2026-10-10 ("no tech debt")
and done the same day — the ledger's step 2 row:**

- **Android 7.0 and 7.1: every `Alarm.set` crashes** (shipped behaviour, not
  this rework's). The fork's `NotificationSettings.kt` builds the icon
  colour with `Color.argb(float, float, float, float)`, an API 26 overload,
  and the app's `minSdk` is 24. Either raise `minSdk` to 26 or above (27
  also settles the lock-screen flags of §13.3), or one more fork patch with
  the int overload. **Done as Patch 8 (C33)**: a pure `packArgb` in the fork's
  `NotificationSettings` companion with the platform overload's own rounding,
  bit-identical on API 26 and above and pinned on the JVM — where the int
  overload answers 0 under `returnDefaultValues`; `minSdk` stays 24.
- **A held alarm can be dropped after 30 s** (shipped behaviour). When a
  second alarm comes due while one sounds, the fork queues it and tells Dart
  nothing. An isolate that starts more than 30 s later — ANTA opened from
  the heads-up — runs `Alarm.init()`, whose `_checkAlarm` finds a stored
  alarm past due and "not ringing" and stops it: it never rings, and its row
  is later settled as fired or Missed. The cure is in the fork's
  `_checkAlarm` (`packages/alarm/lib/alarm.dart`): do not stop a past-due
  alarm that is not sounding while the host reports another one sounding;
  pin it beside `packages/alarm/test/alarm_check_test.dart`. **Done as Patch
  9 (C34)**, pinned there and in `alarm_fork_test.dart`. The app's side was
  then traced: inside its in-flight band, `kLateFireGrace` (30 minutes),
  `_reconcile` keeps the held row `pending` and its entry untouched, and a
  promotion is accepted as any ring; but past 30 minutes of one unattended
  native ring the band alone settled the row as `fired` — the host runs in
  the app's process, so the process was alive at the held alarm's instant —
  and the pass cancelled the entry out of the service's queue: a silent
  drop the hub recorded as rang. **Closed by C36**, the app-side twin: while
  the gateway reports any ring in progress, `_settlePastFires` keeps every
  late row in flight; a late row is settled by the first pass with nothing
  ringing.
- **German and Romanian call a reminder two things.** The tier word printed
  on a reminder's notification is `eventAlertModeNotify` — "Mitteilung" /
  "Notificare", so the line reads "notification · 18:00" on a notification —
  while its channel is "Erinnerungen" / "Mementouri"; English says Reminder
  and Reminders. Settling the tier word ("Erinnerung" / "Memento") reaches
  the editor's and the hub's strings; renaming the channel is the smaller
  move. **Done the smaller way (C35)**, for a reason the review had not seen:
  German's "Erinnerung" is the app's umbrella word for an alert
  (`eventAlert`, `alertsTitle`, `alertsDefaultNone`…), and Romanian's
  "memento" is neuter where `alertsOutcomeSnoozed` "Amânată" agrees with the
  feminine "alarmă" and "notificare" on the hub, the re-post and the eyebrow.
  The channel, its description and `alertsNotificationsDesc` now say
  "Mitteilungen" / "Notificări"; the strings that quote Android's own name for
  the exact-alarm permission ("Wecker & Erinnerungen", "Alarme și mementouri")
  stay. The gateway re-creates the channel at every start and the platform's
  `createNotificationChannel` renames an existing one (its importance it
  keeps), so the rename reaches existing installs without the token moving.

**Known and left, from the same review:**

- A Keep taken while the detail-sheet trip's quick description sheet or
  dates picker is open is still written back by their Done; and with two
  calendars stacked, a warm Open event is answered by the older one, which
  opens a second sheet (the shipped `_serveOccurrenceRequest`).
- A sheet left open under the ring is not redrawn by Keep, and Open event
  lands back on it.
- With two alarm pages stacked and a calendar route live, Open event on the
  page in front **pops** the other ring's page (the collapse onto the
  calendar) rather than covering it — the entry above describes only the
  branch with no calendar open.
- A reminder armed loose is not re-armed into the group when the phone moves
  to Android 16 (the arm token does not name the group shape) until it rolls
  over or its event is edited.
- A change of the phone's 12/24-hour setting reaches a running process only
  with a configuration change or a launch, not with a plain resume; the
  re-arm C15 promises waits for it.
- Patch 7 gives up in one triple fault it used to announce: a native stop
  that failed, then a re-set, then a ring the platform never reports.
- The gateway's `_initialize` still stops at a channel call that throws,
  before `Alarm.init()` (the shipped shape, one more call in it).
- Renaming the open database with no restart is still offered in Settings,
  and any other caller of `AppDatabase.getInstance()` then carries the
  switch out under the running app; the alert pass no longer does (C28).
- The emulator's `alerts_quiet` predates C29 and keeps the plugin's default
  sound and vibration (inert at low importance); a phone that first runs
  this build gets the silent one. Avatars drawn under the old file names
  stay beside the new ones.
- A held alarm rings when the ring in front of it ends, however late that is
  (the service's promotion reads only whether the delivery is current; its
  stale-after rule is the boot receiver's), and its Silence-after window
  counts from then (C41). While any ring is in progress a pass settles no
  late row at all (C36) — a reminder a day old or a genuinely missed alarm
  waits for the first pass with nothing ringing: a delay, never a loss. With
  the app in front the fallback timer still announces a held alarm at its
  own instant, so two pages stack (the pair flow); a process death before
  the promotion leaves that alarm's row `fired` (read as rang in Recent)
  rather than `pending`.
- A `fired` row's entry is never swept by a pass (C37): the stored alarm of
  a ring the process died under, spared at init because another alarm
  sounded or the restart came within 30 s, is left to the plugin's next
  `checkAlarm` or the seven-day sweep, and its row reads rang in Recent
  rather than cancelled; a reboot inside 30 minutes of its instant lets the
  fork's boot receiver ring it, as that roadmap already accepts.
- A planned fire whose occurrence is ringing is armed under an id of its own
  (C38), so one alert, day and kind can briefly hold two rows — the ring's
  `fired` one and the moved occurrence's `pending` one — until the ring's
  handler settles the first; every `fired` row's id is kept from fresh fires
  until the seven-day sweep, which only moves a probe along.
- A tap for an id whose ring intent still waits — a Missed notification for
  a ring that ended while the app was paused — is dropped, as before C40:
  the queue cannot tell a live ring from one that ended, and a ring's page
  must never be displaced by a tap. A Missed notification is cancelled
  nowhere, so one for an id re-armed the same day stays on the shade beside
  the new ring's (taking it down at the re-arm was weighed and left: a
  platform round trip per armed alarm, and a new rule for every re-arm
  under an id).
- Two silence askings that finish out of order can leave a held mark beside
  a live timer; the next emission re-bases the window — longer, never
  missing. A ring whose window started while the host could not answer and
  that is promoted exactly between `_silence`'s two reads would be stopped
  as it starts to sound: a failed host query and a sub-millisecond race
  together.
- Entries the scheduler never re-arms — standing snoozes, another database's —
  keep the old "time, day" order until they fire (§3.6, "old payloads live
  for good").
- A screen reader speaks the caption's " · " on a day-ahead alarm as it does
  in every other string that carries it; only the page's eyebrow trades it
  for a comma (`alarm_page.dart`).
- The light-theme case of the page's test-ring avatar cannot tell the app's
  primary from Flutter's default (both `0xFF6750A4`); the dark case beside it
  is the one that discriminates.

## 9. Ledger

| Slice | State | Notes |
| --- | --- | --- |
| Close (2026-10-10) — the device pass | done 2026-10-10 | One Opus agent on `emulator-5554` (API 36, build BE2A.250530.026.D1, en-US, 12-hour), `ANTA_QA_VIA=agent`, the final build installed by `qa run`; nothing written into the tree. **(1)** `qa flows alerts` 3/3 (4 min 28 s), `alerts_pair` 1/1, `calendar` 19/23 then 20–22 green from a fresh calendar (19 at step 17 as §8 says); `qa errors` clean after every stage; flow 01's new shot is the alarm page — eyebrow, 12:49 PM, the day, "Leg day" with its caption and excerpt, Open event, Stop, Snooze — under the colorized heads-up. **(2)** 72 cells — a remove-after alarm with every optional row (a scratchpad variant of "Tea timer" with an end and a description: the stock one has no caption, its time being the due minute, and no excerpt) and a test ring, light and dark × en / de / ro × 1.0 / 1.3 / 2.0, on 427 × 952 and on 360 × 800 (no phone-sized AVD was usable, so `qa boot --phone -d emulator-5554`, which on an attached emulator only sets `wm size 1080x2400`, reset with `qa unphone`): from the dump rects Stop 64 dp and Snooze 56 dp in every cell, both dock labels on one line, Snooze 12 dp above the navigation bar, the title whole at rest including German at 2.0 on 360 (Romanian "Deschide evenimentul" and "Alarmă de test" wrap to two lines there, the German remove caption to three — wrapping, not clipping); the only cuts are the ones the spec names (the excerpt's ellipsis; the eyebrow and day under the heads-up at 1.3–2.0 on 360); light status icons and no band in dark; the dock rects identical before and after Keep; contact sheets under `build/qa/devpass/`. **(3)** A PIN set, the process killed with `run-as kill -9`, the screen off: the ring started a new process (`FSI allowed: device is not interactive`), the page stood above the keyguard with no Recents button (`isKeyguardShowing=true`, `mKeyguardOccluded=true`), Stop gave the lock screen back; Open event asked for the PIN over the page (the shot is black, as the skill says) and landed on the detail sheet with the ring gone; a reminder behind the keyguard posted and sounded (`notification_alert … 1,1`, the attention state naming it, `g:anta.alerts`, `PEEK suppressed: device not in use`); C24 — Keep on the locked page, the notification's Snooze pressed from the shade (a locked phone gets the full-screen intent, never a heads-up), the re-ring read ALARM · SNOOZED with the moved time and "The event will be kept" with Keep disabled from its first read; C21 — `qa attach`, `getIt<AlertGateway>().cancel(id)` evaluated while the id rang: the page closed by itself, the keyguard came back, no chip and no ring record left, `ringingIds` empty, the event still on the calendar with its remove-after flag. The keyguard put back (`locksettings clear --old 1234`, `set-disabled true`, `get-disabled` → `true`). **(4)** From `dumpsys notification --noredact`: the ring on the plugin's channel, colorized, "Tea timer / Alarm · 12:51 PM", Stop · Snooze 5 min; the reminder on `alerts_reminder`, `g:anta.alerts`, no `SILENT`, "Stretch / Reminder · 12:53 PM – 1:08 PM" with the excerpt under it when expanded, the 144 px avatar, Done · Snooze 5 min, `1,1` and `PEEK allowed` beside a standing chip; the snoozed re-post made in German with the process dead — "Geschlummert · 13:41 – 13:56", the tint, the avatar, Erledigt · 5 Min. schlummern, sounding; the notice on `alerts_quiet` (importance 2, `SILENT`), "Leg day / Alarm at 1:28 PM", Skip · Open, gone at the alarm's instant; Missed on `alerts_quiet`, no actions, "Missed · 1:28 PM" with `when` at the due instant; the chip on `alerts_quiet` with its chronometer, "Until 1:49 PM" with Done · Open note and "Session in progress" with Done · Open event, in German "Bis 14:37" / "Einheit läuft"; no `notification_alert` line for any quiet kind. **(5)** At 360 dp the one-line row shows "Reminder · 1:32 PM – 1:…" (the end time cut) in English and "Mitteilung · 13:41 – 13:56" whole in German; the German re-post's heads-up cuts its end time; the day-ahead reminder, staged through the editor with the "1 day before" preset, reads "Reminder · Sun, Oct 11 · …" — **the day survives the cut** and the whole range shows expanded; the Romanian chip's "Gata · Deschide evenimentul" both whole, a Romanian reminder "Notificare · 14:03 – 14:18" whole. **Also seen:** C41 — the pair with a one-minute window and nobody answering: the held alarm queued at 14:05:00.1, announced by the fallback timer at +0.7 s (two pages, as documented), promoted at 14:06:00.1 when the first timed out, stopped at 14:07:00.2 — 60.1 s after its promotion, not seconds — one Missed each; Patch 9 / C36 — the process killed before the minute, the ring started a fresh process with the second alarm queued, ANTA opened from the sticky heads-up at 58 s (`reconcile(launch) … cancelled=0`), and on Stop the queued alarm was promoted and rang with its own page. **Not seen, owed:** §8's device list. **Put back:** no ANTA notification standing, `wm size` reset, the keyguard disabled on both emulators, `basic.json` re-seeded (`planned=0`, no ANTA entry in `dumpsys alarm`), the app up, the agent's own run killed; `emulator-5556` untouched. Staging facts for the skill: a locked phone gets the full-screen intent and no heads-up; `qa boot --phone` on an attached emulator is a `wm size` override; the agent's taps are not user activity, so the locked screen sleeps ten seconds after Stop. |
| Close (2026-10-10) — the final review | done 2026-10-10 | One multi-agent review, after the code items and before the device pass, so the device pass runs on the final code. Four fresh read-only lenses (Fable, one each): (a) the ring lifecycle end to end, by ending and by beginning, across the fork's Kotlin, the plugin's Dart, the binding, `main.dart`, the scheduler and the page; (b) everything the close changed, `git diff 0c65424` plus the new files; (c) the fix batches of 2026-10-05 read together, batch against batch; (d) the documents against the tree. Fifteen findings, each handed to a skeptic briefed to refute it with evidence; none refuted. Seven in code, fixed in one round by one Opus implementer with a test watched failing first: **C37** the must-fix (a native Snooze landing while a pass is out was cancelled by that pass), **C38** (a plan that moved the ringing occurrence re-armed over the ring), **C39** (a heads-up Stop in the process the alarm started read as missed), **C40** (a re-ring's page carried the first ring's payload), **C41** (a held alarm's silence window ran before it sounded; the lens's note about the fallback timer announcing a held alarm is answered by the same change, with the two-page behaviour of the pair kept), **C42** (Stop and Snooze notified a disposed controller). Eight in the documents, applied by the lead: the OS roadmap's risks row and its Patch 7 paragraph still counted seven patches and one Dart patch; the "API 24–26" owner item had been conflated with the Android 7.0/7.1 crash (API 24 and 25) — the item stays open, the crash is Patch 8's; §4.1's A-decision clause and A10's row now name what C34 and C36 change; the reminder-word suite holds nine umbrella keys, not eight; §0's commit-and-merge sentence is made true by the ledger's last row. Behaviour the fixes change beyond their findings is under "Known and left" (a `fired` row's entry left to the plugin's own sweep; a moved occurrence's second row; a replaced intent across kinds). The one fix reviewer (Fable, read-only; a fix gets one reviewer, not a second review pass) confirmed all six and found two should-fixes and two notes in them, applied by the same implementer with pins watched failing: C41's two host queries were asked "this one first", so a promotion landing between them read as held and the promoted ring got no window at all — now "anything first", with a re-ask when the ringing set was emitted during the asking (`_ringingEmissions`, the implementer's addition for the mirror race the swap opens); C40's replacement across kinds let a stale Missed tap displace a waiting ring's page — now only a ring's page or the same kind replaces; the diff loop also keeps every `fired` row's id from fresh fires (C38's second half); and the fired read is pinned to one statement a pass (the scheduler suite opens its database with `StatementCounter`). Weighed and left: taking a Missed notification down when its id is re-armed (a round trip per armed alarm, a new rule for every re-arm) — "Known and left". Gate after the round, run by the lead: analyzers clean (app and fork); `flutter test` 7,293 passed, 7 skipped, the one known failure; the fork's Dart suite 124 passed; `gen-l10n` clean, `untranslated.txt` `{}`. |
| Close (2026-10-10), step 2 — the owner's three items | done 2026-10-10 | The three items of §8's review block, decided by the owner in one line ("no tech debt"). **Patch 8** (C33): `packArgb` in the fork's `NotificationSettings` companion, bit-identical to the API 26 float overload it replaces, pinned by `NotificationSettingsTest.kt` (6, the two `fromWire` cases watched failing with "expected −10006364 but was 0") and the Patch 8 group of `alarm_fork_test.dart` (comments stripped before the text is searched, since the helper's own KDoc names the overload). **Patch 9** (C34): `_checkAlarm` asks the host whether any alarm rings before it stops a past-due silent one; the new `alarm_check_test.dart` group watched failing ("stopAlarm" among the host's calls), the Patch 9 group of `alarm_fork_test.dart` too. The app's side traced: in flight for `kLateFireGrace` (30 minutes), the row `pending` and the entry untouched (`_settlePastFires`, the `handled` seed of the OS-entries loop — the existing "five minutes late is in flight and left alone" case pins it), a promotion accepted as any ring. The review then showed the band's other side: past 30 minutes of one unattended native ring the row was settled `fired` (the host runs in the app's process, so the process was alive at the held alarm's instant) and the entry cancelled out of the queue — a silent drop recorded as rang. **C36**, the app-side twin, built in the review's fix round: `_settlePastFires` keeps a late row in flight while `AlertGateway.ringingIds` is not empty (the set is filled before the launch pass reads it, since `takeMoves()` awaits `initialize()`), pinned by "an alarm held back behind another ring is in flight past the grace" — watched failing, `Expected: 'pending' Actual: 'fired'` — and its mirror with nothing ringing. The review's notes applied with it: the Patch 9 question asked before the re-read that guards the stop, its log line and comments claiming only what Dart can know, a `FakeHost.anyRingingError` hook with the case "a host that cannot say if anything sounds gets the stop of before", the reminder-word suite's exemption set named `notTheTier` with its reason, the Romanian `alertsNotificationsDesc` naming the events' notifications, the three English `@` descriptions carrying the tier-word rule, the Patch 8 marker on one line. **C35**: the de/ro channel, its description and `alertsNotificationsDesc` take the tier word ("Mitteilungen", "Notificări"); the tier word itself stays, for the two reasons the block records; `test/l10n/reminder_word_test.dart` (8) holds ten tier-sense keys to the stem and nine umbrella keys off it, and trips when a new English string says "reminder" outside its sorted lists. The fork's CHANGELOG counts nine patches; `alarm_pr.sh`'s header names which are in no commit. Gate before the review: analyzers clean (app and fork); the fork's Dart suite 123 passed; Gradle 69 tests with the two known DataStore classes red and `NotificationSettingsTest` 6/6; `flutter test` 7,271 passed, 7 skipped, the one known failure. After the review's round: the fork's suite 124, the scheduler suite 98, the fork guard 13, the reminder-word suite 8, analyzers clean; the whole suite is run again by the final review's gate. One Opus implementer, one Opus reviewer (no must-fix; the should-fix above, built; nine notes, eight applied and one — the Patch 8 guard passing a contrived spelling the Kotlin suite would catch — left as it is). |
| Close (2026-10-10), step 1 — the rest of batch B | done 2026-10-10 | Resumed from §8 after the owner's "I installed it on my phone … finish it". **B4** (C32): `alertsDayThenWhen` in the three ARBs, `whenLabel` and the moved line's rescue lead with the day, `alertsWhenOnDay` narrowed to the notice, the token at `~g4` — every "{when}, {day}" literal moved (the record's list had missed `alert_labels_unloaded_test.dart`, the scheduler's day-before case and the composer's and the page's fixtures), one 12-hour case added. **B5** (a)–(f) as written, plus a second bare `0xFF6750A4` in the scheduler suite and a German day-ahead case that makes the group's `setUpAll` observable (its light-theme twin cannot discriminate: §8). **B6**: both label suites load Flutter's date tables for en, de and ro after `intl`'s; no literal moved on this machine (the tables agree on everything they format), the load proven live with a sentinel. **B7**, **B10** (flow 01 waits 3.5 s before its shot, as flow 00). **B8**: the script refuses a run that is not `--dry-run` while the fork's `AlarmService.kt` carries `RingWakeLock` or a "Patch 5)" / "Patch 6)" mention, one line to stderr, exit 1, before the file checks, `mktemp` and the clone (`grep -qsE`; `--help` prints the header by pattern) — proven with stub `gh` and `git` first on the PATH (exit 1, one line, no stub called) and one real `--dry-run` (three commits built in a temp clone, nothing pushed). **B9**: the Patch 7 guard (the wait before the `_isScheduledAs` question before the announcement, one `Alarm.alarmRang(`, the helper's body whole, `Equatable` with `dateTime` in `props`, no `operator ==`). **The B1/B2 pins**: `test/l10n/alert_removal_verb_test.dart` (4) and the eyebrow literals with `ALARMĂ · AMÂNATĂ`. Every pin watched failing — a temporary ARB, source or helper break, reverted, the diff empty afterwards. One Opus implementer, one Opus reviewer: no must-fix, two should-fixes that are the lead's (the documents, the device pass), twelve notes of which eight were applied by the implementer. Gate: analyzer clean; `flutter test` 7,258 passed, 7 skipped, the one known failure. |
| 6 — wording, documents | done 2026-10-05 | At the owner's call the short path: of batch B only the wording (B1, B2's four "@" descriptions, B3) with three comment sentences A2's reviewers had marked false; the documents brought in line with the tree by one agent with no review; this record's status, §4.2, §8 and ledger. Everything not run is under "Deferred on 2026-10-05" in §8. Final gate: analyzer clean, the fork's Dart too; 7,248 passed, 7 skipped, the one known failure; the fork's Dart suite 122 passed; `qa flows alerts` 3 / 3 on the final build, `qa errors` clean. |
| 6 — fix batch A2 | done 2026-10-05 | C24 to C27 and the start-only language read of C28: Stop decides the removal at the press; `load()` looks the event up before it notifies; the calendar's detail-sheet trip takes the flag from the bloc after a Keep; `AlarmGround` hands the bar back in the launch state. Gate, run independently: analyzer clean; 7,248 passed, 7 skipped, the one known failure; `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1; `qa flows calendar` — 19 fails at step 17 (§8), the other 22 pass, 20–22 on a second run. Review (three reviewers): one should-fix — with two calendars stacked only the older one counted a Keep — fixed with a pin watched failing; two comment notes applied with the wording. **Seen on the emulator:** a Keep on the page, a Snooze on the heads-up, and the re-ring reading "The event will be kept" with Keep disabled from its first read (the previous build read the claim); the write-back reproduced on the previous build with one calendar and with two stacked, gone on the new one; the window's appearance line identical before and after a test ring in both themes, 0 of 184,320 band pixels differing. Not seen: C25 and the start-only read (a write that fails, a start that fails — pins only); C27 below Android 15; C24 on a cold start or behind a PIN keyguard. |
| 6 — fix batch A1 | done 2026-10-05 | C23, the per-pass read of C28, C29, C30 (Patch 7) and text pins for the binding's own call sites. Gate, run independently: analyzer clean, the fork's Dart too; 7,224 passed, 7 skipped, the one known failure; the fork's Dart suite 116 → 122; the fork's Kotlin suite as before (eight classes green, the two known red); `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1. Review (three reviewers): no defect; two notes carried on (the start-only read → A2; a guard for Patch 7 in the app's suite → §8, B9). **Seen on the emulator:** on the previous build, the open database renamed and the app resumed — `Alert reconcile (resumed) failed … connection was closed!` and a note that no longer saved; on the new build neither, the edit read back after a relaunch. Patch 7 with the plugin timer's tick placed just after the due instant: 5 of 5 second announcements before (0.60 to 0.69 s after the first; no second page, the queue drops the echo, but the id left in the binding's ring set and the rows ending `missed`), 0 of 10 after. With Stop merely pressed fast, 0 of 5 either way: the tick usually runs after the platform's report (0.08 to 0.13 s after the due instant for a test ring). Not seen: C23 (a pass must be running as its alarm comes due — pins only); C29's channel (frozen as first created on this emulator). |
| 6 — the whole-change review | done 2026-10-05 | Eight fresh read-only reviewers, one lens each — the page and the kit; Keep and the controller; what each notification says; the payload and an update from the shipped build; the Kotlin and a release build; the three languages; the suites; other platforms, wiring and cost — and every actionable finding handed to a second reader briefed to refute it (two for a must-fix). 28 findings: 1 must-fix and 8 should-fix, all nine confirmed, and 19 notes. The must-fix: every scheduling pass re-resolved which database is active (C28). Fixed in batches A1 and A2 and, for two of the copy findings, the wording; the rest is §8. The ring-handling of Slice 6a was outside its lenses. |
| 6a | done 2026-10-05 | C21 (`AlertRingEndCause.cancelled`: reported by `cancel` only for a live ring it took out, after both backends are asked; `main.dart`'s settle an exhaustive switch with nothing in that arm; the page closes) and C22 (the binding's `_stopping` set); the three notes of Slice 5's review; the documents (`CLAUDE.md`, `COPILOT_CONTEXT.md`, four skills, both masters, both alerts roadmaps, the feature doc, the harness doc). Suites: `alert_ring_maps_test.dart` 4 → 9, `alert_ring_end_wiring_test.dart` (new), one page case. Gate, run independently: analyzer clean; 7,202 passed, 7 skipped, the one known failure; `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1. Review (three reviewers): one test-only should-fix (the settle's pin passed with `cancelled` stacked on another arm) and three document findings, fixed. **Seen on the emulator: C22 was no rare race** — on the Slice 5 build a Snooze on the sounding alarm's page beside a queued second alarm was announced a second time on the first try, its snooze row read `cancelled` and the chip was posted; after, announced once and the snooze armed. C21: a ringing remove-after alarm cancelled through the gateway — the page closed by itself, no chip, the event still there, a held intent went out. |
| 5 | done 2026-10-05 | `cancel` takes the id out of both ring maps before the platform is asked and lowers the keyguard flag only when that took the last ring out; the fork's `AlarmReceiver` not exported (**Patch 5**, a manifest attribute); the ring's wake lock held in `AlarmService.RingWakeLock` and released when the last ring ends, before it is taken again, and in `onDestroy` (**Patch 6**; nested in `AlarmService.kt` because the upstream script copies files by name and would not carry a new one); the fork's CHANGELOG for Patches 3 to 6; `tool/upstream/alarm_pr.sh`'s header; five comments made true (the A5 switch, `keep.xml`, the controller's note on the acknowledgement path, two "is exported" notes in the fork); the "already tracked" diagnostic printing only when the tracked ring names another instant. Suites: `RingWakeLockTest.kt` (8), `test/android/alarm_fork_test.dart` (6, the adapter's three pass-through lines among them), `test/android/alert_ring_maps_test.dart` (4), every pin watched failing. Gate, run independently: analyzer clean (the fork's Dart too); 7,192 passed, 7 skipped, the one known failure; the fork's Kotlin suite — eight classes green, the two known DataStore classes red; `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1. Review (three reviewers): no defect; one should-fix fixed test-only. **Seen on the emulator, with before-readings on the previous build:** the receiver `exported=true` → `false` (`cmd package query-receivers`; `dumpsys package` does not print it on this image) with rings still arriving from a dead process three times, Stop and Snooze on the heads-up with the process dead, the snoozed one ringing again five minutes later, and an alarm armed 3 s before its minute; the wake lock released 1 s after Stop instead of at its five-minute timeout (`Wake Locks: size=0`), after a heads-up Stop, a Snooze, a re-ring and the pair (one lock at a time, the release and the next acquire in the same millisecond); a cancel of a ringing remove-after alarm no longer deleting the event with nobody answering. Carried to Slice 6: C21 (the page such a cancel leaves up) and C22 (a stop that promotes a queued alarm), with three small notes of the review (the cancel comment's reason, the silence timer taken down before the platform is asked, the diagnostic for a payload that names no instant). Not seen: another app's broadcast refused (nothing was sent by hand), `BootReceiver`'s re-arm after a reboot, a refused start's re-arm. |
| 4 | done 2026-10-05 | **4a, the investigation** (no change to the tree): fifty experiments with probe notifications posted through the running QA app, each read back from the platform and then audited line by line against the saved dumps; its rules are §3.7, its decision D20. **4b, the build:** `kAlertQuietChannelId` (`alerts_quiet`, low) created beside the other two with `alertsQuietChannel` / `alertsQuietChannelDesc` ("Quiet notices" / "Leise Hinweise" / "Anunțuri discrete"); the notice, Missed and the chip on it; `sdkInt` on the alerts channel with the pure rule `alertRemindersGroupedOn` (`kAlertGroupMinSdk` 36; a failed read answers "loose" and is not remembered); `kAlertGroupKey` with `GroupAlertBehavior.children` on the reminder and both re-posts; the payload's `grouped`; the token at `~g3`. Suites: the details per channel and per flag, the re-posts, the codec, the context; a new source guard for the alerts channel's method names and the binding's own half of the grouping (each pin watched failing), and one for the chip's channel. Gate, run independently: analyzer clean; 7,182 passed, 7 skipped, the one known failure; `untranslated.txt` `{}`; `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1. Review (three reviewers, one reading the device evidence to the millisecond): no defect; one should-fix (the gateway's half pinned by nothing) fixed test-only. **The five readings of §3.7, all taken with the app's own notifications:** (1) the chip and a notice standing on `alerts_quiet` in one silent bundle, a reminder fires with the process dead — `g:anta.alerts`, no `SILENT`, alert `1,1`, `PEEK allowed`, 5.7 s of heads-up; the same with the app alive beside the chip flow 02 leaves, the case Slice 0 saw silenced; (2) a second reminder while the first stands — sounds, peeks, 2.98 s of heads-up, gathered by the platform at +3.2 s; Done on one and Snooze on the other inside the bundle; the snoozed one back five minutes later with `grp`, sounding and peeking, and again beside one still standing; (3) Missed beside a notice — the pair that made the platform's summary sound in Slice 3's fix pass — then the chip and a second notice: no alert line for any ANTA key, attention null, each leaving quietly by its timeout, the app's cancel, the chip's own Done and a swipe; (4) a test ring with all three standing, screen off, process dead — `FSI allowed`; (5) the first launch over the Slice 3 build's entries `planned=3 scheduled=3` with the notices now on `alerts_quiet` and the reminder carrying its group, the second `scheduled=0`. The lead's calls: the quiet channel is not added to the permission gateway's list (a person who turns it off still gets every alert). Not seen, owed: the promoted chip on the low channel; a second platform build; Android 15 and below (suites only); a reminder behind a PIN keyguard; old-shape entries beside new ones. |
| 3 | done 2026-10-05 | `lib/utils/alert_notification_content.dart` (the composer, written first against the old strings — eight pins green with the gateway wired through it — then changed); pure and public in the gateway: `alertReminderDetails`, `alertNoticeDetails`, `alertMissedDetails`, `alertFallbackAlarmDetails`, `alertRingSettings`, `sessionChipArguments`, `snoozedRepost` / `snoozedRepostFor` / `snoozedRepostTitleOnly`, `alertArmContext`, and the avatar's painter and file name; the avatar as a file (a draft renamed into place, each step bounded, nothing cleared); `timeLabel` in the phone's style; `kAlertArmGrammarToken` `~g2`; the chip's `linkedNote` and `SessionChip.kt` (Done first, the large icon); `showSystemUI: false`; `alertsKindWhen`, four keys retired, seven `@` descriptions rewritten; the test ring's avatar in the theme's primary; flow 00's settle; `moved` on instants. New suites: the composer (32), the details and the rest of the pure pieces (61), a Kotlin-channel source guard (4); the chip +6, the labels +4, the page +1; every existing expectation of the scheduler's and the gateway's suites stands. Gate, run independently: analyzer clean; 7,148 passed, 7 skipped, the one known failure; `untranslated.txt` `{}`; `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1. Review (five reviewers, one reading the shade evidence): one should-fix fixed with pins (nothing pinned the isolate's re-post language or its fallback), and one finding confirmed and written into §3.7 instead of cured (row H). Seen on the emulator, in `dumpsys notification` and in shots: every kind as §3.5 says — the ring heads-up "Alarm · 4:27 AM – 5:27 AM"; the reminder with its excerpt under the text and a 144 px avatar; a reminder armed in German and snoozed with the process dead coming back as "Geschlummert · 04:32 – 04:47" with its colour, avatar and German buttons; the notice silent and gone at the alarm's instant; Missed silent alone, dated by its due instant; the chip with "Open note" and with "Open event"; the first launch over the previous build's entries `planned=3 scheduled=3`, the second `scheduled=0`; a test ring not cut by a re-arm; no volume panel in the floor bucket. Deviations folded in: the composer's third fact `linkedNote`; `alertRingSettings` and `sessionChipArguments` standing in for a details function; the title-only re-post naming its channel by id. Left for the owner: `eventAlertNotifyHint` still says "with Snooze and Done" while the buttons now read Done · Snooze N min (an out-of-scope string). Not seen: the dormant fallback and the title-only re-post (suites only), a 24-hour phone, the promoted chip. |
| 2 | done 2026-10-05 | `AlarmMetrics`; `FormReadTitleRow`, `FormHeaderTextButton(semanticsLabel:)`, `FormActionRow`'s disabled announcement and `FormCaptionSlot(alignment:)` in the kit (the detail sheet adopts the row, its suite untouched); `AlarmGround` with the navigation bar's hand-back; the page rebuilt (no `AppSpacing`, no literal); the controller's three-moment `keep()` with `configureForTesting`; `AlertKeepNotice` and the calendar's listener; the cover on the same ground; six ARB keys, two retired; `alarm-open-database`, `alarm-body`; `alerts_pair.json` with its suite and flow. Page suite 26 → 85 cases (17 bodies untouched, the rest changed per §4.2), a 72-cell layout matrix plus the 780 × 360 cell; new suites for the controller (12), the notice (4), the calendar's listener (4), the ground (8), the pair fixture (7); `form_rows_test` +9. Gate, run independently: analyzer clean; 7,039 passed, 7 skipped, the one known failure; `untranslated.txt` `{}`; `qa flows alerts` 3 / 3, `alerts_pair` 1 / 1; `qa flows calendar` 22 / 23 (`19_fasting_schedule`, §8). Review (four reviewers, one judging the screenshots): five findings, all fixed with a pin watched failing first — the unpinned page hung from the top; `namesRoute` was inert under `rootPushInstant`; Keep then Open event with no calendar on the stack opened a stale sheet; two "no remove row" pins could not fail; the ground case read the ground's own box. Seen on the emulator (forty shots): the heads-up over bare ground with eyebrow, time, day and title clear of it at 1.0 on 427 × 952 and 360 × 800; dark status icons on the light page pushed from Calendar settings; no band under the dark page; German at 2.0 and 1.3 with both dock labels on one line; the dock at the same pixels before and after Keep; the calendar row no longer saying "removed after it rings"; the two-in-a-minute pair with both pages stoppable; "ALARM · SNOOZED" on a page re-ring. Deviations folded in: the ground's hand-back; the route scope; the notice as a flag; the eyebrow's node named in words ("Alarm, Snoozed"); a test ring from another database shows the switch. Carried to Slice 3: a test ring's avatar takes the theme's primary (the stamped light-scheme purple is the dimmest thing on the dark page); flow 00 shoots before the bar style settles. Not seen: the PIN-locked cold start (Slice 6), another database's alarm, TalkBack. |
| 1 | done 2026-10-05 | Seven optional payload fields with their codec; `lib/utils/alert_labels.dart` (`AlertLabels`, `AlertLabels.fixed`, `moved`); `EventTimeFormatter.formatRangeFor` / `formatMinuteFor`; `CalendarCategories.iconKeyFor`; one `_payload` builder in the scheduler; `ringReportPayload` and the snooze-move record in the gateway; the plugin's log listener (`alarmPluginLogLine`); `logging` in `pubspec.yaml`; `alertsWhenOnDay`. 77 new tests, no existing expectation changed. Gate, run independently: analyzer clean; 6,936 passed, 7 skipped, the one known failure; `untranslated.txt` `{}`; `qa flows alerts` 3 / 3. Nothing compares payloads downstream of the ring stream (everything keys on the os id), pinned by a queue test. On the device: stamped payloads read back from the plugin's store (`"when":"11:31 PM – 12:31 AM (+1)"`, `tint`, `glyph`, `lang`), the log listener proved with injected records, and a ring snoozed on its heads-up re-rang with `reRing: true` and its own time — the one visible change of the slice, on the old page. Deviations folded into §3.6: the rescue gated on `languageCode`; the snooze length restamped; when the snooze record is forgotten; the Material clock rule. Reviews: no defect; two notes carried forward (the day of a line rescued across midnight → Slice 2; "same minute" decided on label text → Slice 3). Not staged: the cold-start report site, another database's alarm, a deferred ring. |
| 0 | done 2026-10-04 | 26 page cases through the robot (15 kept, 11 new); placeholders + 7 cases; fixture + 7 cases; three flows green on `emulator-5554` (00 in 17 s, 01 in 158 s, 02 in 122 s). Gate on the final tree, run independently: analyzer clean; 6,859 passed, 7 skipped, the one known failure. Found on the device: Keep's write does not reach the calendar until a relaunch (C4); the seeded reminder was force-grouped silent beside the chip (D17). Review: one flow-header note (the seed goes in with `relaunch`), applied. Test traps for Slice 2: the renderer reports an overflow once per render object, so the robot pumps a fresh app each time; `find.bySemanticsIdentifier` still finds controls under a dialog; `pumpApp(appNavigator: true)` at most once per test (`AppNavigator.navigatorKey` is a global key). |
