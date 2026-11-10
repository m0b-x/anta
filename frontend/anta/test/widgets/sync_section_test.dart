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
