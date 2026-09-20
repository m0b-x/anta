import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/models/app_permission.dart';

import '../services/permission_support.dart';

Future<(PermissionsBloc, List<PermissionsState>)> _pumpBloc(
  FakePermissionGateway gateway, {
  MemoryPermissionPromptStore? store,
}) async {
  final bloc = PermissionsBloc(
    service: permissionServiceOver(gateway, store: store),
  );
  final states = <PermissionsState>[];
  bloc.stream.listen(states.add);
  bloc.add(const PermissionsStarted());
  await pumpEventQueue();
  return (bloc, states);
}

void main() {
  group('start', () {
    test('loads the live picture and the launch option', () async {
      final store = MemoryPermissionPromptStore()..launchPromptEnabled = false;
      final (bloc, states) = await _pumpBloc(
        FakePermissionGateway(
          statuses: {AppPermission.notifications: PermissionStatus.denied},
        ),
        store: store,
      );

      final ready = states.single as PermissionsReady;
      expect(ready.snapshot.needsAttention, isTrue);
      expect(ready.launchPromptEnabled, isFalse);
      expect(ready.hasAppSettings, isTrue);
      expect(ready.isBusy, isFalse);
      expect(ready.notice, isNull);
      await bloc.close();
    });

    test(
      'the stored launch option survives a refresh that lands first',
      () async {
        final slowRead = Completer<void>();
        final store = MemoryPermissionPromptStore()
          ..launchPromptEnabled = false
          ..optionGate = slowRead;
        final bloc = PermissionsBloc(
          service: permissionServiceOver(
            FakePermissionGateway(statuses: allGranted),
            store: store,
          ),
        );
        final states = <PermissionsState>[];
        bloc.stream.listen(states.add);

        bloc
          ..add(const PermissionsStarted())
          ..add(const PermissionsRefreshRequested());
        await pumpEventQueue();
        expect(states.single, isA<PermissionsReady>());

        slowRead.complete();
        await pumpEventQueue();

        expect((states.last as PermissionsReady).launchPromptEnabled, isFalse);
        await bloc.close();
      },
    );

    test('starting twice subscribes once', () async {
      final gateway = FakePermissionGateway(statuses: allGranted);
      final (bloc, states) = await _pumpBloc(gateway);

      bloc.add(const PermissionsStarted());
      await pumpEventQueue();

      expect(states, hasLength(1));
      expect(gateway.statusReads, 1);
      await bloc.close();
    });

    test('a change the service reads elsewhere reaches the state', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final service = permissionServiceOver(gateway);
      final bloc = PermissionsBloc(service: service);
      final states = <PermissionsState>[];
      bloc.stream.listen(states.add);
      bloc.add(const PermissionsStarted());
      await pumpEventQueue();

      gateway.current[AppPermission.notifications] = PermissionStatus.granted;
      await service.refresh();
      await pumpEventQueue();

      expect(states.last.snapshotOrNull!.needsAttention, isFalse);
      await bloc.close();

      gateway.current[AppPermission.notifications] = PermissionStatus.denied;
      await service.refresh();
      await pumpEventQueue();
      expect(states.last.snapshotOrNull!.needsAttention, isFalse);
    });
  });

  group('request', () {
    test('marks the permission in flight, then reports the outcome', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final (bloc, states) = await _pumpBloc(gateway);

      bloc.add(const PermissionRequested(AppPermission.notifications));
      await pumpEventQueue();

      final inFlight = states.whereType<PermissionsReady>().where(
        (state) => state.requesting == AppPermission.notifications,
      );
      expect(inFlight, isNotEmpty);

      final settled = states.last as PermissionsReady;
      expect(settled.isBusy, isFalse);
      expect(settled.snapshot.needsAttention, isFalse);
      expect(settled.notice!.kind, PermissionNoticeKind.request);
      expect(settled.notice!.outcome, PermissionRequestOutcome.granted);
      expect(settled.notice!.permission, AppPermission.notifications);
      await bloc.close();
    });

    test('a second tap while one is in flight is dropped', () async {
      final gateway = FakePermissionGateway(
        statuses: {
          AppPermission.notifications: PermissionStatus.denied,
          AppPermission.fullScreenIntent: PermissionStatus.denied,
        },
      );
      final gate = Completer<void>();
      gateway.promptGate = gate;
      final (bloc, states) = await _pumpBloc(gateway);

      bloc.add(const PermissionRequested(AppPermission.notifications));
      await pumpEventQueue();
      bloc.add(const PermissionRequested(AppPermission.fullScreenIntent));
      await pumpEventQueue();

      expect(gateway.settingsOpens, isEmpty);

      gate.complete();
      await pumpEventQueue();

      expect(gateway.settingsOpens, isEmpty);
      expect((states.last as PermissionsReady).notice!.serial, 1);
      await bloc.close();
    });

    test(
      'every outcome gets its own serial, so a listener fires each time',
      () async {
        final gateway = FakePermissionGateway(
          statuses: {AppPermission.fullScreenIntent: PermissionStatus.denied},
        )..settingsAvailable = false;
        final (bloc, states) = await _pumpBloc(gateway);

        bloc.add(const PermissionRequested(AppPermission.fullScreenIntent));
        await pumpEventQueue();
        bloc.add(const PermissionRequested(AppPermission.fullScreenIntent));
        await pumpEventQueue();

        final notices = states
            .whereType<PermissionsReady>()
            .map((state) => state.notice)
            .nonNulls
            .toSet();
        expect(notices.map((notice) => notice.serial), [1, 2]);
        expect(
          notices.every(
            (notice) => notice.outcome == PermissionRequestOutcome.unavailable,
          ),
          isTrue,
        );
        await bloc.close();
      },
    );
  });

  group('batch', () {
    test('prompts what can be prompted and reports nothing left', () async {
      final gateway = FakePermissionGateway(
        statuses: {
          ...allGranted,
          AppPermission.notifications: PermissionStatus.denied,
        },
      );
      final (bloc, states) = await _pumpBloc(gateway);

      bloc.add(const PromptablePermissionsRequested());
      await pumpEventQueue();

      expect(
        states.whereType<PermissionsReady>().any(
          (state) => state.requestingAll,
        ),
        isTrue,
      );
      final settled = states.last as PermissionsReady;
      expect(settled.isBusy, isFalse);
      expect(settled.notice!.kind, PermissionNoticeKind.batch);
      expect(settled.notice!.outcome, PermissionRequestOutcome.granted);
      expect(gateway.prompts, [AppPermission.notifications]);
      expect(gateway.settingsOpens, isEmpty);
      await bloc.close();
    });

    test('reports what is still missing without opening settings', () async {
      final gateway = FakePermissionGateway(
        statuses: {
          AppPermission.notifications: PermissionStatus.denied,
          AppPermission.batteryOptimization: PermissionStatus.denied,
        },
      );
      final (bloc, states) = await _pumpBloc(gateway);

      bloc.add(const PromptablePermissionsRequested());
      await pumpEventQueue();

      final settled = states.last as PermissionsReady;
      expect(settled.notice!.outcome, PermissionRequestOutcome.denied);
      expect(settled.snapshot.needsAttention, isFalse);
      expect(settled.snapshot.hasMissing, isTrue);
      expect(gateway.settingsOpens, isEmpty);
      await bloc.close();
    });
  });

  group('options', () {
    test('the launch option is persisted', () async {
      final store = MemoryPermissionPromptStore();
      final (bloc, states) = await _pumpBloc(
        FakePermissionGateway(statuses: allGranted),
        store: store,
      );

      bloc.add(const LaunchPromptToggled(false));
      await pumpEventQueue();

      expect((states.last as PermissionsReady).launchPromptEnabled, isFalse);
      expect(store.launchPromptEnabled, isFalse);
      await bloc.close();
    });

    test('system settings that cannot open raise a notice', () async {
      final gateway = FakePermissionGateway(statuses: allGranted)
        ..settingsAvailable = false;
      final (bloc, states) = await _pumpBloc(gateway);

      bloc.add(const AppSettingsRequested());
      await pumpEventQueue();

      final settled = states.last as PermissionsReady;
      expect(gateway.appSettingsOpens, 1);
      expect(settled.notice!.kind, PermissionNoticeKind.appSettings);
      expect(settled.notice!.outcome, PermissionRequestOutcome.unavailable);
      await bloc.close();
    });

    test('a refresh re-reads the platform', () async {
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final (bloc, states) = await _pumpBloc(gateway);

      gateway.current[AppPermission.notifications] = PermissionStatus.granted;
      bloc.add(const PermissionsRefreshRequested());
      await pumpEventQueue();

      expect(states.last.snapshotOrNull!.needsAttention, isFalse);
      await bloc.close();
    });
  });
}
