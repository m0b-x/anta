import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_group_stack.dart';

import '../goldens/support/golden_fonts.dart';

/// The By tag card through [ReportGroupStack] (S5 §2.2): closed by default
/// (O), its first four tags and the card's own "n more" expanding in place,
/// "Show less" folding back under the finger (S), the fold kept for the
/// visit, the meter's share and [ReportGroupStackState.reveal] — beside a
/// Categories stack that still opens by default.
void main() {
  setUpAll(loadGoldenFonts);

  final today = DateTime.utc(2026, 10, 30);

  final gym = CalendarEvent(
    id: 'e-gym',
    title: 'Gym',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
  );
  final events = {gym.id: gym};

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

  tearDown(() => CalendarCategories.updateCache(const []));

  List<ReportDatedRow> gymDays(int count) => [
    for (var i = 0; i < count; i++)
      ReportDatedRow(eventId: gym.id, day: DateTime.utc(2026, 1, 1 + i)),
  ];

  ReportTag tagOf(String key, {int count = 2, String categoryId = 'gym'}) =>
      ReportTag(
        key: key,
        label: key,
        events: 1,
        count: count,
        minutes: 0,
        lastSeenDay: DateTime.utc(2026, 10, 24),
        categoryIds: [categoryId],
        kind: CategoryKind.social,
        rows: gymDays(count),
      );

  const keys = ['ana', 'bob', 'cat', 'dan', 'eve', 'fay', 'gus', 'hal'];
  final eight = [for (final key in keys) tagOf(key)];

  late ReportGroupFolds folds;
  late ScrollController scroll;
  late List<bool> shrinks;

  setUp(() {
    folds = ReportGroupFolds();
    scroll = ScrollController();
    shrinks = [];
  });

  tearDown(() => scroll.dispose());

  Future<void> pumpStack(
    WidgetTester tester, {
    List<ReportTag>? tags,
    ReportCard card = ReportCard.tags,
    List<ReportCategoryGroup>? groups,
    int? preview = 4,
    double room = 0,
    Size surface = const Size(360, 780),
    Key? key,
    Locale locale = const Locale('en'),
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final shown = tags ?? eight;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Builder(
            builder: (context) => CustomScrollView(
              controller: scroll,
              slivers: [
                // Blank room around the card, so a scroll has somewhere to
                // go either way.
                SliverToBoxAdapter(child: SizedBox(height: room)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RowMetrics.groupInset,
                  ),
                  sliver: ReportGroupStack(
                    key: key,
                    scroll: scroll,
                    folds: folds,
                    card: card,
                    groups: groups ?? ReportGroupStack.tagGroups(shown),
                    tags: card == ReportCard.tags
                        ? {for (final tag in shown) tag.key: tag}
                        : const {},
                    preview: card == ReportCard.tags ? preview : null,
                    events: events,
                    labels: ReportLabels(AppLocalizations.of(context)!),
                    today: today,
                    spansMonths: false,
                    use24Hour: true,
                    // Records whether the card was still expanded when told
                    // it would shrink: the fold must come after the call.
                    onShrink: () => shrinks.add(folds.isTagsExpanded),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(height: room)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);
  Finder header(String key) => byId(SemanticsIds.reportTag(key));
  Finder more() => byId(SemanticsIds.reportTagsMore);
  Finder headers() => find.byType(FormMeterRow);
  Finder tagRow(String key, int day) =>
      byId(SemanticsIds.reportTagRow(key, gym.id, DateTime.utc(2026, 1, day)));

  testWidgets('the tags card opens closed; a header tap opens one for the '
      'visit; a Categories stack still opens by default', (tester) async {
    final two = eight.take(2).toList();
    await pumpStack(tester, tags: two);
    expect(header('ana'), findsOneWidget);
    expect(header('bob'), findsOneWidget);
    expect(tagRow('ana', 1), findsNothing);
    expect(folds.isOpen(ReportCard.tags, 'ana'), isFalse);
    expect(more(), findsNothing, reason: 'two tags need no "n more"');

    await tester.tap(header('ana'));
    await tester.pumpAndSettle();
    expect(tagRow('ana', 1), findsOneWidget);
    expect(tagRow('bob', 1), findsNothing);
    expect(folds.isOpen(ReportCard.tags, 'ana'), isTrue);

    // A refold hands the page a new stack over the same folds.
    await pumpStack(tester, tags: two, key: UniqueKey());
    expect(tagRow('ana', 1), findsOneWidget);
    expect(tagRow('bob', 1), findsNothing);

    await pumpStack(
      tester,
      card: ReportCard.categories,
      groups: [
        ReportCategoryGroup(
          categoryId: 'gym',
          count: 2,
          minutes: 0,
          missed: 0,
          rows: gymDays(2),
        ),
      ],
      key: UniqueKey(),
    );
    expect(folds.isOpen(ReportCard.categories, 'gym'), isTrue);
    expect(
      byId(SemanticsIds.reportRow(gym.id, DateTime.utc(2026, 1, 1))),
      findsOneWidget,
    );
  });

  test('tagGroups keeps the first eight in order, each under its key, '
      'counting its days', () {
    final groups = ReportGroupStack.tagGroups([...eight, tagOf('ivy')]);
    expect(groups.map((group) => group.categoryId), keys);
    expect(groups.first.count, 2);
    expect(groups.first.missed, 0);
    expect(groups.first.rows, eight.first.rows);
  });

  testWidgets('eight tags under a preview of four: four headers and "4 '
      'more"; expanded all eight and "Show less"; "Show less" calls onShrink, '
      'then folds', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpStack(tester, surface: const Size(360, 1200));
    expect(headers(), findsNWidgets(4));
    for (final key in keys.skip(4)) {
      expect(header(key), findsNothing);
    }
    expect(find.text('4 more'), findsOneWidget);
    var data = tester.getSemantics(more()).getSemanticsData();
    expect(data.label, '4 more tags');
    expect(data.flagsCollection.isExpanded, Tristate.isFalse);
    expect(SemanticsIds.reportTagsMore, 'report-tags-more');

    await tester.tap(more());
    await tester.pumpAndSettle();
    expect(headers(), findsNWidgets(8));
    expect(find.text('Show less'), findsOneWidget);
    data = tester.getSemantics(more()).getSemanticsData();
    expect(data.label, 'Show fewer tags');
    expect(data.flagsCollection.isExpanded, Tristate.isTrue);
    expect(folds.isTagsExpanded, isTrue);
    expect(shrinks, isEmpty, reason: 'expanding never shrinks');

    await tester.tap(more());
    await tester.pumpAndSettle();
    expect(shrinks, [true], reason: 'onShrink came before the fold');
    expect(headers(), findsNWidgets(4));
    expect(find.text('4 more'), findsOneWidget);
    expect(folds.isTagsExpanded, isFalse);
    handle.dispose();
  });

  testWidgets('the card\'s disclosure speaks of tags in every locale, never '
      'of the section', (tester) async {
    final handle = tester.ensureSemantics();
    for (final (locale, more4, fewer) in const [
      ('en', '4 more tags', 'Show fewer tags'),
      ('de', '4 weitere Schlagwörter', 'Weniger Schlagwörter anzeigen'),
      ('ro', 'Încă 4 taguri', 'Arată mai puține taguri'),
    ]) {
      folds = ReportGroupFolds();
      await pumpStack(
        tester,
        locale: Locale(locale),
        surface: const Size(360, 1200),
        key: UniqueKey(),
      );
      expect(tester.getSemantics(more()).label, more4, reason: locale);
      await tester.tap(more());
      await tester.pumpAndSettle();
      expect(tester.getSemantics(more()).label, fewer, reason: locale);
    }
    handle.dispose();
  });

  testWidgets('the card\'s "n more" is a card of its own after the gap, '
      'its label where the headers\' names start', (tester) async {
    await pumpStack(tester);
    final shell = tester.widget<FormRowShell>(
      find.ancestor(of: more(), matching: find.byType(FormRowShell)),
    );
    expect(shell.first && shell.last, isTrue);
    final fourth = tester.getRect(header('dan'));
    final disclosure = tester.getRect(
      find.ancestor(of: more(), matching: find.byType(FormActionRow)),
    );
    expect(disclosure.top - fourth.bottom, RowMetrics.groupGap);
    expect(
      tester.getTopLeft(find.text('4 more')).dx,
      tester.getTopLeft(find.text('#ana')).dx,
    );
  });

  testWidgets('the meters share the largest of the card\'s tags, past the '
      'preview too, in the first category\'s colour', (tester) async {
    final tags = [
      tagOf('ana', count: 6),
      tagOf('bob', count: 3, categoryId: 'cardio'),
      ...eight.skip(2).take(3),
      tagOf('fay', count: 12),
    ];
    await pumpStack(tester, tags: tags, surface: const Size(360, 1200));
    FormMeterRow meterOf(String key) => tester.widget<FormMeterRow>(
      find.byWidgetPredicate(
        (widget) =>
            widget is FormMeterRow &&
            widget.identifier == SemanticsIds.reportTag(key),
      ),
    );
    expect(meterOf('ana').fraction, 0.5);
    expect(meterOf('bob').fraction, 0.25);
    expect(
      meterOf('bob').meterColor,
      CalendarCategories.resolve('cardio').color,
    );

    await tester.tap(more());
    await tester.pumpAndSettle();
    expect(meterOf('ana').fraction, 0.5, reason: 'expanding never rescales');
    expect(meterOf('fay').fraction, 1);
  });

  testWidgets('given the scroll, "Show less" jumps back by the tags that '
      'leave, so "4 more" lands where the finger was; expanding moves '
      'nothing', (tester) async {
    await pumpStack(tester, room: 900, surface: const Size(360, 1200));
    scroll.jumpTo(1000);
    await tester.pump();
    await tester.tap(more());
    await tester.pumpAndSettle();
    expect(scroll.offset, 1000, reason: 'expanding never compensates');
    // A leaving tag open, its rows laid out.
    await tester.tap(header('eve'));
    await tester.pumpAndSettle();
    expect(tagRow('eve', 2), findsOneWidget);

    final tapY = tester.getRect(more()).top;
    // From the fifth tag's header to the disclosure: the four leaving
    // groups, their rows and the gap after each.
    final leaving = tapY - tester.getRect(header('eve')).top;
    await tester.tap(more());
    await tester.pump();
    expect(find.text('4 more'), findsOneWidget);
    expect(shrinks, [true]);
    expect(scroll.offset, closeTo(1000 - leaving, 0.01));
    expect(tester.getRect(more()).top, closeTo(tapY, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Show less" with the leaving tags scrolled above the viewport '
      'still holds "4 more" under the finger', (tester) async {
    await pumpStack(tester, room: 900, surface: const Size(360, 1200));
    scroll.jumpTo(900);
    await tester.pump();
    await tester.tap(more());
    await tester.pumpAndSettle();
    // The disclosure near the top, the four leaving headers above it.
    final top = tester.getRect(more()).top;
    scroll.jumpTo(scroll.offset + top - 40);
    await tester.pump();
    expect(header('eve'), findsNothing, reason: 'scrolled off above');
    final tapY = tester.getRect(more()).top;
    await tester.tap(more());
    await tester.pump();
    expect(find.text('4 more'), findsOneWidget);
    expect(tester.getRect(more()).top, closeTo(tapY, 0.01));
  });

  testWidgets('the expansion survives a rebuild through the folds', (
    tester,
  ) async {
    await pumpStack(tester, surface: const Size(360, 1200));
    await tester.tap(more());
    await tester.pumpAndSettle();
    await pumpStack(tester, surface: const Size(360, 1200), key: UniqueKey());
    expect(headers(), findsNWidgets(8));
    expect(find.text('Show less'), findsOneWidget);

    folds = ReportGroupFolds();
    await pumpStack(tester, surface: const Size(360, 1200), key: UniqueKey());
    expect(headers(), findsNWidgets(4));
  });

  testWidgets('closed at 1.0 en, four headers and the disclosure stand 384: '
      '4 × (66 + the 18 gap after each) + 48', (tester) async {
    await pumpStack(tester);
    final first = tester.getRect(header('ana'));
    for (final key in keys.take(4)) {
      expect(tester.getRect(header(key)).height, closeTo(66, 1));
    }
    final disclosure = tester.getRect(
      find.ancestor(of: more(), matching: find.byType(FormActionRow)),
    );
    expect(disclosure.height, closeTo(48, 1));
    expect(disclosure.bottom - first.top, closeTo(384, 1));
  });

  testWidgets('reveal opens a tag past the preview, expands the card and '
      'lands its header at the top', (tester) async {
    final stack = GlobalKey<ReportGroupStackState>();
    await pumpStack(tester, room: 900, key: stack);
    expect(header('gus'), findsNothing);
    stack.currentState!.reveal('gus');
    await tester.pumpAndSettle();
    expect(folds.isTagsExpanded, isTrue);
    expect(folds.isOpen(ReportCard.tags, 'gus'), isTrue);
    expect(tester.getRect(header('gus')).top, closeTo(0, 0.01));
    expect(tagRow('gus', 1), findsOneWidget);

    stack.currentState!.reveal('nobody');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
