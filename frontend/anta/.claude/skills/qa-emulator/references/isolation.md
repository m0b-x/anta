# Isolation

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

## Isolation model

Proved end to end on 2026-09-13 on Android (owner's `gym_notes.db` byte-identical
after four QA runs) and on 2026-09-16 on the iOS simulator and macOS.

- QA builds carry `--dart-define=ANTA_QA=true --dart-define=ANTA_QA_DB=qa`
  (`qa run` adds them unless `--no-qa`). The app then uses the `qa` database
  under `gym_notes/` and a namespaced SharedPreferences prefix, so the owner's
  data is never touched.
- **A QA build cannot reach Firebase.** The signed-in identity belongs to the
  install, not to a database, so a QA run on a device where the owner is
  signed in would otherwise act as them: show their name or e-mail on the
  account screens and create or delete `invites`/`pairs` documents in the
  production project. `SyncAvailability` therefore answers false whenever
  `ANTA_QA` is set, which means Firebase is never initialized and the no-op
  auth and pairing bindings are registered. `agent info` and `doctor` print
  `cloud=off` so this is checked, not assumed. Testing sync on purpose is an
  explicit opt-in — `qa run --define ANTA_QA_CLOUD=true` — and every launch
  then warns, and `doctor` turns the agent line to `warn`. Never screenshot
  or dump an account screen in such a run.
- **Everything the tool prints from a log is redacted**: Firebase API keys,
  OAuth client ids, Firebase app ids, OAuth tokens, JWTs, authorization
  headers, private keys and e-mail addresses are masked in `log`, `errors`
  and in the log tails that failure messages quote. Tool output lands in an
  agent transcript, so this is the one place a secret could leave the
  machine. Local VM service URIs are not secrets and stay readable.
- A QA launch reports what it did on the `[qa]` channel, and the driver build
  also keeps those lines in memory for the agent, which is where `run` and
  `relaunch` read them from (logcat / the unified log / `app.log` are the
  fallbacks). A `--fresh` that never produces `[qa] reset`, or a `--seed` that
  never produces `[qa] seed`, exits 3; so does a seed the app rejected. A
  fixture that imports nothing is reported as `imported 0 folders, 0 notes`
  and is **not** a failure — check the count.
- Markers are files in the app's documents directory:

  | Platform | Documents directory | Delivery |
  | --- | --- | --- |
  | iOS simulator | `xcrun simctl get_app_container <udid> com.alexzamfir.anta data` + `/Documents` | a plain file write on the host |
  | macOS | `~/Library/Containers/com.alexzamfir.anta/Data/Documents` (sandboxed; the agent's `info` confirms the path and `qa agent info` prints it) | a plain file write on the host |
  | Android | `/data/user/0/com.alexzamfir.anta/app_flutter` | `adb push` to `/data/local/tmp`, then `run-as … cp` (debug builds only) |

  `--fresh` drops an empty `qa_reset`; `--seed <file>` copies a full-backup
  JSON as `qa_seed.json`. Fixtures live in `tool/qa/fixtures/*.json`.
- **Caveat**: while a QA build is installed, the app icon opens the *QA*
  database. The owner gets their data back on the next normal `flutter run`.
