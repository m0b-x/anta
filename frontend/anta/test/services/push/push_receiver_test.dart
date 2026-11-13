import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/services/push/push_messaging.dart';
import 'package:anta/services/push/push_receiver.dart';

import '../../support/fake_push.dart';
import '../../support/fake_shared_refresh_scheduler.dart';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messaging = _Messaging();
    addresses = FakePushAddressSource();
    reads = 0;
    openPair = 'pair-1';
    sdkLevel = () async => 34;
  });

  PushReceiver receiver() => PushReceiver(
    messaging: messaging,
    addresses: addresses,
    openPair: () async => openPair,
    readShared: () async => reads++,
    sdkLevel: () => sdkLevel(),
    prefs: SharedPreferences.getInstance(),
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
      for (final (level, stored) in [
        (30, null),
        (31, '1'),
        (36, '1'),
      ]) {
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
        final listening = receiver();
        unawaited(listening.addressInUse());
        async.flushMicrotasks();
        for (var i = 0; i < 5; i++) {
          messaging.controller.add(shared('pair-1'));
        }
        async.flushMicrotasks();
        expect(reads, 0);
        async.elapse(const Duration(seconds: 2));
        expect(reads, 1);

        messaging.controller.add(shared('pair-1'));
        async.elapse(const Duration(seconds: 2));
        expect(reads, 2, reason: 'a later message is a later read');
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

    test('the stored answer: written, it is true; missing, false', () async {
      expect(await storedExpedited(), isFalse);
      SharedPreferences.setMockInitialValues({
        SettingsKeys.pushExpeditedWork: '1',
      });
      expect(await storedExpedited(), isTrue);
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
      await handleBackgroundPush({}, scheduler: scheduler, expedited: expedited);
      expect(scheduler.calls, isEmpty);
      expect(asked, 0);

      scheduler.failNext = true;
      await handleBackgroundPush(
        shared('pair-1'),
        scheduler: scheduler,
        expedited: expedited,
      );
    });
  });
}
