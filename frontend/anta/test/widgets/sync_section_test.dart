import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
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
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
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
  }) => SyncStatus(
    binding: _binding,
    pause: pause,
    activity: activity,
    pendingCount: pending,
    parkedCount: parked,
    downloadedRows: downloaded,
    lastFailure: failure,
    lastPushAt: lastPushAt,
  );

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
      'up to date': (bound(), l10n.syncUpToDate, true),
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
      'paused on the quota': (
        bound(pause: SyncPause.quotaExhausted),
        l10n.syncPausedQuota,
        false,
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
        false,
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

    testWidgets('the details carry the last sync, the changes waiting and '
        'the held-back rows on a line of their own', (tester) async {
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
          '${l10n.syncPendingCount(2)}\n${l10n.syncParkedCount(1)}',
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
      await close(tester);
    });

    testWidgets('Sync now sends one run; disabled while paused, it sends '
        'nothing', (tester) async {
      final robot = await open(tester, signedIn(status: bound()));
      final before = syncBloc!.events.length;

      await robot.tap(SemanticsIds.sharingSyncNow);
      expect(syncBloc!.events.sublist(before), [const SyncNowRequested()]);

      syncBloc!.show(signedIn(status: bound(pause: SyncPause.noAccess)));
      await robot.settle();
      final paused = syncBloc!.events.length;
      await robot.tap(SemanticsIds.sharingSyncNow);
      expect(syncBloc!.events.length, paused);
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
      expect(find.text(l10n.exitApp), findsOneWidget);
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

      expect(find.text(l10n.syncPickerSpaces.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.syncPickerHoldsData.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.syncPickerHeldBy('phone_db')), findsOneWidget);
      expect(
        enabled(tester, SemanticsIds.syncPickerSpace(_phone.ref.spaceId)),
        isFalse,
      );
      expect(find.text(l10n.syncPickerMerge('Tablet')), findsOneWidget);
      expect(find.text(l10n.syncPickerDownload('Tablet')), findsOneWidget);

      await tapId(tester, SemanticsIds.syncPickerSpace(_laptop.ref.spaceId));
      expect(answer().returned, isFalse);
      expect(find.text(l10n.syncPickerMerge('Laptop')), findsOneWidget);

      // The held space cannot be picked.
      await tapId(tester, SemanticsIds.syncPickerSpace(_phone.ref.spaceId));
      expect(find.text(l10n.syncPickerMerge('Laptop')), findsOneWidget);

      await tapId(tester, SemanticsIds.syncPickerDownload);
      expect(answer().event, DownloadSpaceRequested(_laptop));
    });

    testWidgets('one space: no list, the choices name it, and each carries '
        'its line', (tester) async {
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
      expect(label(tester, SemanticsIds.syncPickerMerge), contains('Phone'));
      expect(
        label(tester, SemanticsIds.syncPickerMerge),
        contains(l10n.syncPickerMergeDesc),
      );
      expect(
        label(tester, SemanticsIds.syncPickerDownload),
        contains(l10n.syncPickerDownloadDesc),
      );
      expect(
        label(tester, SemanticsIds.syncPickerUpload),
        contains(l10n.syncPickerUploadDesc),
      );

      await tapId(tester, SemanticsIds.syncPickerMerge);
      expect(answer().event, MergeIntoSpaceRequested(_phone));
    });

    testWidgets('one space another database holds: merge and download stay, '
        'disabled, naming the holder; upload still answers', (tester) async {
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
      expect(find.text(l10n.syncPickerHeldBy('phone_db')), findsNWidgets(2));
      await tapId(tester, SemanticsIds.syncPickerMerge);
      expect(answer().returned, isFalse);

      await tapId(tester, SemanticsIds.syncPickerUpload);
      expect(answer().event, const UploadAsNewSpaceRequested());
    });

    testWidgets('several spaces, nothing held here: picking a space syncs '
        'with it, with no merge or download offered', (tester) async {
      final answer = await openPicker(
        tester,
        SyncBindPicking(spaces: [_phone, _tablet], holdsData: false),
      );

      expect(find.text(l10n.syncPickerHoldsData.toUpperCase()), findsNothing);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.syncPickerMerge),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.syncPickerDownload),
        findsNothing,
      );
      expect(find.text(l10n.syncPickerLastUsed('Mar 4, 2020')), findsOneWidget);
      expect(find.text(l10n.syncPickerNotUsed), findsOneWidget);

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
