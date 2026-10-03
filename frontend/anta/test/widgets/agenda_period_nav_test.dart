import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:anta/constants/form_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/agenda_period_nav.dart';

import 'support/layout_errors.dart';

/// The row above a month grid or a year overview, shared by the day list and
/// the overview page. Tier 3 (D6, D11 of
/// `docs/calendar-language-tier-3-roadmap.md`) gave it ids a flow can hit
/// and a title that may take two lines in a box measured over the year's
/// twelve month titles, so paging never moves what sits under the row.
void main() {
  const previousId = 'day-list-nav-previous';
  const nextId = 'day-list-nav-next';
  const todayId = 'day-list-nav-today';
  const titleId = 'day-list-nav-title';

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

  Future<List<FlutterErrorDetails>> pumpNav(
    WidgetTester tester, {
    required String title,
    DateTime? month,
    String? subtitle,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Size? size,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    VoidCallback? onToday,
    VoidCallback? onTitleTap,
    bool withIds = false,
    String? hostIdentifier,
  }) async {
    if (size != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
    }
    return layoutErrorsDuring(() async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Semantics(
              // The day list's `day-list-body` container, as a host.
              identifier: hostIdentifier,
              child: Column(
                children: [
                  AgendaPeriodNav(
                    title: title,
                    month: month,
                    subtitle: subtitle,
                    previousTooltip: 'Previous month',
                    nextTooltip: 'Next month',
                    todayTooltip: 'This month',
                    titleTooltip: 'Jump to a month',
                    onPrevious: onPrevious,
                    onNext: onNext,
                    onToday: onToday,
                    onTitleTap: onTitleTap,
                    previousIdentifier: withIds ? previousId : null,
                    nextIdentifier: withIds ? nextId : null,
                    todayIdentifier: withIds ? todayId : null,
                    titleIdentifier: withIds ? titleId : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  }

  double rowHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AgendaPeriodNav)).height;

  String german(int month) =>
      DateFormat.yMMMM('de').format(DateTime(2026, month));

  testWidgets('the four ids land on the controls, each one node with its '
      'tooltip and its tap', (tester) async {
    var previous = 0, next = 0, today = 0, jumps = 0;
    await pumpNav(
      tester,
      title: 'October 2026',
      month: DateTime.utc(2026, 10, 1),
      onPrevious: () => previous++,
      onNext: () => next++,
      onToday: () => today++,
      onTitleTap: () => jumps++,
      withIds: true,
    );

    expect(dataOf(tester, previousId).tooltip, 'Previous month');
    expect(dataOf(tester, nextId).tooltip, 'Next month');
    expect(dataOf(tester, todayId).tooltip, 'This month');
    final title = dataOf(tester, titleId);
    expect(title.label, contains('October 2026'));
    expect(title.tooltip, 'Jump to a month');
    expect(title.hasAction(SemanticsAction.tap), isTrue);
    for (final id in [previousId, nextId, todayId, titleId]) {
      expect(find.bySemanticsIdentifier(id), findsOneWidget);
      await tester.tap(find.bySemanticsIdentifier(id));
      await tester.pumpAndSettle();
    }
    expect((previous, next, today, jumps), (1, 1, 1, 1));
  });

  testWidgets('without identifiers no node carries one — the overview and '
      'the Dates sheet are untouched', (tester) async {
    await pumpNav(
      tester,
      title: 'October 2026',
      month: DateTime.utc(2026, 10, 1),
      onPrevious: () {},
      onNext: () {},
      onToday: () {},
      onTitleTap: () {},
    );
    for (final id in [previousId, nextId, todayId, titleId]) {
      expect(find.bySemanticsIdentifier(id), findsNothing);
    }
  });

  testWidgets('null callbacks disable the buttons in place, and a title '
      'without a tap is no jump control', (tester) async {
    await pumpNav(tester, title: '2026');

    IconButton button(IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));
    expect(button(Icons.chevron_left_rounded).onPressed, isNull);
    expect(button(Icons.chevron_right_rounded).onPressed, isNull);
    expect(button(Icons.today_rounded).onPressed, isNull);
    expect(find.byIcon(Icons.today_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsNothing);

    await pumpNav(tester, title: '2026', onTitleTap: () {});
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
  });

  testWidgets('at 100 % the measured box is one line: the row is the 48 dp '
      'slot plus its air, for a month and for a year alike', (tester) async {
    await pumpNav(
      tester,
      title: 'September 2026',
      month: DateTime.utc(2026, 9, 1),
      onTitleTap: () {},
    );
    final text = tester.widget<Text>(find.text('September 2026'));
    expect(text.maxLines, FormMetrics.periodTitleMaxLines);
    expect(text.softWrap, isTrue);
    final lineHeight = tester.getSize(find.text('September 2026')).height;
    expect(rowHeight(tester), AgendaPeriodNav.slot + 4);

    await pumpNav(tester, title: '2026', onTitleTap: () {});
    expect(tester.getSize(find.text('2026')).height, lineHeight);
    expect(rowHeight(tester), AgendaPeriodNav.slot + 4);
  });

  testWidgets('on a narrow phone the row is one height for "Juli 2026" and '
      '"September 2026": the box is measured over the year, not the title', (
    tester,
  ) async {
    // At 100 % in the test font "Juli 2026" fits the title's width and
    // "September 2026" takes two lines — the pair that tells a measured box
    // from a content-tall one.
    await pumpNav(
      tester,
      title: german(7),
      month: DateTime.utc(2026, 7, 1),
      locale: const Locale('de'),
      size: const Size(360, 780),
      onTitleTap: () {},
    );
    final oneLine = tester.getSize(find.text('Juli 2026')).height;
    final juli = rowHeight(tester);

    await pumpNav(
      tester,
      title: german(9),
      month: DateTime.utc(2026, 9, 1),
      locale: const Locale('de'),
      size: const Size(360, 780),
      onTitleTap: () {},
    );
    final twoLines = tester.getSize(find.text('September 2026')).height;
    expect(twoLines, moreOrLessEquals(2 * oneLine, epsilon: 0.01));
    expect(rowHeight(tester), juli);
    expect(juli, greaterThan(AgendaPeriodNav.slot + 4));
  });

  testWidgets('at 200 % German on a narrow phone the title wraps to two '
      'lines with no overflow, and every month of the year is one row '
      'height', (tester) async {
    final yearErrors = await pumpNav(
      tester,
      title: '2026',
      locale: const Locale('de'),
      textScale: 2.0,
      size: const Size(360, 780),
      onTitleTap: () {},
    );
    expect(yearErrors, isEmpty);
    final oneLine = tester.getSize(find.text('2026')).height;

    final heights = <double>[];
    double? september;
    for (var month = DateTime.january; month <= DateTime.december; month++) {
      final errors = await pumpNav(
        tester,
        title: german(month),
        month: DateTime.utc(2026, month, 1),
        subtitle: '3 Termine · 1 verpasst',
        locale: const Locale('de'),
        textScale: 2.0,
        size: const Size(360, 780),
        onTitleTap: () {},
      );
      expect(errors, isEmpty, reason: german(month));
      heights.add(rowHeight(tester));
      if (month == DateTime.september) {
        final title = find.text('September 2026');
        september = tester.getSize(title).height;
        expect(
          tester.widget<Text>(title).maxLines,
          FormMetrics.periodTitleMaxLines,
        );
      }
    }
    expect(heights.toSet(), hasLength(1), reason: '$heights');
    expect(september, moreOrLessEquals(2 * oneLine, epsilon: 0.01));
  });

  testWidgets('the count is its own semantics node whatever encloses the '
      'row — never the label of a container above it, as it was under the '
      "day list's body on the device", (tester) async {
    const count = '3 Termine · 1 verpasst';
    await pumpNav(
      tester,
      title: '2026',
      subtitle: count,
      onTitleTap: () {},
      withIds: true,
      hostIdentifier: 'host',
    );
    expect(dataOf(tester, 'host').label, isEmpty);
    expect(find.bySemanticsLabel(count), findsOneWidget);
    expect(dataOf(tester, titleId).label, isNot(contains(count)));
  });

  testWidgets('a count too long for its slot shrinks to fit rather than '
      'cuts, between the chevron and the today slot, and the row is as tall '
      'as with a short count', (tester) async {
    const long = '32 Einträge · 1 verpasst';
    final errors = await pumpNav(
      tester,
      title: '2026',
      subtitle: long,
      locale: const Locale('de'),
      textScale: 2.0,
      size: const Size(360, 780),
      onTitleTap: () {},
    );
    expect(errors, isEmpty);
    final paragraph = tester.renderObject<RenderParagraph>(find.text(long));
    expect(paragraph.didExceedMaxLines, isFalse);
    final drawn = tester.getRect(find.text(long));
    expect(drawn.width, lessThan(paragraph.size.width));
    final previous = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    final today = tester.getRect(
      find.widgetWithIcon(IconButton, Icons.today_rounded),
    );
    expect(drawn.left, greaterThanOrEqualTo(previous.right));
    expect(drawn.right, lessThanOrEqualTo(today.left));
    final tall = rowHeight(tester);

    await pumpNav(
      tester,
      title: '2026',
      subtitle: '8 Einträge',
      locale: const Locale('de'),
      textScale: 2.0,
      size: const Size(360, 780),
      onTitleTap: () {},
    );
    expect(rowHeight(tester), tall);
  });

  testWidgets("a year's twelve titles are laid out once per key: a rebuild or "
      'a page inside the year lays out none, another year, text scale, '
      'locale or width lays them out again', (tester) async {
    // Years no other case shows, so the cache this file shares is cold for
    // them whichever cases ran first.
    final start = AgendaPeriodNav.measurementCount;
    int measured() => AgendaPeriodNav.measurementCount - start;
    Future<void> show(
      String title,
      DateTime month, {
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Size? size,
    }) => pumpNav(
      tester,
      title: title,
      month: month,
      locale: locale,
      textScale: textScale,
      size: size,
      onTitleTap: () {},
    );

    await show('March 2031', DateTime.utc(2031, 3, 1));
    expect(measured(), 1);

    // The same nav rebuilt, as a day tap in the day list rebuilds it.
    await show('March 2031', DateTime.utc(2031, 3, 1));
    expect(measured(), 1);

    // A page inside the year: the builder draws the new title, in the box
    // it already knew.
    final box = rowHeight(tester);
    await show('April 2031', DateTime.utc(2031, 4, 1));
    expect(find.text('April 2031'), findsOneWidget);
    expect(rowHeight(tester), box);
    expect(measured(), 1);

    // A year nav lays out its one title and never asks for a year's twelve.
    await pumpNav(tester, title: '2031', onTitleTap: () {});
    expect(measured(), 1);

    await show('January 2032', DateTime.utc(2032, 1, 1));
    expect(measured(), 2, reason: 'another year');
    await show('January 2032', DateTime.utc(2032, 1, 1), textScale: 2.0);
    expect(measured(), 3, reason: 'another text scale');
    await show(
      'Januar 2032',
      DateTime.utc(2032, 1, 1),
      locale: const Locale('de'),
    );
    expect(measured(), 4, reason: 'another locale');
    await show(
      'January 2032',
      DateTime.utc(2032, 1, 1),
      size: const Size(360, 780),
    );
    expect(measured(), 5, reason: 'another width');

    // Back at the first width — a rotation back — the box is remembered.
    tester.view.reset();
    await show('January 2032', DateTime.utc(2032, 1, 1));
    expect(measured(), 5);
  });

  testWidgets('the remembered boxes are bounded: past the cache size the '
      'least recently shown year is laid out again', (tester) async {
    final start = AgendaPeriodNav.measurementCount;
    int measured() => AgendaPeriodNav.measurementCount - start;
    Future<void> show(int year) => pumpNav(
      tester,
      title: 'January $year',
      month: DateTime.utc(year, 1, 1),
      onTitleTap: () {},
    );

    // One more year than the cache holds, every one new to it.
    const first = 2040;
    const size = AgendaPeriodNav.yearTitleCacheSize;
    for (var year = first; year <= first + size; year++) {
      await show(year);
    }
    expect(measured(), size + 1);

    // The newest is still remembered; the oldest was dropped for it.
    await show(first + size);
    expect(measured(), size + 1);
    await show(first);
    expect(measured(), size + 2);
  });
}
