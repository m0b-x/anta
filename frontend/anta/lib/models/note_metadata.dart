import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';
import '../utils/markdown_plain_text.dart';
import 'item_label.dart';

class NoteMetadata extends Equatable {
  final String id;
  final String folderId;
  final String title;
  final String preview;
  final int contentLength;
  final int chunkCount;
  final bool isCompressed;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Manual sort position within the parent folder. Used to interleave
  /// notes with sibling folders when [NotesSortOrder.positionAsc] is active.
  final int position;

  /// The optional colour label drawn at the trailing edge of the note's
  /// browser row. [ItemLabel.none] — the default — draws nothing.
  final ItemLabel label;

  const NoteMetadata({
    required this.id,
    required this.folderId,
    required this.title,
    required this.preview,
    required this.contentLength,
    required this.chunkCount,
    required this.isCompressed,
    required this.createdAt,
    required this.updatedAt,
    this.position = 0,
    this.label = ItemLabel.none,
  });

  NoteMetadata copyWith({
    String? id,
    String? folderId,
    String? title,
    String? preview,
    int? contentLength,
    int? chunkCount,
    bool? isCompressed,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? position,
    ItemLabel? label,
  }) {
    return NoteMetadata(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      contentLength: contentLength ?? this.contentLength,
      chunkCount: chunkCount ?? this.chunkCount,
      isCompressed: isCompressed ?? this.isCompressed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      position: position ?? this.position,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      JsonKeys.id: id,
      JsonKeys.folderId: folderId,
      JsonKeys.title: title,
      JsonKeys.preview: preview,
      JsonKeys.contentLength: contentLength,
      JsonKeys.chunkCount: chunkCount,
      JsonKeys.isCompressed: isCompressed,
      JsonKeys.createdAt: createdAt.toIso8601String(),
      JsonKeys.updatedAt: updatedAt.toIso8601String(),
      JsonKeys.label: label.storageName,
    };
  }

  factory NoteMetadata.fromJson(Map<String, dynamic> json) {
    return NoteMetadata(
      id: json[JsonKeys.id] as String,
      folderId: json[JsonKeys.folderId] as String,
      title: json[JsonKeys.title] as String,
      preview: json[JsonKeys.preview] as String? ?? '',
      contentLength: json[JsonKeys.contentLength] as int? ?? 0,
      chunkCount: json[JsonKeys.chunkCount] as int? ?? 1,
      isCompressed: json[JsonKeys.isCompressed] as bool? ?? false,
      createdAt: DateTime.parse(json[JsonKeys.createdAt] as String),
      updatedAt: DateTime.parse(json[JsonKeys.updatedAt] as String),
      label: ItemLabel.fromName(json[JsonKeys.label] as String?),
    );
  }

  /// The stored one-line preview of [content]: markdown markers stripped
  /// through [MarkdownPlainText], every line included in source order so
  /// quick search and FTS keep the reach they had over the raw join.
  ///
  /// The single entry point — every writer of the `preview` column goes
  /// through here, so a row's preview can never depend on which code
  /// path saved it.
  static String generatePreview(String content, {int maxLength = 200}) {
    if (content.isEmpty) return '';
    return MarkdownPlainText.strip(content, maxLength: maxLength);
  }

  @override
  List<Object?> get props => [
    id,
    folderId,
    title,
    preview,
    contentLength,
    chunkCount,
    isCompressed,
    createdAt,
    updatedAt,
    position,
    label,
  ];
}

class LazyNote extends Equatable {
  final NoteMetadata metadata;
  final String? _loadedContent;
  final bool isContentLoaded;

  const LazyNote({
    required this.metadata,
    String? content,
    this.isContentLoaded = false,
  }) : _loadedContent = content;

  String get id => metadata.id;
  String get folderId => metadata.folderId;
  String get title => metadata.title;
  String get preview => metadata.preview;
  int get contentLength => metadata.contentLength;
  DateTime get createdAt => metadata.createdAt;
  DateTime get updatedAt => metadata.updatedAt;

  String? get content => _loadedContent;

  LazyNote withContent(String content) {
    return LazyNote(
      metadata: metadata,
      content: content,
      isContentLoaded: true,
    );
  }

  LazyNote copyWith({
    NoteMetadata? metadata,
    String? content,
    bool? isContentLoaded,
  }) {
    return LazyNote(
      metadata: metadata ?? this.metadata,
      content: content ?? _loadedContent,
      isContentLoaded: isContentLoaded ?? this.isContentLoaded,
    );
  }

  @override
  List<Object?> get props => [metadata, _loadedContent, isContentLoaded];
}

class PaginatedNotes extends Equatable {
  final List<NoteMetadata> notes;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool hasMore;
  final bool isLoading;

  const PaginatedNotes({
    required this.notes,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.hasMore,
    this.isLoading = false,
  });

  PaginatedNotes copyWith({
    List<NoteMetadata>? notes,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    bool? hasMore,
    bool? isLoading,
  }) {
    return PaginatedNotes(
      notes: notes ?? this.notes,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  static PaginatedNotes empty() {
    return const PaginatedNotes(
      notes: [],
      currentPage: 0,
      totalPages: 0,
      totalCount: 0,
      hasMore: false,
    );
  }

  @override
  List<Object?> get props => [
    notes,
    currentPage,
    totalPages,
    totalCount,
    hasMore,
    isLoading,
  ];
}

/// What a colour filter with nothing typed answers: the notes wearing one of
/// the picked colours, newest first, and how many there are in all.
///
/// Not a [PaginatedNotes]: this listing is capped rather than paged — there is
/// no next page to ask for — but the header above it still says how many notes
/// the colours gather, which [total] and not [notes] is the answer to.
class LabelledNotes extends Equatable {
  final List<NoteMetadata> notes;

  /// Every note the colours gather, whether or not it fitted under the cap.
  final int total;

  const LabelledNotes({required this.notes, required this.total});

  static const LabelledNotes empty = LabelledNotes(notes: [], total: 0);

  @override
  List<Object?> get props => [notes, total];
}
