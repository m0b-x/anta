import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/shared_refresh/shared_refresh.dart';
import 'package:anta/services/shared_refresh/shared_refresh_app.dart';
import 'package:anta/services/shared_refresh/shared_refresh_plan.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';

import '../../database/support/db_test_support.dart';
import '../../support/fake_shared_refresh_scheduler.dart';

/// `SharedRefresh` — the check scheduled while an alert depends on what the
/// partner shares, and only then (`docs/cloud-shared-freshness.md` §4,
/// decision b).
void main() {
  late FakeSharedRefreshScheduler platform;
  late DateTime now;
  late bool shares;
  late int sharesAsked;

  setUp(() {
    platform = FakeSharedRefreshScheduler();
    now = DateTime(2026, 11, 13, 9);
    shares = true;
    sharesAsked = 0;
  });

  SharedRefresh refreshOf() => SharedRefresh(
    scheduler: platform,
    shares: () async {
      sharesAsked++;
      return shares;
    },
    clock: () => now,
  );

  SharedRefreshNeed alertIn(Duration left) =>
      SharedRefreshNeed(fireTimes: [now.add(left)]);

  group('an account that never paired', () {
    test(
      'asks the platform nothing and is asked nothing, pass after pass',
      () async {
        final refresh = refreshOf();

        await refresh.afterAlertPass(SharedRefreshNeed.none);
        await refresh.afterAlertPass(SharedRefreshNeed.none);

        expect(platform.calls, isEmpty);
        expect(sharesAsked, 0);
      },
    );
  });

  group('wanted', () {
    test('an alert armed on the partner\'s event schedules the check at half '
        'the time left', () async {
      await refreshOf().afterAlertPass(alertIn(const Duration(hours: 6)));

      expect(platform.calls, ['schedule:${const Duration(hours: 3)}']);
    });

    test('"Category alerts too" alone schedules the hourly check', () async {
      await refreshOf().afterAlertPass(
        const SharedRefreshNeed(categoryAlerts: true),
      );

      expect(platform.scheduled, [const Duration(hours: 1)]);
    });

    test('an alert of mine on a partner\'s event that can still occur and is '
        'not armed yet keeps the twelve-hour check', () async {
      final refresh = refreshOf();

      await refresh.afterAlertPass(
        const SharedRefreshNeed(alertDefined: true, alertAhead: true),
      );

      expect(platform.scheduled, [const Duration(hours: 12)]);
      expect(refresh.pokeWorthy, isTrue);
    });

    test('an alert of mine on a past event of theirs schedules nothing — a '
        'past one-off must not keep the check alive — and is still worth '
        'a read when a message comes', () async {
      final refresh = refreshOf();
      expect(refresh.pokeWorthy, isFalse);

      await refresh.afterAlertPass(const SharedRefreshNeed(alertDefined: true));

      expect(platform.scheduled, isEmpty);
      expect(refresh.scheduled, isFalse);
      expect(refresh.pokeWorthy, isTrue);
      expect(sharesAsked, 0, reason: 'nothing to schedule, nothing to ask');
    });

    test('nothing of mine on anything of theirs is worth neither', () async {
      final refresh = refreshOf();

      await refresh.afterAlertPass(const SharedRefreshNeed());
      expect(refresh.pokeWorthy, isFalse);
      await refresh.afterAlertPass(SharedRefreshNeed.none);
      expect(refresh.pokeWorthy, isFalse);
    });

    test('scheduled says whether the last request left a check standing — '
        'how a run learns whether it is wanted', () async {
      final refresh = refreshOf();
      expect(refresh.scheduled, isFalse);

      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));
      expect(refresh.scheduled, isTrue);

      await refresh.afterAlertPass(const SharedRefreshNeed());
      expect(refresh.scheduled, isFalse);

      shares = false;
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));
      expect(refresh.scheduled, isFalse);
    });

    test('a database that does not sync as the paired account schedules '
        'nothing, whatever is armed', () async {
      shares = false;
      final refresh = refreshOf();

      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      expect(platform.scheduled, isEmpty);
      expect(sharesAsked, 1);
    });

    test('the standing conditions are asked only for a need that depends on '
        'the partner\'s rows', () async {
      await refreshOf().afterAlertPass(const SharedRefreshNeed());

      expect(sharesAsked, 0);
    });
  });

  group('one plan, one platform call', () {
    test('the same plan twice schedules once', () async {
      final refresh = refreshOf();
      final need = alertIn(const Duration(hours: 6));

      await refresh.afterAlertPass(need);
      await refresh.afterAlertPass(need);

      expect(platform.scheduled, hasLength(1));
    });

    test('a pass moments later lands within the tolerance and schedules '
        'nothing', () async {
      final refresh = refreshOf();
      final fireAt = now.add(const Duration(hours: 6));

      await refresh.afterAlertPass(SharedRefreshNeed(fireTimes: [fireAt]));
      // Ninety seconds on, half the time left ends forty-five seconds later.
      now = now.add(const Duration(seconds: 90));
      await refresh.afterAlertPass(SharedRefreshNeed(fireTimes: [fireAt]));

      expect(platform.scheduled, hasLength(1));
    });

    test('a plan that moved past the tolerance replaces the work', () async {
      final refresh = refreshOf();

      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));
      await refresh.afterAlertPass(alertIn(const Duration(hours: 2)));

      expect(platform.scheduled, const [
        Duration(hours: 3),
        Duration(hours: 1),
      ]);
    });

    test(
      'a check that already ran is planned again by the next pass',
      () async {
        final refresh = refreshOf();
        final fireAt = now.add(const Duration(hours: 8));

        await refresh.afterAlertPass(SharedRefreshNeed(fireTimes: [fireAt]));
        now = now.add(const Duration(hours: 4, minutes: 5));
        await refresh.afterAlertPass(SharedRefreshNeed(fireTimes: [fireAt]));

        expect(platform.scheduled, const [
          Duration(hours: 4),
          Duration(hours: 1, minutes: 57, seconds: 30),
        ]);
      },
    );

    test(
      'two passes ending together reach the platform in their order',
      () async {
        final refresh = refreshOf();

        final first = refresh.afterAlertPass(alertIn(const Duration(hours: 6)));
        final second = refresh.afterAlertPass(const SharedRefreshNeed());
        await Future.wait([first, second]);

        expect(platform.calls, [
          'schedule:${const Duration(hours: 3)}',
          'cancel',
        ]);
      },
    );
  });

  group('no longer wanted', () {
    test('the alert gone, the scheduled check is cancelled, once', () async {
      final refresh = refreshOf();
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      await refresh.afterAlertPass(const SharedRefreshNeed());
      await refresh.afterAlertPass(const SharedRefreshNeed());

      expect(platform.calls, [
        'schedule:${const Duration(hours: 3)}',
        'cancel',
      ]);
    });

    test(
      'the partner\'s rows gone altogether, it is cancelled as well',
      () async {
        final refresh = refreshOf();
        await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

        await refresh.afterAlertPass(SharedRefreshNeed.none);
        await refresh.afterAlertPass(SharedRefreshNeed.none);

        expect(platform.cancels, 1);
      },
    );

    test('sync stopped or the pair ended while an alert is still armed '
        'cancels it', () async {
      final refresh = refreshOf();
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      shares = false;
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      expect(platform.calls.last, 'cancel');
    });

    test('work an earlier process may have left is cancelled once where the '
        'pass saw sharing, and never where it saw none', () async {
      final refresh = refreshOf();

      await refresh.afterAlertPass(const SharedRefreshNeed());
      await refresh.afterAlertPass(const SharedRefreshNeed());

      expect(platform.calls, ['cancel']);
    });

    test('an alert under ten minutes away with no other plans nothing, and '
        'takes the standing check off', () async {
      final refresh = refreshOf();
      await refresh.afterAlertPass(alertIn(const Duration(hours: 1)));

      now = now.add(const Duration(minutes: 55));
      await refresh.afterAlertPass(
        SharedRefreshNeed(fireTimes: [now.add(const Duration(minutes: 5))]),
      );

      expect(platform.calls, [
        'schedule:${const Duration(minutes: 30)}',
        'cancel',
      ]);
    });

    test('wanted again after a cancel, it is scheduled again', () async {
      final refresh = refreshOf();
      final need = alertIn(const Duration(hours: 6));
      await refresh.afterAlertPass(need);
      await refresh.afterAlertPass(const SharedRefreshNeed());

      await refresh.afterAlertPass(need);

      expect(platform.scheduled, hasLength(2));
    });
  });

  group('while the check\'s own work runs (two slots)', () {
    const three = Duration(hours: 3);

    for (final slot in SharedRefreshSlot.values) {
      test('a run in the ${slot.name} slot schedules its successor into the '
          'other, before it reads — never into its own, which would cancel '
          'the run itself', () async {
        final refresh = refreshOf()..workRunning(slot);

        await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

        expect(platform.calls, ['schedule@${slot.other.name}:$three']);
        expect(refresh.scheduled, isTrue, reason: 'scheduled, so wanted');
      });
    }

    test('a forwarded read forgets the check that just ran: the pass after '
        'it lands on the very instant the app had scheduled, and still '
        'schedules the successor — into the other slot', () async {
      final refresh = refreshOf();
      final need = alertIn(const Duration(hours: 6));
      await refresh.afterAlertPass(need);
      expect(platform.calls, ['schedule:$three']);

      // The work is run moments after it was planned (a message; a pass's
      // forced job), and its read is forwarded here.
      refresh.workRunning(SharedRefreshSlot.first);
      await refresh.afterAlertPass(need);

      expect(platform.calls, ['schedule:$three', 'schedule@second:$three']);
    });

    test('a run that wants no check takes the other slot off, never its '
        'own', () async {
      final refresh = refreshOf()..workRunning(SharedRefreshSlot.second);

      await refresh.afterAlertPass(const SharedRefreshNeed());

      expect(platform.calls, ['cancel@first']);
      expect(refresh.scheduled, isFalse);
    });

    test('a second pass of the same run is one plan still: nothing more is '
        'asked', () async {
      final refresh = refreshOf()..workRunning(SharedRefreshSlot.first);
      final need = alertIn(const Duration(hours: 6));

      await refresh.afterAlertPass(need);
      await refresh.afterAlertPass(need);

      expect(platform.calls, hasLength(1));
    });

    test('once the work is answered the app writes the first slot again, '
        'and only after the pass still on its way', () async {
      final refresh = refreshOf()..workRunning(SharedRefreshSlot.second);
      // Not awaited, as the alert pass leaves it.
      refresh.afterAlertPass(alertIn(const Duration(hours: 6))).ignore();

      await refresh.workEnded();
      await refresh.afterAlertPass(alertIn(const Duration(hours: 2)));

      expect(platform.calls, [
        'schedule@first:$three',
        'schedule:${const Duration(hours: 1)}',
      ]);
    });

    test('the slot of a task is told by its name; a name this build does '
        'not know is the first', () {
      expect(SharedRefreshSlot.ofTask('shared-refresh'), SharedRefreshSlot.first);
      expect(
        SharedRefreshSlot.ofTask('shared-refresh-2'),
        SharedRefreshSlot.second,
      );
      expect(SharedRefreshSlot.ofTask('something'), SharedRefreshSlot.first);
      expect(SharedRefreshSlot.ofTask(null), SharedRefreshSlot.first);
      expect(SharedRefreshSlot.first.other.other, SharedRefreshSlot.first);
    });
  });

  group('a read forwarded to the app (SharedRefreshApp.forwardedRead)', () {
    test('the work is named as running before the read, the alert pass '
        'follows whatever the read found, and the work is given back after '
        'the pass\'s plan', () async {
      final refresh = refreshOf();
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));
      final order = <String>[];

      await SharedRefreshApp.forwardedRead(
        SharedRefreshSlot.first,
        refresh: refresh,
        read: () async {
          order.add('read');
          return null;
        },
        alertPass: () async {
          order.add('pass');
          refresh.afterAlertPass(alertIn(const Duration(hours: 6))).ignore();
        },
      );
      await refresh.afterAlertPass(alertIn(const Duration(hours: 1)));

      expect(order, ['read', 'pass']);
      expect(platform.calls, [
        'schedule:${const Duration(hours: 3)}',
        'schedule@second:${const Duration(hours: 3)}',
        'schedule:${const Duration(minutes: 30)}',
      ]);
    });

    test('a read that throws still gives the work back', () async {
      final refresh = refreshOf();

      await expectLater(
        SharedRefreshApp.forwardedRead(
          SharedRefreshSlot.second,
          refresh: refresh,
          read: () async => throw StateError('no engine'),
          alertPass: () async => fail('no pass after a read that threw'),
        ),
        throwsStateError,
      );
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      expect(platform.calls, ['schedule:${const Duration(hours: 3)}']);
    });

    test('a message\'s read names no work: the check that stands is kept '
        'while the plan has not moved, and replaced in the app\'s own slot '
        'once it has', () async {
      final refresh = refreshOf();
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      await SharedRefreshApp.forwardedRead(
        null,
        refresh: refresh,
        read: () async => null,
        alertPass: () =>
            refresh.afterAlertPass(alertIn(const Duration(hours: 6))),
      );
      await refresh.afterAlertPass(alertIn(const Duration(hours: 1)));

      expect(platform.calls, [
        'schedule:${const Duration(hours: 3)}',
        'schedule:${const Duration(minutes: 30)}',
      ]);
    });

    test('a message\'s read that ends while the check\'s own work is still '
        'served leaves that work its slot', () async {
      final refresh = refreshOf()..workRunning(SharedRefreshSlot.first);

      await SharedRefreshApp.forwardedRead(
        null,
        refresh: refresh,
        read: () async => null,
        alertPass: () async {},
      );
      await refresh.afterAlertPass(alertIn(const Duration(hours: 6)));

      expect(platform.calls, [
        'schedule@second:${const Duration(hours: 3)}',
      ]);
    });
  });

  group('a platform that fails', () {
    test('costs nothing but the call: the next pass asks again', () async {
      final refresh = refreshOf();
      final need = alertIn(const Duration(hours: 6));
      platform.failNext = true;

      await refresh.afterAlertPass(need);
      expect(platform.scheduled, isEmpty);
      await refresh.afterAlertPass(need);

      expect(platform.scheduled, const [Duration(hours: 3)]);
    });

    test('settled() completes once every request has been answered', () async {
      final refresh = refreshOf();
      await refresh.settled();

      // Not awaited, as the alert pass leaves it.
      refresh.afterAlertPass(alertIn(const Duration(hours: 6))).ignore();
      await refresh.settled();

      expect(platform.scheduled, hasLength(1));
    });
  });

  group('databaseShares — syncs and is paired, as the signed-in account', () {
    late AppDatabase db;
    late SettingsService settings;

    setUp(() async {
      db = await openTestDatabase();
      settings = SettingsService.forTesting(db);
    });

    tearDown(() async {
      SettingsService.reset();
      await db.close();
    });

    Future<void> bind({String account = 'me'}) => settings.setSyncBinding(
      SyncBinding(spaceId: 'space', ownerUid: account, accountUid: account),
    );

    Future<void> pair({String account = 'me'}) => settings.setPairingSettings(
      PairingSettings(pairId: 'p1', accountUid: account, partnerUid: 'them'),
    );

    Future<bool> ask(String? uid) =>
        SharedRefresh.databaseShares(uid: uid, settings: settings);

    test('bound to and paired as the signed-in account', () async {
      await bind();
      await pair();

      expect(await ask('me'), isTrue);
    });

    test('nobody signed in', () async {
      await bind();
      await pair();

      expect(await ask(null), isFalse);
    });

    test('never bound', () async {
      await pair();

      expect(await ask('me'), isFalse);
    });

    test('bound by another account', () async {
      await bind(account: 'someone');
      await pair();

      expect(await ask('me'), isFalse);
    });

    test('never paired', () async {
      await bind();

      expect(await ask('me'), isFalse);
    });

    test('the stored pair is another account\'s', () async {
      await bind();
      await pair(account: 'someone');

      expect(await ask('me'), isFalse);
    });
  });
}
