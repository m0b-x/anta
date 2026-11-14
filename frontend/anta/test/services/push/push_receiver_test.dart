import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/push_constants.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/push/firebase_push_address_source.dart';
import 'package:anta/services/push/push_messaging.dart';
import 'package:anta/services/push/push_receiver.dart';
import 'package:anta/services/shared_refresh/shared_refresh_message_gate.dart';

import '../../support/fake_push.dart';
import '../../support/fake_shared_refresh_scheduler.dart';
import '../../support/scripted_prefs_store.dart';
import '../../support/waiting_note.dart';

class _Messaging implements PushMessaging {
  final StreamController<Map<String, dynamic>> controller =
      StreamController.broadcast();
  int listens = 0;
  int registrations = 0;

  @override
  Stream<Map<String, dynamic>> get foreground {
    listens++;
    return controller.stream;
  }

  /// What [SettingsKeys.pushExpeditedWork] held at each hand-over.
  final List<String?> storedAtHandOver = [];

  @override
  Future<void> registerBackgroundHandler() async {
    storedAtHandOver.add(
      (await SharedPreferences.getInstance()).getString(
        SettingsKeys.pushExpeditedWork,
      ),
    );
    registrations++;
  }
}

/// A platform that refuses every message work, recording whether each was
/// asked expedited.
class _Refusing extends FakeSharedRefreshScheduler {
  final List<bool> askedExpedited = [];

  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  }) {
    askedExpedited.add(expedited);
    throw StateError('no platform');
  }
}

/// A relay message (`docs/cloud-shared-freshness.md` §7, "The message"): in
/// front it asks for the open database's shared read, a burst as one; with
/// the app not in front it starts the check's work and touches nothing
/// else. Nothing is listened to on an install that holds no address.
void main() {
  late _Messaging messaging;
  late FakePushAddressSource addresses;
  late int reads;
  late String? openPair;
  late Future<int?> Function() sdkLevel;
  late int openAsked;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugForgetPushEngineResigned();
    messaging = _Messaging();
    addresses = FakePushAddressSource();
    reads = 0;
    openAsked = 0;
    openPair = 'pair-1';
    sdkLevel = () async => 34;
  });

  PushReceiver receiver([FakeAsync? async]) => PushReceiver(
    messaging: messaging,
    addresses: addresses,
    openPair: () async {
      openAsked++;
      return openPair;
    },
    readShared: () async => reads++,
    sdkLevel: () => sdkLevel(),
    prefs: SharedPreferences.getInstance(),
    clock: async == null
        ? DateTime.now
        : () => DateTime(2026, 11, 13, 12).add(async.elapsed),
  );

  Map<String, dynamic> shared(String pair) => {'t': 'shared', 'p': pair};

  group('listening', () {
    test('an install that holds no address listens to nothing and hands the '
        'platform nothing', () async {
      await receiver().start();
      expect(messaging.listens, 0);
      expect(messaging.registrations, 0);
      expect(messaging.controller.hasListener, isFalse);
    });

    test('an install that only owes the end of an address listens to '
        'nothing and hands the platform nothing', () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushDeleteOwed: '1',
      });
      final owing = PushReceiver(
        messaging: messaging,
        addresses: FirebasePushAddressSource(
          prefs: SharedPreferences.getInstance(),
        ),
        openPair: () async => openPair,
        readShared: () async => reads++,
        sdkLevel: () => sdkLevel(),
        prefs: SharedPreferences.getInstance(),
      );
      await owing.start();
      expect(messaging.listens, 0);
      expect(messaging.registrations, 0);
    });

    test('one that holds an address listens at launch and hands the handler '
        'over; each address taken into use hands it over again', () async {
      addresses.held = true;
      final listening = receiver();
      await listening.start();
      await listening.addressInUse();

      expect(messaging.listens, 1);
      expect(messaging.registrations, 2);
      await listening.dispose();
    });
  });

  group('whether a message\'s work is expedited', () {
    test('stored before each hand-over, from the API level: 30 no, 31 and '
        '36 yes, no answer or a failing answer no', () async {
      final listening = receiver();
      for (final (level, stored) in [(30, null), (31, '1'), (36, '1')]) {
        sdkLevel = () async => level;
        await listening.addressInUse();
        expect(messaging.storedAtHandOver.last, stored, reason: 'API $level');
      }
      sdkLevel = () async => null;
      await listening.addressInUse();
      expect(messaging.storedAtHandOver.last, isNull, reason: 'no answer');

      sdkLevel = () async => 36;
      await listening.addressInUse();
      sdkLevel = () async => throw StateError('no activity');
      await listening.addressInUse();
      expect(messaging.storedAtHandOver.last, isNull, reason: 'a failure');

      expect(messaging.registrations, 6, reason: 'every hand-over writes');
      await listening.dispose();
    });

    test('a write that fails still hands the handler over', () async {
      final listening = PushReceiver(
        messaging: messaging,
        addresses: addresses,
        openPair: () async => openPair,
        readShared: () async => reads++,
        sdkLevel: () async => 36,
        prefs: Future<SharedPreferences>.error(StateError('no preferences'))
          ..ignore(),
      );
      await listening.addressInUse();

      expect(messaging.registrations, 1);
      expect(messaging.listens, 1);
      await listening.dispose();
    });
  });

  group('in front', () {
    test('a burst for the open database\'s pair is one read, a moment '
        'later', () {
      fakeAsync((async) {
        final listening = receiver(async);
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        for (var i = 0; i < 5; i++) {
          messaging.controller.add(shared('pair-1'));
        }
        async.flushMicrotasks();
        expect(reads, 0);
        async.elapse(const Duration(seconds: 2));
        expect(reads, 1);

        async.elapse(const Duration(minutes: 1));
        messaging.controller.add(shared('pair-1'));
        async.elapse(const Duration(seconds: 2));
        expect(reads, 2, reason: 'a message past the floor reads at once');
      });
    });

    test('five messages in ten seconds are two reads: the first once its '
        'gather ends, the second at the floor\'s end', () {
      fakeAsync((async) {
        final listening = receiver(async);
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        for (var i = 0; i < 5; i++) {
          messaging.controller.add(shared('pair-1'));
          async.elapse(const Duration(milliseconds: 2500));
        }
        expect(reads, 1);

        // The first read was asked at two seconds; twelve and a half have
        // gone.
        async.elapse(const Duration(seconds: 49));
        expect(reads, 1, reason: 'still inside the floor');
        async.elapse(const Duration(milliseconds: 500));
        expect(reads, 2);
        async.elapse(const Duration(minutes: 5));
        expect(reads, 2, reason: 'one read for all that came within it');
      });
    });

    test('a burst that mixes two pairs is one read when one is the open '
        'database\'s', () {
      fakeAsync((async) {
        final listening = receiver(async);
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        messaging.controller
          ..add(shared('pair-9'))
          ..add(shared('pair-1'))
          ..add(shared('pair-9'));
        async.elapse(const Duration(seconds: 3));
        expect(reads, 1);
      });
    });

    test('a read that throws is logged, and the next message still reads', () {
      fakeAsync((async) {
        var asked = 0;
        final listening = PushReceiver(
          messaging: messaging,
          addresses: addresses,
          openPair: () async => openPair,
          readShared: () async {
            asked++;
            if (asked == 1) throw StateError('engine gone');
          },
          sdkLevel: () => sdkLevel(),
          prefs: SharedPreferences.getInstance(),
          clock: () => DateTime(2026, 11, 13, 12).add(async.elapsed),
        );
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        messaging.controller.add(shared('pair-1'));
        async.elapse(const Duration(seconds: 3));
        expect(asked, 1);

        async.elapse(const Duration(minutes: 1));
        messaging.controller.add(shared('pair-1'));
        async.elapse(const Duration(seconds: 3));
        expect(asked, 2);
      });
    });

    test('dispose stops listening and drops a gather in progress', () {
      fakeAsync((async) {
        final listening = receiver(async);
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        messaging.controller.add(shared('pair-1'));
        async.flushMicrotasks();
        unawaited(listening.dispose());
        async.elapse(const Duration(seconds: 3));
        expect(reads, 0);
        expect(messaging.controller.hasListener, isFalse);
      });
    });

    test('a message for another database\'s pair takes no floor', () {
      fakeAsync((async) {
        final listening = receiver(async);
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        messaging.controller.add(shared('pair-9'));
        async.elapse(const Duration(seconds: 3));
        messaging.controller.add(shared('pair-1'));
        async.elapse(const Duration(seconds: 2));
        expect(reads, 1);
      });
    });

    test('another database\'s pair, an unknown kind and a malformed message '
        'are ignored', () {
      fakeAsync((async) {
        final listening = receiver();
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        messaging.controller
          ..add(shared('pair-9'))
          ..add({'t': 'other', 'p': 'pair-1'})
          ..add({'t': 'shared'})
          ..add({'t': 'shared', 'p': ''})
          ..add({'t': 'shared', 'p': 7});
        async.elapse(const Duration(seconds: 3));
        expect(reads, 0);

        openPair = null;
        messaging.controller.add(shared('pair-1'));
        async.elapse(const Duration(seconds: 3));
        expect(reads, 0, reason: 'the open database holds no pair');
      });
    });

    test('a pair the relay would never name does not ask for the open '
        'pair', () {
      fakeAsync((async) {
        final listening = receiver();
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        messaging.controller
          ..add(shared('x' * 200000))
          ..add(shared('pair/1'));
        async.elapse(const Duration(seconds: 3));
        expect(openAsked, 0);
        expect(reads, 0);
      });
    });
  });

  group('not in front', () {
    tearDown(() => GetIt.I.reset());

    test('a message for a pair schedules the check\'s message work with the '
        'pair, and nothing else is built: it runs with no registrations at '
        'all', () async {
      await GetIt.I.reset();
      final scheduler = FakeSharedRefreshScheduler();

      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => false,
      );

      expect(scheduler.calls, ['message:pair-1']);
    });

    test('the stored answer: written, the work is expedited; missing, it is '
        'not', () async {
      final scheduler = FakeSharedRefreshScheduler();
      await handleBackgroundPush(shared('pair-1'), scheduler: scheduler);

      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushExpeditedWork: '1',
      });
      await handleBackgroundPush(shared('pair-1'), scheduler: scheduler);

      expect(scheduler.calls, ['message:pair-1', 'message:pair-1:expedited']);
    });

    test('expedited as the stored answer says; an answer that cannot be read '
        'is not expedited', () async {
      final scheduler = FakeSharedRefreshScheduler();
      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => true,
      );
      await handleBackgroundPush(
        shared('pair-2'),
        scheduler: scheduler,
        expedited: () async => throw StateError('unreadable'),
      );

      expect(scheduler.calls, ['message:pair-1:expedited', 'message:pair-2']);
    });

    test('an expedited work the platform refuses is scheduled once more, '
        'not expedited', () async {
      final scheduler = FakeSharedRefreshScheduler()..failNext = true;
      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => true,
      );

      expect(scheduler.calls, ['message:pair-1']);
    });

    test('a second refusal is logged, never thrown, and not tried a third '
        'time; a plain work refused is not tried again', () async {
      final logged = <String>[];
      final printer = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add('$message');
      addTearDown(() => debugPrint = printer);
      final scheduler = _Refusing();

      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => true,
      );
      expect(scheduler.askedExpedited, [true, false]);
      expect(logged.last, contains('not scheduled'));

      scheduler.askedExpedited.clear();
      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => false,
      );
      expect(scheduler.askedExpedited, [false]);
    });

    test(
      'a pair the relay would never name — too long, or a character '
      'outside its rule — schedules nothing and reads nothing (P3b)',
      () async {
        final scheduler = FakeSharedRefreshScheduler();
        var asked = 0;
        for (final pair in [
          'x' * 200000,
          'x' * 129,
          'pair/1',
          'pair 1',
          'p\n',
        ]) {
          await handleBackgroundPush(
            {'t': 'shared', 'p': pair, 'junk': 'y' * 1000},
            scheduler: scheduler,
            expedited: () async => true,
            writtenPair: () async {
              asked++;
              return null;
            },
          );
        }
        await handleBackgroundPush(
          shared('A-z_0-9${'x' * 121}'),
          scheduler: scheduler,
          expedited: () async => false,
        );

        expect(asked, 0);
        expect(scheduler.calls, ['message:A-z_0-9${'x' * 121}']);
      },
    );

    test('a pair other than the one this install\'s address was written for '
        'schedules nothing; the written pair, or none written, goes as '
        'ever', () async {
      final scheduler = FakeSharedRefreshScheduler();
      var expeditedAsked = 0;
      Future<bool> expedited() async {
        expeditedAsked++;
        return false;
      }

      await handleBackgroundPush(
        shared('pair-9'),
        scheduler: scheduler,
        expedited: expedited,
        writtenPair: () async => 'pair-1',
      );
      expect(scheduler.calls, isEmpty);
      expect(expeditedAsked, 0);

      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: expedited,
        writtenPair: () async => 'pair-1',
      );
      await handleBackgroundPush(
        shared('pair-2'),
        scheduler: scheduler,
        expedited: expedited,
        writtenPair: () async => throw StateError('unreadable'),
      );
      await handleBackgroundPush(
        shared('pair-3'),
        scheduler: scheduler,
        expedited: expedited,
      );
      expect(scheduler.calls, [
        'message:pair-1',
        'message:pair-2',
        'message:pair-3',
      ]);
    });

    test('the written pair is what the app stored: its messages go, another '
        'pair\'s are dropped, and a stored write that does not read whole '
        'drops nothing', () async {
      final scheduler = FakeSharedRefreshScheduler();
      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushWritten: 'pair-1|fid-1|1',
      });
      await handleBackgroundPush(shared('pair-2'), scheduler: scheduler);
      await handleBackgroundPush(shared('pair-1'), scheduler: scheduler);
      expect(scheduler.calls, ['message:pair-1']);

      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushWritten: 'garbled',
      });
      await handleBackgroundPush(shared('pair-2'), scheduler: scheduler);
      expect(scheduler.calls, ['message:pair-1', 'message:pair-2']);
    });

    group('a pair\'s messages cost one waiting work (push review F3a)', () {
      final t0 = DateTime(2026, 11, 14, 12);
      late FakeSharedRefreshScheduler scheduler;
      late Duration elapsed;

      setUp(() {
        scheduler = FakeSharedRefreshScheduler();
        elapsed = Duration.zero;
      });

      Future<void> message(String pair, {String? written}) =>
          handleBackgroundPush(
            shared(pair),
            scheduler: scheduler,
            expedited: () async => true,
            writtenPair: () async => written,
            clock: () => t0.add(elapsed),
          );

      /// The platform starts the pair's work — a fresh one or a retry.
      Future<void> workStarts(String pair) =>
          SharedRefreshMessageGate.started(pair, now: t0.add(elapsed));

      test(
        'five messages for one pair are one hand-over; once that work '
        'has started, a message during its run is exactly one more',
        () async {
          for (var i = 0; i < 5; i++) {
            await message('pair-1');
            elapsed += const Duration(seconds: 1);
          }
          expect(scheduler.calls, ['message:pair-1:expedited']);

          await workStarts('pair-1');
          for (var i = 0; i < 3; i++) {
            await message('pair-1');
            elapsed += const Duration(seconds: 1);
          }
          expect(scheduler.calls, [
            'message:pair-1:expedited',
            'message:pair-1:expedited',
          ]);
        },
      );

      test('two pairs share no waiting work', () async {
        await message('pair-1');
        await message('pair-2');
        await message('pair-1');
        await message('pair-2');

        expect(scheduler.calls, [
          'message:pair-1:expedited',
          'message:pair-2:expedited',
        ]);
      });

      test(
        'a note left by a work that never ran does not swallow the '
        'pair\'s messages for good: past its age the next one schedules',
        () async {
          await message('pair-1');
          elapsed = kSharedRefreshWaitingMarkAge - const Duration(seconds: 1);
          await message('pair-1');
          expect(scheduler.calls, hasLength(1));

          elapsed = kSharedRefreshWaitingMarkAge;
          await message('pair-1');
          expect(scheduler.calls, hasLength(2));
          // And that one waits in its turn.
          await message('pair-1');
          expect(scheduler.calls, hasLength(2));
        },
      );

      test('a work the platform refused, expedited and plain, waits '
          'nowhere: the next message asks again', () async {
        final refusing = _Refusing();
        await handleBackgroundPush(
          shared('pair-1'),
          scheduler: refusing,
          expedited: () async => true,
          clock: () => t0,
        );
        expect(refusing.askedExpedited, [true, false]);

        await message('pair-1');
        expect(scheduler.calls, ['message:pair-1:expedited']);
      });

      test(
        'a pair other than the written one is dropped before any of '
        'this: nothing is noted for it, and nothing it left is asked',
        () async {
          await message('pair-9', written: 'pair-1');

          expect(scheduler.calls, isEmpty);
          expect(await waits('pair-9', now: t0), isFalse);
          // Written later for that pair, its first message schedules.
          await message('pair-9', written: 'pair-9');
          expect(scheduler.calls, ['message:pair-9:expedited']);
        },
      );

      test('the honest second message, a spacing after the first, is an '
          'expedited hand-over like the first — nothing is put off: a '
          'phone asleep holds a delayed work, and every later one behind '
          'it (second look, D1)', () async {
        await message('pair-1');
        elapsed = const Duration(seconds: 4);
        await workStarts('pair-1');

        elapsed = kPushPokeSpacing;
        await message('pair-1');
        elapsed = kPushPokeSpacing + const Duration(seconds: 2);
        await workStarts('pair-1');

        expect(scheduler.calls, [
          'message:pair-1:expedited',
          'message:pair-1:expedited',
        ]);
      });

      test('a work that asked for a retry and was never run again holds '
          'nothing back: the next message schedules, what follows waits '
          'behind that work, and once it has started — taken for a retry '
          'or not — the next schedules again (second look, D2)', () async {
        await message('pair-1');
        await workStarts('pair-1');
        // It ends asking for a retry; the platform never runs it again.

        elapsed = const Duration(minutes: 1);
        await message('pair-1');
        elapsed = const Duration(minutes: 5);
        await message('pair-1');
        expect(scheduler.calls, hasLength(2), reason: 'one waits already');

        elapsed = const Duration(minutes: 6);
        await workStarts('pair-1');
        elapsed = const Duration(minutes: 9);
        await message('pair-1');

        expect(scheduler.calls, [
          'message:pair-1:expedited',
          'message:pair-1:expedited',
          'message:pair-1:expedited',
        ]);
      });
    });

    group('the messaging plugin\'s engine is no alarm presenter (F13)', () {
      test('the first message this isolate handles resigns it, before '
          'anything else is asked — once, however many follow, and for a '
          'message that is dropped too', () async {
        final order = <String>[];
        final scheduler = FakeSharedRefreshScheduler();
        Future<void> handle(Map<String, dynamic> data) => handleBackgroundPush(
          data,
          scheduler: scheduler,
          expedited: () async => false,
          writtenPair: () async {
            order.add('written');
            return null;
          },
          resign: () async => order.add('resign'),
        );

        await handle({'t': 'other'});
        expect(order, ['resign']);

        await handle(shared('pair-1'));
        await handle(shared('pair-2'));
        expect(order, ['resign', 'written', 'written']);
        expect(scheduler.calls, ['message:pair-1', 'message:pair-2']);
      });

      test('a resign that throws changes nothing of the hand-over, and is '
          'asked again by the next message', () async {
        final scheduler = FakeSharedRefreshScheduler();
        var asked = 0;
        Future<void> handle(String pair) => handleBackgroundPush(
          shared(pair),
          scheduler: scheduler,
          expedited: () async => false,
          resign: () async {
            asked++;
            if (asked == 1) throw StateError('no host');
          },
        );

        await handle('pair-1');
        expect(scheduler.calls, ['message:pair-1']);
        expect(asked, 1);

        await handle('pair-2');
        await handle('pair-3');
        expect(asked, 2);
        expect(scheduler.calls, hasLength(3));
      });
    });

    test('what the app stored is read off the store, past this isolate\'s '
        'copy of the preferences — the plugin keeps the handler\'s engine '
        'for the life of the process: a pair written and an expedited '
        'answer stored behind it are seen, and the copy is left as it '
        'was', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesStorePlatform.instance;
      await store.setValue(
        'String',
        'flutter.${SettingsKeys.pushWritten}',
        'pair-2|fid-1|1',
      );
      await store.setValue(
        'String',
        'flutter.${SettingsKeys.pushExpeditedWork}',
        '1',
      );

      final scheduler = FakeSharedRefreshScheduler();
      await handleBackgroundPush(shared('pair-1'), scheduler: scheduler);
      await handleBackgroundPush(shared('pair-2'), scheduler: scheduler);

      expect(scheduler.calls, ['message:pair-2:expedited']);
      expect(
        prefs.containsKey(SettingsKeys.pushWritten),
        isFalse,
        reason: 'nothing reloads this isolate\'s copy',
      );
    });

    group('the handler hands over promptly (second look, D7)', () {
      test('a message costs one read of the store — the written pair, the '
          'waiting note and the expedited answer all come from it', () async {
        final store = ScriptedPrefsStore.install({
          SettingsKeys.pushWritten: 'pair-1|fid-1|1',
          SettingsKeys.pushExpeditedWork: '1',
        });
        final scheduler = FakeSharedRefreshScheduler();
        // This isolate's own copy, loaded once by whatever asked first.
        await SharedPreferences.getInstance();

        var before = store.reads;
        await handleBackgroundPush(shared('pair-1'), scheduler: scheduler);
        expect(store.reads - before, 1);
        expect(scheduler.calls, ['message:pair-1:expedited']);

        // One that schedules nothing — a work waits — costs no more.
        before = store.reads;
        await handleBackgroundPush(shared('pair-1'), scheduler: scheduler);
        expect(store.reads - before, 1);
        expect(scheduler.calls, hasLength(1));
      });

      test('a store that cannot be read drops nothing: the work is handed '
          'over plain, and the run\'s own pair check stands', () async {
        final store = ScriptedPrefsStore.install({
          SettingsKeys.pushWritten: 'pair-1|fid-1|1',
        });
        await SharedPreferences.getInstance();
        store.onRead = (_) => throw StateError('no store');
        final scheduler = FakeSharedRefreshScheduler();

        await handleBackgroundPush(shared('pair-9'), scheduler: scheduler);

        expect(scheduler.calls, ['message:pair-9']);
      });

      test('a resign that never answers holds the hand-over for its bound '
          'and no longer', () {
        fakeAsync((async) {
          final scheduler = FakeSharedRefreshScheduler();
          final never = Completer<void>();
          var done = false;
          handleBackgroundPush(
            shared('pair-1'),
            scheduler: scheduler,
            expedited: () async => false,
            writtenPair: () async => null,
            resign: () => never.future,
          ).then((_) => done = true);

          async.elapse(kPushResignBound - const Duration(milliseconds: 1));
          expect(scheduler.calls, isEmpty);

          async.elapse(const Duration(milliseconds: 1));
          async.flushMicrotasks();
          expect(scheduler.calls, ['message:pair-1']);
          expect(done, isTrue);
        });
      });

      test('one resign in flight per isolate: four messages against a host '
          'that never answers ask it once, and each is handed over after '
          'the bound (review of leg 12, F6)', () {
        fakeAsync((async) {
          final scheduler = FakeSharedRefreshScheduler();
          final never = Completer<void>();
          var asked = 0;
          var handled = 0;
          for (final data in [
            shared('pair-1'),
            {'t': 'shared', 'p': 'not a pair!'},
            shared('pair-2'),
            shared('pair-3'),
          ]) {
            handleBackgroundPush(
              data,
              scheduler: scheduler,
              expedited: () async => false,
              writtenPair: () async => null,
              resign: () {
                asked++;
                return never.future;
              },
            ).then((_) => handled++);
            final before = handled;
            async.elapse(kPushResignBound - const Duration(milliseconds: 1));
            expect(handled, before, reason: 'still inside the bound');
            async.elapse(const Duration(milliseconds: 1));
            async.flushMicrotasks();
            expect(handled, before + 1);
          }

          expect(asked, 1);
          expect(handled, 4);
          expect(scheduler.calls, [
            'message:pair-1',
            'message:pair-2',
            'message:pair-3',
          ]);
        });
      });

      test('an ask the host failed is forgotten: the next message asks '
          'again, and the answer then is kept', () async {
        final scheduler = FakeSharedRefreshScheduler();
        var asked = 0;
        Future<void> handle(String pair) => handleBackgroundPush(
          shared(pair),
          scheduler: scheduler,
          expedited: () async => false,
          resign: () async {
            asked++;
            if (asked == 1) throw StateError('no host');
          },
        );

        await handle('pair-1');
        await pumpEventQueue();
        await handle('pair-2');
        await handle('pair-3');

        expect(asked, 2);
        expect(scheduler.calls, hasLength(3));
      });

      test('one that answers after its bound still counts: the next message '
          'asks nothing more', () async {
        final scheduler = FakeSharedRefreshScheduler();
        final late = Completer<void>();
        var asked = 0;
        Future<void> handle(String pair) => handleBackgroundPush(
          shared(pair),
          scheduler: scheduler,
          expedited: () async => false,
          resign: () {
            asked++;
            return late.future;
          },
          resignBound: const Duration(milliseconds: 10),
        );

        await handle('pair-1');
        late.complete();
        await pumpEventQueue();
        await handle('pair-2');

        expect(asked, 1);
        expect(scheduler.calls, ['message:pair-1', 'message:pair-2']);
      });
    });

    test('anything else schedules nothing and reads nothing, and a platform '
        'that fails is logged, never thrown', () async {
      final scheduler = FakeSharedRefreshScheduler();
      var asked = 0;
      Future<bool> expedited() async {
        asked++;
        return true;
      }

      await handleBackgroundPush(
        {'t': 'other', 'p': 'x'},
        scheduler: scheduler,
        expedited: expedited,
      );
      await handleBackgroundPush(
        {},
        scheduler: scheduler,
        expedited: expedited,
      );
      expect(scheduler.calls, isEmpty);
      expect(asked, 0);

      scheduler.failNext = true;
      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => false,
      );
      expect(scheduler.calls, isEmpty);
      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: () async => false,
      );
      expect(scheduler.calls, ['message:pair-1'], reason: 'the next goes');
    });
  });
}
