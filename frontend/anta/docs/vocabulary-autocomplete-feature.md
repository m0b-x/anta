# Vocabulary autocomplete

**Status: shipped (schema v32, 2026-08-23).** Design record for the editor's
user-defined suggestion lists. Addendum 2026-10-21: the pills render their
terms' markdown and are outlined chips (see Decisions).

## The problem

Logging a session writes the same thing three ways — "bench", "Bench press",
"BP flat" — and every later search, filter or count silently splits across the
variants. The fix has to be *cheaper than typing the word*, or nobody uses it
mid-set.

## What it does

The user defines named **vocabularies** (Settings → Markdown → Autocomplete →
Edit lists): "Exercises", "Meals", "Clients". In the note editor, two things open
a suggestion bar over the markdown toolbar:

1. **A trigger character** (`@` by default) typed after a space. `@ben` narrows
   to "Bench Press"; tapping the pill writes `Bench Press ` as plain text.
   Anything before the run's first colon **scopes the query to named lists**:
   `@exercise:ben` searches Exercises only, `@exercises,meals:oat` the two of
   them together. A single-list scope labels the bar with that list's name; a
   multi-list scope leaves it to each pill's second line.
2. **Tapping a ghost placeholder.** `- {{exercise}} 3x{{sets}}` is a workout
   template; tapping the first ghost offers the Exercises list (the placeholder
   name resolves to it), and tapping a pill fills the run in place.

Ignoring the bar costs nothing. No match means the bar simply closes and the
characters stay exactly as typed — the feature never refuses input, which is the
whole reason it is suggestion rather than validation.

Lists are edited one entry per line on a full-screen page. A line starting with
`;;` is a **section header** — it keeps a forty-exercise list navigable and is
never suggested:

```
;; Chest
Bench Press
Incline Press

;; Legs
Squat
```

## Decisions worth keeping

**Plain text, not a new syntax.** An accepted suggestion inserts the bare term.
The alternative — a persisted token like `{{exercise:Bench Press}}` — was
rejected: it would put a new construct in the user's files, need a grammar module
consumed by *both* render surfaces, do nothing for the notes already written, and
complicate export. It also has nowhere to live: `{{…}}` belongs to ghost text and
`[[…]]` is reserved for the wiki-link idea. Because insertion is plain text, this
entire feature touches neither `LineBasedMarkdownBuilder` nor
`MarkdownEditorSpanBuilder`.

**re_editor's `CodeAutocomplete` is deliberately unused.** The fork ships it
intact, and it is still wrong here: it hijacks Enter and the arrow keys while
open (breaking "never block free typing"), anchors a popup at the caret rather
than near the thumb, matches prefix-only, and does not wrap its insertion in
`runRevocableOp`. No fork change was needed.

**The bar replaces the toolbar's content at identical height** — one
`MarkdownBar.rowHeight` (48 px) row inside 3 px padding, 55 px with the
hairline, exactly the shortcut row's metrics. A session opening must
never shift the editor. Capture speed is the point; a toolbar that jumps costs
more than the autocomplete saves.

**Ghost engagement needs no coupling.** `ModernEditorWrapper` already selects a
tapped `{{ … }}` run whole. The controller reads that off the selection, so it
learns about ghost taps without touching the wrapper's tap state, its
reentrancy flags, or its pointer plumbing. Once the user types over the engaged
run the braces are gone, so the ghost's start offset is kept as an **anchor** and
the session keeps filtering from there; a second space, a caret move before the
anchor, or a non-collapsed selection abandons it.

**The trigger rule exists to protect ordinary text.** A trigger needs whitespace
before it and a non-space after, so `3x8 @ 60kg`, `5x5@100kg` (the planned set
shorthand) and `a@b.com` can never open a session. One internal space is allowed
so two-word terms can be typed; a second ends it. Inside a ghost run the trigger
never fires — ghosts win, as everywhere else in the editor.

**A scope is matched loosely and never enforced.** Scope tokens resolve on
folded *prefix* (`@exer:` reaches "Exercises", `@push:` reaches "Push Day")
plus the placeholder rule's plural tolerance, so nothing has to be typed in
full or spelled the way the list is titled. One token matching several lists is
a feature — the union is the scope. And resolution is allowed to fail: an
unknown scope is not an error but an unscoped query over the run *as written*,
colon included, while `@:ben` searches everything for "ben". The feature never
costs a keystroke it did not save.

**The scope splits the run, not the line.** Prose colons (`sets: @ben`) sit
outside the query and are never a scope, and the syntax stays usable whatever
trigger character is configured. The one shape it cannot reach is `:` as the
*trigger*: there the separating colon is itself a mid-word trigger occurrence
and the guard protecting `a@b.com` fires first. Widening that guard to recover
one trigger character's scoping would trade away the invariant the whole
trigger rule rests on, so it stays.

**Section headers are rows, not a column or a table.** A `;;` line is stored as
an ordinary `vocabulary_items` row, so it carries position and identity exactly
like a term: the diff-based save reorders and tombstones it with no special
case, and a list round-trips through the editor unchanged. Only the *suggestion*
path filters headers out, which is why the grammar lives on `VocabularyItem` —
the one file both the facade and the service already import, so neither has to
depend on the other. Headers de-duplicate like any other line (two identically
titled headings collapse to the first): one rule applied consistently beats a
second one to remember. "How many terms" everywhere means
`Vocabulary.termCount`, which excludes them — ten exercises under three headings
is still ten.

**The list editor is a page, not a bottom sheet.** Editing forty exercises is a
full-screen task. A sheet is capped at a fraction of the screen *and* does not
shrink for the keyboard — the framework's modal bottom sheet adds no keyboard
padding of its own — so the list box was left with a handful of visible lines
and the only way to see the shape of the list was to dismiss the keyboard. A
`Scaffold` resizes for the keyboard by itself, which is also why
`VocabularyEditorPage` contains no `viewInsets` arithmetic. The name field and
enable switch fold away while the terms field has focus, so the list gets the
whole body; the header's chevron re-opens them without dismissing the keyboard,
so editing the name mid-session costs no keyboard round-trip either.

**Terms are rows, and a save is a diff.** The editor edits the whole list
as one block of lines, so every save re-submits every term. A wipe-and-reinsert
would fork each row's id and bump each version, turning one edited word into a
full-list conflict the moment two devices merge. `VocabularyDao.saveItems` keeps
unchanged rows untouched, tombstones removals, and resurrects a re-added term
into the row it had before.

**Store verbatim, match folded** — the tag roadmap's canonicalization rule,
applied through `normalizeForSearch`. Never a second folding table.

**The pills render a term's markdown the way the live editor will
(2026-10-21).** A term such as `**Bench press**` or `#push` reads in the bar as
it will read in the note: `MarkdownChipSpan` (lib/utils) feeds the term through
the editor's own `EditorInlineEmitter.append` — the same tokenizer, the same
conceal rule, the same colours derived from the pill's style via
`EditorRenderContext.fromTheme` — so no third grammar exists and a new inline
construct reaches the pills for free. Headings keep the pill's font size (the
bar's fixed height is the whole point) and announce themselves instead with an
`H1`…`H6` label, `labelSmall` on the term's baseline, the hashes dropped and the
editor's heading weight kept; an empty heading stays raw so a pill is never
blank. The page hands its colour palette through `MarkdownBar.suggestionPalette`
only while live rendering is on, so a raw note never sits under styled pills.
Inline markers are concealed, never dropped — the editor's rule — and only a
heading's hashes are dropped, since nothing in a chip needs their offsets; a
heading is flattened only when the session starts the line, because anywhere
else the accepted hashes stay prose. A term is never shown blank: all-chrome
terms (`%%note%%`, `# %%x%%`) fall back to the raw text. The visible `H1`…`H6`
label is the toolbar heading menu's own literal, a markdown symbol rather than a
word, so it is not localized; the screen reader gets `header1`…`header6`.

**The pills are outlined, not filled (2026-10-21, designer pass).** A filled
`secondaryContainer` stadium is the app's *selected* chip and was the heaviest
chrome in the editor; the pill is now a 1 px `outlineVariant` stadium on the
bar's own surface, its term in `onSurface` at the body weight, so the chip
span's bold, tags, colours and ghosts read exactly as they will in the note.
The tap target stays 48 px through `TapTargetPadding` while the body is 40 px
and grows with its text at larger scales (47 px at the 1.4 clamp). A scoped
session leads with the Lists glyph and the list names at the pills' own size,
capped at 45 % of the strip, and is shown only for a single-list scope, so its
presence never changes while typing; a multi-list scope relies on the pills'
second line, and a two-name label at that size would have left one pill
visible. The `H1` label is `labelSmall` on the term's baseline,
the ✕ is the toolbar's `MarkdownBarIconButton` (ink included), and the strip
wears the toolbar's edge fade and divider gap, so the two modes read as one
family.

## Shape

```
VocabulariesPage / VocabularyEditorPage
        ↓
VocabularyService  ──publishes──>  Vocabularies (sync facade, lib/constants)
        ↓                                    ↑
VocabularyDao                    VocabularySuggestionController
        ↓                          ↓ (reads candidates per keystroke)
vocabularies + vocabulary_items    VocabularyTrigger + VocabularyMatcher (pure)
                                   ↓
                                   MarkdownBar → VocabularySuggestionBar (MarkdownChipSpan)
                                   ↓ accept
                                   page _applyVocabularyInsertion
```

- **Tables** (v32): both carry the five CRDT columns from birth — the v29
  template shape, no `DEFAULT ''`, nothing to backfill. No index: both load
  wholesale into the facade at first use. The item column is `term`, not `text`,
  because `text()` is Drift's column builder and a getter of that name shadows
  it.
- **Service**: the `EventTemplateService` shape — whole table loaded once,
  republished after every mutation, `forTesting`, and a `DatabaseLifecycle`
  reset that clears the singleton **and** the facade. Owns term normalization
  (`parseTerms`: trim, drop blanks, de-duplicate folded).
- **Facade**: `candidates` is flattened and pre-folded once per publish, so the
  per-keystroke path allocates nothing. `byName` resolves a placeholder with
  singular/plural tolerance both ways; `idsForScopeTokens` resolves a trigger's
  scope segment, looser (folded prefix as well) and to a *set*.
- **Matcher**: prefix > word-start > substring > subsequence, capped at 8, with
  the user's own list order as the tie-break inside each tier. Bucketed rather
  than sorted, so input order survives and a full prefix tier short-circuits.
  `vocabularyIds` is the scope filter: `null` unscoped, an empty set matching
  nothing (a caller that resolved to nothing must decide upstream, where the
  raw run is still available, not fall through to searching everything).
- **Insertion** goes through the page's `_applyVocabularyInsertion`, carrying the
  `_handleShortcut` discipline: the `_isProcessingTextChange` guard (or the paste
  heuristic reflows a long term), one `runRevocableOp` so a completion is a
  single undo step, and a `_previousTextLength` resync. A trailing space is added
  only when the next character is not already one.
- **Backup**: additive `vocabularies` key, no version bump. Each entry nests its
  own terms, so a list and its items can never be restored apart.

## Deliberately not shipped

- **Render-time highlighting of known terms.** Tempting (it would light up old
  notes retroactively) but it touches the span builder's perf-critical memos and
  both render surfaces — a separate change with a separate risk profile.
- Per-term insertion templates, usage-frequency learning, per-note/folder
  vocabulary binding.

`candidateSource` on the controller is the seam left for the tag roadmap's
Tier 2.4 `#tag` autocomplete and the `/` slash-menu idea: same session, same bar,
same insertion path, different provider.

## Tests

- `test/database/vocabulary_crdt_test.dart` — stamping, tombstones,
  resurrection, the diff-based save (identity preservation, reorder, clear), and
  the v32 migration.
- `test/database/schema_parity_test.dart` — frozen DDL for both tables.
- `test/models/vocabulary_item_test.dart` — the `;;` boundary: a term keeping a
  single semicolon must never stop being suggested.
- `test/services/vocabulary_service_test.dart` — term parsing, the published
  facade, placeholder resolution, mutations, backup round-trip.
- `test/controllers/vocabulary_suggestion_controller_test.dart` — both entry
  points end to end against a real `CodeLineEditingController`, including the
  anchor continuation after typing over an engaged ghost and the scoped
  trigger's union, label, whole-run accept and raw-run fallback.
- `test/utils/vocabulary_trigger_test.dart`,
  `test/utils/vocabulary_matcher_test.dart` — the pure grammar (including
  scope-segment splitting) and ranking.
- `test/utils/markdown_chip_span_test.dart` — the pill's rendering: editor
  colours at a fixed size, headings flattened to a level, the raw fallbacks.
- `test/widgets/vocabulary_suggestion_bar_test.dart` — the bar's height
  contract, the pills as buttons, rendered vs raw pills, heading pills.
