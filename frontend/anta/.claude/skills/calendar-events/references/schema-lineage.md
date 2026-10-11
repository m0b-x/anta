# Calendar schema lineage

Reference, not rules — moved verbatim from the calendar-events SKILL.md on 2026-10-11. Read only the part the task needs.

The rules that outlive every version stayed in the SKILL.md, under the same heading.

## Schema lineage (current v40)

v10 calendar tables → v11 `end_date` + time-of-day → v12 `description` → v13 holiday profiles → v14 `note_id` → v15 data-driven `calendar_categories` → v16 `color_value` / `tint_icon` / `priority` → v17 `suppressed` holidays → v18 priority scale inverted (`p -> 6 - p`, backup v7) → v19 `retroactive` → v20/21 `count_occurrences` + `count_style` → v22 computed holidays (seeded rows deleted) → v23 yearly counts from zero → v24 `calendar_event_occurrences` → v26 `tracks_presence` + `calendar_event_absences` → v27 events CRDT → v28 `per_occurrence_descriptions` + occurrence CRDT → v29 `calendar_event_templates` → v30 `calendar_event_skips` → v31 delta-table indexes → v32 vocabularies → v33 `is_hidden` → v34 `show_in_day_rail` → v35 `calendar_filter_presets` → v36 `idx_notes_ltitle` → v37 assume-absent (`absences.status`, `assume_absent`, `assume_absent_from`, the absence index drop-and-recreated) → v38 repair of a stray v37 → v39 `notes.label` / `folders.label` → v40 alerts (`calendar_event_alerts`, device-local `alert_registrations`, `remove_after_alert`).
