import 'package:drift/drift.dart';

abstract class DatabaseSchema {
  static const int currentVersion = 21;

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
