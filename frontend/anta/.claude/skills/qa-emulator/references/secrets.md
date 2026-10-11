# Secrets

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

## Secrets and credentials files

- `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`
  and `lib/firebase_options.dart` are machine-local and gitignored. The
  Android one must sit in **`android/app/`**: one level up Gradle does not
  find it (`File google-services.json is missing`). `.gitignore` also ignores
  these names anywhere in the tree (and the `google_services.json` spelling,
  `key.properties`, keystores and service-account JSON), so a copy dropped in
  the wrong folder cannot be staged by `git add -A`.
- Never `cat` those files, paste their contents into a command, a doc, a
  commit message or a step file, or attach them to anything. To check one,
  print its structure with the values masked.
- Screenshots, dumps and logs live under `build/qa/`, which is ignored. Do not
  copy them into the repo or into `docs/`.
