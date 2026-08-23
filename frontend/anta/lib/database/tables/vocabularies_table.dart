import 'package:drift/drift.dart';

/// User-defined suggestion lists (**v32**).
///
/// A vocabulary is a named bag of terms the editor offers as autocomplete —
/// "Exercises", "Supplements", "Clients". It exists so the same thing gets
/// written the same way every time; it never constrains what may be typed, so
/// nothing here is validation.
///
/// [name] is matched against a ghost placeholder's inner text to scope the
/// suggestion bar (`{{exercise}}` → the "Exercises" vocabulary), folded through
/// `normalizeForSearch` at comparison time. Stored verbatim, matched folded —
/// the canonicalization policy the tag roadmap sets for every user-authored
/// string.
///
/// [isEnabled] turns a list off without deleting it, so a seasonal vocabulary
/// can stop cluttering suggestions and come back later with its terms intact.
///
/// The five CRDT columns are the Notes/Folders block byte-for-byte, present
/// from birth — the `calendar_event_templates` (v29) precedent: a table that
/// starts empty gets the shape for free, with no `withDefault('')` deviation on
/// the identity columns because no existing row has to be satisfied. Stamping
/// lives entirely in `VocabularyDao`.
@DataClassName('VocabularyRow')
class Vocabularies extends Table {
  @override
  String get tableName => 'vocabularies';

  TextColumn get id => text()();
  TextColumn get name => text()();

  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
