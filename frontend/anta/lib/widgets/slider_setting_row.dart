import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/row_metrics.dart';
import 'form_rows.dart';
import 'settings_section_list.dart' show settingsCaptionStyle;

/// A settings-row slider that keeps every drag tick **local** so a fast drag
/// does not fire a haptic, an awaited settings write and a whole-page
/// `setState` (the caption's search-highlighted description, the live
/// appearance preview, the ~40-row non-lazy settings list) on every pixel of
/// movement — only once, when the drag ends.
///
/// [onCommit] fires exactly once per drag: from the platform's
/// `onChangeEnd` when it arrives, or — as a fallback, because
/// accessibility-driven changes do not always call `onChangeEnd` — from a
/// short debounce timer restarted on every tick, or from `dispose` when the
/// row leaves before either has fired. Whichever fires first wins;
/// the local draft is what makes that safe, since it doubles as "is a commit
/// still owed for this drag".
///
/// While a drag is in progress the caption cannot use the pre-rendered,
/// search-highlighted [description] widget (it was built from the old value
/// and would freeze mid-drag) — it renders [draftCaption] as plain text
/// instead, in the kit's caption role so it is visually identical to the
/// real caption. Search highlighting returns the instant the drag commits.
/// The caption's slot is as tall as the tallest caption it may show, so a
/// reading that takes another line never moves the slider under the finger.
class SliderSettingRow extends StatefulWidget {
  final Widget title;
  final Widget? description;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String Function(int draft) draftCaption;

  /// Only its colour is read: the draft is drawn in the kit's caption role,
  /// the size and line its descriptions have, so the row keeps its height.
  final TextStyle captionStyle;
  final ValueChanged<int> onCommit;

  const SliderSettingRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.draftCaption,
    required this.captionStyle,
    required this.onCommit,
  });

  @override
  State<SliderSettingRow> createState() => _SliderSettingRowState();
}

class _SliderSettingRowState extends State<SliderSettingRow> {
  static const _debounceFallback = Duration(milliseconds: 350);

  /// Non-null exactly while a commit is still owed for the current drag —
  /// set on the first tick, cleared the moment either commit path fires.
  /// `didUpdateWidget` also clears it when the committed value changes from
  /// outside (the reset-to-defaults path), so the slider snaps back to the
  /// new prop instead of keeping a now-stale draft.
  int? _draft;
  Timer? _debounceTimer;

  /// The route the row is drawn in, read while it is still in the tree:
  /// `dispose` has no context to ask.
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant SliderSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _draft != null) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      setState(() => _draft = null);
    }
  }

  /// A draft still owed a commit is committed, never dropped: a keyboard or
  /// TalkBack change made within the debounce of leaving the page was lost
  /// with the timer. Leaving with the page, the page is already out of the
  /// tree and takes the commit now; leaving alone — a fold, a search that
  /// filtered the row out — the page is mid-frame and still mounted, and
  /// takes it once the frame is done, if its route and the page in it are
  /// still there. This row's own State is gone by then, so the page's
  /// subtree is what is asked: a page torn down in that frame cannot take a
  /// `setState`.
  @override
  void dispose() {
    _debounceTimer?.cancel();
    final draft = _draft;
    if (draft != null) {
      final commit = widget.onCommit;
      final route = _route;
      if (route != null && route.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route.isActive && (route.subtreeContext?.mounted ?? false)) {
            commit(draft);
          }
        });
      } else {
        commit(draft);
      }
    }
    super.dispose();
  }

  /// The step whose reading is tallest, and the range, locale, style and
  /// width it was measured for: the readings are built and laid out again
  /// only when one of them changes, never on a drag tick — each reading is a
  /// [SliderSettingRow.draftCaption] call, a plural lookup in the real rows.
  ({
    int min,
    int max,
    int divisions,
    Locale? locale,
    TextStyle style,
    TextScaler scaler,
    double width,
  })?
  _measuredFor;
  int? _tallestStep;

  /// The values the caption's slot is sized from. Every step's reading, when
  /// there are at most [RowMetrics.sliderReadingTemplatesMax] of them — the
  /// longest may fall anywhere in the range (the notice's "1410 minutes
  /// before" against its "24 hours before") — as the tallest of them laid
  /// out at [width]; past that bound, the two ends.
  List<int> _templateValues(
    BuildContext context,
    TextStyle style,
    double width,
  ) {
    final steps = widget.divisions + 1;
    if (widget.divisions <= 0 ||
        steps > RowMetrics.sliderReadingTemplatesMax ||
        !width.isFinite) {
      return [widget.min, widget.max];
    }
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final measured = _measuredFor;
    if (measured == null ||
        measured.min != widget.min ||
        measured.max != widget.max ||
        measured.divisions != widget.divisions ||
        measured.locale != locale ||
        measured.style != effective ||
        measured.scaler != scaler ||
        measured.width != width) {
      final span = widget.max - widget.min;
      final values = [
        for (var i = 0; i < steps; i++)
          widget.min + (span * i / widget.divisions).round(),
      ];
      final readings = [for (final value in values) widget.draftCaption(value)];
      final direction = Directionality.of(context);
      var tallest = 0;
      var tallestHeight = -1.0;
      for (var i = 0; i < readings.length; i++) {
        final painter = TextPainter(
          text: TextSpan(text: readings[i], style: effective),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
        )..layout(maxWidth: width);
        if (painter.height > tallestHeight) {
          tallestHeight = painter.height;
          tallest = i;
        }
        painter.dispose();
      }
      _measuredFor = (
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        locale: locale,
        style: effective,
        scaler: scaler,
        width: width,
      );
      _tallestStep = values[tallest];
    }
    return [
      ...{widget.min, widget.max, ?_tallestStep},
    ];
  }

  void _handleChanged(double value) {
    final rounded = value.round();
    setState(() => _draft = rounded);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceFallback, () => _commit(rounded));
  }

  void _handleChangeEnd(double value) => _commit(value.round());

  /// Guarded by [_draft]: once a commit has fired for this drag (timer or
  /// `onChangeEnd`, whichever came first) `_draft` is cleared, so the other
  /// path — arriving late — is a no-op instead of a double commit.
  void _commit(int value) {
    if (_draft == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    setState(() => _draft = null);
    widget.onCommit(value);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final displayValue = draft ?? widget.value;
    final draftStyle = settingsCaptionStyle.copyWith(
      color:
          widget.captionStyle.color ??
          Theme.of(context).colorScheme.onSurfaceVariant,
    );
    Text reading(int value) =>
        Text(widget.draftCaption(value), style: draftStyle);
    final description = widget.description;
    final caption = draft == null ? description : reading(draft);

    // One node to a screen reader: the title, and the caption's sentence as
    // its value — the number with its unit, where the slider alone says a
    // percentage. The caption and the bubble say that number again, so the
    // caption never joins the node and the bubble's number only while a drag
    // shows the bubble.
    return MergeSemantics(
      child: Padding(
        padding: FormMetrics.settingsControlRowPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            widget.title,
            ExcludeSemantics(
              // The tallest reading is the idle caption or the tallest step's
              // — and what is shown sizes the slot too, so it is never a
              // template as well.
              child: LayoutBuilder(
                builder: (context, constraints) => FormCaptionSlot(
                  candidates: [
                    if (draft != null) ?description,
                    for (final value in _templateValues(
                      context,
                      draftStyle,
                      constraints.maxWidth,
                    ))
                      reading(value),
                  ],
                  child: caption ?? const SizedBox.shrink(),
                ),
              ),
            ),
            Slider(
              value: displayValue.toDouble(),
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.divisions,
              label: draft == null ? null : '$draft',
              semanticFormatterCallback: (value) =>
                  widget.draftCaption(value.round()),
              onChanged: _handleChanged,
              onChangeEnd: _handleChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}
