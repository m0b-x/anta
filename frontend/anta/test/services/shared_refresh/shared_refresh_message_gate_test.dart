import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/fresh_preferences.dart';
import 'package:anta/services/shared_refresh/shared_refresh_message_gate.dart';

import '../../support/scripted_prefs_store.dart';
import '../../support/waiting_note.dart';

/// `SharedRefreshMessageGate` — what keeps a pair's relay messages to one
/// work waiting to start while the app is not in front
/// (`docs/cloud-shared-freshness.md` §7; the push review's F3a, and its
/// second look's D1, D2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 11, 14, 12);
  DateTime at(Duration after) => t0.add(after);

  String waitingKey(String pair) =>
      '${SettingsKeys.sharedRefreshMessageWaitingPrefix}$pair';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the waiting note', () {
    test('none until one is made; made, a work waits — for that pair and no '
        'other', () async {
      expect(await waits('pair-1', now: t0), isFalse);

      await SharedRefreshMessageGate.mark('pair-1', now: t0);

      expect(await waits('pair-1', now: t0), isTrue);
      expect(await waits('pair-2', now: t0), isFalse);
    });

    test('taken off — the hand-over failed — nothing waits', () async {
      await SharedRefreshMessageGate.mark('pair-1', now: t0);
      await SharedRefreshMessageGate.unmark('pair-1');

      expect(await waits('pair-1', now: t0), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(waitingKey('pair-1')), isFalse);
    });

    test('one left by a work that never ran is believed for its age and no '
        'longer: it swallows nothing for good', () async {
      await SharedRefreshMessageGate.mark('pair-1', now: t0);

      expect(
        await waits(
          'pair-1',
          now: at(kSharedRefreshWaitingMarkAge - const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        await waits('pair-1', now: at(kSharedRefreshWaitingMarkAge)),
        isFalse,
      );
    });

    test('one from a clock that has since gone back is not believed', () async {
      await SharedRefreshMessageGate.mark(
        'pair-1',
        now: at(const Duration(hours: 1)),
      );

      expect(await waits('pair-1', now: t0), isFalse);
    });

    test('read off the store: a note another isolate made behind this '
        'one\'s copy of the preferences is seen, one it took off is gone — '
        'and a read of the store the caller already made answers the '
        'same', () async {
      await SharedPreferences.getInstance();
      final store = SharedPreferencesStorePlatform.instance;
      await store.setValue(
        'Int',
        'flutter.${waitingKey('pair-1')}',
        t0.millisecondsSinceEpoch,
      );

      expect(await waits('pair-1', now: t0), isTrue);
      expect(
        SharedRefreshMessageGate.waitsIn(
          await FreshPreferences.read(),
          'pair-1',
          now: t0,
        ),
        isTrue,
      );

      await store.remove('flutter.${waitingKey('pair-1')}');
      expect(await waits('pair-1', now: t0), isFalse);
    });

    test('a store that cannot be written fails nothing: nothing is noted, '
        'and the message goes on to its work', () async {
      final store = ScriptedPrefsStore.install();
      store.failWrite = (_) => true;
      await SharedRefreshMessageGate.mark('pair-1', now: t0);
      await SharedRefreshMessageGate.unmark('pair-1');

      expect(await waits('pair-1', now: t0), isFalse);
    });
  });

  group('a message\'s work starts', () {
    test('the note that it waited goes, and no other pair\'s that is still '
        'believed', () async {
      await SharedRefreshMessageGate.mark('pair-1', now: t0);
      await SharedRefreshMessageGate.mark('pair-2', now: t0);

      await SharedRefreshMessageGate.started(
        'pair-1',
        now: at(const Duration(seconds: 3)),
      );

      expect(
        await waits('pair-1', now: at(const Duration(seconds: 3))),
        isFalse,
      );
      expect(
        await waits('pair-2', now: at(const Duration(seconds: 3))),
        isTrue,
      );
    });

    test('nothing else is kept of a start: no instant a later work is held '
        'against', () async {
      await SharedRefreshMessageGate.mark('pair-1', now: t0);
      await SharedRefreshMessageGate.started('pair-1', now: t0);

      final stored = await SharedPreferencesStorePlatform.instance.getAll();
      expect(stored, isEmpty);
    });

    test('a note the store kept behind this isolate\'s copy goes too: the '
        'work is never the isolate that made it', () async {
      await SharedPreferences.getInstance();
      final store = SharedPreferencesStorePlatform.instance;
      await store.setValue(
        'Int',
        'flutter.${waitingKey('pair-1')}',
        t0.millisecondsSinceEpoch,
      );

      await SharedRefreshMessageGate.started('pair-1', now: t0);

      expect(
        await store.getAll(),
        isNot(contains('flutter.${waitingKey('pair-1')}')),
      );
    });

    test('a store that cannot be read still loses the note, and nothing is '
        'thrown: the removal is asked blind', () async {
      final store = ScriptedPrefsStore.install({
        waitingKey('pair-1'): t0.millisecondsSinceEpoch,
      });
      await SharedPreferences.getInstance();
      store.onRead = (_) => throw StateError('no store');

      await SharedRefreshMessageGate.started('pair-1', now: t0);

      store.onRead = null;
      expect(await waits('pair-1', now: t0), isFalse);
    });

    test('what other pairs left that is believed no longer goes with the '
        'start: a pair that ended leaves no key for good', () async {
      await SharedRefreshMessageGate.mark('pair-old', now: t0);
      await SharedRefreshMessageGate.mark(
        'pair-young',
        now: at(kSharedRefreshWaitingMarkAge),
      );

      await SharedRefreshMessageGate.started(
        'pair-1',
        now: at(kSharedRefreshWaitingMarkAge + const Duration(seconds: 5)),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(waitingKey('pair-old')), isFalse);
      expect(prefs.containsKey(waitingKey('pair-young')), isTrue);
    });
  });
}
