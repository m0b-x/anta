import 'package:flutter/material.dart';
import 'font_constants.dart';

/// Centralized text styles for consistent typography
class AppTextStyles {
  /// Dialog title style
  static const TextStyle dialogTitle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: FontConstants.dialogTitle,
  );

  /// Subtitle with theme color
  static TextStyle subtitle(BuildContext context) => TextStyle(
    fontSize: FontConstants.subtitle,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  /// Caption with theme color
  static TextStyle caption(BuildContext context) => TextStyle(
    fontSize: FontConstants.caption,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  /// Label style
  static const TextStyle label = TextStyle(
    fontSize: FontConstants.label,
    fontWeight: FontWeight.w500,
  );

  /// Error text style
  static const TextStyle error = TextStyle(color: Colors.red);

  /// Title text style
  static const TextStyle title = TextStyle(fontSize: FontConstants.title);

  /// Body text with specific size
  static const TextStyle body = TextStyle(fontSize: FontConstants.body);

  /// Small text
  static const TextStyle small = TextStyle(fontSize: FontConstants.small);
}
