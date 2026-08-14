# Money Ledger (Counter Processing Engine)

The integration roadmap (`docs/money-ledger-integration-roadmap.md`) is
implemented: currency formatting (global + per-note), toolbar buttons for all
ops, tap-to-detail on totals, and the calendar day/month money summary.

Track a running sum — money, calories, any quantity — inside any note with a
lightweight, line-led markdown syntax. The balance is computed from the note's
text at render time: nothing is persisted, no counter is mutated, and the data
travels with the note through backups, import/export, and sync for free.

**Opt-in**: the feature ships disabled (`money_ledger_enabled`, default off).
Enable it via the master switch at the top of the markdown settings' Money
ledger section — until then `$` lines render as plain text on both surfaces,
the toolbar shortcuts still just insert their text, and the calendar shows no
money surfaces.

## Syntax

Each op is one line, optionally indented. The `$` sentinel avoids every
existing grammar (`{{ }}` ghosts, `{cN}` shortcut tokens, list markers, tags).

| Line | Meaning |
| --- | --- |
| `$= 100` | Set the balance (initial sum). Also a period checkpoint. |
| `$+ 12.50 protein powder` | Add an amount (optional label after it). |
| `$- 8 shaker` | Subtract an amount. |
| `$* 1.19` | Multiply the balance (e.g. tax). |
| `$/ 2` | Divide the balance (e.g. split a bill). |
| `$$ label` | Show the running total at this point. |
| `$? label` | Show the net change since the last `$=` (or note start). |
| `$! 500 label` | Spending target: shows the remaining budget (target − spent since the last `$=`), green under budget, red over. Inert to the balance. |

Amounts take `.` or `,` decimals (2 for `= + -`, 4 for `* /`; up to 8 integer
digits for amounts, 4 for factors — so a single amount can never exceed the
balance clamp). A malformed amount rejects the whole line —
it renders as plain text, visible feedback that it did not count. Fenced-code
lines are inert. Labels support the full inline grammar (tags, emphasis,
ghosts) and stay searchable.

### Periods (per note / month / year)

`$=` doubles as a period boundary. Structure periods with headings and
checkpoints; `$?` reports the period's net change, `$$` the absolute balance:

```text
## January
$= 500 salary budget
$- 40 gym membership
$+ 25 refund
$? January change      → Δ -15.00
$$                     → Σ 485.00
```

## Rendering

- **Preview**: the `$x` marker is consumed as chrome and replaced by a sign
  glyph (`+ − × ÷ = Σ Δ`). Additions render green, subtractions red,
  multiply/divide amber, set/total in the theme primary (negative totals red).
  Every op row ends with a dimmed running balance (`… = 485.00`); `$$` / `$?`
  render the value as a tinted pill. Amounts and labels keep their exact
  source offsets, so search highlighting lands on them; computed values are
  not source text and are invisible to search by design.
- **Live editor** (Obsidian-style, follows the `liveMarkdownRendering`
  setting): the `$` is concealed and the op char tinted (`-`, `*`, `/`
  substituted 1:1 with `−`, `×`, `÷`), the amount tinted; `$$` / `$?` paint a
  rounded chip with the computed value in place of the token. Lines covered by
  the caret/selection reveal the raw source for editing; line height never
  changes between states.

## Architecture

`lib/utils/markdown_money_syntax.dart` (`MarkdownMoneySyntax`) is the single
source of truth: grammar, fixed-point arithmetic (`apply`), and formatting.
Both surfaces consume it, so they can never disagree about what a money line
is or what the balance reads.

- Arithmetic is fixed-point int — cents for balances, 1/10000ths for parsed
  amounts. No floating point anywhere; multiply/divide round half away from
  zero to the nearest cent; balances clamp to ±500,000,000.00 so 64-bit
  intermediates cannot overflow.
- **Preview pass**: `LineBasedMarkdownBuilder._computeMoneyLedger()` folds the
  ledger in one O(n) pass per `prepare`, probing lead characters directly on
  the source string so non-money lines allocate nothing even on 100k-line
  documents.
- **Editor pass**: `MarkdownEditorLineIndex` gained a money pass beside the
  fence and task passes — per-segment entry snapshots (balance + `$=` anchor),
  truncate-and-append results, resumed at the first changed ~256-line segment,
  so a keystroke never rescans the whole document.
- **Caching**: op lines render purely from their text and live in the editor's
  text-keyed span LRU. `$$` / `$?` lines are positional (their value depends on
  lines above) and go through the positional memo with the value folded into
  the key, exactly like fence roles and indeterminate tasks.
- The editor never inserts characters: values paint via the re_editor fork's
  `CodeInlinePaintSpan` placeholder (1:1 code-unit substitution), keeping
  caret, selection, and search offsets in sync.

## Start balance & currency

- **Global start balance** (`money_start_cents` setting): every note's ledger
  begins at this amount instead of 0, so `$- 300` in a fresh note renders
  `−300 = 700` when the global start is 1000. `$=` still overrides it inside a
  note. The value seeds both render surfaces and the `$?` anchor.
- **Currency** is display-only — parsing and arithmetic stay symbol-free.
  Global symbol + prefix/suffix placement (`money_currency_symbol` /
  `money_currency_suffix`), with per-note overrides stored under
  `money_note_currency_<noteId>` keys (the `note_bar_` precedent; overrides
  export/import with backups, version 6). Symbols render on computed values
  (running balances, `$$`/`$?` pills and chips) — never inside source amounts.
- Settings UI lives in the markdown settings page (Money ledger section:
  start balance, symbol, placement, per-note overrides page). The editor
  re-resolves the config on note open and when returning from settings; a
  change invalidates the preview's builder cache and the editor's span memos
  like a theme change.

## Tap-to-detail

Tapping a `$$` or `$?` value — the pill in the preview or the painted chip in
the live editor — opens a bottom sheet listing every ledger entry feeding that
value (`$?` lists only entries since its `$=` anchor), with the same glyphs
and accent palette as the inline rows. Editor taps are claimed through the
fork's tap interceptor (like task checkboxes), so the caret never moves and
the keyboard never rises; entries are collected on demand by
`MarkdownMoneySyntax.collectEntries` (fence-aware, O(document) on tap only).

## Toolbar

Seven default shortcuts: `default_money` (`$+ `, seeded via
`money_shortcut_seeded`) plus subtract / multiply / divide / set / total /
change siblings seeded as one batch (`money_ops_shortcuts_seeded`) — each
deletable like any default shortcut.

## Calendar

`NoteMoneyLedgerService` (derived, in-memory, DatabaseLifecycle-registered)
computes `{balance, net}` per calendar-linked note from its content, where
`net` sums only op effects (`$=` baseline moves don't count as money
movement). A note's net is attributed to the UTC day of its event's
`startDate` only — a weekly recurring event shows its note's total once, never
per occurrence. Surfaces: a sign-colored day bar (priority 90), a day-summary
entry ("Money: +42.50" with linked note titles), and a `Δ` month total in the
calendar header. Refreshed on calendar load and event create/update; note
edits invalidate lazily via the note-changes stream.

## Limitations / candidates for later

- No named ledgers (`$food+ …`) — one ledger per note; the label is free text.
- `$=` accepts only non-negative amounts; start a debt as `$= 0` + `$- …` (a
  negative *global start balance* is supported via settings).
- Calendar money follows event links; notes without a linked event don't
  appear on the calendar. Cross-note calendar aggregates always use the
  **global** currency — per-note currency overrides style only that note's own
  rendering (summing mixed currencies is intentionally not attempted).
- On a bare `$$`/`$?`/`$!` line (no label), taps on the right half of the
  painted editor chip place the caret instead of opening the sheet — same
  partial-coverage tradeoff as task-checkbox taps; lines with a label are
  fully covered up to the label.
