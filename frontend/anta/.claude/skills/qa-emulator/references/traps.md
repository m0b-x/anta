# Traps in full

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

Contents:

- Shared — `key back`, an app you started yourself, markers left pending, native UI, an ambiguous `wait`, off-screen nodes, a refused reset, a non-driver app, `relaunch` without a DTD, one `flutter run`, typing into a re_editor surface, `TestTextInput`, a tap after a sheet closes, the in-app theme
- iOS simulator — the unified log, a reinstall moving the data container, the Android-only `boot` flags
- macOS — `shot`, the sandbox container, `app.log`
- Android — edge swipes, ASCII-only `input text`, `uiautomator`, `pgrep`, Firebase noise, the logcat clock, `qa type` on adb, the keyboard-inset recipe, emulator warnings, forwarded ports, the Windows launcher, PowerShell quotes
- Notification-shade actions and the Quick Settings tile (Android, 2026-09-23)

Pointers: "see Targets" means `verbs.md`; "the read-only alarm queries" are in `alarm-evidence.md`. Eight of these traps are also copied verbatim into SKILL.md's "Top traps" — change both copies together.

## Traps

Shared:

- **`key back` is `Navigator.maybePop` on the root navigator**, which is
  what Android's back does short of leaving the app: a pushed route pops, a
  sheet or dialog closes, and an in-page mode guarded by `PopScope` (ANTA's
  search bar) is closed by its own handler. With nothing to handle it says
  `nothing to pop` and leaves the app running — a real `popRoute` on the root
  quits a desktop app.
- **An app you started yourself (Xcode, the IDE, a tap on the icon) can still
  be driven**: when no URI is recorded, the tool looks for the VM service the
  app announced in the platform log (simulator: `log show`; Android: logcat +
  `adb forward`) and records it — `qa: recovered the VM service URI from the
  ios log`. macOS has no such log; `qa relaunch -d macos` instead.
- **`doctor` warns about markers left pending** (`qa_seed.json pending in the
  documents directory`): a non-QA build ignores them and the next QA launch
  would silently apply a stale seed.
- **The agent cannot see native UI.** A permission prompt, a share sheet or
  the simulator's own dialogs are invisible to `dump`; `shot` (native on iOS)
  shows them. Android's adb path sees them and warns `foreground is …, not
  com.alexzamfir.anta`.
- **A `wait` on an ambiguous label fails at once** (see Targets). Prefer
  `id:` targets in step files.
- **Off-screen nodes never win a label.** The agent's tree includes rows a
  list has cached beyond the viewport (flagged `hidden`); a visible match is
  preferred over a hidden duplicate, `wait`/`expect` treat a hidden node as
  absent, and `tap` on one says `scroll-to it first`.
- **A refused reset fails the launch.** `[qa] reset refused: ANTA_QA_DB is
  "gym_notes"` means the build points at the owner database; `run`/`relaunch`
  exit 3 on it (the outcome is typed, not matched on wording) instead of
  reporting a reset that never happened.
- **A non-driver app does not stall the verbs.** The driver extension is
  looked for once per connection (15 s only right after a launch, when `main`
  is still registering it); a plain build fails fast with "not the driver
  build".
- **`relaunch` has no DTD.** Hot reload and the Dart MCP's `dtd connect` need
  the `flutter run` from `qa run` (or `qa attach`). `relaunch` records the VM
  URI, which is all the agent and `qa dtd --vm` need.
- **One `flutter run` at a time.** `run` on a second device kills the first
  run's tool process (not its app). Per-device VM/DTD files keep the verbs
  pointed at the right app; `relaunch` restores the agent on either side.
- **A re_editor surface takes one line per `type`.** The note editor and
  both event description surfaces run the delta model and keep only their
  caret line in the text channel (2026-09-30: before that `type` reported
  the text and changed nothing there). `qa type` sends them what a keyboard
  sends — a literal newline inside the argument is an Enter, and so is `key
  enter` — but a step file is one step per line, so write `type "line 1"`,
  `key enter`, `type "line 2"`. `--replace` and `clear` are refused there
  (exit 1); the `→ field:` echo shows the caret line only (led by the
  editor's zero-width prefix on iOS and Android).
- **Typing goes through `TestTextInput`,** so there is never a soft keyboard,
  `type` refuses when no field is focused (exit 2: tap a field first), and
  `key enter` sends the field's own input action (`search`, `done`,
  `newline`…). `key done|search|newline` sends a specific action.
- **A tap right after a dialog or sheet closes falls through** to whatever is
  underneath. Put a `wait` (or a second `dump`) between them.
- **The in-app theme overrides the system theme.** Switch light and dark in
  ANTA's own settings.

iOS simulator:

- **`log` is the unified log** (`xcrun simctl spawn <udid> log show`, ~1 s,
  last 10 minutes, Flutter's own predicate). The app's `print`s do not go to
  stdout on iOS, which is why `relaunch` reads `[qa]` lines from the agent;
  the log fallback is scoped to the running pid (`processID == N`), so a
  previous launch's lines are never mistaken for this one's.
- **A reinstall moves the data container** to a new UUID directory (the
  contents survive). The tool queries `get_app_container` fresh every
  process; never cache that path in a script.
- **`--cold`/`--phone` are Android flags**; pick a different simulator with
  `--sim` instead. `boot` needs `--sim` (or `ANTA_QA_SIM`) when more than one
  iPhone is installed and none is booted.

macOS:

- **`shot` is the agent's render** (no window id is needed); there is no
  native capture without a window id, and `--via native` says so.
- **The sandbox container appears on first launch**, so a brand-new machine
  runs a plain `qa run -d macos` before any `--fresh`/`--seed`.
- **`app.log` is the app's stdout**, captured only for launches this tool
  made (`relaunch`/`launch`); a `qa run` launch logs into `run.log`.

Android (unchanged from the Windows-era harness; still true):

- **Right-edge swipes are Android's back gesture.** Every swipe this tool
  builds keeps 48 px clear of all four edges.
- **`adb shell input text` is ASCII only** and the device shell eats `#`, `(`,
  `)`, `&`, `$` and backticks; `qa type` quotes and refuses non-ASCII. Use
  `--via agent` for Unicode (needs the driver build from `qa run`).
- **`uiautomator dump` fails while an animation runs**; `dump` retries three
  times and names the cause. Never run two dumps at once.
- **`pgrep -f uiautomator` always matches itself**; every probe uses
  `pgrep -f '[u]iautomator'`.
- **`E/FirebearStorageCryptoHelper`** in `errors` is Firebase with no signed-in
  user; hidden as known noise.
- **`adb logcat -T` compares against the device clock**, which lags the host;
  stamps are backdated 15 s and marker waits scope to the app's pid.
- **`qa type` on adb warns when no keyboard is up** — with the driver build
  installed that is always, because the agent owns the text channel; use
  `--via agent`.
- **The emulator's keyboard never takes space (2026-10-01).** The AVD has a
  hardware keyboard (`hw.keyboard=yes`), so Gboard runs in its
  physical-keyboard mode even in a `--no-driver` build: a floating toolbar,
  at most a floating keyboard, and an IME inset source with a zero-height
  frame (`dumpsys window`). `viewInsets.bottom` is always 0 here, so no
  keyboard-inset bug reproduces by typing, and docking the keyboard would
  mean restarting the AVD, which this skill forbids. Deliver the inset the
  way the engine does instead — a VM-service `evaluate` in the `dart:ui`
  library (`qa dtd --vm`; the Dart MCP's `vm_service`, or a ten-line
  WebSocket script):

  ```dart
  Timer.run(() {
    final c = PlatformDispatcher.instance._views[0]!._viewConfiguration;
    PlatformDispatcher.instance._updateWindowMetrics(0, _ViewConfiguration(
      devicePixelRatio: c.devicePixelRatio, size: c.size,
      viewInsets: ViewPadding._(left: 0.0, top: 0.0, right: 0.0, bottom: 900.0),
      viewPadding: c.viewPadding, systemGestureInsets: c.systemGestureInsets,
      padding: ViewPadding._(left: c.viewPadding.left, top: c.viewPadding.top,
          right: c.viewPadding.right, bottom: 0.0),
      gestureSettings: c.gestureSettings, displayFeatures: c.displayFeatures,
      displayId: c.displayId, viewConstraints: c.viewConstraints,
      displayCornerRadii: c.displayCornerRadii));
  })
  ```

  **Inside `Timer.run`, never inline**: an evaluation interrupts the isolate
  wherever it is, and metrics that land mid-build throw in
  `_MediaQueryFromView` and leave the tree's `MediaQuery` stuck on the old
  value while the dispatcher reports the new one. An inset delivered this
  way is by construction a stale one — the window never had it — so
  `WindowInsetsResync` takes it back about 400 ms later; re-deliver it on a
  loop to hold it, and read `MediaQuery.of(AppNavigator.navigatorKey
  .currentContext!)` to see what the routes got.
- **A `WARNING | Failed to …` line from the emulator is not fatal.** `boot`
  ignores INFO/WARNING chatter (it used to abort on a routine `.ini` warning
  on a fresh Mac) and, if it is re-run while an emulator it started is still
  offline, resumes waiting instead of calling the guest wedged.
- **A forwarded port answers before the app does.** After `relaunch`, adb
  accepts the TCP connection on the forwarded VM-service port while nothing
  listens behind it yet, so the WebSocket handshake fails with an
  `HttpException`, not a refused socket. The client treats any I/O error as
  "not answering yet" and retries; if a verb ever races it anyway, the next
  one recovers the URI from logcat (`qa: recovered the VM service URI from
  the android log`).
- **Do not simplify the Windows launcher** in `tool/qa/src/runner.dart`:
  `flutter.bat` writes nothing under `DETACHED_PROCESS`, an inherited stdout
  keeps the caller's shell from returning, and `flutter run` quits when stdin
  reports end-of-file — three separate traps, each a silent failure. On POSIX
  none of them apply and the wrapper simply `exec`s the tool (checked on macOS
  2026-09-16: a detached `flutter run` with stdin at `/dev/null` keeps
  running), so the recorded pid is the tool's own.
- **PowerShell 5.1 eats the inner quotes of a native command's arguments**;
  use `--%` with `\"` or `steps --file`.

**Notification-shade actions (Android, 2026-09-23).** `tap "<label>"` on the
native path resolves inside the **foreground app's** window, so a button on
a notification (Stop, Skip, Open note, Done) never matches by label. Open
the shade with **one** `swipe down --from 540,8 --dist 1400` (a second swipe
expands Quick Settings over the rows), then either `dump --all` and `tap
"#N"` from that dump, or tap raw pixels from the bounds a dump printed
earlier — uiautomator sometimes leaves the `NotificationShade` window out of
a dump entirely while a native `shot` shows it open. Verify the outcome in
`dumpsys notification --noredact` (a record's `id=`, `flags=`, `extras`)
rather than in the tree.

**Quick Settings tile (Android, 2026-09-23).** A tile the app declares is
not in the panel until the user adds it. `adb shell cmd statusbar add-tile
com.alexzamfir.anta/.QuickAlarmTileService` adds it from the host — a
device-UI setting, not app data, and the second sanctioned by-hand call
beside the read-only alarm queries — after which two `swipe down` open the
full panel and a native `look --all` names the tile by its label
(`"Quick alarm"`); tap it by pixels and switch to `--via agent` to see the
sheet it opened. A launcher shortcut is checked from the app drawer (`key
home` on the native path, `swipe up`, `longpress` the app icon, the
bubble's long label is the target) and, read-only, in `adb shell dumpsys
shortcut` under the package.
