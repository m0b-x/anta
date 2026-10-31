import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
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
}

/// The Sharing page's smoke suite (D14 of `docs/settings-rework-roadmap.md`),
/// pinned before S5 / S6 of the settings rework touch it: it opens signed
/// out and signed in, measures at de 2.0 on the small phone, and its two
/// confirmations — sign out while paired, unpair — cancel with no event to
/// either bloc and no write to the account or the gateway.
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
  /// [paired] plants an active pair with Ana, which the first load adopts.
  Future<void> boot({
    AppUser? user,
    bool paired = false,
    bool offline = false,
  }) async {
    auth = offline ? _OfflineAuthService() : FakeAuthService(user: user);
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
    expect(find.widgetWithText(TextButton, l10n.signOut), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signed in and paired, it opens with the account, the partner '
      'and both buttons', (tester) async {
    await boot(user: userA, paired: true);
    await pumpPage(tester);

    expect(syncBloc!.state, isA<SyncSignedIn>());
    expect(pairingBloc!.state, isA<PairingPaired>());
    expect(find.text(userA.displayName!), findsOneWidget);
    expect(find.text(l10n.pairingPairedWith(userB.displayName!)), findsOne);
    expect(find.widgetWithText(TextButton, l10n.signOut), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.unpair), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('cancelled confirmations', () {
    testWidgets('sign out while paired asks first; cancel sends nothing and '
        'keeps the account', (tester) async {
      await boot(user: userA, paired: true);
      await pumpPage(tester);
      final syncEvents = [...syncBloc!.events];
      final pairingEvents = [...pairingBloc!.events];

      await tester.tap(find.widgetWithText(TextButton, l10n.signOut));
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

    testWidgets('unpair asks first; cancel sends nothing and leaves the pair '
        'active on the gateway', (tester) async {
      await boot(user: userA, paired: true);
      await pumpPage(tester);
      final pairingEvents = [...pairingBloc!.events];

      await tester.tap(find.widgetWithText(TextButton, l10n.unpair));
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

    /// The laid-out width of the title in every row that carries a trailing
    /// `TextButton` — the S5 pattern, which squeezes the title rather than
    /// overflowing.
    List<double> titleWidthsBesideButtons(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(
        find.ancestor(
          of: find.byType(TextButton),
          matching: find.byType(ListTile),
        ),
      ))
        tester.getSize(find.byWidget(tile.title!)).width,
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
      // S5 names these two unbounded trailing buttons. Today they leave
      // their titles about 72 and 97 dp (measured 2026-10-31): cramped, but
      // drawn.
      final widths = titleWidthsBesideButtons(tester);
      expect(widths, hasLength(2));
      expect(widths, everyElement(greaterThan(48)));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Today's state, pinned so S5 sees it change: "Erneut versuchen", the
    // longest of the four trailing buttons in German, takes 235 of the
    // tile's 320 dp at 2.0, and the ListTile gives the title what is left
    // after the leading icon and the gaps — nothing. No overflow is
    // reported; the title "Anmeldung fehlgeschlagen" and the error under it
    // are laid out zero dp wide, one glyph per line, and the row grows to
    // about 2,700 dp. When S5 bounds the trailing widget, this expectation
    // flips to a drawn title.
    testWidgets('a failed sign-in, de 2.0 on 360 × 780 collapses the account '
        'title to zero width (known, S5)', (tester) async {
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
      expect(titleWidthsBesideButtons(tester), [0]);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
