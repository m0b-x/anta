import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/auth_error.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';
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

  @override
  void onEvent(SyncEvent event) {
    events.add(event);
    super.onEvent(event);
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

  final l10n = AppLocalizationsEn();

  /// Binds the account, the pairing singleton and the two bloc factories;
  /// [paired] plants an active pair with Ana, which the first load adopts;
  /// [available] false is a build without sync, the QA build's state.
  Future<void> boot({
    AppUser? user,
    bool paired = false,
    bool offline = false,
    bool available = true,
  }) async {
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
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
        home: const SyncSettingsPage(),
      ),
    );
    await settle(tester);
  }

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

  testWidgets('signed in and paired, it opens with the account and the '
      'partner, each row reading its action as its value', (tester) async {
    await boot(user: userA, paired: true);
    await pumpPage(tester);

    expect(syncBloc!.state, isA<SyncSignedIn>());
    expect(pairingBloc!.state, isA<PairingPaired>());
    expect(find.text(userA.displayName!), findsOneWidget);
    expect(find.text(l10n.pairingPairedWith(userB.displayName!)), findsOne);
    expect(find.byType(TextButton), findsNothing);
    for (final (id, action) in [
      (SemanticsIds.sharingSignOut, l10n.signOut),
      (SemanticsIds.sharingUnpair, l10n.unpair),
    ]) {
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(id),
          matching: find.text(action),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);

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

  testWidgets('while an unpair runs the row stays, disabled in place, and '
      'its tap asks nothing', (tester) async {
    await boot(user: userA, paired: true);
    await pumpPage(tester);
    final paired = pairingBloc!.state as PairingPaired;
    pairingBloc!.show(PairingPaired(partner: paired.partner, busy: true));
    await settle(tester);

    final row = find.ancestor(
      of: find.text(l10n.unpair),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    final colorScheme = Theme.of(tester.element(row)).colorScheme;
    expect(
      tester.widget<Text>(find.text(l10n.unpair)).style!.color,
      colorScheme.onSurface.withValues(alpha: FormMetrics.disabledOpacity),
    );
    final events = [...pairingBloc!.events];

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingUnpair));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(pairingBloc!.events, events);

    await tester.pumpWidget(const SizedBox.shrink());
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

    testWidgets('unpair asks first; cancel sends nothing and leaves the pair '
        'active on the gateway', (tester) async {
      await boot(user: userA, paired: true);
      await pumpPage(tester);
      final pairingEvents = [...pairingBloc!.events];

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharingUnpair));
      await settle(tester);
      expect(
        find.text(l10n.pairingUnpairConfirm(userB.displayName!)),
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

    /// The title of every action row, laid out: its width, and whether that
    /// width holds its longest word — a narrower one breaks mid-word.
    List<({double width, bool wholeWords})> actionTitles(WidgetTester tester) =>
        [
          for (final tile in tester.widgetList<SettingsYieldingTile>(
            find.byType(SettingsYieldingTile),
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
      // The two rows S5 named for their trailing buttons, Abmelden and
      // Kopplung aufheben, now values that yield to the title.
      final titles = actionTitles(tester);
      expect(titles, hasLength(2));
      for (final title in titles) {
        expect(title.width, greaterThan(0));
        expect(title.wholeWords, isTrue);
      }

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
