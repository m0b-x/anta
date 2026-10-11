# Harness notes

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

The descriptive paragraphs of SKILL.md's opening, "Which device" and "Two driving layers" sections; the rule lines of those sections stay in SKILL.md, and the three headings below are new.

## The wrapper and the exit codes

The wrapper compiles `build/qa/qa` (`qa.exe` on Windows) the first time it is
used (~3 s on an M-series Mac, ~30 s on the Windows PC) and runs the binary
after that: a verb costs about 30 ms of startup instead of ~2 s of JIT. When a
file under `tool/qa/` changes, the next verb rebuilds itself first
(`qa: sources changed since qa.exe was built — rebuilding…`) and then serves
the verb. `qa build-exe` forces it; `QA_NO_SELF_REBUILD=1` turns it off;
`dart run tool/qa/qa.dart <verb>` still works everywhere and never
self-rebuilds.

Exit codes: `0` ok, `1` usage, `2` target not found or ambiguous, `3` device,
agent or toolchain failure. Every verb takes `--help`.

## `qa devices` and the one `flutter run` slot

`qa devices` lists everything drivable; `--all` adds shut-down simulators. It
exits 3 when nothing is attached *and* a toolchain problem was seen (adb not
answering, `xcrun` missing), so a setup check can rely on it. A `-d` hint also
decides which tools are asked at all: a UDID or `ios` never runs `adb devices`
(a cold adb daemon can take seconds), a serial never runs `simctl list`, and
`boot` honours the same hint (`qa -d android boot` starts the AVD).
Real output, 2026-09-16:

```
ios      B57A8680-5A8F-4010-96BE-7524481996B1    Booted     iPhone 17 Pro Max (iOS 26.2)
macos    macos                                   desktop    pass -d macos  (built: …/build/macos/Build/Products/Debug/ANTA.app)
android  emulator-5554                           device     model:sdk_gphone64_arm64
```

Every recorded connection (`vm_<device>.txt`, `dtd_<device>.txt`) is per
device, so a simulator and the desktop app can be driven in the same session
by switching `-d`. The detached `flutter run` (`run.pid`, `run.log`) is the
one single slot: a `qa run` on a second device ends the first run's tool
process (the first app keeps running — `qa relaunch -d <first>` gets its agent
back in two seconds).

## The two driving layers side by side

| | in-app **agent** (VM service) | **adb** + uiautomator |
| --- | --- | --- |
| Platforms | iOS simulator, macOS, Android (`--via agent`, proved 2026-09-17: a six-step flow in 0.53 s against 10.5 s for three adb steps) | Android only — the default there |
| Needs | the driver build (`test_driver/main_driver.dart`, which `qa run` and `qa relaunch` use) | any build, debug or release |
| Sees | Flutter's own semantics tree: label, value, hint, tooltip, `Semantics.identifier`, flags | the Android accessibility tree, pixels |
| Acts by | synthesised pointer events, `TestTextInput`, key simulation, `popRoute` | `input tap/swipe/text/keyevent` |
| Types | any Unicode, inserted at the caret (`--replace` swaps the field) | ASCII only |
| Waits | frame-synced: every op settles the frame before returning | polls `uiautomator dump` |
| Dump | ~120 ms | ~2 s |
| Cannot see | native chrome: permission prompts, the simulator status bar, share sheets | the soft keyboard is fine; Flutter overlays are fine |
