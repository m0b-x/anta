import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/item_label.dart';
import 'label_dot.dart';

/// The one sheet every "assign a colour" entry point opens: a handle, the
/// action's name, and the [LabelSwatchStrip] ringed on [value].
///
/// Resolves to the picked label, or `null` when the sheet was dismissed
/// without a pick — a caller writes only on a non-null, changed answer.
///
/// The bottom padding is `max(viewInsets, viewPadding)`. Padding by
/// `viewInsets` alone is this app's most-repeated bug — with no keyboard up
/// it is zero, and the strip lands under the gesture bar.
Future<ItemLabel?> showLabelPickerSheet(
  BuildContext context, {
  required ItemLabel value,
}) {
  return showModalBottomSheet<ItemLabel>(
    context: context,
    builder: (sheetContext) {
      // Read from the sheet's own context: it is the one under the route
      // that carries the sheet's insets, and a pick has to pop it.
      final l10n = AppLocalizations.of(sheetContext)!;
      final colorScheme = Theme.of(sheetContext).colorScheme;
      final media = MediaQuery.of(sheetContext);
      final bottomInset = math.max(
        media.viewInsets.bottom,
        media.viewPadding.bottom,
      );
      return SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  l10n.labelAction,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: LabelSwatchStrip(
                  value: value,
                  onChanged: (label) => Navigator.of(sheetContext).pop(label),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// The one-row colour picker that assigns a label: a *clear* swatch first,
/// then the seven hues in palette order.
///
/// One row, divided equally across the sheet's width, so the whole palette is
/// reachable with one thumb and no scroll. Each swatch paints at [dotSize]
/// inside a cell [tapTarget] tall whose width is an eighth of the strip — on a
/// 360 dp phone that is 41 dp, a little under Material's floor but still
/// wider than the painted circle, and never an overflow: eight fixed 48 dp
/// cells plus the padding would need 416 dp.
///
/// The strip is stateless and reports through [onChanged]; whoever hosts it
/// owns the write and decides whether to close.
class LabelSwatchStrip extends StatelessWidget {
  /// The label currently carried by the item, ringed in the strip.
  final ItemLabel value;

  final ValueChanged<ItemLabel> onChanged;

  const LabelSwatchStrip({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// The painted circle each swatch draws.
  static const double swatchSize = 32;

  /// The colour dot inside it.
  static const double dotSize = 22;

  /// The height of one swatch's cell; its width is whatever an eighth of the
  /// strip comes to.
  static const double tapTarget = 48;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _LabelSwatch(
              label: ItemLabel.none,
              selected: value == ItemLabel.none,
              onTap: () => onChanged(ItemLabel.none),
            ),
          ),
          for (final label in ItemLabel.assignable)
            Expanded(
              child: _LabelSwatch(
                label: label,
                selected: value == label,
                onTap: () => onChanged(label),
              ),
            ),
        ],
      ),
    );
  }
}

/// One swatch of [LabelSwatchStrip].
///
/// [ItemLabel.none] is drawn as an outlined circle with a diagonal slash — the
/// absence of a colour said as a shape, because an empty circle alone reads as
/// "white" next to seven filled ones.
class _LabelSwatch extends StatelessWidget {
  final ItemLabel label;
  final bool selected;
  final VoidCallback onTap;

  const _LabelSwatch({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final name = label.displayName(l10n);

    final Widget inner = label == ItemLabel.none
        ? SizedBox.square(
            dimension: LabelSwatchStrip.dotSize,
            child: CustomPaint(
              painter: _NoLabelPainter(color: colorScheme.onSurfaceVariant),
            ),
          )
        : Container(
            width: LabelSwatchStrip.dotSize,
            height: LabelSwatchStrip.dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.labelColor(label, brightness),
              border: Border.all(
                color: AppColors.labelRing(brightness),
                width: 1,
              ),
            ),
          );

    final swatch = Container(
      width: LabelSwatchStrip.swatchSize,
      height: LabelSwatchStrip.swatchSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected
            ? Border.all(color: colorScheme.primary, width: 2)
            : null,
      ),
      child: inner,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Tooltip(
        message: name,
        excludeFromSemantics: true,
        child: SizedBox(
          height: LabelSwatchStrip.tapTarget,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(child: swatch),
          ),
        ),
      ),
    );
  }
}

/// An outlined circle with a diagonal slash: "no label".
class _NoLabelPainter extends CustomPainter {
  final Color color;

  const _NoLabelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final radius = size.shortestSide / 2 - paint.strokeWidth / 2;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, radius, paint);

    final offset = radius * 0.70710678;
    canvas.drawLine(
      Offset(center.dx - offset, center.dy + offset),
      Offset(center.dx + offset, center.dy - offset),
      paint,
    );
  }

  @override
  bool shouldRepaint(_NoLabelPainter oldDelegate) => oldDelegate.color != color;
}
