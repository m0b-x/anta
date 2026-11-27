# The tag browser — design record (2026-11-27)

**Status: PROPOSED — nothing is built.** A designer's judgement and specification, made on 2026-11-27 while the owner was away, of where the app lists the tags in use; it waits for his answer on the lettered decisions of §5. It is step 5 of `docs/tag-system-roadmap.md` and needs that record's steps 4a and 4b (the tag catalog and the editor's autocomplete), which are built as patches and not merged. The renders, the measurements and the mock are in `build/session-2026-11-27/tag_browser/` (git-ignored).

Contents: §1 Diagnosis · §2 The specification · §3 What stays and why ·
§4 Risks · §5 Decisions taken by default · §6 What the design-reviewer
re-renders · §7 Slice plan.

The direction in one line: **the search surface's idle state — the page a
tag tap already lands on, and the in-place search of the browser and of All
notes — gains a Tags section above Recent: four tag rows by number of
notes, then "146 more" that grows the group in place. A tap fills the field
with the tag and runs the search a tag tap in a note runs.** No new route,
no new drawer row, no new state pattern. The mock is
`tag-browser-mock.html`.

## 1. Diagnosis

Rendered with real fonts from the search page's own test harness (a real
database seeded with twelve tagged notes, `SearchPage` pumped as the suite
pumps it), light and dark, text scale 1.0 / 1.3 / 2.0, en and de, 360 × 780
and 412 × 915, the keyboard faked at 336 dp where the field is focused.

1. **No surface lists the tags** (`sheet_now-idle-360.png`). The only door
   to a tag's notes is a tag inside a note. The idle state — where search
   opens, keyboard up — shows Recent alone: 5 recents fully visible at 1.0
   in the 372 dp band between the bar (72) and the keyboard (444), 3 at
   2.0 de. Rule: recognition over recall (Nielsen 6); the roadmap's step 5
   "turns tags into navigation".
2. **Typing a tag prefix answers notes, not tags** (`sheet_now-quick-360.png`,
   `#l`): four note rows with `#l` highlighted inside `#legday`; nothing
   says which tags exist or how many notes each carries. With 150 tags the
   only way to find `#tracțiune` is to remember it. Must not change (the
   quick list is fixed by the brief), so the list has to live where nothing
   is typed.
3. **The full results for `#legday` are sound and stay**
   (`sheet_now-full-360.png`): rows, order and highlight match the note's
   tag tap; no header and no count — the count is what the tag row will
   carry before the tap.
4. **The idle surface has room**: Recent caps at 50 rows
   (`AppConstants.recentNotesLimit`), so anything put under it is never
   reached; anything put above it costs Recent its first screenful with the
   keyboard up. §2 budgets that cost: one recent stays visible at 1.0.
5. **Two inks under 4.5:1, outside this change** (computed from the tokens):
   the idle empty-state message `_messageSliver` draws its text in
   `outline` on `pageGround` — 3.96:1 light (WCAG 1.4.3); the browser's
   `RowCountChevron` count is `outline` on `rowGroup` — 4.33:1 light. Not
   touched here (the adoption rule forbids a drive-by); the tag row does not
   copy the second one (§2, decision O).
6. **Where search lives**: the folder browser's and All notes' search icons
   open search **in place** (`SearchSurface.resultSlivers` under
   `SearchFieldAppBar`); the standalone `SearchPage` is pushed only by a tag
   tap in a note. All three idle states are the same `resultSlivers` idle
   branch, so one change reaches every place search idles.

Taps to a tag's notes, counted from the renders' flows:

| From | (a) idle state of search (chosen) | (b) a Tags page in the drawer |
| --- | --- | --- |
| The folder root | 🔍, the tag — **2** | drawer (edge swipe, or ⋮ → Settings), Tags, the tag — **3–4** |
| Inside a note with a tag | the tag in the note, ✕, another tag — **3** | ←, drawer, Tags, the tag — **4–5** |
| Inside a note without one | ←, 🔍, the tag — **3** | ←, drawer, Tags, the tag — **4–5** |

(b) would also add a route, a drawer row (the drawer lists places, and a
tag list is a query), its own filter field for 150 rows and a launch-restore
decision, and every row would land on the search page anyway. (a) keeps the
recents: they move down by the section's height and nothing else changes
(§2.1).

## 2. The specification

### 2.1 Where and when the section shows

- In `SearchSurface.resultSlivers`, idle branch only (`phase == idle`,
  `labels.isEmpty`): the Tags section, then today's Recent slivers (or
  today's "Type to search notes" message) unchanged below it.
- Not shown: once anything is typed (quick and full phases unchanged), in
  the colour-only listing, and when the snapshot is empty and the catalog
  is not filling (§2.5).
- The section reads a **snapshot** of the catalog taken by the bloc at each
  entry into idle (`SearchOpened`, `SearchCleared`, the hosts' refresh on
  return from a note). A catalog change while rows are on screen is not
  shown until the next entry — nothing moves under the finger. While the
  snapshot is empty (filling, or not yet read) a catalog change re-snapshots
  at once: rows replace a line that has no target.

### 2.2 Elements

| Element | Current | Proposed (role · value · constant) |
| --- | --- | --- |
| Section header | — | `ContentSectionHeader(label: l10n.searchTagsSection, identifier: SemanticsIds.searchTagsHeader)`: `labelSmall` 11 / 500, `onSurfaceVariant`, +0.88 tracking, upper-cased, `RowMetrics.sectionLabel*`; heading level 2, speaks "Tags" as written |
| Filling line | — | the existing `_IndexingNotice` look: `bodySmall` `onSurfaceVariant`, insets `groupInset + sectionLabelInset` / `groupInset`, bottom `sectionLabelBottomPadding` (or `groupGap` when no row follows), `liveRegion`; text `l10n.searchStillIndexing` |
| Group | — | `ContentRowShell` positions first / middle / last, `rowGroup`, radius `RowMetrics.groupRadius` 14, `groupInset` 16 sides, `groupGap` 18 under the last row, divider `rowDivider` indented `dividerIndentPlain` 16 (no leading glyph) |
| Tag row | — | new `SearchTagRow` (§2.3) |
| Disclosure row | — | new `SearchTagsDisclosureRow` (§2.4), the group's last row when collapsible |
| Recent header and rows | at y = 72 | unchanged, at y = 72 + the section's height (284 dp at 1.0, §6) |

### 2.3 `SearchTagRow`

One line of the browser's smart-row anatomy, no glyph: `name · count · ›`.

| Part | Value |
| --- | --- |
| Box | `minHeight` `RowMetrics.singleLineMinHeight` 48; padding `RowMetrics.tagRowPadding` = `EdgeInsets.fromLTRB(groupInset 16, 8, 12, 8)` (new) — the right 12 is `singleLinePadding`'s; the 8 keeps a wrapped name off the row's edges |
| Name | the catalog's spelling as written, `#` included; `fontSize` `RowMetrics.titleFontSize` 15. Flat tag: one span, `primary`, w500. Nested tag (contains `/`): the part up to and including the last `/` in `onSurfaceVariant` w400, the leaf in `primary` w500 (decision D). A zero-width space is drawn after each `/` so a long tag breaks there, never in the semantics label. `maxLines` `RowMetrics.tagNameMaxLines` = 2 (new), ellipsis |
| Count | `'$notes'`, `RowMetrics.countFontSize` 14, **`onSurfaceVariant`** (decision O), tabular figures, end-aligned in `countMinWidth` 26; gap `RowMetrics.gap` 14 before and after |
| Chevron | `Icons.chevron_right`, `chevronSize` 18, `outline` (3:1 non-text: 4.33 light, 5.15 dark) — through `RowCountChevron`, which gains `countColor:` (default `outline`, so folder rows do not change) |
| Ink | `InkWell` on the shell's `Material`, the theme's pressed layer; desktop focus ring from `InkWell`'s focus |
| Tap | the host's `onTagTap(spelling)` (§2.6) |
| Long press | none — no handler, so step 7 can hang a row sheet here (`RowAction`, as `FolderRow` does) without moving anything |
| Semantics | one node: `button`, label `l10n.searchTagSpoken(spelling, notes)` ("#legday, 42 notes"), visible text excluded under it; no per-row identifier — a flow taps the row by its label, which is unique |

Contrast, computed from `AppTheme`: `primary` on `rowGroup` 6.12:1 light,
9.56:1 dark; `onSurfaceVariant` on `rowGroup` 8.88:1 light, 9.56:1 dark.

### 2.4 `SearchTagsDisclosureRow`

The content-row twin of `FormActionRow.disclosure` (its anatomy, its ink).

| Part | Value |
| --- | --- |
| When | the snapshot holds more than `RowMetrics.tagPreviewRows` + 1 tags (new constant `tagPreviewRows` = 4; five or fewer show whole, never "1 more") |
| Box | as the tag row: 48 min, `tagRowPadding` |
| Label | collapsed `l10n.searchTagsMore(count)` — en "146 more", de "146 weitere", ro "Încă 146" (count = total − 4); expanded `l10n.searchTagsLess` — "Show less" (`reportGroupLess`'s wording in all three, its own key); 15 / w500 `primary`, `maxLines` 2 |
| Glyph | trailing at the chevron's place: `expand_more` / `expand_less`, 18, `primary` |
| Tap | toggles `tagsExpanded` in the bloc; a tap that expands also drops the keyboard (`focusNode.unfocus()`), so the list gets the screen |
| Semantics | one node: `button`, `expanded` true / false, label `l10n.searchTagsMoreSpoken(count)` ("146 more tags") or `searchTagsLess`, `identifier: SemanticsIds.searchTagsMore` (one id for both states) |
| Persistence | expanded holds for the search session — across a tag tap, the ✕ and a return from a note — and resets when search opens again (decision K) |

### 2.5 States

| State | Shown |
| --- | --- |
| Catalog empty, nothing filling (new install; a library without tags) | no section; the idle state is today's, pixel for pixel |
| Filling, nothing found yet | header + filling line, then Recent |
| Filling, some found | header + filling line + the found rows (+ disclosure past five) |
| 1–5 tags | header + every tag, no disclosure |
| 6 + tags, collapsed | header + 4 rows + "N more" |
| Expanded | header + every tag (catalog order) + "Show less" at the group's end |
| Colour filter, nothing typed | no section (today's colour listing) |
| Anything typed | no section (today's quick and full phases) |
| Keyboard up (the entry state) | the same section; the list scrolls under the keyboard as Recent does today (`keyboardDismissBehavior: manual` unchanged) |
| Folder scope chip selected (in-place, sub-folder) | the same global section; a tap switches to Everywhere (§2.6) |
| Pressed | `InkWell` splash on `rowGroup` |
| Dark | roles above; no other change |

### 2.6 The tap

`SearchSurface.resultSlivers` gains `ValueChanged<String>? onTagTap`;
`SearchSurface` (the standalone page) gains the same. Each host's handler:
set the field's text to the spelling with the caret at its end, unfocus the
field, dispatch a new `SearchTagPicked(spelling)`. The bloc handles it as
one event: scope := Everywhere, then the `SearchSubmitted` path for that
text (one generation, so no scope-change pass races it). The result is the
state a tag tap in a note lands in: the field reads `#legday`, keyboard
down, phase `full`, the Everywhere chip selected where chips exist, the
rows and order of today's full search.

### 2.7 Per scale (measured at 360 × 780, linear scaler — §6)

| | 1.0 | 1.3 | 2.0 |
| --- | --- | --- | --- |
| Header | 22 | 27 | 38 |
| One-line tag row (incl. divider) | 49 | 49 | 60 |
| `#Krankengymnastik/Schulter` | one line, 228 wide | two lines, broken after `/` — row 73 | two lines, broken inside "Krankengymnastik" (the word is wider than the line) — row 103; never ellipsized in the sample |
| Disclosure (en / de) | one line | one line | one line ("146 weitere" — the long "146 weitere Schlagwörter" wrapped to two and was cut; hence the short label, decision N) |
| Section total (header top → Recent header top) | 284 | 313 | 398 |
| Keyboard up: what the first screen holds | 4 tags, "146 more", Recent label, 1 recent | 4 tags, "146 more", Recent label | header, 4 tags; "146 more" cut 8 dp under the keyboard |
| Keyboard up at 412 × 915 (1.0) | 4 tags, "146 more", 3 recents | | |

Nothing clamps: names wrap to two lines and then ellipsize; the count and
the glyphs never wrap; no `withClampedTextScaling` is added.

### 2.8 Strings (en / de / ro), new keys in all three ARBs

| Key | en | de | ro |
| --- | --- | --- | --- |
| `searchTagsSection` | Tags | Schlagwörter | Taguri |
| `searchTagsMore` | {count} more | {count} weitere | Încă {count} |
| `searchTagsMoreSpoken` | {count, plural, =1{1 more tag} other{{count} more tags}} | {count, plural, =1{1 weiteres Schlagwort} other{{count} weitere Schlagwörter}} | {count, plural, =1{Încă un tag} few{Încă {count} taguri} other{Încă {count} de taguri}} |
| `searchTagsLess` | Show less | `reportGroupLess`'s de text | `reportGroupLess`'s ro text |
| `searchTagSpoken` | {tag}, {count, plural, =1{1 note} other{{count} notes}} | {tag}, {count, plural, =1{1 Notiz} other{{count} Notizen}} | {tag}, {count, plural, =1{o notiță} few{{count} notițe} other{{count} de notițe}} |

"Schlagwort" and "tag" follow the ARBs' existing tag strings
(`editorZoneSearchTagNamed`, `reportSectionTags`); ro never says "etichetă",
which is the colour label's word. The filling line reuses
`searchStillIndexing`.

### 2.9 Constants and ids

- `RowMetrics.tagPreviewRows = 4`, `RowMetrics.tagNameMaxLines = 2`,
  `RowMetrics.tagRowPadding = EdgeInsets.fromLTRB(groupInset, 8, 12, 8)`.
- `SemanticsIds.searchTagsHeader = 'search-tags-header'`,
  `SemanticsIds.searchTagsMore = 'search-tags-more'`.
- Tolerances ±1 dp unless a test pins the value.

### 2.10 State and data

`SearchState` gains `tags` (`List<CatalogTag>`, the snapshot),
`tagsFilling` (`bool`, the body indexer had pending work at the snapshot)
and `tagsExpanded` (`bool`); events `SearchTagsToggled`, `SearchTagPicked`
and `SearchTagsChanged` (the catalog's signal; acts only while idle and the
snapshot is empty). `SearchBloc` takes the catalog facade as a named
dependency from its three constructors (`SearchPage`, the folder page, All
notes). It reads `TagCatalog.all` synchronously; if the 4a facade has no
change signal, slice 1 gives `TagCatalogService` one (it already refreshes
on `BodySearchIndexer.changes`). The surface renders from state only.

## 3. What stays and why

- **What a tag tap in a note does** — unchanged; the browser's tap reproduces
  its landing state instead of inventing a second one.
- **The quick list, the full results, their rows, sections and order** —
  the section exists only in idle.
- **Focus on entry** — the field still focuses itself; only the expanding
  tap and the tag tap drop the keyboard, both user actions after entry.
- **Recent** — rows, cap, unscoped answer and the hint message are today's;
  they move down by a fixed height per scale.
- **The colour-only listing and the scope chips** — untouched.
- **`RowCountChevron` for folders** — its default stays `outline`; finding
  §1.5 is left to the adoption roadmap.
- **No route, no drawer row, no new state pattern**: the bloc keeps state;
  the facade is read the way blocs read services.

## 4. Risks

- **Height budget with the keyboard up**: at 1.3 the first recent drops
  under the keyboard, at 2.0 the disclosure does. Recent stays one scroll
  away; a user who opens search to type loses nothing. Decision E's
  "not taken" (three rows) is the lever if the owner wants Recent back on
  the first screen.
- **Text scale on the device**: the renders use a linear scaler; Android's
  200 % maps 15 sp to about 27, so device rows are shorter than measured
  (60 → about 56). The long nested tag still breaks inside its first word
  at 2.0 — legible, every character kept.
- **German**: the longest visible strings are "SCHLAGWÖRTER" (one line at
  2.0) and "146 weitere"; the spoken forms carry the full words.
- **Dark**: verified in every cell; no tier-only state.
- **Semantics**: the row's label begins with "#" — TalkBack reads it as
  "hash" / "number"; checked only on the device (`qa a11y` dump). The
  header is a level-2 heading under the field's level-1 heading.
- **Catalog freshness**: the snapshot rule means a tag written a minute ago
  appears on the next entry into idle, not live. The catalog itself lags
  the open note by design (roadmap T-I).
- **NFC / NFD twins** (roadmap 4a's known-low): two rows for one tag would
  show here first; the count order puts the stray at the tail, where it is
  visible — a reason for step 7, not a fault of this surface.
- **Scope switch**: a tap from a sub-folder's in-place search moves the
  chip to Everywhere; a user who wanted "this folder's #legday" retaps the
  folder chip (decision H).
- **Keyboard**: the expanded list scrolls with the keyboard down; a long
  expanded list under a raised keyboard (after ✕, which refocuses) is the
  same as today's 50 recents.

## 5. Decisions taken by default

Each is reversible until slice 2 lands; "not taken" is what the owner picks
to overturn it.

| # | Decision | Not taken | Changes behaviour? |
| --- | --- | --- | --- |
| A | The tags live in the search surface's idle state — the standalone page and both in-place searches. | (b) A Tags page from the drawer: +1 route, +1 drawer row, 1–2 more taps, its rows land on search anyway. | Yes — idle gains a section. |
| B | Above Recent; Recent unchanged below. | Below Recent (50 rows down: unreachable); instead of Recent. | Yes — Recent moves down 284 dp at 1.0. |
| C | Rows of the browser's language: `name · count · ›`, `ContentRowShell`. | A wrap of chips (a second idiom on a content-row surface; width-dependent count per line). | No. |
| D | The spelling as written with `#`; a nested tag's parent in `onSurfaceVariant` w400, its leaf in `primary` w500. | The whole spelling in one `primary` ink (the editor's look); `onSurface` like a folder name. | No. |
| E | Four rows, then "N more" grows the group in place; five or fewer show whole. | Three rows (a recent stays visible at 1.3); eight; all always; "All tags ›" to a page. | Yes. |
| F | Ordered by number of notes, ties by spelling — the catalog's order. | A–Z; letter groups; a tree under parents. | No. |
| G | The field's text never filters the tags; typing goes to today's quick list. | A Tags section above the quick list when the text starts with `#` (changes the quick phase, which the brief fixes). | No. |
| H | A tap fills the field with the tag, drops the keyboard and searches Everywhere — the note tag tap's landing state. | Keep the selected folder scope (the row's count would then disagree with the rows). | Yes — the scope chip moves. |
| I | Long press does nothing; room is left for step 7. | A copy / rename menu now. | No. |
| J | A snapshot per entry into idle; live only while empty. | Live updates while shown (rows reorder under the finger during the post-upgrade fill). | No. |
| K | Expanded holds for the search session; expanding drops the keyboard. | Collapse on every return to idle; keep the keyboard up. | Yes. |
| L | Empty catalog: no section, no teaching line. | A caption "Write #word in a note to tag it" (the guide already teaches tags). | No. |
| M | Filling: header + the existing `searchStillIndexing` line + rows found so far. | Hide the section until the catalog is full; a new string. | No. |
| N | New strings of §2.8; the visible disclosure says "146 more" / "146 weitere" / "Încă 146", the spoken one names tags; ro "tag / taguri". | "146 more tags" visibly (wraps and cuts in German at 2.0); ro "etichete". | No. |
| O | The tag count in `onSurfaceVariant` (8.9:1) through a new `RowCountChevron.countColor`. | `RowCountChevron` as is: `outline`, 4.33:1 in light, under WCAG 1.4.3. | No. |
| P | No tags in the colour-only listing. | Tags filtered to the picked colours. | No. |

## 6. What the design-reviewer re-renders

The scratch matrix (removed after the run; rebuild from
`test/widgets/search_page_test.dart`'s harness with `loadGoldenFonts`, 360
× 780 and 412 × 915, dpr 3, IME 336 dp, status 24, nav 24):

- Before (keep as the baseline): `sheet_now-idle-360.png`,
  `sheet_now-quick-360.png`, `sheet_now-full-360.png`, the 412 sheets, and
  `cells/now-*.png` — rows are scale, columns light-en · dark-en · light-de
  · dark-de.
- The proposal, built once: `sheet_new-idle-360.png` (keyboard up),
  `sheet_new-idle-nokb-360.png`, `sheet_new-expanded-360.png`,
  `sheet_new-expanded-end-360.png`, `sheet_new-six-360.png`,
  `sheet_new-filling-360.png`, `sheet_new-filling-empty-360.png`, the 412
  sheets; `measurements.txt` holds every cell's numbers.
- Re-render after the build, each light / dark × 1.0 / 1.3 / 2.0 × en / de:
  idle with the keyboard up and down at 150 tags; expanded mid-list and at
  its end; 5 tags (no disclosure); filling with and without rows; empty
  catalog (must equal `now-idle`); after a tag tap (must equal `now-full`
  for the same tag); quick `#l` (must equal `now-quick`).
- Assert, not eyeball: Recent header top = 72 + 284 / 313 / 398 (±1) at
  1.0 / 1.3 / 2.0 with the 150 list; one-line tag row 49 / 49 / 60;
  `#Krankengymnastik/Schulter` two lines at 1.3 and 2.0, not exceeded;
  disclosure one line in de at 2.0; no overflow exception in any cell; the
  row nodes' labels and the disclosure's `expanded` flag; 48 dp targets
  (`androidTapTargetGuideline`); `qa a11y` on the device for "#".

## 7. Slice plan

Needs 4a (the catalog) merged first; 4b is independent of this surface.

| Slice | Files | The gate proves |
| --- | --- | --- |
| S1 — the snapshot in the bloc | `lib/bloc/search/search_state.dart`, `search_event.dart`, `search_bloc.dart`; the catalog's change signal if 4a lacks one (`lib/services/tag_catalog_service.dart`); the three `SearchBloc(...)` constructions; `test/bloc/search_bloc_test.dart` | idle entry snapshots the catalog; a change while rows are held is ignored, while empty is taken; `tagsFilling` follows the indexer; `SearchTagsToggled` holds across refresh and resets on open; `SearchTagPicked` from a folder scope ends in Everywhere, phase full, the same hits as `SearchSubmitted`; the quick and full paths' states unchanged; analyze clean, whole suite green |
| S2 — the rows and the hosts | new `lib/widgets/search_tag_rows.dart` (`SearchTagRow`, `SearchTagsDisclosureRow`, the slivers); `lib/widgets/search_surface.dart` (`onTagTap`); `lib/widgets/content_rows.dart` (`RowCountChevron.countColor`); `lib/constants/row_metrics.dart`; `lib/constants/semantics_ids.dart`; `lib/pages/search_page.dart`, `optimized_folder_content_page.dart`, `all_notes_page.dart`; the three ARBs + `gen-l10n`; `test/widgets/search_page_test.dart`, the browser's in-place search test | the section above Recent; a tap puts `#tag` in the field with the keyboard down and lists what the note tag tap lists; disclosure toggles and drops focus; empty catalog = today's idle; de at 2.0 on 360 × 780 with no overflow; the folder rows' count still `outline`; `untranslated.txt` empty; whole suite green |
| S3 — the device pass and the records | a flow under `tool/qa/flows/` for search (seed with tags; open search, tap "#legday", ✕, expand by `search-tags-more`); `docs/tag-system-roadmap.md` step 5; the anta-context search reference | the flow green on the pass device; dark · de · 2.0 walk with nothing clipped; `qa errors` clean; the design-reviewer's §6 matrix |

## 8. How to run this

Nothing starts before two things: the owner's answer on §5, and the tag
catalog (`docs/tag-system-roadmap.md`, step 4a) merged — it carries schema
v57 and is a patch until he says so. "Yes to all" is an answer; A and B
decide whether S2 exists in this shape at all, E and K are S1's and S2's,
H is S1's, N is S2's strings.

- **The session:** a Fable 5.2 lead at `high`; with §5 answered nothing is
  left to decide, so an Opus 5.5 session may build it directly instead.
- **Per slice, in sequence** (one `flutter test` at a time): one
  `implementer` in a worktree of its own, briefed with §2, §3 and its row
  of §7; one `reviewer` on the diff against §3; for S2 one `design-reviewer`
  in a fresh context on §6, never shown §1's reasoning; the whole-suite
  gate from the lead.
- **S3** is one `qa-runner` on the new flow and the browser suite, then
  the hand checks its row names.
- **At each slice boundary** the status line is corrected, the uncommitted
  files are counted and a ready commit is offered.
