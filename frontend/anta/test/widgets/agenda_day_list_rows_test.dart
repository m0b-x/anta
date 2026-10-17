import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/widgets/agenda_day_list_rows.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/form_rows.dart';

AgendaDayListEntry _entry(DateTime day, String title, {bool missed = false}) {
  return AgendaDayListEntry(
    day: day,
    icon: Icons.fitness_center,
    color: const Color(0xFF1E88E5),
    title: title,
    missed: missed,
    eventId: title,
  );
}

/// The rows the overview's list and the day list sheet flatten their days
/// into, pinned before the List mode rework
/// (`docs/calendar-overview-list-roadmap.md` slice 0) replaces the page's
/// renderer; a case that names an R-number pins a known defect as it is
/// today.
void main() {
  final jan5 = DateTime.utc(2026, 1, 5);
  final jan6 = DateTime.utc(2026, 1, 6);
  final mar9 = DateTime.utc(2026, 3, 9);
  final dec24 = DateTime.utc(2025, 12, 24);

  final pool = <DateTime, List<AgendaDayListEntry>>{
    dec24: [_entry(dec24, 'Eve')],
    jan5: [_entry(jan5, 'Squat'), _entry(jan5, 'Row', missed: true)],
    mar9: [_entry(mar9, 'Stretch')],
  };

  List<AgendaDayListEntry> entriesOf(DateTime day) => pool[day] ?? const [];

  int keptCountOf(DateTime day) =>
      entriesOf(day).where((entry) => !entry.missed).length;

  List<AgendaDayListRow> build(
    List<DateTime> days, {
    bool groupByDay = true,
    bool withMonths = true,
    bool alwaysMonths = false,
  }) => buildAgendaDayListRows(
    days,
    entriesOf,
    groupByDay: groupByDay,
    withMonths: withMonths,
    keptCountOf: keptCountOf,
    alwaysMonths: alwaysMonths,
  );

  List<String> rowsOf(
    List<DateTime> days, {
    bool groupByDay = true,
    bool withMonths = true,
    bool alwaysMonths = false,
  }) => [
    for (final row in build(
      days,
      groupByDay: groupByDay,
      withMonths: withMonths,
      alwaysMonths: alwaysMonths,
    ))
      switch (row) {
        AgendaDayListMonthRow(:final month, :final showYear) =>
          'month ${month.year}-${month.month}${showYear ? ' with year' : ''}',
        AgendaDayListDayRow(:final day, :final count, :final missed) =>
          'day ${day.month}/${day.day} kept $count missed $missed',
        AgendaDayListEntryRow(:final entry) => 'entry ${entry.title}',
        AgendaDayListCategoryRow(:final label) => 'category $label',
        AgendaDayListEventRow(:final entry) => 'event ${entry.title}',
      },
  ];

  group('buildAgendaDayListRows', () {
    test('months and days head their entries', () {
      expect(rowsOf([jan5, mar9]), [
        'month 2026-1',
        'day 1/5 kept 1 missed 1',
        'entry Squat',
        'entry Row',
        'month 2026-3',
        'day 3/9 kept 1 missed 0',
        'entry Stretch',
      ]);
    });

    test('without groupByDay there are no day headers', () {
      expect(rowsOf([jan5, mar9], groupByDay: false), [
        'month 2026-1',
        'entry Squat',
        'entry Row',
        'month 2026-3',
        'entry Stretch',
      ]);
    });

    test('without withMonths there are no month headers', () {
      expect(rowsOf([jan5, mar9], withMonths: false), [
        'day 1/5 kept 1 missed 1',
        'entry Squat',
        'entry Row',
        'day 3/9 kept 1 missed 0',
        'entry Stretch',
      ]);
    });

    test('days that fall in one month get no month header (R16)', () {
      // R16, pinned as today: `multiMonth` drops the header whenever the
      // first and last day share a month, so a year whose rows are all in
      // March reads as a bare list of days. Slice 3 always heads a month in
      // list mode.
      expect(rowsOf([mar9]), ['day 3/9 kept 1 missed 0', 'entry Stretch']);
    });

    test('days that cross a year put the year on every month row', () {
      expect(rowsOf([dec24, jan5]), [
        'month 2025-12 with year',
        'day 12/24 kept 1 missed 0',
        'entry Eve',
        'month 2026-1 with year',
        'day 1/5 kept 1 missed 1',
        'entry Squat',
        'entry Row',
      ]);
    });

    test('days with no entries are skipped, their months with them', () {
      // January's only day is empty, so no January header — but the span
      // still counts it: the first and last day sit in different months, so
      // March keeps its header though it is the only month drawn.
      expect(rowsOf([jan6, mar9]), [
        'month 2026-3',
        'day 3/9 kept 1 missed 0',
        'entry Stretch',
      ]);
    });

    test('a day header counts the kept entries and the missed apart', () {
      final rows = build([jan5]);
      final header = rows.whereType<AgendaDayListDayRow>().single;
      expect(header.count, 1);
      expect(header.missed, 1);
      expect(rows.whereType<AgendaDayListEntryRow>(), hasLength(2));
    });

    test('no days, no rows', () {
      expect(rowsOf(const []), isEmpty);
    });

    test('alwaysMonths heads a single month too', () {
      expect(rowsOf([mar9], alwaysMonths: true), [
        'month 2026-3',
        'day 3/9 kept 1 missed 0',
        'entry Stretch',
      ]);
      expect(rowsOf([jan5, jan6], alwaysMonths: true), [
        'month 2026-1',
        'day 1/5 kept 1 missed 1',
        'entry Squat',
        'entry Row',
      ]);
    });

    test('alwaysMonths still names the year only when the days cross one', () {
      expect(rowsOf([dec24, jan5], alwaysMonths: true), [
        'month 2025-12 with year',
        'day 12/24 kept 1 missed 0',
        'entry Eve',
        'month 2026-1 with year',
        'day 1/5 kept 1 missed 1',
        'entry Squat',
        'entry Row',
      ]);
    });

    test('alwaysMonths with no entries draws nothing', () {
      expect(rowsOf([jan6], alwaysMonths: true), isEmpty);
    });
  });

  group('AgendaListView.dayHeaderLabel', () {
    final today = DateTime.utc(2026, 10, 11);

    setUpAll(() async {
      await initializeDateFormatting();
    });

    test('names no year by default', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        AgendaListView.dayHeaderLabel(en, DateTime.utc(2026, 3, 9), today),
        'Monday, March 9',
      );
    });

    test('withYear names the year in the locale\'s own order', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final de = lookupAppLocalizations(const Locale('de'));
      final day = DateTime.utc(2025, 12, 24);
      expect(
        AgendaListView.dayHeaderLabel(en, day, today, withYear: true),
        'Wednesday, December 24, 2025',
      );
      expect(
        AgendaListView.dayHeaderLabel(de, day, today, withYear: true),
        'Mittwoch, 24. Dezember 2025',
      );
    });

    test('withYear keeps Today and Tomorrow', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        AgendaListView.dayHeaderLabel(en, today, today, withYear: true),
        en.upcomingToday,
      );
      expect(
        AgendaListView.dayHeaderLabel(
          en,
          DateTime.utc(2026, 10, 12),
          today,
          withYear: true,
        ),
        en.upcomingTomorrow,
      );
    });
  });

  group('month counts', () {
    test('a month row counts the kept and missed entries of its days', () {
      final months = build([
        jan5,
        jan6,
        mar9,
      ]).whereType<AgendaDayListMonthRow>().toList();
      expect(
        [for (final m in months) (m.month.month, m.kept, m.missed)],
        [(1, 1, 1), (3, 1, 0)],
      );
    });

    test('the counts follow the caller\'s kept count, so Missed only counts '
        'every entry as missed', () {
      final month = buildAgendaDayListRows(
        [jan5],
        entriesOf,
        groupByDay: true,
        withMonths: true,
        alwaysMonths: true,
        keptCountOf: (_) => 0,
      ).whereType<AgendaDayListMonthRow>().single;
      expect((month.kept, month.missed), (0, 2));
    });
  });

  group('AgendaDayListRowBuilder', () {
    final today = DateTime.utc(2026, 10, 11);

    Future<void> pumpBuilder(
      WidgetTester tester,
      AgendaDayListRowBuilder Function(List<AgendaDayListRow> rows) of,
      List<AgendaDayListRow> rows,
    ) {
      final builder = of(rows);
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: ListView.builder(
              itemCount: rows.length,
              itemBuilder: builder.build,
            ),
          ),
        ),
      );
    }

    AgendaDayListRowBuilder plain(
      List<AgendaDayListRow> rows, {
      ValueChanged<AgendaDayListEntry>? onEntryTap,
      ValueChanged<AgendaDayListEntry>? onEntryEdit,
      ValueChanged<AgendaDayListEventRow>? onEventTap,
      bool monthCounts = false,
      String? Function(AgendaDayListEntry entry)? rowIdentifier,
      void Function(AgendaDayListEntry entry, bool missed)? onEntryPresence,
    }) => AgendaDayListRowBuilder(
      rows: rows,
      today: today,
      onEntryTap: onEntryTap ?? (_) {},
      onEntryPresence: onEntryPresence,
      presenceIdentifier: (entry) => 'presence-${entry.title}',
      onEntryEdit: onEntryEdit,
      onEventTap: onEventTap,
      monthCounts: monthCounts,
      rowIdentifier: rowIdentifier,
    );

    test('extent kinds, group ends and gaps follow the rows', () {
      final rows = build([jan5, mar9]);
      final builder = plain(rows);
      expect(
        [for (var i = 0; i < rows.length; i++) builder.extentKindOf(i)],
        [
          AgendaRowExtentKind.month,
          AgendaRowExtentKind.dayRead,
          AgendaRowExtentKind.entry,
          AgendaRowExtentKind.entry,
          AgendaRowExtentKind.month,
          AgendaRowExtentKind.dayRead,
          AgendaRowExtentKind.entry,
        ],
      );
      expect(
        [for (var i = 0; i < rows.length; i++) builder.closesGroupOf(i)],
        [false, false, false, true, false, false, true],
      );
      // The list's last row closes its group with no gap under it.
      expect(
        [for (var i = 0; i < rows.length; i++) builder.trailingGapOf(i)],
        [false, false, false, true, false, false, false],
      );

      final captioned = [
        AgendaDayListEntryRow(
          entry: AgendaDayListEntry(
            day: mar9,
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: 'Swim',
            subtitle: 'Every week',
          ),
        ),
      ];
      expect(
        plain(captioned).extentKindOf(0),
        AgendaRowExtentKind.entryCaption,
      );
    });

    testWidgets('months as section labels, days as read rows, entries under '
        'them; the month count only when asked', (tester) async {
      final rows = build([jan5], alwaysMonths: true);
      await pumpBuilder(tester, plain, rows);
      final label = tester.widget<FormSectionLabel>(
        find.byType(FormSectionLabel),
      );
      expect(label.text, 'January');
      expect(label.trailing, isNull);
      expect(find.byType(FormRowShell), findsNWidgets(3));
      expect(find.text('Squat'), findsOneWidget);

      await pumpBuilder(tester, (r) => plain(r, monthCounts: true), rows);
      expect(
        tester.widget<FormSectionLabel>(find.byType(FormSectionLabel)).trailing,
        '1 entry · 1 missed',
      );
    });

    testWidgets('a missed entry is faded at the title indent, a kept one is '
        'not', (tester) async {
      await pumpBuilder(tester, plain, build([jan5]));

      Finder fadeOf(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(Opacity));
      expect(fadeOf('Squat'), findsNothing);
      expect(
        tester.widget<Opacity>(fadeOf('Row')).opacity,
        CalendarColors.missedEventAlpha,
      );
      expect(
        tester
            .widget<FormIndentedRow>(
              find.ancestor(
                of: find.text('Row'),
                matching: find.byType(FormIndentedRow),
              ),
            )
            .dividerIndent,
        FormMetrics.dividerIndentTitle,
      );
    });

    testWidgets('an entry tap hands back its entry; the pencil shows only '
        'where both the caller and the entry offer an edit', (tester) async {
      final tapped = <AgendaDayListEntry>[];
      final edited = <AgendaDayListEntry>[];
      final editable = AgendaDayListEntry(
        day: mar9,
        icon: Icons.fitness_center,
        color: const Color(0xFF1E88E5),
        title: 'Stretch',
        eventId: 'Stretch',
        onEdit: () {},
      );
      final rows = [AgendaDayListEntryRow(entry: editable)];

      await pumpBuilder(tester, (r) => plain(r, onEntryTap: tapped.add), rows);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      await tester.tap(find.text('Stretch'));
      expect(tapped.single.day, mar9);

      await pumpBuilder(tester, (r) => plain(r, onEntryEdit: edited.add), rows);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edited.single.eventId, 'Stretch');
    });

    testWidgets('an entry row carries the identifier the caller names', (
      tester,
    ) async {
      await pumpBuilder(
        tester,
        (r) => plain(r, rowIdentifier: (entry) => 'row-${entry.title}'),
        build([mar9]),
      );
      expect(find.bySemanticsIdentifier('row-Stretch'), findsOneWidget);
    });

    testWidgets('the presence button sits on a tracking entry\'s row when the '
        'caller offers it, hands back the opposite status with the day '
        'panel\'s words, and fades with a missed row', (tester) async {
      final en = lookupAppLocalizations(const Locale('en'));
      final tapped = <AgendaDayListEntry>[];
      final pressed = <(String, bool)>[];
      AgendaDayListEntry tracked(String title, {bool missed = false}) =>
          AgendaDayListEntry(
            day: jan5,
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: title,
            missed: missed,
            eventId: title,
            presenceTracked: true,
          );
      final rows = [
        AgendaDayListEntryRow(entry: tracked('Squat')),
        AgendaDayListEntryRow(entry: tracked('Row', missed: true)),
        AgendaDayListEntryRow(entry: _entry(jan5, 'Stretch')),
      ];
      IconButton button(String title) => tester.widget(
        find.descendant(
          of: find.bySemanticsIdentifier('presence-$title'),
          matching: find.byType(IconButton),
        ),
      );

      await pumpBuilder(
        tester,
        (r) => plain(
          r,
          onEntryTap: tapped.add,
          onEntryPresence: (entry, missed) =>
              pressed.add((entry.title, missed)),
        ),
        rows,
      );
      expect(button('Squat').tooltip, en.eventMarkMissed);
      expect(find.byIcon(Icons.event_busy_rounded), findsOneWidget);
      expect(button('Row').tooltip, en.eventMarkPresent);
      expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
      expect(find.bySemanticsIdentifier('presence-Stretch'), findsNothing);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.bySemanticsIdentifier('presence-Row'),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        CalendarColors.missedEventAlpha,
      );

      await tester.tap(find.bySemanticsIdentifier('presence-Squat'));
      await tester.tap(find.bySemanticsIdentifier('presence-Row'));
      expect(pressed, [('Squat', true), ('Row', false)]);
      expect(tapped, isEmpty);
      await tester.tap(find.text('Squat'));
      expect(tapped.single.title, 'Squat');

      await pumpBuilder(tester, (r) => plain(r), rows);
      expect(find.bySemanticsIdentifier('presence-Squat'), findsNothing);
      expect(find.byIcon(Icons.event_busy_rounded), findsNothing);
      expect(find.byIcon(Icons.event_available_rounded), findsNothing);
    });

    testWidgets('the pencil keeps the slot where an entry offers both an edit '
        'and presence', (tester) async {
      final edited = <AgendaDayListEntry>[];
      final rows = [
        AgendaDayListEntryRow(
          entry: AgendaDayListEntry(
            day: mar9,
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: 'Stretch',
            eventId: 'Stretch',
            onEdit: () {},
            presenceTracked: true,
          ),
        ),
      ];

      await pumpBuilder(
        tester,
        (r) => plain(
          r,
          onEntryEdit: edited.add,
          onEntryPresence: (_, _) => fail('no presence button'),
        ),
        rows,
      );
      expect(find.bySemanticsIdentifier('presence-Stretch'), findsNothing);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      expect(edited.single.title, 'Stretch');
    });

    testWidgets('an event row reads its count, its span and its missed ones, '
        'and its tap hands back the row', (tester) async {
      final tapped = <AgendaDayListEventRow>[];
      final rows = foldAgendaDayListRowsByEvent(
        [
          _entry(jan5, 'Row'),
          _entry(jan6, 'Row', missed: true),
          _entry(mar9, 'Row'),
        ],
        categoryLabels: const {'gym': 'Gym'},
        categoryOrder: const ['gym'],
        newestFirst: false,
        categoryOf: (_) => 'gym',
      );
      await pumpBuilder(tester, (r) => plain(r, onEventTap: tapped.add), rows);

      final label = tester.widget<FormSectionLabel>(
        find.byType(FormSectionLabel),
      );
      expect((label.text, label.trailing), ('Gym', '1 event'));
      final row = tester.widget<FormPickerRow>(find.byType(FormPickerRow));
      expect(row.value, '3');
      expect(row.caption, 'Jan 5 – Mar 9, 2026 · 1 missed');
      expect(row.singleLine, isTrue);

      await tester.tap(find.text('Row'));
      expect(tapped.single.last, mar9);
    });

    testWidgets('each category group\'s first event row opens it with the '
        'rounded top (review 4)', (tester) async {
      final rows = foldAgendaDayListRowsByEvent(
        [_entry(jan5, 'Row'), _entry(jan6, 'Squat'), _entry(mar9, 'Stretch')],
        categoryLabels: const {'gym': 'Gym', 'mobility': 'Mobility'},
        categoryOrder: const ['gym', 'mobility'],
        newestFirst: false,
        categoryOf: (entry) => entry.title == 'Stretch' ? 'mobility' : 'gym',
      );
      await pumpBuilder(tester, plain, rows);

      bool firstOf(String title) => tester
          .widget<FormRowShell>(
            find.ancestor(
              of: find.text(title),
              matching: find.byType(FormRowShell),
            ),
          )
          .first;
      expect(firstOf('Row'), isTrue);
      expect(firstOf('Squat'), isFalse);
      expect(firstOf('Stretch'), isTrue);
    });
  });

  group('foldAgendaDayListRowsByEvent', () {
    List<AgendaDayListRow> fold(
      List<AgendaDayListEntry> entries, {
      bool newestFirst = false,
      Map<String, String> categories = const {
        'Squat': 'gym',
        'Run': 'gym',
        'Bench': 'gym',
        'Stretch': 'mobility',
      },
    }) => foldAgendaDayListRowsByEvent(
      entries,
      categoryLabels: const {'gym': 'Gym', 'mobility': 'Mobility'},
      categoryOrder: const ['gym', 'mobility'],
      newestFirst: newestFirst,
      categoryOf: (entry) => categories[entry.title] ?? 'unknown',
    );

    List<String> describe(List<AgendaDayListRow> rows) => [
      for (final row in rows)
        switch (row) {
          AgendaDayListCategoryRow(:final label, :final eventCount) =>
            'category $label $eventCount',
          AgendaDayListEventRow(:final entry, :final count, :final missed) =>
            'event ${entry.title} $count missed $missed',
          _ => 'other',
        },
    ];

    final jan7 = DateTime.utc(2026, 1, 7);
    final entries = [
      _entry(jan5, 'Squat'),
      _entry(jan5, 'Stretch'),
      _entry(jan6, 'Run'),
      _entry(jan6, 'Squat'),
      _entry(jan7, 'Squat', missed: true),
      _entry(jan7, 'Stretch'),
      _entry(mar9, 'Bench'),
    ];

    test('groups by category in catalog order, the most frequent first, '
        'ties by title', () {
      expect(describe(fold(entries)), [
        'category Gym 3',
        'event Squat 3 missed 1',
        'event Bench 1 missed 0',
        'event Run 1 missed 0',
        'category Mobility 1',
        'event Stretch 2 missed 0',
      ]);
    });

    test('Newest first leads with the event seen last', () {
      expect(describe(fold(entries, newestFirst: true)), [
        'category Gym 3',
        'event Bench 1 missed 0',
        'event Squat 3 missed 1',
        'event Run 1 missed 0',
        'category Mobility 1',
        'event Stretch 2 missed 0',
      ]);
    });

    test('a row spans its first and last day and wears its first entry', () {
      final squat = fold(entries).whereType<AgendaDayListEventRow>().firstWhere(
        (row) => row.entry.title == 'Squat',
      );
      expect((squat.first, squat.last), (jan5, jan7));
      expect(squat.entry.day, jan5);
      expect(squat.entry.missed, isFalse);
    });

    test('a category missing from the catalog follows the known ones', () {
      final rows = fold([_entry(jan5, 'Yoga'), _entry(jan6, 'Stretch')]);
      expect(describe(rows), [
        'category Mobility 1',
        'event Stretch 1 missed 0',
        'category unknown 1',
        'event Yoga 1 missed 0',
      ]);
    });

    test('no entries, no rows', () {
      expect(fold(const []), isEmpty);
    });
  });
}
