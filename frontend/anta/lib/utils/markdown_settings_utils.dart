import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/custom_markdown_shortcut.dart';
import 'icon_utils.dart';

/// UI helpers for displaying and transforming markdown shortcuts.
///
/// All persistence is handled by [MarkdownBarService]. This class contains
/// only stateless, presentation-layer utilities.
class MarkdownSettingsUtils {
  static Widget buildShortcutIcon(
    BuildContext context,
    CustomMarkdownShortcut shortcut,
  ) {
    if (shortcut.id == 'default_header') {
      return Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        child: Text(
          'H',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    return Icon(
      IconUtils.getIconFromData(
        shortcut.iconCodePoint,
        shortcut.iconFontFamily,
      ),
      size: 24,
    );
  }

  static String getShortcutSubtitle(
    BuildContext context,
    CustomMarkdownShortcut shortcut,
  ) {
    final parts = <String>[];

    switch (shortcut.insertType) {
      case 'date':
        parts.add(AppLocalizations.of(context)!.insertsCurrentDate);

        // Show date offset info if any
        final offset = shortcut.dateOffset;
        if (offset != null && !offset.isEmpty) {
          final offsetParts = <String>[];
          if (offset.days != 0) offsetParts.add('${offset.days}d');
          if (offset.months != 0) offsetParts.add('${offset.months}m');
          if (offset.years != 0) offsetParts.add('${offset.years}y');
          parts.add('(${offsetParts.join(', ')})');
        }
        break;
      case 'header':
        parts.add(AppLocalizations.of(context)!.opensHeaderMenu);
        break;
      default:
        final before = _truncateText(shortcut.beforeText, 15);
        final after = _truncateText(shortcut.afterText, 15);
        parts.add(AppLocalizations.of(context)!.beforeAfterText(before, after));
    }

    // Show repeat info if configured
    final repeatConfig = shortcut.repeatConfig;
    if (repeatConfig != null && repeatConfig.isActive) {
      parts.add('×${repeatConfig.count}');
      if (repeatConfig.incrementDate) {
        parts.add('+date');
      }
    }

    return parts.join(' ');
  }

  static String _truncateText(String text, int maxLength) {
    final escaped = text.replaceAll('\n', '↵').replaceAll('\t', '→');
    if (escaped.length <= maxLength) {
      return escaped;
    }
    return '${escaped.substring(0, maxLength)}…';
  }

  static List<CustomMarkdownShortcut> removeAllCustom(
    List<CustomMarkdownShortcut> currentShortcuts,
  ) {
    return currentShortcuts.where((s) => s.isDefault).toList();
  }
}
