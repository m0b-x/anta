import 'dart:ui' show CheckedState, Tristate;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/utils/auth_error.dart';
import 'package:anta/utils/sync_moment_format.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/sync_space_picker_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';
import 'support/layout_errors.dart';
import 'support/sync_section_robot.dart';

/// Keeps every event the page sends and takes any state the suite shows it.
/// Built without a space service or an engine, so the bind, stop and sync
/// events reach a bloc that ignores them — the page's side is what is
/// pinned — while a dismiss still moves the flow back to idle.
class _ScriptedSyncBloc extends SyncBloc {
  _ScriptedSyncBloc({required super.authService});

  final List<SyncEvent> events = [];

  @override
  void onEvent(SyncEvent event) {
    events.add(event);
    super.onEvent(event);
  }

  void show(SyncState state) => emit(state);

  /// Whether the states shown are taken as carrying the engine's status;
  /// a case about the reader's first read sets it false.
  bool engineSeen = true;

  @override
  bool get engineStatusSeen => engineSeen;
}

const _binding = SyncBinding(
  spaceId: 'space-1',
  ownerUid: 'uid-a',
  accountUid: 'uid-a',
);

SyncSpaceInfo _space(String id, String name, {DateTime? lastWriteAt}) =>
    SyncSpaceInfo(
      ref: SyncSpaceRef(ownerUid: userA.uid, spaceId: id),
      name: name,
      createdAt: null,
      createdBy: 'device-1',
      schema: 1,
      lastWriteAt: lastWriteAt,
    );

final _phone = _space('s-phone', 'Phone', lastWriteAt: DateTime(2020, 3, 4));
final _tablet = _space('s-tablet', 'Tablet');
final _laptop = _space('s-laptop', 'Laptop');

const _left = SyncPendingDeletion(
  space: SyncSpaceRef(ownerUid: 'uid-a', spaceId: 'space-9'),
  spaceName: 'Phone',
);

/// The Sharing page's Sync section (S4b-2b of
/// `docs/cloud-sync-phase-02-own-space.md`, D1, D2, D4–D6) and the bind
/// picker: every state line, the rows' enabled and busy states, the stop
/// confirm, the flow's one-time moments, and the large-text matrix.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeAuthService auth;
  late FakePairingGateway gateway;
  _ScriptedSyncBloc? syncBloc;

  final l10n = AppLocalizationsEn();

  Future<void> boot({AppUser? user, bool available = true}) async {
    auth = FakeAuthService(available: available, user: user);
    gateway = FakePairingGateway();
    await PairingService.forTesting(
      auth: auth,
      gateway: gateway,
      settings: SettingsService.forTesting(db),
    );
    GetIt.I.registerFactory<SyncBloc>(
      () => syncBloc = _ScriptedSyncBloc(authService: auth),
    );
    GetIt.I.registerFactory<PairingBloc>(
      () => PairingBloc(authService: auth, gateway: gateway),
    );
  }

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    syncBloc = null;
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

  /// Opens the page signed in as Alex (or signed out) and shows [state].
  Future<SyncSectionRobot> open(
    WidgetTester tester,
    SyncState? state, {
    bool signedIn = true,
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
  }) async {
    await boot(user: signedIn ? userA : null);
    final robot = SyncSectionRobot(tester);
    await robot.pumpPage(
      size: size,
      locale: locale,
      textScale: textScale,
      dark: dark,
    );
    if (state != null) {
      syncBloc!.show(state);
      await robot.settle();
    }
    return robot;
  }

  SyncSignedIn signedIn({
    SyncStatus status = SyncStatus.empty,
    SyncBindFlow flow = const SyncBindIdle(),
  }) => SyncSignedIn(userA, status: status, flow: flow);

  /// Signed in over [status] — unbound by default — with a deletion status
  /// of [pending] (one cloud copy's deletion by default) and its run's
  /// [running], [removed] and [failure]; [account] when the account itself
  /// is being deleted with them.
  SyncSignedIn withPending({
    SyncStatus status = SyncStatus.empty,
    SyncBindFlow flow = const SyncBindIdle(),
    List<SyncPendingDeletion> pending = const [_left],
    bool running = false,
    int removed = 0,
    SyncBindFailure? failure,
    bool account = false,
  }) => SyncSignedIn(
    userA,
    status: status,
    flow: flow,
    deletion: SyncDeletionStatus(
      accountUid: userA.uid,
      pending: pending,
      running: running,
      removed: removed,
      failure: failure,
      account: account,
    ),
  );

  /// The page's held look (review S5), as the other held rows wear it: the
  /// tile disabled, no spinner, the glyph and the title dimmed, the row
  /// announced disabled.
  void expectHeldLook(WidgetTester tester, SyncSectionRobot robot, String id) {
    final row = find.descendant(
      of: robot.byId(id),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(row).enabled, isFalse, reason: id);
    expect(robot.busy(id), isFalse, reason: id);
    expect(
      tester
          .widgetList<Opacity>(
            find.descendant(of: row, matching: find.byType(Opacity)),
          )
          .map((o) => o.opacity)
          .where((opacity) => opacity > 0),
      [FormMetrics.disabledOpacity, FormMetrics.disabledOpacity],
      reason: id,
    );
    expect(
      tester.getSemantics(row).getSemanticsData().flagsCollection.isEnabled,
      Tristate.isFalse,
      reason: id,
    );
  }

  SyncStatus bound({
    SyncPause pause = SyncPause.none,
    SyncActivity activity = SyncActivity.idle,
    int pending = 0,
    int parked = 0,
    int downloaded = 0,
    SyncFailureInfo? failure,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    SyncCadence cadence = SyncCadence.automatic,
  }) => SyncStatus(
    binding: _binding,
    pause: pause,
    activity: activity,
    pendingCount: pending,
    parkedCount: parked,
    downloadedRows: downloaded,
    lastFailure: failure,
    lastPushAt: lastPushAt,
    lastPullAt: lastPullAt,
    cadence: cadence,
  );

  SyncFailureInfo failed(SyncGatewayFailure failure) =>
      SyncFailureInfo(failure, at: DateTime.utc(2026));

  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  group('unbound', () {
    testWidgets('signed in, the section sits between Account and Pairing '
        'and its one row asks to sync this database', (tester) async {
      final robot = await open(tester, null);

      expect(robot.byId(SemanticsIds.sharingSync), findsOneWidget);
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabase),
        true,
      );
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
        isTrue,
      );
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isTrue);
      expect(robot.byId(SemanticsIds.sharingSyncStatus), findsNothing);
      expect(robot.byId(SemanticsIds.sharingSyncStop), findsNothing);
      final account = tester.getRect(robot.byId(SemanticsIds.sharingSignOut));
      final sync = tester.getRect(robot.byId(SemanticsIds.sharingSync));
      final pairing = tester.getRect(robot.byId(SemanticsIds.sharingPair));
      expect(account.top, lessThan(sync.top));
      expect(sync.top, lessThan(pairing.top));
      final before = syncBloc!.events.length;

      await robot.tap(SemanticsIds.sharingSync);

      expect(syncBloc!.events.sublist(before), [
        const SyncThisDatabaseRequested(),
      ]);
      await close(tester);
    });

    testWidgets('signed out, the row stays, disabled, saying to sign in', (
      tester,
    ) async {
      final robot = await open(tester, null, signedIn: false);

      expect(syncBloc!.state, const SyncSignedOut());
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isFalse);
      expect(robot.shows(SemanticsIds.sharingSync, l10n.syncSignInFirst), true);
      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSync);
      expect(syncBloc!.events.length, before);
      await close(tester);
    });

    testWidgets('without sync, the row stays, disabled, saying it is not '
        'available', (tester) async {
      await boot(available: false);
      final robot = SyncSectionRobot(tester);
      await robot.pumpPage();

      expect(syncBloc!.state, const SyncUnavailable());
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isFalse);
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseUnavailable),
        isTrue,
      );
      // A QA build without the cloud shows it on Android too.
      for (final locale in AppLocalizations.supportedLocales) {
        final text = lookupAppLocalizations(locale).syncThisDatabaseUnavailable;
        expect(text, isNot(contains('Android')), reason: '$locale');
        expect(text, isNot(contains('iOS')), reason: '$locale');
      }
      await close(tester);
    });

    testWidgets('a disabled row of the page keeps its reason whole: the '
        'glyph and the title dim together, the reason stays '
        'onSurfaceVariant, and the row is announced disabled', (tester) async {
      final robot = await open(tester, null, signedIn: false);
      final scheme = AppTheme.light().colorScheme;
      const dim = FormMetrics.disabledOpacity;

      // The sync row's reason is its description; the pairing row has
      // none, and says its reason in its title.
      for (final (row, reason, dimmed) in [
        (
          find.descendant(
            of: robot.byId(SemanticsIds.sharingSync),
            matching: find.byType(ListTile),
          ),
          l10n.syncSignInFirst,
          [dim, dim],
        ),
        (
          find.ancestor(
            of: find.text(l10n.pairingSignInFirst),
            matching: find.byType(ListTile),
          ),
          l10n.pairingSignInFirst,
          [dim],
        ),
      ]) {
        expect(tester.widget<ListTile>(row).enabled, isFalse);
        // The drawn reason, not the slot's unseen templates (D-5).
        final caption = find.descendant(
          of: row,
          matching: find.byElementPredicate(
            (e) =>
                e.widget is Text &&
                (e.widget as Text).data == reason &&
                SyncSectionRobot.drawn(e),
          ),
        );
        expect(
          tester.renderObject<RenderParagraph>(caption).text.style?.color,
          scheme.onSurfaceVariant,
          reason: reason,
        );
        expect(
          find.ancestor(of: caption, matching: find.byType(Opacity)),
          findsNothing,
          reason: reason,
        );
        expect(
          tester
              .widgetList<Opacity>(
                find.descendant(of: row, matching: find.byType(Opacity)),
              )
              .map((o) => o.opacity)
              .where((opacity) => opacity > 0),
          dimmed,
          reason: reason,
        );
        final node = tester.getSemantics(row).getSemanticsData();
        expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      }
      await close(tester);
    });

    for (final flow in const [SyncBindChecking(), SyncBindBinding()]) {
      testWidgets('while ${flow.runtimeType} runs, a spinner takes the glyph, '
          'the row keeps its height and a tap sends nothing', (tester) async {
        final robot = await open(tester, signedIn());
        final idle = robot.height(SemanticsIds.sharingSync);
        expect(robot.busy(SemanticsIds.sharingSync), isFalse);

        syncBloc!.show(signedIn(flow: flow));
        await robot.settle();

        expect(robot.busy(SemanticsIds.sharingSync), isTrue);
        expect(robot.height(SemanticsIds.sharingSync), idle);
        expect(
          robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
          isTrue,
        );
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSync);
        expect(syncBloc!.events.length, before);
        await close(tester);
      });
    }

    testWidgets('a copy the heal stopped says so until a bind clears it; '
        'signed out the row keeps its reason (final review X-2)', (
      tester,
    ) async {
      const healed = SyncStatus(unboundAsCopyOf: 'phone_db');
      final robot = await open(tester, signedIn(status: healed));

      expect(
        robot.shows(
          SemanticsIds.sharingSync,
          l10n.syncUnboundAsCopyOf('phone_db'),
        ),
        isTrue,
      );
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
        isFalse,
      );
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isTrue);

      syncBloc!.show(const SyncSignedOut(status: healed));
      await robot.settle();
      expect(robot.shows(SemanticsIds.sharingSync, l10n.syncSignInFirst), true);

      // A bind clears the note; a plain stop after it leaves none behind.
      syncBloc!.show(signedIn(status: bound()));
      await robot.settle();
      syncBloc!.show(signedIn());
      await robot.settle();
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
        isTrue,
      );
      expect(find.text(l10n.syncUnboundAsCopyOf('phone_db')), findsNothing);
      await close(tester);
    });

    group('Finish deleting (cloud-multi-user-roadmap §5.2 g)', () {
      testWidgets('absent with no deletion left; with one, a section of its '
          'own after Pairing, its row naming the space, whose tap finishes '
          'every one without asking (review H2)', (tester) async {
        final robot = await open(tester, signedIn());
        expect(robot.byId(SemanticsIds.sharingSyncFinishDelete), findsNothing);
        expect(find.text(l10n.syncDeletionSection.toUpperCase()), findsNothing);

        syncBloc!.show(withPending());
        await robot.settle();
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        final header = tester.getRect(
          find.text(l10n.syncDeletionSection.toUpperCase()),
        );
        final finish = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncFinishDelete),
        );
        expect(
          header.top,
          greaterThan(tester.getRect(robot.byId(SemanticsIds.sharingPair)).top),
        );
        expect(finish.top, greaterThan(header.bottom));
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinish,
          ),
          isTrue,
        );
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinishDesc('Phone'),
          ),
          isTrue,
        );
        expect(robot.tile(SemanticsIds.sharingSyncFinishDelete).enabled, true);
        final before = syncBloc!.events.length;

        await robot.tap(SemanticsIds.sharingSyncFinishDelete);

        expect(find.byType(AlertDialog), findsNothing);
        expect(syncBloc!.events.sublist(before), [
          const FinishDeletingRequested(),
        ]);
        await close(tester);
      });

      testWidgets('while a run is in flight, the same row is "Deleting cloud '
          'copy", spinning in place over the count with no tap, and the bind '
          'row stays usable', (tester) async {
        final robot = await open(tester, withPending());
        final idle = robot.height(SemanticsIds.sharingSyncFinishDelete);

        syncBloc!.show(withPending(running: true, removed: 12));
        await robot.settle();

        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isTrue);
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudRunning,
          ),
          isTrue,
        );
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudProgress(12),
          ),
          isTrue,
        );
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinish,
          ),
          isFalse,
        );
        expect(robot.height(SemanticsIds.sharingSyncFinishDelete), idle);
        expect(robot.tile(SemanticsIds.sharingSync).enabled, isTrue);
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.length, before);
        await close(tester);
      });

      testWidgets('a run that outlives the records it took — none left — '
          'still spins until it ends; ended, the row stays in place, muted '
          'under a check, saying it is done with no count — a resumed '
          'deletion\'s last run knows only its own (review K8) — and no tap; '
          'the next opening shows no section', (tester) async {
        final robot = await open(
          tester,
          withPending(pending: const [], running: true, removed: 31),
        );
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isTrue);
        final running = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncFinishDelete),
        );

        syncBloc!.show(withPending(pending: const [], removed: 31));
        await robot.settle();

        expect(
          tester.getRect(robot.byId(SemanticsIds.sharingSyncFinishDelete)),
          running,
        );
        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isFalse);
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudDone,
          ),
          isTrue,
        );
        expect(
          robot.shows(SemanticsIds.sharingSyncFinishDelete, '31 items removed'),
          isFalse,
        );
        final tile = robot.tile(SemanticsIds.sharingSyncFinishDelete);
        expect(tile.onTap, isNull);
        expect((tile.leading! as Icon).icon, Icons.check_rounded);
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.length, before);
        await close(tester);

        // A page opened afresh, nothing left: no section.
        await robot.pumpPage();
        syncBloc!.show(withPending(pending: const [], removed: 31));
        await robot.settle();
        expect(robot.byId(SemanticsIds.sharingSyncFinishDelete), findsNothing);
        expect(find.text(l10n.syncDeletionSection.toUpperCase()), findsNothing);
        await close(tester);
      });

      testWidgets('the progress line counts, never repeating the title: '
          '"Starting…" at zero (review H6)', (tester) async {
        final robot = await open(tester, withPending(running: true));

        expect(
          robot.shows(SemanticsIds.sharingSyncFinishDelete, 'Starting…'),
          isTrue,
        );
        for (final (locale, zero, one, many) in const [
          (Locale('en'), 'Starting…', '1 item removed', '40 items removed'),
          (
            Locale('de'),
            'Wird gestartet…',
            '1 Eintrag entfernt',
            '40 Einträge entfernt',
          ),
          (
            Locale('ro'),
            'Se pornește…',
            'Un element eliminat',
            '40 de elemente eliminate',
          ),
        ]) {
          final local = lookupAppLocalizations(locale);
          expect(local.syncDeleteCloudProgress(0), zero);
          expect(local.syncDeleteCloudProgress(1), one);
          expect(local.syncDeleteCloudProgress(40), many);
        }
        expect(
          lookupAppLocalizations(const Locale('ro')).syncDeleteCloudProgress(3),
          '3 elemente eliminate',
        );
        // The copy is feminine in Romanian (copia).
        expect(
          lookupAppLocalizations(
            const Locale('ro'),
          ).syncDeleteCloudFinishDesc('X'),
          startsWith('Ștearsă doar parțial'),
        );
        await close(tester);
      });

      testWidgets('with several left, the row counts them instead of naming '
          'one (review S8)', (tester) async {
        final robot = await open(
          tester,
          withPending(
            pending: const [
              _left,
              SyncPendingDeletion(
                space: SyncSpaceRef(ownerUid: 'uid-a', spaceId: 'space-8'),
                spaceName: 'Tablet',
              ),
            ],
          ),
        );

        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            '2 cloud copies are partly deleted from your account',
          ),
          isTrue,
        );
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinishDesc('Phone'),
          ),
          isFalse,
        );
        await close(tester);
      });

      testWidgets('held while another step runs', (tester) async {
        final robot = await open(
          tester,
          withPending(flow: const SyncBindChecking()),
        );
        final before = syncBloc!.events.length;

        expect(robot.tile(SemanticsIds.sharingSyncFinishDelete).enabled, false);
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.length, before);
        await close(tester);
      });

      testWidgets('a run that failed is the row\'s: the error glyph, its '
          'reason the row\'s value, the tap still finishing, the bind row\'s '
          'description untouched', (tester) async {
        final robot = await open(
          tester,
          withPending(failure: SyncBindFailure.quotaExhausted),
        );

        expect(
          tester
              .getSemantics(robot.byId(SemanticsIds.sharingSyncFinishDelete))
              .getSemanticsData()
              .value,
          l10n.syncFailedQuota,
        );
        expect(
          find.descendant(
            of: robot.byId(SemanticsIds.sharingSyncFinishDelete),
            matching: find.byIcon(Icons.error_outline_rounded),
          ),
          findsOneWidget,
        );
        expect(
          robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
          isTrue,
        );
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.sublist(before), [
          const FinishDeletingRequested(),
        ]);
        await close(tester);
      });

      testWidgets('a run that ended because the app is outdated is held, '
          'saying to update: only an update can finish it (review H3)', (
        tester,
      ) async {
        final robot = await open(tester, withPending());
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        final waiting = robot.height(SemanticsIds.sharingSyncFinishDelete);

        syncBloc!.show(withPending(failure: SyncBindFailure.appOutdated));
        await robot.settle();

        expectHeldLook(tester, robot, SemanticsIds.sharingSyncFinishDelete);
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinishUpdate,
          ),
          isTrue,
        );
        expect(
          tester
              .getSemantics(robot.byId(SemanticsIds.sharingSyncFinishDelete))
              .getSemanticsData()
              .value,
          l10n.syncFailedAppOutdated,
        );
        expect(
          find.descendant(
            of: robot.byId(SemanticsIds.sharingSyncFinishDelete),
            matching: find.byIcon(Icons.error_outline_rounded),
          ),
          findsOneWidget,
        );
        expect(robot.height(SemanticsIds.sharingSyncFinishDelete), waiting);
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.length, before);
        await close(tester);
      });

      testWidgets('a failed sign-out keeps the section from the status it '
          'carries, the account still signed in, and its tap still finishes; '
          'a failed sign-in or another account does not (reviews H5, K3)', (
        tester,
      ) async {
        final robot = await open(tester, withPending());

        syncBloc!.show(
          SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: userA,
            deletion: withPending().deletion,
          ),
        );
        await robot.settle();
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);

        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinishDesc('Phone'),
          ),
          isTrue,
        );
        expect(robot.tile(SemanticsIds.sharingSyncFinishDelete).enabled, true);
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.sublist(before), [
          const FinishDeletingRequested(),
        ]);

        syncBloc!.show(
          const SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: userB,
          ),
        );
        await robot.settle();
        expect(robot.byId(SemanticsIds.sharingSyncFinishDelete), findsNothing);

        syncBloc!.show(const SyncFailure(AuthError.unknown));
        await robot.settle();
        expect(robot.byId(SemanticsIds.sharingSyncFinishDelete), findsNothing);
        await close(tester);
      });

      testWidgets('under a failed sign-out the row follows the run it '
          'carries — the count ticks, held in place — and a tap is judged '
          'on what the row says now (review K3)', (tester) async {
        final robot = await open(tester, withPending());
        SyncFailure failed(SyncSignedIn carrying) => SyncFailure(
          AuthError.unknown,
          action: SyncAccountAction.signOut,
          user: userA,
          deletion: carrying.deletion,
        );

        syncBloc!.show(failed(withPending(running: true, removed: 12)));
        await robot.settle();
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        final running = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncFinishDelete),
        );
        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isTrue);
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudProgress(12),
          ),
          isTrue,
        );
        expect(find.text(l10n.authSignOutFailedRetry), findsOneWidget);
        ScaffoldMessenger.of(
          tester.element(robot.byId(SemanticsIds.sharingSync)),
        ).removeCurrentSnackBar();
        await robot.settle();

        syncBloc!.show(failed(withPending(running: true, removed: 40)));
        await robot.settle();
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudProgress(40),
          ),
          isTrue,
        );
        expect(
          tester.getRect(robot.byId(SemanticsIds.sharingSyncFinishDelete)),
          running,
        );
        // A status re-stamping the failure is no new failure.
        expect(find.byType(SnackBar), findsNothing);
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.length, before);

        // The run's end is said there as it is signed in: its failure's
        // snackbar, then a tap that finishes.
        syncBloc!.show(failed(withPending(failure: SyncBindFailure.offline)));
        await robot.settle();
        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isFalse);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(l10n.syncFailedOffline),
          ),
          findsOneWidget,
        );
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.sublist(before), [
          const FinishDeletingRequested(),
        ]);

        // And a run that ends with nothing left is announced.
        tester.takeAnnouncements();
        syncBloc!.show(failed(withPending(running: true, removed: 41)));
        await robot.settle();
        syncBloc!.show(failed(withPending(pending: const [], removed: 52)));
        await robot.settle();
        expect(tester.takeAnnouncements(), [
          isAccessibilityAnnouncement(
            l10n.syncDeleteCloudDone,
            textDirection: TextDirection.ltr,
            assertiveness: Assertiveness.polite,
          ),
        ]);
        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudDone,
          ),
          isTrue,
        );
        await close(tester);
      });
    });
  });

  group('bound', () {
    final lines = <String, (SyncStatus, String, bool)>{
      'up to date': (
        bound(lastPullAt: DateTime(2020, 3, 4)),
        l10n.syncUpToDate,
        true,
      ),
      'never received, nothing waiting': (bound(), l10n.syncWaitingFirst, true),
      'idle with changes waiting': (
        bound(pending: 2),
        l10n.syncPendingCount(2),
        true,
      ),
      'sending': (
        bound(activity: SyncActivity.pushing, pending: 3),
        l10n.syncSending(3),
        false,
      ),
      'receiving': (
        bound(activity: SyncActivity.pulling),
        l10n.syncReceiving,
        false,
      ),
      'downloading': (
        bound(activity: SyncActivity.pulling, downloaded: 42),
        l10n.syncDownloading(42),
        false,
      ),
      'finishing the update': (
        bound(
          activity: SyncActivity.pulling,
          downloaded: 42,
        ).copyWith(updating: true, updatingTotal: 100),
        l10n.syncUpdatingNotes(42, 100),
        false,
      ),
      'finishing the update, the total unknown': (
        bound(activity: SyncActivity.pulling).copyWith(updating: true),
        l10n.syncUpdating,
        false,
      ),
      // The drain of the run that cut over counts the notes it sent, never
      // the changes waiting, which hold the notes' chunks too.
      'finishing the update, sending': (
        bound(activity: SyncActivity.pushing, pending: 9).copyWith(
          updating: true,
          updatingSending: true,
          updatingTotal: 100,
          updatingSent: 40,
        ),
        l10n.syncUpdatingSending(40, 100),
        false,
      ),
      'paused for an update while finishing the update': (
        bound(
          pause: SyncPause.appOutdated,
          activity: SyncActivity.pulling,
          downloaded: 42,
        ).copyWith(updating: true, updatingTotal: 100),
        l10n.syncPausedAppOutdated,
        false,
      ),
      'paused without access while finishing the update, sending': (
        bound(
          pause: SyncPause.noAccess,
          activity: SyncActivity.pushing,
          pending: 9,
        ).copyWith(
          updating: true,
          updatingSending: true,
          updatingTotal: 100,
          updatingSent: 40,
        ),
        l10n.syncPausedNoAccess,
        false,
      ),
      'offline': (
        bound(
          failure: SyncFailureInfo(
            SyncGatewayFailure.offline,
            at: DateTime.utc(2026),
          ),
        ),
        l10n.syncOffline,
        true,
      ),
      'another failure': (
        bound(
          failure: SyncFailureInfo(
            SyncGatewayFailure.unknown,
            at: DateTime.utc(2026),
          ),
        ),
        l10n.syncRetrying,
        true,
      ),
      // Sync now is what lifts the quota hold and re-checks access.
      'paused on the quota': (
        bound(pause: SyncPause.quotaExhausted),
        l10n.syncPausedQuota,
        true,
      ),
      'paused signed out': (
        bound(pause: SyncPause.signedOut),
        l10n.syncPausedSignedOut,
        false,
      ),
      'paused on another account': (
        bound(pause: SyncPause.accountMismatch),
        l10n.syncPausedOtherAccount,
        false,
      ),
      'paused for an update': (
        bound(pause: SyncPause.appOutdated),
        l10n.syncPausedAppOutdated,
        false,
      ),
      'paused without access': (
        bound(pause: SyncPause.noAccess),
        l10n.syncPausedNoAccess,
        true,
      ),
      'paused on a deleted space': (
        bound(pause: SyncPause.spaceDeleted),
        l10n.syncPausedSpaceDeleted,
        true,
      ),
      // The precedence: a pause outranks a run and a failure, a run the
      // failure it will retry, and a failure the changes waiting.
      'paused on the quota while sending': (
        bound(
          pause: SyncPause.quotaExhausted,
          activity: SyncActivity.pushing,
          pending: 3,
        ),
        l10n.syncPausedQuota,
        false,
      ),
      'paused for an update after a failure': (
        bound(
          pause: SyncPause.appOutdated,
          failure: failed(SyncGatewayFailure.offline),
        ),
        l10n.syncPausedAppOutdated,
        false,
      ),
      'receiving after a failure': (
        bound(
          activity: SyncActivity.pulling,
          failure: failed(SyncGatewayFailure.unknown),
        ),
        l10n.syncReceiving,
        false,
      ),
      'offline with changes waiting': (
        bound(pending: 2, failure: failed(SyncGatewayFailure.offline)),
        l10n.syncOffline,
        true,
      ),
      // The manual cadence (record §13): nothing retries by itself and
      // nothing keeps the device current, so no line promises either.
      'manual and idle': (
        bound(lastPullAt: DateTime(2026, 11, 9), cadence: SyncCadence.manual),
        l10n.syncManualIdle,
        true,
      ),
      'manual before the first pull': (
        bound(cadence: SyncCadence.manual),
        l10n.syncWaitingFirst,
        true,
      ),
      'manual with changes waiting': (
        bound(pending: 3, cadence: SyncCadence.manual),
        l10n.syncPendingCount(3),
        true,
      ),
      'manual and offline': (
        bound(
          failure: failed(SyncGatewayFailure.offline),
          cadence: SyncCadence.manual,
        ),
        l10n.syncOfflineManual,
        true,
      ),
      'manual after another failure': (
        bound(
          failure: failed(SyncGatewayFailure.unknown),
          cadence: SyncCadence.manual,
        ),
        l10n.syncFailedManual,
        true,
      ),
      'manual while paused on the quota': (
        bound(pause: SyncPause.quotaExhausted, cadence: SyncCadence.manual),
        l10n.syncPausedQuota,
        true,
      ),
    };

    for (final MapEntry(key: name, value: (status, line, canSync))
        in lines.entries) {
      testWidgets('$name: the status row says so, and Sync now is '
          '${canSync ? 'enabled' : 'disabled'}', (tester) async {
        final robot = await open(tester, signedIn(status: status));

        expect(robot.shows(SemanticsIds.sharingSyncStatus, line), isTrue);
        expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, canSync);
        expect(robot.tile(SemanticsIds.sharingSyncStop).enabled, isTrue);
        expect(robot.byId(SemanticsIds.sharingSync), findsNothing);
        await close(tester);
      });
    }

    testWidgets('a quota pause whose time is known says until when', (
      tester,
    ) async {
      final pausedAt = DateTime.now();
      final robot = await open(
        tester,
        signedIn(
          status: bound(
            pause: SyncPause.quotaExhausted,
          ).copyWith(quotaPausedAt: pausedAt),
        ),
      );
      final until = l10n.syncPausedQuotaUntil(
        formatSyncQuotaReset(
          tester.element(robot.byId(SemanticsIds.sharingSyncStatus)),
          SyncQuota.nextReset(pausedAt),
        ),
      );

      expect(robot.shows(SemanticsIds.sharingSyncStatus, until), isTrue);
      expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isTrue);
      await close(tester);
    });

    testWidgets('a quota pause whose reset has passed says the plain pause', (
      tester,
    ) async {
      final pausedAt = DateTime.now().subtract(const Duration(days: 2));
      final robot = await open(
        tester,
        signedIn(
          status: bound(
            pause: SyncPause.quotaExhausted,
          ).copyWith(quotaPausedAt: pausedAt),
        ),
      );

      expect(
        robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncPausedQuota),
        isTrue,
      );
      await close(tester);
    });

    testWidgets('the details are one paragraph: the last sync, then the '
        'held-back changes, then the waiting ones (review D2-3, RC3b-3)', (
      tester,
    ) async {
      final robot = await open(
        tester,
        signedIn(
          status: bound(
            pause: SyncPause.quotaExhausted,
            pending: 2,
            parked: 1,
            lastPushAt: DateTime(2020, 3, 4, 9, 30),
          ),
        ),
      );

      expect(
        robot.shows(
          SemanticsIds.sharingSyncStatus,
          '${l10n.syncLastSynced('Mar 4, 2020')} · '
          '${l10n.syncParkedCount(1)} · ${l10n.syncDetailsWaiting(2)}',
        ),
        isTrue,
      );

      syncBloc!.show(
        signedIn(
          status: bound(parked: 1, lastPullAt: DateTime(2020, 3, 4, 9, 30)),
        ),
      );
      await robot.settle();
      expect(
        robot.shows(
          SemanticsIds.sharingSyncStatus,
          '${l10n.syncLastSynced('Mar 4, 2020')} · ${l10n.syncParkedCount(1)}',
        ),
        isTrue,
      );
      await close(tester);
    });

    // Literal groupings, not the localizations' own output: a count that
    // lost its format would match a string built the same way (RC3b-2).
    for (final (locale, grouped) in const [
      (Locale('en'), '12,345'),
      (Locale('de'), '12.345'),
    ]) {
      for (final (name, status, inLine, inDetails) in [
        // The line counts the waiting changes, so the details do not.
        (
          'idle, waiting and held back',
          bound(pending: 12345, parked: 12345, lastPullAt: DateTime(2020)),
          true,
          true,
        ),
        // A pause does not count them, so the details do.
        (
          'paused with changes waiting',
          bound(pause: SyncPause.quotaExhausted, pending: 12345),
          false,
          true,
        ),
        (
          'sending',
          bound(activity: SyncActivity.pushing, pending: 12345),
          true,
          false,
        ),
        (
          'downloading',
          bound(activity: SyncActivity.pulling, downloaded: 12345),
          true,
          false,
        ),
      ]) {
        testWidgets('$name: a five-digit count is grouped in the locale\'s '
            'way, ${locale.languageCode} (review D2-7, RC3b-2)', (
          tester,
        ) async {
          final robot = await open(
            tester,
            signedIn(status: status),
            locale: locale,
          );
          final drawn = find
              .descendant(
                of: robot.byId(SemanticsIds.sharingSyncStatus),
                matching: find.byType(Text),
              )
              .evaluate()
              .where(SyncSectionRobot.drawn)
              .map((e) => (e.widget as Text).data!)
              .toList();
          expect(drawn, hasLength(2));
          expect(drawn.first.contains(grouped), inLine, reason: drawn.first);
          expect(drawn.last.contains(grouped), inDetails, reason: drawn.last);
          expect(drawn.join(), isNot(contains('12345')));
          await close(tester);
        });
      }
    }

    testWidgets('before the first sync the details say so, and a line that '
        'counts the changes is not repeated by them', (tester) async {
      final robot = await open(
        tester,
        signedIn(status: bound(activity: SyncActivity.pushing, pending: 3)),
      );

      expect(
        robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncNeverSynced),
        isTrue,
      );
      expect(
        find.descendant(
          of: robot.byId(SemanticsIds.sharingSyncStatus),
          matching: find.textContaining(l10n.syncDetailsWaiting(3)),
        ),
        findsNothing,
      );
      await close(tester);
    });

    testWidgets('bound and never received, the line waits for the first '
        'sync rather than saying up to date beside "Not synced yet"', (
      tester,
    ) async {
      final robot = await open(tester, signedIn(status: bound()));

      expect(
        robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncWaitingFirst),
        isTrue,
      );
      expect(
        robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncUpToDate),
        isFalse,
      );
      await close(tester);
    });

    testWidgets('Sync now sends one run — on the quota, no-access and '
        'deleted-space pauses too, which it exists to end or re-check; paused '
        'where a run can do nothing, it sends nothing', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));

      for (final pause in const [
        SyncPause.none,
        SyncPause.quotaExhausted,
        SyncPause.noAccess,
        SyncPause.spaceDeleted,
      ]) {
        syncBloc!.show(signedIn(status: bound(pause: pause)));
        await robot.settle();
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncNow);
        expect(syncBloc!.events.sublist(before), [
          const SyncNowRequested(),
        ], reason: pause.name);
      }

      for (final pause in const [
        SyncPause.accountMismatch,
        SyncPause.appOutdated,
      ]) {
        syncBloc!.show(signedIn(status: bound(pause: pause)));
        await robot.settle();
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncNow);
        expect(syncBloc!.events.length, before, reason: pause.name);
      }
      await close(tester);
    });

    group('the Sync automatically switch (record §13)', () {
      SwitchListTile switchOf(WidgetTester tester) =>
          tester.widget<SwitchListTile>(
            find.descendant(
              of: find.bySemanticsIdentifier(SemanticsIds.sharingSyncAutomatic),
              matching: find.byType(SwitchListTile),
            ),
          );

      testWidgets('bound, it sits between Sync now and Stop, on by default '
          'with its subtitle; unbound it is absent', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));

        expect(robot.byId(SemanticsIds.sharingSyncAutomatic), findsOneWidget);
        expect(switchOf(tester).value, isTrue);
        expect(
          robot.shows(SemanticsIds.sharingSyncAutomatic, l10n.syncAutomatic),
          isTrue,
        );
        expect(
          robot.shows(
            SemanticsIds.sharingSyncAutomatic,
            l10n.syncAutomaticOnDesc,
          ),
          isTrue,
        );
        final syncNow = tester.getRect(robot.byId(SemanticsIds.sharingSyncNow));
        final automatic = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncAutomatic),
        );
        final stop = tester.getRect(robot.byId(SemanticsIds.sharingSyncStop));
        expect(syncNow.top, lessThan(automatic.top));
        expect(automatic.top, lessThan(stop.top));

        syncBloc!.show(signedIn(status: SyncStatus.empty));
        await robot.settle();

        expect(robot.byId(SemanticsIds.sharingSyncAutomatic), findsNothing);
        await close(tester);
      });

      testWidgets('off under the manual cadence, with its subtitle, and Sync '
          'now stays enabled', (tester) async {
        final robot = await open(
          tester,
          signedIn(
            status: bound(
              lastPullAt: DateTime(2026, 11, 9),
              cadence: SyncCadence.manual,
            ),
          ),
        );

        expect(switchOf(tester).value, isFalse);
        expect(
          robot.shows(
            SemanticsIds.sharingSyncAutomatic,
            l10n.syncAutomaticOffDesc,
          ),
          isTrue,
        );
        expect(
          robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncManualIdle),
          isTrue,
        );
        expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isTrue);
        await close(tester);
      });

      testWidgets('a tap sends the cadence it switches to, signed in and '
          'signed out alike', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));
        var before = syncBloc!.events.length;

        await robot.tap(SemanticsIds.sharingSyncAutomatic);

        expect(syncBloc!.events.sublist(before), [
          const SyncCadenceChanged(SyncCadence.manual),
        ]);

        syncBloc!.show(signedIn(status: bound(cadence: SyncCadence.manual)));
        await robot.settle();
        before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncAutomatic);
        expect(syncBloc!.events.sublist(before), [
          const SyncCadenceChanged(SyncCadence.automatic),
        ]);

        syncBloc!.show(
          SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
        );
        await robot.settle();
        before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncAutomatic);
        expect(syncBloc!.events.sublist(before), [
          const SyncCadenceChanged(SyncCadence.manual),
        ]);
        await close(tester);
      });

      testWidgets('held while a step runs, like every row, and while the '
          'state carries no status of its own', (tester) async {
        final robot = await open(
          tester,
          signedIn(status: bound(), flow: const SyncBindStopping()),
        );

        expect(switchOf(tester).onChanged, isNull);
        var before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncAutomatic);
        expect(syncBloc!.events.length, before);

        // A failed sign-out draws the last status known: a flip could not
        // be shown there, so none is offered.
        syncBloc!.show(
          const SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: userA,
          ),
        );
        await robot.settle();
        expect(robot.byId(SemanticsIds.sharingSyncAutomatic), findsOneWidget);
        expect(switchOf(tester).onChanged, isNull);
        before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncAutomatic);
        expect(syncBloc!.events.length, before);
        await close(tester);
      });

      testWidgets('a quota pause under the manual cadence names no time it '
          'resumes at', (tester) async {
        final robot = await open(
          tester,
          signedIn(
            status: bound(
              pause: SyncPause.quotaExhausted,
              cadence: SyncCadence.manual,
            ).copyWith(quotaPausedAt: DateTime.now()),
          ),
        );

        expect(
          robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncPausedQuota),
          isTrue,
        );
        await close(tester);
      });

      testWidgets('one height on and off, so Stop never moves', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));
        final on = robot.height(SemanticsIds.sharingSyncAutomatic);
        final stopOn = tester.getTopLeft(
          robot.byId(SemanticsIds.sharingSyncStop),
        );

        syncBloc!.show(signedIn(status: bound(cadence: SyncCadence.manual)));
        await robot.settle();

        expect(robot.height(SemanticsIds.sharingSyncAutomatic), on);
        expect(
          tester.getTopLeft(robot.byId(SemanticsIds.sharingSyncStop)),
          stopOn,
        );
        await close(tester);
      });
    });

    testWidgets('a sign-in keeps the bound rows on the last status known, '
        'through a failure too; Sync now waits for an answer, Stop only '
        'while the sign-in runs — after a failure it asks and stops', (
      tester,
    ) async {
      final robot = await open(
        tester,
        SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
        signedIn: false,
      );

      for (final (state, canStop) in const [
        (SyncSigningIn(), false),
        (SyncFailure(AuthError.unknown), true),
      ]) {
        syncBloc!.show(state);
        await robot.settle();

        expect(
          robot.byId(SemanticsIds.sharingSync),
          findsNothing,
          reason: '$state',
        );
        expect(
          robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncPausedSignedOut),
          isTrue,
          reason: '$state',
        );
        expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isFalse);
        expect(
          robot.tile(SemanticsIds.sharingSyncStop).enabled,
          canStop,
          reason: '$state',
        );
      }

      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSyncStop);
      await robot.tap(SemanticsIds.sharingSyncStopConfirm);
      expect(syncBloc!.events.sublist(before), [const StopSyncingRequested()]);
      await close(tester);
    });

    testWidgets('a sign-in from a bound database shows the status row on '
        'every frame — the state before the read carries the binding — never '
        'the bind row (final review U-2)', (tester) async {
      final robot = await open(
        tester,
        SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
        signedIn: false,
      );

      for (final state in [
        const SyncSigningIn(),
        signedIn(status: bound()),
        signedIn(status: bound(lastPullAt: DateTime(2020, 3, 4))),
      ]) {
        syncBloc!.show(state);
        await robot.settle();

        expect(robot.byId(SemanticsIds.sharingSync), findsNothing);
        expect(robot.byId(SemanticsIds.sharingSyncStatus), findsOneWidget);
      }
      await close(tester);
    });

    testWidgets('while a step runs the Account row is disabled: no sign-out, '
        'no sign-in (final review U-1)', (tester) async {
      final robot = await open(
        tester,
        signedIn(status: bound()).withStepInFlight(true),
      );
      expect(robot.tile(SemanticsIds.sharingSignOut).enabled, isFalse);
      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSignOut);
      expect(find.byType(AlertDialog), findsNothing);
      expect(syncBloc!.events.length, before);

      syncBloc!.show(
        SyncSignedOut(
          status: bound(pause: SyncPause.signedOut),
          stepInFlight: true,
        ),
      );
      await robot.settle();
      expect(robot.tile(SemanticsIds.sharingSignIn).enabled, isFalse);
      await robot.tap(SemanticsIds.sharingSignIn);
      expect(syncBloc!.events.length, before);

      syncBloc!.show(signedIn(status: bound()));
      await robot.settle();
      expect(robot.tile(SemanticsIds.sharingSignOut).enabled, isTrue);
      await close(tester);
    });

    testWidgets('a step another account left running draws the rows busy '
        'until it ends (final review U-5)', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));

      syncBloc!.show(signedIn(status: bound()).withStepInFlight(true));
      await robot.settle();
      expect(robot.busy(SemanticsIds.sharingSyncStop), isTrue);
      expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isFalse);
      await robot.tap(SemanticsIds.sharingSyncStop);
      expect(find.byType(AlertDialog), findsNothing);

      syncBloc!.show(signedIn().withStepInFlight(true));
      await robot.settle();
      expect(robot.busy(SemanticsIds.sharingSync), isTrue);

      syncBloc!.show(signedIn());
      await robot.settle();
      expect(robot.busy(SemanticsIds.sharingSync), isFalse);
      await close(tester);
    });

    testWidgets('the first frame, before the bloc answers, shows the sync '
        'row checking — not an offer to sign in', (tester) async {
      await boot(user: userA);
      final robot = SyncSectionRobot(tester);
      // The tree as the first frame built it, on SyncInitial: the bloc's
      // answer lands after that frame and is drawn by the next.
      await robot.pumpPage(settled: false);

      expect(robot.busy(SemanticsIds.sharingSync), isTrue);
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncSignInFirst),
        isFalse,
      );

      await robot.settle();
      expect(robot.busy(SemanticsIds.sharingSync), isFalse);
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isTrue);
      await close(tester);
    });

    testWidgets('while a step runs the page holds — system back and the '
        "bar's arrow both stay, under another account's idle flow too — and "
        'once it ends, back leaves', (tester) async {
      await boot(user: userA);
      final robot = SyncSectionRobot(tester);
      await robot.pumpPage(pushed: true);

      for (final (status, flow) in [
        (SyncStatus.empty, const SyncBindChecking()),
        (SyncStatus.empty, const SyncBindBinding()),
        (bound(), const SyncBindStopping()),
        // An account change mid-step shows the new account's idle flow; the
        // bloc's flag still holds the page (final review U-1).
        (bound(), const SyncBindIdle()),
      ]) {
        syncBloc!.show(
          signedIn(status: status, flow: flow).withStepInFlight(true),
        );
        await robot.settle();

        await tester.binding.handlePopRoute();
        await robot.settle();
        expect(find.byType(SyncSettingsPage), findsOneWidget, reason: '$flow');
        await robot.tap(SemanticsIds.navBack);
        expect(find.byType(SyncSettingsPage), findsOneWidget, reason: '$flow');
      }

      syncBloc!.show(signedIn());
      await robot.settle();
      await tester.binding.handlePopRoute();
      await robot.settle();
      expect(find.byType(SyncSettingsPage), findsNothing);
      await close(tester);
    });

    testWidgets('signed out, the binding stays: paused, Sync now disabled, '
        'and the stop row still asks and stops', (tester) async {
      final robot = await open(
        tester,
        SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
        signedIn: false,
      );

      expect(
        robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncPausedSignedOut),
        isTrue,
      );
      expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isFalse);
      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSyncStop);
      await robot.tap(SemanticsIds.sharingSyncStopConfirm);
      expect(syncBloc!.events.sublist(before), [const StopSyncingRequested()]);
      await close(tester);
    });

    testWidgets('stop asks first, saying the cloud copy stays; cancel sends '
        'nothing, confirm stops — paused on another account too', (
      tester,
    ) async {
      final robot = await open(
        tester,
        signedIn(status: bound(pause: SyncPause.accountMismatch)),
      );
      final before = syncBloc!.events.length;

      await robot.tap(SemanticsIds.sharingSyncStop);
      expect(find.text(l10n.syncStopConfirmTitle), findsOneWidget);
      expect(find.text(l10n.syncStopConfirmBody), findsOneWidget);
      await robot.tap(SemanticsIds.sheetCancel);
      expect(find.byType(AlertDialog), findsNothing);
      expect(syncBloc!.events.length, before);

      await robot.tap(SemanticsIds.sharingSyncStop);
      expect(
        find.descendant(
          of: robot.byId(SemanticsIds.sharingSyncStopConfirm),
          matching: find.text(l10n.syncStopConfirmAction),
        ),
        findsOneWidget,
      );
      await robot.tap(SemanticsIds.sharingSyncStopConfirm);
      expect(find.byType(AlertDialog), findsNothing);
      expect(syncBloc!.events.sublist(before), [const StopSyncingRequested()]);
      await close(tester);
    });

    testWidgets('paused on a deleted space, stop is still the way out', (
      tester,
    ) async {
      final robot = await open(
        tester,
        signedIn(status: bound(pause: SyncPause.spaceDeleted)),
      );
      final before = syncBloc!.events.length;

      await robot.tap(SemanticsIds.sharingSyncStop);
      await robot.tap(SemanticsIds.sharingSyncStopConfirm);

      expect(syncBloc!.events.sublist(before), [const StopSyncingRequested()]);
      await close(tester);
    });

    testWidgets('while stopping, the stop row spins in place and asks '
        'nothing', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      final idle = robot.height(SemanticsIds.sharingSyncStop);

      syncBloc!.show(signedIn(status: bound(), flow: const SyncBindStopping()));
      await robot.settle();

      expect(robot.busy(SemanticsIds.sharingSyncStop), isTrue);
      expect(robot.height(SemanticsIds.sharingSyncStop), idle);
      expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isFalse);
      await robot.tap(SemanticsIds.sharingSyncStop);
      expect(find.byType(AlertDialog), findsNothing);
      await close(tester);
    });

    testWidgets('paused on a deleted space, the stop confirmation says the '
        'copy is gone and this device keeps everything', (tester) async {
      final robot = await open(
        tester,
        signedIn(status: bound(pause: SyncPause.spaceDeleted)),
      );

      await robot.tap(SemanticsIds.sharingSyncStop);

      expect(find.text(l10n.syncStopConfirmTitle), findsOneWidget);
      expect(find.text(l10n.syncStopConfirmBodyDeleted), findsOneWidget);
      expect(find.text(l10n.syncStopConfirmBody), findsNothing);
      await robot.tap(SemanticsIds.sheetCancel);
      await close(tester);
    });

    group('Delete cloud copy (cloud-multi-user-roadmap §5)', () {
      Color titleColor(WidgetTester tester, SyncSectionRobot robot) =>
          (find
                      .descendant(
                        of: robot.byId(SemanticsIds.sharingSyncDelete),
                        matching: find.text(l10n.syncDeleteCloud),
                      )
                      .evaluate()
                      .single
                      .renderObject!
                  as RenderParagraph)
              .text
              .style!
              .color!;

      testWidgets('the last row, right after Stop, its title in the error '
          'colour and its description under it', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));
        await robot.reveal(SemanticsIds.sharingSyncDelete);
        final stop = tester.getRect(robot.byId(SemanticsIds.sharingSyncStop));
        final delete = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncDelete),
        );

        // Only the group's hairline divider between the two.
        expect(delete.top, inInclusiveRange(stop.bottom, stop.bottom + 1));
        await robot.reveal(SemanticsIds.sharingPair);
        expect(
          tester.getTopLeft(robot.byId(SemanticsIds.sharingPair)).dy,
          greaterThan(
            tester.getRect(robot.byId(SemanticsIds.sharingSyncDelete)).bottom,
          ),
        );
        expect(titleColor(tester, robot), AppTheme.light().colorScheme.error);
        expect(
          robot.shows(SemanticsIds.sharingSyncDelete, l10n.syncDeleteCloudDesc),
          isTrue,
        );
        expect(robot.tile(SemanticsIds.sharingSyncDelete).enabled, isTrue);
        await close(tester);
      });

      for (final (name, state, signedInAs) in [
        (
          'signed out',
          SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
          false,
        ),
        (
          'paused on another account',
          signedIn(status: bound(pause: SyncPause.accountMismatch)),
          true,
        ),
        (
          'while another step runs',
          signedIn(status: bound(), flow: const SyncBindStopping()),
          true,
        ),
        // Review S3: the service always refuses an outdated app, and a copy
        // marked or gone is left by "Stop syncing".
        (
          'on an outdated app',
          signedIn(status: bound(pause: SyncPause.appOutdated)),
          true,
        ),
        (
          'paused on a deleted space',
          signedIn(status: bound(pause: SyncPause.spaceDeleted)),
          true,
        ),
      ]) {
        testWidgets('$name, the row stays, disabled, and asks nothing', (
          tester,
        ) async {
          final robot = await open(tester, state, signedIn: signedInAs);
          await robot.reveal(SemanticsIds.sharingSyncDelete);
          final before = syncBloc!.events.length;

          expect(robot.tile(SemanticsIds.sharingSyncDelete).enabled, isFalse);
          expect(
            titleColor(tester, robot),
            isNot(AppTheme.light().colorScheme.error),
          );
          await robot.tap(SemanticsIds.sharingSyncDelete);
          expect(find.byType(AlertDialog), findsNothing);
          expect(syncBloc!.events.length, before);
          await close(tester);
        });
      }

      // A copy that will not sync may still be deleted (review S3).
      for (final pause in [
        SyncPause.none,
        SyncPause.quotaExhausted,
        SyncPause.noAccess,
      ]) {
        testWidgets('enabled under the ${pause.name} pause', (tester) async {
          final robot = await open(
            tester,
            signedIn(status: bound(pause: pause)),
          );
          await robot.reveal(SemanticsIds.sharingSyncDelete);
          expect(robot.tile(SemanticsIds.sharingSyncDelete).enabled, isTrue);
          await close(tester);
        });
      }

      testWidgets('a tap asks first in a destructive dialog with its own id; '
          'cancel sends nothing, confirm deletes', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));
        await robot.reveal(SemanticsIds.sharingSyncDelete);
        final before = syncBloc!.events.length;

        await robot.tap(SemanticsIds.sharingSyncDelete);
        expect(find.text(l10n.syncDeleteCloudConfirmTitle), findsOneWidget);
        // What goes and what stays, this database's sync included (review
        // S1).
        expect(
          find.text(
            'The copy is removed from your account for good, and this '
            'database stops syncing. Nothing is deleted on this device. Your '
            'other devices keep what they hold and stop syncing too.',
          ),
          findsOneWidget,
        );
        final confirm = find.descendant(
          of: robot.byId(SemanticsIds.sharingSyncDeleteConfirm),
          matching: find.byType(FilledButton),
        );
        expect(
          find.descendant(
            of: confirm,
            matching: find.text(l10n.syncDeleteCloudConfirmAction),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(confirm)
              .style!
              .backgroundColor!
              .resolve({}),
          AppTheme.light().colorScheme.error,
        );
        await robot.tap(SemanticsIds.sheetCancel);
        expect(find.byType(AlertDialog), findsNothing);
        expect(syncBloc!.events.length, before);

        await robot.tap(SemanticsIds.sharingSyncDelete);
        await robot.tap(SemanticsIds.sharingSyncDeleteConfirm);
        expect(find.byType(AlertDialog), findsNothing);
        expect(syncBloc!.events.sublist(before), [
          const DeleteCloudCopyRequested(),
        ]);
        await close(tester);
      });

      testWidgets('during its step, the row spins in place over its '
          'description, asks nothing, and Stop is held, looking held', (
        tester,
      ) async {
        final robot = await open(tester, signedIn(status: bound()));
        await robot.reveal(SemanticsIds.sharingSyncDelete);
        final idle = robot.height(SemanticsIds.sharingSyncDelete);
        final stopIdle = robot.height(SemanticsIds.sharingSyncStop);

        syncBloc!.show(
          signedIn(status: bound(), flow: const SyncBindDeleting()),
        );
        await robot.settle();

        expect(robot.busy(SemanticsIds.sharingSyncDelete), isTrue);
        expect(
          robot.shows(SemanticsIds.sharingSyncDelete, l10n.syncDeleteCloudDesc),
          isTrue,
        );
        expect(
          robot.shows(
            SemanticsIds.sharingSyncDelete,
            l10n.syncDeleteCloudProgress(0),
          ),
          isFalse,
        );
        expect(robot.height(SemanticsIds.sharingSyncDelete), idle);
        expectHeldLook(tester, robot, SemanticsIds.sharingSyncStop);
        expect(robot.height(SemanticsIds.sharingSyncStop), stopIdle);
        expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isFalse);
        await robot.tap(SemanticsIds.sharingSyncDelete);
        expect(find.byType(AlertDialog), findsNothing);
        await close(tester);
      });

      testWidgets('under the delete step the Delete row spins alone: its run '
          'reads running, yet no deletion row is drawn, in the Sync section '
          'or after it (review H1)', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));

        syncBloc!.show(
          withPending(
            status: bound(),
            flow: const SyncBindDeleting(),
            running: true,
          ),
        );
        await robot.settle();
        await robot.scrollThrough();

        expect(robot.byId(SemanticsIds.sharingSyncFinishDelete), findsNothing);
        expect(
          find.text(
            l10n.syncDeletionSection.toUpperCase(),
            skipOffstage: false,
          ),
          findsNothing,
        );
        await robot.reveal(SemanticsIds.sharingSyncDelete);
        expect(robot.busy(SemanticsIds.sharingSyncDelete), isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // The step ends with the run going on: the section comes, last.
        syncBloc!.show(withPending(running: true));
        await robot.settle();
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isTrue);
        await close(tester);
      });

      for (final (label, shownBefore) in [
        ('"Finish deleting"', [withPending(status: bound())]),
        (
          'an ended deletion',
          [
            withPending(status: bound(), pending: const [], running: true),
            withPending(status: bound(), pending: const [], removed: 3),
          ],
        ),
      ]) {
        testWidgets('with $label on screen, a delete step keeps the section, '
            'its row held, and nothing moves on a page scrolled to its end '
            '(review K6)', (tester) async {
          final robot = await open(
            tester,
            shownBefore.first,
            size: const Size(360, 780),
          );
          for (final state in shownBefore.skip(1)) {
            syncBloc!.show(state);
            await robot.settle();
          }
          final position = robot.listPosition;
          position.jumpTo(position.maxScrollExtent);
          await tester.pump();
          final end = position.pixels;
          Rect at(String id) => tester.getRect(robot.byId(id));
          final row = at(SemanticsIds.sharingSyncFinishDelete);
          final pair = at(SemanticsIds.sharingPair);

          for (final state in [
            withPending(
              status: bound(),
              flow: const SyncBindDeleting(),
              pending: shownBefore.last.deletion!.pending,
              removed: shownBefore.last.deletion!.removed,
            ),
            // The step's own run starts while it is still in flight.
            withPending(
              status: bound(),
              flow: const SyncBindDeleting(),
              running: true,
            ),
          ]) {
            syncBloc!.show(state);
            await robot.settle();

            expect(position.pixels, end);
            expect(at(SemanticsIds.sharingSyncFinishDelete), row);
            expect(at(SemanticsIds.sharingPair), pair);
            expect(
              robot.tile(SemanticsIds.sharingSyncFinishDelete).onTap,
              isNull,
            );
          }

          // Ended, the run goes on in the same section.
          syncBloc!.show(withPending(running: true));
          await robot.settle();
          await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
          expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isTrue);
          await close(tester);
        });
      }

      testWidgets('the Delete row\'s slot is sized from its description '
          'alone, never from a progress line', (tester) async {
        final robot = await open(tester, signedIn(status: bound()));
        await robot.reveal(SemanticsIds.sharingSyncDelete);
        final slot = find.descendant(
          of: robot.byId(SemanticsIds.sharingSyncDelete),
          matching: find.byType(FormCaptionSlot),
        );

        expect(slot, findsOneWidget);
        expect(
          tester
              .widget<FormCaptionSlot>(slot)
              .candidates
              .map((candidate) => (candidate as Text).data),
          [l10n.syncDeleteCloudDesc],
        );
        await close(tester);
      });

      testWidgets('bound, a deletion in progress has the same section after '
          'Pairing, with the same id and height as unbound, and the Sync '
          'section still ends with Delete', (tester) async {
        final robot = await open(tester, withPending());
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        final unbound = robot.height(SemanticsIds.sharingSyncFinishDelete);

        syncBloc!.show(withPending(status: bound(), running: true));
        await robot.settle();
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        final row = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncFinishDelete),
        );

        expect(
          row.top,
          greaterThan(tester.getRect(robot.byId(SemanticsIds.sharingPair)).top),
        );
        await robot.reveal(SemanticsIds.sharingSyncDelete);
        final delete = tester.getRect(
          robot.byId(SemanticsIds.sharingSyncDelete),
        );
        final pairingHeader = tester.getRect(
          find.text(l10n.pairingSection.toUpperCase()),
        );
        // Nothing between Delete and the Pairing header but the gap.
        expect(pairingHeader.top, greaterThan(delete.bottom));
        expect(
          pairingHeader.top - delete.bottom,
          lessThan(robot.height(SemanticsIds.sharingSyncFinishDelete)),
        );
        await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
        expect(robot.busy(SemanticsIds.sharingSyncFinishDelete), isTrue);
        expect(row.height, unbound);

        syncBloc!.show(withPending(status: bound()));
        await robot.settle();

        expect(
          robot.shows(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinish,
          ),
          isTrue,
        );
        expect(robot.height(SemanticsIds.sharingSyncFinishDelete), unbound);
        final before = syncBloc!.events.length;
        await robot.tap(SemanticsIds.sharingSyncFinishDelete);
        expect(syncBloc!.events.sublist(before), [
          const FinishDeletingRequested(),
        ]);
        await close(tester);
      });
    });
  });

  group('Delete account (cloud-multi-user-roadmap §6.1)', () {
    const row = SemanticsIds.sharingDeleteAccount;
    const finish = SemanticsIds.sharingSyncFinishDelete;

    Future<void> show(SyncSectionRobot robot, SyncState state) async {
      syncBloc!.show(state);
      await robot.settle(rounds: 4);
    }

    SemanticsData data(
      WidgetTester tester,
      SyncSectionRobot robot,
      String id,
    ) => tester.getSemantics(robot.byId(id)).getSemanticsData();

    Color titleColor(WidgetTester tester, SyncSectionRobot robot) =>
        (find
                    .descendant(
                      of: robot.byId(row),
                      matching: find.text(l10n.syncDeleteAccount),
                    )
                    .evaluate()
                    .single
                    .renderObject!
                as RenderParagraph)
            .text
            .style!
            .color!;

    int requests() =>
        syncBloc!.events.whereType<DeleteAccountRequested>().length;

    testWidgets('the Account section\'s second row while signed in, right '
        'under the account, its title in the error colour', (tester) async {
      final robot = await open(tester, signedIn());
      final account = tester.getRect(robot.byId(SemanticsIds.sharingSignOut));
      final delete = tester.getRect(robot.byId(row));

      // Only the group's hairline divider between the two.
      expect(delete.top, inInclusiveRange(account.bottom, account.bottom + 1));
      expect(titleColor(tester, robot), AppTheme.light().colorScheme.error);
      expect(robot.shows(row, l10n.syncDeleteAccountDesc), isTrue);
      expect(robot.tile(row).enabled, isTrue);
      await close(tester);
    });

    for (final (name, state) in <(String, SyncState)>[
      ('signed out', const SyncSignedOut()),
      ('while a sign-in runs', const SyncSigningIn()),
      ('after a failed sign-in', const SyncFailure(AuthError.unknown)),
    ]) {
      testWidgets('$name there is no account to delete: the row is there, '
          'held, and asks nothing', (tester) async {
        final robot = await open(tester, state, signedIn: false);

        expectHeldLook(tester, robot, row);
        expect(
          titleColor(tester, robot),
          isNot(AppTheme.light().colorScheme.error),
        );
        await robot.tap(row);
        expect(find.byType(AlertDialog), findsNothing);
        expect(requests(), 0);
        await close(tester);
      });
    }

    testWidgets('signing in and out never moves what is under the account: '
        'the row keeps its place and its height', (tester) async {
      final robot = await open(tester, signedIn());
      final signedInAt = tester.getRect(robot.byId(row));
      final underAccount =
          signedInAt.top -
          tester.getRect(robot.byId(SemanticsIds.sharingSignOut)).bottom;

      await show(robot, const SyncSignedOut());

      final signedOutAt = tester.getRect(robot.byId(row));
      expect(signedOutAt.height, signedInAt.height);
      expect(
        signedOutAt.top -
            tester.getRect(robot.byId(SemanticsIds.sharingSignIn)).bottom,
        underAccount,
      );
      await close(tester);
    });

    testWidgets('where sync is unavailable there is no account at all, and '
        'no row', (tester) async {
      final robot = await open(
        tester,
        const SyncUnavailable(),
        signedIn: false,
      );

      expect(robot.byId(row), findsNothing);
      await close(tester);
    });

    testWidgets('after a failed sign-out the account is still signed in, '
        'and the row is there', (tester) async {
      final robot = await open(
        tester,
        const SyncFailure(
          AuthError.unknown,
          action: SyncAccountAction.signOut,
          user: userA,
        ),
      );

      expect(robot.tile(row).enabled, isTrue);
      await close(tester);
    });

    testWidgets('a tap asks first in a destructive dialog with its own id; '
        'cancel sends nothing, confirm asks for the deletion', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));

      await robot.tap(row);
      expect(find.text(l10n.syncDeleteAccountConfirmTitle), findsOneWidget);
      // What goes, what stays, and that Google's prompt follows.
      expect(
        find.text(
          'Every cloud copy of this account is removed for good, sharing '
          'with your partner ends, and the account itself is deleted. '
          'Nothing is deleted on this device. Google will ask you to sign '
          'in once more.',
        ),
        findsOneWidget,
      );
      final confirm = find.descendant(
        of: robot.byId(SemanticsIds.sharingDeleteAccountConfirm),
        matching: find.byType(FilledButton),
      );
      expect(
        find.descendant(
          of: confirm,
          matching: find.text(l10n.syncDeleteAccount),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(confirm)
            .style!
            .backgroundColor!
            .resolve({}),
        AppTheme.light().colorScheme.error,
      );
      await robot.tap(SemanticsIds.sheetCancel);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests(), 0);

      await robot.tap(row);
      await robot.tap(SemanticsIds.sharingDeleteAccountConfirm);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests(), 1);
      await close(tester);
    });

    testWidgets('while its start runs — the prompt, then the step — the row '
        'spins and asks nothing, and the bind, stop and cloud copy rows '
        'only look held', (tester) async {
      final robot = await open(
        tester,
        signedIn(status: bound(), flow: const SyncAccountDeleting()),
      );

      expect(robot.busy(row), isTrue);
      expect(data(tester, robot, row).value, l10n.syncBusyLabel);
      expect(titleColor(tester, robot), AppTheme.light().colorScheme.error);
      await robot.tap(row);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests(), 0);
      await robot.reveal(SemanticsIds.sharingSyncDelete);
      expectHeldLook(tester, robot, SemanticsIds.sharingSyncStop);
      expectHeldLook(tester, robot, SemanticsIds.sharingSyncDelete);

      await show(robot, signedIn(flow: const SyncAccountDeleting()));
      expectHeldLook(tester, robot, SemanticsIds.sharingSync);
      await close(tester);
    });

    for (final (name, state) in [
      (
        'while another step runs',
        signedIn(status: bound(), flow: const SyncBindStopping()),
      ),
      (
        'while the account\'s deletion already runs',
        withPending(pending: const [], running: true, account: true),
      ),
    ]) {
      testWidgets('$name the row is held and asks nothing', (tester) async {
        final robot = await open(tester, state);

        expectHeldLook(tester, robot, row);
        expect(
          titleColor(tester, robot),
          isNot(AppTheme.light().colorScheme.error),
        );
        await robot.tap(row);
        expect(find.byType(AlertDialog), findsNothing);
        expect(requests(), 0);
        await close(tester);
      });
    }

    testWidgets('a failed start is this row\'s: the reason is its value '
        'under the error glyph and the snackbar says it once — never the '
        'bind row\'s, never the stop row\'s', (tester) async {
      final robot = await open(tester, signedIn());
      const failed = SyncBindFailed(
        SyncBindFailure.otherAccount,
        account: true,
      );

      await show(robot, signedIn(flow: failed));

      expect(data(tester, robot, row).value, l10n.syncFailedOtherAccount);
      expect(
        find.descendant(
          of: robot.byId(row),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.syncFailedOtherAccount),
        ),
        findsOneWidget,
      );
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
        isTrue,
      );
      expect(
        find.descendant(
          of: robot.byId(SemanticsIds.sharingSync),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsNothing,
      );

      await show(robot, signedIn(status: bound(), flow: failed));
      expect(data(tester, robot, SemanticsIds.sharingSyncStop).value, isEmpty);
      // The row stays tappable: the next tap starts again.
      expect(robot.tile(row).enabled, isTrue);
      await close(tester);
    });

    testWidgets('a start that failed for no better reason is worded as the '
        'account\'s, never as sync that could not be turned on', (
      tester,
    ) async {
      final robot = await open(tester, signedIn());

      await show(
        robot,
        signedIn(
          flow: const SyncBindFailed(SyncBindFailure.unknown, account: true),
        ),
      );

      expect(data(tester, robot, row).value, l10n.syncDeleteAccountFailed);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.syncDeleteAccountFailed),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.syncFailedUnknown), findsNothing);
      await close(tester);
    });

    testWidgets('while the account is going — running or waiting — "Sync '
        'this database" is held: a copy made now could outlive the '
        'account', (tester) async {
      final robot = await open(
        tester,
        withPending(pending: const [], running: true, account: true),
      );
      final before = syncBloc!.events.length;

      expectHeldLook(tester, robot, SemanticsIds.sharingSync);
      await robot.tap(SemanticsIds.sharingSync);

      await show(robot, withPending(pending: const [], account: true));
      expectHeldLook(tester, robot, SemanticsIds.sharingSync);
      await robot.tap(SemanticsIds.sharingSync);
      expect(syncBloc!.events.sublist(before), isEmpty);

      // A cloud copy's deletion alone holds nothing.
      await show(robot, withPending());
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isTrue);
      await close(tester);
    });

    testWidgets('running, the deletion section\'s row is the account\'s: '
        '"Deleting account" over the count, spinning, asking nothing', (
      tester,
    ) async {
      final robot = await open(
        tester,
        withPending(running: true, removed: 12, account: true),
      );
      await robot.reveal(finish);

      expect(robot.shows(finish, l10n.syncDeleteAccountRunning), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteCloudProgress(12)), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteCloudRunning), isFalse);
      expect(robot.busy(finish), isTrue);
      await robot.tap(finish);
      expect(find.byType(AlertDialog), findsNothing);
      expect(syncBloc!.events.whereType<FinishDeletingRequested>(), isEmpty);
      await close(tester);
    });

    testWidgets('waiting, it is "Finish deleting account" — with or without '
        'a copy left — and its tap asks again before asking for the '
        'deletion, never for the copies alone', (tester) async {
      final robot = await open(
        tester,
        withPending(pending: const [], account: true),
      );
      await robot.reveal(finish);

      expect(robot.shows(finish, l10n.syncDeleteAccountFinish), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteAccountFinishDesc), isTrue);
      expect(robot.busy(finish), isFalse);

      await show(robot, withPending(account: true));
      await robot.reveal(finish);
      expect(robot.shows(finish, l10n.syncDeleteAccountFinish), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteAccountFinishDesc), isTrue);

      await robot.tap(finish);
      expect(find.text(l10n.syncDeleteAccountConfirmTitle), findsOneWidget);
      await robot.tap(SemanticsIds.sharingDeleteAccountConfirm);
      expect(requests(), 1);
      expect(syncBloc!.events.whereType<FinishDeletingRequested>(), isEmpty);
      await close(tester);
    });

    testWidgets('stopped on a failure, the row carries the reason as its '
        'value under the error glyph; held until an update, it says so and '
        'asks nothing', (tester) async {
      final robot = await open(
        tester,
        withPending(failure: SyncBindFailure.offline, account: true),
      );
      await robot.reveal(finish);

      expect(data(tester, robot, finish).value, l10n.syncFailedOffline);
      expect(
        find.descendant(
          of: robot.byId(finish),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(robot.tile(finish).enabled, isTrue);

      await show(
        robot,
        withPending(failure: SyncBindFailure.appOutdated, account: true),
      );
      await robot.reveal(finish);
      expect(robot.shows(finish, l10n.syncDeleteCloudFinishUpdate), isTrue);
      expect(robot.tile(finish).enabled, isFalse);
      await robot.tap(finish);
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests(), 0);
      await close(tester);
    });

    testWidgets('the sign-out confirmation says what signing out does to an '
        'unfinished account deletion', (tester) async {
      final robot = await open(
        tester,
        withPending(pending: const [], account: true),
      );

      await robot.tap(SemanticsIds.sharingSignOut);

      expect(find.text(l10n.signOutConfirmDeleting), findsOneWidget);
      expect(find.text(l10n.signOutConfirm), findsNothing);
      await robot.tap(SemanticsIds.sheetCancel);

      // With no account deletion it is the plain question again.
      await show(robot, withPending());
      await robot.tap(SemanticsIds.sharingSignOut);
      expect(find.text(l10n.signOutConfirm), findsOneWidget);
      await robot.tap(SemanticsIds.sheetCancel);
      await close(tester);
    });

    testWidgets('the signed-out state the deletion ended in says "Account '
        'deleted" once; a plain sign-out says nothing', (tester) async {
      final robot = await open(
        tester,
        withPending(pending: const [], running: true, account: true),
      );
      Finder said() => find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.syncDeleteAccountDone),
      );

      await show(robot, const SyncSignedOut(accountDeleted: true));
      expect(said(), findsOneWidget);
      expectHeldLook(tester, robot, row);
      expect(robot.byId(finish), findsNothing);

      ScaffoldMessenger.of(
        tester.element(robot.byId(SemanticsIds.sharingSignIn)),
      ).removeCurrentSnackBar();
      await robot.settle();
      await show(robot, const SyncSignedOut());
      expect(said(), findsNothing);
      await close(tester);
    });

    testWidgets('a run that ends with the account still to delete says why '
        'it waits; one that ended the account says nothing of a cloud copy', (
      tester,
    ) async {
      final robot = await open(
        tester,
        withPending(running: true, account: true),
      );
      tester.takeAnnouncements();

      await show(robot, withPending(pending: const [], account: true));
      expect(tester.takeAnnouncements().map((a) => a.message), [
        l10n.syncDeleteAccountFinishDesc,
      ]);

      // Asked again, its run ends with nothing left: the account is gone,
      // and the signed-out state that follows is what says so.
      await show(
        robot,
        withPending(pending: const [], running: true, account: true),
      );
      await show(robot, withPending(pending: const [], removed: 4));
      expect(tester.takeAnnouncements(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      // For the moment before the session's own end takes the section away,
      // its row says what ended.
      await robot.reveal(finish);
      expect(robot.shows(finish, l10n.syncDeleteAccountDone), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteCloudDone), isFalse);
      await close(tester);
    });

    testWidgets('only a run ends an account: a deletion given up while it '
        'waited ends as its copies\' — the row never reads "Account '
        'deleted" of an account that stays', (tester) async {
      final robot = await open(tester, withPending(account: true));
      await show(robot, withPending(pending: const [], account: true));

      // Signing out gave it up: nothing is left, and the account is there.
      await show(robot, withPending(pending: const []));
      await robot.reveal(finish);

      expect(robot.shows(finish, l10n.syncDeleteCloudDone), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteAccountDone), isFalse);
      await close(tester);
    });

    testWidgets('given up while its run was emptying the copies, the run '
        'goes on as a cloud copy\'s and ends as one, said so', (tester) async {
      final robot = await open(
        tester,
        withPending(running: true, account: true),
      );
      tester.takeAnnouncements();

      await show(robot, withPending(running: true, removed: 2));
      await show(robot, withPending(pending: const [], removed: 4));
      await robot.reveal(finish);

      expect(tester.takeAnnouncements().map((a) => a.message), [
        l10n.syncDeleteCloudDone,
      ]);
      expect(robot.shows(finish, l10n.syncDeleteCloudDone), isTrue);
      expect(robot.shows(finish, l10n.syncDeleteAccountDone), isFalse);
      await close(tester);
    });

    testWidgets('a step that starts an account\'s deletion ends without a '
        'word of its own', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      tester.takeAnnouncements();

      await show(
        robot,
        signedIn(
          status: bound(),
          flow: const SyncAccountDeleting(),
        ).withStepInFlight(true),
      );
      await show(robot, signedIn());

      expect(tester.takeAnnouncements(), isEmpty);
      await close(tester);
    });

    group('large text', () {
      setUpAll(loadGoldenFonts);

      for (final (locale, scale) in const [
        (Locale('en'), 1.0),
        (Locale('en'), 2.0),
        (Locale('de'), 1.3),
        (Locale('de'), 2.0),
        (Locale('ro'), 1.0),
        (Locale('ro'), 2.0),
      ]) {
        testWidgets('the row is one height idle, starting, held and failed, '
            'and it fits, ${locale.languageCode} at $scale', (tester) async {
          late SyncSectionRobot robot;
          final heights = <double>{};
          final errors = await layoutErrorsDuring(() async {
            robot = await open(
              tester,
              signedIn(),
              size: const Size(360, 780),
              locale: locale,
              textScale: scale,
            );
            for (final state in [
              signedIn(),
              signedIn(status: bound()),
              signedIn(flow: const SyncAccountDeleting()),
              signedIn(status: bound(), flow: const SyncBindStopping()),
              signedIn(
                flow: const SyncBindFailed(
                  SyncBindFailure.otherAccount,
                  account: true,
                ),
              ),
              withPending(pending: const [], running: true, account: true),
              withPending(pending: const [], account: true),
              const SyncFailure(
                AuthError.unknown,
                action: SyncAccountAction.signOut,
                user: userA,
              ),
            ]) {
              syncBloc!.show(state);
              await robot.settle(rounds: 3);
              await robot.reveal(row);
              heights.add(robot.height(row));
            }
          });

          expect(errors, isEmpty);
          expect(heights, hasLength(1));
          await close(tester);
        });

        testWidgets('the confirmation shows its whole body, '
            '${locale.languageCode} at $scale', (tester) async {
          final local = lookupAppLocalizations(locale);
          late SyncSectionRobot robot;
          final errors = await layoutErrorsDuring(() async {
            robot = await open(
              tester,
              signedIn(),
              size: const Size(360, 780),
              locale: locale,
              textScale: scale,
            );
            await robot.tap(row);
          });

          expect(errors, isEmpty);
          expect(find.text(local.syncDeleteAccountConfirmBody), findsOneWidget);
          expect(
            robot.byId(SemanticsIds.sharingDeleteAccountConfirm),
            findsOneWidget,
          );
          await robot.tap(SemanticsIds.sheetCancel);
          await close(tester);
        });
      }
    });
  });

  group('failures', () {
    final wording = <SyncBindFailed, String>{
      const SyncBindFailed(SyncBindFailure.offline): l10n.syncFailedOffline,
      const SyncBindFailed(SyncBindFailure.quotaExhausted):
          l10n.syncFailedQuota,
      const SyncBindFailed(SyncBindFailure.spaceGone): l10n.syncFailedSpaceGone,
      const SyncBindFailed(SyncBindFailure.permissionDenied):
          l10n.syncFailedPermission,
      const SyncBindFailed(SyncBindFailure.suspended): l10n.syncFailedSuspended,
      const SyncBindFailed(SyncBindFailure.alreadyBound):
          l10n.syncFailedAlreadyBound,
      const SyncBindFailed(
        SyncBindFailure.spaceHeldByAnotherDatabase,
        holderDatabase: 'tablet_db',
      ): l10n.syncFailedHeld(
        'tablet_db',
      ),
      const SyncBindFailed(SyncBindFailure.spaceHeldByAnotherDatabase):
          l10n.syncFailedHeldUnnamed,
      const SyncBindFailed(SyncBindFailure.invalidSpaceName):
          l10n.syncFailedInvalidName,
      const SyncBindFailed(SyncBindFailure.newDatabaseFailed):
          l10n.syncFailedNewDatabase,
      const SyncBindFailed(SyncBindFailure.accountDeleting):
          l10n.syncFailedAccountDeleting,
      const SyncBindFailed(SyncBindFailure.unknown): l10n.syncFailedUnknown,
    };

    for (final MapEntry(key: failed, value: text) in wording.entries) {
      testWidgets(
        '${failed.failure.name}${failed.holderDatabase == null ? '' : ' (named)'}: '
        'a snackbar says it, and the bind row keeps it',
        (tester) async {
          final robot = await open(tester, signedIn());

          syncBloc!.show(signedIn(flow: failed));
          await robot.settle();

          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(text),
            ),
            findsOneWidget,
          );
          expect(robot.shows(SemanticsIds.sharingSync, text), isTrue);
          await close(tester);
        },
      );
    }

    testWidgets('the snackbar shows once: a status emit under the same '
        'failure raises none, the row keeps the reason, and the next tap '
        'starts again', (tester) async {
      final robot = await open(tester, signedIn());
      syncBloc!.show(
        signedIn(flow: const SyncBindFailed(SyncBindFailure.offline)),
      );
      await robot.settle();
      expect(find.byType(SnackBar), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(SnackBar)),
      ).removeCurrentSnackBar();
      await robot.settle();

      syncBloc!.show(
        signedIn(
          status: const SyncStatus(pendingCount: 1),
          flow: const SyncBindFailed(SyncBindFailure.offline),
        ),
      );
      await robot.settle();

      expect(find.byType(SnackBar), findsNothing);
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncFailedOffline),
        true,
      );
      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSync);
      expect(syncBloc!.events.sublist(before), [
        const SyncThisDatabaseRequested(),
      ]);
      await close(tester);
    });

    testWidgets('a failed stop is worded as the stop in its snackbar alone: '
        'the stop row keeps one height and Pairing never moves (final '
        'review D-4)', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      final stop = robot.height(SemanticsIds.sharingSyncStop);
      final pairing = tester.getTopLeft(robot.byId(SemanticsIds.sharingPair));

      syncBloc!.show(
        signedIn(
          status: bound(),
          flow: const SyncBindFailed(SyncBindFailure.unknown),
        ),
      );
      await robot.settle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.syncStopFailed),
        ),
        findsOneWidget,
      );
      expect(
        robot.shows(SemanticsIds.sharingSyncStop, l10n.syncStopFailed),
        isFalse,
      );
      expect(robot.height(SemanticsIds.sharingSyncStop), stop);
      expect(tester.getTopLeft(robot.byId(SemanticsIds.sharingPair)), pairing);
      await close(tester);
    });

    testWidgets('a failed sign-out is the sign-out\'s: its title and snackbar '
        'say so, and the row signs out again rather than offering a sign-in', (
      tester,
    ) async {
      final robot = await open(tester, signedIn(status: bound()));

      syncBloc!.show(
        const SyncFailure(AuthError.unknown, action: SyncAccountAction.signOut),
      );
      await robot.settle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.authSignOutFailedRetry),
        ),
        findsOneWidget,
      );
      expect(robot.byId(SemanticsIds.sharingRetry), findsNothing);
      expect(
        robot.shows(SemanticsIds.sharingSignOut, l10n.authSignOutFailed),
        isTrue,
      );
      expect(robot.shows(SemanticsIds.sharingSignOut, l10n.signOut), isTrue);
      expect(find.text(l10n.signInFailed), findsNothing);
      expect(find.text(l10n.authErrorUnknown), findsNothing);
      ScaffoldMessenger.of(
        tester.element(find.byType(SnackBar)),
      ).removeCurrentSnackBar();
      await robot.settle();
      final before = syncBloc!.events.length;

      await robot.tap(SemanticsIds.sharingSignOut);
      expect(find.text(l10n.signOutConfirm), findsOneWidget);
      await robot.tap(SemanticsIds.sheetConfirm);

      expect(syncBloc!.events.sublist(before), [const SignOutRequested()]);
      await close(tester);
    });

    testWidgets('a failed sign-out names the account still signed in: its '
        'name, else its email, else its id (review D3-2, RC3c-1)', (
      tester,
    ) async {
      final robot = await open(tester, signedIn(status: bound()));

      for (final (user, shown) in const [
        (AppUser(uid: 'uid-x', displayName: 'Alex', email: 'a@b.c'), 'Alex'),
        (AppUser(uid: 'uid-x', email: 'a@b.c'), 'a@b.c'),
        (AppUser(uid: 'uid-x'), 'uid-x'),
      ]) {
        syncBloc!.show(
          SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: user,
          ),
        );
        await robot.settle();
        expect(
          robot.shows(SemanticsIds.sharingSignOut, l10n.authSignOutFailed),
          isTrue,
        );
        expect(
          robot.shows(SemanticsIds.sharingSignOut, shown),
          isTrue,
          reason: shown,
        );
      }
      await close(tester);
    });

    testWidgets('a failed sign-in keeps its own words and Retry signs in', (
      tester,
    ) async {
      final robot = await open(tester, signedIn());

      syncBloc!.show(const SyncFailure(AuthError.unknown));
      await robot.settle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.authErrorUnknown),
        ),
        findsOneWidget,
      );
      expect(robot.shows(SemanticsIds.sharingRetry, l10n.signInFailed), true);
      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingRetry);
      expect(syncBloc!.events.sublist(before), [const SignInRequested()]);
      await close(tester);
    });

    testWidgets('a second failed sign-out says so again: its own snackbar, '
        'not a row that looks dead (review RC3-1)', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      auth.signOutError = const AuthException(AuthError.unknown);
      Finder snackbar() => find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(l10n.authSignOutFailedRetry),
      );

      for (var attempt = 1; attempt <= 2; attempt++) {
        await robot.tap(SemanticsIds.sharingSignOut);
        await robot.tap(SemanticsIds.sheetConfirm);
        expect(snackbar(), findsOneWidget, reason: 'attempt $attempt');
        expect(
          robot.shows(SemanticsIds.sharingSignOut, l10n.authSignOutFailed),
          isTrue,
        );
        ScaffoldMessenger.of(
          tester.element(find.byType(SnackBar)),
        ).removeCurrentSnackBar();
        await robot.settle();
        expect(snackbar(), findsNothing);
      }
      await close(tester);
    });

    testWidgets('after a failed sign-out the section reads signed in, as the '
        'Account row does; after a failed sign-in it reads signed out '
        '(review RC3-4)', (tester) async {
      final robot = await open(tester, signedIn());
      const signOutFailed = SyncFailure(
        AuthError.unknown,
        action: SyncAccountAction.signOut,
      );

      syncBloc!.show(signOutFailed);
      await robot.settle();
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isTrue);
      expect(
        robot.shows(SemanticsIds.sharingSync, l10n.syncThisDatabaseDesc),
        isTrue,
      );
      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSync);
      expect(
        syncBloc!.events.sublist(before),
        contains(const SyncThisDatabaseRequested()),
      );

      syncBloc!.show(const SyncFailure(AuthError.unknown));
      await robot.settle();
      expect(robot.tile(SemanticsIds.sharingSync).enabled, isFalse);
      expect(robot.shows(SemanticsIds.sharingSync, l10n.syncSignInFirst), true);

      // Bound: Sync now follows the status carried from before the failure;
      // Stop stays available after either.
      syncBloc!.show(signedIn(status: bound(lastPullAt: DateTime(2020, 3, 4))));
      await robot.settle();
      syncBloc!.show(signOutFailed);
      await robot.settle();
      expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isTrue);
      expect(robot.tile(SemanticsIds.sharingSyncStop).enabled, isTrue);
      syncBloc!.show(const SyncFailure(AuthError.unknown));
      await robot.settle();
      expect(robot.tile(SemanticsIds.sharingSyncNow).enabled, isFalse);
      expect(robot.tile(SemanticsIds.sharingSyncStop).enabled, isTrue);
      await close(tester);
    });
  });

  // What a screen reader hears that no focus change would say (final review
  // D-2, WCAG 2.2 SC 4.1.3): polite, in the page's direction.
  group('announcements', () {
    Matcher said(String message) => isAccessibilityAnnouncement(
      message,
      textDirection: TextDirection.ltr,
      assertiveness: Assertiveness.polite,
    );

    Future<void> show(SyncSectionRobot robot, SyncState state) async {
      syncBloc!.show(state);
      await robot.settle();
    }

    testWidgets('a busy row reads its name, then that it is working: the '
        'spinner is silent and the row carries the value (review RC2-5)', (
      tester,
    ) async {
      final robot = await open(tester, signedIn());
      SemanticsData row(String id) =>
          tester.getSemantics(robot.byId(id)).getSemanticsData();
      expect(row(SemanticsIds.sharingSync).value, isEmpty);

      await show(robot, signedIn(flow: const SyncBindChecking()));
      expect(row(SemanticsIds.sharingSync).value, l10n.syncBusyLabel);
      expect(
        row(SemanticsIds.sharingSync).label,
        startsWith(l10n.syncThisDatabase),
      );
      expect(
        row(SemanticsIds.sharingSync).label,
        isNot(contains(l10n.syncBusyLabel)),
      );

      await show(
        robot,
        signedIn(status: bound(), flow: const SyncBindStopping()),
      );
      expect(row(SemanticsIds.sharingSyncStop).value, l10n.syncBusyLabel);
      expect(
        row(SemanticsIds.sharingSyncStop).label,
        startsWith(l10n.syncStop),
      );

      await show(robot, signedIn(status: bound()));
      expect(row(SemanticsIds.sharingSyncStop).value, isEmpty);
      await close(tester);
    });

    testWidgets('a failed stop draws no line but its row carries the reason '
        'as its value, so the red glyph is never silent (review RC3-7)', (
      tester,
    ) async {
      final robot = await open(tester, signedIn(status: bound()));
      SemanticsData stop() => tester
          .getSemantics(robot.byId(SemanticsIds.sharingSyncStop))
          .getSemanticsData();
      expect(stop().value, isEmpty);

      await show(
        robot,
        signedIn(
          status: bound(),
          flow: const SyncBindFailed(SyncBindFailure.unknown),
        ),
      );
      expect(stop().value, l10n.syncStopFailed);
      expect(stop().label, startsWith(l10n.syncStop));
      expect(
        robot.shows(SemanticsIds.sharingSyncStop, l10n.syncStopFailed),
        isFalse,
      );

      // A new stop's spinner says it is working, not the old reason.
      await show(
        robot,
        signedIn(status: bound(), flow: const SyncBindStopping()),
      );
      expect(stop().value, l10n.syncBusyLabel);
      await close(tester);
    });

    testWidgets('a bind whose settle read failed is said when its bound '
        'status arrives, once (review RC2-3)', (tester) async {
      final robot = await open(tester, signedIn());
      tester.takeAnnouncements();

      await show(robot, signedIn(flow: const SyncBindBinding()));
      // The settle: the step is over, the read kept the unbound status.
      await show(robot, signedIn(status: const SyncStatus(pendingCount: 1)));
      expect(tester.takeAnnouncements(), isEmpty);

      await show(robot, signedIn(status: bound()));
      expect(tester.takeAnnouncements(), [said(l10n.syncAnnounceBoundUnnamed)]);
      await show(robot, signedIn(status: bound(pending: 1)));
      expect(tester.takeAnnouncements(), isEmpty);
      await close(tester);
    });

    testWidgets('the engine\'s stored pause arriving after the first read is '
        'not said as one that began; a later one is (review RC2-4)', (
      tester,
    ) async {
      final robot = await open(tester, signedIn());
      syncBloc!.engineSeen = false;
      await show(robot, signedIn(status: bound()));
      tester.takeAnnouncements();

      syncBloc!.engineSeen = true;
      await show(robot, signedIn(status: bound(pause: SyncPause.noAccess)));
      expect(tester.takeAnnouncements(), isEmpty);

      await show(robot, signedIn(status: bound()));
      await show(
        robot,
        signedIn(status: bound(pause: SyncPause.quotaExhausted)),
      );
      expect(tester.takeAnnouncements(), [said(l10n.syncPausedQuota)]);
      await close(tester);
    });

    testWidgets('a bind decided in the tap is said once it settles, without '
        'a name the page never had', (tester) async {
      final robot = await open(tester, signedIn());
      tester.takeAnnouncements();

      await show(robot, signedIn(flow: const SyncBindChecking()));
      await show(robot, signedIn(flow: const SyncBindBinding()));
      expect(tester.takeAnnouncements(), isEmpty);
      await show(robot, signedIn(status: bound()));
      expect(tester.takeAnnouncements(), [said(l10n.syncAnnounceBoundUnnamed)]);

      await show(robot, signedIn(status: bound(pending: 2)));
      expect(tester.takeAnnouncements(), isEmpty);
      await close(tester);
    });

    testWidgets('a merge the picker named is said with the space\'s name', (
      tester,
    ) async {
      final robot = await open(tester, signedIn());
      await show(robot, signedIn(flow: const SyncBindChecking()));
      await show(
        robot,
        signedIn(flow: SyncBindPicking(spaces: [_phone], holdsData: true)),
      );
      await robot.tap(SemanticsIds.syncPickerMerge);
      await robot.tap(SemanticsIds.syncPickerMergeConfirm);
      tester.takeAnnouncements();

      await show(robot, signedIn(flow: const SyncBindBinding()));
      await show(robot, signedIn(status: bound()));

      expect(tester.takeAnnouncements(), [
        said(l10n.syncAnnounceBound(_phone.name)),
      ]);
      await close(tester);
    });

    testWidgets('a stop is said once it settles', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      tester.takeAnnouncements();

      await show(
        robot,
        signedIn(status: bound(), flow: const SyncBindStopping()),
      );
      expect(tester.takeAnnouncements(), isEmpty);
      await show(robot, signedIn());

      expect(tester.takeAnnouncements(), [said(l10n.syncAnnounceStopped)]);
      await close(tester);
    });

    testWidgets('a deletion\'s step that ends well says nothing by itself; '
        'its run ending with nothing left says "Cloud copy deleted" once, '
        'never its count, and later states say nothing more', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      tester.takeAnnouncements();

      await show(
        robot,
        signedIn(status: bound(), flow: const SyncBindDeleting()),
      );
      await show(robot, withPending(running: true));
      await show(robot, withPending(running: true, removed: 40));
      expect(tester.takeAnnouncements(), isEmpty);
      await show(robot, withPending(pending: const [], removed: 52));
      expect(tester.takeAnnouncements(), [said(l10n.syncDeleteCloudDone)]);
      expect(find.byType(SnackBar), findsNothing);

      // A later bind is said as a bind, never as the deletion.
      await show(robot, withPending(pending: const [], removed: 52));
      await show(robot, signedIn(flow: const SyncBindChecking()));
      await show(robot, signedIn(status: bound()));
      expect(tester.takeAnnouncements(), [said(l10n.syncAnnounceBoundUnnamed)]);
      await close(tester);
    });

    testWidgets('a delete that needed no run — its space already gone — is '
        'said once at its step\'s end, and nothing later says it again '
        '(review H4)', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      tester.takeAnnouncements();

      await show(
        robot,
        signedIn(status: bound(), flow: const SyncBindDeleting()),
      );
      expect(tester.takeAnnouncements(), isEmpty);
      // Unbound, and the account's status never read running.
      await show(robot, withPending(pending: const []));
      expect(tester.takeAnnouncements(), [said(l10n.syncDeleteCloudDone)]);

      await show(robot, withPending(pending: const [], removed: 0));
      await show(robot, signedIn());
      expect(tester.takeAnnouncements(), isEmpty);
      // No run was seen, so no section either.
      expect(robot.byId(SemanticsIds.sharingSyncFinishDelete), findsNothing);
      await close(tester);
    });

    testWidgets('a deletion status of another account says nothing', (
      tester,
    ) async {
      final robot = await open(tester, withPending(running: true, removed: 5));
      tester.takeAnnouncements();

      await show(
        robot,
        SyncSignedIn(
          userB,
          deletion: SyncDeletionStatus(accountUid: userB.uid),
        ),
      );

      expect(tester.takeAnnouncements(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await close(tester);
    });

    testWidgets('"Finish deleting" ending well is said the same way, with no '
        'step at all', (tester) async {
      final robot = await open(tester, withPending());
      tester.takeAnnouncements();

      await show(robot, withPending(running: true, removed: 3));
      await show(robot, withPending(pending: const [], removed: 3));

      expect(tester.takeAnnouncements(), [said(l10n.syncDeleteCloudDone)]);
      await close(tester);
    });

    testWidgets('a run that ends with a failure raises the failure snackbar '
        'once and says nothing of its own', (tester) async {
      final robot = await open(tester, withPending(running: true, removed: 8));
      tester.takeAnnouncements();

      await show(
        robot,
        withPending(removed: 8, failure: SyncBindFailure.offline),
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.syncFailedOffline),
        ),
        findsOneWidget,
      );
      expect(tester.takeAnnouncements(), isEmpty);
      // Dismissed, it is never raised again by a later state.
      ScaffoldMessenger.of(
        tester.element(robot.byId(SemanticsIds.sharingSync)),
      ).removeCurrentSnackBar();
      await robot.settle();
      await show(
        robot,
        withPending(
          flow: const SyncBindChecking(),
          removed: 8,
          failure: SyncBindFailure.offline,
        ),
      );
      expect(find.byType(SnackBar), findsNothing);
      await close(tester);
    });

    testWidgets('a run that had ended before the page opened says nothing', (
      tester,
    ) async {
      final robot = await open(tester, signedIn());
      tester.takeAnnouncements();

      await show(robot, withPending(failure: SyncBindFailure.offline));
      await show(robot, withPending(pending: const [], removed: 9));

      expect(tester.takeAnnouncements(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await close(tester);
    });

    testWidgets('a failed deletion is its own row\'s: the reason is the '
        'delete row\'s value, never the stop row\'s', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      SemanticsData row(String id) =>
          tester.getSemantics(robot.byId(id)).getSemanticsData();

      await show(
        robot,
        signedIn(
          status: bound(),
          flow: const SyncBindFailed(SyncBindFailure.unknown, deleting: true),
        ),
      );

      expect(row(SemanticsIds.sharingSyncDelete).value, l10n.syncFailedUnknown);
      expect(row(SemanticsIds.sharingSyncStop).value, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.syncFailedUnknown),
        ),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('a pause that begins is said in the status line\'s words; '
        'one found on opening, a repeat and a run\'s counts are not', (
      tester,
    ) async {
      final robot = await open(
        tester,
        signedIn(status: bound(pause: SyncPause.noAccess)),
      );
      expect(tester.takeAnnouncements(), isEmpty);

      await show(robot, signedIn(status: bound()));
      expect(tester.takeAnnouncements(), isEmpty);
      await show(
        robot,
        signedIn(status: bound(pause: SyncPause.quotaExhausted)),
      );
      expect(tester.takeAnnouncements(), [said(l10n.syncPausedQuota)]);
      await show(
        robot,
        signedIn(status: bound(pause: SyncPause.quotaExhausted, pending: 3)),
      );
      expect(tester.takeAnnouncements(), isEmpty);

      await show(robot, signedIn(status: bound()));
      for (final pending in const [3, 2, 1]) {
        await show(
          robot,
          signedIn(
            status: bound(activity: SyncActivity.pushing, pending: pending),
          ),
        );
      }
      expect(tester.takeAnnouncements(), isEmpty);

      // A sign-out pauses the binding it keeps.
      await show(
        robot,
        SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
      );
      expect(tester.takeAnnouncements(), [said(l10n.syncPausedSignedOut)]);
      await close(tester);
    });

    testWidgets('a failure is said once, by its snackbar\'s live region, not '
        'a second time by the page', (tester) async {
      final robot = await open(tester, signedIn());
      tester.takeAnnouncements();

      await show(robot, signedIn(flow: const SyncBindChecking()));
      await show(
        robot,
        signedIn(flow: const SyncBindFailed(SyncBindFailure.permissionDenied)),
      );

      expect(tester.takeAnnouncements(), isEmpty);
      final snackbar = tester.getSemantics(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(l10n.syncFailedPermission),
        ),
      );
      expect(snackbar.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(snackbar.label, contains(l10n.syncFailedPermission));
      await close(tester);
    });
  });

  group('the flow from the page', () {
    testWidgets('the picker opens once per picking; closed, it sends the '
        'dismiss', (tester) async {
      final robot = await open(tester, signedIn());
      final picking = SyncBindPicking(
        spaces: [_phone, _tablet],
        holdsData: true,
      );

      syncBloc!.show(signedIn(flow: picking));
      await robot.settle();
      expect(find.byType(SyncSpacePickerSheet), findsOneWidget);

      // A status emit carries the same picking: no second sheet.
      syncBloc!.show(
        signedIn(status: const SyncStatus(pendingCount: 4), flow: picking),
      );
      await robot.settle();
      expect(find.byType(SyncSpacePickerSheet), findsOneWidget);

      final before = syncBloc!.events.length;
      await robot.tap(SemanticsIds.syncPickerClose);

      expect(find.byType(SyncSpacePickerSheet), findsNothing);
      expect(syncBloc!.events.sublist(before), [const BindFlowDismissed()]);
      expect((syncBloc!.state as SyncSignedIn).flow, const SyncBindIdle());
      await close(tester);
    });

    for (final (id, event) in [
      (SemanticsIds.syncPickerMerge, MergeIntoSpaceRequested(_phone)),
      (SemanticsIds.syncPickerDownload, DownloadSpaceRequested(_phone)),
      (SemanticsIds.syncPickerUpload, const UploadAsNewSpaceRequested()),
    ]) {
      testWidgets('$id dispatches ${event.runtimeType} and closes the sheet', (
        tester,
      ) async {
        final robot = await open(tester, signedIn());
        syncBloc!.show(
          signedIn(flow: SyncBindPicking(spaces: [_phone], holdsData: true)),
        );
        await robot.settle();
        final before = syncBloc!.events.length;

        await robot.tap(id);
        // A merge of a database that holds data asks first (final review
        // F-1).
        if (id == SemanticsIds.syncPickerMerge) {
          await robot.tap(SemanticsIds.syncPickerMergeConfirm);
        }

        expect(find.byType(SyncSpacePickerSheet), findsNothing);
        expect(syncBloc!.events.sublist(before), [event]);
        await close(tester);
      });
    }

    testWidgets('after a download the restart prompt asks to exit, and the '
        'switch is acknowledged', (tester) async {
      final robot = await open(tester, signedIn());
      final before = syncBloc!.events.length;

      syncBloc!.show(
        signedIn(
          status: bound(),
          flow: const SyncBindIdle(switchedToDatabase: 'phone_db'),
        ),
      );
      await robot.settle();

      expect(find.text(l10n.restartRequiredTitle), findsOneWidget);
      expect(find.text(l10n.restartRequiredNewDatabase), findsOneWidget);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.sharingSyncRestart),
          matching: find.text(l10n.exitApp),
        ),
        findsOneWidget,
      );
      expect(syncBloc!.events.sublist(before), [const BindFlowDismissed()]);
      await close(tester);
    });
  });

  /// Opens the sheet over a plain page and keeps what it answers.
  Future<({SyncEvent? event, bool returned}) Function()> openPicker(
    WidgetTester tester,
    SyncBindPicking picking, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
  }) async {
    SyncEvent? event;
    var returned = false;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  SyncSpacePickerSheet.show(context, picking: picking).then((
                    answer,
                  ) {
                    event = answer;
                    returned = true;
                  }),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => (event: event, returned: returned);
  }

  Future<void> tapId(WidgetTester tester, String id) async {
    await tester.ensureVisible(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(id));
    await tester.pumpAndSettle();
  }

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

  bool enabled(WidgetTester tester, String id) =>
      dataOf(tester, id).flagsCollection.isEnabled == Tristate.isTrue;

  String label(WidgetTester tester, String id) => dataOf(tester, id).label;

  /// Null on a node that is no selection at all.
  bool? checked(WidgetTester tester, String id) =>
      switch (dataOf(tester, id).flagsCollection.isChecked) {
        CheckedState.isTrue => true,
        CheckedState.isFalse => false,
        _ => null,
      };

  group('the picker', () {
    testWidgets('several spaces holding data: the list picks the space the '
        'choices name, the first free one at first', (tester) async {
      final answer = await openPicker(
        tester,
        SyncBindPicking(
          spaces: [_phone, _tablet, _laptop],
          holdsData: true,
          heldBy: {_phone.ref: 'phone_db'},
        ),
      );

      expect(find.text(l10n.syncPickerTitle), findsOneWidget);
      expect(find.text(l10n.syncPickerSpaces.toUpperCase()), findsOneWidget);
      // The held space's reason, said once, on its own row.
      expect(find.text(l10n.syncPickerHeldBy('phone_db')), findsOneWidget);
      expect(
        enabled(tester, SemanticsIds.syncPickerSpace(_phone.ref.spaceId)),
        isFalse,
      );
      expect(
        checked(tester, SemanticsIds.syncPickerSpace(_tablet.ref.spaceId)),
        isTrue,
      );
      // The labels carry the outcome and never the name: the check mark
      // says which space.
      expect(
        label(tester, SemanticsIds.syncPickerMerge),
        l10n.syncPickerMergeSelected,
      );
      expect(
        label(tester, SemanticsIds.syncPickerDownload),
        l10n.syncPickerDownloadSelected,
      );
      expect(
        label(tester, SemanticsIds.syncPickerUpload),
        l10n.syncPickerUpload,
      );
      final sheet = tester.getRect(find.byType(SyncSpacePickerSheet));

      await tapId(tester, SemanticsIds.syncPickerSpace(_laptop.ref.spaceId));
      expect(answer().returned, isFalse);
      expect(
        checked(tester, SemanticsIds.syncPickerSpace(_laptop.ref.spaceId)),
        isTrue,
      );
      expect(
        checked(tester, SemanticsIds.syncPickerSpace(_tablet.ref.spaceId)),
        isFalse,
      );
      expect(tester.getRect(find.byType(SyncSpacePickerSheet)), sheet);

      // The held space cannot be picked.
      await tapId(tester, SemanticsIds.syncPickerSpace(_phone.ref.spaceId));
      expect(
        checked(tester, SemanticsIds.syncPickerSpace(_laptop.ref.spaceId)),
        isTrue,
      );

      await tapId(tester, SemanticsIds.syncPickerDownload);
      expect(answer().event, DownloadSpaceRequested(_laptop));
    });

    testWidgets('a held space keeps its reason whole: the name and the check '
        'dim, the caption stays onSurfaceVariant and wraps', (tester) async {
      await openPicker(
        tester,
        SyncBindPicking(
          spaces: [_phone, _tablet],
          holdsData: true,
          heldBy: {_phone.ref: 'phone_db'},
        ),
      );
      final row = find.bySemanticsIdentifier(
        SemanticsIds.syncPickerSpace(_phone.ref.spaceId),
      );
      final caption = find.descendant(
        of: row,
        matching: find.text(l10n.syncPickerHeldBy('phone_db')),
      );

      expect(
        find.ancestor(of: caption, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        tester.renderObject<RenderParagraph>(caption).text.style?.color,
        AppTheme.light().colorScheme.onSurfaceVariant,
      );
      expect(tester.widget<Text>(caption).maxLines, isNull);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.text('Phone'),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        FormMetrics.disabledOpacity,
      );
    });

    testWidgets('every listed space held: none shows selected, merge and '
        'download stay disabled, upload still answers', (tester) async {
      final answer = await openPicker(
        tester,
        SyncBindPicking(
          spaces: [_phone, _tablet],
          holdsData: true,
          heldBy: {_phone.ref: 'phone_db', _tablet.ref: 'tablet_db'},
        ),
      );

      for (final space in [_phone, _tablet]) {
        final id = SemanticsIds.syncPickerSpace(space.ref.spaceId);
        expect(checked(tester, id), isFalse, reason: space.name);
        expect(enabled(tester, id), isFalse, reason: space.name);
      }
      expect(enabled(tester, SemanticsIds.syncPickerMerge), isFalse);
      expect(enabled(tester, SemanticsIds.syncPickerDownload), isFalse);
      await tapId(tester, SemanticsIds.syncPickerMerge);
      expect(answer().returned, isFalse);

      await tapId(tester, SemanticsIds.syncPickerUpload);
      expect(answer().event, const UploadAsNewSpaceRequested());
    });

    testWidgets('one space: no list, the choices name it and carry no help '
        'line', (tester) async {
      final answer = await openPicker(
        tester,
        SyncBindPicking(spaces: [_phone], holdsData: true),
      );

      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.syncPickerSpace(_phone.ref.spaceId),
        ),
        findsNothing,
      );
      expect(find.text(l10n.syncPickerSpaces.toUpperCase()), findsNothing);
      expect(
        label(tester, SemanticsIds.syncPickerMerge),
        l10n.syncPickerMerge('Phone'),
      );
      expect(
        label(tester, SemanticsIds.syncPickerDownload),
        l10n.syncPickerDownload('Phone'),
      );
      expect(
        label(tester, SemanticsIds.syncPickerUpload),
        l10n.syncPickerUpload,
      );

      await tapId(tester, SemanticsIds.syncPickerMerge);
      await tapId(tester, SemanticsIds.syncPickerMergeConfirm);
      expect(answer().event, MergeIntoSpaceRequested(_phone));
    });

    // Under the bind floor every row both sides hold takes the cloud's
    // version with no conflict copy, and the choices carry no caption that
    // could say so (final review F-1).
    for (final (name, picking, target) in [
      ('one space', SyncBindPicking(spaces: [_phone], holdsData: true), _phone),
      (
        'the selected space',
        SyncBindPicking(spaces: [_phone, _tablet], holdsData: true),
        _phone,
      ),
    ]) {
      testWidgets('merging into $name with data here asks first, saying '
          'what wins; cancel keeps the picker as it was, confirm sends the '
          'merge', (tester) async {
        final answer = await openPicker(tester, picking);
        final sheet = tester.getRect(find.byType(SyncSpacePickerSheet));

        await tapId(tester, SemanticsIds.syncPickerMerge);
        expect(
          find.text(l10n.syncMergeConfirmTitle(target.name)),
          findsOneWidget,
        );
        expect(find.text(l10n.syncMergeConfirmBody), findsOneWidget);
        expect(
          find.descendant(
            of: find.bySemanticsIdentifier(SemanticsIds.syncPickerMergeConfirm),
            matching: find.text(l10n.syncMergeConfirmAction),
          ),
          findsOneWidget,
        );
        expect(answer().returned, isFalse);

        await tapId(tester, SemanticsIds.sheetCancel);
        expect(find.byType(AlertDialog), findsNothing);
        expect(answer().returned, isFalse);
        expect(tester.getRect(find.byType(SyncSpacePickerSheet)), sheet);
        if (picking.spaces.length > 1) {
          expect(
            checked(tester, SemanticsIds.syncPickerSpace(target.ref.spaceId)),
            isTrue,
          );
        }

        await tapId(tester, SemanticsIds.syncPickerMerge);
        await tapId(tester, SemanticsIds.syncPickerMergeConfirm);
        expect(find.byType(AlertDialog), findsNothing);
        expect(answer().event, MergeIntoSpaceRequested(target));
      });
    }

    for (final (name, picking, id) in [
      (
        'its one space',
        SyncBindPicking(spaces: [_phone], holdsData: false),
        SemanticsIds.syncPickerMerge,
      ),
      (
        'a listed space',
        SyncBindPicking(spaces: [_phone, _tablet], holdsData: false),
        SemanticsIds.syncPickerSpace(_phone.ref.spaceId),
      ),
    ]) {
      testWidgets('a database that holds nothing syncs with $name at once: '
          'nothing to lose, nothing asked', (tester) async {
        final answer = await openPicker(tester, picking);

        await tester.tap(find.bySemanticsIdentifier(id));
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        await tester.pumpAndSettle();

        expect(answer().event, MergeIntoSpaceRequested(_phone));
      });
    }

    testWidgets('one space another database holds: merge and download stay, '
        'disabled, the holder named once; upload still answers', (
      tester,
    ) async {
      final answer = await openPicker(
        tester,
        SyncBindPicking(
          spaces: [_phone],
          holdsData: true,
          heldBy: {_phone.ref: 'phone_db'},
        ),
      );

      expect(enabled(tester, SemanticsIds.syncPickerMerge), isFalse);
      expect(enabled(tester, SemanticsIds.syncPickerDownload), isFalse);
      expect(find.text(l10n.syncPickerHeldBy('phone_db')), findsOneWidget);
      await tapId(tester, SemanticsIds.syncPickerMerge);
      expect(answer().returned, isFalse);

      await tapId(tester, SemanticsIds.syncPickerUpload);
      expect(answer().event, const UploadAsNewSpaceRequested());
    });

    testWidgets('several spaces, nothing held here: each space is an action '
        'row that syncs with it, with no merge or download offered', (
      tester,
    ) async {
      final answer = await openPicker(
        tester,
        SyncBindPicking(
          spaces: [_phone, _tablet, _laptop],
          holdsData: false,
          heldBy: {_laptop.ref: 'laptop_db'},
        ),
      );

      expect(find.byType(FormCheckRow), findsNothing);
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(
            SemanticsIds.syncPickerSpace(_tablet.ref.spaceId),
          ),
          matching: find.byIcon(Icons.sync_rounded),
        ),
        findsOneWidget,
      );
      expect(
        checked(tester, SemanticsIds.syncPickerSpace(_tablet.ref.spaceId)),
        isNull,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.syncPickerMerge),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.syncPickerDownload),
        findsNothing,
      );
      expect(find.text(l10n.syncPickerJoin('Tablet')), findsOneWidget);
      expect(find.text(l10n.syncPickerLastUsed('Mar 4, 2020')), findsOneWidget);
      expect(find.text(l10n.syncPickerNotUsed), findsOneWidget);
      expect(find.text(l10n.syncPickerHeldBy('laptop_db')), findsOneWidget);
      expect(
        enabled(tester, SemanticsIds.syncPickerSpace(_laptop.ref.spaceId)),
        isFalse,
      );
      await tapId(tester, SemanticsIds.syncPickerSpace(_laptop.ref.spaceId));
      expect(answer().returned, isFalse);

      await tapId(tester, SemanticsIds.syncPickerSpace(_tablet.ref.spaceId));
      expect(answer().event, MergeIntoSpaceRequested(_tablet));
    });

    testWidgets('one space held, nothing here: "Sync with" is offered, '
        'disabled, naming the holder', (tester) async {
      await openPicker(
        tester,
        SyncBindPicking(
          spaces: [_phone],
          holdsData: false,
          heldBy: {_phone.ref: 'phone_db'},
        ),
      );

      expect(find.text(l10n.syncPickerJoin('Phone')), findsOneWidget);
      expect(enabled(tester, SemanticsIds.syncPickerMerge), isFalse);
      expect(find.text(l10n.syncPickerHeldBy('phone_db')), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.syncPickerDownload),
        findsNothing,
      );
    });

    final picking = SyncBindPicking(spaces: [_phone, _tablet], holdsData: true);

    testWidgets('✕ answers null', (tester) async {
      final answer = await openPicker(tester, picking);
      await tapId(tester, SemanticsIds.syncPickerClose);
      expect(answer(), (event: null, returned: true));
    });

    testWidgets('the barrier answers null', (tester) async {
      final answer = await openPicker(tester, picking);
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(answer(), (event: null, returned: true));
    });

    testWidgets('system back answers null', (tester) async {
      final answer = await openPicker(tester, picking);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(answer(), (event: null, returned: true));
    });

    testWidgets('its body carries the sheet id', (tester) async {
      await openPicker(tester, picking);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.syncPicker),
        findsOneWidget,
      );
    });
  });

  // The contrast guideline never judges a two-line row — it looks a node's
  // text up by the merged label, title and description together — so the
  // enabled descriptions' tokens are pinned here, as the disabled reasons
  // are above (review RC2-1).
  group('enabled descriptions', () {
    /// The one drawn paragraph [finder] names: its colour, and no fade on
    /// the way up.
    void expectToken(
      WidgetTester tester,
      Finder finder,
      Color color,
      String reason,
    ) {
      final drawn = finder.evaluate().where(SyncSectionRobot.drawn).toList();
      expect(drawn, hasLength(1), reason: reason);
      final element = drawn.single;
      expect(
        (element.renderObject! as RenderParagraph).text.style?.color,
        color,
        reason: reason,
      );
      var faded = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget case Opacity(:final opacity) when opacity < 1) {
          faded = true;
        }
        return !faded;
      });
      expect(faded, isFalse, reason: reason);
    }

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      final scheme = (dark ? AppTheme.dark() : AppTheme.light()).colorScheme;

      testWidgets('the bind row, its failure and the status details are '
          'onSurfaceVariant, $theme', (tester) async {
        final robot = await open(tester, signedIn(), dark: dark);
        Finder within(String id, Finder text) =>
            find.descendant(of: robot.byId(id), matching: text);

        expectToken(
          tester,
          within(
            SemanticsIds.sharingSync,
            find.text(l10n.syncThisDatabaseDesc),
          ),
          scheme.onSurfaceVariant,
          'the bind row',
        );

        syncBloc!.show(
          signedIn(status: bound(parked: 2, lastPullAt: DateTime(2020, 3, 4))),
        );
        await robot.settle();
        final details = within(
          SemanticsIds.sharingSyncStatus,
          find.textContaining(l10n.syncParkedCount(2)),
        );
        expectToken(tester, details, scheme.onSurfaceVariant, 'the details');
        final paragraph =
            details.evaluate().firstWhere(SyncSectionRobot.drawn).widget
                as Text;
        expect(
          paragraph.data!.split(' · '),
          hasLength(2),
          reason: 'the last sync and the count, one line',
        );
        expect(paragraph.data, isNot(contains('\n')));

        // The bind row's failure reason, in the slot the description keeps.
        syncBloc!.show(
          signedIn(flow: const SyncBindFailed(SyncBindFailure.offline)),
        );
        await robot.settle();
        expectToken(
          tester,
          within(SemanticsIds.sharingSync, find.text(l10n.syncFailedOffline)),
          scheme.onSurfaceVariant,
          'the bind row\'s failure',
        );
        await close(tester);
      });

      testWidgets('the deletion rows\' descriptions and progress line are '
          'onSurfaceVariant, $theme', (tester) async {
        final robot = await open(tester, signedIn(status: bound()), dark: dark);
        Finder within(String id, String text) =>
            find.descendant(of: robot.byId(id), matching: find.text(text));

        await robot.reveal(SemanticsIds.sharingSyncDelete);
        expectToken(
          tester,
          within(SemanticsIds.sharingSyncDelete, l10n.syncDeleteCloudDesc),
          scheme.onSurfaceVariant,
          'the delete row',
        );

        syncBloc!.show(withPending(running: true, removed: 7));
        await robot.settle();
        expectToken(
          tester,
          within(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudProgress(7),
          ),
          scheme.onSurfaceVariant,
          'the deletion row\'s progress',
        );

        syncBloc!.show(withPending());
        await robot.settle();
        expectToken(
          tester,
          within(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudFinishDesc('Phone'),
          ),
          scheme.onSurfaceVariant,
          'the Finish row',
        );

        // Ended while the page is open: the title itself is muted.
        syncBloc!.show(withPending(pending: const [], removed: 7));
        await robot.settle();
        expectToken(
          tester,
          within(
            SemanticsIds.sharingSyncFinishDelete,
            l10n.syncDeleteCloudDone,
          ),
          scheme.onSurfaceVariant,
          'the done row\'s title',
        );
        await close(tester);
      });

      testWidgets('a picker row\'s caption is onSurfaceVariant, $theme', (
        tester,
      ) async {
        await openPicker(
          tester,
          SyncBindPicking(spaces: [_phone, _tablet], holdsData: true),
          dark: dark,
        );

        expectToken(
          tester,
          find.descendant(
            of: find.bySemanticsIdentifier(
              SemanticsIds.syncPickerSpace(_tablet.ref.spaceId),
            ),
            matching: find.text(l10n.syncPickerNotUsed),
          ),
          scheme.onSurfaceVariant,
          'the picker caption',
        );
      });
    }
  });

  group('large text', () {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    setUpAll(loadGoldenFonts);

    final heldPicking = SyncBindPicking(
      spaces: [
        _space(
          's-long',
          'Trainingstagebuch und Kalender',
          lastWriteAt: DateTime(2020, 3, 4),
        ),
        _phone,
        _tablet,
      ],
      holdsData: true,
      heldBy: {_phone.ref: 'Datenbank des Telefons'},
    );

    // Every bound state the row may show, from the shortest line to the
    // longest, with the counts appearing and gaining digits.
    final boundStates = [
      bound(),
      bound(lastPullAt: DateTime.now()),
      bound(pending: 1, lastPullAt: DateTime(2020, 9, 28)),
      bound(pending: 12345, parked: 3, lastPushAt: DateTime(2019, 5, 28)),
      bound(activity: SyncActivity.pushing, pending: 3),
      bound(activity: SyncActivity.pulling),
      bound(activity: SyncActivity.pulling, downloaded: 4200),
      // The update's lines, at the widest count: a cutover that starts
      // must not grow the row.
      bound(
        activity: SyncActivity.pulling,
        downloaded: 4200,
      ).copyWith(updating: true, updatingTotal: 99999),
      bound(activity: SyncActivity.pushing, pending: 3).copyWith(
        updating: true,
        updatingSending: true,
        updatingTotal: 99999,
        updatingSent: 4200,
      ),
      bound(pending: 2, failure: failed(SyncGatewayFailure.offline)),
      bound(parked: 1, failure: failed(SyncGatewayFailure.unknown)),
      for (final pause in SyncPause.values) bound(pause: pause, parked: 2),
      // The manual cadence's lines, and the switch's two subtitles.
      bound(lastPullAt: DateTime(2026), cadence: SyncCadence.manual),
      bound(
        failure: failed(SyncGatewayFailure.offline),
        cadence: SyncCadence.manual,
      ),
      bound(
        failure: failed(SyncGatewayFailure.unknown),
        cadence: SyncCadence.manual,
      ),
    ];

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('en'), 2.0),
      (Locale('de'), 1.0),
      (Locale('de'), 1.3),
      (Locale('de'), 2.0),
      (Locale('ro'), 1.0),
      (Locale('ro'), 2.0),
    ]) {
      testWidgets('the status row is one height in every bound state, and '
          'Sync now and Stop never move, ${locale.languageCode} at $scale', (
        tester,
      ) async {
        final robot = await open(
          tester,
          signedIn(status: boundStates.first),
          size: const Size(360, 780),
          locale: locale,
          textScale: scale,
        );
        final heights = <double>{};
        final syncNow = <double>{};
        final stop = <double>{};
        final lineTops = <double>{};
        final glyphTops = <double>{};
        final lineHeight = FormMetrics.labelLineHeight * scale;

        for (final status in boundStates) {
          syncBloc!.show(signedIn(status: status));
          await robot.settle(rounds: 3);
          heights.add(robot.height(SemanticsIds.sharingSyncStatus));
          syncNow.add(
            tester.getTopLeft(robot.byId(SemanticsIds.sharingSyncNow)).dy,
          );
          stop.add(
            tester.getTopLeft(robot.byId(SemanticsIds.sharingSyncStop)).dy,
          );

          // The line and the details, as drawn: the templates under them
          // sit at a zero opacity.
          final row = tester.getRect(
            robot.byId(SemanticsIds.sharingSyncStatus),
          );
          final texts = find
              .descendant(
                of: robot.byId(SemanticsIds.sharingSyncStatus),
                matching: find.byType(Text),
              )
              .evaluate()
              .where(SyncSectionRobot.drawn)
              .toList();
          expect(texts, hasLength(2), reason: '$status');
          final [line, details] = [
            for (final e in texts)
              tester.getRect(find.byElementPredicate((x) => x == e)),
          ];
          // Cut on screen, never for a screen reader.
          expect(
            tester
                .getSemantics(robot.byId(SemanticsIds.sharingSyncStatus))
                .label,
            contains((texts.last.widget as Text).data!),
            reason: '$status',
          );
          final glyph = tester.getRect(
            find.descendant(
              of: robot.byId(SemanticsIds.sharingSyncStatus),
              matching: find.byType(Icon),
            ),
          );
          lineTops.add(line.top - row.top);
          glyphTops.add(glyph.top - row.top);
          // The details follow the line at once, so the room a short state
          // leaves is all under the last line (final review D-1)…
          expect(details.top, closeTo(line.bottom, 0.01), reason: '$status');
          expect(details.bottom, lessThanOrEqualTo(row.bottom));
          // …and the glyph labels the line, not the middle of the row.
          expect(
            glyph.center.dy,
            inInclusiveRange(line.top, line.top + lineHeight),
            reason: '$status',
          );
        }

        expect(heights, hasLength(1));
        expect(syncNow, hasLength(1));
        expect(stop, hasLength(1));
        expect(lineTops, hasLength(1));
        expect(glyphTops, hasLength(1));
        await close(tester);
      });
    }

    // The line and the details share the slot's lines: a short line leaves
    // its lines to the details, which then read whole (review D3-1).
    for (final (locale, scale, width, status) in [
      (
        const Locale('de'),
        2.0,
        360.0,
        bound(parked: 3, lastPullAt: DateTime(2020, 9, 28, 15, 9)),
      ),
      (
        const Locale('en'),
        1.0,
        412.0,
        bound(
          pause: SyncPause.quotaExhausted,
          pending: 12345,
          parked: 3,
          lastPushAt: DateTime(2020, 9, 28),
        ),
      ),
    ]) {
      testWidgets('the details take the lines a short status line leaves and '
          'read whole, in a row of one height, ${locale.languageCode} at '
          '$scale on ${width.toInt()}', (tester) async {
        final robot = await open(
          tester,
          signedIn(status: bound()),
          size: Size(width, 915),
          locale: locale,
          textScale: scale,
        );
        final empty = robot.height(SemanticsIds.sharingSyncStatus);

        syncBloc!.show(signedIn(status: status));
        await robot.settle(rounds: 3);

        expect(robot.height(SemanticsIds.sharingSyncStatus), empty);
        final details = find
            .descendant(
              of: robot.byId(SemanticsIds.sharingSyncStatus),
              matching: find.byType(Text),
            )
            .evaluate()
            .where(SyncSectionRobot.drawn)
            .last;
        final paragraph = details.renderObject! as RenderParagraph;
        expect(paragraph.didExceedMaxLines, isFalse);
        final text = (details.widget as Text).data!;
        expect(text, contains(' · '));
        await close(tester);
      });
    }

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('en'), 2.0),
      (Locale('de'), 1.0),
      (Locale('de'), 2.0),
      (Locale('ro'), 1.0),
      (Locale('ro'), 2.0),
    ]) {
      testWidgets('a failed sign-out keeps the Account row\'s height: nothing '
          'below it moves, ${locale.languageCode} at $scale (review D3-2, '
          'D4-1)', (tester) async {
        final robot = await open(
          tester,
          signedIn(status: bound()),
          size: const Size(360, 780),
          locale: locale,
          textScale: scale,
        );
        final account = robot.height(SemanticsIds.sharingSignOut);
        final status = tester
            .getTopLeft(robot.byId(SemanticsIds.sharingSyncStatus))
            .dy;

        syncBloc!.show(
          const SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
            user: userA,
          ),
        );
        await robot.settle();

        expect(robot.height(SemanticsIds.sharingSignOut), account);
        expect(
          tester.getTopLeft(robot.byId(SemanticsIds.sharingSyncStatus)).dy,
          status,
        );
        expect(
          robot.shows(SemanticsIds.sharingSignOut, userA.displayName!),
          isTrue,
        );
        await close(tester);
      });
    }

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('de'), 2.0),
      (Locale('ro'), 2.0),
    ]) {
      testWidgets('the unbound row is one height in every state, a failure '
          'and the heal note ellipsized inside its slot, and Pairing never '
          'moves, ${locale.languageCode} at $scale (final review D-5)', (
        tester,
      ) async {
        final robot = await open(
          tester,
          signedIn(),
          size: const Size(360, 780),
          locale: locale,
          textScale: scale,
        );
        final local = lookupAppLocalizations(locale);
        final heights = <double>{};
        final pairing = <double>{};
        const longName = 'Trainingstagebuch_und_Kalender_2026_vom_Telefon';
        const held = SyncBindFailed(
          SyncBindFailure.spaceHeldByAnotherDatabase,
          holderDatabase: longName,
        );

        for (final state in <SyncState>[
          signedIn(),
          signedIn(flow: const SyncBindChecking()),
          signedIn(flow: const SyncBindBinding()),
          signedIn(flow: held),
          signedIn(
            flow: const SyncBindFailed(SyncBindFailure.permissionDenied),
          ),
          signedIn(status: const SyncStatus(unboundAsCopyOf: longName)),
          const SyncSignedOut(),
          const SyncSigningIn(),
          const SyncFailure(AuthError.unknown),
          const SyncFailure(
            AuthError.unknown,
            action: SyncAccountAction.signOut,
          ),
          const SyncUnavailable(),
        ]) {
          syncBloc!.show(state);
          await robot.settle(rounds: 3);
          heights.add(robot.height(SemanticsIds.sharingSync));
          // The section's own top and the row's height decide Pairing's
          // place; the Account row above changes with the session (D-6,
          // deferred), so the offset is taken from the row.
          final sync = tester.getRect(robot.byId(SemanticsIds.sharingSync));
          final pair = robot.byId(SemanticsIds.sharingPair);
          if (pair.evaluate().isNotEmpty) {
            pairing.add(tester.getTopLeft(pair).dy - sync.top);
          }
        }
        expect(heights, hasLength(1));
        expect(pairing, hasLength(lessThanOrEqualTo(1)));

        // A reason longer than the slot fills it to its last line and ends
        // there in an ellipsis — every line the slot has, never fewer
        // (review RC3-5); a screen reader and the snackbar say it whole.
        final longer = List.filled(4, longName).join(' ');
        // The loop's failures queued snackbars of their own.
        ScaffoldMessenger.of(
          tester.element(robot.byId(SemanticsIds.sharingSync)),
        ).clearSnackBars();
        await robot.settle();
        syncBloc!.show(
          signedIn(
            flow: SyncBindFailed(
              SyncBindFailure.spaceHeldByAnotherDatabase,
              holderDatabase: longer,
            ),
          ),
        );
        await robot.settle(rounds: 3);
        RenderParagraph drawnText(String text) {
          final drawn = find
              .descendant(
                of: robot.byId(SemanticsIds.sharingSync),
                matching: find.text(text),
              )
              .evaluate()
              .where(SyncSectionRobot.drawn);
          expect(drawn, hasLength(1), reason: text);
          return drawn.single.renderObject! as RenderParagraph;
        }

        final slot = tester.getSize(
          find.descendant(
            of: robot.byId(SemanticsIds.sharingSync),
            matching: find.byType(FormCaptionSlot),
          ),
        );
        final paragraph = drawnText(local.syncFailedHeld(longer));
        expect(paragraph.didExceedMaxLines, isTrue);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        expect(paragraph.size.height, closeTo(slot.height, 0.5));
        expect(
          tester.getSemantics(robot.byId(SemanticsIds.sharingSync)).label,
          contains(local.syncFailedHeld(longer)),
        );
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(local.syncFailedHeld(longer)),
          ),
          findsOneWidget,
        );

        // The heal note, which has no snackbar, fits whole at the phone's
        // own size (review RC3-2).
        if (scale == 1.0) {
          syncBloc!.show(
            signedIn(status: const SyncStatus(unboundAsCopyOf: 'phone_db')),
          );
          await robot.settle(rounds: 3);
          expect(
            drawnText(local.syncUnboundAsCopyOf('phone_db')).didExceedMaxLines,
            isFalse,
          );
        }
        await close(tester);
      });
    }

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('en'), 1.3),
      (Locale('en'), 2.0),
      (Locale('de'), 1.0),
      (Locale('de'), 1.3),
      (Locale('de'), 2.0),
      (Locale('ro'), 1.0),
      (Locale('ro'), 1.3),
      (Locale('ro'), 2.0),
    ]) {
      testWidgets('the Delete row is one height idle, busy, held and failed, '
          '${locale.languageCode} at $scale', (tester) async {
        final robot = await open(
          tester,
          signedIn(status: bound()),
          size: const Size(360, 780),
          locale: locale,
          textScale: scale,
        );
        Future<Set<double>> heights(String id, List<SyncState> states) async {
          final seen = <double>{};
          for (final state in states) {
            syncBloc!.show(state);
            await robot.settle(rounds: 3);
            await robot.reveal(id);
            seen.add(robot.height(id));
          }
          return seen;
        }

        const failed = SyncBindFailed(SyncBindFailure.offline, deleting: true);
        final delete = await heights(SemanticsIds.sharingSyncDelete, [
          signedIn(status: bound()),
          signedIn(status: bound(), flow: const SyncBindDeleting()),
          signedIn(status: bound(pause: SyncPause.accountMismatch)),
          signedIn(status: bound(pause: SyncPause.appOutdated)),
          signedIn(status: bound(pause: SyncPause.spaceDeleted)),
          signedIn(status: bound(), flow: const SyncBindStopping()),
          signedIn(status: bound(), flow: failed),
          SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
          // With a deletion running, whose section follows the page.
          withPending(status: bound(), running: true, removed: 99999),
        ]);

        expect(delete, hasLength(1));
        await close(tester);
      });
    }

    for (final size in const [Size(360, 780), Size(412, 915)]) {
      for (final (locale, scale) in const [
        (Locale('en'), 1.0),
        (Locale('en'), 1.3),
        (Locale('en'), 2.0),
        (Locale('de'), 1.0),
        (Locale('de'), 1.3),
        (Locale('de'), 2.0),
        (Locale('ro'), 1.0),
        (Locale('ro'), 1.3),
        (Locale('ro'), 2.0),
      ]) {
        final cell =
            '${locale.languageCode} at $scale on '
            '${size.width.toInt()} × ${size.height.toInt()}';

        testWidgets('the deletion section is last: nothing above it moves as '
            'it comes, changes and ends, its row is one height in every '
            'state, bound and unbound, and it fits, $cell (review H2)', (
          tester,
        ) async {
          final local = lookupAppLocalizations(locale);
          final pairing = find.text(
            local.pairingSection.toUpperCase(),
            skipOffstage: false,
          );
          late SyncSectionRobot robot;
          final rows = <double>{};
          final errors = await layoutErrorsDuring(() async {
            robot = await open(
              tester,
              signedIn(),
              size: size,
              locale: locale,
              textScale: scale,
            );
            for (final status in [SyncStatus.empty, bound()]) {
              final above = <Rect>{};
              Future<void> measure(
                SyncState state, {
                bool row = true,
                bool anchor = true,
              }) async {
                syncBloc!.show(state);
                await robot.settle(rounds: 3);
                if (anchor) {
                  above.add(
                    await robot.listRect(
                      pairing,
                      () => tester.getRect(pairing),
                    ),
                  );
                }
                if (row) {
                  await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
                  rows.add(robot.height(SemanticsIds.sharingSyncFinishDelete));
                }
              }

              await measure(signedIn(status: status), row: false);
              await measure(withPending(status: status, running: true));
              await measure(
                withPending(status: status, running: true, removed: 99999),
              );
              await measure(
                withPending(status: status, pending: const [], running: true),
              );
              await measure(withPending(status: status));
              // On screen when a delete step begins — which runs bound — it
              // stays, held, through the step and the run it starts
              // (review K6).
              if (status.binding != null) {
                await measure(
                  withPending(status: status, flow: const SyncBindDeleting()),
                );
                await measure(
                  withPending(
                    status: status,
                    flow: const SyncBindDeleting(),
                    running: true,
                  ),
                );
              }
              // Held under another step.
              await measure(
                withPending(status: status, flow: const SyncBindChecking()),
              );
              await measure(
                withPending(status: status, failure: SyncBindFailure.offline),
              );
              await measure(
                withPending(
                  status: status,
                  failure: SyncBindFailure.appOutdated,
                ),
              );
              // A name too long for the slot, which it cuts rather than
              // grows.
              await measure(
                withPending(
                  status: status,
                  pending: [
                    SyncPendingDeletion(
                      space: _left.space,
                      spaceName: 'W' * 40,
                    ),
                  ],
                ),
              );
              // The count of several left, at two digits.
              await measure(
                withPending(status: status, pending: List.filled(12, _left)),
              );
              // The account's own deletion (cloud-multi-user-roadmap §6.1):
              // running over its copies, waiting with and without one left,
              // stopped on a failure, held until an update, and through its
              // own step when the section was already on screen.
              await measure(
                withPending(status: status, running: true, account: true),
              );
              await measure(withPending(status: status, account: true));
              await measure(
                withPending(status: status, pending: const [], account: true),
              );
              await measure(
                withPending(
                  status: status,
                  failure: SyncBindFailure.offline,
                  account: true,
                ),
              );
              await measure(
                withPending(
                  status: status,
                  failure: SyncBindFailure.appOutdated,
                  account: true,
                ),
              );
              await measure(
                withPending(
                  status: status,
                  flow: const SyncAccountDeleting(),
                  account: true,
                ),
              );
              // Ended while the page is open, with and without a count.
              await measure(
                withPending(status: status, pending: const [], removed: 31),
              );
              await measure(withPending(status: status, pending: const []));
              if (status.binding != null) {
                await measure(
                  withPending(
                    status: status,
                    pending: const [],
                    flow: const SyncBindDeleting(),
                  ),
                );
              }
              // A failed sign-out carries no sync status of its own: its
              // rows above are judged elsewhere, this one here, on the
              // deletion status it carries (review K3).
              await measure(
                SyncFailure(
                  AuthError.unknown,
                  action: SyncAccountAction.signOut,
                  user: userA,
                  deletion: withPending(status: status).deletion,
                ),
                anchor: false,
              );
              expect(above, hasLength(1), reason: '$status');
            }

            // The progress line at its widest count is whole, never cut, and
            // so is the count of several left.
            for (final (state, text) in [
              (
                withPending(running: true, removed: 99999),
                local.syncDeleteCloudProgress(99999),
              ),
              (
                withPending(pending: List.filled(12, _left)),
                local.syncDeleteCloudFinishMany(12),
              ),
              (
                withPending(failure: SyncBindFailure.appOutdated),
                local.syncDeleteCloudFinishUpdate,
              ),
              (
                withPending(pending: const [], account: true),
                local.syncDeleteAccountFinishDesc,
              ),
            ]) {
              syncBloc!.show(state);
              await robot.settle(rounds: 3);
              await robot.reveal(SemanticsIds.sharingSyncFinishDelete);
              final drawn = find
                  .descendant(
                    of: robot.byId(SemanticsIds.sharingSyncFinishDelete),
                    matching: find.text(text),
                  )
                  .evaluate()
                  .where(SyncSectionRobot.drawn);
              expect(
                (drawn.single.renderObject! as RenderParagraph)
                    .didExceedMaxLines,
                isFalse,
                reason: text,
              );
            }
          });

          expect(errors.map((e) => e.exceptionAsString()), isEmpty);
          expect(tester.takeException(), isNull);
          expect(rows, hasLength(1));
          await close(tester);
        });
      }
    }

    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      testWidgets('a long space name is what an ellipsis cuts: the fixed '
          'words of the Finish row stay whole, ${locale.languageCode} '
          '(review S2)', (tester) async {
        // Forty characters at their widest, so the name cannot fit the slot.
        final name = 'W' * 40;
        final robot = await open(
          tester,
          withPending(
            pending: [SyncPendingDeletion(space: _left.space, spaceName: name)],
          ),
          size: const Size(360, 780),
          locale: locale,
        );
        final strings = lookupAppLocalizations(locale);
        final text = strings.syncDeleteCloudFinishDesc(name);
        final fixed = strings
            .syncDeleteCloudFinishDesc('')
            .replaceAll(RegExp('[“”„"]'), '')
            .trim();
        final paragraph =
            find
                    .descendant(
                      of: robot.byId(SemanticsIds.sharingSyncFinishDelete),
                      matching: find.text(text),
                    )
                    .evaluate()
                    .where(SyncSectionRobot.drawn)
                    .single
                    .renderObject!
                as RenderParagraph;

        expect(paragraph.didExceedMaxLines, isTrue);
        // The last position drawn lies past the fixed words: only the name
        // is cut.
        final lastDrawn = paragraph.getPositionForOffset(
          Offset(paragraph.size.width, paragraph.size.height - 1),
        );
        expect(
          lastDrawn.offset,
          greaterThanOrEqualTo(text.indexOf(fixed) + fixed.length),
        );
        await close(tester);
      });
    }

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('de'), 2.0),
    ]) {
      testWidgets('an empty database\'s "Sync with" rows keep the check rows\' '
          'rhythm: the caption tight under the name, the same air, '
          '${locale.languageCode} at $scale (final review D-7)', (
        tester,
      ) async {
        final local = lookupAppLocalizations(locale);
        final geometry = <bool, ({double top, double gap, double bottom})>{};
        final heights = <bool, double>{};
        for (final holdsData in [true, false]) {
          await openPicker(
            tester,
            SyncBindPicking(spaces: [_phone, _tablet], holdsData: holdsData),
            size: const Size(360, 780),
            locale: locale,
            textScale: scale,
          );
          final id = SemanticsIds.syncPickerSpace(_tablet.ref.spaceId);
          Rect rectIn(String text) => tester.getRect(
            find.descendant(
              of: find.bySemanticsIdentifier(id),
              matching: find.text(text),
            ),
          );
          final row = tester.getRect(find.bySemanticsIdentifier(id));
          final label = rectIn(
            holdsData ? _tablet.name : local.syncPickerJoin(_tablet.name),
          );
          final caption = rectIn(local.syncPickerNotUsed);
          geometry[holdsData] = (
            top: label.top - row.top,
            gap: caption.top - label.bottom,
            bottom: row.bottom - caption.bottom,
          );
          heights[holdsData] = row.height;
          await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(geometry[false], geometry[true]);
        // One line of name each in English; a longer German name may take a
        // second line, never more air.
        if (scale == 1.0) expect(heights[false], heights[true]);
      });
    }

    for (final locale in const [Locale('de'), Locale('ro')]) {
      testWidgets('the Merge confirm scrolls at 2.0: its whole body is '
          'reachable and nothing overflows, ${locale.languageCode} on 360 '
          '(review D2-1)', (tester) async {
        final local = lookupAppLocalizations(locale);
        final errors = await layoutErrorsDuring(() async {
          await openPicker(
            tester,
            SyncBindPicking(spaces: [_phone], holdsData: true),
            size: const Size(360, 780),
            locale: locale,
            textScale: 2.0,
          );
          await tapId(tester, SemanticsIds.syncPickerMerge);
        });
        expect(errors.map((e) => e.exceptionAsString()), isEmpty);

        final scrollable = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Scrollable),
            )
            .first;
        // With the title clamped (D3-3) the body may fit outright; either
        // way its last line is reachable.
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final body = tester.getRect(find.text(local.syncMergeConfirmBody));
        expect(
          body.bottom,
          lessThanOrEqualTo(tester.getRect(scrollable).bottom + 0.5),
        );
        expect(
          find.bySemanticsIdentifier(SemanticsIds.syncPickerMergeConfirm),
          findsOneWidget,
        );
      });
    }

    for (final (locale, scale) in const [
      (Locale('de'), 1.3),
      (Locale('de'), 2.0),
      (Locale('ro'), 1.3),
      (Locale('ro'), 2.0),
    ]) {
      testWidgets('the picker title fits whole and a pick keeps the sheet '
          'one height, ${locale.languageCode} at $scale on 360', (
        tester,
      ) async {
        final local = lookupAppLocalizations(locale);
        await openPicker(
          tester,
          heldPicking,
          size: const Size(360, 780),
          locale: locale,
          textScale: scale,
        );

        final title = tester.renderObject<RenderParagraph>(
          find.text(local.syncPickerTitle),
        );
        expect(title.didExceedMaxLines, isFalse);
        final sheet = tester.getRect(find.byType(SyncSpacePickerSheet));
        await tapId(tester, SemanticsIds.syncPickerSpace(_tablet.ref.spaceId));
        expect(
          checked(tester, SemanticsIds.syncPickerSpace(_tablet.ref.spaceId)),
          isTrue,
        );
        expect(tester.getRect(find.byType(SyncSpacePickerSheet)), sheet);
      });
    }

    for (final size in const [Size(360, 780), Size(412, 915)]) {
      for (final dark in [false, true]) {
        for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
          final cell =
              '${locale.languageCode} ${dark ? 'dark' : 'light'} 2.0 on '
              '${size.width.toInt()} × ${size.height.toInt()}';

          for (final scale in const [1.0, 1.3, 2.0]) {
            final sections =
                '${locale.languageCode} ${dark ? 'dark' : 'light'} $scale on '
                '${size.width.toInt()} × ${size.height.toInt()}';

            testWidgets('bound and unbound sections fit, $sections', (
              tester,
            ) async {
              late SyncSectionRobot robot;
              final errors = await layoutErrorsDuring(() async {
                robot = await open(
                  tester,
                  signedIn(
                    status: bound(
                      pause: SyncPause.accountMismatch,
                      pending: 12,
                      parked: 3,
                      lastPushAt: DateTime(2020, 3, 4),
                    ),
                    flow: const SyncBindFailed(SyncBindFailure.unknown),
                  ),
                  size: size,
                  locale: locale,
                  textScale: scale,
                  dark: dark,
                );
                await robot.scrollThrough();
                // The Delete row busy, the deletion row under it at its
                // widest count.
                syncBloc!.show(
                  withPending(
                    status: bound(),
                    flow: const SyncBindDeleting(),
                    running: true,
                    removed: 99999,
                  ),
                );
                await robot.settle();
                await robot.scrollThrough();
                syncBloc!.show(
                  withPending(
                    status: bound(),
                    failure: SyncBindFailure.permissionDenied,
                  ),
                );
                await robot.settle();
                await robot.scrollThrough();
                syncBloc!.show(
                  withPending(
                    flow: const SyncBindFailed(
                      SyncBindFailure.spaceHeldByAnotherDatabase,
                      holderDatabase: 'Datenbank des Telefons',
                    ),
                    pending: const [
                      SyncPendingDeletion(
                        space: SyncSpaceRef(
                          ownerUid: 'uid-a',
                          spaceId: 'space-9',
                        ),
                        spaceName: 'Trainingstagebuch und Kalender',
                      ),
                    ],
                    failure: SyncBindFailure.quotaExhausted,
                  ),
                );
                await robot.settle();
                await robot.scrollThrough();
                syncBloc!.show(withPending(running: true, removed: 99999));
                await robot.settle();
                await robot.scrollThrough();
              });

              expect(errors.map((e) => e.exceptionAsString()), isEmpty);
              expect(tester.takeException(), isNull);
              await close(tester);
            });
          }

          testWidgets('the picker fits, $cell', (tester) async {
            final errors = await layoutErrorsDuring(() async {
              await openPicker(
                tester,
                heldPicking,
                size: size,
                locale: locale,
                textScale: 2.0,
                dark: dark,
              );
              await tester.ensureVisible(
                find.bySemanticsIdentifier(SemanticsIds.syncPickerUpload),
              );
              await tester.pumpAndSettle();
            });

            expect(errors.map((e) => e.exceptionAsString()), isEmpty);
            expect(tester.takeException(), isNull);
            expect(
              find.bySemanticsIdentifier(SemanticsIds.syncPickerUpload),
              findsOneWidget,
            );
          });
        }
      }
    }
  });
}
