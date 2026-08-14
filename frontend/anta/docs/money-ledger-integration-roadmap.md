# Money Ledger Integration Roadmap — ANTA

> **Status: implemented.** All four tiers below shipped (with small
> deliberate deviations: per-note currency UI is a bulk page reached from the
> markdown settings' Money section rather than a utility button; the calendar
> tier attributes a note's net to its event's start-date day only, and `net`
> counts op effects, not `$=` baseline moves). This document stays as the
> design rationale; current behavior is documented in
> `docs/money-ledger-feature.md`.

Forward plan for the money-ledger feature (`docs/money-ledger-feature.md`). The
**engine baseline is shipped**: `$= $+ $- $* $/` ops, `$$` totals, `$?` net
change since the last `$=`, rendered on both the preview and the live editor,
with a `default_money` toolbar shortcut for `$+`. This document covers the four
integration features chosen as the next increment: **currency formatting**
(global + per-note), **toolbar buttons for the remaining ops**, **tap-to-detail
on totals**, and a **calendar day/month money summary**. Read alongside
`docs/money-ledger-feature.md` and the `markdown-engine` skill before starting.

Hard constraint (unchanged): the ledger stays **derived from note content** —
nothing here introduces a counter mutation or a new source of truth for the
balance. Currency is a *display* concern layered on top of the existing pure
`MarkdownMoneySyntax` arithmetic; it must not touch parsing or the fixed-point
cents math.

## Shipped baseline (do not redo)

- **Grammar + arithmetic** — `lib/utils/markdown_money_syntax.dart`
  (`MarkdownMoneySyntax`): parse, `apply` (fixed-point cents, round-half-away-
  from-zero, clamped to ±`balanceLimitCents`), `formatCents` /
  `formatCentsSigned` (plain, no currency symbol — see Tier 1).
- **Preview render** — `LineBasedMarkdownBuilder._computeMoneyLedger()` (one
  O(n) fold per `prepare`) + `_buildMoneyLine` (chrome glyphs, offset-mapped
  amount/label, dimmed running balance on op rows, tinted pill on `$$`/`$?`).
- **Editor render** — `MarkdownEditorLineIndex`'s incremental money pass
  (`moneyValueAt`, mirrors the task pass: per-segment entry balance + `$=`
  anchor snapshots, resumes at the first changed segment) +
  `MarkdownEditorSpanBuilder._buildMoneyLine` / `_moneyTotalSpan` /
  `_EditorMoneyTotalSpan` (fork `CodeInlinePaintSpan`, paints `Σ`/`Δ` + value
  into a placeholder box substituting 1:1 for the second marker char).
- **Palette** — `MarkdownConstants.moneyPositive/moneyNegative/moneyNeutral`.
- **Toolbar** — `default_money` shortcut (`$+ `) in
  `lib/config/default_markdown_shortcuts.dart`, seeded into pre-existing
  profiles via `MarkdownBarService._seedDefaultShortcutIfNeeded('default_money',
  'money_shortcut_seeded')`.

None of this needs to change to add the four features below — they are all
additive.

---

## Tier 1 — Currency formatting (global + per-note)

### Why
The `$` in the syntax is the operator sentinel, not a currency symbol — amounts
are typed as bare numbers (`$+ 12.50`). Users track money in different
currencies (lei, EUR, USD); the display should show a real symbol without
touching the grammar.

### Design
Keep `MarkdownMoneySyntax` currency-agnostic (pure, no settings/I-O — matches
the "pure, cheap" bar every other shared grammar file holds itself to). Add
symbol formatting as a **separate pure helper** in the same file so both
surfaces stay in lockstep:

```dart
// lib/utils/markdown_money_syntax.dart — new static methods, no state added
static String formatCentsWithSymbol(int cents, {required String symbol, required bool suffix});
static String formatCentsSignedWithSymbol(int cents, {required String symbol, required bool suffix});
```

Both wrap the existing `formatCents`/`formatCentsSigned` and just prepend/
append `symbol` (with a thin space) per `suffix`. Existing callers of the
un-suffixed methods keep working — this is purely additive.

### Settings (global default)
- `lib/constants/settings_keys.dart`: `moneyCurrencySymbol` (default `'\$'`),
  `moneyCurrencySuffix` (bool, default `false`).
- `lib/services/settings_service.dart`: `getMoneyCurrencySymbol()` /
  `setMoneyCurrencySymbol(String)`, `getMoneyCurrencySuffix()` /
  `setMoneyCurrencySuffix(bool)` — follow the existing `_getBool`/raw-string
  getter pattern used for other settings.
- Add both raw key strings to `BackupService._exportSettings`'s whitelist so
  the global default survives backup/restore (easy to forget — the report from
  the initial architecture scan flagged this exact whitelist as a common miss).
- Add a small settings UI entry (symbol text field + prefix/suffix toggle) —
  `lib/pages/markdown_settings_page.dart` is the natural home, next to other
  markdown-related toggles.

### Per-note override
Mirror `MarkdownBarService`'s exact precedent for per-note state that needs no
new table: `note_bar_<noteId>` keys in `user_settings`, exported via a
dedicated `_exportNoteBarAssignments`/import pair in `BackupService` (see
`backup_service.dart:103` and the matching import branch) rather than the flat
settings whitelist (whitelist entries are static key strings; per-note keys are
dynamic and need their own prefix-scan export like this one).

- Keys: `money_currency_symbol_<noteId>`, `money_currency_suffix_<noteId>`.
  Absent = inherit the global default (do **not** duplicate the global value
  into every note — only write a key when the note actually overrides it, same
  as `note_bar_<noteId>` only exists for notes with a real override).
- `SettingsService`: `getNoteMoneyCurrencySymbol(noteId) -> String?` (null =
  inherit), `setNoteMoneyCurrencySymbol(noteId, String?)` (null clears the
  override — delete the key), and the suffix-bool equivalents.
- `BackupService`: add `_exportMoneyCurrencyOverrides()` /
  `_importMoneyCurrencyOverrides()` following the `_exportNoteBarAssignments`
  shape exactly (prefix-scan `user_settings`, map noteId → value, defaults on
  missing keys so old backups import unchanged).
- UI: a small currency override control in the note editor's overflow menu or
  settings sheet (reuse whatever per-note override affordance
  `note_bar_assignment_page.dart` already uses as a UI pattern reference).

### Threading into rendering
- **Preview**: add `currencySymbol` / `currencySuffix` fields to
  `LineMarkdownStyle` (constructed once per style-rebuild, same lifecycle as
  `ghostColor`). `_buildMoneyLine` calls
  `MarkdownMoneySyntax.formatCentsWithSymbol(value, symbol: style.currencySymbol, suffix: style.currencySuffix)`
  instead of the bare `formatCents`. `LineMarkdownStyle.fromTheme` (or its
  caller in `markdown_render_service.dart`) needs the resolved effective
  currency (per-note override ?? global) passed in from the page.
- **Editor**: `MarkdownEditorSpanBuilder` has no persistent style struct today
  (it derives everything from the per-line `TextStyle` + `Theme.of(context)`
  at `build()` time) — add two fields (`currencySymbol`, `currencySuffix`) with
  a `configureCurrency(String symbol, bool suffix)` setter, called by the page
  when the note loads / the override changes (same moment the page resolves
  the markdown-bar profile for the note). **Must** clear `_spanCache` and
  `_positionalSpanCache` when currency changes (extend the existing
  style/baseColor/primary/isDark cache-invalidation check in `build()` —
  currency is exactly the same kind of "affects every money line's rendered
  text" input those already guard against).
- Resolve effective currency once per note load in
  `optimized_note_editor_page.dart` (near where the markdown-bar profile is
  resolved for the note) and pass it to both the preview bloc/service and the
  span builder — don't re-resolve per keystroke.

### Effort / risk
**M.** No schema migration (rides `user_settings`, same precedent as note-bar
overrides). Main risk is cache-invalidation correctness on the editor side —
verify with the same "does an unrelated theme rebuild still render the old
currency" check the ghost/tag features already had to pass.

---

## Tier 2 — Toolbar buttons for the remaining ops

### Why
Only `$+` has a one-tap shortcut today; `$- $* $/ $= $$ $?` require typing the
marker by hand, which is worse mobile ergonomics than every other markdown
construct in the toolbar.

### Design
Add six more entries to `lib/config/default_markdown_shortcuts.dart`, each a
plain `wrap`-style shortcut (no new `insertType`, no counter binding — these
are pure text templates, exactly like `default_bold`):

| id | beforeText | suggested icon |
| --- | --- | --- |
| `default_money_subtract` | `$- ` | `Icons.remove_circle_outline` |
| `default_money_multiply` | `$* ` | `Icons.close` |
| `default_money_divide` | `$/ ` | `Icons.call_split` |
| `default_money_set` | `$= ` | `Icons.flag_outlined` |
| `default_money_total` | `$$` | `Icons.functions` |
| `default_money_delta` | `$? ` | `Icons.trending_up` |

Consider renaming the existing `default_money` shortcut's label from "Money" to
"Money +" once its siblings exist, for toolbar scannability (id stays the same
— only the label is user-visible and free to change).

Seed each into pre-existing profiles the same way `default_ghost` /
`default_highlight` / `default_callout` were seeded: one
`_seedDefaultShortcutIfNeeded(id, guardKey)` call per shortcut with its own
guard key (`money_subtract_shortcut_seeded`, etc.) in
`MarkdownBarService`'s init path, right after the existing
`_seedDefaultShortcutIfNeeded('default_money', 'money_shortcut_seeded')` call.
New installs get all seven via `DefaultMarkdownShortcuts.shortcuts` directly
(seeding is a no-op there, matching the existing ghost/highlight/callout
comment about new-install behavior).

`$$` and `$?` shortcuts insert a bare marker with no amount — that's correct,
they're display-only lines.

### Effort / risk
**S.** Same shape as three already-shipped seeding precedents. No renderer
changes needed — the engine already handles all six ops.

---

## Tier 3 — Tap-to-detail on `$$` / `$?` totals

### Why
A total/delta chip currently just shows a number. Tapping it to see *which*
lines produced that number (mirrors how a tag tap routes to search, and a
ghost tap selects its run) turns the ledger into something you can audit
without scrolling.

### Design

#### 1. Shared entry-collector (pure, on-demand — not part of the hot passes)
Add to `MarkdownMoneySyntax` (or a small companion file if it grows) a
non-incremental helper used only on tap, so it doesn't need the fence/task
passes' resumability:

```dart
class MoneyLedgerEntry {
  final int lineIndex;
  final MoneyLineMatch match;
  final int balanceAfter; // or delta value, depending on caller intent
}

// Scans from `fromLine` (exclusive) to `toLine` (inclusive), folding ops and
// collecting every non-fence, non-callout money line in between. Callers
// resolve `fromLine` themselves: 0 for a `$$` total (whole-document), or the
// line index of the most recent `$=` above `toLine` for a `$?` delta.
static List<MoneyLedgerEntry> collectEntries({
  required int Function(int lineIndex) lineAt, // or List<String> lines
  required int toLine,
  int fromLine = 0,
});
```

This runs once per tap (rare, user-initiated), so an O(document) scan is fine
even on large notes — no need to hook it into the incremental passes.

#### 2. Preview tap plumbing
Follow the exact six-call-site pattern the ghost/tag taps already established
(cited in the earlier architecture scan of this feature):
1. New `typedef MoneyTapCallback = void Function(int lineIndex, MoneyLineKind kind)`
   next to `TagTapCallback`/`GhostTapCallback` in `line_based_markdown_builder.dart`.
2. Constructor field on `LineBasedMarkdownBuilder`.
3. `_buildMoneyLine`: for `$$`/`$?` rows, attach a `TapGestureRecognizer`
   cached in `_linkRecognizers` (key `'money:$lineIndex'`) the same way
   `_buildTagSpan`/`_buildGhostSpan` do, calling `onMoneyTap!(lineIndex, m.kind)`.
4. Thread through `MarkdownRenderService` construction params.
5. `MarkdownPreviewBloc.bindCallbacks` (+ stored field) and builder
   construction.
6. `MarkdownPreviewBlocView` field + `_bindCallbacks`.
7. Page handler `_handleMoneyTap(lineIndex, kind)` in
   `optimized_note_editor_page.dart`, opening the detail sheet (see below).

#### 3. Editor tap interception on the painted chip
The `$$`/`$?` value is a `CodeInlinePaintSpan` placeholder (`_EditorMoneyTotalSpan`),
not a widget — tap resolution has to go through the fork's
`CodeEditorTapInterceptor` (`packages/re_editor`, wired in
`modern_editor_wrapper.dart`), the same mechanism the task checkbox and
concealed links use: a zone resolves from line text via
`MarkdownMoneySyntax.parse` (kind ∈ {total, delta}), tap-down claims it (caret
never moves, no keyboard rise), tap-up fires the handler. Follow the existing
pass-through rules exactly (reveal lines, fence lines, oversized lines, ghosts
win) — do not special-case around them.

#### 4. Detail sheet widget
A bottom sheet (reuse `DaySummaryPanel`'s Card-list visual style for
consistency) listing each collected entry: op glyph + accent color (reuse the
existing `MarkdownConstants.moneyPositive/Negative/Neutral` palette so the
sheet visually matches the inline rows), amount, label, running value at that
point. Tapping an entry could jump the editor caret to that line (optional
polish, not required for v1).

### Effort / risk
**M–L.** The plumbing is entirely precedented (six-call-site pattern already
exists twice in this codebase for ghost/tag), but it's a lot of call sites to
touch correctly. The editor tap-interception piece is the trickiest part —
study `_maybeActivateTappedGhost` and the checkbox zone resolution in
`modern_editor_wrapper.dart` closely before writing the money zone.

---

## Tier 4 — Calendar day/month money summary

### Why
Surfacing "how much changed today/this month" on the calendar was flagged as a
clean extension point during the original architecture scan: `DayBarProvider`
and `DaySummaryProvider` are explicitly designed for exactly this ("implement
the provider interface and pass it in — no other call sites need to change").

### The constraint that shapes this feature
Notes have **no date field** beyond `createdAt`/`updatedAt`. The only way a
note maps to a calendar day today is through a `CalendarEvent.noteId` link, and
`DayBarProvider.barsFor`/`DaySummaryProvider.summaryFor` **must be pure,
synchronous, and precomputed** (they run inside `TableCalendar`'s
`markerBuilder` for every visible cell on every rebuild) — no note-content
parsing or DB hits inside the provider itself. Ship this feature *within* that
constraint rather than trying to lift it (a proper "money per day independent
of calendar links" feature would need notes to carry a date, which is out of
scope here).

### Design

#### 1. A note-ledger cache service
New singleton (DatabaseLifecycle-registered, following the `CalendarEventService`
shape: async `getInstance()`, one full pass into an in-memory unmodifiable map,
synchronous getter):

```dart
class NoteMoneyLedgerService {
  // noteId -> (finalBalanceCents, netChangeCents) computed by running
  // MarkdownMoneySyntax over the note's full content once.
  Map<String, ({int balance, int delta})> get ledgers;
}
```

Populate lazily/on note save (hook into wherever `NoteStorageService` already
persists content — reuse that save signal rather than adding a new one) and
also compute on first load for existing notes. Cache invalidates per-note on
edit, not the whole map — mirror `FolderNameIndex`'s incremental-update shape
rather than `CalendarEventService`'s whole-table reload, since this needs to
stay current as notes are edited far more often than calendar events change.

This is a **derived cache** (same "TagIndex precedent" the drift-migrations
skill already documents for exactly this situation) — no schema migration, no
backup-format change, rebuildable from note content on restore.

#### 2. A `DayMoneyBarProvider` / `DayMoneySummaryProvider`
Given `CalendarEvent.noteId` links, sum `NoteMoneyLedgerService` deltas for
every event occurring on `day` (via `CalendarEvent.occursOn(day)`, the existing
single authority for "is this event on this day"). Watch the double-counting
trap flagged earlier: **a recurring event maps one `noteId` to many days** — if
the same note is linked to a recurring event, do not attribute its full delta
to every occurrence; either restrict money bars/summaries to non-recurring
event links, or explicitly document that a recurring-event note's total is
shown once (e.g. only on its `startDate` occurrence) rather than repeated.

- `DayBarProvider` implementation: a single amount can't render as text in a
  bar (bars are color-only dots/strips) — pick a stable key (e.g. `'money'`), a
  priority band that doesn't collide with events (0–4) / holiday (150) /
  weekend (250) (e.g. 50–99, still below holiday), and color by sign (positive/
  negative/neutral from the shared palette). This gives an at-a-glance "money
  moved today" indicator, not a number.
- `DaySummaryProvider` implementation: the actual numeric surface — a
  `DaySummaryEntry` with icon (`Icons.payments`), color by sign, title like
  "Net: +42.50" (apply the Tier 1 currency formatting here too), subtitle
  listing linked note titles. Called only for the selected day, so a slightly
  heavier synchronous lookup is fine.
- Register both in `DayBarsResolver.defaults` / `DaySummaryResolver.defaults`
  (`lib/services/day_bars_resolver.dart:108`,
  `lib/services/day_summary_resolver.dart:136`) — no other call site changes,
  per the class docs.

#### 3. Month-level total (optional stretch within this tier)
No existing aggregation pattern to reuse (confirmed absent in the original
scan). If pursued: sum `NoteMoneyLedgerService` deltas for every event whose
`occursOn` is true for any day in the visible month, surfaced in the header
(`headerTitleBuilder` in `calendar_page.dart:377` already customizes the title
row) or a dedicated summary row. This is a new pattern (first month-level
aggregation in the codebase) — keep it isolated and don't let it leak into the
day-cell hot path.

#### 4. Cache invalidation signal
`CalendarBloc._dayCache` is currently invalidated only on event-set or
category-filter changes; a note edit is invisible to it today (flagged as a
risk in the original scan). Money bars/summaries need a new invalidation path:
either (a) the note editor notifies `CalendarBloc` on save when the edited note
has calendar-event links (query `CalendarEventDao` by `noteId` on save — cheap,
rare), or (b) accept eventual consistency and only refresh on calendar page
reopen. Start with (b) for v1 — it matches the day-bar/summary resolvers'
"rebuilt fresh every build" model and avoids adding a new cross-bloc signal
before it's proven necessary.

### Effort / risk
**L.** The largest of the four — new singleton service, two provider
implementations, and a cache-invalidation decision. The double-counting trap
on recurring events is the sharpest correctness risk; write it down as an
explicit test case before shipping (a note linked to a weekly recurring event
should show its delta once, not multiplied by occurrence count).

---

## Cross-cutting rules

- **Currency is display-only.** `MarkdownMoneySyntax`'s parse/`apply`/plain
  `formatCents` stay currency-agnostic; only the `*WithSymbol` formatting
  helpers and the two rendering surfaces know about the resolved symbol.
- **No new persistence patterns without the derived/rebuildable precedent.**
  Per-note currency overrides and the calendar money cache both ride existing
  mechanisms (`user_settings` prefix keys, an in-memory service rebuilt from
  note content) — no Drift migration in this roadmap.
- **Purity holds at the calendar boundary.** `DayBarProvider`/
  `DaySummaryProvider` implementations must stay synchronous and I/O-free;
  all computation happens ahead of time in `NoteMoneyLedgerService`.
- **Six-call-site tap pattern, not a shortcut.** Reuse the ghost/tag tap
  plumbing shape exactly for money taps — don't invent a parallel callback
  mechanism.
- **Backup whitelist discipline.** Any new global setting key must be added to
  `BackupService._exportSettings`'s whitelist explicitly — it's silently
  dropped otherwise (this has already bitten the ghost/highlight/callout
  seeding features once, per the settings-service report from the original
  scan).
- After each tier: `dart analyze lib` clean; for Tier 1, verify a theme/
  currency change actually invalidates both the preview chunk cache and the
  editor's `_spanCache`/`_positionalSpanCache` (stale currency symbols are an
  easy silent bug).

## Suggested ordering

1. **Tier 2 (toolbar buttons)** — smallest, zero rendering risk, immediate
   ergonomics win, unblocks nothing else so it's safe to do anytime.
2. **Tier 1 (currency)** — foundational for Tier 3's detail sheet (which
   should show currency-formatted amounts) and Tier 4's summary entries.
3. **Tier 3 (tap-to-detail)** — biggest editor-integration payoff the user
   asked about; depends on Tier 1 only for formatting polish, not blocking.
4. **Tier 4 (calendar summary)** — largest and most architecturally novel;
   do last, and treat the recurring-event double-count case as a hard
   correctness gate before shipping, not a follow-up fix.
