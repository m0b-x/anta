# Calendar schema lineage

Reference, not rules — moved verbatim from the calendar-events SKILL.md on 2026-10-11. Read only the part the task needs.

The rules that outlive every version stayed in the SKILL.md, under the same heading. Since the second cut (2026-10-11) the SKILL.md states them compactly; their full lines, verbatim with the whys and examples, are under "Rules that outlive every version" below.

## Schema lineage (current v42)

v10 calendar tables → v11 `end_date` + time-of-day → v12 `description` → v13 holiday profiles → v14 `note_id` → v15 data-driven `calendar_categories` → v16 `color_value` / `tint_icon` / `priority` → v17 `suppressed` holidays → v18 priority scale inverted (`p -> 6 - p`, backup v7) → v19 `retroactive` → v20/21 `count_occurrences` + `count_style` → v22 computed holidays (seeded rows deleted) → v23 yearly counts from zero → v24 `calendar_event_occurrences` → v26 `tracks_presence` + `calendar_event_absences` → v27 events CRDT → v28 `per_occurrence_descriptions` + occurrence CRDT → v29 `calendar_event_templates` → v30 `calendar_event_skips` → v31 delta-table indexes → v32 vocabularies → v33 `is_hidden` → v34 `show_in_day_rail` → v35 `calendar_filter_presets` → v36 `idx_notes_ltitle` → v37 assume-absent (`absences.status`, `assume_absent`, `assume_absent_from`, the absence index drop-and-recreated) → v38 repair of a stray v37 → v39 `notes.label` / `folders.label` → v40 alerts (`calendar_event_alerts`, device-local `alert_registrations`, `remove_after_alert`) → v41 `overview_views` → v42 category alerts and digests (`calendar_category_alerts` with the v40 alert shape and the CRDT block, `event_digests` with the `overview_views` shape + `enabled`, `calendar_events.category_alerts` default 1, `alert_registrations.source` default `'event'`; `idx_calendar_category_alerts_category` in its own creator).

## Rules that outlive every version

- The recurrence **interval rides inside `rule_payload`** — write only when `> 1`, decode clamped to 1, never an `interval` column.
- Additive columns get `PRAGMA table_info` guards, defaults that mean what a pre-existing row already meant, and **no backfill**; backup stays version 7 unless import semantics change.
- A **swapped index is dropped and recreated** (the v27 / v37 idiom); `IF NOT EXISTS` alone strands upgraders on the old shape.
- `DatabaseIndexes.createCalendarDeltaIndexes()` is separate from `createCalendarIndexes()` because the latter runs inside the v9→v10 migration, where the delta tables do not exist yet; a new index goes in the creator whose tables exist when it runs.
- `alert_registrations` is **device-local**: no CRDT block, hard deletes, never exported, never synced, rebuildable by any reconcile.
- Backup strand rules: `eventOccurrences`, `eventSkips`, `eventAlerts` are keyed to events (absent key beside a present `calendarEvents` **clears** the table); `eventTemplates` is keyed to categories; `categoryAlerts` (v42) follows `eventTemplates` — absent beside `calendarCategories` **clears** (the categories import wipes and replaces, so alerts keyed to old custom ids would orphan and the device's built-in-category alerts would silently apply); `eventDigests` (v42) follows `overviewViews`; `overviewViews` (v41) follows `calendarFilterPresets` — additive, absent leaves the table, the archive version unbumped; `calendarFilterPresets` has **no** strand rule (an absent key leaves presets alone, the `vocabularies` behaviour). Categories import **before** events.
- `event_digests.payload` is one codec, forward-compatible: an unreadable or empty payload or an unknown cadence decodes `enabled = false`.
