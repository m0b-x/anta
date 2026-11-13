import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';
import 'item_label.dart';

/// Whether a folder of the person's own is shared with the partner, and by
/// which mark (`docs/cloud-share-surfaces-roadmap.md` §6.11): a surface
/// offers "Share with {name}" on [none], shows it ticked on [byMark] and
/// disabled on [through], naming the folder whose mark covers this one.
final class FolderShare extends Equatable {
  /// The folder whose mark shares this one, for [through] alone.
  final String? throughFolderId;
  final bool _byMark;

  const FolderShare._(this.throughFolderId, this._byMark);

  static const FolderShare none = FolderShare._(null, false);

  /// The folder carries its own mark and no folder above it does.
  static const FolderShare byMark = FolderShare._(null, true);

  /// A folder above it, [folderId], carries the mark that shares it — the
  /// outermost one when a merge left a mark under a mark, since un-sharing
  /// that one is what would make this folder private.
  const FolderShare.through(String folderId) : this._(folderId, false);

  bool get isShared => _byMark || throughFolderId != null;
  bool get isByMark => _byMark;

  @override
  List<Object?> get props => [throughFolderId, _byMark];
}

/// Represents a folder that contains notes
class Folder extends Equatable {
  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final String? noteSortOrder;
  final String? subfolderSortOrder;

  /// Manual sort position within the folder's parent, in the folders' own
  /// sequence: the custom sort the browser reads it in.
  final int position;

  /// The optional colour label drawn at the trailing edge of the folder's
  /// browser row. [ItemLabel.none] — the default — draws nothing.
  final ItemLabel label;

  /// The folder is one the partner shares with this account: read-only here
  /// (the fences), never part of a reorder, a selection or an export.
  /// Transient — set where `FolderStorageService` maps its rows, never
  /// stored and never in [toJson].
  final bool fromPartner;

  /// How the person shares this folder; [FolderShare.none] for a partner's.
  /// Transient, as [fromPartner] is.
  final FolderShare share;

  const Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    this.noteSortOrder,
    this.subfolderSortOrder,
    this.position = 0,
    this.label = ItemLabel.none,
    this.fromPartner = false,
    this.share = FolderShare.none,
  });

  Folder copyWith({
    String? id,
    String? name,
    String? parentId,
    DateTime? createdAt,
    String? noteSortOrder,
    String? subfolderSortOrder,
    int? position,
    ItemLabel? label,
    bool? fromPartner,
    FolderShare? share,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
      noteSortOrder: noteSortOrder ?? this.noteSortOrder,
      subfolderSortOrder: subfolderSortOrder ?? this.subfolderSortOrder,
      position: position ?? this.position,
      label: label ?? this.label,
      fromPartner: fromPartner ?? this.fromPartner,
      share: share ?? this.share,
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
      JsonKeys.label: label.storageName,
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
      label: ItemLabel.fromName(json[JsonKeys.label] as String?),
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
    label,
    fromPartner,
    share,
  ];
}
