# Fasting Schedule Roadmap — ANTA

**Status: shipped (2026-08-16).** Everything below is implemented. The running
behaviour is described in `docs/calendar-events-feature.md` §4.5 — read that
first; this file is kept as the design record (why each decision was made, and
what was deliberately left out).

**What shipped:** one personal *schedule* — weekdays + months + a month scope +
exception dates — persisted in a single `calendar_fasting_schedule` JSON key
with a fallback read of the retired weekday CSV; 42 engine and model unit tests
(`test/constants/fasting_calendar_test.dart`,
`test/models/fasting_schedule_test.dart`); and the `FastingCalendar`
reset hook, wired through `SettingsService.reset`.

## Addendum — weekday scope (2026-08-22)

The weekday set gated **only** the year-round weekly rule, while the month set
had a scope selector. That asymmetry was never a decision — it is simply what
shipped, and it made "I keep Wednesdays and Fridays" impossible to express for
Great Lent, which marked all forty days regardless.

`FastingWeekdayScope` mirrors `FastingMonthScope` exactly: `weeklyOnly` (default,
today's behaviour) and `allFasts`, which gates every fasting mark. It rides in
the same `calendar_fasting_schedule` JSON under `weekdayScope`, decoded through
`fromName`, so a blob written before this addendum reads as `weeklyOnly` and no
existing practice narrows behind the user's back. The gate is one probe inside
`_buildYear`'s `merge`, next to the month twin — the new row in the filter table
above:

```
| `weekdays` (`allFasts`) | `merge` in `_buildYear` | 1 probe per produced entry |
```

Still **subtract-only**: the scope can only remove days, never invent one, and
`forceDates` still wins on an off weekday. In the sheet it is a `ChoiceChip` pair
under the weekday chips, reusing `fastingMonthScopeWeekly` /
`fastingMonthScopeAll` for the options (same question, different axis) with new
`fastingWeekdayScopeTitle` key and a hint pair (see the fix below).

Because it is a `FastingSchedule` field and `configure` compares whole schedules
through `Equatable`, the warm per-year maps invalidate for free.

**One deviation from the plan as written:** `FastingSchedule` parses exception
dates with a strict `yyyy-MM-dd` pattern instead of `DateTime.tryParse`, which
silently rolls `2026-13-99` over into a real (wrong) date. A corrupt row is
dropped, never relocated.

---

## Context

The fasting engine derives every fasting day deterministically from
(year, tradition); nothing is persisted except the configuration. Today the only
personal knob is *which weekdays* you keep, and its chips render only while the
Orthodox tradition is enabled — even though `FastingCalendar` reads the setting
unconditionally and the Catholic Friday abstinence is hardcoded.

What a real personal practice needs and cannot express: **which months** you keep
the fast in, and **which exact days** you skip (a birthday, a wedding) or add.

The goal is one "my practice" schedule, visible for any enabled tradition, in a
single settings key, without touching the engine's performance profile
(O(365) build once per year per tradition, O(1) lookups afterwards).

Two standing debts are folded in because they are cheap here: `FastingCalendar`
is a static singleton with **no reset hook** on a database switch, and the engine
— pure static date math — has **no tests**.

### Decisions taken

1. The month filter carries a **scope selector**: `weeklyOnly` (default — only
   the weekly rule) vs `allFasts` (a disabled month hides every fasting mark,
   all traditions included).
2. **One shared schedule**, shown whenever any tradition is enabled.
3. Exception dates support both **skip** and **force**.

### Design decision: the weekday set vs. Catholic Friday abstinence

The schedule may **subtract** from a tradition's own weekly rule, never **invent**
days that tradition does not have:

- Orthodox: unchanged — the weekly loop marks exactly the days in the set.
- Catholic: the year-round loop stays **Friday-only**, but is skipped entirely
  when Friday ∉ `weekdays`.

Reading the set literally would fabricate a "Catholic Wednesday abstinence" —
doctrinally wrong and never asked for. Leaving Catholic hardcoded would make a
schedule *presented as global* silently not apply to half the enabled
traditions. Lent/Advent Fridays and Good Friday belong to the seasonal fast, not
the weekly rule, and are untouched either way — symmetric with Orthodox, where
the weekly loop only fills days no great fast claimed.

---

## Files

**New**: `lib/models/fasting_schedule.dart`,
`lib/widgets/fasting_schedule_sheet.dart`,
`test/models/fasting_schedule_test.dart`,
`test/constants/fasting_calendar_test.dart`

**Modified**: `lib/constants/fasting_calendar.dart`,
`lib/constants/settings_keys.dart`, `lib/services/settings_service.dart`,
`lib/pages/calendar_settings_page.dart`, `lib/pages/calendar_page.dart`,
`lib/l10n/app_{en,de,ro}.arb`

**Untouched**: `day_summary_resolver.dart`, `day_bars_resolver.dart`,
`calendar_day_cell.dart`, `fasting_style_sheet.dart`, `backup_service.dart`, all
Drift files. **No migration, no build_runner.**

---

## 1. `lib/models/fasting_schedule.dart` (new)

Mirrors `lib/models/fasting_appearance.dart` exactly: `Equatable`, per-field
forward-compatible degradation, an `encode()`/`decode()` pair, `fromName` on the
enum, rich doc comments (this file family uses them).

```dart
enum FastingMonthScope { weeklyOnly, allFasts;
  static FastingMonthScope fromName(String? name) { …; return weeklyOnly; } }
```

| Field | Type | Default |
| --- | --- | --- |
| `weekdays` | `Set<int>` 1..7 | `{wednesday, friday}` |
| `months` | `Set<int>` 1..12 | all twelve |
| `monthScope` | `FastingMonthScope` | `weeklyOnly` |
| `weekdayScope` | `FastingWeekdayScope` | `weeklyOnly` |
| `skipDates` | `Set<DateTime>` UTC midnight | `{}` |
| `forceDates` | `Set<DateTime>` UTC midnight | `{}` |

Statics: `defaultWeekdays`, `allMonths`, `maxExceptionDates = 200`. Members:
`keepsEveryMonth`, `exceptionCount`, `copyWith`.

`copyWith` **normalizes**: clamps `weekdays` to 1..7 and `months` to 1..12,
date-onlys every `DateTime` to UTC midnight, removes from `skipDates` anything
present in `forceDates` (**force wins**), truncates each set to
`maxExceptionDates` (sorted ascending, oldest kept).

`encode()` — always writes the three structural fields, omits empty date lists
(the same discipline as `FastingTraditionStyle.toJson`):

```json
{"weekdays":[3,5],"months":[1,2,3,4,5,6,7,8,9,10,11,12],
 "monthScope":"weeklyOnly","skip":["2026-03-15"],"force":["2026-05-01"]}
```

`static FastingSchedule decode(String? raw, {String? legacyWeekdayCsv})` — a
decode ladder that never throws:

1. `raw` starts with `{` → `jsonDecode` inside `try/on FormatException`. Per
   field: `weekdays`/`months` — `is List` → valid ints (**an empty list stays
   empty**), otherwise the default; `monthScope` through `fromName`;
   `skip`/`force` through `DateTime.tryParse`, unparseable entries dropped. The
   result passes through the same normalization `copyWith` uses.
2. `raw` absent/empty/unparseable **and** `legacyWeekdayCsv != null` →
   `FastingSchedule(weekdays: _parseWeekdayCsv(legacy))`, everything else
   default. `''` → empty set; `'3,5'` → `{3,5}`; invalid parts dropped.
3. Otherwise → `const FastingSchedule()`.

> **Critical**: the absent-vs-empty distinction lives at the service boundary.
> `decode` must treat `legacyWeekdayCsv: null` (never set → Wed+Fri) and `''`
> (deliberately cleared → none) **differently**.

`props` covers all five fields — `Equatable` uses `DeepCollectionEquality`, so
`Set` comparison is order-independent, which `configure` relies on.

---

## 2. Engine — `lib/constants/fasting_calendar.dart`

**Enum**: append a `// ── Personal ──` group to `FastingPeriod` with
`personalFast`; `periodNameOf` gains `=> l10n.fastingPersonalFast` (the
exhaustive switch makes the compiler enforce it). `FastingPeriod` is never
persisted — zero compatibility risk.

**State**: delete `defaultWeekdayFastDays` and `_weekdayFastDays`; add
`static FastingSchedule _schedule = const FastingSchedule();` plus a `schedule`
getter.

**`configure`**: the `weekdayFastDays` parameter becomes
`FastingSchedule schedule = const FastingSchedule()`. The manual set comparison
disappears — `schedule == _schedule` covers all five fields. Update the doc
comment: the *schedule* is compute-affecting, appearance is not.

**`resetConfiguration()`** (new): clears `_traditions`, `_appearance`,
`_orthodoxGreatFasts`, `_schedule` and both caches.

**`_buildYear`** — the `allFasts` month filter applies **inside the `merge`
closure**, not in a later pass (O(1) per already-produced entry, no second
traversal of the merged map):

```dart
final filterEveryFast = _schedule.monthScope == FastingMonthScope.allFasts;
void merge(Map<DateTime, FastingInfo> tradition) {
  tradition.forEach((day, info) {
    if (filterEveryFast && !_schedule.months.contains(day.month)) return;
    (out[day] ??= []).add(info);
  });
}
// … the four existing tradition calls, unchanged …
_applyExceptions(year, out);
```

**`_applyExceptions(year, out)`** (new, runs last): iterates the date sets
(hand-picked and capped), not the year map. `skipDates` → `out.remove(day)`.
`forceDates` → when the day is not already marked,
`FastingInfo(owner, personalFast, oil)`, where `owner` is the **first enabled
tradition in declaration order** — the same one whose colour and icon the grid
uses for a single-tradition day. No enabled traditions → return.

**`_buildOrthodox`**, the weekly loop — two `Set.contains` probes inside the
existing O(365) pass:

```dart
if (!_schedule.weekdays.contains(d.weekday)) continue;
if (!_schedule.months.contains(d.month)) continue;
if (map.containsKey(d) || fastFree.contains(d)) continue;
```

**`_buildCatholic`**, the year-round Friday abstinence — the loop is wrapped in
`if (_schedule.weekdays.contains(DateTime.friday)) { … }` and gains the month
probe; a comment states the subtract-only rule. `_buildMuslim` / `_buildJewish`
stay untouched (their fasts are seasonal/fixed — only the `allFasts` month filter
in `merge` and the exception dates can reach them).

| Filter | Applied where | Cost |
| --- | --- | --- |
| `weekdays` | Orthodox/Catholic weekly loops | 1 probe/day, existing pass |
| `months` (always) | the same loops | 1 probe/day, existing pass |
| `months` (`allFasts`) | `merge` in `_buildYear` | 1 probe per produced entry |
| `weekdays` (`allFasts`) | `merge` in `_buildYear` | 1 probe per produced entry |
| `skip`/`force` | `_applyExceptions`, after merge | O(≤400) per year build |
| `on` / `cellStyleFor` | **unchanged** | O(1) |

---

## 3. Settings

**`settings_keys.dart`**: keep `calendarFastingWeekdays` (still *read* as the
seed, doc comment updated) and add
`calendarFastingSchedule = 'calendar_fasting_schedule'`.

**`settings_service.dart`**: replace `getFastingWeekdays`/`setFastingWeekdays`
(~685-708) with `getFastingSchedule`/`setFastingSchedule`. The getter reads the
new key; when it is absent it reads the legacy CSV and passes it as
`legacyWeekdayCsv` **including when it is `''`**.

`SettingsService.reset()` — already registered as a `DatabaseLifecycle` reset
handler at `settings_service.dart:25` — gains
`FastingCalendar.resetConfiguration();`, exactly the `PublicHolidayService.reset()`
pattern. **Do not** register `FastingCalendar` with `DatabaseLifecycle` directly:
the registry self-clears after each `notifyDatabaseSwitching()`, so a
registration made once from `calendar_page` would fire once and never again,
while one per `_loadSettings()` call would accumulate duplicates.

**`calendar_page.dart`** (~80, ~88): `getFastingSchedule()` →
`schedule: fastingSchedule` in `FastingCalendar.configure`.

---

## 4. UI — `FastingScheduleSheet` (new)

**Why a sheet, not inline chips**: the fasting section already carries up to 4
switches + 4 appearance rows + the great-fasts switch + 7 chips. Another 12 month
chips, a scope selector and two date lists would double the tallest section on
the page, and `SettingsSectionList`'s search would match a wall of chips with no
useful title. `lib/widgets/fasting_style_sheet.dart` is the exact local
precedent: **one summary row → a modal with live `onChanged` persistence**. The
weekday chips **move into** the sheet.

Structure 1:1 after `FastingStyleSheet`:
`FractionallySizedBox(heightFactor: 0.86)`, a header with close +
`titleLarge`, `ListView(padding: fromLTRB(20, 8, 20, 24))`, a private `_label`
helper. No text fields → **no debounce**; every control writes through
`_apply(next)` (`setState` + `onChanged`).

```dart
static Future<void> show(BuildContext context, {
  required FastingSchedule initialSchedule,
  required CalendarAppearance appearance,   // for CalendarDatePickerSheet
  required ValueChanged<FastingSchedule> onChanged,
});
```

Sections, top to bottom:

1. **`fastingWeekdayDaysTitle`** (reused) with a `selectAll`/`selectNone` pair in
   the label row. The 7 `FilterChip`s use
   `RecurrenceFormatter.weekdayShort(w, l10n.localeName)` — the code lifted from
   `calendar_settings_page.dart:712-728`. Caption: `fastingWeekdayDaysDesc`
   (reused).
2. **`fastingMonthsTitle`** with the same pair. 12 `FilterChip`s; the label comes
   from `intl`, **never an ARB month matrix** —
   `DateFormat.MMM(localeName).format(DateTime.utc(2024, month))` through
   `toBeginningOfSentenceCase`, the same shape as `_weekStartLabel` and
   `MonthYearPickerSheet`.
3. **`fastingMonthScopeTitle`** — two `ChoiceChip`s (`…Weekly` / `…All`) plus
   `fastingMonthScopeHint` in `bodySmall`/`onSurfaceVariant`. It stays visible
   **even when all twelve months are ticked**: the user has to understand what
   turning a month off will do *before* turning it off.
4. **`fastingExceptionsSkipTitle`** + hint.
   `OutlinedButton.icon(Icons.event_busy_rounded, fastingAddDates)` →
   `CalendarDatePickerSheet.pickMulti(context, initialSelection: const {},
   firstDate: CalendarBounds.earliest, lastDate: CalendarBounds.latest,
   appearance: …)`. `pickMulti` returns `null` for both dismiss and empty, so it
   is used **purely additively** (`skipDates ∪ picked`) and removal happens in
   the list below — sidestepping its "never returns an empty set" contract
   without changing it. Under the button: the sorted dates as
   `ListTile(dense: true)` rows with `DateFormat.yMMMEd(localeName)` and
   `IconButton(Icons.close_rounded, tooltip: l10n.remove)`. Button disabled +
   `fastingExceptionsFull` at `maxExceptionDates`.
5. **`fastingExceptionsForceTitle`** + hint — identical structure,
   `Icons.event_available_rounded`, writes `forceDates`.

Adding a date to one list removes it from the other (the model's `copyWith`
normalization does it; the sheet just calls `copyWith`).

### `calendar_settings_page.dart`

- State: `Set<int> _fastingWeekdays` (line 66) →
  `FastingSchedule _fastingSchedule = const FastingSchedule();`; `_loadSettings`
  reads `getFastingSchedule()`.
- Delete `_toggleFastingWeekday` (157-165) and the chips `SettingsEntry`
  (695-735).
- Add `_editFastingSchedule()` (after the `_editFastingStyle` pattern) and
  `_fastingScheduleSummary(l10n)` → `"Wed, Fri · All year · 3 exceptions"`
  (weekdays via `RecurrenceFormatter.formatWeekdays`; `fastingScheduleNoDays` /
  `fastingScheduleNoMonths` / `fastingScheduleAllYear` / `fastingMonthsCount`
  for the edge cases).
- **After** the `if (orthodox)` block (which keeps only the great-fasts switch),
  add a `SettingsEntry` gated on `if (_fastingTraditions.isNotEmpty)`: a
  `ListTile` with `Icons.event_repeat_rounded`, title `fastingScheduleTitle`,
  the summary as subtitle, `onTap: _editFastingSchedule`, and
  `keywords: [fastingWeekdayDaysTitle, fastingMonthsTitle,
  fastingExceptionsSkipTitle]` so settings search still finds those labels now
  that they live inside a sheet.
- Reset to defaults (~919, ~936):
  `setFastingSchedule(const FastingSchedule())` +
  `_fastingSchedule = const FastingSchedule()`.

---

## 5. Localization

New keys in all three ARB files, right after `fastingDescriptionHint`. `@`
metadata blocks **only in `app_en.arb`** (de/ro are plain value maps, including
for plurals — precedent: `recurrenceEveryWeeks`).

| Key | en | de | ro |
| --- | --- | --- | --- |
| `fastingScheduleTitle` | My practice | Meine Praxis | Rânduiala mea |
| `fastingScheduleAllYear` | All year | Ganzes Jahr | Tot anul |
| `fastingScheduleNoDays` | No weekly days | Keine wöchentlichen Tage | Fără zile săptămânale |
| `fastingScheduleNoMonths` | No months kept | Keine Monate | Nicio lună |
| `fastingMonthsTitle` | Months you keep | Monate, die du hältst | Lunile pe care le ții |
| `fastingMonthScopeTitle` | Months apply to | Monate gelten für | Lunile se aplică la |
| `fastingMonthScopeWeekly` | Weekly fast only | Nur wöchentliches Fasten | Doar postul săptămânal |
| `fastingMonthScopeAll` | All fasts | Alle Fastenzeiten | Toate posturile |
| `fastingMonthScopeHint` | A month you turn off is never marked | Ein ausgeschalteter Monat wird nie markiert | O lună dezactivată nu e marcată niciodată |
| `fastingExceptionsSkipTitle` | Days off | Freie Tage | Zile libere |
| `fastingExceptionsSkipHint` | Never marked, whatever the calendar says | Nie markiert, egal was der Kalender sagt | Nemarcate, orice ar spune calendarul |
| `fastingExceptionsForceTitle` | Extra fast days | Zusätzliche Fastentage | Zile de post în plus |
| `fastingExceptionsForceHint` | Always marked, even outside your practice | Immer markiert, auch außerhalb deiner Praxis | Marcate mereu, chiar în afara rânduielii |
| `fastingExceptionsFull` | Limit reached | Grenze erreicht | Limită atinsă |
| `fastingAddDates` | Add dates | Daten hinzufügen | Adaugă date |
| `selectNone` | None | Keine | Niciuna |
| `fastingPersonalFast` | Personal fast | Persönliches Fasten | Post personal |

Two ICU plurals (Romanian needs `few`), with
`"placeholders": {"count": {"type": "int", "example": "3"}}` in the en `@` block:

- `fastingMonthsCount` — en `{count, plural, =1{1 month} other{{count} months}}`
  · de `{count, plural, =1{1 Monat} other{{count} Monate}}`
  · ro `{count, plural, =1{1 lună} few{{count} luni} other{{count} de luni}}`
- `fastingExceptionsCount` — en `{count, plural, =1{1 exception} other{{count} exceptions}}`
  · de `{count, plural, =1{1 Ausnahme} other{{count} Ausnahmen}}`
  · ro `{count, plural, =1{1 excepție} few{{count} excepții} other{{count} de excepții}}`

Reused, **do not redefine**: `selectAll`, `remove`, `fastingWeekdayDaysTitle`,
`fastingWeekdayDaysDesc`, `fastingSectionTitle`, `fastingSectionDesc`.

---

## 6. Tests

`test/models/fasting_schedule_test.dart` — the defaults; an `encode`→`decode`
round-trip across all five fields; `decode(null)` → defaults;
`decode(null, legacy: '3,5')` → `{3,5}`; **`decode(null, legacy: '')` → empty
set** (the deliberate "none" case survives); a CSV with garbage → only the valid
values; `'not json'` and `'{oops'` → defaults, no throw; an unknown `monthScope`
→ `weeklyOnly`; `months` absent → all 12 vs `"months": []` → empty (absent ≠
empty), same for `weekdays`; bad dates dropped, good ones as UTC midnight; a date
in both sets ends up **only** in `force`; `copyWith` normalizes local→UTC and
drops 0/8 and 0/13; more than `maxExceptionDates` → exactly the cap; equality is
set-order-independent (the basis of `configure`'s no-op path).

`test/constants/fasting_calendar_test.dart` —
`setUp(() => FastingCalendar.resetConfiguration())` is **mandatory** (a static
facade, otherwise tests leak configuration into each other).

- *Weekly*: Wed/Fri marked, Thu not; an empty set → the whole year empty;
  `{monday}` → only Mondays; fast-free windows still win (the Wednesday of Bright
  Week is empty); a great-fast day is not overwritten by `weekdayFast`.
- *Months*: `weeklyOnly` without January → no `weekdayFast` in January, February
  untouched; `weeklyOnly` without December with great fasts on → the Nativity
  Fast **survives**; `allFasts` without December → December entirely empty,
  November untouched; `months: {}` + `allFasts` → an empty year.
- *Catholic*: default → 2026-07-03 is `fridayAbstinence`;
  `weekdays: {wednesday}` → no Friday abstinence anywhere **and no** invented
  Wednesday fast; `weekdays: {}` → Good Friday / Ash Wednesday / Lent weekdays
  survive (seasonal ≠ weekly).
- *Exceptions*: a skip removes a computed day; a skip on an unmarked day is a
  no-op; a force on an unmarked day → exactly one `FastingInfo`
  `personalFast`/`oil` attributed to the first enabled tradition; Catholic-only →
  attributed to Catholic; a force on an already-marked day does not duplicate.
- *Cache/configure*: `configure` twice with equal schedules keeps the year map
  (`identical`); changing `months` invalidates it; changing only the appearance
  keeps the map warm while `cellStyleFor` reflects the new colour.
- *Reset*: after `resetConfiguration()` → `isEnabled` false, `on()` empty,
  `cellStyleFor().isEmpty`; reconfiguring after a reset yields the new
  configuration's answers (both caches were dropped).

---

## 7. Execution order

1. `fasting_schedule.dart` → 2. `fasting_calendar.dart` → 3. `settings_keys.dart`
→ 4. `settings_service.dart` → 5. the three ARB files + `flutter gen-l10n` (the
`periodNameOf` switch needs `fastingPersonalFast` to exist) →
6. `fasting_schedule_sheet.dart` → 7. `calendar_settings_page.dart` →
8. `calendar_page.dart` → 9. the tests.

## 8. Verification

```powershell
flutter gen-l10n
Get-Content untranslated.txt      # no new fasting* key listed
dart analyze lib
flutter test test/models/fasting_schedule_test.dart
flutter test test/constants/fasting_calendar_test.dart
flutter test
flutter run -d windows            # Calendar > settings > Religious fasting > My practice
```

No `build_runner` — nothing Drift-shaped changes.

Manual: toggle months under both scopes and confirm the grid and day panel update
on returning from settings; add an exception day and check the panel row; switch
databases and confirm the grid no longer carries the previous database's
practice.

## 9. Risks

1. **Backup** — the assumption that backups dump every `user_settings` row is
   **false**: `BackupService._exportSettings`
   (`lib/services/backup_service.dart:144-185`) exports a fixed allowlist that
   contains **no `calendar_*` key at all**, the existing fasting keys included.
   So the new key regresses nothing — but it does not enter the JSON backup
   either. "Share Database" copies the whole file, so it survives there. **Do not
   touch the allowlist here**: adding only the schedule key would restore a
   practice with no traditions enabled, incoherent with its siblings. Putting
   calendar settings in JSON backups is a separate, deliberate change that adds
   the whole `calendar_fasting_*` family at once.
2. **Downgrade (accepted)** — once the new key is written,
   `calendar_fasting_weekdays` is never written again, so an older build would
   read the stale CSV. Exactly how `calendar_fasting_style` was retired
   (read-as-seed, never re-written). Mirroring the CSV on every write would fix
   it at the cost of a key that never dies — **don't**.
3. **Absent vs. empty in the legacy CSV** — the single most breakable thing.
   `getFastingSchedule` must pass `legacyWeekdayCsv` including when it is `''`,
   and `decode` must distinguish `null` from `''`. The two dedicated tests do not
   get merged.
4. **Removing `defaultWeekdayFastDays`** touches 4 call sites
   (`settings_service.dart:691`, `calendar_settings_page.dart:66,920,936`) — all
   rewritten above; `dart analyze lib` catches any miss.
5. **`allFasts` + zero months** is a legitimate state that blanks the whole
   calendar. `fastingMonthScopeHint` and `fastingScheduleNoMonths` exist so it is
   never a mystery — **do not** reject the empty month set.

---

## Deferred, not planned here

Ideas considered and left out, recorded so they are not re-derived:

- **Per-tradition schedules** (each tradition with its own days/months). The JSON
  shape above can gain a `byTradition` object later without a key change, but the
  UI cost is real and months are meaningless for Ramadan / the Jewish fasts.
- **Custom user-defined fasting periods** (arbitrary named date ranges). That
  wants a table, not a settings key — closer to a calendar category than to the
  computed engine.
- **Surfacing today's fast outside the calendar** (drawer, upcoming agenda).
  `FastingCalendar.isFastingDay` exists and is currently unused; note that the
  facade is only configured once `CalendarPage` mounts, so any earlier consumer
  needs configuration moved to app start first.

## Fix — the scope hints described only one branch (2026-08-23)

Reported as "I set Wednesday and Friday, but most of August is tinted". It
reproduces, and the engine is right: with the default `weeklyOnly` scope,
August 2026 marks **19 of 31** days for an Orthodox Wed/Fri practice — the
Dormition Fast owns Aug 1–14 outright, the Beheading of St John takes Aug 29,
and only the four remaining Wednesdays and Fridays come from the weekly rule.
Switch the weekday scope to `allFasts` and the same month drops to 8 days.
Nothing in `FastingCalendar`, `FastingSchedule`, `SettingsService` or the
page's `configure` call was wrong.

What *was* wrong is what the sheet told the user. Both scope selectors printed
a single static hint describing only the `allFasts` branch — "A day you turn
off is never marked" and "A month you turn off is never marked" — under a
control whose **default** is `weeklyOnly`, where a multi-day fast still marks
every one of its days. The month hint shipped that way with the per-month
commit and the weekday one copied it. So the app stated the exact opposite of
what it does out of the box, and a correctly-configured practice read as a bug.

The hint is now chosen by the selected scope
(`_weekdayScopeHint` / `_monthScopeHint` in `fasting_schedule_sheet.dart`),
against four keys in place of two: `fastingWeekdayScopeHintWeekly` /
`fastingWeekdayScopeHintAll` and `fastingMonthScopeHintWeekly` /
`fastingMonthScopeHintAll`. `test/widgets/fasting_schedule_sheet_test.dart`
pins each scope to its hint, in both axes and across a chip tap.

**Left alone, deliberately — two open questions for the user:**

1. **The default is still `weeklyOnly`.** It is the pre-existing behaviour and
   the documented choice, and flipping it would silently rewrite the calendar
   of every install that already set weekdays. If "Wednesdays and Fridays,
   whatever the season" is the practice most people mean when they pick
   weekdays, `allFasts` is arguably the better default — but that is a product
   decision with a data-visible blast radius, not a bug fix.
2. **`_weekdayScopeLabel` still reuses `fastingMonthScopeWeekly` /
   `fastingMonthScopeAll`** for the option labels. Correct today ("Weekly fast
   only" / "All fasts" read fine on both axes), but it means rewording the
   month options silently rewords the weekday ones.
