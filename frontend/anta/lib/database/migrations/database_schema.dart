import 'package:drift/drift.dart';

abstract class DatabaseSchema {
  static const int currentVersion = 34;

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
