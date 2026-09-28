import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../services/event_time_formatter.dart';
import '../services/settings_service.dart';
import '../utils/time_pad_entry.dart';
import 'automation_id.dart';
import 'form_rows.dart';

typedef TimePadCaption =
    String? Function(int minute, String Function(int minute) formatTime);

abstract final class TimePadCaptions {
  static TimePadCaption endsAfter(AppLocalizations l10n, int durationMinutes) {
    return (minute, formatTime) {
      final end = minute + durationMinutes;
      final time = formatTime(end);
      return [
        end >= EventTime.minutesPerDay
            ? l10n.timePadEndsNextDayAt(time)
            : l10n.timePadEndsAt(time),
        EventTimeFormatter.formatDuration(durationMinutes, l10n),
      ].join(' · ');
    };
  }

  static TimePadCaption afterStart(AppLocalizations l10n, int startMinute) {
    final start = startMinute % EventTime.minutesPerDay;
    return (minute, formatTime) {
      var length = minute - start;
      if (length <= 0) length += EventTime.minutesPerDay;
      return [
        l10n.timePadAfterStart(
          EventTimeFormatter.formatDuration(length, l10n),
          formatTime(start),
        ),
        if (start + length >= EventTime.minutesPerDay)
          l10n.eventCrossesMidnight,
      ].join(' · ');
    };
  }
}

class TimePadSheet extends StatefulWidget {
  final int initialMinute;
  final String title;
  final TimePadCaption? caption;
  final int? periodAfter;

  const TimePadSheet({
    super.key,
    required this.initialMinute,
    required this.title,
    this.caption,
    this.periodAfter,
  });

  static Future<int?> pick(
    BuildContext context, {
    required int initialMinute,
    required String title,
    TimePadCaption? caption,
    int? periodAfter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: TimePadSheet(
          initialMinute: initialMinute,
          title: title,
          caption: caption,
          periodAfter: periodAfter,
        ),
      ),
    );
  }

  @override
  State<TimePadSheet> createState() => _TimePadSheetState();
}

class _TimePadSheetState extends State<TimePadSheet> {
  static final Map<LogicalKeyboardKey, int> _digitKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  TimePadEntry? _entry;
  bool _haptics = false;
  bool _closed = false;

  /// The body's scroll position feeds the header's hairline (a sub-sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the pad.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
    _loadHaptics();
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entry ??= TimePadEntry.open(
      initialMinute: widget.initialMinute,
      use24h: _uses24h(context),
      periodAfter: widget.periodAfter,
    );
  }

  static bool _uses24h(BuildContext context) {
    final format = MaterialLocalizations.of(context).timeOfDayFormat(
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return hourFormat(of: format) != HourFormat.h;
  }

  Future<void> _loadHaptics() async {
    final settings = await SettingsService.getInstance();
    final enabled = await settings.getHapticFeedback();
    if (mounted) _haptics = enabled;
  }

  void _apply(
    TimePadEntry Function(TimePadEntry entry) step, {
    bool haptic = true,
  }) {
    final current = _entry!;
    final next = step(current);
    if (_closed || identical(next, current)) return;
    if (haptic && _haptics) HapticFeedback.lightImpact();
    setState(() => _entry = next);
    if (next.isComplete) {
      _closed = true;
      Navigator.of(context).pop(next.value);
    }
  }

  String _formatTime(int minute) {
    final wrapped = minute % EventTime.minutesPerDay;
    return TimeOfDay(hour: wrapped ~/ 60, minute: wrapped % 60).format(context);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final digit = _digitKeys[key];
    final TimePadEntry Function(TimePadEntry entry)? step;
    if (digit != null) {
      step = (entry) => entry.pressDigit(digit);
    } else if (key == LogicalKeyboardKey.backspace) {
      step = (entry) => entry.backspace();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      step = (entry) => entry.finish();
    } else if (event.character == ':' ||
        event.character == '.' ||
        key == LogicalKeyboardKey.numpadDecimal) {
      step = (entry) => entry.selectPart(TimePadPart.minute);
    } else if (key == LogicalKeyboardKey.keyA) {
      step = (entry) => entry.pressPeriod(TimePadPeriod.am);
    } else if (key == LogicalKeyboardKey.keyP) {
      step = (entry) => entry.pressPeriod(TimePadPeriod.pm);
    } else {
      step = null;
    }
    if (step == null) return KeyEventResult.ignored;
    _apply(step, haptic: false);
    return KeyEventResult.handled;
  }

  /// The caption band's height: [FormMetrics.timePadCaptionLines] lines of
  /// the caption's own style at the ambient text scale. Measured through a
  /// `TextPainter` rather than multiplied from a guessed line factor — the
  /// style's line box (`bodyMedium` draws 1.43 of its size) is what two
  /// lines actually occupy, and a band a pixel short clips the second
  /// line's descenders. Sized from the style alone, never from the caption's
  /// text, so the keypad below never moves as the digits change.
  double _captionBandHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    final line = painter.preferredLineHeight;
    painter.dispose();
    return line * FormMetrics.timePadCaptionLines;
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry!;
    final l10n = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = math.max(viewInsets, viewPadding);
    final keyHeight = (MediaQuery.sizeOf(context).height * 0.068).clamp(
      44.0,
      60.0,
    );
    final showsCaption = widget.caption != null || !entry.use24h;
    final caption = entry.awaitingPeriod
        ? l10n.timePadChoosePeriod(
            material.anteMeridiemAbbreviation,
            material.postMeridiemAbbreviation,
          )
        : widget.caption?.call(entry.previewValue, _formatTime);
    final captionStyle = theme.textTheme.bodyMedium!;
    final captionBandHeight = _captionBandHeight(context, captionStyle);

    return Focus(
      autofocus: true,
      // No semantics node of its own: a focusable node here merged the
      // header's title into itself, and the sheet read as one "Start time"
      // node with the title gone from the tree. The hardware keys still
      // arrive through `onKeyEvent`; focus semantics belong to a control a
      // screen reader can act on, and this root is not one.
      includeSemantics: false,
      onKeyEvent: _onKeyEvent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.timePadCancel,
            onLeading: () => Navigator.of(context).pop(),
            title: widget.title,
            scrolled: _headerScrolled,
            trailingInset: FormMetrics.headerActionInset,
            // The keys that complete an entry pop by themselves; Done serves
            // a partial one, so it waits on `canFinish`.
            trailing: FormHeaderTextButton(
              label: l10n.timePadDone,
              identifier: SemanticsIds.timePadDone,
              onPressed: entry.canFinish
                  ? () => _apply((entry) => entry.finish())
                  : null,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              controller: _bodyScroll,
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + bottomClearance,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildReadout(entry, material, theme),
                  if (showsCaption)
                    SizedBox(
                      height: captionBandHeight,
                      child: Center(
                        child: Semantics(
                          liveRegion: entry.awaitingPeriod,
                          child: Text(
                            caption ?? '',
                            maxLines: FormMetrics.timePadCaptionLines,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: captionStyle.copyWith(
                              color: entry.awaitingPeriod
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: entry.awaitingPeriod
                                  ? FontWeight.w600
                                  : null,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.4,
                    child: _buildKeypad(entry, l10n, material, keyHeight),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadout(
    TimePadEntry entry,
    MaterialLocalizations material,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    final digits = theme.textTheme.displayMedium?.copyWith(
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final hourActive =
        entry.active == TimePadPart.hour && !entry.awaitingPeriod;
    final minuteActive =
        entry.active == TimePadPart.minute && !entry.awaitingPeriod;
    return Row(
      children: [
        const SizedBox(width: 48),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: MediaQuery.withNoTextScaling(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TimePart(
                      identifier: SemanticsIds.timePadHour,
                      label: material.timePickerHourLabel,
                      text: entry.hourLabel,
                      pending: hourActive ? entry.pending : '',
                      active: hourActive,
                      style: digits,
                      onPressed: () =>
                          _apply((entry) => entry.selectPart(TimePadPart.hour)),
                    ),
                    ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          ':',
                          style: digits?.copyWith(color: scheme.onSurface),
                        ),
                      ),
                    ),
                    _TimePart(
                      identifier: SemanticsIds.timePadMinute,
                      label: material.timePickerMinuteLabel,
                      text: entry.minuteLabel,
                      pending: minuteActive ? entry.pending : '',
                      active: minuteActive,
                      style: digits,
                      onPressed: () => _apply(
                        (entry) => entry.selectPart(TimePadPart.minute),
                      ),
                    ),
                    if (!entry.use24h)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 10),
                        child: Text(
                          entry.period == TimePadPeriod.am
                              ? material.anteMeridiemAbbreviation
                              : material.postMeridiemAbbreviation,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(
                              alpha: entry.periodIsSuggestion ? 0.45 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AutomationId(
          identifier: SemanticsIds.timePadBackspace,
          child: IconButton(
            tooltip: material.deleteButtonTooltip,
            icon: const Icon(Icons.backspace_outlined),
            onPressed: entry.canBackspace
                ? () => _apply((entry) => entry.backspace())
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildKeypad(
    TimePadEntry entry,
    AppLocalizations l10n,
    MaterialLocalizations material,
    double keyHeight,
  ) {
    Widget digit(int value) => _PadKey(
      identifier: SemanticsIds.timePadDigit(value),
      label: '$value',
      height: keyHeight,
      tone: _KeyTone.digit,
      onPressed: entry.canPressDigit(value)
          ? () => _apply((entry) => entry.pressDigit(value))
          : null,
    );
    Widget shortcut(int minute, String identifier, String semanticsLabel) =>
        _PadKey(
          identifier: identifier,
          label: ':${minute.toString().padLeft(2, '0')}',
          semanticsLabel: semanticsLabel,
          height: keyHeight,
          tone: _KeyTone.shortcut,
          onPressed: entry.canPressShortcut
              ? () => _apply((entry) => entry.pressShortcut(minute))
              : null,
        );
    Widget period(TimePadPeriod value, String identifier, String label) =>
        _PadKey(
          identifier: identifier,
          label: label,
          height: keyHeight,
          tone: entry.period != value
              ? _KeyTone.period
              : (entry.periodIsSuggestion
                    ? _KeyTone.periodSuggested
                    : _KeyTone.periodChosen),
          onPressed: () => _apply((entry) => entry.pressPeriod(value)),
        );

    final rows = <List<Widget>>[
      [digit(1), digit(2), digit(3)],
      [digit(4), digit(5), digit(6)],
      [digit(7), digit(8), digit(9)],
      [
        shortcut(0, SemanticsIds.timePadOnTheHour, l10n.timePadOnTheHour),
        digit(0),
        shortcut(30, SemanticsIds.timePadHalfPast, l10n.timePadHalfPast),
      ],
      if (!entry.use24h)
        [
          period(
            TimePadPeriod.am,
            SemanticsIds.timePadAm,
            material.anteMeridiemAbbreviation,
          ),
          period(
            TimePadPeriod.pm,
            SemanticsIds.timePadPm,
            material.postMeridiemAbbreviation,
          ),
        ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, row) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
            child: Row(
              children: [
                for (final (column, key) in row.indexed) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(child: key),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TimePart extends StatelessWidget {
  final String identifier;
  final String label;
  final String text;
  final String pending;
  final bool active;
  final TextStyle? style;
  final VoidCallback onPressed;

  const _TimePart({
    required this.identifier,
    required this.label,
    required this.text,
    required this.pending,
    required this.active,
    required this.style,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = active ? scheme.onPrimaryContainer : scheme.onSurface;
    final typing = pending.isNotEmpty;
    final shown = typing ? pending : text;
    return AutomationId(
      identifier: identifier,
      child: Semantics(
        selected: active,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            fixedSize: const Size(100, 84),
            padding: EdgeInsets.zero,
            backgroundColor: active
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            foregroundColor: foreground,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: active ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Semantics(
            label: '$label, $shown',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  shown,
                  style: style?.copyWith(
                    color: active && !typing
                        ? foreground.withValues(alpha: 0.4)
                        : foreground,
                  ),
                ),
                if (typing)
                  Container(
                    width: 3,
                    height: 44,
                    margin: const EdgeInsetsDirectional.only(start: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _KeyTone { digit, shortcut, period, periodSuggested, periodChosen }

class _PadKey extends StatelessWidget {
  final String identifier;
  final String label;
  final String? semanticsLabel;
  final double height;
  final _KeyTone tone;
  final VoidCallback? onPressed;

  const _PadKey({
    required this.identifier,
    required this.label,
    required this.height,
    required this.tone,
    required this.onPressed,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      _KeyTone.shortcut => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _KeyTone.periodChosen => (scheme.primary, scheme.onPrimary),
      _ => (scheme.surfaceContainerHigh, scheme.onSurface),
    };
    final textStyle = switch (tone) {
      _KeyTone.digit => theme.textTheme.headlineMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      _KeyTone.shortcut => theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      _ => theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    };
    final text = Text(label);
    return AutomationId(
      identifier: identifier,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.45),
          disabledForegroundColor: foreground.withValues(alpha: 0.3),
          minimumSize: Size.fromHeight(height),
          padding: EdgeInsets.zero,
          textStyle: textStyle,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: tone == _KeyTone.periodSuggested
                ? BorderSide(color: scheme.primary, width: 2)
                : BorderSide.none,
          ),
        ),
        child: semanticsLabel == null
            ? text
            : Semantics(
                label: semanticsLabel,
                excludeSemantics: true,
                child: text,
              ),
      ),
    );
  }
}
