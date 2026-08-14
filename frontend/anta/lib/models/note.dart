import 'package:equatable/equatable.dart';

import '../constants/json_keys.dart';

class Note extends Equatable {
  final String id;
  final String folderId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.folderId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Note copyWith({
    String? id,
    String? folderId,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      JsonKeys.id: id,
      JsonKeys.folderId: folderId,
      JsonKeys.title: title,
      JsonKeys.content: content,
      JsonKeys.createdAt: createdAt.toIso8601String(),
      JsonKeys.updatedAt: updatedAt.toIso8601String(),
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json[JsonKeys.id] as String,
      folderId: json[JsonKeys.folderId] as String,
      title: json[JsonKeys.title] as String,
      content: json[JsonKeys.content] as String,
      createdAt: DateTime.parse(json[JsonKeys.createdAt] as String),
      updatedAt: DateTime.parse(json[JsonKeys.updatedAt] as String),
    );
  }

  @override
  List<Object?> get props => [
    id,
    folderId,
    title,
    content,
    createdAt,
    updatedAt,
  ];
}
