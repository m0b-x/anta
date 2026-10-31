---
paths:
  - "test/**"
  - "test_driver/**"
  - "tool/qa/**"
  - "dart_test.yaml"
---
# Tests and the QA harness — loads when a test or the harness is touched

- Run the **whole** suite, one `flutter test` at a time, never while a QA `flutter run` is up (two Flutter processes race on `build/native_assets`). `dart analyze lib test` when tests changed; add `tool test_driver` when the harness changed.
- Suites run against pure-Dart fakes (`test/bloc/sync_bloc_test.dart`), sheets against the robots in `test/widgets/support/` (`test/widgets/event_look_sheet_test.dart`); no mocking package, no network, `NativeDatabase.memory()` for the database suite.
- Fake the keyboard through `tester.view` insets, not a real focus change; a widget test under `FakeAsync` must not open Drift; benchmarks carry the `benchmark` tag and are skipped by default.
- Known noise, not regressions: a transient `sqlite3` lock crash (rerun once); `test/qa/host_devices_test.dart` fails on Windows only.
- Device passes go through `tool/qa/qa` (the `qa-emulator` skill), never `adb`, `emulator` or `xcrun simctl` by hand. A suite is one call — `qa pass calendar -d emulator-5556` on the one fleet guest (a reseed before every flow, one `report.json`; `qa fleet pass calendar` is its sharded form for the days the owner asks for it), `qa pass alerts -d emulator-5556` for the clock-relative suites, `qa pass settings -d emulator-5556` for the settings suite (a `basic.json` reseed before every flow, no prelude) — after `qa fleet install --build` when `lib/` or `test_driver/` changed; a hand-driven seed goes in with `qa relaunch --fresh --seed …`, never `qa run` (it builds first and a clock-relative seed comes out stale). `qa build` is a Flutter build: never beside `flutter test` or a `qa run`.
- A saved flow targets controls by `id:` (`SemanticsIds`), never by label; `test/qa/flows_lint_test.dart` enforces it against each suite's `_labels.txt`. A new control a flow needs gets an id in the same change.
