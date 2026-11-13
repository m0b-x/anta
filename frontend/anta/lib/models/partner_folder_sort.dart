import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';

/// The person's own sort of one of the partner's folders
/// (`docs/cloud-share-surfaces-roadmap.md` §6.12: "Sort preferences are mine
/// and keep working"). The folder's sort columns are the partner's row,
/// which this database never writes, so the choice is a setting of this
/// phone's — one JSON map by folder id under `SettingsKeys.shareFolderSorts`
/// — laid over the folder where `FolderStorageService` maps it, and dropped
/// with the folder when the partner's share of it ends
/// (`SharedRowDao` removes it with the row).
class PartnerFolderSort extends Equatable {
  /// A `NotesSortOrder` name, or null for the browser's default.
  final String? noteSortOrder;

  /// A `FoldersSortOrder` name, or null for the browser's default.
  final String? subfolderSortOrder;

  const PartnerFolderSort({this.noteSortOrder, this.subfolderSortOrder});

  /// The map [raw] stores; empty when it is absent or cannot be read, so a
  /// damaged value costs the sorts and never a load.
  static Map<String, PartnerFolderSort> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (value is Map<String, dynamic>)
            key: PartnerFolderSort(
              noteSortOrder: _name(value[JsonKeys.noteSortOrder]),
              subfolderSortOrder: _name(value[JsonKeys.subfolderSortOrder]),
            ),
      };
    } on FormatException {
      return const {};
    }
  }

  /// [sorts] as stored, or null for none: the caller deletes the row then,
  /// so "never set" and "every folder gone" leave the same absence.
  static String? encodeAll(Map<String, PartnerFolderSort> sorts) {
    if (sorts.isEmpty) return null;
    final ids = sorts.keys.toList()..sort();
    return jsonEncode({
      for (final id in ids)
        id: {
          if (sorts[id]!.noteSortOrder != null)
            JsonKeys.noteSortOrder: sorts[id]!.noteSortOrder,
          if (sorts[id]!.subfolderSortOrder != null)
            JsonKeys.subfolderSortOrder: sorts[id]!.subfolderSortOrder,
        },
    });
  }

  static String? _name(Object? value) => value is String ? value : null;

  @override
  List<Object?> get props => [noteSortOrder, subfolderSortOrder];
}
