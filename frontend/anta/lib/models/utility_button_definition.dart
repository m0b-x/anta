import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'utility_button_config.dart';

/// Describes the static metadata for a utility button: icon, label, lock state.
///
/// All known utility buttons are registered in [all]. Adding a new button
/// requires one entry here plus the corresponding ID constant and
/// default-order entry in [UtilityButtonId].
class UtilityButtonDefinition {
  final String id;
  final IconData icon;
  final String Function(AppLocalizations) labelResolver;
  final bool isLocked;

  UtilityButtonDefinition({
    required this.id,
    required this.icon,
    required this.labelResolver,
    this.isLocked = false,
  });

  String label(AppLocalizations l10n) => labelResolver(l10n);

  // ---------------------------------------------------------------------------
  // Registry
  // ---------------------------------------------------------------------------

  static final List<UtilityButtonDefinition> all = [
    UtilityButtonDefinition(
      id: UtilityButtonId.undo,
      icon: Icons.undo,
      labelResolver: (l) => l.undo,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.redo,
      icon: Icons.redo,
      labelResolver: (l) => l.redo,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.paste,
      icon: Icons.content_paste,
      labelResolver: (l) => l.paste,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.decreaseFont,
      icon: Icons.text_decrease,
      labelResolver: (l) => l.decreaseFontSize,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.increaseFont,
      icon: Icons.text_increase,
      labelResolver: (l) => l.increaseFontSize,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.share,
      icon: Icons.share,
      labelResolver: (l) => l.shareNote,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.switchBar,
      icon: Icons.dashboard_customize,
      labelResolver: (l) => l.switchBar,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.scrollToTop,
      icon: Icons.vertical_align_top,
      labelResolver: (l) => l.goToTop,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.scrollToBottom,
      icon: Icons.vertical_align_bottom,
      labelResolver: (l) => l.goToBottom,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.counter,
      icon: Icons.pin_rounded,
      labelResolver: (l) => l.counterInsertTooltip,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.reorder,
      icon: Icons.swap_horiz,
      labelResolver: (l) => l.reorderShortcuts,
    ),
    UtilityButtonDefinition(
      id: UtilityButtonId.settings,
      icon: Icons.settings,
      labelResolver: (l) => l.settings,
      isLocked: true,
    ),
  ];

  static final Map<String, UtilityButtonDefinition> _byId = {
    for (final def in all) def.id: def,
  };

  /// Returns the definition for [id], or `null` if unknown.
  static UtilityButtonDefinition? getById(String id) => _byId[id];
}
