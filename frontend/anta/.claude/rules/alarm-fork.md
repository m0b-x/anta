---
paths:
  - "packages/alarm/**"
  - "android/alarm/**"
  - "tool/upstream/**"
---
# The alarm fork — loads when packages/alarm or its upstream tooling is touched

- `packages/alarm/` is an owned fork of the `alarm` plugin (base 5.13.2) carrying nine patches and nothing else; upstream is watched, not tracked, and every cherry-pick is recorded in `docs/event-alerts-os-integration-roadmap.md` §2. The patch list and their reasons: `calendar-events/references/alarm-fork.md`.
- The Pigeon-generated bindings are untouched; a change goes into the Kotlin or the Dart side of a patch, never into generated code.
- After a Kotlin change: `cd android && ./gradlew :alarm:testDebugUnitTest`. After a Dart change: `cd packages/alarm && flutter test`, and `dart analyze packages/alarm/lib`.
- Only the Alarm tier of event alerts uses this plugin; a change here is verified with the alerts device pass (`qa flows alerts`, seeded with `qa relaunch`).
- `tool/upstream/alarm_pr.sh` builds the upstream PR for the first two patches; it refuses a real run while the copied `AlarmService.kt` still carries later patches — run it with `--dry-run` unless the owner asks for the PR.
