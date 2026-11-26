part of '../calendar_overview_page.dart';

/// The list's rows on [_ListLayout]'s slots, which it reads by their prefix
/// sums: the stock varied-extent sliver sums the extents from the first row
/// on every lookup, so a frame near the end of thirty thousand rows walked
/// them all (review 17); here a row's offset, the row at an offset and the
/// whole are lookups. The whole is exact before the last row is laid out —
/// an estimate from the rows built would put the scroll range, the
/// scrollbar and a jump's clamp thousands of pixels off (R9).
class _ExactExtentSliver extends SliverMultiBoxAdaptorWidget {
  final _ListLayout layout;

  const _ExactExtentSliver({required super.delegate, required this.layout});

  @override
  _RenderExactExtentSliver createRenderObject(BuildContext context) {
    return _RenderExactExtentSliver(
      childManager: context as SliverMultiBoxAdaptorElement,
      layout: layout,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderExactExtentSliver renderObject,
  ) {
    renderObject.listLayout = layout;
  }
}

class _RenderExactExtentSliver extends RenderSliverFixedExtentBoxAdaptor {
  _RenderExactExtentSliver({
    required super.childManager,
    required _ListLayout layout,
  }) : _layout = layout;

  _ListLayout _layout;
  set listLayout(_ListLayout value) {
    if (identical(value, _layout)) return;
    _layout = value;
    markNeedsLayout();
  }

  @override
  double? get itemExtent => null;

  @override
  ItemExtentBuilder get itemExtentBuilder => _slotOf;

  double? _slotOf(int index, SliverLayoutDimensions _) =>
      index < _layout.slots.length ? _layout.slots[index] : null;

  @override
  double indexToLayoutOffset(double itemExtent, int index) =>
      _layout.offsetOfSlot(index);

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _layout.slotReaching(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _layout.slotReaching(scrollOffset);

  @override
  double computeMaxScrollOffset(
    SliverConstraints constraints,
    double itemExtent,
  ) => _layout.extent;

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) => _layout.extent;
}

/// One template of every row kind, laid out offstage at the list's width so
/// [_RowExtents] holds the heights the rows really take — the invisible
/// template that sizes the nav's title, for rows. Built through the page's
/// own row builder, so a template is the row it stands for. A header kind is
/// templated by its widest — the widest label the kind can carry in this
/// locale, beside a three-digit count — once on one line and once wrapped,
/// and keeps one line when that one fits it (D, the fix pass).
class _RowExtentProbe extends StatefulWidget {
  final AgendaDayListRowBuilder Function(
    List<AgendaDayListRow> rows, {
    AgendaHeaderSlots? headers,
    bool? dayHeaderWithYear,
  })
  builderOf;
  final DateTime today;

  /// Whether the heights are wanted: read after the frame that laid the
  /// templates out, and reported through [onMeasured].
  final bool measure;
  final ValueChanged<_RowExtents> onMeasured;

  const _RowExtentProbe({
    required this.builderOf,
    required this.today,
    required this.measure,
    required this.onMeasured,
  });

  @override
  State<_RowExtentProbe> createState() => _RowExtentProbeState();
}

class _RowExtentProbeState extends State<_RowExtentProbe> {
  /// The count the header templates carry: "100 entries · 100 missed".
  static const int _widestCount = 100;

  static const AgendaHeaderSlots _oneLine = AgendaHeaderSlots(
    sectionsOnOneLine: true,
    daysOnOneLine: true,
  );
  static const AgendaHeaderSlots _wrapped = AgendaHeaderSlots(
    sectionsOnOneLine: false,
    daysOnOneLine: false,
  );

  /// The widest section label and the widest read row, each laid out on one
  /// line and wrapped; a read row also bare, outside its shell, which is the
  /// height its slot gives it.
  final GlobalKey _sectionOneLine = GlobalKey();
  final GlobalKey _sectionWrapped = GlobalKey();
  final GlobalKey _dayOneLine = GlobalKey();
  final GlobalKey _dayWrapped = GlobalKey();
  final GlobalKey _dayBareOneLine = GlobalKey();
  final GlobalKey _dayBareWrapped = GlobalKey();

  /// Two runs of templates — plain entries, captioned entries — each entry
  /// kind measured inside its group and closing it.
  final List<GlobalKey> _plain = List.generate(3, (_) => GlobalKey());
  final List<GlobalKey> _captioned = List.generate(3, (_) => GlobalKey());

  /// The tail's two captions, in [_ListTail] order.
  final List<GlobalKey> _tails = List.generate(
    _ListTail.values.length,
    (_) => GlobalKey(),
  );

  void _read() {
    if (!mounted || !widget.measure) return;
    double heightOf(GlobalKey key) => key.currentContext?.size?.height ?? 0;
    // Wrapping changes nothing while the widest fits one line: the one-line
    // shape is kept then, and a count longer than the template's squeezes
    // its label rather than outgrowing the slot.
    final sectionsOnOneLine =
        heightOf(_sectionWrapped) <=
        heightOf(_sectionOneLine) + precisionErrorTolerance;
    final daysOnOneLine =
        heightOf(_dayWrapped) <=
        heightOf(_dayOneLine) + precisionErrorTolerance;
    final month = heightOf(
      sectionsOnOneLine ? _sectionOneLine : _sectionWrapped,
    );
    final extents = _RowExtents(
      headers: AgendaHeaderSlots(
        sectionsOnOneLine: sectionsOnOneLine,
        daysOnOneLine: daysOnOneLine,
        sectionHeight: month,
        dayReadHeight: heightOf(
          daysOnOneLine ? _dayBareOneLine : _dayBareWrapped,
        ),
      ),
      month: month,
      dayRead: heightOf(daysOnOneLine ? _dayOneLine : _dayWrapped),
      entry: heightOf(_plain[1]),
      entryEnd: heightOf(_plain[2]),
      entryCaption: heightOf(_captioned[1]),
      entryCaptionEnd: heightOf(_captioned[2]),
      caption: heightOf(_tails[_ListTail.loading.index]),
      capCaption: heightOf(_tails[_ListTail.capped.index]),
    );
    if (extents.month <= 0 ||
        extents.dayRead <= 0 ||
        extents.entryCaptionEnd <= 0 ||
        extents.capCaption <= 0) {
      return;
    }
    widget.onMeasured(extents);
  }

  /// The widest of [labels] as [style] draws it at the ambient scale.
  static String _widest(
    BuildContext context,
    Iterable<String> labels,
    TextStyle? style,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = '';
    var widestWidth = -1.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widestWidth) {
        widest = label;
        widestWidth = painter.width;
      }
      painter.dispose();
    }
    return widest;
  }

  /// The day whose read row's label is the widest the list can show: every
  /// weekday in every month of the year at a two-digit day — the read row's
  /// own format, `DateFormat` over the locale's names, with the year a
  /// period across New Year adds, so no period needs another measurement —
  /// and Today and Tomorrow.
  DateTime _widestDay(BuildContext context, AgendaDayListRowBuilder rows) {
    final l10n = AppLocalizations.of(context)!;
    final today = widget.today;
    final days = <String, DateTime>{
      for (var month = 1; month <= 12; month++)
        for (var day = 22; day <= 28; day++)
          _dayLabel(l10n, rows, DateTime.utc(today.year, month, day)):
              DateTime.utc(today.year, month, day),
      _dayLabel(l10n, rows, today): today,
      _dayLabel(l10n, rows, today.add(const Duration(days: 1))): today.add(
        const Duration(days: 1),
      ),
    };
    final style = FormLabelValue.labelStyle(
      Theme.of(context).colorScheme.onSurface,
    );
    return days[_widest(context, days.keys, style)]!;
  }

  String _dayLabel(
    AppLocalizations l10n,
    AgendaDayListRowBuilder rows,
    DateTime day,
  ) => AgendaListView.dayHeaderLabel(
    l10n,
    day,
    rows.today,
    withYear: rows.dayHeaderWithYear,
  );

  /// The month whose label is the widest: the twelve of the year, with the
  /// year, in the section label's capitals — the pinned label's form.
  DateTime _widestMonth(BuildContext context) {
    final localeName = AppLocalizations.of(context)!.localeName;
    final months = <String, DateTime>{
      for (var month = 1; month <= 12; month++)
        FormSectionLabel.capitals(
          AgendaListView.monthLabel(
            localeName,
            DateTime.utc(widget.today.year, month),
            withYear: true,
          ),
        ): DateTime.utc(
          widget.today.year,
          month,
        ),
    };
    final style = FormSectionLabel.textStyle(Theme.of(context));
    return months[_widest(context, months.keys, style)]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.measure) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) => _read());
    final color = Theme.of(context).colorScheme.primary;
    final today = widget.today;
    AgendaDayListEntryRow entry(String? caption) => AgendaDayListEntryRow(
      entry: AgendaDayListEntry(
        day: today,
        icon: Icons.event_rounded,
        color: color,
        title: today.toIso8601String(),
        subtitle: caption,
        // Measured with the presence button wherever the page offers it, so
        // the probe lays out the real row.
        presenceTracked: true,
      ),
    );
    final day = AgendaDayListDayRow(day: today, count: 1, missed: 1);
    final plain = <AgendaDayListRow>[day, entry(null), entry(null)];
    final captioned = <AgendaDayListRow>[
      day,
      entry(today.toIso8601String()),
      entry(today.toIso8601String()),
    ];
    final plainRows = widget.builderOf(plain);
    final captionedRows = widget.builderOf(captioned);
    AgendaDayListRowBuilder headerRows(
      List<AgendaDayListRow> rows,
      bool oneLine,
    ) => widget.builderOf(
      rows,
      headers: oneLine ? _oneLine : _wrapped,
      dayHeaderWithYear: true,
    );
    final widestDay = _widestDay(context, headerRows(const [], true));
    final section = <AgendaDayListRow>[
      AgendaDayListMonthRow(
        month: _widestMonth(context),
        showYear: true,
        kept: _widestCount,
        missed: _widestCount,
      ),
    ];
    final dayRead = <AgendaDayListRow>[
      AgendaDayListDayRow(
        day: widestDay,
        count: _widestCount,
        missed: _widestCount,
      ),
    ];
    Widget header(GlobalKey key, List<AgendaDayListRow> rows, bool oneLine) =>
        KeyedSubtree(
          key: key,
          child: headerRows(rows, oneLine).build(context, 0),
        );
    Widget bare(GlobalKey key, bool oneLine) => KeyedSubtree(
      key: key,
      child: headerRows(dayRead, oneLine).readRow(
        context,
        day: widestDay,
        kept: _widestCount,
        missed: _widestCount,
      ),
    );
    return Offstage(
      child: ExcludeFocus(
        child: IgnorePointer(
          child: TickerMode(
            enabled: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(_sectionOneLine, section, true),
                header(_sectionWrapped, section, false),
                header(_dayOneLine, dayRead, true),
                header(_dayWrapped, dayRead, false),
                bare(_dayBareOneLine, true),
                bare(_dayBareWrapped, false),
                for (var i = 0; i < plain.length; i++)
                  KeyedSubtree(
                    key: _plain[i],
                    child: plainRows.build(context, i),
                  ),
                for (var i = 0; i < captioned.length; i++)
                  KeyedSubtree(
                    key: _captioned[i],
                    child: captionedRows.build(context, i),
                  ),
                for (final tail in _ListTail.values)
                  KeyedSubtree(
                    key: _tails[tail.index],
                    child: _OverviewBody._tailCaption(
                      AppLocalizations.of(context)!,
                      tail,
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
