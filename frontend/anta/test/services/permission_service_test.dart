import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/app_permission.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';

import 'permission_support.dart';

void main() {
  group('snapshot', () {
    test(
      'lists what the platform answered for, in the gateway order',
      () async {
        final gateway = FakePermissionGateway(
          statuses: {
            AppPermission.batteryOptimization: PermissionStatus.denied,
            AppPermission.notifications: PermissionStatus.granted,
            AppPermission.fullScreenIntent: PermissionStatus.unknown,
            AppPermission.exactAlarms: PermissionStatus.notApplicable,
          },
        );
        final service = permissionServiceOver(gateway);

        final snapshot = await service.refresh();

        expect(snapshot.entries.map((entry) => entry.permission), [
          AppPermission.notifications,
          AppPermission.fullScreenIntent,
          AppPermission.batteryOptimization,
        ]);
        expect(
          snapshot.statusOf(AppPermission.exactAlarms),
          PermissionStatus.notApplicable,
        );
        expect(snapshot.hasUnknown, isTrue);
        expect(snapshot.needsAttention, isFalse);
        expect(snapshot.hasMissing, isTrue);
        expect(service.snapshot.value, snapshot);
      },
    );

    test('a platform with nothing to grant reads as empty', () async {
      final service = PermissionService(
        gateway: const NoOpPermissionGateway(),
        store: MemoryPermissionPromptStore(),
        deviceId: () async => 'device-a',
      );

      final snapshot = await service.refresh();

      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.needsAttention, isFalse);
      expect(service.hasAppSettings, isFalse);
    });

    test('only an essential permission raises attention', () async {
      final gateway = FakePermissionGateway(
        statuses: {
          ...allGranted,
          AppPermission.fullScreenIntent: PermissionStatus.denied,
          AppPermission.batteryOptimization: PermissionStatus.denied,
        },
      );
      final service = permissionServiceOver(gateway);

      expect((await service.refresh()).needsAttention, isFalse);

      gateway.current[AppPermission.notifications] = PermissionStatus.denied;
      final snapshot = await service.refresh();

      expect(snapshot.needsAttention, isTrue);
      expect(
        snapshot.missingEssential.single.permission,
        AppPermission.notifications,
      );
    });

    test(
      'a failed read says it could not ask, never "nothing to grant"',
      () async {
        final gateway = FakePermissionGateway(statuses: allGranted)
          ..statusError = StateError('channel gone');
        final service = permissionServiceOver(gateway);

        final snapshot = await service.refresh();

        expect(snapshot.isEmpty, isFalse);
        expect(snapshot.entries.every((entry) => entry.isUnknown), isTrue);
        expect(snapshot.needsAttention, isFalse);
      },
    );

    test('resuming the app re-reads, leaving it does not', () async {
      final lifecycle = StreamController<AppLifecycleState>.broadcast();
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final service = permissionServiceOver(
        gateway,
        lifecycle: lifecycle.stream,
      );
      await service.refresh();
      expect(gateway.statusReads, 1);

      lifecycle.add(AppLifecycleState.inactive);
      lifecycle.add(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(gateway.statusReads, 1);

      gateway.current[AppPermission.notifications] = PermissionStatus.granted;
      lifecycle.add(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(gateway.statusReads, 2);
      expect(
        service.snapshot.value!.statusOf(AppPermission.notifications),
        PermissionStatus.granted,
      );
      await service.dispose();
      await lifecycle.close();
    });

    test('an older read landing late never overwrites a newer one', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final service = permissionServiceOver(gateway);
      final slow = Completer<void>();
      gateway.statusGate = slow;
      final stale = service.refresh();
      await pumpEventQueue();

      gateway.statusGate = null;
      gateway.current[AppPermission.notifications] = PermissionStatus.granted;
      await service.refresh();
      slow.complete();
      await stale;

      expect(
        service.snapshot.value!.statusOf(AppPermission.notifications),
        PermissionStatus.granted,
      );
    });
  });

  group('request', () {
    test('a held permission is not asked about again', () async {
      final gateway = FakePermissionGateway(statuses: allGranted);
      final service = permissionServiceOver(gateway);

      expect(
        await service.request(AppPermission.notifications),
        PermissionRequestOutcome.granted,
      );
      expect(gateway.prompts, isEmpty);
      expect(gateway.settingsOpens, isEmpty);
    });

    test('a promptable permission is prompted, and granted', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final service = permissionServiceOver(gateway);

      expect(
        await service.request(AppPermission.notifications),
        PermissionRequestOutcome.granted,
      );
      expect(gateway.prompts, [AppPermission.notifications]);
      expect(gateway.settingsOpens, isEmpty);
      expect(service.snapshot.value!.needsAttention, isFalse);
    });

    test('a refusal in the system dialog is respected', () async {
      final gateway =
          FakePermissionGateway(
              statuses: {AppPermission.notifications: PermissionStatus.denied},
            )
            ..promptResults[AppPermission.notifications] =
                PermissionPromptResult.denied;
      final service = permissionServiceOver(gateway);

      expect(
        await service.request(AppPermission.notifications),
        PermissionRequestOutcome.denied,
      );
      expect(gateway.settingsOpens, isEmpty);
      expect(
        service.snapshot.value!.entryOf(AppPermission.notifications)!.canPrompt,
        isTrue,
      );
    });

    test(
      'a prompt the system would not show falls through to settings',
      () async {
        final gateway =
            FakePermissionGateway(
                statuses: {
                  AppPermission.notifications: PermissionStatus.denied,
                },
              )
              ..promptResults[AppPermission.notifications] =
                  PermissionPromptResult.blocked;
        final service = permissionServiceOver(gateway);

        expect(
          await service.request(AppPermission.notifications),
          PermissionRequestOutcome.openedSettings,
        );
        expect(gateway.settingsOpens, [AppPermission.notifications]);
        expect(
          service.snapshot.value!
              .entryOf(AppPermission.notifications)!
              .canPrompt,
          isFalse,
        );

        await service.request(AppPermission.notifications);
        expect(gateway.prompts, hasLength(1));
        expect(gateway.settingsOpens, hasLength(2));
      },
    );

    test(
      'a grant made in settings makes the prompt worth trying again',
      () async {
        final gateway =
            FakePermissionGateway(
                statuses: {
                  AppPermission.notifications: PermissionStatus.denied,
                },
              )
              ..promptResults[AppPermission.notifications] =
                  PermissionPromptResult.blocked;
        final service = permissionServiceOver(gateway);
        await service.request(AppPermission.notifications);

        gateway.current[AppPermission.notifications] = PermissionStatus.granted;
        await service.refresh();
        gateway.current[AppPermission.notifications] = PermissionStatus.denied;
        final snapshot = await service.refresh();

        expect(
          snapshot.entryOf(AppPermission.notifications)!.canPrompt,
          isTrue,
        );
      },
    );

    test(
      'a permission with no prompt goes straight to its settings page',
      () async {
        final gateway = FakePermissionGateway(
          statuses: {AppPermission.fullScreenIntent: PermissionStatus.denied},
        );
        final service = permissionServiceOver(gateway);

        expect(
          await service.request(AppPermission.fullScreenIntent),
          PermissionRequestOutcome.openedSettings,
        );
        expect(gateway.prompts, isEmpty);
        expect(gateway.settingsOpens, [AppPermission.fullScreenIntent]);
      },
    );

    test('an unreadable permission offers the settings page too', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.unknown},
      );
      final service = permissionServiceOver(gateway);

      expect(
        await service.request(AppPermission.notifications),
        PermissionRequestOutcome.openedSettings,
      );
      expect(gateway.prompts, isEmpty);
    });

    test('settings that cannot be opened say so', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.fullScreenIntent: PermissionStatus.denied},
      )..settingsAvailable = false;
      final service = permissionServiceOver(gateway);

      expect(
        await service.request(AppPermission.fullScreenIntent),
        PermissionRequestOutcome.unavailable,
      );
    });

    test('a permission this platform lacks is unavailable', () async {
      final service = permissionServiceOver(
        FakePermissionGateway(statuses: allGranted),
      );

      expect(
        await service.request(AppPermission.exactAlarms),
        PermissionRequestOutcome.unavailable,
      );
    });

    test('requests run one at a time', () async {
      final gateway = FakePermissionGateway(
        statuses: {
          AppPermission.notifications: PermissionStatus.denied,
          AppPermission.fullScreenIntent: PermissionStatus.denied,
        },
      );
      final gate = Completer<void>();
      gateway.promptGate = gate;
      final service = permissionServiceOver(gateway);

      final first = service.request(AppPermission.notifications);
      final second = service.request(AppPermission.fullScreenIntent);
      await pumpEventQueue();

      expect(gateway.prompts, [AppPermission.notifications]);
      expect(gateway.settingsOpens, isEmpty);

      gate.complete();
      await Future.wait([first, second]);

      expect(gateway.settingsOpens, [AppPermission.fullScreenIntent]);
    });
  });

  group('promptFor', () {
    test('prompts only what was named, and never opens settings', () async {
      final gateway =
          FakePermissionGateway(
              statuses: {
                AppPermission.notifications: PermissionStatus.denied,
                AppPermission.fullScreenIntent: PermissionStatus.denied,
              },
            )
            ..promptResults[AppPermission.notifications] =
                PermissionPromptResult.blocked;
      final service = permissionServiceOver(gateway);

      final snapshot = await service.promptFor(const [
        AppPermission.notifications,
        AppPermission.fullScreenIntent,
      ]);

      expect(gateway.prompts, [AppPermission.notifications]);
      expect(gateway.settingsOpens, isEmpty);
      expect(snapshot.needsAttention, isTrue);
    });

    test('promptForMissing skips what is already held', () async {
      final gateway = FakePermissionGateway(statuses: allGranted);
      final service = permissionServiceOver(gateway);

      await service.promptForMissing();

      expect(gateway.prompts, isEmpty);
    });
  });

  group('launch prompt', () {
    FakePermissionGateway missingNotifications() => FakePermissionGateway(
      statuses: {
        ...allGranted,
        AppPermission.notifications: PermissionStatus.denied,
      },
    );

    test('is due while something essential is missing', () async {
      final service = permissionServiceOver(missingNotifications());

      final snapshot = await service.launchPromptSnapshot();

      expect(snapshot, isNotNull);
      expect(snapshot!.needsAttention, isTrue);
    });

    test('is not due for a recommended permission alone', () async {
      final service = permissionServiceOver(
        FakePermissionGateway(
          statuses: {
            ...allGranted,
            AppPermission.batteryOptimization: PermissionStatus.denied,
          },
        ),
      );

      expect(await service.launchPromptSnapshot(), isNull);
    });

    test('is not due when the platform could not answer', () async {
      final service = permissionServiceOver(
        FakePermissionGateway(
          statuses: {AppPermission.notifications: PermissionStatus.unknown},
        ),
      );

      expect(await service.launchPromptSnapshot(), isNull);
    });

    test('stays quiet once switched off', () async {
      final store = MemoryPermissionPromptStore()..launchPromptEnabled = false;
      final service = permissionServiceOver(
        missingNotifications(),
        store: store,
      );

      expect(await service.launchPromptSnapshot(), isNull);

      await service.setLaunchPromptEnabled(true);
      expect(await service.launchPromptSnapshot(), isNotNull);
    });

    test('an acknowledged gap is not raised again', () async {
      final store = MemoryPermissionPromptStore();
      final service = permissionServiceOver(
        missingNotifications(),
        store: store,
      );

      await service.acknowledgeLaunchPrompt();

      expect(store.acknowledgement, 'device-a|notifications');
      expect(await service.launchPromptSnapshot(), isNull);
    });

    test('a newly missing essential permission raises it again', () async {
      final store = MemoryPermissionPromptStore();
      final gateway = FakePermissionGateway(statuses: allGranted);
      final service = permissionServiceOver(gateway, store: store);
      await service.acknowledgeLaunchPrompt();
      expect(store.acknowledgement, 'device-a|');
      expect(await service.launchPromptSnapshot(), isNull);

      gateway.current[AppPermission.notifications] = PermissionStatus.denied;

      expect(await service.launchPromptSnapshot(), isNotNull);
    });

    test(
      'an acknowledgement restored from another device does not count',
      () async {
        final store = MemoryPermissionPromptStore()
          ..acknowledgement = 'device-b|notifications';
        final service = permissionServiceOver(
          missingNotifications(),
          store: store,
        );

        expect(await service.launchPromptSnapshot(), isNotNull);
      },
    );

    test('a stored value it cannot read counts as never asked', () async {
      for (final junk in ['', 'no-separator', '|notifications']) {
        final store = MemoryPermissionPromptStore()..acknowledgement = junk;
        final service = permissionServiceOver(
          missingNotifications(),
          store: store,
        );

        expect(await service.launchPromptSnapshot(), isNotNull, reason: junk);
      }
    });
  });

  group('acknowledgement codec', () {
    test('round trips, names sorted', () {
      const value = PermissionAcknowledgement(
        deviceId: 'device-a',
        missing: {'notifications', 'exactAlarms'},
      );

      expect(value.encode(), 'device-a|exactAlarms,notifications');

      final decoded = PermissionAcknowledgement.decode(value.encode())!;
      expect(decoded.deviceId, 'device-a');
      expect(decoded.missing, {'notifications', 'exactAlarms'});
    });

    test('covers a subset on the same device only', () {
      const value = PermissionAcknowledgement(
        deviceId: 'device-a',
        missing: {'notifications', 'exactAlarms'},
      );

      expect(
        value.covers(deviceId: 'device-a', missing: ['notifications']),
        isTrue,
      );
      expect(value.covers(deviceId: 'device-a', missing: const []), isTrue);
      expect(
        value.covers(deviceId: 'device-a', missing: ['fullScreenIntent']),
        isFalse,
      );
      expect(
        value.covers(deviceId: 'device-b', missing: ['notifications']),
        isFalse,
      );
    });
  });
}
