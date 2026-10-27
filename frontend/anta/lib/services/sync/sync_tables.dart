import 'sync_table_binding.dart';
import 'tables/calendar_categories_binding.dart';
import 'tables/calendar_category_alerts_binding.dart';
import 'tables/calendar_event_absences_binding.dart';
import 'tables/calendar_event_alerts_binding.dart';
import 'tables/calendar_event_occurrences_binding.dart';
import 'tables/calendar_event_skips_binding.dart';
import 'tables/calendar_event_templates_binding.dart';
import 'tables/calendar_events_binding.dart';
import 'tables/calendar_filter_presets_binding.dart';
import 'tables/counter_values_binding.dart';
import 'tables/counters_binding.dart';
import 'tables/event_digests_binding.dart';
import 'tables/folders_binding.dart';
import 'tables/notes_binding.dart';
import 'tables/overview_views_binding.dart';
import 'tables/vocabularies_binding.dart';
import 'tables/vocabulary_items_binding.dart';

/// Every synced table's binding, in pull order: a parent before its children,
/// so a page of children lands under rows the screens already know. Nothing
/// in SQLite enforces it (no `PRAGMA foreign_keys`); the order is for the
/// screens' sake. One entry per `syncedTables` row except `content_chunks`,
/// which travels inside its note — `sync_tables_test` pins it complete.
///
/// One exception, deliberate: an event's `noteId` points at a note, and the
/// calendar block comes before `notes` — the calendar is the heavier read
/// and the link is followed only on a tap. Inside one run a merged event can
/// name a note that has not arrived; `afterRun` refreshes once it has (R82).
const List<SyncTableBinding<Object>> syncTableBindings = [
  CalendarCategoriesBinding(),
  CalendarEventTemplatesBinding(),
  CalendarEventsBinding(),
  CalendarEventOccurrencesBinding(),
  CalendarEventAbsencesBinding(),
  CalendarEventSkipsBinding(),
  CalendarEventAlertsBinding(),
  CalendarCategoryAlertsBinding(),
  EventDigestsBinding(),
  CalendarFilterPresetsBinding(),
  OverviewViewsBinding(),
  FoldersBinding(),
  NotesBinding(),
  CountersBinding(),
  CounterValuesBinding(),
  VocabulariesBinding(),
  VocabularyItemsBinding(),
];
