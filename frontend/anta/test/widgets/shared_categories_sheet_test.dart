import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/utils/share_copy.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/shared_categories_sheet.dart';
import 'package:anta/widgets/shared_category_sheet.dart';
import 'package:anta/widgets/share_notice_listener.dart';

import '../goldens/support/golden_fonts.dart';
import '../support/fake_share_service.dart';
import 'support/layout_errors.dart';
import 'support/semantics_geometry.dart';

/// The received-categories sheet (share surfaces §6.4, the slice D spec §2):
/// the rows and their order, a switch that writes through the bloc and moves
/// nothing, the two row shapes, the hidden row's dimmed avatar, the empty
/// list, and the measured heights with the real faces.
void main() {
  // The spec's heights were measured with the real faces.
  setUpAll(loadGoldenFonts);

  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [],
  );

  CalendarCategory mine(
    String id, {
    required int order,
    bool builtIn = true,
    bool hidden = false,
    String name = '',
  }) => CalendarCategory(
    id: id,
    name: name.isEmpty ? id : name,
    colorValue: 0xFF43A047,
    iconKey: 'fitness_center',
    sortOrder: order,
    isBuiltIn: builtIn,
    isHidden: hidden,
  );

  CalendarCategory theirs(String id, String name, int order) =>
      CalendarCategory(
        id: id,
        name: name,
        colorValue: 0xFF3949AB,
        iconKey: 'work',
        sortOrder: order,
        isBuiltIn: false,
        fromPartner: true,
      );

  PartnerSharedCategory own(
    String id,
    String name,
    int order, {
    bool shown = true,
    int count = 18,
  }) => PartnerSharedCategory(
    category: theirs(id, name, order),
    joinsMine: false,
    shown: shown,
    eventCount: count,
  );

  PartnerSharedCategory builtIn(
    String id, {
    bool shown = true,
    int count = 9,
  }) => PartnerSharedCategory(
    category: CalendarCategories.byId(id) ?? mine(id, order: 0),
    joinsMine: true,
    shown: shown,
    eventCount: count,
  );

  late FakeShareService service;
  late ShareBloc bloc;

  /// The partner's own two by name, as the overview lists them, then the
  /// built-ins in an order that is not mine.
  ShareOverview overview({Set<String> hidden = const {}}) => ShareOverview(
    partnerCategories: [
      own('p-night', 'Night shift', 1, shown: !hidden.contains('p-night')),
      own('p-family', 'Family', 0, shown: !hidden.contains('p-family')),
      builtIn('birthday', shown: !hidden.contains('birthday')),
      builtIn('gym', shown: !hidden.contains('gym')),
    ],
  );

  setUp(() {
    CalendarCategories.updateCache([
      mine('gym', order: 0),
      mine('birthday', order: 1),
    ]);
    service = FakeShareService(availability: const ShareReady(audience))
      ..shareOverview = overview();
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double scale = 1.0,
    bool dark = false,
    String name = 'Maria',
    Size surface = const Size(360, 780),
    bool settled = true,
    bool noticed = false,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.reset);
    bloc = ShareBloc(
      service: () async => service,
      calendarChanges: const Stream.empty(),
    );
    addTearDown(bloc.close);
    bloc.add(const ShareOpened());
    await tester.runAsync(
      () => bloc.stream.firstWhere((state) => state is ShareLoaded),
    );
    await tester.pumpWidget(
      MaterialApp(
        // [noticed]: the app's notice listener above it, as `main.dart`
        // mounts it, which says what the service tells of.
        navigatorKey: noticed ? AppNavigator.navigatorKey : null,
        navigatorObservers: [
          if (noticed) ...[
            AppNavigator.routeObserver,
            ShareNoticeListener.routes,
          ],
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: noticed
              ? ShareNoticeListener(
                  shareService: () async => service,
                  loadCategories: () async => null,
                  child: child!,
                )
              : child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SharedCategoriesSheet.show(
                context,
                bloc: bloc,
                partner: PartnerLook(name: name),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (!settled) return;
    await tester.pumpAndSettle();
  }

  /// Lets the bloc's write and its reload land.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  final rows = find.byType(FormPickerSwitchRow);

  List<String> labels(WidgetTester tester) => [
    for (final row in tester.widgetList<FormPickerSwitchRow>(rows)) row.label,
  ];

  Finder rowOf(String label) => find.byWidgetPredicate(
    (w) => w is FormPickerSwitchRow && w.label == label,
  );

  /// The product of every `Opacity` above [finder].
  double opacityOver(WidgetTester tester, Finder finder) {
    var product = 1.0;
    for (final opacity in tester.widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )) {
      product *= opacity.opacity;
    }
    return product;
  }

  group('order', () {
    test('the partner\'s own by name — the reader stores them all at one '
        'order — then the built-ins by my page\'s: In use, then Archived', () {
      final ordered = orderSharedCategories(
        [
          own('p-b', 'beta', 0),
          builtIn('gym'),
          own('p-a', 'Alpha', 0),
          builtIn('birthday'),
          builtIn('rest'),
          own('p-c', 'Gamma', 0),
          // A same-named pair keeps one order, by id.
          own('p-z', 'Alpha', 0),
        ],
        [
          mine('gym', order: 0, hidden: true),
          mine('rest', order: 1),
          mine('birthday', order: 2),
          theirs('p-a', 'Alpha', 0),
        ],
      );

      expect(
        [for (final e in ordered) e.category.id],
        ['p-a', 'p-z', 'p-b', 'p-c', 'rest', 'birthday', 'gym'],
      );
    });

    test('a built-in my list does not hold goes last, in the overview\'s '
        'order', () {
      final ordered = orderSharedCategories(
        [builtIn('mobility'), builtIn('cardio'), builtIn('gym')],
        [mine('gym', order: 0)],
      );

      expect(
        [for (final e in ordered) e.category.id],
        ['gym', 'mobility', 'cardio'],
      );
    });
  });

  testWidgets('lists the partner\'s own first, by name, then the built-ins '
      'in my order, each with its count', (tester) async {
    await open(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategoriesSheet),
      findsOneWidget,
    );
    expect(find.text('Categories from Maria'), findsOneWidget);
    expect(
      find.text(
        'Switched-off ones stay off your calendar; Maria never sees what '
        'you hide.',
      ),
      findsOneWidget,
    );
    expect(labels(tester), ['Family', 'Night shift', 'Gym', 'Birthday']);
    expect(
      tester.widget<FormPickerSwitchRow>(rowOf('Night shift')).caption,
      '18 events',
    );
    expect(
      tester.widget<FormPickerSwitchRow>(rowOf('Gym')).caption,
      '9 events · joins your Gym',
    );
    expect(find.byType(FormSearchRow), findsNothing);
  });

  testWidgets('a flip sends the bloc the new value and nothing moves', (
    tester,
  ) async {
    await open(tester);
    final tops = [
      for (final e in rows.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)),
    ];

    service.shareOverview = overview(hidden: {'p-night'});
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategoryShow('p-night')),
    );
    await settle(tester);

    expect(service.shownSets, [('p-night', false)]);
    expect(
      tester.widget<FormPickerSwitchRow>(rowOf('Night shift')).value,
      isFalse,
    );
    expect(labels(tester), ['Family', 'Night shift', 'Gym', 'Birthday']);
    expect([
      for (final e in rows.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)),
    ], tops);
  });

  // Said by the app's notice listener from the service's notice, so no
  // sheet and no bloc needs to be alive when the write lands (D30, A13).
  group('a hide that takes alerts of mine off (D30, A13)', () {
    const said =
        'Night shift is hidden. Your alerts on it are off until you show it '
        'again.';

    setUp(() {
      CalendarCategories.updateCache([
        mine('gym', order: 0),
        mine('birthday', order: 1),
        theirs('p-night', 'Night shift', 1),
        theirs('p-family', 'Family', 0),
      ]);
    });

    Future<void> flip(WidgetTester tester, String id) async {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoryShow(id)),
      );
      await settle(tester);
    }

    testWidgets('one bar says so, over the list', (tester) async {
      service.armedByCategory = {'p-night': 2};
      await open(tester, noticed: true);

      service.shareOverview = overview(hidden: {'p-night'});
      await flip(tester, 'p-night');

      expect(find.text(said).hitTestable(), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoriesSheet),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('over the category\'s own sheet, said once', (tester) async {
      service.armedByCategory = {'p-night': 1};
      await open(tester, noticed: true);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoryRow('p-night')),
      );
      await tester.pumpAndSettle();

      service.shareOverview = overview(hidden: {'p-night'});
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategorySheetShow),
      );
      await settle(tester);

      expect(find.text(said).hitTestable(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the sheet closed before the write landed: said all the '
        'same', (tester) async {
      service.armedByCategory = {'p-night': 2};
      await open(tester, noticed: true);
      final write = service.settingsHold = Completer<void>();

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoryShow('p-night')),
      );
      await tester.pump();
      Navigator.of(
        tester.element(
          find.bySemanticsIdentifier(SemanticsIds.sharedCategoriesSheet),
        ),
      ).pop();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoriesSheet),
        findsNothing,
      );
      expect(find.text(said), findsNothing);

      write.complete();
      await settle(tester);

      expect(find.text(said), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('nothing is said when nothing was armed, nor on showing it '
        'again', (tester) async {
      service.armedByCategory = {'p-family': 1};
      await open(tester, noticed: true);

      service.shareOverview = overview(hidden: {'p-night'});
      await flip(tester, 'p-night');
      expect(find.textContaining('is hidden'), findsNothing);

      service.shareOverview = overview();
      await flip(tester, 'p-night');
      expect(find.textContaining('is hidden'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a hide whose write fails says nothing', (tester) async {
      service.armedByCategory = {'p-night': 2};
      await open(tester, noticed: true);
      service.settingsFailure = StateError('disk full');

      await flip(tester, 'p-night');

      expect(find.textContaining('is hidden'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a row shows what the bloc holds, never a value of its own', (
    tester,
  ) async {
    await open(tester);

    // The service stores the flip but its overview still says shown.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategoryShow('p-night')),
    );
    await settle(tester);

    expect(service.shownSets, [('p-night', false)]);
    expect(
      tester.widget<FormPickerSwitchRow>(rowOf('Night shift')).value,
      isTrue,
    );
  });

  testWidgets('the title is the sheet\'s level-1 heading, as the read '
      'sheet\'s is', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    final title = tester.getSemantics(find.text('Categories from Maria'));
    expect(title, isSemantics(isHeader: true, label: 'Categories from Maria'));
    expect(title.getSemanticsData().headingLevel, 1);
    handle.dispose();
  });

  testWidgets('a shared built-in is one node that toggles from anywhere on '
      'the row', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategoryRow('gym')),
      findsNothing,
    );
    final node = tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.sharedCategoryShow('gym')),
        )
        .getSemanticsData();
    expect(node.label, contains('Gym'));
    expect(node.label, contains('9 events · joins your Gym'));
    expect(node.flagsCollection.isToggled, Tristate.isTrue);

    await tester.tap(find.text('Gym'));
    await settle(tester);

    expect(service.shownSets, [('gym', false)]);
    expect(find.byType(SharedCategorySheet), findsNothing);
    handle.dispose();
  });

  testWidgets('an own category is two nodes: the row opens its sheet, the '
      'switch says what it shows', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    final row = tester
        .getSemantics(
          find.bySemanticsIdentifier(SemanticsIds.sharedCategoryRow('p-night')),
        )
        .getSemanticsData();
    final toggle = tester
        .getSemantics(
          find.bySemanticsIdentifier(
            SemanticsIds.sharedCategoryShow('p-night'),
          ),
        )
        .getSemanticsData();
    expect(row.label, contains('Night shift'));
    expect(row.label, contains('18 events'));
    expect(row.label, isNot(contains('Maria')), reason: 'decision dk');
    expect(toggle.label, 'Show Night shift on my calendar');

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategoryRow('p-night')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SharedCategorySheet), findsOneWidget);
    expect(service.shownSets, isEmpty);
    handle.dispose();
  });

  testWidgets('a hidden row dims its avatar alone', (tester) async {
    service.shareOverview = overview(hidden: {'p-night', 'gym'});
    await open(tester);

    for (final label in ['Night shift', 'Gym']) {
      final row = rowOf(label);
      final avatar = find.descendant(
        of: row,
        matching: find.byType(EventAvatar),
      );
      expect(opacityOver(tester, avatar), 0.38, reason: label);
      final text = find.descendant(of: row, matching: find.text(label));
      expect(opacityOver(tester, text), 1.0, reason: label);
      expect(
        opacityOver(
          tester,
          find.descendant(of: row, matching: find.byType(Switch)),
        ),
        1.0,
      );
    }
    final shown = find.descendant(
      of: rowOf('Family'),
      matching: find.byType(EventAvatar),
    );
    expect(opacityOver(tester, shown), 1.0);
  });

  testWidgets('the avatar follows the look: a ring under Outlined', (
    tester,
  ) async {
    await open(tester);

    for (final avatar in tester.widgetList<EventAvatar>(
      find.byType(EventAvatar),
    )) {
      expect(avatar.outlined, isTrue);
      expect(avatar.semanticsLabel, isNull, reason: 'decision dk');
    }
  });

  testWidgets('empty, it says None', (tester) async {
    service.shareOverview = const ShareOverview();
    await open(tester);

    expect(find.text('None'), findsOneWidget);
    expect(rows, findsNothing);
  });

  testWidgets('✕ closes the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(SharedCategoriesSheet), findsNothing);
  });

  /// The category's sheet opened while this one is still sliding in: this
  /// one reaches its place under that sheet's barrier, which blocks its
  /// semantics, and a row that only moved kept its old transform — a tap
  /// by id (and TalkBack) then aimed below it. The two filter sheets
  /// showed it on the device (2026-11-13).
  testWidgets('a row is reported where it is painted after its sheet opened '
      'while this one was still sliding in', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, settled: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final row = find.bySemanticsIdentifier(
      SemanticsIds.sharedCategoryRow('p-night'),
    );
    final sliding = tester.getRect(row);
    await tester.tapAt(tester.getCenter(row));
    await tester.pumpAndSettle();
    expect(find.byType(SharedCategorySheet), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SharedCategorySheet),
        matching: find.byTooltip('Close'),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byType(SharedCategorySheet), findsNothing);
    final painted = tester.getRect(row);
    expect(
      painted.top,
      lessThan(sliding.top),
      reason: 'the sheet was still on its way up when the row was tapped',
    );
    expect(semanticsGlobalRect(tester.getSemantics(row), tester.view), painted);
    handle.dispose();
  });

  group('measured at 360 × 780 (spec §2)', () {
    for (final dark in [false, true]) {
      for (final (scale, height) in const [
        (1.0, 62.0),
        (1.3, 67.0),
        (2.0, 94.0),
      ]) {
        testWidgets('an own row is $height dp at $scale '
            '(${dark ? 'dark' : 'light'})', (tester) async {
          await open(tester, scale: scale, dark: dark);

          expect(
            tester.getSize(rowOf('Night shift')).height,
            moreOrLessEquals(height, epsilon: 1),
          );
        });
      }
    }

    testWidgets('a built-in row is 62 dp at 1.0', (tester) async {
      await open(tester);

      expect(
        tester.getSize(rowOf('Gym')).height,
        moreOrLessEquals(62, epsilon: 1),
      );
    });

    testWidgets('the box is the editor\'s, whatever it lists', (tester) async {
      await open(tester);
      final full = tester.getSize(find.byType(SharedCategoriesSheet)).height;
      expect(full, moreOrLessEquals(780 * 0.92, epsilon: 1));
    });
  });

  group('large text and long names', () {
    for (final (locale, joins) in const [
      (Locale('en'), '9 events · joins your Gym'),
      (Locale('de'), '9 Ereignisse · in deiner Kategorie Training'),
      (Locale('ro'), '9 evenimente · intră în categoria ta Sală'),
    ]) {
      testWidgets('${locale.languageCode} at 2.0 overflows nothing and cuts '
          'no built-in caption', (tester) async {
        final errors = await layoutErrorsDuring(() async {
          await open(
            tester,
            locale: locale,
            scale: 2.0,
            dark: true,
            name: 'Maximilian-Alexander',
          );
          await tester.drag(
            find
                .descendant(
                  of: find.byType(SharedCategoriesSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
        });

        expect(errors, isEmpty);
        final caption = tester
            .widget<FormPickerSwitchRow>(
              find
                  .byWidgetPredicate(
                    (w) =>
                        w is FormPickerSwitchRow &&
                        w.onTap == null &&
                        w.caption.startsWith('9 '),
                  )
                  .first,
            )
            .caption;
        expect(caption, joins);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: rows, matching: find.byType(RichText)),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: paragraph.text.toPlainText(),
          );
        }
        // The caption under the title names the person whole (decision dd).
        final whole = tester.renderObject<RenderParagraph>(
          find.textContaining('Maximilian-Alexander').last,
        );
        expect(whole.didExceedMaxLines, isFalse);
      });
    }
  });

  // Review RD2 4: the Categories page's separator, whose space before the
  // dot is a no-break one.
  testWidgets('a built-in\'s caption joins its parts as the Categories page '
      'does', (tester) async {
    await open(tester);

    final l10n = lookupAppLocalizations(const Locale('en'));
    final caption = tester.widget<FormPickerSwitchRow>(rowOf('Gym')).caption;
    expect(
      caption,
      ShareCopy.caption([
        l10n.categoryEventCount(9),
        l10n.shareJoinsYours('Gym'),
      ]),
    );
    expect(caption, contains(AppConstants.captionSeparator));
    expect(caption, isNot(contains(' ·')));
  });

  for (final scale in const [1.0, 1.3]) {
    for (final locale in const [Locale('en'), Locale('de')]) {
      testWidgets('at $scale in ${locale.languageCode} a two-digit count\'s '
          'caption wraps as it did with the count bound to its noun', (
        tester,
      ) async {
        service.shareOverview = ShareOverview(
          partnerCategories: [builtIn('gym', count: 12)],
        );
        await open(tester, locale: locale, scale: scale);
        final row = find.byWidgetPredicate(
          (w) => w is FormPickerSwitchRow && w.onTap == null,
        );
        final paragraph = tester
            .renderObjectList<RenderParagraph>(
              find.descendant(of: row, matching: find.byType(RichText)),
            )
            .firstWhere((p) => p.text.toPlainText().contains('·'));
        final caption = paragraph.text.toPlainText();
        expect(caption, startsWith('12 '));
        // The same text with the count's glue as the strings spell it.
        final bound = caption.replaceFirst(' ', ' ');
        List<double> lines(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: paragraph.text.style),
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
          )..layout(maxWidth: paragraph.constraints.maxWidth);
          addTearDown(painter.dispose);
          return [for (final line in painter.computeLineMetrics()) line.width];
        }

        expect(lines(caption), lines(bound));
      });
    }
  }

  testWidgets('a built-in\'s caption wrapped at 2.0 in German at 360 dp '
      'never starts a line with the dot', (tester) async {
    // A count as wide as this makes "123 Ereignisse ·" wider than the
    // column: bound whole, the line breaker cut it just before the dot.
    service.shareOverview = ShareOverview(
      partnerCategories: [builtIn('gym', count: 123)],
    );
    await open(tester, locale: const Locale('de'), scale: 2.0);
    await tester.drag(
      find
          .descendant(
            of: find.byType(SharedCategoriesSheet),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    // The built-in's row is the one with no sheet of its own to open.
    final row = find.byWidgetPredicate(
      (w) => w is FormPickerSwitchRow && w.onTap == null,
    );

    final captions = [
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: row, matching: find.byType(RichText)),
      ))
        if (paragraph.text.toPlainText().contains('·')) paragraph,
    ];
    expect(captions, isNotEmpty);
    for (final paragraph in captions) {
      final text = paragraph.text.toPlainText();
      final firstLine = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 1),
          )
          .single;
      expect(
        paragraph.size.height,
        greaterThan(firstLine.bottom - firstLine.top),
        reason: 'the caption wraps, or the case proves nothing',
      );
      // The dot shares its line with the space before it.
      double lineOf(int offset) => paragraph
          .getOffsetForCaret(TextPosition(offset: offset), Rect.zero)
          .dy;
      final dot = text.indexOf('·');
      expect(
        lineOf(dot),
        lineOf(dot - 1),
        reason: '"$text" starts a line with its dot',
      );
    }
  });

  group('accessibility guidelines', () {
    for (final dark in [false, true]) {
      testWidgets('targets, labels and text contrast '
          '(${dark ? 'dark' : 'light'}), one row hidden', (tester) async {
        final handle = tester.ensureSemantics();
        service.shareOverview = overview(hidden: {'p-family'});
        await open(tester, dark: dark);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
