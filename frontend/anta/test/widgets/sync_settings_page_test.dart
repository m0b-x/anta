import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_theme.dart';
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
import 'package:anta/models/sync_binding.dart';
import 'package:anta/pages/sharing_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/utils/auth_error.dart';
import 'package:anta/utils/data_notice.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/share_events_sheets.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';
import 'support/layout_errors.dart';

/// An account whose sign-in fails offline, the way to the failure row and
/// its Retry button.
class _OfflineAuthService extends FakeAuthService {
  @override
  Future<AppUser?> signInWithGoogle() async =>
      throw const AuthException(AuthError.offline);
}

/// Keeps every event the page sends, so a cancelled dialog can be shown to
/// have sent none.
class _RecordingSyncBloc extends SyncBloc {
  _RecordingSyncBloc({required super.authService});

  final List<SyncEvent> events = [];

  /// Puts the page in a state the account fakes cannot reach — a database
  /// bound to a space, whose stop row asks before it stops.
  void show(SyncState state) => emit(state);

  @override
  void onEvent(SyncEvent event) {
    events.add(event);
    super.onEvent(event);
  }
}

/// Counts who listens to its states, so a wait that ended can be shown to
/// have left no subscription behind.
class _ListenedShareBloc extends ShareBloc {
  _ListenedShareBloc({super.service, super.calendarChanges});

  int listeners = 0;

  @override
  Stream<ShareState> get stream {
    final source = super.stream;
    late StreamSubscription<ShareState> forwarding;
    late final StreamController<ShareState> out;
    out = StreamController<ShareState>(
      sync: true,
      onListen: () {
        listeners++;
        forwarding = source.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
      },
      onCancel: () {
        listeners--;
        return forwarding.cancel();
      },
    );
    return out.stream;
  }
}

class _RecordingPairingBloc extends PairingBloc {
  _RecordingPairingBloc({required super.authService, required super.gateway});

  final List<PairingEvent> events = [];

  @override
  void onEvent(PairingEvent event) {
    events.add(event);
    super.onEvent(event);
  }

  /// Puts the page in a state the fakes pass through too fast to catch — a
  /// request in flight.
  void show(PairingState state) => emit(state);
}

/// The Sharing page's smoke suite (D14 of `docs/settings-rework-roadmap.md`):
/// it opens signed out and signed in, measures at de 2.0 on the small phone,
/// and its confirmations — sign out, paired or not, and unpair — cancel with
/// no event to either bloc and no write to the account or the gateway. Since
/// S6 each action is its row's tap, the action's word the row's value.
///
/// The page builds its own blocs through `getIt`, so the suite registers
/// factories that hand out recording blocs over the pairing fakes, and binds
/// `PairingService` to an in-memory database before the page asks for it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeAuthService auth;
  late FakePairingGateway gateway;
  late SettingsService settings;
  _RecordingSyncBloc? syncBloc;
  _RecordingPairingBloc? pairingBloc;
  late FakeShareService share;
  var shareBlocs = 0;

  /// The share bloc the page built first — its own.
  _ListenedShareBloc? pageShare;

  /// While set, every share read waits on it: the page's first load has
  /// not landed until a case completes it.
  Completer<void>? shareGate;

  /// Whether sharing cannot be opened: every load ends failed.
  var shareFails = false;

  final l10n = AppLocalizationsEn();

  /// Binds the account, the pairing singleton and the two bloc factories;
  /// [paired] plants an active pair with Ana, which the first load adopts;
  /// [available] false is a build without sync, the QA build's state.
  ///
  /// The share bloc's factory counts what it builds: a page that never
  /// paired must build none. Paired, sharing reads as ready with Ana and
  /// [overview] as what this database shares.
  Future<void> boot({
    AppUser? user,
    bool paired = false,
    bool offline = false,
    bool available = true,
    ShareOverview overview = ShareOverview.empty,
  }) async {
    share = FakeShareService(
      availability: paired
          ? ShareReady(
              ShareAudience(
                id: 'pair-1',
                displayName: userB.displayName,
                members: const [],
              ),
            )
          : const ShareNotPaired(),
    )..shareOverview = overview;
    shareBlocs = 0;
    pageShare = null;
    shareGate = null;
    shareFails = false;
    GetIt.I.registerFactory<ShareBloc>(() {
      shareBlocs++;
      final bloc = _ListenedShareBloc(
        service: () async {
          await shareGate?.future;
          if (shareFails) throw StateError('sharing not opened');
          return share;
        },
        calendarChanges: const Stream.empty(),
      );
      pageShare ??= bloc;
      return bloc;
    });
    auth = offline
        ? _OfflineAuthService()
        : FakeAuthService(available: available, user: user);
    gateway = FakePairingGateway();
    if (paired) {
      gateway.seedPair(
        [userA.uid, userB.uid],
        {userB.uid: PairProfile.fromUser(userB)},
      );
    }
    settings = SettingsService.forTesting(db);
    await PairingService.forTesting(
      auth: auth,
      gateway: gateway,
      settings: settings,
    );
    GetIt.I.registerFactory<SyncBloc>(
      () => syncBloc = _RecordingSyncBloc(authService: auth),
    );
    GetIt.I.registerFactory<PairingBloc>(
      () => pairingBloc = _RecordingPairingBloc(
        authService: auth,
        gateway: gateway,
      ),
    );
  }

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    syncBloc = null;
    pairingBloc = null;
    db = await openTestDatabase();
  });

  tearDown(() async {
    await GetIt.I.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    await gateway.dispose();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const SyncSettingsPage(),
      ),
    );
    await settle(tester);
  }

  /// The paired row's description as drawn: its slot lays the summary's
  /// templates out unseen beside it, so the words are read off the row's
  /// own text, the last after its title.
  String summaryOf(WidgetTester tester) => tester
      .widgetList<HighlightedText>(
        find.descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
          matching: find.byType(HighlightedText),
        ),
      )
      .last
      .text;

  /// The ended notice's title; the paired row draws the same words.
  Finder notice() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(l10n.pairingEndedTitle),
  );

  Future<void> answerDialog(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await settle(tester);
  }

  testWidgets('signed out, it opens with the sign-in row and the pairing row '
      'disabled', (tester) async {
    await boot();
    await pumpPage(tester);

    expect(syncBloc!.state, const SyncSignedOut());
    expect(pairingBloc!.state, const PairingSignedOut());
    expect(find.text(l10n.signInWithGoogle), findsOneWidget);
    expect(find.text(l10n.pairingSignInFirst), findsOneWidget);
    expect(find.text(l10n.signOut), findsNothing);
    expect(find.bySemanticsIdentifier(SemanticsIds.sharingSignIn), findsOne);
    expect(find.bySemanticsIdentifier(SemanticsIds.sharingList), findsOne);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('without sync, it opens on the disabled unavailable row, '
      'identified, and no pairing section', (tester) async {
    await boot(available: false);
    await pumpPage(tester);

    expect(syncBloc!.state, const SyncUnavailable());
    expect(find.text(l10n.syncUnavailablePlatform), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text(l10n.syncUnavailablePlatform),
              matching: find.byType(ListTile),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharingUnavailable),
      findsOne,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharingSignIn),
      findsNothing,
    );
    expect(pairingBloc!.state, const PairingUnavailable());
    expect(find.bySemanticsIdentifier(SemanticsIds.sharingPair), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signed in and paired, it opens with the account reading its '
      'action and the partner\'s row saying what is shared, a chevron in '
      'place of Unpair', (tester) async {
    await boot(user: userA, paired: true);
    await pumpPage(tester);

    expect(syncBloc!.state, isA<SyncSignedIn>());
    expect(pairingBloc!.state, isA<PairingPaired>());
    expect(find.text(userA.displayName!), findsOneWidget);
    expect(find.text(l10n.pairingPairedWith(userB.displayName!)), findsOne);
    expect(find.byType(TextButton), findsNothing);
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.sharingSignOut),
        matching: find.text(l10n.signOut),
      ),
      findsOneWidget,
    );
    expect(summaryOf(tester), l10n.shareNothingYet);
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.unpair), findsNothing);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharingUnpair),
      findsNothing,
    );
    // The page's load, never the Sharing page's shared read.
    expect(share.sharedReads, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('never paired, no share bloc is built and the pairing row is '
      'today\'s', (tester) async {
    await boot(user: userA);
    await pumpPage(tester);

    expect(pairingBloc!.state, isA<PairingUnpaired>());
    expect(shareBlocs, 0);
    expect(share.overviews, 0);
    expect(find.text(l10n.pairingNotPairedDesc), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.sharingPair), findsOne);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the paired row sums up what is shared from plural parts, at '
      'one height with and without, and opens the Sharing page', (
    tester,
  ) async {
    CalendarEvent event(String id) => CalendarEvent(
      id: id,
      title: id,
      categoryId: 'other',
      startDate: DateTime(2026, 11, 12),
    );
    const category = CalendarCategory(
      id: 'work',
      name: 'Work',
      colorValue: 0xFF1E88E5,
      iconKey: 'event',
      sortOrder: 0,
      isBuiltIn: false,
    );
    await boot(
      user: userA,
      paired: true,
      overview: ShareOverview(
        categories: const [category, category, category],
        events: [
          MySharedEvent(event: event('a'), categoryShared: false),
          MySharedEvent(event: event('b'), categoryShared: false),
        ],
      ),
    );
    await pumpPage(tester);
    final paired = find.bySemanticsIdentifier(SemanticsIds.sharingPaired);

    expect(
      summaryOf(tester),
      '${l10n.shareSummaryCategories(3)}, ${l10n.shareSummaryEvents(2)}',
    );
    final withSummary = tester.getRect(paired);

    share.shareOverview = ShareOverview(
      events: [MySharedEvent(event: event('a'), categoryShared: false)],
    );
    share.emit(share.availability);
    await settle(tester, rounds: 4);
    expect(summaryOf(tester), l10n.shareSummaryEvents(1));
    share.shareOverview = ShareOverview.empty;
    share.emit(share.availability);
    await settle(tester, rounds: 4);
    expect(summaryOf(tester), l10n.shareNothingYet);
    expect(tester.getRect(paired), withSummary);

    share.shareOverview = ShareOverview(
      events: [MySharedEvent(event: event('a'), categoryShared: false)],
    );
    await tester.tap(paired);
    await settle(tester);
    expect(find.byType(SharingPage), findsOneWidget);
    expect(share.sharedReads, 1);

    // Its Single events entry opens the sheet of the events shared one by
    // one, whose rows are read rows: only their ✕ acts.
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sharingMineEvents),
    );
    await settle(tester);
    final sheet = find.byType(MySharedEventsSheet);
    expect(sheet, findsOneWidget);
    final row = tester.widget<FormPickerRow>(
      find.descendant(of: sheet, matching: find.byType(FormPickerRow)),
    );
    expect(row.label, 'a');
    expect(row.onTap, isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.shareEventUnshare('a')),
      findsOneWidget,
    );

    Navigator.of(tester.element(sheet)).pop();
    await settle(tester);
    expect(sheet, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The order the Sharing page's leave relies on: this page raises its
  // ended notice before the Sharing page hears the pair end, so the page
  // takes itself and the sheet over it out from under the notice.
  testWidgets('a pair that ends under the Sharing page and its sheet leaves '
      'the ended notice alone on this page', (tester) async {
    await boot(
      user: userA,
      paired: true,
      overview: ShareOverview(
        events: [
          MySharedEvent(
            event: CalendarEvent(
              id: 'a',
              title: 'a',
              categoryId: 'other',
              startDate: DateTime(2026, 11, 12),
            ),
            categoryShared: false,
          ),
        ],
      ),
    );
    await pumpPage(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingPaired));
    await settle(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sharingMineEvents),
    );
    await settle(tester);
    expect(find.byType(MySharedEventsSheet), findsOneWidget);

    pairingBloc!.show(PairingEnded(partnerName: userB.displayName));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(notice(), findsOneWidget);
    expect(find.byType(MySharedEventsSheet), findsNothing);
    expect(find.byType(SharingPage), findsNothing);
    expect(find.byType(SyncSettingsPage), findsOneWidget);

    await answerDialog(tester, SemanticsIds.sharingEndedNoticeClose);
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SyncSettingsPage), findsOneWidget);
    expect(pairingBloc!.events, contains(const EndedNoticeDismissed()));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed sign-in reads Retry on the account row, and its tap '
      'asks again', (tester) async {
    await boot(offline: true);
    await pumpPage(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingSignIn));
    await settle(tester);
    expect(syncBloc!.state, const SyncFailure(AuthError.offline));
    final before = syncBloc!.events.length;

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingRetry));
    await settle(tester);

    expect(syncBloc!.events.sublist(before), [const SignInRequested()]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('the paired row\'s height', () {
    // Measured with Roboto, as a phone lays the words out.
    setUpAll(loadGoldenFonts);

    for (final (scale, locale) in [
      (1.0, const Locale('en')),
      (1.3, const Locale('en')),
      (2.0, const Locale('de')),
    ]) {
      testWidgets('at $scale in ${locale.languageCode} the paired row is one '
          'height with a summary and with nothing shared', (tester) async {
        await boot(
          user: userA,
          paired: true,
          overview: ShareOverview(
            events: [
              MySharedEvent(
                event: CalendarEvent(
                  id: 'a',
                  title: 'a',
                  categoryId: 'other',
                  startDate: DateTime(2026, 11, 12),
                ),
                categoryShared: false,
              ),
            ],
          ),
        );
        final errors = await layoutErrorsDuring(
          () => pumpPage(
            tester,
            size: const Size(360, 2400),
            locale: locale,
            textScale: scale,
          ),
        );
        expect(errors.map((e) => e.exceptionAsString()), isEmpty);
        final paired = find.bySemanticsIdentifier(SemanticsIds.sharingPaired);
        final withSummary = tester.getSize(paired).height;
        share.shareOverview = ShareOverview.empty;
        share.emit(share.availability);
        await settle(tester, rounds: 4);

        expect(tester.getSize(paired).height, withSummary);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  testWidgets('while an unpair runs the row stays, disabled in place, and '
      'its tap opens nothing', (tester) async {
    await boot(user: userA, paired: true);
    await pumpPage(tester);
    final paired = pairingBloc!.state as PairingPaired;
    pairingBloc!.show(PairingPaired(partner: paired.partner, busy: true));
    await settle(tester);

    final row = find.descendant(
      of: find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    expect(
      find.descendant(
        of: row,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    final events = [...pairingBloc!.events];

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingPaired));
    await settle(tester);

    expect(find.byType(SharingPage), findsNothing);
    expect(pairingBloc!.events, events);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('stop syncing while paired (D25)', () {
    const bound = SyncStatus(
      binding: SyncBinding(
        spaceId: 'space-1',
        ownerUid: 'uid-a',
        accountUid: 'uid-a',
      ),
    );

    Future<void> openStop(WidgetTester tester) async {
      await pumpPage(tester);
      syncBloc!.show(const SyncSignedIn(userA, status: bound));
      await settle(tester, rounds: 4);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharingSyncStop),
      );
      await settle(tester, rounds: 4);
    }

    testWidgets('sharing something, the confirmation adds what the partner '
        'keeps', (tester) async {
      await boot(
        user: userA,
        paired: true,
        overview: const ShareOverview(
          categories: [
            CalendarCategory(
              id: 'work',
              name: 'Work',
              colorValue: 0xFF1E88E5,
              iconKey: 'event',
              sortOrder: 0,
              isBuiltIn: false,
            ),
          ],
        ),
      );
      await openStop(tester);

      expect(
        find.text(
          '${l10n.syncStopConfirmBody} '
          '${l10n.syncStopSharingLine(userB.displayName!)}',
        ),
        findsOneWidget,
      );
      await answerDialog(tester, SemanticsIds.sheetCancel);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('paired and sharing nothing, the confirmation is today\'s', (
      tester,
    ) async {
      await boot(user: userA, paired: true);
      await openStop(tester);

      expect(find.text(l10n.syncStopConfirmBody), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Review 15: the sentence is the database's answer at the tap, never a
    // state whose first read has not landed.
    group('asked at the tap', () {
      const sharing = ShareOverview(
        categories: [
          CalendarCategory(
            id: 'work',
            name: 'Work',
            colorValue: 0xFF1E88E5,
            iconKey: 'event',
            sortOrder: 0,
            isBuiltIn: false,
          ),
        ],
      );
      Finder confirm() =>
          find.bySemanticsIdentifier(SemanticsIds.sharingSyncStopConfirm);
      Finder stop() => find.bySemanticsIdentifier(SemanticsIds.sharingSyncStop);

      Future<void> showBound(WidgetTester tester) async {
        await pumpPage(tester);
        syncBloc!.show(const SyncSignedIn(userA, status: bound));
        await settle(tester, rounds: 4);
      }

      testWidgets('tapped before the first read landed, the confirmation '
          'waits for it and says what the partner keeps — once, however '
          'often it is tapped', (tester) async {
        await boot(user: userA, paired: true, overview: sharing);
        shareGate = Completer<void>();
        await showBound(tester);

        await tester.tap(stop());
        await tester.pump();
        await tester.tap(stop());
        await settle(tester, rounds: 2);
        expect(confirm(), findsNothing, reason: 'the read has not landed');

        shareGate!.complete();
        await settle(tester, rounds: 4);
        expect(
          find.text(
            '${l10n.syncStopConfirmBody} '
            '${l10n.syncStopSharingLine(userB.displayName!)}',
          ),
          findsOneWidget,
        );
        expect(confirm(), findsOneWidget);
        await answerDialog(tester, SemanticsIds.sheetCancel);
        expect(confirm(), findsNothing);
        expect(syncBloc!.events, isNot(contains(const StopSyncingRequested())));

        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('a read that never lands holds the tap only so long: the '
          'confirmation opens without the sentence', (tester) async {
        await boot(user: userA, paired: true, overview: sharing);
        shareGate = Completer<void>();
        await showBound(tester);

        await tester.tap(stop());
        await tester.pump(SyncLimits.stopConfirmShareRead);
        await settle(tester, rounds: 2);
        expect(find.text(l10n.syncStopConfirmBody), findsOneWidget);
        await answerDialog(tester, SemanticsIds.sheetCancel);

        shareGate!.complete();
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('a wait that ran out leaves no listener on the share bloc', (
        tester,
      ) async {
        await boot(user: userA, paired: true, overview: sharing);
        shareGate = Completer<void>();
        await showBound(tester);
        final before = pageShare!.listeners;

        await tester.tap(stop());
        await tester.pump();
        expect(pageShare!.listeners, before + 1, reason: 'the tap waits');
        await tester.pump(SyncLimits.stopConfirmShareRead);
        await settle(tester, rounds: 2);
        expect(confirm(), findsOneWidget);
        expect(pageShare!.listeners, before);
        await answerDialog(tester, SemanticsIds.sheetCancel);

        shareGate!.complete();
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('a load that failed is an answer: the confirmation opens on '
          'the tap\'s own frame, without the sentence', (tester) async {
        await boot(user: userA, paired: true, overview: sharing);
        shareFails = true;
        await showBound(tester);
        expect(pageShare!.state, isA<ShareLoadFailed>());

        await tester.tap(stop());
        await tester.pump();
        expect(find.text(l10n.syncStopConfirmBody), findsOneWidget);
        await settle(tester, rounds: 2);
        await answerDialog(tester, SemanticsIds.sheetCancel);

        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('the Sharing page opened during the wait: the tap is '
          'dropped, and the next one asks', (tester) async {
        await boot(user: userA, paired: true, overview: sharing);
        shareGate = Completer<void>();
        await showBound(tester);

        await tester.tap(stop());
        await tester.pump();
        await tester.tap(
          find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
        );
        await settle(tester, rounds: 2);
        expect(find.byType(SharingPage), findsOneWidget);

        shareGate!.complete();
        await settle(tester, rounds: 4);
        expect(confirm(), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);

        Navigator.of(tester.element(find.byType(SharingPage))).pop();
        await settle(tester);
        expect(find.byType(SharingPage), findsNothing);
        expect(confirm(), findsNothing, reason: 'the dropped tap stays dropped');

        await tester.tap(stop());
        await settle(tester, rounds: 4);
        expect(confirm(), findsOneWidget);
        await answerDialog(tester, SemanticsIds.sheetCancel);

        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('the ended notice raised during the wait stays alone: the '
          'tap is dropped', (tester) async {
        await boot(user: userA, paired: true, overview: sharing);
        shareGate = Completer<void>();
        await showBound(tester);

        await tester.tap(stop());
        await tester.pump();
        pairingBloc!.show(PairingEnded(partnerName: userB.displayName));
        await settle(tester, rounds: 2);
        expect(notice(), findsOneWidget);

        shareGate!.complete();
        await settle(tester, rounds: 4);
        expect(confirm(), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(notice(), findsOneWidget);

        await answerDialog(tester, SemanticsIds.sharingEndedNoticeClose);
        expect(find.byType(AlertDialog), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('never paired, the confirmation opens on the tap\'s own '
          'frame and builds no share bloc', (tester) async {
        await boot(user: userA);
        await showBound(tester);

        await tester.tap(stop());
        await tester.pump();
        // Built on that frame; its fade has not yet given it semantics.
        expect(find.text(l10n.syncStopConfirmBody), findsOneWidget);
        expect(shareBlocs, 0);
        await settle(tester, rounds: 2);
        await answerDialog(tester, SemanticsIds.sheetCancel);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    });
  });

  // Design review 15: the Pairing row's words on the app's own grounds.
  group('the paired row\'s text contrast', () {
    setUpAll(loadGoldenFonts);

    for (final dark in [false, true]) {
      testWidgets('meets the text-contrast guideline in the '
          '${dark ? 'dark' : 'light'} theme', (tester) async {
        final handle = tester.ensureSemantics();
        await boot(user: userA, paired: true);
        await pumpPage(
          tester,
          size: const Size(412, 2400),
          theme: dark ? AppTheme.dark() : AppTheme.light(),
        );
        expect(
          find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
          findsOneWidget,
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.pumpWidget(const SizedBox.shrink());
        handle.dispose();
      });
    }
  });

  group('cancelled confirmations', () {
    testWidgets('sign out while paired asks first; cancel sends nothing and '
        'keeps the account', (tester) async {
      await boot(user: userA, paired: true);
      await pumpPage(tester);
      final syncEvents = [...syncBloc!.events];
      final pairingEvents = [...pairingBloc!.events];

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingSignOut));
      await settle(tester);
      expect(
        find.text(l10n.pairingSignOutConfirm(userB.displayName!)),
        findsOneWidget,
      );
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(find.byType(AlertDialog), findsNothing);
      expect(syncBloc!.events, syncEvents);
      expect(pairingBloc!.events, pairingEvents);
      expect(auth.currentUser, userA);
      expect(syncBloc!.state, isA<SyncSignedIn>());
      expect(pairingBloc!.state, isA<PairingPaired>());

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // The whole row signs out, so it asks with no pair too.
    testWidgets('sign out with no pair asks first; cancel sends nothing, yes '
        'signs out', (tester) async {
      await boot(user: userA);
      await pumpPage(tester);
      expect(pairingBloc!.state, isNot(isA<PairingPaired>()));
      final syncEvents = [...syncBloc!.events];

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingSignOut));
      await settle(tester);
      expect(find.text(l10n.signOutConfirm), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(find.byType(AlertDialog), findsNothing);
      expect(syncBloc!.events, syncEvents);
      expect(auth.currentUser, userA);
      expect(syncBloc!.state, isA<SyncSignedIn>());

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingSignOut));
      await settle(tester);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      expect(syncBloc!.events.sublist(syncEvents.length), [
        const SignOutRequested(),
      ]);
      expect(auth.currentUser, isNull);
      expect(syncBloc!.state, const SyncSignedOut());

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Unpair lives on the Sharing page the paired row opens; it acts on
    // this page's pairing bloc.
    testWidgets('unpair asks first; cancel sends nothing and leaves the pair '
        'active on the gateway', (tester) async {
      await boot(user: userA, paired: true);
      await pumpPage(tester);
      final pairingEvents = [...pairingBloc!.events];

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingPaired));
      await settle(tester);
      // Unpair is the Sharing page's last row, below a phone's fold.
      final unpair = find.bySemanticsIdentifier(SemanticsIds.sharingUnpair);
      await tester.scrollUntilVisible(
        unpair,
        200,
        scrollable: find
            .descendant(
              of: find.bySemanticsIdentifier(SemanticsIds.sharingPageList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      await tester.tap(unpair);
      await settle(tester);
      expect(
        find.text(
          '${l10n.pairingUnpairConfirm(userB.displayName!)} '
          '${l10n.pairingRepairHint}',
        ),
        findsOneWidget,
      );
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(find.byType(AlertDialog), findsNothing);
      expect(pairingBloc!.events, pairingEvents);
      expect(gateway.endedPairs, isEmpty);
      expect(gateway.pairs.values.single.isActive, isTrue);
      final stored = await tester.runAsync(settings.getPairingSettings);
      expect(stored!.pairId, gateway.pairs.keys.single);
      expect(pairingBloc!.state, isA<PairingPaired>());

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('where your data is stored (cloud-multi-user-roadmap §9 R2)', () {
    const row = SemanticsIds.sharingDataNotice;

    Finder byId(String id) => find.bySemanticsIdentifier(id);

    Future<void> reveal(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find
            .descendant(
              of: byId(SemanticsIds.sharingList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
    }

    testWidgets('signed out, the Privacy section is there under Pairing: one '
        'row, its title over the short answer', (tester) async {
      await boot();
      await pumpPage(tester);
      await reveal(tester, byId(row));

      for (final text in [l10n.dataNoticeTitle, l10n.dataNoticeDesc]) {
        expect(
          find.descendant(of: byId(row), matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(
        tester.getRect(byId(row)).top,
        greaterThanOrEqualTo(
          tester.getRect(find.text(l10n.pairingSignInFirst)).bottom,
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('signed in and paired, its tap opens the whole notice — '
        'every paragraph, for the place the build states — and Close closes '
        'it; neither bloc hears of it', (tester) async {
      await boot(user: userA, paired: true);
      await pumpPage(tester);
      final syncEvents = [...syncBloc!.events];
      final pairingEvents = [...pairingBloc!.events];
      await reveal(tester, byId(row));
      expect(
        tester.getRect(byId(row)).top,
        greaterThanOrEqualTo(
          tester.getRect(byId(SemanticsIds.sharingPaired)).bottom,
        ),
      );

      await tester.tap(byId(row));
      await settle(tester);

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text(l10n.dataNoticeTitle)),
        findsOneWidget,
      );
      final paragraphs = dataNoticeParagraphs(l10n);
      expect(paragraphs, contains(l10n.dataNoticeCloudUs));
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(paragraphs.join('\n\n')),
        ),
        findsOneWidget,
      );

      await answerDialog(tester, SemanticsIds.sharingDataNoticeClose);

      expect(dialog, findsNothing);
      expect(syncBloc!.events, syncEvents);
      expect(pairingBloc!.events, pairingEvents);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('it is found by what a person would type: privacy, gdpr, '
        'server', (tester) async {
      await boot(user: userA);
      await pumpPage(tester);

      for (final word in ['privacy', 'gdpr', 'server']) {
        await tester.enterText(find.byType(TextField), word);
        await settle(tester, rounds: 4);

        expect(byId(row), findsOneWidget, reason: word);
        expect(byId(SemanticsIds.sharingSync), findsNothing, reason: word);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('without sync nothing can leave the device, and there is no '
        'Privacy section', (tester) async {
      await boot(available: false);
      await pumpPage(tester);

      expect(syncBloc!.state, const SyncUnavailable());
      expect(byId(row), findsNothing);
      expect(find.text(l10n.dataNoticeTitle), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('smoke', () {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    setUpAll(loadGoldenFonts);

    Future<List<FlutterErrorDetails>> pumpSmall(WidgetTester tester) =>
        layoutErrorsDuring(
          () => pumpPage(
            tester,
            size: const Size(360, 780),
            locale: const Locale('de'),
            textScale: 2.0,
          ),
        );

    /// The title of every action row — of the one row with the id [under]
    /// when given — laid out: its width, and whether that width holds its
    /// longest word — a narrower one breaks mid-word.
    List<({double width, bool wholeWords})> actionTitles(
      WidgetTester tester, {
      String? under,
    }) => [
      for (final tile in tester.widgetList<SettingsYieldingTile>(
        under == null
            ? find.byType(SettingsYieldingTile)
            : find.descendant(
                of: find.bySemanticsIdentifier(under),
                matching: find.byType(SettingsYieldingTile),
              ),
      ))
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byWidget(tile.title),
            matching: find.byType(RichText),
          ),
        ))
          (
            width: paragraph.size.width,
            wholeWords:
                paragraph.size.width + 0.5 >=
                paragraph.getMinIntrinsicWidth(double.infinity),
          ),
    ];

    testWidgets('signed out, de 2.0 on 360 × 780 fits with no exception', (
      tester,
    ) async {
      await boot();
      final errors = await pumpSmall(tester);

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('signed in and paired, de 2.0 on 360 × 780 fits with no '
        'exception', (tester) async {
      await boot(user: userA, paired: true);
      final errors = await pumpSmall(tester);

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      // The row S5 named for its trailing button, Abmelden, now a value
      // that yields to the title. Kopplung aufheben moved onto the Sharing
      // page; the paired row below the first screen, which opens it, is
      // walked to and laid out whole.
      final signOut = actionTitles(tester, under: SemanticsIds.sharingSignOut);
      expect(signOut, hasLength(1));
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
        200,
        scrollable: find
            .descendant(
              of: find.bySemanticsIdentifier(SemanticsIds.sharingList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final title in signOut) {
        expect(title.width, greaterThan(0));
        expect(title.wholeWords, isTrue);
      }
      expect(
        tester
            .getSize(find.bySemanticsIdentifier(SemanticsIds.sharingPaired))
            .height,
        lessThan(780),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Pinned at S0 as the title laid out zero dp wide beside "Erneut
    // versuchen", a 235 dp trailing button, one glyph a line in a row about
    // 2,700 dp tall (S5). The action is now the row's value, which goes
    // under the description when the title needs the width.
    testWidgets('a failed sign-in, de 2.0 on 360 × 780 keeps the account '
        'title whole', (tester) async {
      await boot(offline: true);
      final errors = await layoutErrorsDuring(() async {
        await pumpPage(
          tester,
          size: const Size(360, 780),
          locale: const Locale('de'),
          textScale: 2.0,
        );
        await tester.tap(find.byIcon(Icons.login_rounded));
        await settle(tester);
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(syncBloc!.state, const SyncFailure(AuthError.offline));
      final titles = actionTitles(tester);
      expect(titles, hasLength(1));
      expect(titles.single.width, greaterThan(0));
      expect(titles.single.wholeWords, isTrue);
      final de = lookupAppLocalizations(const Locale('de'));
      expect(find.text(de.signInFailed), findsOneWidget);
      expect(
        tester
            .getSize(find.bySemanticsIdentifier(SemanticsIds.sharingRetry))
            .height,
        lessThan(780),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a failed sign-out, de 2.0 on 360 × 780 keeps the account '
        'title whole and offers the sign-out again (review RC3-9)', (
      tester,
    ) async {
      await boot(user: userA);
      auth.signOutError = const AuthException(AuthError.unknown);
      final errors = await layoutErrorsDuring(() async {
        await pumpPage(
          tester,
          size: const Size(360, 780),
          locale: const Locale('de'),
          textScale: 2.0,
        );
        final row = find.bySemanticsIdentifier(SemanticsIds.sharingSignOut);
        await tester.ensureVisible(row);
        await tester.tap(row);
        await settle(tester);
        await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
        await settle(tester);
      });

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(
        syncBloc!.state,
        const SyncFailure(
          AuthError.unknown,
          action: SyncAccountAction.signOut,
          user: userA,
        ),
      );
      final titles = actionTitles(tester);
      expect(titles, hasLength(1));
      expect(titles.single.width, greaterThan(0));
      expect(titles.single.wholeWords, isTrue);
      final de = lookupAppLocalizations(const Locale('de'));
      expect(find.text(de.authSignOutFailed), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharingRetry),
        findsNothing,
      );
      expect(
        tester
            .getSize(find.bySemanticsIdentifier(SemanticsIds.sharingSignOut))
            .height,
        lessThan(780),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
