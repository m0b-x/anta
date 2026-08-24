import 'dart:async';

import 'package:flutter/material.dart';

/// A settings-row slider that keeps every drag tick **local** so a fast drag
/// does not fire a haptic, an awaited settings write and a whole-page
/// `setState` (the caption's search-highlighted description, the live
/// appearance preview, the ~40-row non-lazy settings list) on every pixel of
/// movement — only once, when the drag ends.
///
/// [onCommit] fires exactly once per drag: from the platform's
/// `onChangeEnd` when it arrives, or — as a fallback, because
/// accessibility-driven changes do not always call `onChangeEnd` — from a
/// short debounce timer restarted on every tick. Whichever fires first wins;
/// the local draft is what makes that safe, since it doubles as "is a commit
/// still owed for this drag".
///
/// While a drag is in progress the caption cannot use the pre-rendered,
/// search-highlighted [description] widget (it was built from the old value
/// and would freeze mid-drag) — it renders [draftCaption] as plain text
/// instead, styled with [captionStyle] so it is visually identical to the
/// real caption. Search highlighting returns the instant the drag commits.
class SliderSettingRow extends StatefulWidget {
  final Widget title;
  final Widget? description;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String Function(int draft) draftCaption;
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

  @override
  void didUpdateWidget(covariant SliderSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _draft != null) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      setState(() => _draft = null);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
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
    final caption = draft == null
        ? widget.description
        : Text(widget.draftCaption(draft), style: widget.captionStyle);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.title,
          const SizedBox(height: 4),
          ?caption,
          Slider(
            value: displayValue.toDouble(),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.divisions,
            label: '$displayValue',
            onChanged: _handleChanged,
            onChangeEnd: _handleChangeEnd,
          ),
        ],
      ),
    );
  }
}
