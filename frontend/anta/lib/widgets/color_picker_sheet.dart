import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_spacing.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/color_picker_mode.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';

/// Dependency-free HSV colour picker: a saturation/brightness square, a hue
/// slider, and a hex field, returning an opaque 32-bit ARGB int (or `null` on
/// cancel).
///
/// **Two geometries, square by default.** On a wheel, hue and saturation are
/// polar-coupled — dragging toward "less saturated" drifts the hue — and full
/// saturation lives in a thin rim, which is exactly where people aim; the
/// square gives two independent Cartesian axes over its whole area, so it is
/// the easier target one-handed and it stays the default. The wheel is the
/// opt-in for the many people who have used one for years and reach for it by
/// habit. The choice is a standing preference ([ColorPickerMode], persisted),
/// resolved in [show] *before* the sheet is built so it can never open square
/// and flip to wheel a frame later.
///
/// Only the geometry and the slider under it differ: the wheel owns hue, so
/// its slider carries brightness, while the square's carries hue. Everything
/// else — the preview pair, the hex field, the actions — is one implementation
/// shared by both, and switching modes never changes the selected colour.
///
/// **A sheet rather than a dialog.** The hex field summons the keyboard, which
/// covers a centred `AlertDialog`; a sheet rises with it. It also retires the
/// `IntrinsicWidth`/`LayoutBuilder` conflict the dialog had to size its wheel
/// around — a sheet's content gets real width constraints.
///
/// **No alpha.** Every calendar surface applies its own `withValues(alpha:)`
/// for washes, stripes and dimmed states, so a user-chosen opacity would
/// multiply into those and the rendered day would disagree with the swatch.
/// Six hex digits in, `0xFF` alpha out.
class ColorPickerSheet extends StatefulWidget {
  /// The colour being replaced, if any. Non-null turns the preview row into a
  /// before/after pair — editing a swatch is "this dot, but that shade", and
  /// without the old colour on screen that is a match from memory.
  final int? initialColor;

  /// The geometry to open with. [show] resolves it from settings; the
  /// parameter exists so a caller — and a test — can pin it.
  final ColorPickerMode initialMode;

  const ColorPickerSheet({
    super.key,
    this.initialColor,
    this.initialMode = ColorPickerMode.square,
  });

  static Future<int?> show(BuildContext context, {int? initialColor}) async {
    final mode = await _loadMode();
    if (!context.mounted) return null;
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          ColorPickerSheet(initialColor: initialColor, initialMode: mode),
    );
  }

  /// Reads the remembered geometry, falling back to the square on any
  /// failure.
  ///
  /// The guard is deliberately total: this is a cosmetic preference opening a
  /// sheet the user just asked for, so no settings failure — an unavailable
  /// database, a widget test with no backend bound — is worth turning into a
  /// picker that does not open.
  static Future<ColorPickerMode> _loadMode() async {
    try {
      final settings = await SettingsService.getInstance();
      return await settings.getColorPickerMode();
    } catch (e) {
      debugPrint('[ColorPickerSheet] Mode read failed: $e');
      return ColorPickerMode.fromName(SettingsKeys.defaultColorPickerMode);
    }
  }

  @override
  State<ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<ColorPickerSheet> {
  /// Tallest the square is allowed to get; on a short screen it shrinks with
  /// the sheet rather than pushing the actions off the bottom.
  static const double _maxSquareHeight = 240;

  /// One arrow-key press, and one accessibility increment, as a fraction of
  /// the axis. Shift multiplies it by [_coarseStepFactor].
  static const double _step = 0.02;
  static const double _semanticStep = 0.05;
  static const double _coarseStepFactor = 5;

  /// How long the geometry cross-fade runs. Short enough that a tap feels
  /// answered rather than staged.
  static const Duration _modeFade = Duration(milliseconds: 150);

  late double _hue;
  late double _saturation;
  late double _value;
  late ColorPickerMode _mode;

  late final TextEditingController _hexController;
  final FocusNode _hexFocus = FocusNode();
  bool _hexInvalid = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    final initial = widget.initialColor;
    final hsv = initial == null
        ? const HSVColor.fromAHSV(1, 210, 0.7, 0.9)
        : HSVColor.fromColor(Color(initial));
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _hexController = TextEditingController(text: _hexOf(_color));
    // The field mirrors the square while the user is elsewhere, and stops
    // mirroring the moment they type into it — see [_syncHexField].
    _hexFocus.addListener(() {
      if (mounted && !_hexFocus.hasFocus) setState(_syncHexField);
    });
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  Color get _color => HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  static String _hexOf(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Rewrites the field from the current HSV — but never while the field has
  /// focus, or every keystroke would fight the caret.
  void _syncHexField() {
    if (_hexFocus.hasFocus) return;
    final hex = _hexOf(_color);
    if (_hexController.text == hex) return;
    _hexController.text = hex;
    _hexInvalid = false;
  }

  void _applyHsv({double? hue, double? saturation, double? value}) {
    setState(() {
      if (hue != null) _hue = hue % 360;
      if (saturation != null) _saturation = saturation.clamp(0.0, 1.0);
      if (value != null) _value = value.clamp(0.0, 1.0);
      _syncHexField();
    });
  }

  /// Exactly six hex digits, optionally led by one `#`.
  ///
  /// Anchored and explicit rather than "strip a hash and try to parse": a
  /// looser reading accepts `12#3456` and `-12345` — `int.tryParse` takes a
  /// sign — and applies a colour for input the user can see is nonsense.
  static final RegExp _hexPattern = RegExp(r'^#?[0-9a-fA-F]{6}$');

  /// Parses what has been typed. Six digits apply live; anything else marks
  /// the field invalid and changes no colour — including an eight-digit
  /// value, which would be an alpha this picker does not offer.
  void _onHexChanged(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _hexInvalid = false);
      return;
    }
    if (!_hexPattern.hasMatch(text)) {
      setState(() => _hexInvalid = true);
      return;
    }
    final parsed = int.parse(text.replaceFirst('#', ''), radix: 16);
    final hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
    setState(() {
      _hexInvalid = false;
      // A grey has no hue — `HSVColor.fromColor` reports 0 for anything
      // achromatic. Taking that would swing the wheel and the hue slider to
      // red the moment someone types `000000`, so the hue in force is kept:
      // it is the axis the user will reach for next, and at saturation 0 it
      // changes nothing about the colour they just asked for.
      if (hsv.saturation > 0) _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
    });
  }

  void _revertToInitial() {
    final initial = widget.initialColor;
    if (initial == null) return;
    final hsv = HSVColor.fromColor(Color(initial));
    _hexFocus.unfocus();
    _applyHsv(hue: hsv.hue, saturation: hsv.saturation, value: hsv.value);
  }

  Future<void> _copyHex() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _hexOf(_color)));
    if (!mounted) return;
    CustomSnackbar.showSuccess(context, l10n.colorHexCopied);
  }

  /// Switching geometry is a view change and nothing else: the HSV state
  /// carries across untouched, so the hex and both preview dots are identical
  /// either side of the tap.
  void _setMode(ColorPickerMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    unawaited(_persistMode(mode));
  }

  /// Fire-and-forget, and guarded like the read: failing to remember the
  /// geometry must never interrupt the colour the user is in the middle of
  /// picking.
  static Future<void> _persistMode(ColorPickerMode mode) async {
    try {
      final settings = await SettingsService.getInstance();
      await settings.setColorPickerMode(mode);
    } catch (e) {
      debugPrint('[ColorPickerSheet] Mode write failed: $e');
    }
  }

  /// Polar coordinates → hue (angle) and saturation (radius).
  ///
  /// A point beyond the rim keeps tracking at full saturation rather than
  /// dropping the gesture — a finger that overshoots is still pointing at a
  /// hue, and stopping dead there is what makes a wheel feel slippery.
  void _setFromWheel(Offset local, double diameter) {
    final radius = diameter / 2;
    final v = local - Offset(radius, radius);
    // `atan2` is undefined at the exact centre; keeping the hue there stops a
    // dead-centre tap from snapping the slider track and the hex to 0°.
    if (v.distance < 0.5) {
      _applyHsv(saturation: 0);
      return;
    }
    var angle = math.atan2(v.dy, v.dx);
    if (angle < 0) angle += 2 * math.pi;
    _applyHsv(
      hue: angle * 180 / math.pi,
      saturation: radius == 0 ? 0 : v.distance / radius,
    );
  }

  /// Arrow keys on the wheel, in its own axes: across walks the hue, up and
  /// down the saturation.
  KeyEventResult _onWheelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final coarse = HardwareKeyboard.instance.isShiftPressed
        ? _coarseStepFactor
        : 1;
    final step = _step * coarse;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _applyHsv(hue: _hue - step * 360);
      case LogicalKeyboardKey.arrowRight:
        _applyHsv(hue: _hue + step * 360);
      case LogicalKeyboardKey.arrowUp:
        _applyHsv(saturation: _saturation + step);
      case LogicalKeyboardKey.arrowDown:
        _applyHsv(saturation: _saturation - step);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The wheel's spoken value. Saturation is the axis the increase/decrease
  /// actions step, not hue: hue wraps, and a value that rolls 359 → 0 reads
  /// as broken to a screen reader.
  String _wheelSemanticValue(AppLocalizations l10n, double saturation) {
    return l10n.colorHueSaturationValue(
      _hue.round(),
      (saturation * 100).round(),
    );
  }

  String _semanticValue(AppLocalizations l10n, double brightness) {
    return l10n.colorSaturationBrightnessValue(
      (_saturation * 100).round(),
      (brightness * 100).round(),
    );
  }

  /// Square coordinates → saturation (x) and brightness (y, top is brightest).
  void _setFromSquare(Offset local, Size size) {
    _applyHsv(
      saturation: size.width == 0 ? 0 : local.dx / size.width,
      value: size.height == 0 ? 1 : 1 - local.dy / size.height,
    );
  }

  /// Arrow keys nudge the square on desktop; Shift makes the step coarse.
  /// Handled here rather than left to focus traversal, because a focused
  /// colour field is the one place arrows should move the value.
  KeyEventResult _onSquareKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final coarse = HardwareKeyboard.instance.isShiftPressed
        ? _coarseStepFactor
        : 1;
    final step = _step * coarse;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _applyHsv(saturation: _saturation - step);
      case LogicalKeyboardKey.arrowRight:
        _applyHsv(saturation: _saturation + step);
      case LogicalKeyboardKey.arrowUp:
        _applyHsv(value: _value + step);
      case LogicalKeyboardKey.arrowDown:
        _applyHsv(value: _value - step);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initial = widget.initialColor;
    // The sheet, not just the scroll view, takes the clearance: the actions
    // sit at its bottom edge and have to stay reachable. It is the **larger**
    // of the keyboard inset and the system's bottom inset, never just the
    // keyboard — `useSafeArea: true` wraps the route in `SafeArea(bottom:
    // false)`, so with no keyboard up this sheet's Cancel/Select row runs
    // underneath the gesture pill or the three-button bar.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.eventColorCustomTitle,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Icon-only: the two names are wide in German, and the row has
                // to hold a title as well. The tooltips carry the names, and
                // with them the semantics labels.
                SegmentedButton<ColorPickerMode>(
                  segments: [
                    ButtonSegment(
                      value: ColorPickerMode.square,
                      icon: const Icon(Icons.gradient_rounded),
                      tooltip: l10n.colorModeSquare,
                    ),
                    ButtonSegment(
                      value: ColorPickerMode.wheel,
                      icon: const Icon(Icons.donut_large_rounded),
                      tooltip: l10n.colorModeWheel,
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (selection) => _setMode(selection.first),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _GeometryBox(
              mode: _mode,
              fadeDuration: _modeFade,
              maxHeight: _maxSquareHeight,
              square: (size) => _SaturationBrightnessSquare(
                size: size,
                hue: _hue,
                saturation: _saturation,
                value: _value,
                semanticLabel: l10n.colorSaturationBrightness,
                // All three are required together: a semantics node carrying
                // an increase action must declare what the value becomes, or
                // the framework asserts.
                semanticValue: _semanticValue(l10n, _value),
                semanticIncreasedValue: _semanticValue(
                  l10n,
                  (_value + _semanticStep).clamp(0.0, 1.0),
                ),
                semanticDecreasedValue: _semanticValue(
                  l10n,
                  (_value - _semanticStep).clamp(0.0, 1.0),
                ),
                onChanged: _setFromSquare,
                onKeyEvent: _onSquareKey,
                onSemanticIncrease: () =>
                    _applyHsv(value: _value + _semanticStep),
                onSemanticDecrease: () =>
                    _applyHsv(value: _value - _semanticStep),
              ),
              wheel: (size) => _HueSaturationWheel(
                diameter: size.height,
                hue: _hue,
                saturation: _saturation,
                value: _value,
                semanticLabel: l10n.colorHueSaturation,
                semanticValue: _wheelSemanticValue(l10n, _saturation),
                semanticIncreasedValue: _wheelSemanticValue(
                  l10n,
                  (_saturation + _semanticStep).clamp(0.0, 1.0),
                ),
                semanticDecreasedValue: _wheelSemanticValue(
                  l10n,
                  (_saturation - _semanticStep).clamp(0.0, 1.0),
                ),
                onChanged: _setFromWheel,
                onKeyEvent: _onWheelKey,
                onSemanticIncrease: () =>
                    _applyHsv(saturation: _saturation + _semanticStep),
                onSemanticDecrease: () =>
                    _applyHsv(saturation: _saturation - _semanticStep),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // One slider row in both modes, same metrics, so the toggle moves
            // nothing below it. The wheel owns hue, so its slider takes the
            // axis the wheel has no room for.
            if (_mode == ColorPickerMode.square)
              _GradientSlider(
                value: _hue,
                max: 360,
                label: l10n.colorHue,
                trackColors: const [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
                thumbColor: HSVColor.fromAHSV(1, _hue, 1, 1).toColor(),
                formatValue: (v) => '${v.round()}°',
                onChanged: (hue) => _applyHsv(hue: hue),
              )
            else
              _GradientSlider(
                value: _value,
                max: 1,
                label: l10n.colorBrightness,
                // The track previews exactly what dragging it does to the
                // colour currently chosen on the wheel.
                trackColors: [
                  Colors.black,
                  HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
                ],
                thumbColor: _color,
                formatValue: (v) => '${(v * 100).round()}%',
                onChanged: (value) => _applyHsv(value: value),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (initial != null) ...[
                  _PreviewDot(
                    color: Color(initial),
                    tooltip: l10n.colorPickerCurrent,
                    onTap: _revertToInitial,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                _PreviewDot(color: _color, tooltip: l10n.colorPickerNew),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    focusNode: _hexFocus,
                    // `#` + eight digits: long enough to *accept* a pasted
                    // ARGB code so the error can explain that this picker has
                    // no alpha. A cap of 7 would have the length formatter
                    // reject the paste with no keystroke and no explanation.
                    maxLength: 9,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: l10n.colorHexLabel,
                      counterText: '',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _hexInvalid ? l10n.colorHexInvalid : null,
                    ),
                    onChanged: _onHexChanged,
                    onSubmitted: (_) => _hexFocus.unfocus(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.colorCopyHex,
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: _copyHex,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_color.toARGB32()),
                  child: Text(l10n.select),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The one box both geometries live in.
///
/// Its height is the square's formula, and the disc is sized from it and
/// centred — so switching modes cannot move the slider, the hex field or the
/// actions by a pixel. Only the geometry cross-fades; the box itself never
/// resizes, which is why the switcher stacks its children rather than letting
/// them lay each other out.
class _GeometryBox extends StatelessWidget {
  final ColorPickerMode mode;
  final Duration fadeDuration;
  final double maxHeight;
  final Widget Function(Size size) square;
  final Widget Function(Size size) wheel;

  const _GeometryBox({
    required this.mode,
    required this.fadeDuration,
    required this.maxHeight,
    required this.square,
    required this.wheel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Slightly wide rather than square: saturation is the axis people
        // travel furthest along, and a sheet has width to spare where it has
        // no height to spare. The disc takes the short side, so the height is
        // also its diameter.
        final width = constraints.maxWidth;
        final height = (width / 1.5).clamp(140.0, maxHeight);
        final size = Size(width, height);

        return SizedBox(
          width: width,
          height: height,
          child: AnimatedSwitcher(
            duration: fadeDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: mode == ColorPickerMode.square
                ? KeyedSubtree(
                    key: const ValueKey('color_picker_square'),
                    child: square(size),
                  )
                : KeyedSubtree(
                    key: const ValueKey('color_picker_wheel'),
                    child: Center(child: wheel(size)),
                  ),
          ),
        );
      },
    );
  }
}

/// The saturation (x) / brightness (y) plane for one hue.
class _SaturationBrightnessSquare extends StatelessWidget {
  final Size size;
  final double hue;
  final double saturation;
  final double value;
  final String semanticLabel;
  final String semanticValue;
  final String semanticIncreasedValue;
  final String semanticDecreasedValue;
  final void Function(Offset local, Size size) onChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onSemanticIncrease;
  final VoidCallback onSemanticDecrease;

  const _SaturationBrightnessSquare({
    required this.size,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.semanticLabel,
    required this.semanticValue,
    required this.semanticIncreasedValue,
    required this.semanticDecreasedValue,
    required this.onChanged,
    required this.onKeyEvent,
    required this.onSemanticIncrease,
    required this.onSemanticDecrease,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: semanticLabel,
      value: semanticValue,
      increasedValue: semanticIncreasedValue,
      decreasedValue: semanticDecreasedValue,
      slider: true,
      onIncrease: onSemanticIncrease,
      onDecrease: onSemanticDecrease,
      child: Focus(
        onKeyEvent: onKeyEvent,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                Focus.of(context).requestFocus();
                onChanged(d.localPosition, size);
              },
              onPanStart: (d) {
                // A flick that crosses touch slop inside the tap deadline
                // never fires `onTapDown`, so focus is taken here too —
                // otherwise a drag begun while the hex field holds focus
                // leaves that field mirroring a colour that has moved on.
                Focus.of(context).requestFocus();
                onChanged(d.localPosition, size);
              },
              onPanUpdate: (d) => onChanged(d.localPosition, size),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  size: size,
                  painter: _SquarePainter(
                    hue: hue,
                    saturation: saturation,
                    value: value,
                    thumbBorder: colorScheme.onSurface,
                    focusRing: focused ? colorScheme.primary : null,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The hue (angle) / saturation (radius) disc for one brightness.
///
/// Sized from the shared geometry box's short side and centred in it, so the
/// two modes occupy the same rectangle.
class _HueSaturationWheel extends StatelessWidget {
  final double diameter;
  final double hue;
  final double saturation;
  final double value;
  final String semanticLabel;
  final String semanticValue;
  final String semanticIncreasedValue;
  final String semanticDecreasedValue;
  final void Function(Offset local, double diameter) onChanged;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onSemanticIncrease;
  final VoidCallback onSemanticDecrease;

  const _HueSaturationWheel({
    required this.diameter,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.semanticLabel,
    required this.semanticValue,
    required this.semanticIncreasedValue,
    required this.semanticDecreasedValue,
    required this.onChanged,
    required this.onKeyEvent,
    required this.onSemanticIncrease,
    required this.onSemanticDecrease,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: semanticLabel,
      value: semanticValue,
      increasedValue: semanticIncreasedValue,
      decreasedValue: semanticDecreasedValue,
      slider: true,
      onIncrease: onSemanticIncrease,
      onDecrease: onSemanticDecrease,
      child: Focus(
        onKeyEvent: onKeyEvent,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                Focus.of(context).requestFocus();
                onChanged(d.localPosition, diameter);
              },
              onPanStart: (d) {
                Focus.of(context).requestFocus();
                onChanged(d.localPosition, diameter);
              },
              onPanUpdate: (d) => onChanged(d.localPosition, diameter),
              child: CustomPaint(
                size: Size.square(diameter),
                painter: _WheelPainter(
                  hue: hue,
                  saturation: saturation,
                  value: value,
                  thumbBorder: colorScheme.onSurface,
                  focusRing: focused ? colorScheme.primary : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SquarePainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;
  final Color thumbBorder;
  final Color? focusRing;

  const _SquarePainter({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.thumbBorder,
    required this.focusRing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // White → the pure hue across, then transparent → black down. Two stock
    // gradients; the composite is the standard HSV plane.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    if (focusRing != null) {
      canvas.drawRect(
        rect.deflate(1),
        Paint()
          ..color = focusRing!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // The thumb is a ring, not a disc: filling it would hide the very colour
    // it is pointing at.
    final thumb = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      thumb,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      thumb,
      10.5,
      Paint()
        ..color = thumbBorder.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_SquarePainter old) {
    return old.hue != hue ||
        old.saturation != saturation ||
        old.value != value ||
        old.thumbBorder != thumbBorder ||
        old.focusRing != focusRing;
  }
}

/// Paints the disc: hue around, saturation out from the centre, darkened by
/// the current brightness so it previews the colour the slider will produce.
class _WheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;
  final Color thumbBorder;
  final Color? focusRing;

  const _WheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.thumbBorder,
    required this.focusRing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var degrees = 0; degrees <= 360; degrees += 60)
              HSVColor.fromAHSV(1, (degrees % 360).toDouble(), 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    // Saturation falls off toward the centre: opaque white in the middle,
    // transparent at the rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    if (value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - value),
      );
    }

    if (focusRing != null) {
      canvas.drawCircle(
        center,
        radius - 1,
        Paint()
          ..color = focusRing!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // The same ring thumb the square uses, not the old wheel's filled white
    // dot — a filled thumb hides the very colour it points at, and the two
    // geometries should not disagree about what "the current colour" looks
    // like.
    final angle = hue * math.pi / 180;
    final thumb =
        center +
        Offset(math.cos(angle), math.sin(angle)) * (saturation * radius);
    canvas.drawCircle(
      thumb,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      thumb,
      10.5,
      Paint()
        ..color = thumbBorder.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) {
    return old.hue != hue ||
        old.saturation != saturation ||
        old.value != value ||
        old.thumbBorder != thumbBorder ||
        old.focusRing != focusRing;
  }
}

/// One axis as a real Material [Slider] over a gradient track — which is what
/// buys keyboard arrows, focus and slider semantics for free rather than
/// re-implementing them on a painted strip.
///
/// Both modes render this with identical metrics, so the row's height is the
/// same either side of a geometry switch: only its track, thumb tint and
/// label differ.
class _GradientSlider extends StatelessWidget {
  final double value;
  final double max;
  final String label;
  final List<Color> trackColors;
  final Color thumbColor;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.value,
    required this.max,
    required this.label,
    required this.trackColors,
    required this.thumbColor,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 20,
        trackShape: _GradientTrackShape(trackColors),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 11,
          elevation: 2,
        ),
        thumbColor: thumbColor,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
      ),
      child: Semantics(
        label: label,
        child: Slider(
          value: value,
          max: max,
          onChanged: onChanged,
          semanticFormatterCallback: formatValue,
          // On the widget, not through the theme: `Slider` resolves
          // `widget.thumbColor ?? widget.activeColor ?? theme.thumbColor`, so
          // passing an `activeColor` here would shadow the tint and leave the
          // thumb painted in the app accent over a spectrum track. The track
          // shape ignores active/inactive colours anyway.
          thumbColor: thumbColor,
        ),
      ),
    );
  }
}

/// Paints a gradient as the slider's track, ignoring the active/inactive
/// split — every position on these tracks is equally "on".
class _GradientTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final List<Color> colors;

  const _GradientTrackShape(this.colors);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final radius = Radius.circular(rect.height / 2);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }
}

/// A colour sample big enough to judge, with a 44px touch target around it.
class _PreviewDot extends StatelessWidget {
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _PreviewDot({required this.color, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
