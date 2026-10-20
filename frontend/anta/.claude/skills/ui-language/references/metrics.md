# Surfaces and numbers

Reference, not rules — moved verbatim from the ui-language SKILL.md on 2026-10-11. Read only the part the task needs.

## Where the language came from (the old opening paragraph)

Its link is relative to SKILL.md; from this file the record is `../../../../docs/event-editor-redesign-roadmap.md`.

The app speaks one UI language: grouped rows on a layered ground, one sheet chrome, role-named numbers. Navigation round 2 (2026-09-07, `docs/navigation-round-2-roadmap.md`) set its tokens — the palette, `SurfaceRoles`, `RowMetrics`, the bars, the menu anatomy — and the 2026-09-25 event editor redesign built the form rows and the sheet chrome on them. The design record with the owner's decisions D1–D20 and the full token spec is [docs/event-editor-redesign-roadmap.md](../../../docs/event-editor-redesign-roadmap.md) §2–§3. This skill is the working rulebook; the records have the why. The calendar's own widgets and its catalogue of ids are in `calendar-ui`.

## Surfaces and numbers — the roles, the text roles, the heights, the old spacing scale

- Ground `colorScheme.pageGround`, groups `rowGroup`, hairlines `rowDivider`, menus `menuSurface` at `FormMetrics.menuRadius`. **No `Card`, no elevation, no shadow anywhere in a form or a sheet.** Light puts `surface` groups on a `surfaceContainer` ground and dark the reverse — read the roles, never the tokens.
- Text roles: label 15 / 400 `onSurface`; value 15 / 400 `onSurfaceVariant`, tabular figures; action 15 / 500 `primary` (`error` when destructive); caption 13 / 400 `onSurfaceVariant` (`error` when it is one); counter 12; section label 11 / 500 uppercase, letter-spacing 0.88; glyph 22 `primary`; chevron 18 `outline`; trailing icon button 48 × 48 with a 20 px `outline` glyph. **Placeholders, hints and counters are `onSurfaceVariant`, never `outline`** — `outline` on `surface` is 4.3:1, under AA for text; glyphs may use it at 3:1.
- Rows are 48 dp minimum (`rowMinHeight`), two-line rows 62 (`twoLineRowMinHeight`), the title row 56. Disabled is 38 % opacity (`disabledOpacity`) with no ink — disabled, never hidden.
- The generic `AppSpacing` scale (`xs` … `xxl` and the `EdgeInsets` built from it) is the older surfaces' vocabulary: a surface on the language reads none of it. It retires surface by surface — a rework's record names what it retires (`ui-revamp`). `AppSpacing.fabClearance` is a role, not the scale, and stays.

## Files — the metrics, the bars and the takeover page's ground

|File|Holds|
|---|---|
| `lib/constants/row_metrics.dart` | `RowMetrics` — the browser rows' geometry the form metrics build on (group inset 16, radius 14, gap 18, divider indents 52 / 16) |
| `lib/constants/app_bar_metrics.dart` | `AppBarMetrics` — the bars' geometry: toolbar 48, glyphs 22, title 17 / 500, the browser's large title |
| `lib/constants/markdown_bar_metrics.dart` | `MarkdownBarMetrics` — the note editor's bottom bar (2026-10-20, `docs/editor-ux-review-2026-10-19.md` U1): 48 dp buttons laid edge to edge with no dead band, 20 px glyphs that do not follow the text scale (the suggestion row shares the height), the section divider, the 24 dp edge fades that are the strip's only scroll cue, the suggestion row's gaps and the reorder panel's shares of the height above the keyboard; the rendering rules in the `markdown-engine` skill |
| `lib/main.dart` (`AppSystemBars`) | the system bars over every page, an `AnnotatedRegion` keyed on the brightness the app resolved, not the phone's (2026-10-20, U2.10): transparent bars, buttons in the opposite brightness, no contrast scrim — under the dark theme Android otherwise paints a light band under the navigation bar; a page with its own region (an app bar's status bar, `AlarmGround`) still wins where it is drawn |
| `lib/constants/alarm_metrics.dart` | `AlarmMetrics` — the takeover page's own numbers: the display numeral, the dock's button heights, label sizes, gaps and text-scale ceiling, the body height under which the dock unpins. Whatever a form or a row already names stays a `FormMetrics` / `RowMetrics` read |
| `lib/widgets/alarm_ground.dart` | `AlarmGround` — `pageGround` edge to edge under one `AnnotatedRegion` that makes both system bars transparent with icons by theme, and hands the navigation bar back when the last ground leaves the screen, in the state the app has at launch (what `MaterialApp` sets, read off `SystemUiOverlayStyle.light`: black, light buttons, a transparent divider, contrast enforced — not by the phone's brightness); the alarm page and the lock-screen cover stand on it |
