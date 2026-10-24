import 'sync_table_binding.dart';
import 'tables/counter_values_binding.dart';
import 'tables/counters_binding.dart';
import 'tables/folders_binding.dart';
import 'tables/notes_binding.dart';
import 'tables/vocabularies_binding.dart';
import 'tables/vocabulary_items_binding.dart';

/// Every synced table's binding, in pull order: a parent before its children,
/// so a page of children lands under rows the screens already know. Nothing
/// in SQLite enforces it (no `PRAGMA foreign_keys`); the order is for the
/// screens' sake.
///
/// S2b prepends the calendar tables — categories, templates, events, the
/// three day tables, event alerts, category alerts, digests, filter presets,
/// overview views — and pins this list complete against `syncedTables`
/// (minus `content_chunks`, which travels inside its note).
const List<SyncTableBinding<Object>> syncTableBindings = [
  FoldersBinding(),
  NotesBinding(),
  CountersBinding(),
  CounterValuesBinding(),
  VocabulariesBinding(),
  VocabularyItemsBinding(),
];
