# Traps in full

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

Contents:

- Shared — `key back`, an app you started yourself, markers left pending, native UI, an ambiguous `wait`, off-screen nodes, a refused reset, a non-driver app, `relaunch` without a DTD, one `flutter run`, typing into a re_editor surface, `TestTextInput`, a tap after a sheet closes, the in-app theme
- iOS simulator — the unified log, a reinstall moving the data container, the Android-only `boot` flags
- macOS — `shot`, the sandbox container, `app.log`
- Android — edge swipes, ASCII-only `input text`, `uiautomator`, `pgrep`, Firebase noise, the logcat clock, `qa type` on adb, the keyboard-inset recipe, emulator warnings, forwarded ports, the Windows launcher, PowerShell quotes
- Notification-shade actions and the Quick Settings tile (Android, 2026-09-23)
- The pass and the fleet (2026-10-23) — the stale-build warning, E-cores, the panel race, `--nth` over hidden matches, `--absent` beyond the cache extent, a v1 agent, `latest_<suite>.txt`, a lone flow without its prelude, `qa build` beside a run

Retired on 2026-10-23 (fixed in the harness, kept here so an old flow comment makes sense): "`ANTA_QA_VIA=agent` on the Windows emulator" — `auto` is the agent wherever it answers; "scroll before an `--absent` check so absence means gone, not off-screen" — a node in the tree but scrolled out counts as present and `--absent` means no node matches at all, except beyond a lazy list's cache extent (below); "an `expect` below the fold fails" — `expect` and `wait` count the scrolled-out node, and `tap` scrolls it into view first.

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
- **Off-screen nodes never win a label without `--nth`.** The agent's tree
  includes rows a list has cached beyond the viewport (flagged `hidden`) and,
  separately, nodes outside the screen rect (`offscreen`, a route still
  sliding in); without `--nth` a visible match is preferred over a hidden
  duplicate. Since 2026-10-23 `wait`/`expect` count a `hidden` node as
  present (not an `offscreen`-only one), `tap`/`longpress`/`drag` reveal it
  first (`revealed: …`), and `--nth` numbers every match in traversal order.
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

## The pass and the fleet (2026-10-23)

- **A stale-build warning at the top of a pass** (`warning: a source of the
  APK changed after the installed build …`) means the APK on the device
  predates a source change under `lib/`, `test_driver/`, `android/`,
  `pubspec.*`, `assets/` or a fork's `android/`: nothing the pass says is
  evidence about the current code. `qa fleet install --build`, then run
  again. `qa run` records what it installed too, so a device last served by
  `run` is not falsely stale.
- **A fleet emulator that is uniformly slow** — first frame 9 s instead
  of 5, every tap half a second, a pure shell loop 1.65× slower — has its
  qemu on the E-cores of the hybrid i7 (Windows prefers them for a process
  without a window). `fleet boot` pins the qemu to the P-cores the moment it
  appears; `fleet status` shows `affinity=0xFFFF`; an unpinned one is a
  `doctor` warn. Priority class changes nothing; `pm compile` on the
  debuggable APK changes nothing.
- **Every app launch leaves ≈ 400 MB in the emulator's host-GPU accounting
  and never gives it back.** `\GPU Process Memory\Dedicated Usage` per qemu
  grows 370–445 MB per launch (a fresh qemu shows 3 MB; one guest reached
  93 GB of virtual accounting after a pass), every verb slows with it
  (reseed p50 5.6 s a minute after boot → 10 s two hours later; a pure adb
  screencap 228 → 340 ms; the alerts suite 265 → 394 s), idle CPU creeps up,
  and at ≈ 130 launches (58.7 GB) `anta_qa_2` hung with `detected a hanging
  thread 'QEMU2 main loop'` and a window titled only "Android Emulator" (its
  crash reporter) that blocked `fleet boot`. The guest itself stays flat
  (shell loop, RAM, `/data`, the WAL, processes, pending alarms). A sharded
  calendar pass is ≈ 10 launches per device. So: `fleet pass` and `fleet
  install` recycle a guest over 40 launches since boot or over 16 GB on the
  counter (`--no-recycle` skips), `fleet status` shows `launches=` and the
  counter, `doctor` warns, `fleet stop <name> --force` kills a hung fleet
  qemu that is not on adb (the one process kill the fleet does, guarded by
  the AVD name on its command line). Measure on freshly booted guests.
- **`-no-window` makes a qemu spin.** A windowless emulator keeps one host
  thread at 100 % while the guest is 97 % idle — 1.2 cores 25 s after boot,
  two spinners and 2.2 cores after hours of passes — whatever the GPU,
  audio or snapshot flags; it doubled a sharded pass's wall time (654 s
  against 268 s). A windowed qemu idles at 0.2 cores; minimized, 0.14, and
  it still relaunches the app (first frame 4.1 s) and renders screenshots.
  `fleet boot` therefore opens a window and minimizes it; `fleet status`
  shows `window=minimized`; `doctor` warns on a headless fleet qemu
  (`qemu-system-x86_64-headless.exe`). The owner's windowed emulator was
  at 1.8 cores "idle" the same evening with the app rendering no frames —
  not explained; re-measured after the fleet went windowed.
- **The calendar's bottom panel restores its mode about a second after the
  page opens** (`lib/widgets/calendar_bottom_panel.dart`'s `_load()`
  overwrites `_mode` after its four settings reads), so a `tap "Upcoming"`
  within ~1.5 s of landing snaps back to Day. The calendar prelude ends with
  `tap id:panel-mode-day --settle 2000`, which rides it out (Day is already
  selected, so nothing is persisted). An app fix is the owner's call
  (`docs/qa-pass-rework.md` §6).
- **`--nth` numbers every match in traversal order, hidden ones included**,
  so a duplicate scrolled above the viewport counts before the visible one.
  Four calendar flows use `--nth`; a new one should name the row by id.
- **`--absent` beyond a lazy list's cache extent passes** because a
  `ListView.builder` row that far away is not in the semantics tree at all;
  `scroll-to` it into the cache extent first when absence must mean gone.
  Inside a sheet or a `SingleChildScrollView` the whole content is in the
  tree, so `--absent` there means gone.
- **A v1 agent in the installed APK** fails a `tap` on a scrolled-out node
  with `installed agent is v1, this tool needs v2 — qa build then qa
  install` (`scroll-to` warns and swipes instead); `doctor`'s agent line
  warns on it.
- **`latest_<suite>.txt` after a hand-sharded pass** (two `qa pass --shard`
  calls) points at the shard that finished last until `qa pass --merge`;
  `fleet pass` merges itself.
- **A lone flow run with `qa flows <dir>/<flow>` gets no reseed** and the
  prelude only when it is the suite's first flow (or with `--prelude`);
  `qa pass <suite> --only <flow>` is the self-contained way to run one.
- **`qa build` is refused while a `qa run` is alive** (`--force` overrides)
  because both write `build/app` and race on `build/native_assets`; never
  run it beside a `flutter test` either.
- **Two first boots of new AVDs in parallel took 80–113 s unpinned**; a
  pinned re-boot takes 16 s. Create the fleet once, boot it as often as you
  like.
- **The emulator's own `adb -e` keep-awake fails with more than one emulator**
  (`more than one emulator`), so `fleet boot` sets `screen_off_timeout` and
  `svc power stayon` per serial itself; a guest that still sleeps between
  passes gets `qa wake`.
