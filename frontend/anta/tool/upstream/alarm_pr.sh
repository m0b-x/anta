#!/usr/bin/env bash
# Opens the upstream pull request for the first two of the Android patches
# the local `packages/alarm/` fork carries (event alerts OS-1, decisions B1
# and B4 in docs/event-alerts-os-integration-roadmap.md): alarm-clock
# scheduling and content:// sounds. It rebuilds the patches from the fork's
# own files on a fresh clone of gdelataillade/alarm at the fork's base tag,
# one commit per patch plus a changelog line, pushes the branch to a fork
# under the GitHub account `gh` is logged in as, and opens the PR from there.
#
# Before opening the PR: the fork carries nine patches now
# (packages/alarm/CHANGELOG.md), and the first commit here is no longer
# Patch 1 alone. It copies the fork's AlarmService.kt whole, for the
# ACTION_SHOW constant, and that file has since gained all of Patch 6 (the
# ring's wake lock, held in AlarmService.RingWakeLock and released when the
# ring ends) and a comment saying AlarmReceiver is no longer exported, which
# is Patch 5: a line of the library's manifest that nothing here copies, so
# upstream the comment would be false. Neither is in the commit messages,
# the changelog entry or the PR body below, and Patch 6's
# RingWakeLockTest.kt is not copied. Patches 3, 4 and 7 to 9
# (NotificationService.kt, AlarmPlugin.kt, platform_timers.dart,
# NotificationSettings.kt, alarm.dart) are in no commit here at all.
#
# So a run without --dry-run is refused, before anything is cloned or
# written, while the fork's AlarmService.kt matches RingWakeLock or carries
# Patch 5 or 6 mentions ("Patch 5)", "Patch 6)"), with one line on stderr
# and exit 1; the file's "(ANTA fork, Patch 1)." — the patch this PR is
# for — does not match. The check reads the fork's file, not the copy, so
# it lifts by itself only once none of them is in that file: whoever gives
# Patch 6 a commit and a paragraph of its own, or takes them all out of the
# copy, takes the check out too. A dry run still goes through: it pushes
# nothing, and what it prints — its diffstat, and the branch it leaves at
# the printed path — is how to see what the copy would carry.
#
#   ./tool/upstream/alarm_pr.sh            # clone, commit, push, open the PR
#   ./tool/upstream/alarm_pr.sh --dry-run  # clone and commit only; print the diffstat and the branch's path
#
# Needs git and a logged-in `gh` (`gh auth login`). The account needs no
# rights on the upstream repository: `gh repo fork` creates or reuses a fork
# under it, and the PR is opened from that fork. Re-runnable: a fresh clone
# every time, nothing is written into this repository.
set -euo pipefail

upstream_repo="gdelataillade/alarm"
base_tag="v5.13.2"
branch="anta/alarm-clock-and-content-uris"
title="Android: arm exact alarms with setAlarmClock, play content:// sounds directly"

here="$(cd "$(dirname "$0")/../.." && pwd)"
fork="$here/packages/alarm"
kotlin="android/src/main/kotlin/com/gdelataillade/alarm"
tests="android/src/test/kotlin/com/gdelataillade/alarm"
dry_run=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        -h|--help) awk 'NR>=2 && /^set -euo pipefail/{exit} NR>=2' "$0"; exit 0 ;;
        *) echo "alarm_pr: unknown argument $arg" >&2; exit 1 ;;
    esac
done

# The header's "Before opening the PR", enforced here rather than trusted to
# a reader: the first commit copies this file whole, and nothing the script
# writes says a word about the wake lock or the Patch 5 or 6 mentions it
# would carry upstream. Silent on a missing file, which the loop below
# reports.
if [ "$dry_run" = 0 ] && grep -qsE 'RingWakeLock|Patch [56]\)' "$fork/$kotlin/alarm/AlarmService.kt"; then
    echo "alarm_pr: refused: packages/alarm/$kotlin/alarm/AlarmService.kt still carries Patch 6 (RingWakeLock) or Patch 5 or 6 mentions (\"Patch 5)\", \"Patch 6)\"), which no commit, changelog line or PR body here describes; all must be out of it (see this script's header; --dry-run still runs)" >&2
    exit 1
fi

for f in "$kotlin/alarm/AlarmService.kt" "$kotlin/services/AlarmScheduler.kt" \
         "$kotlin/services/AudioService.kt" "$tests/services/AudioServiceTest.kt"; do
    [ -f "$fork/$f" ] || { echo "alarm_pr: $fork/$f is missing" >&2; exit 1; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/alarm-pr.XXXXXX")"
echo "alarm_pr: working in $work"
git clone -q "https://github.com/$upstream_repo" "$work/alarm"
cd "$work/alarm"
git checkout -q -b "$branch" "$base_tag"

cp "$fork/$kotlin/alarm/AlarmService.kt" "$kotlin/alarm/AlarmService.kt"
cp "$fork/$kotlin/services/AlarmScheduler.kt" "$kotlin/services/AlarmScheduler.kt"
git add -A
git commit -q -F - <<'MSG'
[Android] Arm exact alarms with AlarmManager.setAlarmClock

setAlarmClock is the one AlarmManager entry point that carries alarm
semantics through the platform: the entry is exempt from Doze and the
standby buckets by the platform's own definition, it is shown as the
device's next alarm (status-bar icon, lock-screen line, Quick Settings,
getNextAlarmClock()), and its show intent is what those surfaces open.
setExactAndAllowWhileIdle gave none of that, and a restricted standby
bucket was still allowed to defer it.

The show intent is the application's launch intent carrying the new
AlarmService.ACTION_SHOW and the alarm id under EXTRA_ALARM_ID, so an app
can land on its alarm list instead of a cold start; a package with no
launch intent gets a null show intent, which AlarmClockInfo allows.

The canScheduleExactAlarms guard, the SecurityException fallback and both
inexact fallbacks are unchanged: setAlarmClock needs the same exact-alarm
permission on Android 12-13. Below API 21 setExact stays.
MSG

cp "$fork/$kotlin/services/AudioService.kt" "$kotlin/services/AudioService.kt"
mkdir -p "$tests/services"
cp "$fork/$tests/services/AudioServiceTest.kt" "$tests/services/AudioServiceTest.kt"
git add -A
git commit -q -F - <<'MSG'
[Android] Play content://, android.resource:// and file:// sounds directly

AudioService.playAudio hands such a value to
MediaPlayer.setDataSource(Context, Uri) before the asset and path
branches: the !startsWith("/") rewrite there would otherwise prepend the
app's files directory to a URI and hand the player a path that names
nothing. An app can now pass the ringtone picker's URI straight through
assetAudioPath without copying the file first.

A URI the device cannot open (a sound picked on another phone, restored
here) falls back to the device's default alarm sound rather than leaving
the alarm silent, the same resolution the null path uses.

AudioServiceTest pins which values take the URI branch.
MSG

python3 - "$PWD/CHANGELOG.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
entry = (
    "## Unreleased\n"
    "* **[Android] Exact alarms are armed with `AlarmManager.setAlarmClock`.** "
    "An alarm is now exempt from Doze and the standby buckets by the platform's own definition "
    "and is shown as the device's next alarm (status-bar icon, lock screen, Quick Settings); "
    "its show intent launches the app with `AlarmService.ACTION_SHOW` and the alarm id under `EXTRA_ALARM_ID`.\n"
    "* **[Android] `content://`, `android.resource://` and `file://` sounds play directly** "
    "through `MediaPlayer.setDataSource(Context, Uri)`, falling back to the device default alarm sound "
    "when the URI cannot be opened.\n\n"
)
p.write_text(entry + s)
PY
git add -A
git commit -q -m "Changelog for setAlarmClock and URI sounds"

echo "alarm_pr: three commits on $branch over $base_tag"
git --no-pager log --oneline "$base_tag..HEAD"
git --no-pager diff --stat "$base_tag..HEAD"

body="$work/pr-body.md"
cat > "$body" <<'BODY'
Two Android changes, both inside Kotlin that the Pigeon-generated bindings never reference — no Dart or wire change.

### 1. `AlarmScheduler.setExactAlarm` arms with `AlarmManager.setAlarmClock`

`setAlarmClock` is the one `AlarmManager` entry point that carries alarm semantics through the platform. Compared with `setExactAndAllowWhileIdle`, an entry armed with it is

- **exempt from Doze and from the standby buckets** by the platform's own definition — today an exact-while-idle alarm can still be deferred in the `restricted` bucket and by OEM battery managers that only respect real alarms;
- **shown as the device's next alarm**: the status-bar alarm icon, the lock-screen line, Quick Settings, and `getNextAlarmClock()` for everything that reads it (Bedtime mode, assistants, some watches and launchers);
- **openable**: `AlarmClockInfo.showIntent` is what the lock-screen line and Quick Settings launch. It is built as the application's launch intent carrying a new `AlarmService.ACTION_SHOW` action and the alarm id under `EXTRA_ALARM_ID`, so an app can land on its alarm list rather than on a cold start. A package with no launch intent gets a null show intent, which `AlarmClockInfo` allows.

The `canScheduleExactAlarms` guard, the `SecurityException` fallback and both inexact fallbacks are unchanged — `setAlarmClock` needs the same exact-alarm permission on Android 12–13. Below API 21 (the plugin's `minSdk` is 19) `setExact` stays. The boot receiver's re-arm goes through the same `schedule`, so nothing else changes.

If you would rather keep `setExactAndAllowWhileIdle` as the default, this can sit behind an `AndroidAlarmSettings` flag — say so and I will add the Pigeon field.

### 2. `AudioService.playAudio` plays `content://`, `android.resource://` and `file://` sources directly

Such a value is handed to `MediaPlayer.setDataSource(Context, Uri)` before the asset and path branches — the `!startsWith("/")` rewrite there would otherwise prepend the app's files directory to a URI. This lets an app hand the ringtone picker's URI straight to `assetAudioPath` without copying the file into its own storage first. A URI the device cannot open (a sound picked on another phone) falls back to the device's default alarm sound, the same resolution the `null` path uses, rather than leaving the alarm silent.

### Tests

`AudioServiceTest` (2 cases) pins which values take the URI branch; the existing Android unit tests pass alongside it (50 in total).

### Verified

Android 16 (API 36.1, `google_apis_playstore` arm64 emulator): `dumpsys alarm` lists every entry as an `Alarm clock:` block with the show intent and `temporaryAppAllowlistReasonCode=301`; the status-bar alarm icon and `next_alarm_formatted`; the lock screen's alarm line; the Quick Settings "Alarm, …" row launching the show intent into the app; a `content://media/…` sound picked from the system picker playing verbatim (`AudioService: Using URI sound`); native snooze and stop unchanged. Both patches have been running in production in an app that forks 5.13.2 by path since 2026-09-22.
BODY

if [ "$dry_run" = 1 ]; then
    echo "alarm_pr: dry run — nothing pushed. Branch: $work/alarm ($branch). PR body: $body"
    exit 0
fi

gh auth status >/dev/null 2>&1 || { echo "alarm_pr: gh is not logged in (gh auth login)" >&2; exit 1; }
user="$(gh api user -q .login)"
gh repo fork "$upstream_repo" --clone=false >/dev/null 2>&1 || true
git remote add fork "https://github.com/$user/alarm.git"
git push -q -u fork "$branch"
gh pr create --repo "$upstream_repo" --base main --head "$user:$branch" \
    --title "$title" --body-file "$body"
