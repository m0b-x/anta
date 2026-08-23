# Vocabulary autocomplete

**Status: shipped (schema v32, 2026-08-23).** Design record for the editor's
user-defined suggestion lists.

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
   them together. A scoped bar labels itself with the lists it is confined to.
2. **Tapping a ghost placeholder.** `- {{exercise}} 3x{{sets}}` is a workout
   template; tapping the first ghost offers the Exercises list (the placeholder
   name resolves to it), and tapping a pill fills the run in place.

Ignoring the bar costs nothing. No match means the bar simply closes and the
characters stay exactly as typed — the feature never refuses input, which is the
whole reason it is suggestion rather than validation.

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

**The bar replaces the toolbar's content at identical height** — 40px pills
inside 8px padding, exactly the shortcut row's metrics. A session opening must
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

**Terms are rows, and a save is a diff.** The editor sheet edits the whole list
as one block of lines, so every save re-submits every term. A wipe-and-reinsert
would fork each row's id and bump each version, turning one edited word into a
full-list conflict the moment two devices merge. `VocabularyDao.saveItems` keeps
unchanged rows untouched, tombstones removals, and resurrects a re-added term
into the row it had before.

**Store verbatim, match folded** — the tag roadmap's canonicalization rule,
applied through `normalizeForSearch`. Never a second folding table.

## Shape

```
VocabulariesPage / VocabularyEditorSheet
        ↓
VocabularyService  ──publishes──>  Vocabularies (sync facade, lib/constants)
        ↓                                    ↑
VocabularyDao                    VocabularySuggestionController
        ↓                          ↓ (reads candidates per keystroke)
vocabularies + vocabulary_items    VocabularyTrigger + VocabularyMatcher (pure)
                                   ↓
                                   MarkdownBar → VocabularySuggestionBar
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
- `test/services/vocabulary_service_test.dart` — term parsing, the published
  facade, placeholder resolution, mutations, backup round-trip.
- `test/controllers/vocabulary_suggestion_controller_test.dart` — both entry
  points end to end against a real `CodeLineEditingController`, including the
  anchor continuation after typing over an engaged ghost and the scoped
  trigger's union, label, whole-run accept and raw-run fallback.
- `test/utils/vocabulary_trigger_test.dart`,
  `test/utils/vocabulary_matcher_test.dart` — the pure grammar (including
  scope-segment splitting) and ranking.
