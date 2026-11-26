part of '../calendar_overview_page.dart';

/// Every row kind's height at the text scale, locale and width in use (T4),
/// read off [_RowExtentProbe]'s templates; an entry kind twice, as the
/// shell draws it — with the hairline under it, and closing its group. The
/// headers' two are their widest's, in the layout [headers] gives them.
@immutable
class _RowExtents {
  final AgendaHeaderSlots headers;
  final double month;
  final double dayRead;
  final double entry;
  final double entryEnd;
  final double entryCaption;
  final double entryCaptionEnd;

  /// The list's tail: "Loading more…", and the cap's line, which wraps to
  /// two lines in German at 200 %.
  final double caption;
  final double capCaption;

  const _RowExtents({
    required this.headers,
    required this.month,
    required this.dayRead,
    required this.entry,
    required this.entryEnd,
    required this.entryCaption,
    required this.entryCaptionEnd,
    required this.caption,
    required this.capCaption,
  });

  double slotOfTail(_ListTail tail) => switch (tail) {
    _ListTail.loading => caption,
    _ListTail.capped => capCaption,
  };

  /// The slot of a row of [kind]: its height, plus the gap to the next group
  /// when it carries one.
  double slotOf(
    AgendaRowExtentKind kind, {
    required bool closesGroup,
    required bool trailingGap,
  }) {
    final height = switch (kind) {
      AgendaRowExtentKind.month => month,
      AgendaRowExtentKind.dayRead => dayRead,
      AgendaRowExtentKind.entry => closesGroup ? entryEnd : entry,
      AgendaRowExtentKind.entryCaption =>
        closesGroup ? entryCaptionEnd : entryCaption,
    };
    return trailingGap ? height + RowMetrics.groupGap : height;
  }

  @override
  bool operator ==(Object other) =>
      other is _RowExtents &&
      other.headers == headers &&
      other.month == month &&
      other.dayRead == dayRead &&
      other.entry == entry &&
      other.entryEnd == entryEnd &&
      other.entryCaption == entryCaption &&
      other.entryCaptionEnd == entryCaptionEnd &&
      other.caption == caption &&
      other.capCaption == capCaption;

  @override
  int get hashCode => Object.hash(
    headers,
    month,
    dayRead,
    entry,
    entryEnd,
    entryCaption,
    entryCaptionEnd,
    caption,
    capCaption,
  );
}

/// What closes a list that does not reach its period's end: months still
/// being resolved, or the entry cap (T5).
enum _ListTail { loading, capped }

/// The list's rows as slots and their prefix sums, so an offset, a row, a
/// day and a section convert into one another without laying out a row
/// (§3.8 item 4): a jump, the landing and the anchoring are exact, and the
/// pinned label is a lookup.
class _ListLayout {
  final List<AgendaDayListRow> rows;
  final _RowExtents extents;

  /// The caption after [rows], if the list has one: one slot more than
  /// there are rows.
  final _ListTail? tail;

  /// Each row's extent, as the list's `itemExtentBuilder` hands it out, and
  /// the tail's last.
  final List<double> slots;

  /// `slots` summed: row `i` starts at `_offsets[i]`; the last entry is the
  /// whole run.
  final List<double> _offsets;

  /// The section rows — months, or category groups — in list order.
  final List<int> _sections;

  /// The day read rows in list order, their days ascending, or descending
  /// under Newest first.
  final List<int> _days;
  final bool _newestFirst;

  _ListLayout._(
    this.rows,
    this.extents,
    this.tail,
    this.slots,
    this._offsets,
    this._sections,
    this._days,
    this._newestFirst,
  );

  factory _ListLayout.of(
    AgendaDayListRowBuilder builder,
    _RowExtents extents, {
    required bool newestFirst,
    required _ListTail? tail,
  }) => _summed(builder, extents, newestFirst: newestFirst, tail: tail);

  bool get newestFirst => _newestFirst;

  /// This layout over [builder]'s rows, which begin with [rows]: the slots
  /// summed so far stand but the last row's — whose group a new row may
  /// carry on, so its gap can change — and only the rest is summed (review
  /// 16). The arrays are copied, so every layout stays what it was.
  _ListLayout extendedTo(
    AgendaDayListRowBuilder builder, {
    required _ListTail? tail,
  }) {
    final kept = rows.isEmpty ? 0 : rows.length - 1;
    return _summed(
      builder,
      extents,
      newestFirst: _newestFirst,
      tail: tail,
      from: this,
      kept: kept,
    );
  }

  /// Sums [builder]'s rows from row [kept] on, the ones before it taken from
  /// [from].
  static _ListLayout _summed(
    AgendaDayListRowBuilder builder,
    _RowExtents extents, {
    required bool newestFirst,
    required _ListTail? tail,
    _ListLayout? from,
    int kept = 0,
  }) {
    final rows = builder.rows;
    final count = rows.length + (tail == null ? 0 : 1);
    final slots = List<double>.filled(count, 0);
    final offsets = List<double>.filled(count + 1, 0);
    final sections = <int>[];
    final days = <int>[];
    if (from != null && kept > 0) {
      slots.setRange(0, kept, from.slots);
      offsets.setRange(0, kept + 1, from._offsets);
      sections.addAll(from._sections.where((row) => row < kept));
      days.addAll(from._days.where((row) => row < kept));
    }
    for (var i = kept; i < rows.length; i++) {
      slots[i] = extents.slotOf(
        builder.extentKindOf(i),
        closesGroup: builder.closesGroupOf(i),
        trailingGap: builder.trailingGapOf(i),
      );
      offsets[i + 1] = offsets[i] + slots[i];
      switch (rows[i]) {
        case AgendaDayListMonthRow() || AgendaDayListCategoryRow():
          sections.add(i);
        case AgendaDayListDayRow():
          days.add(i);
        case AgendaDayListEntryRow() || AgendaDayListEventRow():
          break;
      }
    }
    if (tail != null) {
      slots[rows.length] = extents.slotOfTail(tail);
      offsets[count] = offsets[rows.length] + slots[rows.length];
    }
    return _ListLayout._(
      rows,
      extents,
      tail,
      slots,
      offsets,
      sections,
      days,
      newestFirst,
    );
  }

  double offsetOfRow(int index) => _offsets[index];

  /// Where slot [index] starts — the tail's too; past the last, the end.
  double offsetOfSlot(int index) =>
      _offsets[index < slots.length ? index : slots.length];

  /// The slot a sliver lays out first or last for [scrollOffset]: the one
  /// whose end reaches it — at a slot's boundary the one before it, as the
  /// stock varied-extent sliver counts; past the end, the last.
  int slotReaching(double scrollOffset) {
    if (scrollOffset <= 0) return 0;
    var low = 1;
    var high = slots.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_offsets[mid] >= scrollOffset) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low - 1;
  }

  /// The whole run of rows, end to end.
  double get extent => _offsets.last;

  /// The row under [offset]: the last one starting at or above it.
  int rowAtOffset(double offset) {
    var low = 0;
    var high = rows.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_offsets[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// The section row heading the row under [offset]; null above the first.
  int? groupAt(double offset) => switch (_sectionIndexAt(offset)) {
    final index? => _sections[index],
    null => null,
  };

  /// The section whose label is pinned above the list at [offset]: the one
  /// [groupAt] names once its own label's slot lies wholly above [offset],
  /// else the one before it — while any of a label still shows in the list,
  /// the pinned label is another.
  int? pinnedAt(double offset) {
    final index = _sectionIndexAt(offset);
    if (index == null) return null;
    final section = _sections[index];
    if (offset >= _offsets[section + 1]) return section;
    return index > 0 ? _sections[index - 1] : null;
  }

  /// Where the next section starts from [offset] ([direction] 1), or the
  /// previous one (-1) — the section [offset] is inside first, unless it is
  /// at that section's very start; null past either end.
  double? sectionStep(double offset, int direction) {
    if (_sections.isEmpty) return null;
    final index = _sectionIndexAt(offset);
    final int target;
    if (index == null) {
      target = direction > 0 ? 0 : -1;
    } else if (direction > 0) {
      target = index + 1;
    } else {
      target = _offsets[_sections[index]] < offset ? index : index - 1;
    }
    if (target < 0 || target >= _sections.length) return null;
    return _offsets[_sections[target]];
  }

  /// [_sections]' index of the section heading the row under [offset].
  int? _sectionIndexAt(double offset) {
    final row = rowAtOffset(offset);
    int? found;
    var low = 0;
    var high = _sections.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_sections[mid] <= row) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  /// The month the row under [offset] belongs to; null in per-event rows.
  DateTime? monthAtOffset(double offset) => switch (groupAt(offset)) {
    final index? => switch (rows[index]) {
      AgendaDayListMonthRow(:final month) => month,
      _ => null,
    },
    null => null,
  };

  /// The first day read row at or past [day] in the list's direction — the
  /// day's own, or the nearest after it as the list reads; null when none
  /// follows.
  int? _dayRowFrom(DateTime day) {
    bool reached(int row) {
      final rowDay = (rows[row] as AgendaDayListDayRow).day;
      return _newestFirst ? !rowDay.isAfter(day) : !rowDay.isBefore(day);
    }

    var low = 0;
    var high = _days.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (reached(_days[mid])) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low < _days.length ? _days[low] : null;
  }

  /// Where [day]'s read row starts, or the nearest later day's as the list
  /// reads; null when no day follows.
  double? offsetOfDay(DateTime day) => switch (_dayRowFrom(day)) {
    final row? => _offsets[row],
    null => null,
  };

  /// [day]'s own read row, if the list has one.
  int? dayRowOf(DateTime day) {
    final row = _dayRowFrom(day);
    if (row == null) return null;
    return (rows[row] as AgendaDayListDayRow).day == day ? row : null;
  }

  int? monthRowOf(DateTime month) {
    for (final row in _sections) {
      if (rows[row] case AgendaDayListMonthRow(
        month: final m,
      ) when m == month) {
        return row;
      }
    }
    return null;
  }

  int? categoryRowOf(String categoryId) {
    for (final row in _sections) {
      if (rows[row] case AgendaDayListCategoryRow(
        categoryId: final id,
      ) when id == categoryId) {
        return row;
      }
    }
    return null;
  }

  int? eventRowOf(String? eventId) {
    if (eventId == null) return null;
    for (var row = 0; row < rows.length; row++) {
      if (rows[row] case AgendaDayListEventRow(
        :final entry,
      ) when entry.eventId == eventId) {
        return row;
      }
    }
    return null;
  }
}
