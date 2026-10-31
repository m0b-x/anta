import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/report_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_category_group.dart';

import '../goldens/support/golden_fonts.dart';

/// What a group's callbacks were handed.
class _Log {
  int toggles = 0;
  int mores = 0;
  int showAsList = 0;
  final dated = <ReportDatedRow>[];
  final routines = <ReportRoutineRow>[];
  final presence = <(ReportDatedRow, bool)>[];
}

/// One group in a plain scroll view, holding its own open and expanded
/// state as the page will.
class _GroupHost extends StatefulWidget {
  const _GroupHost({
    super.key,
    required this.card,
    required this.group,
    required this.events,
    required this.log,
    required this.today,
    this.fraction = 0,
    this.open = true,
    this.spansMonths = false,
    this.listEnabled = true,
  });

  final ReportCard card;
  final ReportCategoryGroup group;
  final Map<String, CalendarEvent> events;
  final _Log log;
  final DateTime today;
  final double fraction;
  final bool open;
  final bool spansMonths;

  /// Whether "Show as list" has a tap; without one it draws disabled.
  final bool listEnabled;

  @override
  State<_GroupHost> createState() => _GroupHostState();
}

class _GroupHostState extends State<_GroupHost> {
  late bool _open = widget.open;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final rows = ReportGroupRows(
      card: widget.card,
      group: widget.group,
      events: widget.events,
      labels: ReportLabels(AppLocalizations.of(context)!),
      fraction: widget.fraction,
      open: _open,
      expanded: _expanded,
      onToggle: () {
        log.toggles++;
        setState(() => _open = !_open);
      },
      onMore: () {
        log.mores++;
        setState(() => _expanded = !_expanded);
      },
      onDatedTap: log.dated.add,
      onRoutineTap: log.routines.add,
      onPresence: (row, missed) => log.presence.add((row, missed)),
      onShowAsList: widget.listEnabled ? () => log.showAsList++ : null,
      today: widget.today,
      spansMonths: widget.spansMonths,
      use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: RowMetrics.groupInset,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              rows.build,
              childCount: rows.rowCount,
            ),
          ),
        ),
      ],
    );
  }
}

/// Several groups in one lazily built list, as the page lays a card's
/// groups into its one `SliverList`, each group's open state held here.
class _CardHost extends StatefulWidget {
  const _CardHost({
    required this.groups,
    required this.open,
    required this.events,
    required this.today,
  });

  final List<ReportCategoryGroup> groups;
  final List<bool> open;
  final Map<String, CalendarEvent> events;
  final DateTime today;

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  late final List<bool> _open = [...widget.open];

  @override
  Widget build(BuildContext context) {
    final labels = ReportLabels(AppLocalizations.of(context)!);
    final builders = [
      for (final (i, group) in widget.groups.indexed)
        ReportGroupRows(
          card: ReportCard.categories,
          group: group,
          events: widget.events,
          labels: labels,
          open: _open[i],
          expanded: false,
          onToggle: () => setState(() => _open[i] = !_open[i]),
          onMore: () {},
          onDatedTap: (_) {},
          onRoutineTap: (_) {},
          today: widget.today,
          spansMonths: false,
          use24Hour: true,
        ),
    ];
    final slots = [
      for (final rows in builders)
        for (var i = 0; i < rows.rowCount; i++) (rows, i),
    ];
    final indexOf = {
      for (final (n, (rows, i)) in slots.indexed) rows.keyOf(i): n,
    };
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
      itemCount: slots.length,
      itemBuilder: (context, n) => slots[n].$1.build(context, slots[n].$2),
      findChildIndexCallback: (key) => indexOf[key],
    );
  }
}

/// The report's category groups (W, X) drawn alone: the header, the
/// preview of four and the disclosure rows, the three row kinds, the
/// Missed card's presence button, the 200-row cap, and §4.8's heights with
/// Roboto loaded.
void main() {
  setUpAll(loadGoldenFonts);

  final today = DateTime.utc(2026, 10, 30);

  /// A tracked, timed daily routine.
  final gym = CalendarEvent(
    id: 'e-gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    tracksPresence: true,
  );

  /// A timed one-off.
  final pt = CalendarEvent(
    id: 'e-pt',
    title: 'PT session',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 10, 8),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 17 * 60, durationMinutes: 60),
  );

  /// A yearly birthday counting the years.
  final birthday = CalendarEvent(
    id: 'e-ana',
    title: "Ana's birthday",
    categoryId: 'birthday',
    startDate: DateTime.utc(1994, 10, 29),
    rule: const YearlyRecurrence(),
    countOccurrences: true,
    countStyle: OccurrenceCountStyle.elapsed,
  );

  /// An untimed to-do.
  final groceries = CalendarEvent(
    id: 'e-groceries',
    title: 'Groceries',
    categoryId: 'other',
    startDate: DateTime.utc(2026, 10, 30),
    rule: const OneTimeRecurrence(),
  );

  /// A timed weekly program numbering its weeks: Thursday 8 October is its
  /// third.
  final block = CalendarEvent(
    id: 'e-block',
    title: 'Strength block',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 24),
    rule: const WeeklyRecurrence(weekdays: {DateTime.thursday}),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
    countOccurrences: true,
  );

  final events = {
    for (final event in [gym, pt, birthday, groceries, block]) event.id: event,
  };

  /// Gym's aggregate row: 8 of 10 attended, 8 h.
  final routine = ReportRoutineRow(
    eventId: gym.id,
    attended: 8,
    total: 10,
    minutes: 480,
    latestDay: DateTime.utc(2026, 10, 29),
  );

  setUp(() {
    CalendarCategories.updateCache([
      for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: seed.kind.name,
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: index,
          isBuiltIn: true,
        ),
    ]);
  });

  tearDown(() {
    EventPresence.resetCache();
    CalendarCategories.updateCache(const []);
  });

  /// [count] gym rows on consecutive days from 1 January.
  List<ReportRow> gymDays(int count) => [
    for (var i = 0; i < count; i++)
      ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 1, 1 + i)),
  ];

  ReportCategoryGroup groupOf(
    List<ReportRow> rows, {
    String categoryId = 'gym',
    int? count,
    int minutes = 0,
    int missed = 0,
  }) => ReportCategoryGroup(
    categoryId: categoryId,
    count: count ?? rows.length,
    minutes: minutes,
    missed: missed,
    rows: rows,
  );

  Future<_Log> pump(
    WidgetTester tester,
    ReportCategoryGroup group, {
    ReportCard card = ReportCard.categories,
    double fraction = 0.5,
    bool open = true,
    bool spansMonths = false,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Size surface = const Size(360, 780),
    Brightness brightness = Brightness.light,
    bool listEnabled = true,
    bool disableAnimations = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final log = _Log();
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            alwaysUse24HourFormat: true,
            disableAnimations: disableAnimations,
          ),
          child: child!,
        ),
        home: Scaffold(
          // A fresh host per pump: a second pump in one test starts closed
          // to the first one's open and expanded state.
          body: _GroupHost(
            key: UniqueKey(),
            card: card,
            group: group,
            events: events,
            log: log,
            today: today,
            fraction: fraction,
            open: open,
            spansMonths: spansMonths,
            listEnabled: listEnabled,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return log;
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);
  String rowId(String eventId, int month, int day) =>
      SemanticsIds.reportRow(eventId, DateTime.utc(2026, month, day));
  String header(ReportCard card, String categoryId) =>
      SemanticsIds.reportGroup(card.name, categoryId);
  String more(ReportCard card, String categoryId) =>
      SemanticsIds.reportGroupMore(card.name, categoryId);

  /// [parts] as the report joins them, the dot bound to the fact before it.
  String joined(List<String> parts) => parts.join(ReportLabels.separator);

  /// The picker row carrying [id] — `AutomationId` sits inside the row.
  Finder pickerOf(String id) => find.byWidgetPredicate(
    (widget) => widget is FormPickerRow && widget.identifier == id,
  );

  /// The subtitle a dated row draws: the caption under its title.
  String subtitleOf(WidgetTester tester, String id) {
    final caption = tester.widget<FormCaption>(
      find.descendant(of: byId(id), matching: find.byType(FormCaption)),
    );
    return caption.text;
  }

  group('folding', () {
    testWidgets('a twelve-row group opens on its header, four rows and '
        '"8 more"', (tester) async {
      await pump(tester, groupOf(gymDays(12)));
      expect(byId(header(ReportCard.categories, 'gym')), findsOneWidget);
      for (var day = 1; day <= 4; day++) {
        expect(byId(rowId(gym.id, 1, day)), findsOneWidget);
      }
      expect(byId(rowId(gym.id, 1, 5)), findsNothing);
      expect(find.text('8 more'), findsOneWidget);
      expect(find.text('Show less'), findsNothing);
    });

    testWidgets('"n more" shows every row in place and reads "Show less"; '
        'that folds back to four', (tester) async {
      final log = await pump(
        tester,
        groupOf(gymDays(12)),
        surface: const Size(360, 1600),
      );
      final aboveBefore = tester.getRect(byId(rowId(gym.id, 1, 4)));
      await tester.tap(byId(more(ReportCard.categories, 'gym')));
      await tester.pumpAndSettle();
      expect(log.mores, 1);
      for (var day = 1; day <= 12; day++) {
        expect(byId(rowId(gym.id, 1, day)), findsOneWidget);
      }
      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('8 more'), findsNothing);
      expect(
        tester.getRect(byId(rowId(gym.id, 1, 4))),
        aboveBefore,
        reason: 'nothing above the tapped row moves',
      );

      await tester.tap(byId(more(ReportCard.categories, 'gym')));
      await tester.pumpAndSettle();
      expect(log.mores, 2);
      expect(byId(rowId(gym.id, 1, 5)), findsNothing);
      expect(find.text('8 more'), findsOneWidget);
    });

    testWidgets('a header tap calls onToggle; a closed group is its header '
        'alone', (tester) async {
      final log = await pump(tester, groupOf(gymDays(12)));
      await tester.tap(byId(header(ReportCard.categories, 'gym')));
      await tester.pumpAndSettle();
      expect(log.toggles, 1);
      expect(byId(rowId(gym.id, 1, 1)), findsNothing);
      expect(find.text('8 more'), findsNothing);
      expect(byId(header(ReportCard.categories, 'gym')), findsOneWidget);
      // The glyph turns half a turn while open, back when closed.
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0,
      );
      // The named trailing part, as the disclosure row's (D46).
      final glyph = tester.widget<FormTrailingGlyph>(
        find.descendant(
          of: find.byType(AnimatedRotation),
          matching: find.byType(FormTrailingGlyph),
        ),
      );
      expect(glyph.icon, Icons.expand_more_rounded);
      expect(glyph.color, isNull);
    });

    testWidgets('a group of four or fewer has no disclosure row', (
      tester,
    ) async {
      await pump(tester, groupOf(gymDays(4)));
      expect(byId(more(ReportCard.categories, 'gym')), findsNothing);
      expect(byId(rowId(gym.id, 1, 4)), findsOneWidget);
    });

    ReportGroupRows expandedRows(int count) => ReportGroupRows(
      card: ReportCard.categories,
      group: groupOf(gymDays(count)),
      events: events,
      labels: ReportLabels(lookupAppLocalizations(const Locale('en'))),
      open: true,
      expanded: true,
      onToggle: () {},
      onMore: () {},
      onDatedTap: (_) {},
      onRoutineTap: (_) {},
      onShowAsList: () {},
      today: today,
      spansMonths: true,
      use24Hour: true,
    );

    test('200 rows end on "Show less" alone; 201 put "Show as list" before '
        'it', () {
      String slot(ReportGroupRows rows, int index) =>
          (rows.keyOf(index) as ValueKey<String>).value.split('/').last;

      final exact = expandedRows(ReportMetrics.maxListRows);
      // The header, 200 rows, Show less.
      expect(exact.rowCount, 1 + ReportMetrics.maxListRows + 1);
      expect(slot(exact, exact.rowCount - 1), 'more');
      expect(slot(exact, exact.rowCount - 2), isNot('list'));

      final over = expandedRows(ReportMetrics.maxListRows + 1);
      // The header, 200 rows, Show as list, Show less.
      expect(over.rowCount, 1 + ReportMetrics.maxListRows + 2);
      expect(slot(over, over.rowCount - 2), 'list');
      expect(slot(over, over.rowCount - 1), 'more');
    });

    testWidgets('past 200 rows the expansion stops at 200 and the row after '
        'reads "Show as list"', (tester) async {
      final group = groupOf(gymDays(250));
      expect(expandedRows(250).rowCount, 1 + ReportMetrics.maxListRows + 2);

      final log = await pump(tester, group, surface: const Size(360, 780));
      await tester.tap(byId(more(ReportCard.categories, 'gym')));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable);
      await tester.scrollUntilVisible(
        find.text('Show as list'),
        500,
        scrollable: list,
      );
      expect(find.text('Show as list'), findsOneWidget);
      expect(
        byId(SemanticsIds.reportRow(gym.id, DateTime.utc(2026, 7, 19))),
        findsOneWidget,
        reason: 'the 200th row',
      );
      expect(
        byId(SemanticsIds.reportRow(gym.id, DateTime.utc(2026, 7, 20))),
        findsNothing,
      );
      expect(
        byId(SemanticsIds.reportGroupList(ReportCard.categories.name, 'gym')),
        findsOneWidget,
      );
      await tester.tap(find.text('Show as list'));
      await tester.pumpAndSettle();
      expect(log.showAsList, 1);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('"Show as list" with no tap is announced disabled and calls '
        'nothing; with one it says which group', (tester) async {
      final handle = tester.ensureSemantics();
      final listId = SemanticsIds.reportGroupList(
        ReportCard.categories.name,
        'gym',
      );
      Future<void> showList() async {
        await tester.tap(byId(more(ReportCard.categories, 'gym')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          byId(listId),
          500,
          scrollable: find.byType(Scrollable),
        );
      }

      await pump(tester, groupOf(gymDays(201)));
      await showList();
      var data = tester.getSemantics(byId(listId)).getSemanticsData();
      expect(data.label, 'Show Gym as a list');
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);

      final log = await pump(tester, groupOf(gymDays(201)), listEnabled: false);
      await showList();
      data = tester.getSemantics(byId(listId)).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      await tester.tap(find.text('Show as list'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(log.showAsList, 0);
      handle.dispose();
    });

    testWidgets('a closed group\'s header alone draws as one card', (
      tester,
    ) async {
      await pump(tester, groupOf(gymDays(12)), open: false);
      final shell = tester.widget<FormRowShell>(find.byType(FormRowShell));
      expect(shell.first && shell.last, isTrue);
      final card = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FormRowShell),
              matching: find.byType(Material),
            )
            .first,
      );
      const round = Radius.circular(RowMetrics.groupRadius);
      expect(
        card.borderRadius,
        const BorderRadius.vertical(top: round, bottom: round),
      );
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('with animations off the glyph turns at once', (tester) async {
      await pump(tester, groupOf(gymDays(2)));
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
        Durations.short4,
      );
      await pump(tester, groupOf(gymDays(2)), disableAnimations: true);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
        Duration.zero,
      );
    });

    testWidgets('opening a group keeps every later header\'s glyph where it '
        'was', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 1600);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: _CardHost(
              // Opening Gym puts Cardio's header at the index Rest's
              // header held: unkeyed, Cardio would take over Rest's turned
              // glyph and rotate it back.
              groups: [
                groupOf(gymDays(1)),
                groupOf(gymDays(2), categoryId: 'cardio'),
                groupOf(gymDays(2), categoryId: 'rest'),
              ],
              open: const [false, false, true],
              events: events,
              today: today,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double turnsOf(String categoryId) {
        final glyph = find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is FormMeterRow &&
                widget.identifier == header(ReportCard.categories, categoryId),
          ),
          matching: find.byType(RotationTransition),
        );
        return tester.widget<RotationTransition>(glyph).turns.value;
      }

      expect(turnsOf('cardio'), 0);
      expect(turnsOf('rest'), 0.5);
      await tester.tap(byId(header(ReportCard.categories, 'gym')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(turnsOf('gym'), inExclusiveRange(0, 0.5));
      expect(turnsOf('cardio'), 0);
      expect(turnsOf('rest'), 0.5);
      await tester.pumpAndSettle();
      expect(turnsOf('gym'), 0.5);
      expect(turnsOf('cardio'), 0);
      expect(turnsOf('rest'), 0.5);
    });
  });

  group('disclosure rows', () {
    testWidgets('"8 more" and "Show less" announce their fold state and '
        'group; a semantics tap reaches onMore', (tester) async {
      final handle = tester.ensureSemantics();
      final log = await pump(
        tester,
        groupOf(gymDays(12)),
        surface: const Size(360, 1600),
      );
      final id = more(ReportCard.categories, 'gym');
      var data = tester.getSemantics(byId(id)).getSemanticsData();
      expect(data.label, '8 more in Gym');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isExpanded, Tristate.isFalse);

      tester.semantics.performAction(
        find.semantics.byLabel('8 more in Gym'),
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(log.mores, 1);
      data = tester.getSemantics(byId(id)).getSemanticsData();
      expect(data.label, 'Show less of Gym');
      expect(data.flagsCollection.isExpanded, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('German at 2.0 wraps "Weniger anzeigen" to two lines with no '
        'overflow', (tester) async {
      await pump(
        tester,
        groupOf(gymDays(6)),
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(360, 1600),
      );
      await tester.tap(byId(more(ReportCard.categories, 'gym')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = tester.renderObject<RenderParagraph>(
        find.text('Weniger anzeigen'),
      );
      final painter = TextPainter(
        text: label.text,
        textScaler: label.textScaler,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: label.size.width);
      addTearDown(painter.dispose);
      expect(painter.computeLineMetrics(), hasLength(2));
      expect(label.size.height, closeTo(painter.height, 0.5));
    });
  });

  group('header', () {
    testWidgets('one node: the spoken facts, expanded, the id, the tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        groupOf(gymDays(12), count: 14, minutes: 792, missed: 2),
      );
      final node = tester.getSemantics(
        byId(header(ReportCard.categories, 'gym')),
      );
      final data = node.getSemanticsData();
      expect(node.childrenCount, 0);
      expect(data.label, 'Gym, 14 events, 13.2 hours, 2 missed');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isExpanded, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
        0.5,
      );
      handle.dispose();
    });

    testWidgets('the facts per card; the meter only on Categories', (
      tester,
    ) async {
      final rows = gymDays(2);
      await pump(
        tester,
        groupOf(rows, count: 14, minutes: 792, missed: 2),
        fraction: 1,
      );
      expect(find.text(joined(['14', '13.2 h', '2 missed'])), findsOneWidget);
      var meter = tester.widget<FormMeterRow>(find.byType(FormMeterRow));
      expect(meter.fraction, 1);
      expect(meter.label, 'Gym');

      await pump(
        tester,
        groupOf(rows, count: 2, missed: 2),
        card: ReportCard.missed,
      );
      expect(find.text('2 missed'), findsOneWidget);
      meter = tester.widget<FormMeterRow>(find.byType(FormMeterRow));
      expect(meter.fraction, isNull);
      expect(byId(header(ReportCard.missed, 'gym')), findsOneWidget);

      await pump(
        tester,
        groupOf(rows.sublist(0, 1), count: 1, minutes: 60),
        card: ReportCard.ahead,
      );
      expect(find.text(joined(['1', '1 h'])), findsOneWidget);
      expect(
        tester.widget<FormMeterRow>(find.byType(FormMeterRow)).fraction,
        isNull,
      );
      expect(byId(header(ReportCard.ahead, 'gym')), findsOneWidget);
    });

    testWidgets('the header avatar is the category\'s; child rows paint '
        'none', (tester) async {
      await pump(tester, groupOf(gymDays(3)));
      expect(find.byType(EventAvatar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FormMeterRow),
          matching: find.byType(EventAvatar),
        ),
        findsOneWidget,
      );
      // The rows' 40 dp slot stays, so their titles stand at x 70.
      final title = find.descendant(
        of: byId(rowId(gym.id, 1, 1)),
        matching: find.text('Gym'),
      );
      expect(
        tester.getTopLeft(title).dx,
        RowMetrics.groupInset + FormMetrics.dividerIndentTitle,
      );
    });

    testWidgets('the header\'s name, a routine\'s title and the disclosure '
        'label all start at x 70', (tester) async {
      await pump(tester, groupOf([routine, ...gymDays(6)]));
      const x = RowMetrics.groupInset + FormMetrics.dividerIndentTitle;
      final name = find.descendant(
        of: find.byType(FormMeterRow),
        matching: find.text('Gym'),
      );
      final title = find.descendant(
        of: pickerOf(SemanticsIds.reportRoutine(gym.id)),
        matching: find.text('Gym'),
      );
      expect(tester.getTopLeft(name).dx, x);
      expect(tester.getTopLeft(title).dx, x);
      expect(tester.getTopLeft(find.text('3 more')).dx, x);
    });
  });

  group('rows', () {
    testWidgets('a routine aggregate reads the attended count and "8 of 10 '
        'attended · 8 h"; a tap hands it back', (tester) async {
      final log = await pump(tester, groupOf([routine], count: 8));
      final row = byId(SemanticsIds.reportRoutine(gym.id));
      expect(row, findsOneWidget);
      final picker = tester.widget<FormPickerRow>(
        pickerOf(SemanticsIds.reportRoutine(gym.id)),
      );
      expect(picker.value, '8');
      expect(picker.caption, joined(['8 of 10 attended', '8 h']));
      await tester.tap(row);
      expect(log.routines, [routine]);
    });

    testWidgets('a timed one-off reads its day, its start and its duration', (
      tester,
    ) async {
      final row = ReportDatedRow(
        eventId: pt.id,
        day: DateTime.utc(2026, 10, 8),
      );
      final log = await pump(tester, groupOf([row]));
      final id = rowId(pt.id, 10, 8);
      expect(subtitleOf(tester, id), joined(['Thu 8', '17:00', '1 h']));
      await tester.tap(byId(id));
      expect(log.dated, [row]);
    });

    testWidgets('a counted timed repeat puts its count label after the '
        'duration', (tester) async {
      await pump(
        tester,
        groupOf([
          ReportDatedRow(eventId: block.id, day: DateTime.utc(2026, 10, 8)),
        ]),
      );
      expect(
        subtitleOf(tester, rowId(block.id, 10, 8)),
        joined(['Thu 8', '18:00', '1 h', 'Week 3']),
      );
    });

    testWidgets('a birthday reads its count label; a to-do its tasks; the '
        'month joins the day across months', (tester) async {
      final ana = ReportDatedRow(
        eventId: birthday.id,
        day: DateTime.utc(2026, 10, 29),
      );
      final todo = ReportDatedRow(
        eventId: groceries.id,
        day: DateTime.utc(2026, 10, 30),
        tasks: const ReportTaskCount(5, 8),
      );
      await pump(tester, groupOf([ana, todo], categoryId: 'other'));
      expect(
        subtitleOf(tester, rowId(birthday.id, 10, 29)),
        joined(['Thu 29', '32 years']),
      );
      expect(
        subtitleOf(tester, rowId(groceries.id, 10, 30)),
        joined(['Fri 30', '5 of 8 tasks']),
      );

      await pump(
        tester,
        groupOf([ana], categoryId: 'birthday'),
        spansMonths: true,
      );
      expect(
        subtitleOf(tester, rowId(birthday.id, 10, 29)),
        joined(['Thu 29 Oct', '32 years']),
      );
    });

    testWidgets('a Missed row is drawn whole with the presence button, which '
        'asks to mark the day present', (tester) async {
      final day = DateTime.utc(2026, 10, 27);
      final row = ReportDatedRow(eventId: gym.id, day: day, missed: true);
      final log = await pump(
        tester,
        groupOf([row], missed: 1),
        card: ReportCard.missed,
      );
      final id = SemanticsIds.reportRow(gym.id, day);
      expect(
        find.ancestor(of: byId(id), matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        find.descendant(of: byId(id), matching: find.byType(Opacity)),
        findsNothing,
      );
      final button = byId(SemanticsIds.reportRowPresence(gym.id, day));
      expect(button, findsOneWidget);
      expect(find.byIcon(Icons.event_available_rounded), findsOneWidget);
      expect(
        tester
            .widget<FormTrailingButton>(find.byType(FormTrailingButton))
            .tooltip,
        'Mark as present',
      );
      await tester.tap(button);
      expect(log.presence, [(row, false)]);
      expect(log.dated, isEmpty);
    });

    testWidgets('an Ahead row of a tracked event carries no button', (
      tester,
    ) async {
      final day = DateTime.utc(2026, 10, 31);
      await pump(
        tester,
        groupOf([ReportDatedRow(eventId: gym.id, day: day)]),
        card: ReportCard.ahead,
      );
      expect(byId(SemanticsIds.reportRow(gym.id, day)), findsOneWidget);
      expect(byId(SemanticsIds.reportRowPresence(gym.id, day)), findsNothing);
      expect(find.byType(FormTrailingButton), findsNothing);
    });
  });

  group('geometry', () {
    for (final (scale, headerHeight, rowHeight) in [
      (1.0, 66.0, 62.0),
      (1.3, 77.4, 67.0),
      (2.0, 104.0, 94.0),
    ]) {
      testWidgets('at $scale the header is $headerHeight, a row $rowHeight, '
          'a routine row too, the disclosure row at least 48', (tester) async {
        await pump(
          tester,
          groupOf([routine, ...gymDays(6)], count: 14, minutes: 792, missed: 2),
          textScale: scale,
          surface: const Size(360, 1600),
        );
        expect(
          tester.getSize(find.byType(FormMeterRow)).height,
          closeTo(headerHeight, 1),
        );
        final dated = tester.getSize(pickerOf(rowId(gym.id, 1, 1))).height;
        expect(dated, closeTo(rowHeight, 1));
        // Exactly, not within a pixel: "Show less" reads any built child
        // row's height for the rows above the viewport, whatever their kind.
        expect(
          tester.getSize(pickerOf(SemanticsIds.reportRoutine(gym.id))).height,
          dated,
        );
        expect(
          tester.getSize(find.byType(FormActionRow)).height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('German at 2.0 on 360 lays out with no exception '
          '(${brightness.name})', (tester) async {
        await pump(
          tester,
          groupOf([routine, ...gymDays(6)], count: 14, minutes: 792, missed: 2),
          locale: const Locale('de'),
          textScale: 2.0,
          brightness: brightness,
        );
        expect(find.text('3 weitere'), findsOneWidget);
      });
    }

    testWidgets('dark: the group wears the dark row surface at the light '
        'geometry', (tester) async {
      await pump(
        tester,
        groupOf([routine, ...gymDays(6)], count: 14, minutes: 792, missed: 2),
        brightness: Brightness.dark,
      );
      final header = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FormRowShell).first,
              matching: find.byType(Material),
            )
            .first,
      );
      expect(header.color, AppTheme.dark().colorScheme.rowGroup);
      expect(tester.getSize(find.byType(FormMeterRow)).height, closeTo(66, 1));
      expect(
        tester.getSize(pickerOf(rowId(gym.id, 1, 1))).height,
        closeTo(62, 1),
      );
      expect(find.text('3 more'), findsOneWidget);
    });
  });
}
