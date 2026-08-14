import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Known utility button IDs used in the toolbar.
///
/// These serve as stable identifiers across serialization and
/// are matched against when building the toolbar widget list.
class UtilityButtonId {
  UtilityButtonId._();

  static const String undo = 'undo';
  static const String redo = 'redo';
  static const String paste = 'paste';
  static const String decreaseFont = 'decrease_font';
  static const String increaseFont = 'increase_font';
  static const String reorder = 'reorder';
  static const String share = 'share';
  static const String switchBar = 'switch_bar';
  static const String settings = 'settings';
  static const String scrollToTop = 'scroll_to_top';
  static const String scrollToBottom = 'scroll_to_bottom';
  static const String counter = 'counter';

  /// Ordered list of all known utility button IDs (default order).
  static const List<String> defaultOrder = [
    undo,
    redo,
    paste,
    decreaseFont,
    increaseFont,
    share,
    switchBar,
    counter,
    scrollToTop,
    scrollToBottom,
    reorder,
    settings,
  ];

  /// IDs that cannot be hidden (the user must always have access to settings).
  static const Set<String> locked = {settings};
}

/// Lightweight configuration for a single utility button in the toolbar.
class UtilityButtonConfig extends Equatable {
  final String id;
  final bool isVisible;

  const UtilityButtonConfig({required this.id, this.isVisible = true});

  UtilityButtonConfig copyWith({bool? isVisible}) {
    return UtilityButtonConfig(id: id, isVisible: isVisible ?? this.isVisible);
  }

  Map<String, dynamic> toJson() => {'id': id, 'isVisible': isVisible};

  factory UtilityButtonConfig.fromJson(Map<String, dynamic> json) {
    return UtilityButtonConfig(
      id: json['id'] as String,
      isVisible: json['isVisible'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [id, isVisible];

  /// Returns the default configuration list with all buttons visible
  /// in the standard order.
  static List<UtilityButtonConfig> defaults() {
    return UtilityButtonId.defaultOrder
        .map((id) => UtilityButtonConfig(id: id))
        .toList();
  }

  /// Serializes the list to a JSON string for database storage.
  static String encode(List<UtilityButtonConfig> configs) {
    return jsonEncode(configs.map((c) => c.toJson()).toList());
  }

  /// Deserializes from a JSON string, merging with defaults so that
  /// newly added buttons are included and removed ones are dropped.
  static List<UtilityButtonConfig> decode(String jsonStr) {
    final List<dynamic> decoded = jsonDecode(jsonStr);
    final loaded = decoded
        .map((json) => UtilityButtonConfig.fromJson(json))
        .toList();

    // Preserve saved order for known buttons, then append any new defaults.
    final knownIds = UtilityButtonId.defaultOrder.toSet();
    final result = <UtilityButtonConfig>[];

    // First: buttons from saved order that are still known.
    for (final config in loaded) {
      if (knownIds.contains(config.id)) {
        result.add(config);
      }
    }

    // Second: any new default buttons not yet in saved config.
    final savedIds = result.map((c) => c.id).toSet();
    for (final id in UtilityButtonId.defaultOrder) {
      if (!savedIds.contains(id)) {
        result.add(UtilityButtonConfig(id: id));
      }
    }

    return result;
  }
}
