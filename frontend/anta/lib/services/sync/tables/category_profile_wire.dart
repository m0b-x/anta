import 'package:drift/drift.dart' show Value;

import '../../../constants/category_kinds.dart';
import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../sync_table_binding.dart';

/// The one map a `calendar_category_profiles` row is written as, for the
/// sync binding and the backup alike: every column as stored, under its
/// [CategoryProfileKeys] name, the dates as epoch milliseconds.
///
/// Raw on both ends, never through `CategoryProfile`: the model reads a
/// kind, area, measure or target this build does not know as `custom` or
/// absent, and a backup written through it after a sync with a newer build
/// would downgrade those categories for good.
abstract final class CategoryProfileWire {
  static const String table = 'calendar_category_profiles';

  static Map<String, Object?> encode(CategoryProfileRow row) => {
    CategoryProfileKeys.id: row.id,
    CategoryProfileKeys.categoryId: row.categoryId,
    CategoryProfileKeys.kind: row.kind,
    CategoryProfileKeys.area: row.area,
    CategoryProfileKeys.measure: row.measure,
    CategoryProfileKeys.nominalMinutes: row.nominalMinutes,
    CategoryProfileKeys.markVerb: row.markVerb,
    CategoryProfileKeys.marksNew: row.marksNew,
    CategoryProfileKeys.assumeAbsentNew: row.assumeAbsentNew,
    CategoryProfileKeys.countsHours: row.countsHours,
    CategoryProfileKeys.targetKind: row.targetKind,
    CategoryProfileKeys.targetValue: row.targetValue,
    CategoryProfileKeys.targetPeriod: row.targetPeriod,
    CategoryProfileKeys.createdAt: row.createdAt.millisecondsSinceEpoch,
    CategoryProfileKeys.updatedAt: row.updatedAt.millisecondsSinceEpoch,
    if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
  };

  /// [encode] read back: the identity, content, audit and owner columns, no
  /// CRDT field — the envelope or the importing DAO stamps those.
  ///
  /// Strict for a live map ([WireFields]): a missing or mistyped column is a
  /// [FormatException] naming the key, never a default over real data. A
  /// tombstone's empty map takes the column defaults.
  static CalendarCategoryProfilesCompanion decode(WireFields f) {
    return CalendarCategoryProfilesCompanion(
      id: Value(f.field<String>(CategoryProfileKeys.id, '')),
      categoryId: Value(f.field<String>(CategoryProfileKeys.categoryId, '')),
      kind: Value(f.field<String>(CategoryProfileKeys.kind, 'custom')),
      area: Value(f.nullable<String>(CategoryProfileKeys.area)),
      measure: Value(f.nullable<String>(CategoryProfileKeys.measure)),
      nominalMinutes: Value(
        f.nullable<int>(CategoryProfileKeys.nominalMinutes),
      ),
      markVerb: Value(f.nullable<String>(CategoryProfileKeys.markVerb)),
      marksNew: Value(f.nullable<bool>(CategoryProfileKeys.marksNew)),
      assumeAbsentNew: Value(
        f.nullable<bool>(CategoryProfileKeys.assumeAbsentNew),
      ),
      countsHours: Value(f.nullable<bool>(CategoryProfileKeys.countsHours)),
      targetKind: Value(f.nullable<String>(CategoryProfileKeys.targetKind)),
      targetValue: Value(f.nullable<int>(CategoryProfileKeys.targetValue)),
      targetPeriod: Value(f.nullable<String>(CategoryProfileKeys.targetPeriod)),
      createdAt: Value(f.fieldMs(CategoryProfileKeys.createdAt)),
      updatedAt: Value(f.fieldMs(CategoryProfileKeys.updatedAt)),
      ownerId: Value(JsonKeys.ownerIdOf(f.data)),
    );
  }
}
