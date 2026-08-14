import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';

/// Represents a folder that contains notes
class Folder extends Equatable {
  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final String? noteSortOrder;
  final String? subfolderSortOrder;

  /// Manual sort position within the folder's parent. Used to interleave
  /// folders and notes in a single ordering when [FoldersSortOrder.positionAsc]
  /// is active.
  final int position;

  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    this.noteSortOrder,
    this.subfolderSortOrder,
    this.position = 0,
  });

  Folder copyWith({
    String? id,
    String? name,
    String? parentId,
    DateTime? createdAt,
    String? noteSortOrder,
    String? subfolderSortOrder,
    int? position,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      noteSortOrder: noteSortOrder ?? this.noteSortOrder,
      subfolderSortOrder: subfolderSortOrder ?? this.subfolderSortOrder,
      position: position ?? this.position,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      JsonKeys.id: id,
      JsonKeys.name: name,
      JsonKeys.parentId: parentId,
      JsonKeys.createdAt: createdAt.toIso8601String(),
      JsonKeys.noteSortOrder: noteSortOrder,
      JsonKeys.subfolderSortOrder: subfolderSortOrder,
    };
  }

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json[JsonKeys.id] as String,
      name: json[JsonKeys.name] as String,
      parentId: json[JsonKeys.parentId] as String?,
      createdAt: DateTime.parse(json[JsonKeys.createdAt] as String),
      noteSortOrder: json[JsonKeys.noteSortOrder] as String?,
      subfolderSortOrder: json[JsonKeys.subfolderSortOrder] as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    parentId,
    createdAt,
    noteSortOrder,
    subfolderSortOrder,
    position,
  ];
}
