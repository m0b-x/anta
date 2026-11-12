import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/pages/sharing_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';
import 'support/layout_errors.dart';

/// Takes any pairing state the suite shows it: the pair ending under the
/// page is a state the gateway fake has no call for.
class _ShownPairingBloc extends PairingBloc {
  _ShownPairingBloc({required super.authService, required super.gateway});

  void show(PairingState state) => emit(state);
}

/// A share write that throws, the way to the page's failure snackbar.
class _FailingShareService extends FakeShareService {
  _FailingShareService({super.availability});

  @override
  Future<ShareChange> setCategoriesShared(Set<String> ids) async =>
      throw StateError('the write failed');
}

/// An undo that throws, the way to the failure said after the page left.
class _FailingUndoShareService extends FakeShareService {
  _FailingUndoShareService({super.availability});

  @override
  Future<ShareChange> undo(ShareChange change) async =>
      throw StateError('the undo failed');
}

/// A first read that throws: the page's load fails.
class _UnreadableShareService extends FakeShareService {
  _UnreadableShareService({super.availability});

  @override
  Future<ShareOverview> overview() async => throw StateError('the read failed');
}

/// Flutter's 4.5:1 text-contrast guideline but for the node of [reason]:
/// its few short words at 13 px give the sampler more anti-aliasing step
/// pixels than core ones (2.16:1 measured, light, on a token far above
/// 4.5:1), so its colour token is pinned instead.
class _ContrastBesideTheReason extends MinimumTextContrastGuideline {
  const _ContrastBesideTheReason(this.reason);

  final String reason;

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) || data.label == reason;
}

/// Every route pushed and popped above the host, by its kind.
class _RouteLog extends NavigatorObserver {
  final List<String> pushed = [];
  final List<String> popped = [];

  static String _name(Route<dynamic> route) => switch (route) {
    PageRoute() => 'page',
    RawDialogRoute() => 'dialog',
    _ => 'sheet',
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(_name(route));

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(_name(route));
}

CalendarCategory _category(String id, String name, {bool hidden = false}) =>
    CalendarCategory(
      id: id,
      name: name,
      colorValue: 0xFF1E88E5,
      iconKey: 'event',
      sortOrder: 0,
      isBuiltIn: false,
      isHidden: hidden,
      sharedByMe: true,
    );

MySharedEvent _event(String id) => MySharedEvent(
  event: CalendarEvent(
    id: id,
    title: 'Event $id',
    categoryId: 'other',
    startDate: DateTime(2026, 11, 12),
  ),
  categoryShared: false,
);

/// The Sharing page (`docs/cloud-share-surfaces-roadmap.md` §6.2, slice C:
/// YOU SHARE and the last group) over [FakeShareService] and the pairing
/// fakes: every state of the two sections, their heights held across the
/// states, the tick sheet it opens, its snackbars and Undo, both confirms,
/// and the page leaving when the pair ends.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final l10n = AppLocalizationsEn();
  const maria = ShareAudience(id: 'pair-1', displayName: 'Maria', members: []);
  final work = _category('work', 'Work');
  final travel = _category('travel', 'Travel');
  final gym = _category('gym', 'Gym');

  late AppDatabase db;
  late FakeAuthService auth;
  late FakePairingGateway gateway;
  late FakeShareService share;
  late _ShownPairingBloc pairingBloc;

  /// The account and its pair with Ana, the page's pairing bloc, and the
  /// blocs a pushed Sync & sharing builds through `getIt`.
  Future<void> boot({
    ShareAvailability availability = const ShareReady(maria),
    ShareOverview overview = ShareOverview.empty,
    FakeShareService? service,
  }) async {
    auth = FakeAuthService(user: userA);
    gateway = FakePairingGateway()
      ..seedPair(
        [userA.uid, userB.uid],
        {userB.uid: PairProfile.fromUser(userB)},
      );
    await PairingService.forTesting(
      auth: auth,
      gateway: gateway,
      settings: SettingsService.forTesting(db),
    );
    await CalendarEventService.forTesting(db);
    share = (service ?? FakeShareService(availability: availability))
      ..shareOverview = overview;
    pairingBloc = _ShownPairingBloc(authService: auth, gateway: gateway)
      ..add(const LoadPairing());
    GetIt.I.registerFactory<ShareBloc>(
      () => ShareBloc(
        service: () async => share,
        calendarChanges: const Stream.empty(),
      ),
    );
    GetIt.I.registerFactory<SyncBloc>(() => SyncBloc(authService: auth));
    GetIt.I.registerFactory<PairingBloc>(
      () => PairingBloc(authService: auth, gateway: gateway),
    );
  }

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    CalendarEventService.reset();
    db = await openTestDatabase();
  });

  tearDown(() async {
    await pairingBloc.close();
    await GetIt.I.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    CalendarEventService.reset();
    CalendarCategories.updateCache(const []);
    await gateway.dispose();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes.
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// A host page that pushes the Sharing page, as the Pairing row does.
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    NavigatorObserver? observer,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        navigatorObservers: [?observer],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SharingPage(
                      pairingBloc: pairingBloc,
                      shareService: () async => share,
                    ),
                  ),
                ),
                child: const Text('host'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('host'));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    ScaffoldMessenger.of(
      tester.element(find.byType(Navigator).first),
    ).clearSnackBars();
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  /// A tick sheet row: its name may also stand on the page under it.
  Finder tick(String id) => byId(SemanticsIds.categoryPickRow(id));

  /// The four entries of slice C's two sections, top to bottom.
  const entries = [
    SemanticsIds.sharingMineCategories,
    SemanticsIds.sharingMineEvents,
    SemanticsIds.sharingStopAll,
    SemanticsIds.sharingUnpair,
  ];

  List<Rect> rects(WidgetTester tester) => [
    for (final id in entries) tester.getRect(byId(id)),
  ];

  ListTile tileOf(WidgetTester tester, String id) => tester.widget<ListTile>(
    find.descendant(of: byId(id), matching: find.byType(ListTile)),
  );

  /// How many of [text]'s paragraphs paint: the slot's templates sit under
  /// an `Opacity` of 0.
  int painted(WidgetTester tester, String text) => find
      .text(text)
      .evaluate()
      .where(
        (element) =>
            element.findAncestorWidgetOfExactType<Opacity>()?.opacity != 0,
      )
      .length;

  /// Shows the page a new overview and availability, as a pull would.
  Future<void> show(
    WidgetTester tester, {
    ShareOverview? overview,
    ShareAvailability? availability,
  }) async {
    if (overview != null) share.shareOverview = overview;
    share.emit(availability ?? share.availability);
    await settle(tester, rounds: 4);
  }

  final sharing = ShareOverview(
    categories: [work, travel],
    events: [_event('a'), _event('b')],
  );

  testWidgets('it opens on what is shared: the name in the title, the '
      'intro, the names on one line, the events counted, one shared read', (
    tester,
  ) async {
    await boot(overview: sharing);
    await open(tester);

    expect(find.text(l10n.sharingWithTitle('Maria')), findsOneWidget);
    expect(byId(SemanticsIds.sharingPage), findsOneWidget);
    expect(painted(tester, l10n.shareYouShareCaption('Maria')), 1);
    expect(find.text('Work, Travel'), findsOneWidget);
    expect(find.text(l10n.shareSummaryEvents(2)), findsOneWidget);
    expect(find.text(l10n.shareStopAllDesc), findsOneWidget);
    expect(find.text(l10n.shareUnpairDesc), findsOneWidget);
    for (final id in entries) {
      expect(byId(id), findsOneWidget, reason: id);
      expect(tileOf(tester, id).enabled, isTrue, reason: id);
    }
    expect(share.sharedReads, 1);
    expect(painted(tester, l10n.shareNeedsSync), 0);
    expect(tester.takeException(), isNull);

    await close(tester);
  });

  testWidgets('nothing shared: "None" in both entries and Stop sharing '
      'everything disabled in place, asking nothing', (tester) async {
    await boot();
    await open(tester);

    expect(find.text(l10n.shareNone), findsNWidgets(2));
    expect(tileOf(tester, SemanticsIds.sharingStopAll).enabled, isFalse);

    await tester.tap(byId(SemanticsIds.sharingStopAll));
    await settle(tester, rounds: 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(share.stops, 0);

    await close(tester);
  });

  testWidgets('without a profile name every label says "your partner"', (
    tester,
  ) async {
    await boot(
      availability: const ShareReady(
        ShareAudience(id: 'pair-1', displayName: null, members: []),
      ),
    );
    await open(tester);

    expect(find.text(l10n.sharingWithTitle('your partner')), findsOneWidget);
    expect(
      painted(tester, 'Your partner sees these and cannot change them.'),
      1,
    );

    await close(tester);
  });

  testWidgets('a long list of names stays one line, cut with an ellipsis, '
      'and the entry keeps its height', (tester) async {
    await boot(overview: ShareOverview(categories: [work]));
    await open(tester, size: const Size(360, 780));
    final before = rects(tester);

    await show(
      tester,
      overview: ShareOverview(
        categories: [
          for (var i = 0; i < 12; i++) _category('c$i', 'Category number $i'),
        ],
      ),
    );

    final names = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: byId(SemanticsIds.sharingMineCategories),
        matching: find.textContaining('Category number 0'),
      ),
    );
    expect(names.didExceedMaxLines, isTrue);
    expect(rects(tester), before);

    await close(tester);
  });

  group('heights', () {
    // Measured with Roboto, as a phone lays the words out.
    setUpAll(loadGoldenFonts);

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('at $scale every entry keeps its place and height through '
          'nothing shared, sending and waiting to send', (tester) async {
        // Tall enough that the list builds every entry at 2.0.
        await boot(overview: sharing);
        await open(tester, size: const Size(360, 1600), textScale: scale);
        final normal = rects(tester);
        // The header's slot lays every template out unseen, so a status that
        // shows is its template's text twice.
        int drawn(String status) => find.text(status).evaluate().length;
        expect(drawn(l10n.shareSending), 1);

        await show(tester, overview: ShareOverview.empty);
        expect(rects(tester), normal, reason: 'nothing shared');

        await show(
          tester,
          overview: ShareOverview(categories: [work], sending: true),
        );
        expect(drawn(l10n.shareSending), 2);
        expect(rects(tester), normal, reason: 'sending');

        await show(
          tester,
          overview: ShareOverview(
            categories: [work],
            sending: true,
            offline: true,
          ),
        );
        expect(drawn(l10n.shareWaitingToSend), 2);
        expect(drawn(l10n.shareSending), 1);
        expect(rects(tester), normal, reason: 'waiting to send');
        expect(tester.takeException(), isNull);

        await close(tester);
      });

      for (final locale in const [Locale('en'), Locale('de')]) {
        testWidgets('at $scale in ${locale.languageCode} the entries\' tops '
            'are one whether sync is on or not — mid-visit and at open', (
          tester,
        ) async {
          await boot(overview: sharing);
          await open(
            tester,
            size: const Size(360, 1600),
            locale: locale,
            textScale: scale,
          );
          final ready = rects(tester);

          await show(tester, availability: const ShareNotSyncing(maria));
          expect(rects(tester), ready, reason: 'sync off mid-visit');
          await show(tester, availability: const ShareReady(maria));
          expect(rects(tester), ready, reason: 'sync on again');

          // Opened again on a database that does not sync.
          share.emit(const ShareNotSyncing(maria));
          Navigator.of(tester.element(byId(SemanticsIds.sharingPage))).pop();
          await settle(tester);
          await tester.tap(find.text('host'));
          await settle(tester);
          expect(rects(tester), ready, reason: 'opened not syncing');
          expect(tester.takeException(), isNull);

          await close(tester);
        });
      }
    }
  });

  testWidgets('not syncing: YOU SHARE dims in place, "Turn on sync to share" '
      'standing where the intro stood; a tap goes back to the Sync & sharing '
      'page beneath, pushing nothing', (tester) async {
    await boot(overview: sharing);
    final log = _RouteLog();
    await open(tester, size: const Size(360, 780), observer: log);

    await show(tester, availability: const ShareNotSyncing(maria));

    expect(painted(tester, l10n.shareNeedsSync), 1);
    expect(painted(tester, l10n.shareYouShareCaption('Maria')), 0);
    expect(tileOf(tester, SemanticsIds.sharingMineCategories).enabled, isFalse);
    expect(tileOf(tester, SemanticsIds.sharingMineEvents).enabled, isFalse);
    expect(find.text('Work, Travel'), findsOneWidget);

    // Sync turned on again mid-visit: the intro is back in its slot.
    await show(tester, availability: const ShareReady(maria));
    expect(painted(tester, l10n.shareNeedsSync), 0);
    expect(painted(tester, l10n.shareYouShareCaption('Maria')), 1);
    await show(tester, availability: const ShareNotSyncing(maria));

    final before = List.of(log.pushed);
    await tester.tap(byId(SemanticsIds.sharingMineCategories));
    await settle(tester);
    expect(log.pushed, before, reason: 'no second Sync & sharing');
    expect(log.popped, ['page']);
    expect(byId(SemanticsIds.sharingPage), findsNothing);
    expect(find.text('host'), findsOneWidget);
    expect(find.byType(SyncSettingsPage), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await close(tester);
  });

  testWidgets('a dimmed entry is one enabled button to a screen reader: its '
      'title and the reason, and where it goes', (tester) async {
    final handle = tester.ensureSemantics();
    await boot(overview: sharing, availability: const ShareNotSyncing(maria));
    await open(tester, size: const Size(360, 780));

    for (final (id, title) in [
      (SemanticsIds.sharingMineCategories, l10n.shareRowCategories),
      (SemanticsIds.sharingMineEvents, l10n.shareRowEvents),
    ]) {
      expect(
        tester.getSemantics(byId(id)),
        matchesSemantics(
          identifier: id,
          label: '$title\n${l10n.shareNeedsSync}',
          hint: l10n.shareOpensSyncHint,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
        reason: id,
      );
    }

    await close(tester);
    handle.dispose();
  });

  group('the tick sheet', () {
    testWidgets('Categories opens it titled and captioned, each row with its '
        'event count from the overview, ticked as shared; Done sends the set '
        'and the snackbar says what stopped, with Undo', (tester) async {
      CalendarCategories.updateCache([work, travel, gym]);
      await boot(
        overview: ShareOverview(
          categories: [work, travel],
          eventCounts: const {'work': 1},
        ),
      );
      // The calendar says otherwise: the counts are the overview's.
      await tester.runAsync(
        () async => (await CalendarEventService.getInstance()).upsert(
          CalendarEvent(
            id: 'e1',
            title: 'Standup',
            categoryId: 'travel',
            startDate: DateTime(2026, 11, 12),
          ),
        ),
      );
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);

      expect(byId(SemanticsIds.shareCategoriesSheet), findsOneWidget);
      expect(find.text(l10n.shareCategoriesTitle), findsOneWidget);
      expect(find.text(l10n.shareCategoriesCaption('Maria')), findsOneWidget);
      FormCheckRow row(String label) =>
          tester.widget<FormCheckRow>(find.widgetWithText(FormCheckRow, label));
      expect(row('Work').caption, l10n.categoryEventCount(1));
      expect(row('Travel').caption, l10n.categoryEventCount(0));
      expect(row('Work').checked, isTrue);
      expect(row('Gym').checked, isFalse);
      // A category made inside this sheet must not be shared by Done alone
      // (case C9): the page opens the picker opted out of ticking it.
      expect(
        tester
            .widget<CategoryPickerSheet>(find.byType(CategoryPickerSheet))
            .tickCreated,
        isFalse,
      );

      share.nextChange = ShareChange(
        unsharedCategories: [work],
        keptOnTheirOwn: 2,
      );
      await tester.tap(tick('work'));
      await tester.pump();
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);

      expect(share.categorySets, [
        {'travel'},
      ]);
      final message = l10n.shareStoppedSomeStay('Work', 2);
      expect(
        message,
        'No longer shared: Work. 2 events stay shared on their own.',
      );
      expect(find.text(message), findsOneWidget);

      await tester.tap(find.text(l10n.undo));
      await settle(tester);
      expect(share.undone, [share.nextChange]);

      await close(tester);
    });

    testWidgets('Done on an unchanged set and ✕ write nothing', (tester) async {
      CalendarCategories.updateCache([work, travel]);
      await boot(overview: ShareOverview(categories: [work]));
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);
      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      await tester.tap(byId(SemanticsIds.categoryPickClose));
      await settle(tester);

      expect(share.categorySets, isEmpty);
      expect(find.byType(SnackBar), findsNothing);

      await close(tester);
    });

    testWidgets('sharing says "Sharing Work, Travel with Maria" and stopping '
        '"No longer shared: Gym", each with Undo', (tester) async {
      CalendarCategories.updateCache([work, travel, gym]);
      await boot(overview: ShareOverview(categories: [gym]));
      await open(tester);

      share.nextChange = ShareChange(sharedCategories: [work, travel]);
      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      await tester.tap(tick('work'));
      await tester.tap(tick('travel'));
      await tester.pump();
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);
      expect(find.text('Sharing Work, Travel with Maria'), findsOneWidget);
      expect(find.text(l10n.undo), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(byId(SemanticsIds.sharingPage)),
      ).removeCurrentSnackBar();
      await settle(tester, rounds: 2);

      share.nextChange = ShareChange(unsharedCategories: [gym]);
      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      await tester.tap(tick('gym'));
      await tester.pump();
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);
      expect(find.text('No longer shared: Gym'), findsOneWidget);
      expect(find.text(l10n.undo), findsOneWidget);

      await close(tester);
    });

    testWidgets('a refused write says why and changes nothing on screen', (
      tester,
    ) async {
      CalendarCategories.updateCache([work, travel]);
      await boot(overview: ShareOverview(categories: [work]));
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      // Sync stopped elsewhere while the sheet was up.
      share.emit(const ShareNotSyncing(maria));
      await tester.tap(tick('travel'));
      await tester.pump();
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);

      expect(share.categorySets, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.shareNeedsSync),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.undo), findsNothing);
      expect(find.text('Work'), findsOneWidget);

      await close(tester);
    });

    testWidgets('a failed write says so, with no Undo', (tester) async {
      CalendarCategories.updateCache([work, travel]);
      await boot(
        service: _FailingShareService(availability: const ShareReady(maria)),
        overview: ShareOverview(categories: [work]),
      );
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      await tester.tap(tick('travel'));
      await tester.pump();
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);

      expect(find.text(l10n.shareChangeFailed), findsOneWidget);
      expect(find.text(l10n.undo), findsNothing);
      expect(find.text('Work'), findsOneWidget);

      await close(tester);
    });
  });

  group('an Undo that outlives the page', () {
    /// Shares Travel from the tick sheet, leaves the page under its
    /// snackbar, and lets the page's bloc close.
    Future<void> shareThenLeave(WidgetTester tester) async {
      CalendarCategories.updateCache([work, travel]);
      await open(tester);
      share.nextChange = ShareChange(sharedCategories: [travel]);
      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      await tester.tap(tick('travel'));
      await tester.pump();
      await tester.tap(byId(SemanticsIds.categoryPickDone));
      await settle(tester);
      expect(find.text('Sharing Travel with Maria'), findsOneWidget);

      Navigator.of(tester.element(byId(SemanticsIds.sharingPage))).pop();
      await settle(tester);
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(find.text(l10n.undo), findsOneWidget);
    }

    testWidgets('writes through the service itself once the page has left', (
      tester,
    ) async {
      await boot(overview: ShareOverview(categories: [work]));
      await shareThenLeave(tester);

      await tester.tap(find.text(l10n.undo));
      await settle(tester);

      expect(share.undone, [
        ShareChange(sharedCategories: [travel]),
      ]);
      expect(find.text(l10n.undo), findsNothing);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('says a failed write on the app\'s messenger', (tester) async {
      await boot(
        service: _FailingUndoShareService(
          availability: const ShareReady(maria),
        ),
        overview: ShareOverview(categories: [work]),
      );
      await shareThenLeave(tester);

      await tester.tap(find.text(l10n.undo));
      await settle(tester);

      expect(find.text(l10n.shareChangeFailed), findsOneWidget);
      expect(find.text('host'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await close(tester);
    });
  });

  testWidgets('a load that fails says so in one line, and Unpair is still '
      'offered', (tester) async {
    await boot(
      service: _UnreadableShareService(availability: const ShareReady(maria)),
    );
    await open(tester);

    expect(byId(SemanticsIds.sharingPage), findsOneWidget);
    expect(find.text(l10n.shareLoadFailed), findsOneWidget);
    expect(byId(SemanticsIds.sharingMineCategories), findsNothing);
    expect(byId(SemanticsIds.sharingMineEvents), findsNothing);
    expect(tileOf(tester, SemanticsIds.sharingUnpair).enabled, isTrue);
    expect(tester.takeException(), isNull);

    await close(tester);
  });

  group('the last group', () {
    testWidgets('Stop sharing everything asks first; cancel sends nothing, '
        'confirm clears every mark', (tester) async {
      await boot(overview: sharing);
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingStopAll));
      await settle(tester, rounds: 4);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.shareStopAllConfirmTitle('Maria')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.shareStopAllConfirm('Maria')),
        ),
        findsOneWidget,
      );
      await tester.tap(byId(SemanticsIds.sheetCancel));
      await settle(tester, rounds: 4);
      expect(find.byType(AlertDialog), findsNothing);
      expect(share.stops, 0);

      await tester.tap(byId(SemanticsIds.sharingStopAll));
      await settle(tester, rounds: 4);
      share.shareOverview = ShareOverview.empty;
      await tester.tap(byId(SemanticsIds.sheetConfirm));
      await settle(tester);

      expect(share.stops, 1);
      expect(find.text(l10n.shareNone), findsNWidgets(2));
      expect(tileOf(tester, SemanticsIds.sharingStopAll).enabled, isFalse);

      await close(tester);
    });

    testWidgets('Unpair asks with the re-pair sentence; cancel keeps the '
        'pair, confirm unpairs and closes the page', (tester) async {
      await boot(overview: sharing);
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingUnpair));
      await settle(tester, rounds: 4);
      expect(
        find.text(
          '${l10n.pairingUnpairConfirm(userB.displayName!)} '
          '${l10n.pairingRepairHint}',
        ),
        findsOneWidget,
      );
      await tester.tap(byId(SemanticsIds.sheetCancel));
      await settle(tester, rounds: 4);
      expect(gateway.endedPairs, isEmpty);
      expect(byId(SemanticsIds.sharingPage), findsOneWidget);

      await tester.tap(byId(SemanticsIds.sharingUnpair));
      await settle(tester, rounds: 4);
      await tester.tap(byId(SemanticsIds.sharingUnpairConfirm));
      await settle(tester);

      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(find.text('host'), findsOneWidget);
      expect(gateway.endedPairs, hasLength(1));

      await close(tester);
    });
  });

  testWidgets('a partner with no name is "your partner" in the Unpair '
      'dialog, as every share label says it', (tester) async {
    await boot(overview: sharing);
    await open(tester);
    pairingBloc.show(const PairingPaired());
    await settle(tester, rounds: 2);

    await tester.tap(byId(SemanticsIds.sharingUnpair));
    await settle(tester, rounds: 4);

    expect(
      find.text(
        '${l10n.pairingUnpairConfirm('your partner')} '
        '${l10n.pairingRepairHint}',
      ),
      findsOneWidget,
    );

    await close(tester);
  });

  group('the pair ending while the page is open', () {
    testWidgets('closes it when the pairing bloc says the pair is gone', (
      tester,
    ) async {
      await boot(overview: sharing);
      await open(tester);

      pairingBloc.show(const PairingUnpaired());
      await settle(tester);

      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(find.text('host'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('sharing alone saying "not paired" — a pair another account '
        'made — keeps the page open on the way out of it: the partner named, '
        'YOU SHARE absent, Unpair offered and working', (tester) async {
      await boot(availability: const ShareNotPaired(), overview: sharing);
      await open(tester);

      expect(byId(SemanticsIds.sharingPage), findsOneWidget);
      expect(
        find.text(l10n.sharingWithTitle(userB.displayName!)),
        findsOneWidget,
      );
      expect(byId(SemanticsIds.sharingMineCategories), findsNothing);
      expect(byId(SemanticsIds.sharingMineEvents), findsNothing);
      expect(tileOf(tester, SemanticsIds.sharingStopAll).enabled, isFalse);
      expect(tileOf(tester, SemanticsIds.sharingUnpair).enabled, isTrue);

      await tester.tap(byId(SemanticsIds.sharingUnpair));
      await settle(tester, rounds: 4);
      await tester.tap(byId(SemanticsIds.sharingUnpairConfirm));
      await settle(tester);

      expect(gateway.endedPairs, hasLength(1));
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(find.text('host'), findsOneWidget);

      await close(tester);
    });

    testWidgets('a tick sheet open as the pair ends closes before the page, '
        'and finishing nothing writes nothing', (tester) async {
      CalendarCategories.updateCache([work, travel]);
      await boot(overview: ShareOverview(categories: [work]));
      await open(tester);
      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      expect(byId(SemanticsIds.shareCategoriesSheet), findsOneWidget);
      await tester.tap(tick('travel'));
      await tester.pump();

      pairingBloc.show(const PairingUnpaired());
      await settle(tester);

      expect(byId(SemanticsIds.shareCategoriesSheet), findsNothing);
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(find.text('host'), findsOneWidget);
      expect(share.categorySets, isEmpty);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('a confirm open as the pair ends closes with the page and '
        'stops nothing', (tester) async {
      await boot(overview: sharing);
      await open(tester);
      await tester.tap(byId(SemanticsIds.sharingStopAll));
      await settle(tester, rounds: 4);
      expect(find.byType(AlertDialog), findsOneWidget);

      pairingBloc.show(const PairingSignedOut());
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(share.stops, 0);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('the ended notice raised over a tick sheet stays; the sheet '
        'and the page go', (tester) async {
      CalendarCategories.updateCache([work, travel]);
      await boot(overview: ShareOverview(categories: [work]));
      await open(tester);
      await tester.tap(byId(SemanticsIds.sharingMineCategories));
      await settle(tester);
      showDialog<void>(
        context: tester.element(byId(SemanticsIds.sharingPage)),
        builder: (_) => const AlertDialog(content: Text('ended')),
      );
      await settle(tester, rounds: 2);

      pairingBloc.show(const PairingEnded(partnerName: 'Ana'));
      await settle(tester);

      expect(find.text('ended'), findsOneWidget);
      expect(byId(SemanticsIds.shareCategoriesSheet), findsNothing);
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      Navigator.of(tester.element(find.text('ended'))).pop();
      await settle(tester, rounds: 2);
      expect(find.text('host'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('closes it, under a notice raised over it, leaving the '
        'notice', (tester) async {
      await boot(overview: sharing);
      await open(tester);
      final page = tester.element(byId(SemanticsIds.sharingPage));
      // What Sync & sharing does under the page as the pair ends.
      showDialog<void>(
        context: page,
        builder: (_) => const AlertDialog(content: Text('ended')),
      );
      await settle(tester, rounds: 2);

      pairingBloc.show(const PairingEnded(partnerName: 'Ana'));
      await settle(tester);

      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(find.text('ended'), findsOneWidget);
      Navigator.of(tester.element(find.text('ended'))).pop();
      await settle(tester, rounds: 2);
      expect(find.text('host'), findsOneWidget);

      await close(tester);
    });
  });

  group('large text and the guidelines', () {
    setUpAll(loadGoldenFonts);

    testWidgets('German at 2.0 on 360 × 780 with "Maximilian-Alexander" and '
        'long names lays out with no overflow', (tester) async {
      await boot(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maximilian-Alexander',
            members: [],
          ),
        ),
        overview: ShareOverview(
          categories: [
            _category('a', 'Arbeitsbesprechungen'),
            _category('b', 'Geburtstage der Familie'),
          ],
          events: [_event('a')],
          sending: true,
        ),
      );
      final errors = await layoutErrorsDuring(
        () => open(
          tester,
          size: const Size(360, 780),
          locale: const Locale('de'),
          textScale: 2.0,
        ),
      );

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      final de = lookupAppLocalizations(const Locale('de'));
      expect(
        find.text(de.sharingWithTitle('Maximilian-Alexander')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        byId(SemanticsIds.sharingUnpair),
        200,
        scrollable: find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('every target is 48 dp and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await boot(overview: sharing);
      await open(tester, size: const Size(360, 780));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await close(tester);
      handle.dispose();
    });

    for (final dark in [false, true]) {
      for (final availability in const [
        ShareReady(maria),
        ShareNotSyncing(maria),
      ]) {
        final theme = dark ? 'dark' : 'light';
        final syncing = availability is ShareReady ? 'syncing' : 'not syncing';
        testWidgets('every text meets the contrast guideline, $theme, '
            '$syncing', (tester) async {
          final handle = tester.ensureSemantics();
          await boot(overview: sharing, availability: availability);
          await open(tester, size: const Size(360, 780), dark: dark);

          await expectLater(
            tester,
            meetsGuideline(_ContrastBesideTheReason(l10n.shareNeedsSync)),
          );
          if (availability is ShareNotSyncing) {
            // The reason's token, at full strength, where the sampler
            // cannot judge it.
            final reason = find
                .text(l10n.shareNeedsSync)
                .evaluate()
                .singleWhere(
                  (element) =>
                      element.findAncestorWidgetOfExactType<Opacity>() == null,
                );
            expect(
              (reason.renderObject! as RenderParagraph).text.style?.color,
              Theme.of(reason).colorScheme.onSurfaceVariant,
            );
          }

          await close(tester);
          handle.dispose();
        });
      }
    }
  });

  testWidgets('the page\'s search finds its entries by their words', (
    tester,
  ) async {
    await boot(overview: sharing);
    await open(tester);

    await tester.enterText(find.byType(TextField), 'unpair');
    await settle(tester, rounds: 4);
    expect(byId(SemanticsIds.sharingUnpair), findsOneWidget);
    expect(byId(SemanticsIds.sharingMineCategories), findsNothing);

    await tester.enterText(find.byType(TextField), 'single');
    await settle(tester, rounds: 4);
    expect(byId(SemanticsIds.sharingMineEvents), findsOneWidget);
    expect(byId(SemanticsIds.sharingStopAll), findsNothing);

    await close(tester);
  });
}
