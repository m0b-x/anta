import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import 'form_rows.dart';

/// Date picker for jumping the calendar somewhere else.
///
/// Three scroll wheels — day, month and year — that move up/down
/// independently, so a flick crosses days, months or decades without leaving
/// the screen. Opened from the calendar header's "August 2026" title. The day
/// wheel is bounded by the length of the shown month (leap-aware), and the
/// day clamps when the month or year changes under it. A "Type the date"
/// switch swaps the wheels for a text field when the target date is already
/// known.
class MonthYearPickerSheet extends StatefulWidget {
  /// Date the wheels open on.
  final DateTime initialDate;

  /// Inclusive bounds; only the year/month parts are honoured.
  final DateTime firstDate;
  final DateTime lastDate;

  /// Calendar accent, passed down from the page like every other calendar
  /// surface so the selected row matches the grid.
  final Color accent;

  const MonthYearPickerSheet({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.accent,
  });

  /// Returns the chosen date (date-only UTC), or null when dismissed.
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required Color accent,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<DateTime>(
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
        child: MonthYearPickerSheet(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          accent: accent,
        ),
      ),
    );
  }

  @override
  State<MonthYearPickerSheet> createState() => _MonthYearPickerSheetState();
}

class _MonthYearPickerSheetState extends State<MonthYearPickerSheet> {
  static const double _itemExtent = 44;

  /// Rows a wheel shows — the selected one and two either side — and so the
  /// height of the box both modes share.
  static const int _wheelRows = 5;

  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _yearController;
  late final TextEditingController _textController;
  late final FocusNode _textFocus;

  late int _day;
  late int _month;
  late int _year;
  bool _typing = false;
  String? _error;

  /// The body's scroll position feeds the header's hairline (a sub-sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the wheels.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  int get _firstYear => widget.firstDate.year;
  int get _lastYear => widget.lastDate.year;

  /// Days in the shown month — `day 0` of the next month is the last day of
  /// this one, so this is leap-aware and needs no special-casing for
  /// February or the 30/31 split.
  static int _daysInMonth(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year.clamp(_firstYear, _lastYear);
    _month = widget.initialDate.month;
    _day = widget.initialDate.day.clamp(1, _daysInMonth(_year, _month));
    _dayController = FixedExtentScrollController(initialItem: _day - 1);
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
    _yearController = FixedExtentScrollController(
      initialItem: _year - _firstYear,
    );
    _textController = TextEditingController();
    _textFocus = FocusNode();
    _bodyScroll.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  /// After the month or year moves, pull the day back inside the new month
  /// (Jan 31 → switch to Feb → 28/29) and realign the day wheel to it. The
  /// wheel's child count shrinks in the same build, so the controller can be
  /// momentarily past the end; the post-frame jump settles it.
  void _clampDayToMonth() {
    final maxDay = _daysInMonth(_year, _month);
    if (_day <= maxDay) return;
    _day = maxDay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dayController.hasClients) _dayController.jumpToItem(_day - 1);
    });
  }

  /// Month names come from `intl`, not an ARB matrix, sentence-cased because
  /// locales like Romanian spell them lowercase mid-sentence.
  String _monthName(int month, String localeName) {
    final name = DateFormat.MMMM(localeName).format(DateTime.utc(2024, month));
    return toBeginningOfSentenceCase(name, localeName) ?? name;
  }

  /// Months outside the bounds in the edge years cannot be confirmed. The
  /// wheel still scrolls through them — a wheel that fights the finger feels
  /// broken — so they are only dimmed, and confirming clamps.
  bool _isMonthAllowed(int month) {
    if (_year == _firstYear && month < widget.firstDate.month) return false;
    if (_year == _lastYear && month > widget.lastDate.month) return false;
    return true;
  }

  /// Keeps the returned date inside the caller's bounds. The wheels already
  /// keep day/month valid within a year, but the edge years can still be
  /// partially out of range.
  DateTime _bounded(int year, int month, int day) {
    final date = DateTime.utc(year, month, day);
    if (date.isBefore(widget.firstDate)) return widget.firstDate;
    if (date.isAfter(widget.lastDate)) return widget.lastDate;
    return date;
  }

  void _confirm(AppLocalizations l10n) {
    if (_typing) {
      _submitTyped(l10n);
      return;
    }
    Navigator.of(context).pop(_bounded(_year, _month, _day));
  }

  /// Moves the three wheels to the current [_day]/[_month]/[_year]. Needed
  /// whenever the wheels re-enter the tree (leaving typed mode re-attaches
  /// their controllers at `initialItem`, not at the last scrolled values) and
  /// after programmatic state changes like the Today button.
  void _alignWheelsToState({required bool animate}) {
    void move(FixedExtentScrollController controller, int item) {
      if (!controller.hasClients) return;
      if (animate) {
        controller.animateToItem(
          item,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        controller.jumpToItem(item);
      }
    }

    move(_dayController, _day - 1);
    move(_monthController, _month - 1);
    move(_yearController, _year - _firstYear);
  }

  void _goToCurrent() {
    final now = DateTime.now();
    final wasTyping = _typing;
    setState(() {
      _typing = false;
      _error = null;
      _year = now.year.clamp(_firstYear, _lastYear);
      _month = now.month;
      _day = now.day;
    });
    if (wasTyping) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _alignWheelsToState(animate: false);
      });
    } else {
      _alignWheelsToState(animate: true);
    }
  }

  void _toggleTyping() {
    if (_typing) {
      setState(() {
        _typing = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _alignWheelsToState(animate: false);
      });
      return;
    }
    _textController.text =
        '${_day.toString().padLeft(2, '0')}/'
        '${_month.toString().padLeft(2, '0')}/$_year';
    _textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _textController.text.length,
    );
    setState(() {
      _typing = true;
      _error = null;
    });
    _textFocus.requestFocus();
  }

  void _submitTyped(AppLocalizations l10n) {
    final parsed = _parse(_textController.text, l10n.localeName);
    if (parsed == null) {
      setState(() => _error = l10n.monthYearPickerInvalid);
      return;
    }
    if (parsed.year < _firstYear || parsed.year > _lastYear) {
      setState(
        () => _error = l10n.monthYearPickerRange('$_firstYear', '$_lastYear'),
      );
      return;
    }
    Navigator.of(context).pop(_bounded(parsed.year, parsed.month, parsed.day));
  }

  /// Forgiving parse of a typed date. Deliberately loose about separators and
  /// order, because the one thing worse than no typed mode is one that
  /// rejects what the user obviously meant. The canonical form is `dd/mm/yyyy`
  /// (what the hint shows), but these all work too:
  ///
  /// - `15/08/2026`, `15.8.2026`, `2026-08-15` → 15 Aug 2026 (a 4-digit year
  ///   on either end fixes d/m/Y vs Y/m/d; the month is the middle number).
  /// - `08/2026`, `2026-08`, `august 2026` → Aug 2026, day kept from the wheel.
  /// - `15 august 2026`, `15 aug` → the 15th (named month; any bare number
  ///   ≤ 31 that is not the year is the day).
  /// - a bare `2026` keeps the current month and day, a bare number that can
  ///   only be a day (`>12`) sets the day, a bare `≤12` sets the month.
  ///
  /// Day defaults to the wheel's current day (clamped to the resolved month);
  /// an impossible day like `31/02` clamps to the month's length. Returns null
  /// when nothing sensible can be read; the year range is checked by the
  /// caller so it can name the bounds that were missed.
  ({int day, int month, int year})? _parse(String raw, String localeName) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;

    int? namedMonth;
    for (var m = 1; m <= 12; m++) {
      final anchor = DateTime.utc(2024, m);
      final full = DateFormat.MMMM(localeName).format(anchor).toLowerCase();
      final abbrev = DateFormat.MMM(
        localeName,
      ).format(anchor).toLowerCase().replaceAll('.', '');
      if (text.contains(full) ||
          (abbrev.length >= 3 && text.contains(abbrev))) {
        namedMonth = m;
        break;
      }
    }

    final numbers = RegExp(
      r'\d+',
    ).allMatches(text).map((m) => m.group(0)!).toList();

    int? month;
    int? year;
    int? day;

    if (namedMonth != null) {
      month = namedMonth;
      final fourDigit = numbers.where((n) => n.length == 4).firstOrNull;
      year = fourDigit != null ? int.parse(fourDigit) : _year;
      // Any other number next to a named month is the day of the month.
      final dayText = numbers.where((n) => n != fourDigit).firstOrNull;
      if (dayText != null) day = int.parse(dayText);
    } else if (numbers.length >= 3) {
      // d/m/Y or Y-m-d — either way the month is the middle number.
      month = int.parse(numbers[1]);
      if (numbers.first.length == 4) {
        year = int.parse(numbers.first);
        day = int.parse(numbers.last);
      } else {
        day = int.parse(numbers.first);
        year = numbers.last.length == 4
            ? int.parse(numbers.last)
            : _expandYear(int.parse(numbers.last));
      }
    } else if (numbers.length == 2) {
      final a = numbers[0];
      final b = numbers[1];
      if (a.length == 4) {
        year = int.parse(a);
        month = int.parse(b);
      } else {
        month = int.parse(a);
        year = b.length == 4 ? int.parse(b) : _expandYear(int.parse(b));
      }
    } else if (numbers.length == 1) {
      final value = int.parse(numbers.first);
      if (numbers.first.length == 4) {
        year = value;
        month = _month;
      } else if (value > 12) {
        // Can only be a day.
        day = value;
        month = _month;
        year = _year;
      } else {
        month = value;
        year = _year;
      }
    }

    if (month == null || year == null) return null;
    if (month < 1 || month > 12) return null;
    final maxDay = _daysInMonth(year, month);
    final resolvedDay = (day ?? _day).clamp(1, maxDay);
    return (day: resolvedDay, month: month, year: year);
  }

  /// Turns a two-digit year into a full one, pivoting on the current year
  /// like a date-of-birth field: up to ten years ahead reads as 20xx
  /// (`8/26` → August 2026), anything further reads as 19xx (`5/91` →
  /// May 1991 — a birth year, not 2091). Pivoting beats "nearest the
  /// range" because the range now spans two centuries. Four-digit years
  /// are never touched.
  int _expandYear(int value) {
    if (value >= 100) return value;
    final candidate = 2000 + value;
    return candidate <= DateTime.now().year + 10 ? candidate : 1900 + value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // The keyboard in typed mode and the system bar sit on the same edge;
    // the larger inset rides the scroll view's padding, read here from the
    // sheet's own context — only that one rebuilds when the keyboard opens.
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.monthYearClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.monthYearPickerTitle,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.apply,
            identifier: SemanticsIds.monthYearApply,
            onPressed: () => _confirm(l10n),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Both modes are the same height — the typed entry sits in
                // the wheels' box — so the swap moves nothing under the
                // header. `AnimatedSize` stays as the safety net that would
                // ease rather than snap should a locale's error caption ever
                // outgrow the box at a large scale.
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _typing
                      ? _buildTypedEntry(l10n)
                      : _buildWheels(l10n, theme),
                ),
                const SizedBox(height: RowMetrics.groupGap),
                FormRowGroup(
                  trailingGap: false,
                  children: [
                    FormActionRow(
                      glyph: Icons.today_rounded,
                      label: l10n.datePickerToday,
                      identifier: SemanticsIds.monthYearToday,
                      onTap: _goToCurrent,
                    ),
                    // A switch names the mode; a toggle whose label flips
                    // under the finger does not.
                    FormSwitchRow(
                      glyph: Icons.keyboard_rounded,
                      label: l10n.monthYearPickerTypedEntry,
                      value: _typing,
                      identifier: SemanticsIds.monthYearTyped,
                      onChanged: (_) => _toggleTyping(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWheels(AppLocalizations l10n, ThemeData theme) {
    final yearCount = _lastYear - _firstYear + 1;
    final dayCount = _daysInMonth(_year, _month);
    return SizedBox(
      height: _itemExtent * _wheelRows,
      child: Stack(
        children: [
          // A single quiet band marks the committed row. No box around the
          // wheels, no accent flood — just enough to say "this line is the
          // selection".
          Center(
            child: IgnorePointer(
              child: Container(
                height: _itemExtent,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
              ),
            ),
          ),
          // Fading the rows toward the top and bottom edges is what makes a
          // wheel read as a wheel rather than a clipped list.
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.3, 0.7, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: Row(
              children: [
                // Day | month | year, matching the dd/mm/yyyy the typed field
                // expects, so the two modes read the same way round.
                Expanded(
                  flex: 2,
                  child: _wheel(
                    controller: _dayController,
                    itemCount: dayCount,
                    onChanged: (index) => setState(() => _day = index + 1),
                    builder: (index) => _WheelLabel(
                      text: '${index + 1}',
                      selected: index + 1 == _day,
                      disabled: false,
                      accent: widget.accent,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _wheel(
                    controller: _monthController,
                    itemCount: 12,
                    onChanged: (index) => setState(() {
                      _month = index + 1;
                      _clampDayToMonth();
                    }),
                    builder: (index) => _WheelLabel(
                      text: _monthName(index + 1, l10n.localeName),
                      selected: index + 1 == _month,
                      disabled: !_isMonthAllowed(index + 1),
                      accent: widget.accent,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _wheel(
                    controller: _yearController,
                    itemCount: yearCount,
                    onChanged: (index) => setState(() {
                      _year = _firstYear + index;
                      _clampDayToMonth();
                    }),
                    builder: (index) => _WheelLabel(
                      text: '${_firstYear + index}',
                      selected: _firstYear + index == _year,
                      disabled: false,
                      accent: widget.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required ValueChanged<int> onChanged,
    required Widget Function(int index) builder,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: _itemExtent,
      diameterRatio: 1.9,
      perspective: 0.0022,
      overAndUnderCenterOpacity: 0.55,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) => builder(index),
      ),
    );
  }

  /// The typed field in the wheels' own box, aligned at its top: the two
  /// modes are then one height, so switching never resizes the sheet or
  /// moves the header — the language's "size the dependent area with an
  /// invisible template". The field with its two-line error caption stays
  /// under the box even at 200 % on a 360 dp phone (the German case pins it).
  Widget _buildTypedEntry(AppLocalizations l10n) {
    return SizedBox(
      height: _itemExtent * _wheelRows,
      child: Align(
        alignment: Alignment.topCenter,
        child: TextField(
          controller: _textController,
          focusNode: _textFocus,
          autofocus: true,
          keyboardType: TextInputType.datetime,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(24)],
          decoration: InputDecoration(
            labelText: l10n.monthYearPickerFieldLabel,
            hintText: l10n.monthYearPickerFieldHint,
            errorText: _error,
            prefixIcon: const Icon(Icons.edit_calendar_rounded),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submitTyped(l10n),
        ),
      ),
    );
  }
}

class _WheelLabel extends StatelessWidget {
  final String text;
  final bool selected;
  final bool disabled;
  final Color accent;

  const _WheelLabel({
    required this.text,
    required this.selected,
    required this.disabled,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
        : selected
        ? accent
        : theme.colorScheme.onSurfaceVariant;
    final style =
        (selected ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge)
            ?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        // A long month name scales down to its column rather than being cut
        // — the bold selected "September" read "Septem…" at 200 %. At 1×
        // every name fits and the box changes nothing, so the unselected
        // rows look as they did.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, maxLines: 1, style: style),
        ),
      ),
    );
  }
}
