import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/core/qa/qa_bootstrap.dart';
import 'package:anta/services/shared_refresh/shared_refresh_entry.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';

/// Where the platform starts Dart for the check (`sharedRefreshEntry`), off
/// the one platform that gives the work an engine of its own
/// (`docs/cloud-shared-freshness.md` §10). On iOS the plugin runs a task on
/// the app's engine: a run "without the app" there would register its own
/// dependencies over the app's and close the app's database as it ended.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The channel the plugin hands a task to Dart on, once `executeTask` has
  /// set its handler up on this engine.
  const taskChannel =
      'dev.flutter.pigeon.workmanager_platform_interface.'
      'WorkmanagerFlutterApi.executeTask';

  setUp(() {
    SharedRefreshAvailability.debugSupported = false;
    // So a trigger that did fire here would get as far as looking for the
    // database and fail there — "run it again" — where with no preferences
    // at all it ends quietly at the first thing it reads.
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => SharedRefreshAvailability.debugSupported = null);

  /// What this engine answers a task the plugin hands it: null while
  /// nothing listens.
  Future<ByteData?> handedATask() async {
    ByteData? reply;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          taskChannel,
          const StandardMessageCodec().encodeMessage(<Object?>[
            kSharedRefreshWorkName,
            null,
          ]),
          (data) => reply = data,
        );
    return reply;
  }

  test('off Android the entry returns at once: nothing of the plugin is '
      'set up on this engine, so no task can be handed to it', () async {
    sharedRefreshEntry();
    await pumpEventQueue();

    expect(await handedATask(), isNull);
  });

  test('and a task that reached its handler some other way fires nothing '
      'and is not asked for again, whatever started it', () async {
    for (final cause in SharedRefreshCause.values) {
      expect(
        await sharedRefreshTask(kSharedRefreshWorkName, {
          kSharedRefreshCauseKey: cause.name,
          kSharedRefreshPairKey: 'pair-1',
        }),
        isTrue,
        reason: cause.name,
      );
    }
    expect(await sharedRefreshTask(kSharedRefreshSecondWorkName, null), isTrue);
  });

  group('on the platform that gives the work an engine', () {
    setUp(() => SharedRefreshAvailability.debugSupported = true);

    test('a host that never hears the resign holds the work back for the '
        'bound and no longer: the trigger is fired all the same, with what '
        'the work was scheduled with (review of leg 12, F4)', () async {
      final fired = <String>[];
      final never = Completer<void>();
      addTearDown(never.complete);

      final done = sharedRefreshTask(
        kSharedRefreshSecondWorkName,
        {
          kSharedRefreshCauseKey: SharedRefreshCause.message.name,
          kSharedRefreshPairKey: 'pair-1',
        },
        resign: () => never.future,
        resignBound: const Duration(milliseconds: 40),
        fire:
            ({
              SharedRefreshCause cause = SharedRefreshCause.check,
              SharedRefreshSlot slot = SharedRefreshSlot.first,
              String? pair,
            }) async {
              fired.add('${cause.name} ${slot.name} $pair');
              return true;
            },
      );

      expect(await done.timeout(const Duration(seconds: 2)), isTrue);
      expect(fired, ['message second pair-1']);
    });

    test('a resign that throws is logged and the work goes on', () async {
      var fired = 0;

      expect(
        await sharedRefreshTask(
          kSharedRefreshWorkName,
          null,
          resign: () async => throw StateError('no host'),
          fire:
              ({
                SharedRefreshCause cause = SharedRefreshCause.check,
                SharedRefreshSlot slot = SharedRefreshSlot.first,
                String? pair,
              }) async {
                fired++;
                return false;
              },
        ),
        isFalse,
      );
      expect(fired, 1);
    });
  });

  group('a QA build\'s preferences are namespaced once per isolate (device '
      'pass, 2026-11-14)', () {
    setUp(QaBootstrap.debugForgetPrefixed);
    tearDown(QaBootstrap.debugForgetPrefixed);

    test('the plugin is asked for the prefix until it took, and never '
        'after: it refuses once the isolate has opened the preferences, '
        'and every step that may be the first asks', () {
      var asked = 0;
      for (var call = 0; call < 4; call++) {
        QaBootstrap.prefixOnce(() => asked++);
      }

      expect(asked, 1);
    });

    test('a first call that comes too late still throws — a QA build '
        'reading the un-prefixed store is a defect to see — and is asked '
        'again by the next', () {
      var asked = 0;
      void tooLate() {
        asked++;
        throw StateError('setPrefix cannot be called after getInstance');
      }

      expect(() => QaBootstrap.prefixOnce(tooLate), throwsStateError);
      expect(() => QaBootstrap.prefixOnce(tooLate), throwsStateError);
      expect(asked, 2);
    });
  });
}
