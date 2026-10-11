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
- Device passes go through `tool/qa/qa` (the `qa-emulator` skill), never `adb` or `xcrun simctl` by hand; a seed goes in with `qa relaunch --fresh --seed …` (after a `lib/` change: a plain `qa run` first, then the relaunch), because `qa run` builds first and a clock-relative seed comes out of the build stale.
