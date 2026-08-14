import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// A small, dependency-free HSV color wheel dialog.
///
/// The disc selects hue (angle) and saturation (radius); a slider below sets
/// the brightness (value). Returns the chosen color as a 32-bit ARGB int, or
/// `null` when cancelled. Kept self-contained on purpose so the app keeps its
/// minimal, offline-first dependency footprint.
class ColorWheelDialog extends StatefulWidget {
  final int? initialColor;

  const ColorWheelDialog({super.key, this.initialColor});

  static Future<int?> show(BuildContext context, {int? initialColor}) {
    return showDialog<int>(
      context: context,
      builder: (_) => ColorWheelDialog(initialColor: initialColor),
    );
  }

  @override
  State<ColorWheelDialog> createState() => _ColorWheelDialogState();
}

class _ColorWheelDialogState extends State<ColorWheelDialog> {
  /// Largest side length of the square wheel in logical pixels. On narrow
  /// screens the wheel shrinks to the available dialog width.
  static const double _maxWheelSize = 240;

  late double _hue;
  late double _saturation;
  late double _value;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialColor;
    final hsv = initial == null
        ? const HSVColor.fromAHSV(1, 0, 1, 1)
        : HSVColor.fromColor(Color(initial));
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = initial == null ? 1.0 : hsv.value;
  }

  Color get _color => HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  void _updateFromLocal(Offset local, double size) {
    final center = Offset(size / 2, size / 2);
    final radius = size / 2;
    final v = local - center;
    final distance = v.distance;
    var angle = math.atan2(v.dy, v.dx);
    if (angle < 0) angle += 2 * math.pi;
    setState(() {
      _hue = (angle * 180 / math.pi) % 360;
      _saturation = radius == 0 ? 0 : (distance / radius).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // AlertDialog sizes itself by wrapping its content in IntrinsicWidth,
    // which cannot traverse a LayoutBuilder (Flutter throws "LayoutBuilder
    // does not support returning intrinsic dimensions" — by design, not a
    // bug we can suppress). So the wheel's width has to come from a value
    // read at build time, not a layout-time constraint query. Mirrors
    // Material's default AlertDialog sizing: ~40px insetPadding + ~24px
    // content padding per side.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final available = screenWidth - (40 + 24) * 2;
    final size = math.min(
      _maxWheelSize,
      available > 0 ? available : _maxWheelSize,
    );

    return AlertDialog(
      title: Text(l10n.eventColorCustomTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onPanStart: (d) => _updateFromLocal(d.localPosition, size),
              onPanUpdate: (d) => _updateFromLocal(d.localPosition, size),
              onTapDown: (d) => _updateFromLocal(d.localPosition, size),
              child: CustomPaint(
                size: Size.square(size),
                painter: _WheelPainter(
                  hue: _hue,
                  saturation: _saturation,
                  value: _value,
                  thumbBorder: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.brightness_6_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: _value,
                    onChanged: (v) => setState(() => _value = v),
                  ),
                ),
                _PreviewSwatch(color: _color),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color.toARGB32()),
          child: Text(l10n.select),
        ),
      ],
    );
  }
}

class _PreviewSwatch extends StatelessWidget {
  final Color color;
  const _PreviewSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;
  final Color thumbBorder;

  const _WheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.thumbBorder,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Hue sweep (red → ... → red) around the disc.
    final hueColors = <Color>[
      for (var i = 0; i <= 360; i += 60)
        HSVColor.fromAHSV(1, (i % 360).toDouble(), 1, 1).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = SweepGradient(colors: hueColors).createShader(rect),
    );

    // Saturation falloff: opaque white at the center → transparent at edge.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // Brightness: darken the whole disc as value decreases.
    if (value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - value),
      );
    }

    // Thumb at (hue angle, saturation radius).
    final angle = hue * math.pi / 180;
    final thumb =
        center +
        Offset(math.cos(angle), math.sin(angle)) * (saturation * radius);
    canvas.drawCircle(thumb, 10, Paint()..color = Colors.white);
    canvas.drawCircle(
      thumb,
      10,
      Paint()
        ..color = thumbBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) {
    return old.hue != hue ||
        old.saturation != saturation ||
        old.value != value ||
        old.thumbBorder != thumbBorder;
  }
}
