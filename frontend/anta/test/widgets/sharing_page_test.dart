import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/sync_limits.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/pages/sharing_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/utils/sync_moment_format.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/share_events_sheets.dart';

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
  Future<ShareOverview> overview({bool withCounts = false}) async =>
      throw StateError('the read failed');
}

/// A first read that waits on [overviewHold]: the page before it loads.
class _HeldShareService extends FakeShareService {
  _HeldShareService({super.availability});

  final Completer<void> overviewHold = Completer<void>();

  @override
  Future<ShareOverview> overview({bool withCounts = false}) async {
    final overview = await super.overview(withCounts: withCounts);
    await overviewHold.future;
    return overview;
  }
}

/// Flutter's 4.5:1 text-contrast guideline but for the nodes of [reasons]:
/// their few short words at 13 px give the sampler more anti-aliasing step
/// pixels than core ones (2.16:1 measured, light, on a token far above
/// 4.5:1), so their colour token is pinned instead.
class _ContrastBesideTheReason extends MinimumTextContrastGuideline {
  const _ContrastBesideTheReason(this.reasons);

  final Set<String> reasons;

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) || reasons.contains(data.label);
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

/// One of the partner's own categories, as the reader stores it.
CalendarCategory _theirs(String id, String name) => CalendarCategory(
  id: id,
  name: name,
  colorValue: 0xFF3949AB,
  iconKey: 'work',
  sortOrder: 0,
  isBuiltIn: false,
  fromPartner: true,
);

/// A built-in of mine, which a partner's share of that id joins.
CalendarCategory _builtIn(String id, {required int order}) => CalendarCategory(
  id: id,
  name: id,
  colorValue: 0xFF43A047,
  iconKey: 'fitness_center',
  sortOrder: order,
  isBuiltIn: true,
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

  /// A host page that pushes the Sharing page, as the Pairing row does. The
  /// default surface is a phone's width, tall enough that the list builds
  /// all five sections at 1.0: the receiving half put the last group below
  /// a real phone's fold.
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(412, 1700),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    NavigatorObserver? observer,
    Future<void> Function(BuildContext context)? onOpenEvents,
    bool hostResizes = true,
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
            resizeToAvoidBottomInset: hostResizes,
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SharingPage(
                      pairingBloc: pairingBloc,
                      onOpenEvents: onOpenEvents,
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

  /// The entries of YOU SHARE and the last group, top to bottom.
  const entries = [
    SemanticsIds.sharingMineCategories,
    SemanticsIds.sharingMineEvents,
    SemanticsIds.sharingMineFolders,
    SemanticsIds.sharingStopAll,
    SemanticsIds.sharingUnpair,
  ];

  /// A 360 dp phone with the whole page on screen at 1.0, so the guidelines
  /// and the rects see every section.
  const wholePage = Size(360, 1700);

  /// The seven of sections 2–4, top to bottom.
  const received = [
    SemanticsIds.sharingTheirsCategories,
    SemanticsIds.sharingTheirsEvents,
    SemanticsIds.sharingTheirsFolders,
    SemanticsIds.sharingLookEvents,
    SemanticsIds.sharingLookNotes,
    SemanticsIds.sharingMarkMine,
    SemanticsIds.sharingAlerts,
  ];

  /// Every entry of the page, top to bottom.
  const everyEntry = [
    SemanticsIds.sharingMineCategories,
    SemanticsIds.sharingMineEvents,
    SemanticsIds.sharingMineFolders,
    ...received,
    SemanticsIds.sharingStopAll,
    SemanticsIds.sharingUnpair,
  ];

  List<Rect> rects(WidgetTester tester) => [
    for (final id in everyEntry) tester.getRect(byId(id)),
  ];

  /// "None" in the entry [id], whichever half of the page it stands in.
  Finder saysNone(String id) =>
      find.descendant(of: byId(id), matching: find.text(l10n.shareNone));

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
    folders: const [
      MySharedFolder(id: 'f1', name: 'Trips', parentName: null, noteCount: 3),
    ],
    folderCount: 1,
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
    expect(
      find.descendant(
        of: byId(SemanticsIds.sharingMineFolders),
        matching: find.text('Trips'),
      ),
      findsOneWidget,
    );
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

    expect(saysNone(SemanticsIds.sharingMineCategories), findsOneWidget);
    expect(saysNone(SemanticsIds.sharingMineEvents), findsOneWidget);
    expect(saysNone(SemanticsIds.sharingMineFolders), findsOneWidget);
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
    await open(tester, size: wholePage);
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

  /// A 360 dp phone tall enough that the list builds every entry of the
  /// page at German 2.0 (≈ 2800 dp, the slice C spec §13, before slice F's
  /// three entries).
  const everyEntryBuilt = Size(360, 4400);

  group('heights', () {
    // Measured with Roboto, as a phone lays the words out.
    setUpAll(loadGoldenFonts);

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('at $scale every entry keeps its place and height through '
          'nothing shared, sending and waiting to send', (tester) async {
        await boot(overview: sharing);
        await open(tester, size: everyEntryBuilt, textScale: scale);
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

        // Every entry left is one the push set aside: it goes nowhere until
        // a start or "Sync now", so the header does not say "Sending…".
        await show(
          tester,
          overview: ShareOverview(
            categories: [work],
            sending: true,
            sendingParked: true,
          ),
        );
        expect(drawn(l10n.shareWaitingToSend), 2);
        expect(drawn(l10n.shareSending), 1);
        expect(rects(tester), normal, reason: 'held back');
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
            size: everyEntryBuilt,
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
      'title, what is shared and the reason, and where it goes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await boot(overview: sharing, availability: const ShareNotSyncing(maria));
    await open(tester, size: wholePage);

    for (final (id, title, description, reason) in [
      (
        SemanticsIds.sharingMineCategories,
        l10n.shareRowCategories,
        'Work, Travel',
        l10n.shareNeedsSync,
      ),
      (
        SemanticsIds.sharingMineEvents,
        l10n.shareRowEvents,
        l10n.shareSummaryEvents(2),
        l10n.shareNeedsSync,
      ),
      (
        SemanticsIds.sharingTheirsCategories,
        l10n.shareRowCategories,
        l10n.shareNone,
        l10n.shareNeedsSyncReceive,
      ),
      (
        SemanticsIds.sharingTheirsEvents,
        l10n.shareRowEvents,
        l10n.shareNone,
        l10n.shareNeedsSyncReceive,
      ),
    ]) {
      expect(
        tester.getSemantics(byId(id)),
        matchesSemantics(
          identifier: id,
          label: '$title\n$description\n$reason',
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
    Future<void> shareThenLeave(
      WidgetTester tester, {
      bool hostResizes = true,
    }) async {
      CalendarCategories.updateCache([work, travel]);
      await open(tester, hostResizes: hostResizes);
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

    testWidgets('a refused write says "Turn on sync to share", as the '
        'events sheet says it', (tester) async {
      await boot(overview: ShareOverview(categories: [work]));
      await shareThenLeave(tester);
      share.emit(const ShareNotSyncing(maria));

      await tester.tap(find.text(l10n.undo));
      await settle(tester);

      expect(find.text(l10n.shareNeedsSync), findsOneWidget);
      expect(find.text(l10n.shareChangeFailed), findsNothing);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('a failed write is said over a bottom route that does not '
        'resize, throwing nothing', (tester) async {
      await boot(
        service: _FailingUndoShareService(
          availability: const ShareReady(maria),
        ),
        overview: ShareOverview(categories: [work]),
      );
      await shareThenLeave(tester, hostResizes: false);

      await tester.tap(find.text(l10n.undo));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.shareChangeFailed), findsOneWidget);

      await close(tester);
    });

    testWidgets('tapped after a database switch it writes nothing and says '
        'nothing', (tester) async {
      await boot(overview: ShareOverview(categories: [work]));
      await shareThenLeave(tester);
      DatabaseLifecycle.notifyDatabaseSwitching();

      await tester.tap(find.text(l10n.undo));
      await settle(tester);

      expect(share.undone, isEmpty);
      expect(find.text(l10n.shareChangeFailed), findsNothing);
      expect(tester.takeException(), isNull);

      await close(tester);
    });
  });

  testWidgets('an Undo tapped after a database switch while the page is up '
      'writes nothing', (tester) async {
    CalendarCategories.updateCache([work, travel]);
    await boot(overview: ShareOverview(categories: [work]));
    await open(tester);
    share.nextChange = ShareChange(sharedCategories: [travel]);
    await tester.tap(byId(SemanticsIds.sharingMineCategories));
    await settle(tester);
    await tester.tap(tick('travel'));
    await tester.pump();
    await tester.tap(byId(SemanticsIds.categoryPickDone));
    await settle(tester);
    DatabaseLifecycle.notifyDatabaseSwitching();

    await tester.tap(find.text(l10n.undo));
    await settle(tester);

    expect(share.undone, isEmpty);

    await close(tester);
  });

  testWidgets('while the Single events sheet is up only the sheet says an '
      'Undo that failed, over itself', (tester) async {
    await boot(
      service: _FailingUndoShareService(availability: const ShareReady(maria)),
      overview: sharing,
    );
    await open(
      tester,
      onOpenEvents: (context) =>
          MySharedEventsSheet.show(context, bloc: context.read<ShareBloc>()),
    );
    await tester.tap(byId(SemanticsIds.sharingMineEvents));
    await settle(tester);
    await tester.tap(byId(SemanticsIds.shareEventUnshare('a')));
    await settle(tester);

    await tester.tap(find.text(l10n.undo));
    await settle(tester);

    expect(find.text(l10n.shareChangeFailed), findsOneWidget);
    expect(find.text(l10n.shareChangeFailed).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await close(tester);
  });

  testWidgets('Folders opens my shared folders; while that sheet is up only '
      'the sheet says an Undo that failed, over itself', (tester) async {
    await boot(
      service: _FailingUndoShareService(availability: const ShareReady(maria)),
      overview: sharing,
    );
    await open(tester);
    await tester.tap(byId(SemanticsIds.sharingMineFolders));
    await settle(tester);
    expect(byId(SemanticsIds.shareFoldersSheet), findsOneWidget);

    await tester.tap(byId(SemanticsIds.shareFolderUnshare('f1')));
    await settle(tester);
    expect(share.folderShares, [('f1', false)]);
    await tester.tap(find.text(l10n.undo));
    await settle(tester);

    expect(find.text(l10n.shareChangeFailed), findsOneWidget);
    expect(find.text(l10n.shareChangeFailed).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await close(tester);
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
    for (final id in received) {
      expect(byId(id), findsNothing, reason: id);
    }
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
      expect(saysNone(SemanticsIds.sharingMineCategories), findsOneWidget);
      expect(saysNone(SemanticsIds.sharingMineEvents), findsOneWidget);
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

    group('with an alert of mine armed on what they share (D30, A14)', () {
      final asked =
          '${l10n.pairingUnpairConfirm(userB.displayName!)} '
          '${l10n.pairingRepairHint}';

      testWidgets('the dialog says it turns off, after the re-pair sentence', (
        tester,
      ) async {
        await boot(overview: sharing);
        share.armedByCategory = {'p-night': 1};
        await open(tester);

        await tester.tap(byId(SemanticsIds.sharingUnpair));
        await settle(tester, rounds: 4);

        expect(
          find.text(
            '$asked ${l10n.shareAlertsTurnOffLine(userB.displayName!)}',
          ),
          findsOneWidget,
        );
        expect(share.armedReads, [null]);
        await tester.tap(byId(SemanticsIds.sheetCancel));
        await settle(tester, rounds: 4);

        await close(tester);
      });

      testWidgets('a read that never answers holds the tap only so long — '
          'once, however often it is tapped — and the dialog opens without '
          'the sentence', (tester) async {
        await boot(overview: sharing);
        share.armedByCategory = {'p-night': 1};
        share.armedHold = Completer<void>();
        await open(tester);

        await tester.tap(byId(SemanticsIds.sharingUnpair));
        await tester.pump();
        await tester.tap(byId(SemanticsIds.sharingUnpair));
        await settle(tester, rounds: 2);
        expect(byId(SemanticsIds.sharingUnpairConfirm), findsNothing);

        await tester.pump(SyncLimits.stopConfirmShareRead);
        await settle(tester, rounds: 4);
        expect(find.text(asked), findsOneWidget);
        expect(share.armedReads, [null]);
        await tester.tap(byId(SemanticsIds.sheetCancel));
        await settle(tester, rounds: 4);

        share.armedHold!.complete();
        await close(tester);
      });
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
      for (final id in received) {
        expect(byId(id), findsNothing, reason: id);
      }
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

    testWidgets('a page that opened whole keeps every section as the pair '
        'ends: sharing saying "not paired" first moves nothing, and the '
        'sections stay while the page leaves', (tester) async {
      await boot(overview: sharing);
      await open(tester, size: wholePage);
      final before = rects(tester);

      share.emit(const ShareNotPaired());
      await settle(tester, rounds: 4);
      expect(rects(tester), before);

      pairingBloc.show(const PairingEnded());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      for (final id in everyEntry) {
        expect(byId(id), findsOneWidget, reason: id);
      }

      await settle(tester);
      expect(byId(SemanticsIds.sharingPage), findsNothing);

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

    testWidgets('a confirmation of the page\'s own on top as the pair ends, '
        'before any notice, is never taken for the notice: it goes with the '
        'page', (tester) async {
      await boot(overview: sharing);
      await open(tester);
      await tester.tap(byId(SemanticsIds.sharingStopAll));
      await settle(tester, rounds: 4);
      expect(find.byType(AlertDialog), findsOneWidget);

      pairingBloc.show(const PairingEnded());
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(share.stops, 0);
      expect(find.text('host'), findsOneWidget);

      await close(tester);
    });

    testWidgets('a confirmation of the page\'s own under a route of '
        'another\'s is closed by its handle: the other route stays, and the '
        'confirmation\'s answer does nothing', (tester) async {
      await boot(overview: sharing);
      await open(tester);
      await tester.tap(byId(SemanticsIds.sharingStopAll));
      await settle(tester, rounds: 4);
      expect(find.byType(AlertDialog), findsOneWidget);
      // Not the page's: Sync & sharing's notice, raised before the page
      // hears that the pair has ended.
      final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
      unawaited(
        showDialog<void>(
          context: navigator.context,
          builder: (_) => const Dialog(child: Text('pair ended')),
        ),
      );
      await settle(tester, rounds: 4);

      pairingBloc.show(const PairingEnded());
      await settle(tester);

      expect(find.text('pair ended'), findsOneWidget);
      expect(find.text(l10n.shareStopAllConfirmTitle('Maria')), findsNothing);
      expect(byId(SemanticsIds.sharingPage), findsNothing);
      expect(share.stops, 0);
      expect(tester.takeException(), isNull);

      Navigator.of(tester.element(find.text('pair ended'))).pop();
      await settle(tester, rounds: 4);
      expect(find.text('host'), findsOneWidget);

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

  group('the receiving half', () {
    final night = _theirs('p-night', 'Night shift');
    final family = _theirs('p-family', 'Family');
    final birthday = _builtIn('birthday', order: 1);
    final gymBuiltIn = _builtIn('gym', order: 0);
    PartnerSharedCategory shared(CalendarCategory category) =>
        PartnerSharedCategory(
          category: category,
          joinsMine: category.isBuiltIn,
          shown: true,
          eventCount: 1,
        );

    /// The intro's lines, in the record's order, as [count] says the last.
    List<String> lines(int count) => [
      l10n.shareMaybeStale,
      l10n.shareUpdateApp('Maria'),
      l10n.shareNotShown(count),
    ];

    testWidgets('sections 2–4 stand between YOU SHARE and the last group, in '
        'the record\'s order', (tester) async {
      await boot(overview: sharing);
      await open(tester);

      final headers = [
        l10n.shareYouShare,
        l10n.sharePartnerShares('Maria'),
        l10n.shareLookSection,
        l10n.shareAlertsSection,
        l10n.pairingSection,
      ];
      final headerTops = [
        for (final header in headers)
          tester
              .getTopLeft(find.text(header.toUpperCase(), findRichText: true))
              .dy,
      ];
      final entryTops = [for (final rect in rects(tester)) rect.top];
      for (final tops in [headerTops, entryTops]) {
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]), reason: '$i of $tops');
        }
      }
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('the header says when the partner\'s things were last read, '
        '"Could not check" after a failed read, nothing while not syncing or '
        'never read — in one slot that never changes width', (tester) async {
      final readAt = DateTime.now();
      await boot(overview: ShareOverview(readAt: readAt));
      await open(tester);
      final updated = l10n.shareUpdated(
        formatSyncMoment(
          tester.element(byId(SemanticsIds.sharingPage)),
          readAt,
        ),
      );
      // The first of its texts is the template the slot is sized by.
      Rect slot() => tester.getRect(
        find
            .ancestor(
              of: find.text(l10n.shareCheckFailed).first,
              matching: find.byType(Stack),
            )
            .first,
      );
      final width = slot().width;
      final before = rects(tester);
      expect(painted(tester, updated), 1);
      expect(painted(tester, l10n.shareCheckFailed), 0);

      await show(
        tester,
        overview: ShareOverview(readAt: readAt, readFailed: true),
      );
      expect(painted(tester, l10n.shareCheckFailed), 1);
      expect(painted(tester, updated), 0);
      expect(slot().width, width, reason: 'failed');
      expect(rects(tester), before, reason: 'failed');

      await show(tester, availability: const ShareNotSyncing(maria));
      expect(painted(tester, l10n.shareCheckFailed), 0);
      expect(painted(tester, updated), 0);
      expect(slot().width, width, reason: 'not syncing');
      expect(rects(tester), before, reason: 'not syncing');

      await show(
        tester,
        overview: ShareOverview.empty,
        availability: const ShareReady(maria),
      );
      expect(painted(tester, l10n.shareCheckFailed), 0);
      expect(painted(tester, updated), 0);
      expect(slot().width, width, reason: 'never read');
      expect(rects(tester), before, reason: 'never read');

      await close(tester);
    });

    testWidgets('not syncing: "Turn on sync to receive" stands where the '
        'intro stood', (tester) async {
      await boot(overview: sharing, availability: const ShareNotSyncing(maria));
      await open(tester);

      expect(painted(tester, l10n.shareNeedsSyncReceive), 1);
      expect(painted(tester, l10n.sharePartnerSharesCaption('Maria')), 0);
      expect(
        tileOf(tester, SemanticsIds.sharingTheirsCategories).enabled,
        isFalse,
      );
      expect(tileOf(tester, SemanticsIds.sharingTheirsEvents).enabled, isFalse);

      await show(tester, availability: const ShareReady(maria));
      expect(painted(tester, l10n.shareNeedsSyncReceive), 0);
      expect(painted(tester, l10n.sharePartnerSharesCaption('Maria')), 1);
      expect(
        tileOf(tester, SemanticsIds.sharingTheirsCategories).enabled,
        isTrue,
      );

      await close(tester);
    });

    testWidgets('the lines true at open stand under the intro in order and '
        'are held for the visit: one that clears leaves its space blank', (
      tester,
    ) async {
      final old = DateTime.now().subtract(const Duration(days: 8));
      await boot(
        overview: ShareOverview(
          readAt: old,
          partnerNewerWire: true,
          refusedCount: 2,
        ),
      );
      await open(tester);

      for (final line in lines(2)) {
        expect(painted(tester, line), 1, reason: line);
      }
      // The shown text lies over its template, so the last is the one drawn.
      final tops = [
        for (final line in lines(2)) tester.getTopLeft(find.text(line).last).dy,
      ];
      expect(tops[1], greaterThan(tops[0]));
      expect(tops[2], greaterThan(tops[1]));
      expect(
        tops.first,
        greaterThan(
          tester
              .getTopLeft(
                find.text(l10n.sharePartnerSharesCaption('Maria')).last,
              )
              .dy,
        ),
      );
      final before = rects(tester);

      // Still true, with a new count: said as it stands now.
      await show(
        tester,
        overview: ShareOverview(
          readAt: old,
          partnerNewerWire: true,
          refusedCount: 3,
        ),
      );
      expect(painted(tester, l10n.shareNotShown(3)), 1);
      expect(rects(tester), before, reason: 'a new count');

      await show(tester, overview: ShareOverview(readAt: DateTime.now()));
      for (final line in lines(3)) {
        expect(painted(tester, line), 0, reason: line);
      }
      expect(rects(tester), before, reason: 'every line cleared');
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('a line that comes true mid-visit waits for the next visit, '
        'and a failed read goes to the header', (tester) async {
      await boot(overview: ShareOverview(readAt: DateTime.now()));
      await open(tester);
      final before = rects(tester);

      final old = DateTime.now().subtract(const Duration(days: 8));
      await show(
        tester,
        overview: ShareOverview(
          readAt: old,
          readFailed: true,
          partnerNewerWire: true,
          refusedCount: 2,
        ),
      );
      for (final line in lines(2)) {
        expect(painted(tester, line), 0, reason: line);
      }
      expect(painted(tester, l10n.shareCheckFailed), 1);
      expect(rects(tester), before);

      // The next visit opens on them.
      Navigator.of(tester.element(byId(SemanticsIds.sharingPage))).pop();
      await settle(tester);
      await tester.tap(find.text('host'));
      await settle(tester);
      for (final line in lines(2)) {
        expect(painted(tester, line), 1, reason: line);
      }

      await close(tester);
    });

    testWidgets('the entries name the partner\'s own categories by name, '
        'then the built-ins in my order, on one line, and count the single '
        'events', (tester) async {
      CalendarCategories.updateCache([gymBuiltIn, birthday]);
      await boot(
        overview: ShareOverview(
          partnerCategories: [
            shared(night),
            shared(family),
            shared(birthday),
            shared(gymBuiltIn),
          ],
          partnerEvents: [
            for (final id in ['x', 'y', 'z']) _event(id).event,
          ],
        ),
      );
      await open(tester, size: wholePage);

      expect(
        find.descendant(
          of: byId(SemanticsIds.sharingTheirsCategories),
          matching: find.text('Family, Night shift, Gym, Birthday'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: byId(SemanticsIds.sharingTheirsEvents),
          matching: find.text(l10n.shareSummaryEvents(3)),
        ),
        findsOneWidget,
      );
      final before = rects(tester);

      await show(
        tester,
        overview: ShareOverview(
          partnerCategories: [
            for (var i = 0; i < 12; i++)
              shared(_theirs('p$i', 'Category number $i')),
          ],
        ),
      );
      final names = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: byId(SemanticsIds.sharingTheirsCategories),
          matching: find.textContaining('Category number 0'),
        ),
      );
      expect(names.didExceedMaxLines, isTrue);
      expect(rects(tester), before, reason: 'a long list');

      await show(tester, overview: ShareOverview.empty);
      expect(saysNone(SemanticsIds.sharingTheirsCategories), findsOneWidget);
      expect(saysNone(SemanticsIds.sharingTheirsEvents), findsOneWidget);
      expect(rects(tester), before, reason: 'nothing shared');

      await close(tester);
    });

    testWidgets('Categories opens what the partner shares, Single events '
        'their read-only list', (tester) async {
      CalendarCategories.updateCache([gymBuiltIn, birthday]);
      await boot(overview: ShareOverview(partnerCategories: [shared(night)]));
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingTheirsCategories));
      await settle(tester);
      expect(byId(SemanticsIds.sharedCategoriesSheet), findsOneWidget);
      expect(
        find.text(l10n.shareTheirCategoriesTitle('Maria')),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(byId(SemanticsIds.sharedCategoriesSheet)),
      ).pop();
      await settle(tester);

      await tester.tap(byId(SemanticsIds.sharingTheirsEvents));
      await settle(tester);
      expect(byId(SemanticsIds.sharedEventsSheet), findsOneWidget);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('Folders names the partner\'s top folders on one line and '
        'opens their read-only list; "None" without any', (tester) async {
      await boot(
        overview: const ShareOverview(
          partnerFolders: [
            PartnerSharedFolder(id: 'p1', name: 'Recipes', noteCount: 40),
            PartnerSharedFolder(id: 'p2', name: 'Trips', noteCount: 2),
          ],
        ),
      );
      await open(tester);

      expect(
        find.descendant(
          of: byId(SemanticsIds.sharingTheirsFolders),
          matching: find.text('Recipes, Trips'),
        ),
        findsOneWidget,
      );
      expect(saysNone(SemanticsIds.sharingMineFolders), findsOneWidget);

      await tester.tap(byId(SemanticsIds.sharingTheirsFolders));
      await settle(tester);
      expect(byId(SemanticsIds.sharedFoldersSheet), findsOneWidget);
      expect(byId(SemanticsIds.sharedFolderOpen('p1')), findsOneWidget);
      expect(find.text(l10n.shareFromPartner('Maria')), findsOneWidget);
      Navigator.of(tester.element(byId(SemanticsIds.sharedFoldersSheet))).pop();
      await settle(tester);

      await show(tester, overview: ShareOverview.empty);
      expect(saysNone(SemanticsIds.sharingTheirsFolders), findsOneWidget);
      expect(tester.takeException(), isNull);

      await close(tester);
    });

    testWidgets('not syncing, a dimmed entry goes back to the Sync & sharing '
        'page beneath, opening no sheet', (tester) async {
      await boot(overview: sharing, availability: const ShareNotSyncing(maria));
      final log = _RouteLog();
      await open(tester, observer: log);

      final before = List.of(log.pushed);
      await tester.tap(byId(SemanticsIds.sharingTheirsEvents));
      await settle(tester);
      expect(log.pushed, before);
      expect(log.popped, ['page']);
      expect(find.text('host'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      await close(tester);
    });

    // Review RD2 5: a tap before the first read would write from the
    // shipped value.
    testWidgets('before the first load the look row and the mark switch '
        'stand in place and take no tap', (tester) async {
      final held = _HeldShareService(availability: const ShareReady(maria));
      await boot(service: held, overview: sharing);
      await open(tester);
      final ids = [
        SemanticsIds.sharingLookEvents,
        SemanticsIds.sharingLookNotes,
        SemanticsIds.sharingMarkMine,
      ];
      final before = [for (final id in ids) tester.getRect(byId(id))];

      await tester.tap(
        byId(SemanticsIds.sharingLookEventsChoice('plain')),
        warnIfMissed: false,
      );
      await tester.tap(
        byId(SemanticsIds.sharingLookNotesChoice('plain')),
        warnIfMissed: false,
      );
      await tester.tap(byId(SemanticsIds.sharingMarkMine), warnIfMissed: false);
      await settle(tester, rounds: 4);
      expect(held.look, ShareEventLook.outlined);
      expect(held.notes, ShareNoteLook.avatar);
      expect(held.mine, isTrue);

      held.overviewHold.complete();
      await settle(tester);
      expect([for (final id in ids) tester.getRect(byId(id))], before);

      await tester.tap(byId(SemanticsIds.sharingLookEventsChoice('plain')));
      await settle(tester, rounds: 4);
      expect(held.look, ShareEventLook.plain);

      await close(tester);
    });

    testWidgets('the look row: three segments, the stored one selected; a '
        'tap shows at once and then writes', (tester) async {
      await boot(overview: sharing);
      share.look = ShareEventLook.avatar;
      await open(tester);
      SegmentedButton<ShareEventLook> row() =>
          tester.widget(find.byType(SegmentedButton<ShareEventLook>));

      expect(row().segments.map((s) => s.value), ShareEventLook.values);
      expect(row().selected, {ShareEventLook.avatar});
      expect(row().direction, Axis.horizontal);
      for (final (look, label) in [
        (ShareEventLook.outlined, l10n.shareLookOutlined),
        (ShareEventLook.avatar, l10n.shareLookAvatar),
        (ShareEventLook.plain, l10n.shareLookPlain),
      ]) {
        expect(
          find.descendant(
            of: byId(SemanticsIds.sharingLookEventsChoice(look.name)),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }

      final hold = share.settingsHold = Completer<void>();
      await tester.tap(byId(SemanticsIds.sharingLookEventsChoice('plain')));
      await settle(tester, rounds: 2);
      expect(row().selected, {ShareEventLook.plain});
      expect(share.look, ShareEventLook.avatar, reason: 'not written yet');

      hold.complete();
      await settle(tester, rounds: 4);
      expect(share.look, ShareEventLook.plain);
      expect(row().selected, {ShareEventLook.plain});

      await close(tester);
    });

    testWidgets('the notes\' look row: Avatar and Like mine, the stored one '
        'selected; a tap shows at once and then writes', (tester) async {
      await boot(overview: sharing);
      share.notes = ShareNoteLook.plain;
      await open(tester);
      SegmentedButton<ShareNoteLook> row() =>
          tester.widget(find.byType(SegmentedButton<ShareNoteLook>));

      expect(row().segments.map((s) => s.value), ShareNoteLook.values);
      expect(row().selected, {ShareNoteLook.plain});
      expect(
        find.descendant(
          of: byId(SemanticsIds.sharingLookNotes),
          matching: find.text(l10n.shareNoteLook),
        ),
        findsOneWidget,
      );
      for (final (look, label) in [
        (ShareNoteLook.avatar, l10n.shareLookAvatar),
        (ShareNoteLook.plain, l10n.shareLookPlain),
      ]) {
        expect(
          find.descendant(
            of: byId(SemanticsIds.sharingLookNotesChoice(look.name)),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }

      final hold = share.settingsHold = Completer<void>();
      await tester.tap(byId(SemanticsIds.sharingLookNotesChoice('avatar')));
      await settle(tester, rounds: 2);
      expect(row().selected, {ShareNoteLook.avatar});
      expect(share.notes, ShareNoteLook.plain, reason: 'not written yet');

      hold.complete();
      await settle(tester, rounds: 4);
      expect(share.notes, ShareNoteLook.avatar);
      expect(share.look, ShareEventLook.outlined, reason: 'events untouched');

      await close(tester);
    });

    testWidgets('the mark switch writes at once', (tester) async {
      await boot(overview: sharing);
      await open(tester);
      SwitchListTile mark() => tester.widget<SwitchListTile>(
        find.descendant(
          of: byId(SemanticsIds.sharingMarkMine),
          matching: find.byType(SwitchListTile),
        ),
      );

      expect(mark().value, isTrue);
      expect(find.text(l10n.shareMarkMineDesc), findsOneWidget);

      await tester.tap(byId(SemanticsIds.sharingMarkMine));
      await settle(tester, rounds: 4);
      expect(share.mine, isFalse);
      expect(mark().value, isFalse);

      await close(tester);
    });

    testWidgets('the alerts entry says its value with no chevron; its menu '
        'offers three choices with their lines, the current one ticked, and '
        'a pick writes and shows', (tester) async {
      await boot(overview: sharing);
      await open(tester);
      Finder inAlerts(Finder matching) => find.descendant(
        of: byId(SemanticsIds.sharingAlerts),
        matching: matching,
      );

      expect(inAlerts(find.text(l10n.shareAlertsOwn)), findsOneWidget);
      expect(inAlerts(find.byIcon(Icons.chevron_right_rounded)), findsNothing);

      await tester.tap(byId(SemanticsIds.sharingAlerts));
      await settle(tester, rounds: 6);
      FormMenuItemRow item(String id) => tester.widget<FormMenuItemRow>(
        find.byWidgetPredicate(
          (w) => w is FormMenuItemRow && w.identifier == id,
        ),
      );
      for (final (id, label, caption, checked) in [
        (
          SemanticsIds.sharingAlertsOff,
          l10n.shareAlertsOff,
          l10n.shareAlertsOffDesc,
          false,
        ),
        (
          SemanticsIds.sharingAlertsOwn,
          l10n.shareAlertsOwn,
          l10n.shareAlertsOwnDesc,
          true,
        ),
        (
          SemanticsIds.sharingAlertsCategory,
          l10n.shareAlertsCategory,
          l10n.shareAlertsCategoryDesc,
          false,
        ),
      ]) {
        expect(item(id).label, label);
        expect(item(id).caption, caption);
        expect(item(id).checked, checked, reason: id);
      }

      await tester.tap(byId(SemanticsIds.sharingAlertsCategory));
      await settle(tester, rounds: 6);
      expect(share.shareAlerts, ShareAlerts.category);
      expect(inAlerts(find.text(l10n.shareAlertsCategory)), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(FormMenuItemRow), findsNothing);

      await close(tester);
    });

    testWidgets('switched to Off with alerts of mine armed on what they '
        'share, nothing more is said: its own line says nothing shared rings '
        '(D30)', (tester) async {
      await boot(overview: sharing);
      share.armedByCategory = {'p-night': 2};
      await open(tester);

      await tester.tap(byId(SemanticsIds.sharingAlerts));
      await settle(tester, rounds: 6);
      await tester.tap(byId(SemanticsIds.sharingAlertsOff));
      await settle(tester, rounds: 6);

      expect(share.shareAlerts, ShareAlerts.off);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('are off'), findsNothing);
      expect(find.textContaining('turn off'), findsNothing);
      expect(share.armedReads, isEmpty);

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
          partnerCategories: [
            PartnerSharedCategory(
              category: _theirs('p-a', 'Nachtschichten im Krankenhaus'),
              joinsMine: false,
              shown: true,
              eventCount: 3,
            ),
          ],
          partnerEvents: [_event('b').event],
          sending: true,
          readAt: DateTime.now().subtract(const Duration(days: 8)),
          partnerNewerWire: true,
          refusedCount: 12,
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

    testWidgets('German at 2.0 stacks the look\'s three choices, each whole, '
        'and the whole page lays out with no overflow', (tester) async {
      await boot(
        availability: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maximilian-Alexander',
            members: [],
          ),
        ),
        overview: ShareOverview(
          readAt: DateTime.now().subtract(const Duration(days: 8)),
          partnerNewerWire: true,
          refusedCount: 12,
        ),
      );
      final errors = await layoutErrorsDuring(
        () => open(
          tester,
          size: everyEntryBuilt,
          locale: const Locale('de'),
          textScale: 2.0,
        ),
      );

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      for (final id in everyEntry) {
        expect(byId(id), findsOneWidget, reason: id);
      }
      final row = tester.widget<SegmentedButton<ShareEventLook>>(
        find.byType(SegmentedButton<ShareEventLook>),
      );
      expect(row.direction, Axis.vertical);

      await close(tester);
    });

    for (final dark in [false, true]) {
      testWidgets('every target is 48 dp and labelled, '
          '${dark ? 'dark' : 'light'}', (tester) async {
        final handle = tester.ensureSemantics();
        await boot(overview: sharing);
        await open(tester, size: wholePage, dark: dark);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        await close(tester);
        handle.dispose();
      });
    }

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
          await open(tester, size: wholePage, dark: dark);

          await expectLater(
            tester,
            meetsGuideline(
              _ContrastBesideTheReason({
                l10n.shareNeedsSync,
                l10n.shareNeedsSyncReceive,
              }),
            ),
          );
          if (availability is ShareNotSyncing) {
            // Each reason's token, at full strength, where the sampler
            // cannot judge it.
            for (final text in [
              l10n.shareNeedsSync,
              l10n.shareNeedsSyncReceive,
            ]) {
              final reason = find
                  .text(text)
                  .evaluate()
                  .singleWhere(
                    (element) =>
                        element.findAncestorWidgetOfExactType<Opacity>() ==
                        null,
                  );
              expect(
                (reason.renderObject! as RenderParagraph).text.style?.color,
                Theme.of(reason).colorScheme.onSurfaceVariant,
                reason: text,
              );
            }
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
