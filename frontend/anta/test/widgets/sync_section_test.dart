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
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/utils/auth_error.dart';
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

  SyncStatus bound({
    SyncPause pause = SyncPause.none,
    SyncActivity activity = SyncActivity.idle,
    int pending = 0,
    int parked = 0,
    int downloaded = 0,
    SyncFailureInfo? failure,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
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
        final caption = find.descendant(of: row, matching: find.text(reason));
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
              .map((o) => o.opacity),
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

    testWidgets('the details carry the last sync on one line and one count '
        'on the next: the changes waiting before the held-back ones', (
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
          '${l10n.syncLastSynced('Mar 4, 2020')}\n${l10n.syncPendingCount(2)}',
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
          '${l10n.syncLastSynced('Mar 4, 2020')}\n${l10n.syncParkedCount(1)}',
        ),
        isTrue,
      );
      await close(tester);
    });

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
        robot.shows(SemanticsIds.sharingSyncStatus, l10n.syncPendingCount(3)),
        isFalse,
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

    testWidgets('Sync now sends one run — on the quota and no-access pauses '
        'too, which it exists to end; paused where a run can do nothing, it '
        'sends nothing', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));

      for (final pause in const [
        SyncPause.none,
        SyncPause.quotaExhausted,
        SyncPause.noAccess,
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

    testWidgets('a sign-in keeps the bound rows on the last status known, '
        'through a failure too; Sync now and Stop wait for an answer', (
      tester,
    ) async {
      final robot = await open(
        tester,
        SyncSignedOut(status: bound(pause: SyncPause.signedOut)),
        signedIn: false,
      );

      for (final state in const [
        SyncSigningIn(),
        SyncFailure(AuthError.unknown),
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
        expect(robot.tile(SemanticsIds.sharingSyncStop).enabled, isFalse);
      }
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
        "bar's arrow both stay — and idle, back leaves", (tester) async {
      await boot(user: userA);
      final robot = SyncSectionRobot(tester);
      await robot.pumpPage(pushed: true);

      for (final (status, flow) in [
        (SyncStatus.empty, const SyncBindChecking()),
        (SyncStatus.empty, const SyncBindBinding()),
        (bound(), const SyncBindStopping()),
      ]) {
        syncBloc!.show(signedIn(status: status, flow: flow));
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

    testWidgets('a failed stop is worded as the stop and kept on the stop '
        'row', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));

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
        true,
      );
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
      expect(answer().event, MergeIntoSpaceRequested(_phone));
    });

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
      bound(pending: 2, failure: failed(SyncGatewayFailure.offline)),
      bound(parked: 1, failure: failed(SyncGatewayFailure.unknown)),
      for (final pause in SyncPause.values) bound(pause: pause, parked: 2),
    ];

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('de'), 1.3),
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
        }

        expect(heights, hasLength(1));
        expect(syncNow, hasLength(1));
        expect(stop, hasLength(1));
        await close(tester);
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

          testWidgets('bound and unbound sections fit, $cell', (tester) async {
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
                textScale: 2.0,
                dark: dark,
              );
              await robot.scrollThrough();
              syncBloc!.show(
                signedIn(
                  flow: const SyncBindFailed(
                    SyncBindFailure.spaceHeldByAnotherDatabase,
                    holderDatabase: 'Datenbank des Telefons',
                  ),
                ),
              );
              await robot.settle();
              await robot.scrollThrough();
            });

            expect(errors.map((e) => e.exceptionAsString()), isEmpty);
            expect(tester.takeException(), isNull);
            await close(tester);
          });

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
