import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_spacing.dart';
import '../constants/app_icon_sizes.dart';
import '../constants/font_constants.dart';
import '../constants/note_search_metrics.dart';
import '../l10n/app_localizations.dart';
import '../utils/re_editor_search_controller.dart';

/// Bottom sheet listing every search match as line number + source snippet,
/// so an arbitrary match is one sighted tap away instead of N chevron taps.
///
/// Pops the picked match index, or null when dismissed.
class NoteMatchListSheet extends StatefulWidget {
  final ReEditorSearchController searchController;
  final bool hapticsEnabled;

  /// Opens with the number field focused — the long-press accelerator for
  /// "take me to the 15th" rather than "let me look through them".
  final bool focusJumpField;

  const NoteMatchListSheet({
    super.key,
    required this.searchController,
    required this.hapticsEnabled,
    this.focusJumpField = false,
  });

  static Future<int?> show(
    BuildContext context, {
    required ReEditorSearchController searchController,
    required bool hapticsEnabled,
    bool focusJumpField = false,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NoteSearchMetrics.sheetRadius),
        ),
      ),
      builder: (context) => NoteMatchListSheet(
        searchController: searchController,
        hapticsEnabled: hapticsEnabled,
        focusJumpField: focusJumpField,
      ),
    );
  }

  @override
  State<NoteMatchListSheet> createState() => _NoteMatchListSheetState();
}

class _NoteMatchListSheetState extends State<NoteMatchListSheet> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _jumpController = TextEditingController();
  final FocusNode _jumpFocus = FocusNode();
  bool _centered = false;

  /// Row the typed number points at. Typing only previews — "15" passes
  /// through "1", and jumping live would fling the note twice for one intent.
  int? _candidateIndex;
  bool _jumpOutOfRange = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _jumpController.dispose();
    _jumpFocus.dispose();
    super.dispose();
  }

  /// Centers the current match once the list has a viewport to measure.
  void _centerOnCurrent(double rowExtent) {
    if (_centered || !_scrollController.hasClients) return;
    _centered = true;
    final index = widget.searchController.currentMatchIndex;
    if (index <= 0) return;
    _scrollToIndex(index, rowExtent);
  }

  void _scrollToIndex(int index, double rowExtent) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target =
        index * rowExtent - position.viewportDimension / 2 + rowExtent / 2;
    _scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _onJumpChanged(String value, double rowExtent) {
    final count = widget.searchController.matchCount;
    final typed = int.tryParse(value);
    if (typed == null) {
      setState(() {
        _candidateIndex = null;
        _jumpOutOfRange = false;
      });
      return;
    }
    final inRange = typed >= 1 && typed <= count;
    setState(() {
      _candidateIndex = inRange ? typed - 1 : null;
      _jumpOutOfRange = !inRange;
    });
    if (inRange) _scrollToIndex(typed - 1, rowExtent);
  }

  /// Submit clamps rather than rewriting as you type: the valid range has been
  /// on screen the whole time, so a clamp reads as a correction.
  void _submitJump() {
    final count = widget.searchController.matchCount;
    final typed = int.tryParse(_jumpController.text);
    if (typed == null || count == 0) return;
    final clamped = typed.clamp(1, count);
    if (clamped != typed && widget.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
    _select(clamped - 1);
  }

  void _select(int index) {
    if (widget.hapticsEnabled) HapticFeedback.selectionClick();
    Navigator.pop(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final rowExtent = media.textScaler.scale(NoteSearchMetrics.matchRowExtent);
    // The search field keeps focus while the sheet is up, so the keyboard is
    // still on screen: sit above it instead of behind it.
    final keyboardInset = media.viewInsets.bottom;
    final available = media.size.height - keyboardInset;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: available * NoteSearchMetrics.sheetHeightFactor,
        ),
        child: ListenableBuilder(
          listenable: widget.searchController,
          builder: (context, _) {
            final count = widget.searchController.matchCount;
            final currentIndex = widget.searchController.currentMatchIndex;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _centerOnCurrent(rowExtent);
            });

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Grabber(color: colors.outlineVariant),
                _Header(
                  title: l10n.matchesForQuery(widget.searchController.query),
                  count: l10n.matchCountLabel(count),
                  jumpField: count == 0
                      ? null
                      : _JumpToMatchField(
                          controller: _jumpController,
                          focusNode: _jumpFocus,
                          autofocus: widget.focusJumpField,
                          matchCount: count,
                          outOfRange: _jumpOutOfRange,
                          onChanged: (value) =>
                              _onJumpChanged(value, rowExtent),
                          onSubmitted: _submitJump,
                        ),
                ),
                Divider(height: 1, color: colors.outlineVariant),
                Flexible(
                  child: count == 0
                      ? _EmptyState(message: l10n.noSearchResults)
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: count,
                          itemExtent: rowExtent,
                          padding: EdgeInsets.only(
                            bottom: media.padding.bottom,
                          ),
                          itemBuilder: (context, index) {
                            final preview = widget.searchController.previewAt(
                              index,
                            );
                            if (preview == null) {
                              return const SizedBox.shrink();
                            }
                            return _MatchRow(
                              preview: preview,
                              isCurrent: index == currentIndex,
                              isCandidate: index == _candidateIndex,
                              lineLabel: l10n.matchAtLine(
                                preview.lineNumber + 1,
                              ),
                              onTap: () => _select(index),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  final Color color;

  const _Grabber({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Container(
        width: NoteSearchMetrics.grabberWidth,
        height: NoteSearchMetrics.grabberHeight,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(NoteSearchMetrics.grabberHeight),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String count;
  final Widget? jumpField;

  const _Header({required this.title, required this.count, this.jumpField});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: FontConstants.title,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: FontConstants.caption,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (jumpField != null) ...[
            const SizedBox(width: AppSpacing.sm),
            jumpField!,
          ],
        ],
      ),
    );
  }
}

/// Type a match number and go straight to it. Typing previews (the list
/// scrolls, the row outlines); only submit moves the note.
class _JumpToMatchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final int matchCount;
  final bool outOfRange;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  const _JumpToMatchField({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.matchCount,
    required this.outOfRange,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final digits = min(
      matchCount.toString().length,
      NoteSearchMetrics.maxJumpDigits,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: NoteSearchMetrics.jumpFieldWidth,
              height: NoteSearchMetrics.jumpFieldHeight,
              child: Semantics(
                label: l10n.goToMatchNumber,
                hint: l10n.enterMatchNumber(1, matchCount),
                textField: true,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(digits),
                  ],
                  style: TextStyle(
                    fontSize: FontConstants.body,
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.matchNumberHint,
                    hintStyle: TextStyle(
                      fontSize: FontConstants.caption,
                      color: colors.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: colors.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        NoteSearchMetrics.jumpFieldRadius,
                      ),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: onChanged,
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.matchNumberRange(1, matchCount),
              style: TextStyle(
                fontSize: FontConstants.tiny,
                color: outOfRange ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.xs),
        // Filled, not a bare IconButton: a wider hit area on a transparent
        // icon just adds dead space, it doesn't read as a bigger button.
        Tooltip(
          message: l10n.goToMatchNumber,
          child: Material(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(
              NoteSearchMetrics.jumpFieldRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onSubmitted,
              child: SizedBox(
                width: NoteSearchMetrics.jumpGoButtonWidth,
                height: NoteSearchMetrics.touchTarget,
                child: Center(
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: AppIconSizes.medium,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: AppSpacing.allXl,
      child: Text(
        message,
        style: TextStyle(
          fontSize: FontConstants.body,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  final SearchMatchPreview preview;
  final bool isCurrent;
  final bool isCandidate;
  final String lineLabel;
  final VoidCallback onTap;

  const _MatchRow({
    required this.preview,
    required this.isCurrent,
    required this.isCandidate,
    required this.lineLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: isCurrent,
      label: lineLabel,
      value: preview.snippet,
      child: Material(
        color: isCurrent ? colors.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: isCurrent
                ? BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: colors.primary,
                        width: NoteSearchMetrics.currentMarkerWidth,
                      ),
                    ),
                  )
                // What the typed number points at, before it is committed.
                : isCandidate
                ? BoxDecoration(
                    border: Border.all(
                      color: colors.primary,
                      width: NoteSearchMetrics.candidateBorderWidth,
                    ),
                  )
                : null,
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: NoteSearchMetrics.lineNumberWidth,
                  child: Text(
                    lineLabel,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: FontConstants.caption,
                      fontWeight: FontWeight.w500,
                      color: isCurrent
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _Snippet(preview: preview, isCurrent: isCurrent),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppIconSizes.small,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The match snippet with the hit itself bold and tinted — never colour alone.
class _Snippet extends StatelessWidget {
  final SearchMatchPreview preview;
  final bool isCurrent;

  const _Snippet({required this.preview, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseColor = isCurrent
        ? colors.onSecondaryContainer
        : colors.onSurface;
    final base = TextStyle(fontSize: FontConstants.body, color: baseColor);

    final snippet = preview.snippet;
    final start = min(preview.highlightStart, snippet.length);
    final end = min(max(preview.highlightEnd, start), snippet.length);
    final leading = preview.trimmedStart ? '…' : '';
    final trailing = preview.trimmedEnd ? '…' : '';

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: '$leading${snippet.substring(0, start)}'),
          TextSpan(
            text: snippet.substring(start, end),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.primary,
              backgroundColor: colors.primary.withValues(alpha: 0.12),
            ),
          ),
          TextSpan(text: '${snippet.substring(end)}$trailing'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
