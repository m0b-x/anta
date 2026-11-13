import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/share_events_sheets.dart';

import '../goldens/support/golden_fonts.dart';
import '../support/fake_share_service.dart';

/// The two Single events lists of the Sharing page (the slice C spec §4):
/// mine, whose ✕ un-shares at once with Undo and whose row then leaves, and
/// the partner's, read-only, whose tap opens the event's read sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [],
  );

  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);

  final dinner = CalendarEvent(
    id: 'dinner',
    title: 'Dinner',
    categoryId: 'gym',
    startDate: today.add(const Duration(days: 1)),
    time: const EventTime(startMinute: 19 * 60, durationMinutes: 60),
    markedShared: true,
  );
  final lunch = CalendarEvent(
    id: 'lunch',
    title: 'Lunch',
    categoryId: 'work',
    startDate: today,
    markedShared: true,
  );
  final shift = CalendarEvent(
    id: 'shift',
    title: 'Night shift',
    categoryId: 'theirs',
    startDate: today.add(const Duration(days: 3)),
    fromPartner: true,
  );

  late FakeShareService service;
  late ShareBloc bloc;
  late List<(CalendarEvent, DateTime)> opened;
  final en = lookupAppLocalizations(const Locale('en'));

  CalendarCategory category(String id, String name, int order, bool shared) =>
      CalendarCategory(
        id: id,
        name: name,
        colorValue: 0xFF43A047,
        iconKey: 'event',
        sortOrder: order,
        isBuiltIn: false,
        sharedByMe: shared,
      );

  // The real faces, as the spec measured them: the test font's square
  // glyphs wrap a caption a line earlier than a phone does.
  setUpAll(() async {
    await initializeDateFormatting();
    await loadGoldenFonts();
  });

  setUp(() {
    CalendarCategories.updateCache([
      category('gym', 'Gym', 0, false),
      category('work', 'Work', 1, true),
    ]);
    service = FakeShareService(availability: const ShareReady(audience))
      ..shareOverview = ShareOverview(
        events: [
          MySharedEvent(event: dinner, categoryShared: false),
          MySharedEvent(event: lunch, categoryShared: true),
        ],
        partnerEvents: [shift],
      );
    opened = [];
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  /// Loads the bloc as the Sharing page would, then opens [show] from a
  /// button on a 360 × 780 phone.
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) show, {
    Locale locale = const Locale('en'),
    double scale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openMine(
    WidgetTester tester, {
    Locale? locale,
    double? scale,
    ThemeData? theme,
  }) => open(
    tester,
    (context) => MySharedEventsSheet.show(
      context,
      bloc: bloc,
      onOpen: (_, event, day) async => opened.add((event, day)),
    ),
    locale: locale ?? const Locale('en'),
    scale: scale ?? 1.0,
    theme: theme,
  );

  /// [openMine] with the fake as the service an Undo past a closed bloc
  /// writes through — `show` resolves the app's own.
  Future<void> openMineOnFake(WidgetTester tester) => open(
    tester,
    (context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: MySharedEventsSheet(
          bloc: bloc,
          shareService: () async => service,
        ),
      ),
    ),
  );

  Future<void> openTheirs(
    WidgetTester tester, {
    Locale? locale,
    double? scale,
    ThemeData? theme,
    String partner = 'Maria',
    bool withOpener = true,
  }) => open(
    tester,
    (context) => PartnerSharedEventsSheet.show(
      context,
      bloc: bloc,
      partner: PartnerLook(name: partner),
      onOpen: withOpener
          ? (_, event, day) async => opened.add((event, day))
          : null,
    ),
    locale: locale ?? const Locale('en'),
    scale: scale ?? 1.0,
    theme: theme,
  );

  /// Lets the bloc's write and its reload land.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  FormPickerRow rowOf(WidgetTester tester, String title) =>
      tester.widget<FormPickerRow>(
        find.byWidgetPredicate((w) => w is FormPickerRow && w.label == title),
      );

  Finder unshare(String id) =>
      find.bySemanticsIdentifier(SemanticsIds.shareEventUnshare(id));

  /// The sheet's own ✕ — the snackbar over it carries a Close of its own.
  Finder sheetClose() => find.descendant(
    of: find.byType(FormSheetHeader),
    matching: find.byTooltip('Close'),
  );

  group('my singly shared events', () {
    testWidgets('lists each with its when and a ✕, under "Single events"', (
      tester,
    ) async {
      await openMine(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.shareEventsSheet),
        findsOneWidget,
      );
      expect(find.text('Single events'), findsOneWidget);
      // A heading, like the read sheet's title: a screen reader's headings
      // list holds every share sheet by its name.
      expect(
        tester
            .widget<FormSheetHeader>(find.byType(FormSheetHeader))
            .titleIsHeading,
        isTrue,
      );
      final row = rowOf(tester, 'Dinner');
      expect(row.caption, 'Tomorrow · 7:00 PM – 8:00 PM');
      expect(row.captionWraps, isTrue);
      expect(row.showChevron, isFalse);
      expect(row.trailingButton!.tooltip, 'Stop sharing');
      expect(
        tester.getSize(find.byTooltip('Stop sharing').first),
        const Size.square(FormMetrics.trailingButtonSize),
      );
    });

    testWidgets('an event its category shares too says so in its row', (
      tester,
    ) async {
      await openMine(tester);

      expect(
        rowOf(tester, 'Lunch').caption,
        'Today\nOn for everything in Work',
      );
    });

    testWidgets('the ✕ un-shares at once: the row leaves, the snackbar says '
        'so, and Undo writes it back', (tester) async {
      await openMine(tester);

      await tester.tap(unshare('dinner'));
      await settle(tester);

      expect(service.eventShares, [('dinner', false)]);
      expect(find.text('Dinner'), findsNothing);
      expect(find.text('No longer shared: Dinner'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(service.undone, hasLength(1));
      expect(service.undone.single.unsharedEvents.single.id, 'dinner');
      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('the ✕ on an event its category shares says it stays shared '
        'through the category', (tester) async {
      await openMine(tester);

      await tester.tap(unshare('lunch'));
      await settle(tester);

      expect(service.eventShares, [('lunch', false)]);
      expect(find.text('Lunch stays shared through Work'), findsOneWidget);
    });

    testWidgets('a ✕ the service refuses brings the row back and says why', (
      tester,
    ) async {
      await openMine(tester);
      service.emit(const ShareNotSyncing(audience));

      await tester.tap(unshare('dinner'));
      await settle(tester);

      expect(service.eventShares, isEmpty);
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('Turn on sync to share'), findsOneWidget);
    });

    testWidgets('a ✕ whose write fails brings the row back and says '
        'shareChangeFailed over the sheet', (tester) async {
      await openMine(tester);
      final hold = service.hold = Completer<void>();

      await tester.tap(unshare('dinner'));
      await settle(tester);
      expect(find.text('Dinner'), findsNothing);
      hold.completeError(StateError('disk'));
      await settle(tester);

      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text(en.shareChangeFailed).hitTestable(), findsOneWidget);
      expect(find.text(en.saveStatusError), findsNothing);
    });

    testWidgets('a row comes back on Undo only once the undo was written', (
      tester,
    ) async {
      await openMine(tester);
      await tester.tap(unshare('dinner'));
      await settle(tester);
      final hold = service.hold = Completer<void>();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(service.undone, hasLength(1));
      expect(find.text('Dinner'), findsNothing);

      hold.complete();
      await settle(tester);
      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('an Undo that fails leaves the row out and says '
        'shareChangeFailed over the sheet', (tester) async {
      await openMine(tester);
      await tester.tap(unshare('dinner'));
      await settle(tester);
      final hold = service.hold = Completer<void>();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      hold.completeError(StateError('disk'));
      await settle(tester);

      expect(find.text('Dinner'), findsNothing);
      expect(find.text(en.shareChangeFailed).hitTestable(), findsOneWidget);
    });

    testWidgets('a ✕ on a sheet whose bloc has closed acts on nothing', (
      tester,
    ) async {
      await openMine(tester);
      await tester.runAsync(bloc.close);

      await tester.tap(unshare('dinner'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(service.eventShares, isEmpty);
      expect(find.text('Dinner'), findsOneWidget);
    });

    testWidgets('an Undo tapped after the sheet and the page\'s bloc have '
        'closed writes through the service and throws nothing', (tester) async {
      await openMineOnFake(tester);
      await tester.tap(unshare('dinner'));
      await settle(tester);
      await tester.tap(sheetClose());
      await tester.pumpAndSettle();
      await tester.runAsync(bloc.close);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(service.undone.single.unsharedEvents.single.id, 'dinner');
      expect(find.text(en.shareChangeFailed), findsNothing);
    });

    testWidgets('such an Undo that fails says shareChangeFailed through the '
        'app\'s messenger', (tester) async {
      await openMineOnFake(tester);
      await tester.tap(unshare('dinner'));
      await settle(tester);
      await tester.tap(sheetClose());
      await tester.pumpAndSettle();
      await tester.runAsync(bloc.close);
      final hold = service.hold = Completer<void>();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      hold.completeError(StateError('disk'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(SnackBar, en.shareChangeFailed),
        findsOneWidget,
      );
    });

    testWidgets('a row\'s tap opens the event on the day it names', (
      tester,
    ) async {
      await openMine(tester);

      await tester.tap(find.text('Dinner'));
      await tester.pumpAndSettle();

      expect(opened.single.$1.id, 'dinner');
      expect(opened.single.$2, today.add(const Duration(days: 1)));
    });

    testWidgets('empty, it says one line', (tester) async {
      service.shareOverview = const ShareOverview();
      await openMine(tester);

      expect(find.text('Share an event from its editor.'), findsOneWidget);
      expect(find.byType(FormPickerRow), findsNothing);
    });

    testWidgets('✕ closes the sheet', (tester) async {
      await openMine(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(MySharedEventsSheet), findsNothing);
    });
  });

  group('the partner\'s events', () {
    testWidgets('read-only rows in the partner\'s look, the name in the '
        'caption', (tester) async {
      await openTheirs(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventsSheet),
        findsOneWidget,
      );
      expect(find.text('Single events'), findsOneWidget);
      expect(find.text('From Maria'), findsOneWidget);
      final row = rowOf(tester, 'Night shift');
      expect(row.trailingButton, isNull);
      expect(row.showChevron, isFalse);
      expect(find.byTooltip('Stop sharing'), findsNothing);
    });

    testWidgets('a tap opens the event through the flow, which reads it', (
      tester,
    ) async {
      await openTheirs(tester);

      await tester.tap(find.text('Night shift'));
      await tester.pumpAndSettle();

      expect(opened.single.$1.id, 'shift');
      expect(opened.single.$1.fromPartner, isTrue);
    });

    testWidgets('where the host has no event sheets, a row takes no tap at '
        'all — never one that does nothing', (tester) async {
      await openTheirs(tester, withOpener: false);

      expect(rowOf(tester, 'Night shift').onTap, isNull);
      await tester.tap(find.text('Night shift'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventsSheet),
        findsOneWidget,
      );
    });

    testWidgets('empty, it says None', (tester) async {
      service.shareOverview = const ShareOverview();
      await openTheirs(tester);

      expect(find.text('None'), findsOneWidget);
    });
  });

  for (final mine in const [true, false]) {
    final which = mine ? 'my' : 'the partner\'s';

    testWidgets('$which list in German at 2.0 overflows nothing', (
      tester,
    ) async {
      if (mine) {
        await openMine(tester, locale: const Locale('de'), scale: 2.0);
      } else {
        await openTheirs(tester, locale: const Locale('de'), scale: 2.0);
      }

      expect(tester.takeException(), isNull);
      expect(find.text('Einzelne Ereignisse'), findsOneWidget);
    });

    testWidgets('$which list meets the tap-target and labelled-target '
        'guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      if (mine) {
        await openMine(tester);
      } else {
        await openTheirs(tester);
      }

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('$which list meets the text-contrast guideline in $name', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        // In the test font's solid glyphs: the sampler takes the modes of a
        // text's pixels, and Roboto's anti-aliasing step outnumbers the
        // full-strength pixels of a short 13 px caption ("From Maria" read
        // 2.10:1 in onSurfaceVariant, a token above 7:1), so the real
        // faces would judge the edges rather than the colours.
        final solid = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'FlutterTest'),
        );
        if (mine) {
          await openMine(tester, theme: solid);
        } else {
          await openTheirs(tester, theme: solid);
        }

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('$which list in German at 2.0 cuts nothing of a time, a '
        'long category name or a long partner name', (tester) async {
      CalendarCategories.updateCache([
        category('gym', 'Gym', 0, false),
        category('work', 'Familienangelegenheiten und Arzttermine', 1, true),
      ]);
      if (mine) {
        await openMine(tester, locale: const Locale('de'), scale: 2.0);
      } else {
        await openTheirs(
          tester,
          locale: const Locale('de'),
          scale: 2.0,
          partner: 'Maximilian-Alexander',
        );
      }

      expect(tester.takeException(), isNull);
      final rows = tester.widgetList<FormPickerRow>(find.byType(FormPickerRow));
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final caption = find.text(row.caption!);
        final paragraph = tester.renderObject<RenderParagraph>(caption);
        expect(paragraph.maxLines, isNull, reason: row.caption);
        expect(paragraph.didExceedMaxLines, isFalse, reason: row.caption);
        final rowRect = tester.getRect(
          find.byWidgetPredicate(
            (widget) => widget is FormPickerRow && widget.label == row.label,
          ),
        );
        final captionRect = tester.getRect(caption);
        expect(captionRect.bottom, lessThanOrEqualTo(rowRect.bottom));
        expect(captionRect.right, lessThanOrEqualTo(rowRect.right));
      }
      if (mine) {
        expect(
          rowOf(tester, 'Lunch').caption,
          contains('Familienangelegenheiten und Arzttermine'),
        );
      } else {
        expect(find.text('Von Maximilian-Alexander'), findsOneWidget);
      }
    });
  }

  group('an event with no coming occurrence', () {
    final concert = CalendarEvent(
      id: 'concert',
      title: 'Concert',
      categoryId: 'gym',
      startDate: DateTime.utc(2024, 3, 9),
      markedShared: true,
    );
    final gig = CalendarEvent(
      id: 'gig',
      title: 'Gig',
      categoryId: 'theirs',
      startDate: DateTime.utc(2024, 3, 9),
      fromPartner: true,
    );

    setUp(() {
      service.shareOverview = ShareOverview(
        events: [MySharedEvent(event: concert, categoryShared: false)],
        partnerEvents: [gig],
      );
    });

    testWidgets('shows its date with the year in my list', (tester) async {
      await openMine(tester);
      expect(rowOf(tester, 'Concert').caption, 'Mar 9, 2024');
    });

    testWidgets('shows its date with the year in the partner\'s list, in '
        'the locale\'s own order', (tester) async {
      await openTheirs(tester, locale: const Locale('de'));
      expect(rowOf(tester, 'Gig').caption, '9. März 2024');
    });
  });
}
