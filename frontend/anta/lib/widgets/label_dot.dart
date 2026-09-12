import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/item_label.dart';

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
