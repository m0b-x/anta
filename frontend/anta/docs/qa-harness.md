# QA harness

**Status: Phase A shipped and proved end to end 2026-09-13 — Android on
Windows. Phase B shipped 2026-09-16 — the iOS simulator and the macOS desktop
build, driven from macOS through an in-app agent over the VM service, proved
end to end on the iPhone 17 Pro Max simulator (iOS 26.2) and on macOS 26.0.1.
Android completed on the same Mac 2026-09-17 against an API 36 AVD: both the
adb path and the agent path (`--via agent`), plus the cloud-isolation and
output-redaction guards. Phase C (on-device `integration_test` suites)
possible, not shipped.**

The device-driving half of the QA automation: one command-line tool an agent
can use to boot a device, run ANTA against an isolated database, look at the
screen, act on it by label, and read back errors. The day-to-day reference is
the [`qa-emulator` skill](../.claude/skills/qa-emulator/SKILL.md); this file
is the architecture and the roadmap.

## What the end-to-end passes proved

### 2026-09-16, iPhone 17 Pro Max simulator and macOS, from a Mac

`qa run --fresh --seed tool/qa/fixtures/basic.json -d <udid>` dropped both
markers into the simulator's data container as plain files, built and
installed the driver build (62 s warm), captured the DTD and VM URIs from the
detached `flutter run`, and read the three `[qa]` lines back **through the
agent** rather than from a log:

```
[qa] reset: cleared preferences and qa.db
[qa] seed: imported 4 folders, 3 notes
[qa] onboarding marked completed
```

`qa dump` then showed the fixture root with the same labels and ids the
Android dump has (`"All notes\n3"  id=drawer-all-notes`, `"Money\nGreen label\n1"`,
`id=search-open`, `id=create-folder`) in 120 ms. An eight-step `steps` flow —
tap the search button, wait for `id:search-field`, type `squat ăöü`, dump,
screenshot, back, back, dump — took 1.7 s and left the field reading
`text="squat ăöü"` with the caret at 9. `qa relaunch --fresh --seed …` (bare
`xcrun simctl launch` with a fixed VM-service port) had the agent answering
and the markers verified in 2.5 s. `qa doctor` was all `ok`, `qa errors` clean
on all three sources (run log, simulator unified log, the app's own error
buffer).

The desktop build: `qa run -d macos` built, launched and connected in 44 s.
`qa relaunch -d macos --fresh --seed …` restarted the sandboxed app with the
engine switches in its environment, verified the markers through the agent
and found `"Training\nBlue label"` in 1.9 s total; the same search flow typed
`Deadlift ✓ ünïcode`, deleted one character with `key backspace` and read the
field back. `key back` on the root route then quit the app — which is what
`popRoute` means on desktop — and `doctor` reported it precisely (`no
process`, agent `Connection refused`, stale `run.pid`); `back` now goes
through `Navigator.maybePop` and reports `nothing to pop` instead.

The Android side on the same Mac: `qa boot --avd Medium_Phone_API_36.1`
started the emulator (after fixing a false fatal on a routine
`WARNING | Failed to process .ini file` line), `state`/`doctor`/`dump`/`shot`/
`swipe`/`key` ran through adb + uiautomator unchanged, and `qa run -d
emulator-5554` failed honestly in 1:38 on the checkout's then-missing
`google-services.json`; the Android app and its agent path were exercised the
next day (below).

### 2026-09-17, emulator-5554 (API 36) on the Mac, and the leak guards

With `android/app/google-services.json` in place `qa run -d emulator-5554`
built, installed and connected in 61 s (heartbeat lines every 20 s).
`agent info` answered `android  1080x2400 @2.625x  lifecycle=resumed  qa=qa
cloud=off` — the first live proof of the cloud guard on the platform where
Firebase would otherwise initialize. The adb path drove the real app (tap
with `--wait`, back, wait: 10.5 s for three steps, the uiautomator cost), and
the agent path ran a six-step flow with `squat ăöü` typed and two `expect`s in
**0.53 s**. `qa relaunch --fresh --seed …` delivered both markers through
`run-as`, started the activity with the engine-switch extras, forwarded the
port, had the agent answering with its first frame after 2.1 s, and printed
the three typed `[qa]` outcomes.

That relaunch found the last bug of the port: adb accepts a connection on a
forwarded port before anything listens behind it, so the WebSocket handshake
dies with an `HttpException` rather than a refused socket. `connect` now maps
every `IOException` to "not answering yet", which `waitForVmService` retries;
before the fix the next verb still recovered on its own by reading the VM
service line out of logcat.

Two guards landed with it. **A QA build cannot reach Firebase**: identity
belongs to the install, not to a database, so a QA run on a device where the
owner is signed in would have shown their name or e-mail and could have
written `invites`/`pairs` documents in the production project.
`SyncAvailability.resolve` now answers false for a QA build
(`ANTA_QA_CLOUD=true` opts in, loudly). **Tool output is redacted**: API
keys, OAuth client ids, Firebase app ids, tokens, JWTs, authorization
headers, private keys and e-mail addresses are masked in `log`, `errors` and
quoted log tails. The credentials file itself had been dropped in `android/`,
where Gradle did not find it and git did not ignore it; it now sits in
`android/app/` and `.gitignore` ignores those file names anywhere in the tree.

### 2026-09-13, emulator-5554 (Android 16) on Windows

Reset, seed and onboarding skip as above; the root showed the fixture and not
the owner's collection; a seeded note rendered headings, tasks, nested bullets,
a tag pill and a wiki link; the Money ledger computed `Σ 827.50`, `Δ -172.50`
and `+468.00`; the calendar carried both seeded events. A second `qa run` kept
the data, `--fresh` alone left an empty root, and `--no-qa` brought the owner's
collection back with `gym_notes.db` byte-identical (282,624 bytes, same mtime)
and `qa.db` beside it.

## Architecture

```
tool/qa/qa                   POSIX entry (macOS, Linux, Git Bash): compiles build/qa/qa on first use, then runs it
tool/qa/qa.cmd               Windows entry, same contract (build/qa/qa.exe)
tool/qa/qa.dart              verb dispatch (package:args CommandRunner), QaContext, exit codes
tool/qa/src/
  errors.dart                QaException + the exit codes (0/1/2/3), UnsupportedOnPlatform
  paths.dart                 build/qa layout, per-device URI files, macOS bundle path
  process_runner.dart        ProcessRunner interface + the real one (fakeable)
  self_build.dart            staleness decision, `dart compile exe`, running-exe swap
  app_ids.dart               bundle id, Android activity, iOS executable, macOS product name
  device_select.dart         DeviceKind/DeviceRef, -d resolution across adb + simctl + desktop
  device.dart                Device (platform plumbing) and UiDriver (see/act) contracts,
                             ScreenSize/DeviceProbe, AndroidDevice + AdbUiDriver
  adb.dart                   SdkTools (locate adb/emulator), Adb, serial selection
  shell_batch.dart           several device commands per `adb shell`, split on a separator
  simctl.dart                `xcrun simctl` wrapper: list/boot/launch/terminate/screenshot/log
  ios_device.dart            IosDevice: data container markers, launchctl pid, PNG header size
  macos_device.dart          MacosDevice: xcconfig product name, ps pids, sandbox documents, env launch
  vm_service_client.dart     JSON-RPC over a dart:io WebSocket, driver-isolate discovery, free port
  agent_protocol.dart        the op names, keys and flags shared with test_driver/qa_agent.dart
  agent_client.dart          AgentClient (a UiDriver) + AgentInfo + QaOutcome
  poll.dart                  pollUntil, the one wait loop the newer code shares
  ui_tree.dart               uiautomator XML and agent JSON -> flat UiNode list, foreground package
  dump_cache.dart            build/qa/last_dump.txt, so `#N` means what you read (either format)
  target.dart                target string -> node/point, with match precedence
  shell_words.dart           `steps` line -> argv, POSIX quoting rules
  input_text.dart            `input text` escaping, adb keycode aliases
  gestures.dart              swipe geometry with edge avoidance
  shots.dart                 capture callback + downscale + naming, annotated `look` badges
  markers.dart               QA marker files: adb run-as delivery, and plain host-side writes
  doctor.dart                the `doctor` checks, as pure functions over captured output
  log_parse.dart             run-log URIs, launch failures, `[qa]` markers, emulator fatals
  runner.dart                detached `flutter run`/emulator/app launches, engine switches,
                             DTD/VM capture, orphaned-DDS reaping (Windows + POSIX)
  fixtures/                  seed backups pushed by `run --seed`
test/qa/                     unit tests against fakes, captured dumps and a fake VM service
test_driver/main_driver.dart Flutter Driver entry point + the agent (`qa run`'s default target)
test_driver/qa_agent.dart    the in-app agent: semantics dump, pointer/key/text synthesis, drag, chords,
                             screenshot, frame timing, error buffer, [qa] lines — driver target only
build/qa/qa[.exe]            the compiled tool (rebuilt automatically when sources move)
build/qa/last_dump.txt       the tree `#N` targets resolve against
build/qa/vm_<device>.txt     the VM service URI per device; dtd_<device>.txt likewise
build/qa/device.txt          which device the recorded flutter run serves (kill-run clears its URIs)
build/qa/app.log             stdout of a desktop app launched by relaunch/launch
build/qa/rebuild.lock        held while one qa process recompiles the tool
```

No file under `tool/qa/src/` imports Flutter, so everything runs under plain
`dart run` and is still importable from `flutter test` by relative path.
`test_driver/qa_agent.dart` imports Flutter, `flutter_test` and
`flutter_driver`, and shares only `agent_protocol.dart` with the tool.

### Two driving layers, one verb layer

Every verb talks to a `Device` (process control, markers, native capture,
platform log) and a `UiDriver` (dump, tap, long-press, swipe, type, key).

| | `AgentClient` | `AdbUiDriver` |
| --- | --- | --- |
| where | iOS simulator, macOS, and Android with `--via agent` | Android (default) |
| dump | Flutter's semantics tree serialised by the agent: label, value, hint, tooltip, `identifier`, physical-pixel rect, role flags, `hidden` for off-screen nodes | `uiautomator dump` XML |
| tap / long-press / swipe | `LiveWidgetController.tapAt`, `startGesture` + `up`, `timedDragFrom` (60 Hz, real clock) | `adb shell input` |
| type | `TestTextInput`: inserts at the caret (or `--replace`), any Unicode; refuses with exit 2 when no field is focused | `adb shell input text`, ASCII |
| key | `popRoute` through the navigation channel (after a `canPop` check), the field's own `TextInputAction` for Enter, `simulateKeyDownEvent` for the rest | `adb shell input keyevent` |
| settle | every op awaits `endOfFrame` until no frame is scheduled (500 ms cap) | `--settle` pause, `uiautomator` retries |
| screenshot | `WidgetInspectorService.screenshot` of the root `RenderView` (used on macOS, and with `--via agent`) | `screencap` / `simctl io screenshot` (native, the default where it exists) |

The `UiTree` the verbs consume is the same class either way. `fromAgentJson`
maps the agent's fields onto the uiautomator vocabulary the way Flutter's
Android bridge does — label plus tooltip become the content description, the
value becomes the text, `Semantics.identifier` becomes the resource id, and
the flags become a role (`Button`, `EditText`, `Switch`, `Scroll`, …) — so
`target.dart` and every step file are shared verbatim across platforms.

### How the agent is reached

`test_driver/main_driver.dart` enables the Flutter Driver extension with a
`handler` and with `enableTextEntryEmulation: false`, then installs
`QaAgent`: it registers its own `TestTextInput` (the driver binding is a
`TestDefaultBinaryMessengerBinding`, which is what makes that legal in a live
app), holds a `SemanticsHandle`, and chains `FlutterError.onError` and
`PlatformDispatcher.onError` after the first frame into a 100-line ring
buffer. The tool speaks to it with the Driver extension's `request_data`
command: `VmServiceClient` opens the VM service WebSocket, finds the isolate
whose `extensionRPCs` include `ext.flutter.driver`, and sends
`{"op": …}` JSON; the reply is `{"ok": true, …}` or `{"ok": false, "error",
"kind"}`, where `kind` picks the exit code (`target` → 2, `usage` → 1).

Where the URI comes from:

| Launch | URI |
| --- | --- |
| `qa run` / `qa attach` | parsed from `flutter run --print-dtd` output (both DTD and VM) |
| `qa relaunch` / `qa launch` on iOS | `xcrun simctl launch … --vm-service-port=<free host port> --disable-service-auth-codes` (plus `--enable-checked-mode --verify-entry-points --enable-dart-profiling`, as `flutter run` passes); the simulator shares the host loopback, so `http://127.0.0.1:<port>/` answers within a second |
| … on macOS | the same switches through `FLUTTER_ENGINE_SWITCHES` / `FLUTTER_ENGINE_SWITCH_<n>` in the app's environment, the app started through the wrapper script with stdout to `app.log` |
| … on Android | the same switches as `am start` extras (`--ei vm-service-port`, `--ez disable-service-auth-codes true`), then `adb forward tcp:<port> tcp:<port>` |

The URI is recorded per device (`build/qa/vm_<id>.txt`), so a simulator and
the desktop app can be driven in one session. `relaunch` waits for `getVM` to
answer (aborting early if the process dies), then asks the agent for `info`,
which also carries the `[qa]` lines `QaBootstrap` kept in memory — the reason
marker verification is instant and log-format-free on every platform.

### What an AI tester gets beyond see-and-act (2026-09-16 hardening pass)

| Verb | What it is for |
| --- | --- |
| `look` | one call = screenshot with every interesting node boxed and tagged `#N` (orange tappable, blue text field, green scrollable) + the dump lines; the picture and the indices agree, so the next call can be `tap "#14"` |
| `expect A B --absent C` | a checklist in one call, re-checked for `--timeout` seconds; exit 2 lists every miss and the screen it saw |
| `reload` / `restart` | edit-verify loop without the MCP: SIGUSR1/SIGUSR2 to the `flutter run` behind `qa run`, wait for its `Reloaded …`/`Restarted application` line, then `--wait`/`--shot` (POSIX; 0.4 s / 1 s measured) |
| `perf start` … `perf stop` | frame timing from inside the app (`SchedulerBinding.addTimingsCallback`): p50/p90/max build, raster and total, jank = frames whose build **or** raster exceeded 16.7 ms — `totalSpan` alone counts the vsync wait on a 60 Hz simulator and reads as 100 % jank |
| `drag A B --hold 600` | press, hold, move, release through one `TestGesture`; the hold makes a reorder handle fire |
| `clear`, `key meta+z`, `key ctrl+shift+z` | empty the focused field; modifier chords through `simulateKeyDownEvent` |
| `agent info` | platform, screen, lifecycle, QA mode, RSS, documents path and the `[qa]` lines, in one round trip |

Stability work in the same pass, each from something observed live:

- **The driver extension registers after the VM service answers.** A bare
  `relaunch` on macOS connected within 0.5 s and found no
  `ext.flutter.driver`; `driverIsolateId` now polls for up to 15 s before
  calling a build "not the driver build".
- **`key back` is `Navigator.maybePop` on the root navigator.** A `canPop`
  guard broke ANTA's search bar, which is an in-page mode closed by a
  `PopScope`, not a route; `maybePop` runs that handler and returns whether
  anything took the pop. A real `popRoute` on the root quits a desktop app.
- **`kill-run` forgets the URIs it recorded** (`run.device` remembers which
  device the run served): the VM URI `flutter run` prints is its DDS proxy and
  dies with the tool, so the next verb said "connection refused" instead of
  "relaunch". A desktop app started by that run dies with it too; the
  description says so.
- **An IDE-launched app is recoverable.** With no URI recorded, `agent()`
  reads the VM service the app announced in the platform log (simulator
  `log show`, Android logcat + `adb forward`) and records it.
- **`doctor` reports pending markers**, a stale `qa_seed.json` being the
  quiet way to corrupt the next run's baseline.
- **Two `qa` processes starting together no longer race the self-rebuild**
  (`build/qa/rebuild.lock`, reclaimed after two minutes).
- **`run` has an 8-minute budget and a heartbeat** (`still waiting for flutter
  run (40 s): …` every 20 s) so a cold Android build neither times out nor
  looks hung.
- **An ambiguous `wait` fails at once** with the `--nth` listing instead of
  polling to the timeout, and `boot` no longer treats an emulator `WARNING`
  line as fatal.
- **A code-review pass (six angles) landed a second round**: `[qa]` outcomes
  are typed (`QaBootstrap.entries`, `{kind, ok, message}`) and the CLI branches
  on `ok`, so a refused reset or a rejected seed fails the launch without
  matching wording; `Device.probe`/`hasNativeCapture`/`logName` replaced
  type ladders in the verb layer; `forceStop` waits for the pid to go instead
  of a fixed sleep; the marker poller asks only the agent once it answers (no
  more `log show` per tick) and the iOS log fallback is pid-scoped; `ref()`
  asks adb and simctl in parallel and only the ones a `-d` hint needs; adb and
  simctl failures are appended to the "no device attached" error and make
  `devices` exit 3; `kill-run` keeps a URI a later `relaunch` recorded; the
  driver-extension wait is opt-in per connection; hidden nodes lose to visible
  ones in target resolution; dumps are parsed once; `reload` reads only the
  bytes the log gained; `look` dumps and captures in parallel; the agent
  turns semantics on lazily at the first `dump` and off again for `perf start`
  so frame stats are not inflated by semantics work; `last_dump.xml` from
  the previous tool version is still read. The hand-written VM service client
  stays: it is ~150 lines, fully tested against a fake service, and keeps the
  compiled tool free of `package:vm_service`.

### Speed

Measured 2026-09-16 on an M-series Mac against the iPhone 17 Pro Max
simulator (agent path). The Android column is the 2026-09-14 Windows
measurement of the adb path for comparison.

| Verb | iOS simulator (agent) | Android emulator (adb) |
| --- | ---: | ---: |
| `agent info` (one round trip) | 19 ms inside a 0.5 s process | — |
| `state` | 0.3 s | 131 ms |
| `dump` | 120 ms | 2,054 ms |
| `tap "Search all notes"` | ~150 ms | 2,389 ms |
| `shot` | 0.45 s native / 0.5 s agent | 552 ms |
| eight-step `steps` flow | 1.7 s | ~7 s for five steps |
| `relaunch --fresh --seed` | 2.5 s (macOS: 1.9 s) | ~3 s (adb, no agent); 7 s on the Mac including an adb `--wait` |
| `run --fresh --seed` | 62 s (macOS: 44 s) | ~15 s warm on Windows; 61 s on the Mac |
| six-step flow on Android, `--via agent` | — | **0.53 s** (adb: 10.5 s for three steps) |

The agent removes the two costs the Windows work could only trim: the
uiautomator dump (~2 s of device time per look) and the adb round trip. The
remaining floor is process startup (~30 ms) plus the WebSocket connect.

### The Windows launcher

`runner.dart` looks over-engineered and is not. Three independent Windows
behaviours each break a detached `flutter run` silently, and the launcher has
to dodge all three at once. `boot` reuses the same machinery for the emulator
and `MacosDevice.launchApp` for the desktop app, which is what gives
`build/qa/emulator.log` and `build/qa/app.log`:

| Behaviour | Symptom | Answer |
| --- | --- | --- |
| `flutter.bat` produces no output under `DETACHED_PROCESS` | the run looks like a four-minute hang | start it through `Start-Process` with real file handles |
| a child inherits the calling shell's stdout handle | the agent's shell never returns, even though the verb finished | redirect the child's stdout/stderr to files and never read the launcher's own stdout — the pid comes back through `run.pid` |
| `flutter run` quits the moment stdin reports end-of-file | the URIs print, then the run is gone seconds later | the wrapper feeds flutter from an idle `for /l … ping` pipe that writes nothing and never closes |

On POSIX none of the three apply (checked 2026-09-16: a detached `flutter
run` with stdin at `/dev/null` keeps running), so the script `exec`s the tool
and the recorded pid is the tool's own — which matters because
`ProcessStartMode.detached` does **not** put the child in its own process
group, so a wrapper that forked instead of exec'ing would leave the tool
behind when `kill-run` signalled the wrapper. `kill-run` and `run` also reap
orphaned `dart development-service` processes on both platforms (Windows:
CIM query; POSIX: `ps -axo pid=,ppid=,command=` filtered to ppid 1).

`launchDetached` fails fast rather than waiting out its timeout: a Gradle or
kernel-snapshot failure aborts immediately (the Android run on a checkout
without `google-services.json` did exactly that), and the VM service
handshake error aborts after a 20-second grace period.

### App seams contract (owned by the app side, not by this tool)

| Piece | Value |
| --- | --- |
| Dart-defines | `ANTA_QA=true`, `ANTA_QA_DB=qa` (default `qa`), optional `ANTA_QA_SKIP_ONBOARDING=false` |
| Database | `qa` under the `gym_notes/` directory, plus a namespaced SharedPreferences prefix |
| Documents dir | Android `/data/user/0/com.alexzamfir.anta/app_flutter`; iOS simulator `<data container>/Documents`; macOS `~/Library/Containers/com.alexzamfir.anta/Data/Documents` (the agent's `info` reports the live value) |
| Reset marker | empty `qa_reset` — next QA launch clears QA prefs and deletes `gym_notes/qa.db*` |
| Seed marker | `qa_seed.json` (full-backup JSON) — next QA launch imports it |
| Marker delivery | Android: `adb push` + `run-as … cp` (debug builds only); iOS/macOS: a file write into the documents directory on the host |
| `[qa]` lines | printed with `debugPrint` **and** kept in `QaBootstrap.log` (text) and `QaBootstrap.entries` (`{kind, ok, message}`), both returned by the agent's `info` |
| Cloud | off: `SyncAvailability.resolve` answers false for a QA build, so Firebase is never initialized and auth/pairing are the no-op bindings. `--dart-define=ANTA_QA_CLOUD=true` opts in; the agent reports `cloud` either way |

Both markers are consumed by the app. `tool/qa/fixtures/basic.json` is the
standard seed.

### Automation identifiers

`lib/constants/semantics_ids.dart` holds the ids; `lib/widgets/automation_id.dart`
attaches them. A bare `Semantics(identifier: …)` around a leaf control builds a
**second** node, so `AutomationId` adds a `MergeSemantics` and the id, the
label and the tap action land on one node; containers (`editor-body`,
`editor-toolbar`, `label-picker`) keep the plain wrapper on purpose. The agent
reads `SemanticsData.identifier` off the merged node, which is exactly what
Android exposes as the resource id and iOS as `accessibilityIdentifier` — so
`id:` targets are the ones to use in step files.

## Phase C — on-device suites (not shipped)

`flutter_driver` and `integration_test` are both dev dependencies, the driver
entry point compiles and runs on all three platforms, and the agent's ops are
the primitives an `integration_test/` suite would need. Nothing is written
yet; the planner decides scope.
