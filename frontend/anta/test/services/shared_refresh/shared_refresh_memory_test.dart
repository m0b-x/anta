import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/shared_refresh/shared_refresh.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_memory.dart';
import 'package:anta/services/shared_refresh/shared_refresh_plan.dart';
import 'package:anta/services/shared_refresh/shared_refresh_ports.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';

import '../../support/fake_port_registry.dart';

/// The platform as the WorkManager binding drives it: one work per slot,
/// replaced on write, the other slot taken off when no work is running.
class _Works implements SharedRefreshScheduler {
  _Works(this.clock);

  final DateTime Function() clock;
  final Map<SharedRefreshSlot, DateTime> works = {};
  int schedules = 0;
  int cancels = 0;

  /// Every check that was replaced or taken off for one due later.
  final List<String> movedAway = [];

  bool refuses = false;

  @override
  Future<void> schedule(Duration delay, {SharedRefreshSlot? runningIn}) async {
    if (refuses) throw StateError('platform refused');
    schedules++;
    final slot = runningIn?.other ?? SharedRefreshSlot.first;
    final at = clock().add(delay);
    for (final gone in [slot, if (runningIn == null) slot.other]) {
      final was = works.remove(gone);
      if (was != null && at.isAfter(was)) movedAway.add('$was -> $at');
    }
    works[slot] = at;
  }

  @override
  Future<void> cancel({SharedRefreshSlot? runningIn}) async {
    cancels++;
    works.removeWhere((slot, _) => slot != runningIn);
  }

  /// The platform knows what it holds; a test may make it unable to say.
  bool? Function(SharedRefreshSlot slot)? standing;
  final List<SharedRefreshSlot> asked = [];

  @override
  Future<bool?> stands(SharedRefreshSlot slot) async {
    asked.add(slot);
    final scripted = standing;
    return scripted == null ? works.containsKey(slot) : scripted(slot);
  }

  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  }) async {}
}

/// A store that answers nothing, and counts how often it was asked.
class _Unreadable implements SharedRefreshMemory {
  int asked = 0;

  @override
  Future<Map<SharedRefreshSlot, DateTime>> standing() {
    asked++;
    throw StateError('store');
  }

  @override
  Future<void> stands(SharedRefreshSlot slot, DateTime? due) async {}
}

/// The check's plan across isolates (`docs/cloud-shared-freshness.md` §4;
/// the review of what a run arms and reads, R1, R2, R5 and R9): every
/// launch and every run is a new `SharedRefresh` over one memory and one
/// platform.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late _Works platform;
  late SharedRefreshMemory memory;
  late bool shares;

  setUp(() {
    now = DateTime(2026, 11, 14, 8);
    platform = _Works(() => now);
    memory = InProcessSharedRefreshMemory();
    shares = true;
  });

  SharedRefresh isolate({SharedRefreshMemory? over}) => SharedRefresh(
    scheduler: platform,
    shares: () async => shares,
    memory: over ?? memory,
    clock: () => now,
  );

  SharedRefreshNeed alertAt(DateTime fire) =>
      SharedRefreshNeed(fireTimes: [fire]);

  /// What the platform does when a work's time has come: its run, a new
  /// isolate that names its slot, passes and ends.
  Future<int> runDueWorks(SharedRefreshNeed need) async {
    var ran = 0;
    for (final slot in SharedRefreshSlot.values) {
      final due = platform.works[slot];
      if (due == null || due.isAfter(now)) continue;
      platform.works.remove(slot);
      final run = isolate()..workRunning(slot);
      await run.afterAlertPass(need);
      await run.workEnded();
      ran++;
    }
    return ran;
  }

  group('what stands outlives the isolate that planned it (review R2)', () {
    test('cold launches with nothing read never move a check away: the one '
        'that stands is kept until its work runs (probe P1 — before, each '
        'launch replaced it four hours before it was due and none ran in 64 '
        'hours)', () async {
      final need = alertAt(DateTime(2026, 11, 17, 8));
      await isolate().afterAlertPass(need);
      final first = platform.works[SharedRefreshSlot.first];
      expect(first, isNotNull);

      var ran = 0;
      for (var launch = 0; launch < 8; launch++) {
        now = now.add(const Duration(hours: 8));
        ran += await runDueWorks(need);
        await isolate().afterAlertPass(need);
      }

      expect(platform.movedAway, isEmpty);
      expect(ran, greaterThanOrEqualTo(4));
      expect(
        platform.works.values.where((due) => due.isAfter(now)),
        [isNotNull],
        reason: 'one check stands ahead',
      );
    });

    test('a later plan leaves the standing check and asks the platform '
        'nothing; a nearer one replaces it', () async {
      await isolate().afterAlertPass(
        alertAt(now.add(const Duration(hours: 6))),
      );
      final standing = platform.works[SharedRefreshSlot.first]!;

      now = now.add(const Duration(minutes: 30));
      await isolate().afterAlertPass(
        alertAt(now.add(const Duration(hours: 6))),
      );
      expect(platform.schedules, 1);
      expect(platform.works[SharedRefreshSlot.first], standing);

      await isolate().afterAlertPass(
        alertAt(now.add(const Duration(hours: 1))),
      );
      expect(platform.schedules, 2);
      expect(
        platform.works[SharedRefreshSlot.first],
        now.add(const Duration(minutes: 30)),
      );
    });

    test('a check that is due and has not run waits for the network: a '
        'pass with nothing read neither cancels nor replaces it, whatever '
        'the plan says now (probe P2 — before, it was cancelled eight '
        'minutes before the ring)', () async {
      final fire = DateTime(2026, 11, 14, 11);
      await isolate().afterAlertPass(alertAt(fire));
      final due = DateTime(2026, 11, 14, 9, 30);
      expect(platform.works, {SharedRefreshSlot.first: due});

      now = DateTime(2026, 11, 14, 10, 52);
      // The plan says "none": the ring is nearer than any check.
      final resumed = isolate();
      await resumed.afterAlertPass(alertAt(fire));
      expect(resumed.planned, SharedRefreshPlanned.stands);
      // The plan says twelve hours out.
      await isolate().afterAlertPass(
        SharedRefreshNeed(fireTimes: [fire], alertAhead: true),
      );
      // Nothing of the partner's rings any more, and the database shares.
      await isolate().afterAlertPass(const SharedRefreshNeed());

      expect(platform.works, {SharedRefreshSlot.first: due});
      expect(platform.schedules, 1);
      expect(platform.cancels, 0);
    });

    test('it goes for cause alone — the database no longer shares — and its '
        'memory with it', () async {
      await isolate().afterAlertPass(alertAt(DateTime(2026, 11, 14, 11)));
      now = DateTime(2026, 11, 14, 10, 52);
      shares = false;

      // The process that scheduled it sees the pairing end.
      final app = isolate()..workRunning(SharedRefreshSlot.second);
      await app.workEnded();
      await app.afterAlertPass(SharedRefreshNeed.none);

      expect(platform.works, isEmpty);
      expect(await memory.standing(), isEmpty);
    });

    test('a pass that follows a read plans from now, as it always did: the '
        'due check is replaced, and a later plan is followed', () async {
      await isolate().afterAlertPass(alertAt(DateTime(2026, 11, 14, 11)));
      now = DateTime(2026, 11, 14, 10);

      final app = isolate()..readMade();
      await app.afterAlertPass(alertAt(DateTime(2026, 11, 14, 20)));

      expect(platform.works, {
        SharedRefreshSlot.first: DateTime(2026, 11, 14, 15),
      });
    });

    test('the work that runs stands no more for any isolate: its slot is '
        'written off as it starts, and the launch after it plans against '
        'the successor', () async {
      final need = alertAt(DateTime(2026, 11, 17, 8));
      await isolate().afterAlertPass(need);
      now = now.add(const Duration(hours: 12));

      expect(await runDueWorks(need), 1);

      final standing = await memory.standing();
      expect(standing.keys, [SharedRefreshSlot.second]);
      expect(standing.values.single, platform.works[SharedRefreshSlot.second]);
      await isolate().afterAlertPass(need);
      expect(platform.schedules, 2, reason: 'the launch asked nothing');
    });

    test('a memory that cannot be read is no memory: the pass plans as a '
        'first one — a later check over a nearer, never none', () async {
      await isolate().afterAlertPass(
        alertAt(now.add(const Duration(hours: 6))),
      );
      now = now.add(const Duration(minutes: 30));

      final blind = isolate(over: _Unreadable());
      await blind.afterAlertPass(alertAt(now.add(const Duration(hours: 6))));

      expect(blind.planned, SharedRefreshPlanned.stands);
      expect(platform.schedules, 2);
    });

    test('an account that never paired asks the memory nothing', () async {
      final store = _Unreadable();
      final never = isolate(over: store);

      await never.afterAlertPass(SharedRefreshNeed.none);
      await never.afterAlertPass(SharedRefreshNeed.none);

      expect(never.planned, SharedRefreshPlanned.notWanted);
      expect(store.asked, 0);
      expect(platform.cancels, 0);
    });

    test('in the preferences it is a key per slot, re-read each time — '
        'another isolate\'s write is the one that counts — and a removal '
        'is asked of the store whatever this isolate\'s copy holds', () async {
      SharedPreferences.setMockInitialValues({});
      const memory = PreferencesSharedRefreshMemory();
      final store = SharedPreferencesStorePlatform.instance;
      final first = DateTime(2026, 11, 14, 20);
      final second = DateTime(2026, 11, 15, 8);

      await memory.stands(SharedRefreshSlot.first, first);
      expect(await memory.standing(), {SharedRefreshSlot.first: first});
      expect(
        (await SharedPreferences.getInstance()).getInt(
          SettingsKeys.sharedRefreshStandsFirst,
        ),
        first.millisecondsSinceEpoch,
      );

      // A run's isolate schedules its successor behind this one's copy.
      await store.setValue(
        'Int',
        'flutter.${SettingsKeys.sharedRefreshStandsSecond}',
        second.millisecondsSinceEpoch,
      );
      expect(await memory.standing(), {
        SharedRefreshSlot.first: first,
        SharedRefreshSlot.second: second,
      });

      await store.setValue(
        'Int',
        'flutter.${SettingsKeys.sharedRefreshStandsFirst}',
        second.millisecondsSinceEpoch,
      );
      await store.remove('flutter.${SettingsKeys.sharedRefreshStandsFirst}');
      await store.setValue(
        'Int',
        'flutter.${SettingsKeys.sharedRefreshStandsFirst}',
        first.millisecondsSinceEpoch,
      );
      await memory.stands(SharedRefreshSlot.first, null);
      await memory.stands(SharedRefreshSlot.second, null);
      expect(await store.getAll(), isEmpty);
    });
  });

  group('the memory is believed only where the platform agrees (closing '
      'review, K1)', () {
    /// A memory that came back with the phone's backup, or whose work was
    /// consumed or lost with nobody writing it off: an entry, and no work.
    Future<void> remembered(Duration fromNow) =>
        memory.stands(SharedRefreshSlot.first, now.add(fromNow));

    final ahead = SharedRefreshNeed(fireTimes: [DateTime(2026, 11, 17, 8)]);

    test('a due check the platform does not hold is dropped and the pass '
        'plans as a first one — once: three later passes left it "standing" '
        'for good and asked the platform nothing (probe R8-C)', () async {
      await remembered(const Duration(minutes: -1));
      final app = isolate();

      for (var pass = 0; pass < 3; pass++) {
        await app.afterAlertPass(ahead);
      }

      expect(app.planned, SharedRefreshPlanned.stands);
      expect(platform.schedules, 1);
      expect(platform.asked, [SharedRefreshSlot.first]);
      expect(platform.works[SharedRefreshSlot.first], isNotNull);
      expect(
        (await memory.standing())[SharedRefreshSlot.first],
        platform.works[SharedRefreshSlot.first],
      );
    });

    test('a check that lies ahead in the memory and not on the platform — '
        'a phone set up from another\'s backup — is planned anew, though the '
        'plan is the later one', () async {
      await remembered(const Duration(hours: 1));

      await isolate().afterAlertPass(ahead);

      expect(platform.schedules, 1);
      expect(
        platform.works[SharedRefreshSlot.first],
        now.add(const Duration(hours: 12)),
      );
    });

    test('a platform that cannot tell changes nothing: the memory is '
        'trusted as before', () async {
      platform.standing = (_) => null;
      await remembered(const Duration(minutes: -1));

      final app = isolate();
      await app.afterAlertPass(ahead);

      expect(app.planned, SharedRefreshPlanned.stands);
      expect(platform.schedules, 0);
      expect(platform.asked, [SharedRefreshSlot.first]);
    });

    test('"cannot tell" is asked again at the next pass — it is no belief '
        'for the isolate\'s life — and an answer is asked for once (second '
        'look, N6)', () async {
      platform.standing = (_) => null;
      await remembered(const Duration(minutes: -1));
      final app = isolate();

      await app.afterAlertPass(ahead);
      await app.afterAlertPass(ahead);
      expect(platform.asked, hasLength(2));

      platform.standing = (_) => true;
      await app.afterAlertPass(ahead);
      await app.afterAlertPass(ahead);
      expect(platform.asked, hasLength(3));
      expect(platform.schedules, 0);
    });

    test('one question per isolate for an entry while it lies ahead, and '
        'one more when it is first found due — never one per pass', () async {
      await isolate().afterAlertPass(ahead);
      expect(platform.asked, isEmpty, reason: 'it scheduled the work itself');

      final app = isolate();
      for (var pass = 0; pass < 3; pass++) {
        now = now.add(const Duration(hours: 1));
        await app.afterAlertPass(ahead);
      }
      expect(platform.asked, [SharedRefreshSlot.first]);

      now = now.add(const Duration(hours: 12));
      for (var pass = 0; pass < 3; pass++) {
        await app.afterAlertPass(ahead);
      }
      expect(platform.asked, [
        SharedRefreshSlot.first,
        SharedRefreshSlot.first,
      ]);
      expect(platform.schedules, 1);
    });

    test('an account that never paired asks the platform nothing', () async {
      await isolate().afterAlertPass(SharedRefreshNeed.none);

      expect(platform.asked, isEmpty);
    });

    test('a check\'s work served by an app in which sync did not come up is '
        'written off where every isolate reads it (probe R8-C, F1b): the '
        'app bound a memory of its own there, and the slot stood "due" in '
        'the preferences for good', () async {
      final due = DateTime.now().subtract(const Duration(minutes: 1));
      SharedPreferences.setMockInitialValues({
        SettingsKeys.sharedRefreshStandsFirst: due.millisecondsSinceEpoch,
        SettingsKeys.sharedRefreshPlanned: '1',
      });
      SharedRefreshAvailability.debugSupported = true;
      final registry = FakePortRegistry();
      await GetIt.I.reset();
      addTearDown(() async {
        SharedRefreshApp.resetForTesting();
        SharedRefreshAvailability.debugSupported = null;
        await GetIt.I.reset();
      });
      // As the launch binds it where sync cannot run: no platform, a
      // memory of the isolate alone, and no sync gateway.
      GetIt.I.registerSingleton<SharedRefresh>(
        SharedRefresh(
          scheduler: const NoOpSharedRefreshScheduler(),
          shares: () async => false,
        ),
      );
      SharedRefreshApp.beginLaunch(registry: registry);
      SharedRefreshApp.launched();

      final end = await SharedRefreshTrigger(
        steps: AppSharedRefreshRunSteps(SharedRefreshSlot.first),
        port: SharedRefreshRunPort(
          registry: registry,
          pingTimeout: const Duration(milliseconds: 200),
        ),
      ).fire();

      expect(end, SharedRefreshEnd.forwarded);
      expect(await const PreferencesSharedRefreshMemory().standing(), isEmpty);
    });
  });

  group('"wanted but nothing stands" is not "not wanted" (review R1)', () {
    test('a schedule the platform refuses leaves the plan wanted and not '
        'standing: a check\'s work fails on it and is run again, a '
        'message\'s is left its answer (probe P3)', () async {
      platform.refuses = true;
      final run = isolate()..workRunning(SharedRefreshSlot.first);
      run.passAwaited();
      await run.afterAlertPass(alertAt(DateTime(2026, 11, 15, 8)));

      expect(run.planned, SharedRefreshPlanned.wantedNotStanding);
      expect(run.scheduled, isFalse);
      expect(
        () => SharedRefreshApp.worthAfterPass(run, check: true),
        throwsA(isA<SharedPassFailed>()),
      );
      expect(SharedRefreshApp.worthAfterPass(run, check: false), (
        check: false,
        poke: true,
      ));
    });

    test('a pass that never reported — its setup failed before the plan was '
        'told — is no answer for either work', () async {
      // An earlier pass of the isolate did report: its answer is not this
      // pass's.
      final run = isolate();
      await run.afterAlertPass(const SharedRefreshNeed());
      run.passAwaited();

      for (final check in [true, false]) {
        expect(
          () => SharedRefreshApp.worthAfterPass(run, check: check),
          throwsA(isA<SharedPassFailed>()),
        );
      }
    });

    test('a pass that reported no need is "not wanted", as before', () async {
      final run = isolate()..passAwaited();
      await run.afterAlertPass(const SharedRefreshNeed());

      expect(SharedRefreshApp.worthAfterPass(run, check: true), (
        check: false,
        poke: false,
      ));
    });
  });

  group('the forwarded path (review R5)', () {
    test('a pass that reports nothing answers the asker failed, where a '
        'swallowed one answered "done" with no successor', () async {
      final app = isolate();

      await expectLater(
        SharedRefreshApp.forwardedRead(
          SharedRefreshSlot.first,
          refresh: app,
          read: () async => true,
          alertPass: () =>
              SharedRefreshApp.passThatReports(app, () async {}, check: true),
        ),
        throwsA(isA<SharedPassFailed>()),
      );
    });

    test('and one the platform refused the successor of, the same', () async {
      final app = isolate();
      platform.refuses = true;

      await expectLater(
        SharedRefreshApp.forwardedRead(
          SharedRefreshSlot.first,
          refresh: app,
          read: () async => true,
          alertPass: () => SharedRefreshApp.passThatReports(
            app,
            () => app.afterAlertPass(alertAt(DateTime(2026, 11, 15, 8))),
            check: true,
          ),
        ),
        throwsA(isA<SharedPassFailed>()),
      );
    });

    test('the read is spent with its pass, reported or not: a later pass '
        'that has nothing to do with it moves no check away on its '
        'strength', () async {
      final app = isolate();
      await app.afterAlertPass(alertAt(now.add(const Duration(hours: 6))));
      final standing = platform.works[SharedRefreshSlot.first];

      await expectLater(
        SharedRefreshApp.forwardedRead(
          null,
          refresh: app,
          read: () async => true,
          alertPass: () async => throw const SharedPassFailed('quiet'),
        ),
        throwsA(isA<SharedPassFailed>()),
      );
      now = now.add(const Duration(minutes: 30));
      await app.afterAlertPass(alertAt(now.add(const Duration(hours: 6))));

      expect(platform.works[SharedRefreshSlot.first], standing);
      expect(platform.schedules, 1);
    });

    test('two check works forwarded at once converge on one successor '
        '(probe P4)', () async {
      final app = isolate();
      final need = alertAt(DateTime(2026, 11, 15, 8));
      platform.works[SharedRefreshSlot.first] = now;
      platform.works[SharedRefreshSlot.second] = now;
      final a = Completer<void>();
      final b = Completer<void>();
      Future<void> forwarded(SharedRefreshSlot slot, Completer<void> gate) =>
          SharedRefreshApp.forwardedRead(
            slot,
            refresh: app,
            read: () async {
              await gate.future;
              return true;
            },
            alertPass: () => app.afterAlertPass(need),
          );

      final first = forwarded(SharedRefreshSlot.first, a);
      final second = forwarded(SharedRefreshSlot.second, b);
      a.complete();
      await first;
      now = now.add(const Duration(seconds: 2));
      b.complete();
      await second;

      expect(platform.schedules, 1);
      expect(platform.works.values.where((due) => due.isAfter(now)), [
        isNotNull,
      ]);
      expect((await memory.standing()).values, hasLength(1));
    });
  });

  group('a forwarded message read asks the worth first (review R9)', () {
    Future<bool> readFor({
      required bool inFront,
      SharedRefreshNeed? lastPass,
      SharedRefreshSlot? slot,
    }) async {
      final app = isolate();
      if (lastPass != null) await app.afterAlertPass(lastPass);
      var read = false;
      await SharedRefreshApp.forwardedRead(
        slot,
        pair: slot == null ? 'pair-1' : null,
        holdsPair: (_) async => true,
        inFront: () => inFront,
        refresh: app,
        read: () async => read = true,
        alertPass: () async {},
      );
      return read;
    }

    const nothingOfMine = SharedRefreshNeed();
    const anAlertOfMine = SharedRefreshNeed(alertDefined: true);

    test('alive and not in front, it reads only when the last pass found a '
        'message worth a read — as a run does', () async {
      expect(await readFor(inFront: false, lastPass: nothingOfMine), isFalse);
      expect(await readFor(inFront: false, lastPass: anAlertOfMine), isTrue);
    });

    test('in front it reads as it always did', () async {
      expect(await readFor(inFront: true, lastPass: nothingOfMine), isTrue);
    });

    test(
      'not known is not "no": before any pass has reported, it reads',
      () async {
        expect(await readFor(inFront: false), isTrue);
      },
    );

    test('the check\'s own work is not asked: it reads, and plans', () async {
      expect(
        await readFor(
          inFront: false,
          lastPass: nothingOfMine,
          slot: SharedRefreshSlot.first,
        ),
        isTrue,
      );
    });
  });
}
