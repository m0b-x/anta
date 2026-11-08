import 'package:drift/drift.dart';

abstract class DatabaseSchema {
  static const int currentVersion = 51;

  /// The version the sync space carries and every engine compares against:
  /// a space written by a higher one pauses this build as outdated. Bumped
  /// only when the wire changes (the documents the sync bindings write),
  /// never for a local-only migration, so a device on a newer local schema
  /// does not pause every other device; it never exceeds [currentVersion]
  /// (`docs/scalability-roadmap.md` §5.1 S1). 46: a note's body crosses as
  /// chunk documents and a manifest (§5.3 S6).
  static const int syncSchemaVersion = 46;

  static const int v1Initial = 1;
  static const int v2UserSettings = 2;
  static const int v3ContentChunksIsDeleted = 3;
  static const int v4ManualOrdering = 4;
  static const int v5FolderSortPreferences = 5;
  static const int v6CounterTables = 6;
  static const int v7CounterDateTimeFix = 7;
  static const int v8CounterPinAndOrder = 8;
  static const int v9NameUniquenessIndexes = 9;
  static const int v10CalendarTables = 10;
  static const int v11CalendarEndDateAndTimeOfDay = 11;
  static const int v12CalendarDescription = 12;
  static const int v13HolidayProfiles = 13;
  static const int v14CalendarEventNoteLink = 14;
  static const int v15CalendarCategories = 15;
  static const int v16CalendarEventColorPriority = 16;
  static const int v17PublicHolidaySuppressed = 17;
  static const int v18EventPriorityInverted = 18;
  static const int v19EventRetroactive = 19;
  static const int v20EventOccurrenceCount = 20;
  static const int v21EventCountStyle = 21;
  static const int v22ComputedHolidays = 22;
  static const int v23YearlyCountsFromZero = 23;
  static const int v24EventOccurrenceDescriptions = 24;
  static const int v25PositionIndexesOnFreshInstalls = 25;
  static const int v26EventPresence = 26;
  static const int v27CalendarEventsCrdt = 27;
  static const int v28DescriptionScope = 28;
  static const int v29EventTemplates = 29;
  static const int v30EventSkips = 30;
  static const int v31CalendarDeltaIndexes = 31;
  static const int v32Vocabularies = 32;
  static const int v33CategoryHidden = 33;
  static const int v34EventShowInDayRail = 34;
  static const int v35CalendarFilterPresets = 35;
  static const int v36NoteTitleIndex = 36;
  static const int v37AssumeAbsent = 37;
  static const int v38PresenceDefaultRepair = 38;
  static const int v39ItemLabels = 39;
  static const int v40EventAlerts = 40;
  static const int v41OverviewViews = 41;
  static const int v42CategoryAlertsAndDigests = 42;
  static const int v43SyncReadiness = 43;
  static const int v44CategoryProfiles = 44;
  static const int v45OneOffSkipSweep = 45;
  static const int v46ContentChunkHashes = 46;
  static const int v47StorageHygiene = 47;
  static const int v48NoteBodySearch = 48;
  static const int v49Counters = 49;
  static const int v50QuickSearchIndex = 50;
  static const int v51OutboxRepublish = 51;
}

typedef MigrationStep = Future<void> Function(Migrator m, GeneratedDatabase db);

class Migration {
  final int fromVersion;
  final int toVersion;
  final MigrationStep migrate;

  const Migration({
    required this.fromVersion,
    required this.toVersion,
    required this.migrate,
  });
}
