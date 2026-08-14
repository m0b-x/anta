import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'custom_markdown_shortcut.dart';

/// A named toolbar profile containing a set of markdown shortcuts.
///
/// Each profile has a unique [id], a user-visible [name], and its own
/// ordered list of [shortcuts]. The special [isDefault] flag marks
/// the built-in profile which cannot be deleted or renamed.
class MarkdownBarProfile extends Equatable {
  /// Stable unique identifier (UUID v4 for user-created profiles).
  final String id;

  /// User-visible display name.
  final String name;

  /// Whether this is the built-in default profile.
  final bool isDefault;

  /// Ordered list of shortcuts belonging to this profile.
  final List<CustomMarkdownShortcut> shortcuts;

  /// Timestamp of last modification (for sorting / display).
  final DateTime updatedAt;

  const MarkdownBarProfile({
    required this.id,
    required this.name,
    this.isDefault = false,
    required this.shortcuts,
    required this.updatedAt,
  });

  /// The well-known ID of the built-in default profile.
  static const String defaultProfileId = 'default';

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isDefault': isDefault,
    'shortcuts': shortcuts.map((s) => s.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MarkdownBarProfile.fromJson(Map<String, dynamic> json) {
    return MarkdownBarProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      shortcuts: (json['shortcuts'] as List<dynamic>)
          .map(
            (s) => CustomMarkdownShortcut.fromJson(s as Map<String, dynamic>),
          )
          .toList(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Batch helpers (encode / decode a full list of profiles)
  // ---------------------------------------------------------------------------

  static String encodeList(List<MarkdownBarProfile> profiles) {
    return jsonEncode(profiles.map((p) => p.toJson()).toList());
  }

  static List<MarkdownBarProfile> decodeList(String jsonStr) {
    final List<dynamic> decoded = jsonDecode(jsonStr);
    return decoded
        .map((j) => MarkdownBarProfile.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Copy helpers
  // ---------------------------------------------------------------------------

  MarkdownBarProfile copyWith({
    String? id,
    String? name,
    bool? isDefault,
    List<CustomMarkdownShortcut>? shortcuts,
    DateTime? updatedAt,
  }) {
    return MarkdownBarProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      shortcuts: shortcuts ?? List.from(this.shortcuts),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, isDefault, shortcuts, updatedAt];
}
