# QA harness

**Status: Phase A shipped and proved end to end 2026-09-13 — Android on
Windows, driver and app seams together. Phase B (iOS on macOS) planned.
Phase C (on-device `integration_test` suites) possible, not shipped.**

## What the end-to-end pass proved (2026-09-13, emulator-5554, Android 16)

`qa run --fresh --seed tool/qa/fixtures/basic.json` reset the QA database,
imported the fixture and skipped onboarding:

```
[qa] reset: cleared preferences and qa.db
[qa] seed: imported 4 folders, 3 notes
[qa] onboarding marked completed
```

The root then showed the fixture (`All notes 3`, `Inbox 0`, `Money 1 · Green
label`, `Training 2 · Blue label`) and not the owner's collection. A seeded
note rendered headings, checked and unchecked tasks, nested bullets, a tag pill
and a wiki link; the Money note's ledger computed `Σ 827.50`, `Δ -172.50` and a
budget remainder of `+468.00`; the calendar carried both seeded events — the
weekly `Lifting session` on Mondays and Thursdays and the one-off `Yearly
checkup` on Tuesday, 3 February 2026. `qa errors` and the Dart MCP's
`get_runtime_errors` were clean.

A second `qa run` with no flags kept that data. `qa run --fresh` alone left an
empty database on the folder root, never on onboarding. `qa run --no-qa` then
brought the owner's own collection back unchanged, with `gym_notes.db` at the
same 282,624 bytes and the same mtime it had before the QA runs, and `qa.db`
sitting beside it.

The device-driving half of the QA automation: one command-line tool an agent
can use to boot the emulator, run ANTA against an isolated database, look at
the screen, act on it by label, and read back errors. The day-to-day reference
is the [`qa-emulator` skill](../.claude/skills/qa-emulator/SKILL.md); this file
is the architecture and the roadmap.

## Architecture

```
tool/qa/qa.dart              verb dispatch (package:args CommandRunner), exit codes
tool/qa/src/
  errors.dart                QaException + the four exit codes (0/1/2/3)
  paths.dart                 build/qa layout, package-root discovery
  process_runner.dart        ProcessRunner interface + the real one (fakeable)
  adb.dart                   SdkTools (locate adb/emulator/qemu-img), Adb, serial selection
  device.dart                Device abstraction: AndroidDevice + IosSimulator placeholder
  ui_tree.dart               uiautomator XML -> flat UiNode list
  target.dart                target string -> node/point, with match precedence
  input_text.dart            `input text` escaping, keycode aliases
  gestures.dart              swipe geometry with edge avoidance
  shots.dart                 screencap + downscale + naming
  markers.dart               QA marker files pushed through run-as
  runner.dart                detached `flutter run`, DTD/VM URI capture
  fixtures/                  seed backups pushed by `run --seed`
test/qa/                     unit tests against fakes and real captured dumps
test_driver/main_driver.dart Flutter Driver entry point (`enableFlutterDriverExtension`)
```

No file under `tool/qa/src/` imports Flutter, so everything runs under plain
`dart run` and is still importable from `flutter test` by relative path.

### The Windows launcher

`runner.dart` looks over-engineered and is not. Three independent Windows
behaviours each break a detached `flutter run` silently, and the launcher has
to dodge all three at once:

| Behaviour | Symptom | Answer |
| --- | --- | --- |
| `flutter.bat` produces no output under `DETACHED_PROCESS` | the run looks like a four-minute hang | start it through `Start-Process` with real file handles |
| a child inherits the calling shell's stdout handle | the agent's shell never returns, even though the verb finished | redirect the child's stdout/stderr to files and never read the launcher's own stdout — the pid comes back through `run.pid` |
| `flutter run` quits the moment stdin reports end-of-file | the URIs print, then the run is gone seconds later | the wrapper feeds flutter from an idle `for /l … ping` pipe that writes nothing and never closes |

Redirecting stdin to a file looks like it should help and does the opposite:
`cmd` then never builds the pipe. `powershell.exe` needs a console host as much
as `flutter.bat` does, so the launcher itself is started normally rather than
detached.

`launchDetached` also fails fast rather than waiting out its timeout: a Gradle
or kernel-snapshot failure aborts immediately, and the VM service handshake
error (`Error connecting to the service protocol`) aborts after a 20-second
grace period, because it sometimes recovers. `run`, `attach` and `kill-run`
reap orphaned `dart development-service` processes — a DDS whose parent is
gone still owns the app's VM service and blocks the next run's handshake. Only
true orphans are killed, so a `flutter run` the owner has going is untouched.

The verb layer only ever talks to `Device`, never to `Adb` directly for input,
which is what lets Phase B slot an `IosSimulator` in. `IosSimulator` exists
today and throws `Phase B: not implemented on this platform` for every verb.

### App seams contract (owned by the app side, not by this tool)

| Piece | Value |
| --- | --- |
| Dart-defines | `ANTA_QA=true`, `ANTA_QA_DB=qa` (default `qa`), optional `ANTA_QA_SKIP_ONBOARDING=false` |
| Database | `qa` under the `gym_notes/` directory, plus a namespaced SharedPreferences prefix |
| Documents dir | `/data/user/0/com.alexzamfir.anta/app_flutter` |
| Reset marker | empty `qa_reset` — next QA launch clears QA prefs and deletes `gym_notes/qa.db*` |
| Seed marker | `qa_seed.json` (full-backup JSON) — next QA launch imports it |
| Marker delivery | `adb push` to `/data/local/tmp`, then `adb shell run-as com.alexzamfir.anta cp …` (debug builds only) |

Both markers are consumed by the app. `tool/qa/fixtures/basic.json` is the
standard seed.

### Two driving layers

`adb` + `uiautomator` works on any build and sees the Android accessibility
tree; Flutter Driver sees the widget tree, is frame-synced and types Unicode,
but needs `test_driver/main_driver.dart`, which `qa run` uses by default
(`--no-driver` opts out). Driver is reached through the Dart MCP
(`flutter_driver_command`) over the DTD connection that `qa dtd` hands you.
`widget_inspector` and `get_runtime_errors` work on any debug build.

### Automation identifiers

`lib/constants/semantics_ids.dart` holds the ids; `lib/widgets/automation_id.dart`
attaches them. A bare `Semantics(identifier: …)` around a leaf control builds a
**second** node — a dump shows an unlabelled `View` carrying the id beside the
`Button` carrying the tooltip, at identical bounds — so `AutomationId` adds a
`MergeSemantics` and the id, the label and the tap action land on one node.
Containers (`editor-body`, `editor-toolbar`, `label-picker`) keep the plain
`Semantics` wrapper on purpose: merging would collapse their children.
`_SmartRow` and the drawer rows already merge through their own row widgets and
need nothing. `test/widgets/optimized_folder_content_page_test.dart` pins both
shapes against `getSemanticsData()`, which is the merged view the platform
receives.

The tooltip lands on `SemanticsData.tooltip`, not `label` — Android reads it as
the content description, but a Flutter Driver `BySemanticsLabel` finder will
not match it. Use `ByTooltipMessage` for buttons and `ByText` for rows.

## Phase B — iOS on macOS (planned)

- `xcrun simctl boot <udid>`, `launch`, `terminate`, and
  `xcrun simctl io <udid> screenshot <path>` replace `boot`/`launch`/`stop`/`shot`.
- `idb` covers what `simctl` does not: `idb ui tap/swipe/text/key` for input and
  `idb ui describe-all` for the accessibility tree — the same flat-node shape
  `ui_tree.dart` already produces, so `target.dart` is reused unchanged (a
  JSON parser sits where the XML parser is on Android).
- `ios/` has no `Podfile` yet, so the first run on a Mac is a CocoaPods
  bootstrap (`flutter build ios --debug --no-codesign` generates it).
- `Semantics.identifier` surfaces as `accessibilityIdentifier`, which is what
  `idb` matches on — prefer it over the label for anything the harness must
  find reliably across locales.
- The marker files move to the app's Documents directory inside the simulator's
  data container (`xcrun simctl get_app_container … data`); no `run-as` needed.

## Phase C — on-device suites (not shipped)

`flutter_driver` and `integration_test` are both dev dependencies now and the
driver entry point compiles and runs (proved 2026-09-13 on `emulator-5554`), so
an `integration_test/` suite driven by `flutter test integration_test/… -d
emulator-5554` is possible. Nothing is written yet; the planner decides scope.
