import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/item_label.dart';
import '../models/label_style.dart';

/// The colour label of a note or folder, as the small filled circle drawn at
/// the trailing edge of its browser row.
///
/// [ItemLabel.none] collapses to nothing at all — no box, no reserved width —
/// so an unlabelled row lays out exactly as it did before labels existed and
/// only a labelled one moves anything.
///
/// The ring is a 1px inset hairline at ten percent of the opposite tone. It is
/// what stops the yellow from dissolving into a light row surface, and it is
/// drawn on every hue so the seven read as one set.
class LabelDot extends StatelessWidget {
  final ItemLabel label;
  final double size;

  const LabelDot({
    super.key,
    required this.label,
    this.size = RowMetrics.labelDotSize,
  });

  @override
  Widget build(BuildContext context) {
    if (label == ItemLabel.none) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;

    return Semantics(
      label: l10n.labelSemantics(label.displayName(l10n)),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.labelColor(label, brightness),
          border: Border.all(color: AppColors.labelRing(brightness), width: 1),
        ),
      ),
    );
  }
}

/// What one row has to draw for its label, once the label and the chosen
/// [LabelStyle] are both known.
///
/// Exists so the three rows that carry a label — note, folder, search
/// result — do not each restate the same two-way switch, and so the stripe's
/// colour and its accessible name are resolved in exactly one place.
@immutable
class LabelRowDecoration {
  /// The stripe's fill, non-null only for a labelled row in the stripe style.
  final Color? stripeColor;

  /// The stripe's accessible name — the same string [LabelDot] carries.
  final String? stripeSemantics;

  /// Whether this row draws the trailing dot.
  final bool showsDot;

  const LabelRowDecoration._({
    this.stripeColor,
    this.stripeSemantics,
    this.showsDot = false,
  });

  /// Nothing at all: an unlabelled row, in either style.
  static const LabelRowDecoration none = LabelRowDecoration._();

  factory LabelRowDecoration.resolve(
    BuildContext context, {
    required ItemLabel label,
    required LabelStyle style,
  }) {
    if (label == ItemLabel.none) return none;
    if (style == LabelStyle.dot) {
      return const LabelRowDecoration._(showsDot: true);
    }
    final l10n = AppLocalizations.of(context)!;
    return LabelRowDecoration._(
      stripeColor: AppColors.labelColor(label, Theme.of(context).brightness),
      stripeSemantics: l10n.labelSemantics(label.displayName(l10n)),
    );
  }
}

/// The localized name of a colour label.
///
/// A `switch` over the enum rather than a key lookup: there is no generic
/// `AppLocalizations.byKey`, and a new label added to [ItemLabel] should fail
/// to compile here until it is named in all three ARBs.
extension ItemLabelL10n on ItemLabel {
  String displayName(AppLocalizations l10n) {
    switch (this) {
      case ItemLabel.none:
        return l10n.labelNone;
      case ItemLabel.red:
        return l10n.labelRed;
      case ItemLabel.orange:
        return l10n.labelOrange;
      case ItemLabel.yellow:
        return l10n.labelYellow;
      case ItemLabel.green:
        return l10n.labelGreen;
      case ItemLabel.teal:
        return l10n.labelTeal;
      case ItemLabel.blue:
        return l10n.labelBlue;
      case ItemLabel.pink:
        return l10n.labelPink;
    }
  }
}
