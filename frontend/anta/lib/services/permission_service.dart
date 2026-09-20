import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/app_permission.dart';
import 'permission_gateway.dart';
import 'settings_service.dart';

abstract class PermissionPromptStore {
  Future<String?> readAcknowledgement();

  Future<void> writeAcknowledgement(String value);

  Future<bool> readLaunchPromptEnabled();

  Future<void> writeLaunchPromptEnabled(bool value);
}

class SettingsPermissionPromptStore implements PermissionPromptStore {
  const SettingsPermissionPromptStore();

  @override
  Future<String?> readAcknowledgement() async =>
      (await SettingsService.getInstance()).getPermissionPromptAcknowledged();

  @override
  Future<void> writeAcknowledgement(String value) async =>
      (await SettingsService.getInstance()).setPermissionPromptAcknowledged(
        value,
      );

  @override
  Future<bool> readLaunchPromptEnabled() async =>
      (await SettingsService.getInstance()).getPermissionLaunchPrompt();

  @override
  Future<void> writeLaunchPromptEnabled(bool value) async =>
      (await SettingsService.getInstance()).setPermissionLaunchPrompt(value);
}

class PermissionAcknowledgement {
  const PermissionAcknowledgement({
    required this.deviceId,
    required this.missing,
  });

  static const String _fieldSeparator = '|';
  static const String _nameSeparator = ',';

  final String deviceId;
  final Set<String> missing;

  bool covers({required String deviceId, required Iterable<String> missing}) =>
      deviceId == this.deviceId && this.missing.containsAll(missing);

  String encode() {
    final names = missing.toList()..sort();
    return '$deviceId$_fieldSeparator${names.join(_nameSeparator)}';
  }

  static PermissionAcknowledgement? decode(String? raw) {
    if (raw == null) return null;
    final split = raw.indexOf(_fieldSeparator);
    if (split <= 0) return null;
    return PermissionAcknowledgement(
      deviceId: raw.substring(0, split),
      missing: {
        for (final name in raw.substring(split + 1).split(_nameSeparator))
          if (name.isNotEmpty) name,
      },
    );
  }
}

class PermissionService {
  PermissionService({
    required PermissionGateway gateway,
    required PermissionPromptStore store,
    required Future<String> Function() deviceId,
    Stream<AppLifecycleState>? lifecycle,
  }) : _gateway = gateway,
       _store = store,
       _deviceId = deviceId {
    _lifecycleSubscription = lifecycle?.listen(_onLifecycle);
  }

  final PermissionGateway _gateway;
  final PermissionPromptStore _store;
  final Future<String> Function() _deviceId;

  final ValueNotifier<PermissionSnapshot?> _snapshot = ValueNotifier(null);
  final Set<AppPermission> _blocked = {};

  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  Future<void>? _tail;
  int _generation = 0;
  bool _disposed = false;

  ValueListenable<PermissionSnapshot?> get snapshot => _snapshot;

  bool get hasAppSettings => _gateway.hasAppSettings;

  static Stream<AppLifecycleState> appLifecycle() {
    late final StreamController<AppLifecycleState> controller;
    AppLifecycleListener? listener;
    controller = StreamController<AppLifecycleState>.broadcast(
      onListen: () {
        listener = AppLifecycleListener(onStateChange: controller.add);
      },
      onCancel: () {
        listener?.dispose();
        listener = null;
      },
    );
    return controller.stream;
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<PermissionSnapshot> refresh() async {
    final generation = ++_generation;
    Map<AppPermission, PermissionStatus> statuses;
    try {
      statuses = await _gateway.statuses();
    } catch (e) {
      debugPrint('[PermissionService] status read failed: $e');
      statuses = {
        for (final permission in _gateway.supported)
          permission: PermissionStatus.unknown,
      };
    }
    _blocked.removeWhere(
      (permission) => statuses[permission] == PermissionStatus.granted,
    );
    final snapshot = _snapshotOf(statuses);
    if (generation == _generation && !_disposed) _snapshot.value = snapshot;
    return snapshot;
  }

  PermissionSnapshot _snapshotOf(
    Map<AppPermission, PermissionStatus> statuses,
  ) {
    return PermissionSnapshot([
      for (final permission in _gateway.supported)
        if (_applies(statuses[permission]))
          PermissionEntry(
            permission: permission,
            status: statuses[permission]!,
            canPrompt:
                _gateway.canPrompt(permission) &&
                !_blocked.contains(permission),
          ),
    ]);
  }

  bool _applies(PermissionStatus? status) =>
      status != null && status != PermissionStatus.notApplicable;

  Future<PermissionRequestOutcome> request(AppPermission permission) =>
      _serialize(() => _request(permission));

  Future<PermissionRequestOutcome> _request(AppPermission permission) async {
    final entry = (await refresh()).entryOf(permission);
    if (entry == null) return PermissionRequestOutcome.unavailable;
    if (entry.isGranted) return PermissionRequestOutcome.granted;
    if (entry.isMissing && entry.canPrompt) {
      final result = await _prompt(permission);
      final after = await refresh();
      if (after.statusOf(permission) == PermissionStatus.granted) {
        return PermissionRequestOutcome.granted;
      }
      if (result == PermissionPromptResult.denied) {
        return PermissionRequestOutcome.denied;
      }
    }
    final opened = await _gateway.openSettings(permission);
    return opened
        ? PermissionRequestOutcome.openedSettings
        : PermissionRequestOutcome.unavailable;
  }

  Future<PermissionPromptResult> _prompt(AppPermission permission) async {
    var result = PermissionPromptResult.blocked;
    try {
      result = await _gateway.prompt(permission);
    } catch (e) {
      debugPrint('[PermissionService] prompt failed: $e');
    }
    if (result == PermissionPromptResult.blocked) _blocked.add(permission);
    return result;
  }

  Future<PermissionSnapshot> promptFor(Iterable<AppPermission> permissions) {
    final wanted = permissions.toSet();
    return _serialize(() async {
      final before = await refresh();
      for (final entry in before.missing) {
        if (entry.canPrompt && wanted.contains(entry.permission)) {
          await _prompt(entry.permission);
        }
      }
      return refresh();
    });
  }

  Future<PermissionSnapshot> promptForMissing() =>
      promptFor(AppPermission.values);

  Future<bool> openAppSettings() => _gateway.openAppSettings();

  Future<bool> isLaunchPromptEnabled() => _store.readLaunchPromptEnabled();

  Future<void> setLaunchPromptEnabled(bool value) =>
      _store.writeLaunchPromptEnabled(value);

  Future<PermissionSnapshot?> launchPromptSnapshot() async {
    if (!await _store.readLaunchPromptEnabled()) return null;
    final snapshot = await refresh();
    if (!snapshot.needsAttention) return null;
    final acknowledged = PermissionAcknowledgement.decode(
      await _store.readAcknowledgement(),
    );
    if (acknowledged != null &&
        acknowledged.covers(
          deviceId: await _deviceId(),
          missing: _missingEssentialNames(snapshot),
        )) {
      return null;
    }
    return snapshot;
  }

  Future<void> acknowledgeLaunchPrompt() async {
    final snapshot = await refresh();
    await _store.writeAcknowledgement(
      PermissionAcknowledgement(
        deviceId: await _deviceId(),
        missing: _missingEssentialNames(snapshot).toSet(),
      ).encode(),
    );
  }

  Iterable<String> _missingEssentialNames(PermissionSnapshot snapshot) =>
      snapshot.missingEssential.map((entry) => entry.permission.name);

  Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _lifecycleSubscription?.cancel();
    _lifecycleSubscription = null;
    _snapshot.dispose();
  }
}
