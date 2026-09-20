import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_permission.dart';
import '../../services/permission_service.dart';
import 'permissions_event.dart';
import 'permissions_state.dart';

export 'permissions_event.dart';
export 'permissions_state.dart';

class PermissionsBloc extends Bloc<PermissionsEvent, PermissionsState> {
  PermissionsBloc({required PermissionService service})
    : _service = service,
      super(const PermissionsInitial()) {
    on<PermissionsStarted>(_onStarted);
    on<PermissionsRefreshRequested>(_onRefreshRequested);
    on<PermissionSnapshotChanged>(_onSnapshotChanged);
    on<PermissionRequested>(_onPermissionRequested);
    on<PromptablePermissionsRequested>(_onPromptableRequested);
    on<AppSettingsRequested>(_onAppSettingsRequested);
    on<LaunchPromptToggled>(_onLaunchPromptToggled);
  }

  final PermissionService _service;

  bool _started = false;
  bool _launchPromptEnabled = true;
  bool _launchPromptToggled = false;
  int _noticeSerial = 0;

  Future<void> _onStarted(
    PermissionsStarted event,
    Emitter<PermissionsState> emit,
  ) async {
    if (_started) return;
    _started = true;
    _service.snapshot.addListener(_onServiceSnapshot);
    try {
      final stored = await _service.isLaunchPromptEnabled();
      if (!_launchPromptToggled) _launchPromptEnabled = stored;
    } catch (e) {
      debugPrint('[PermissionsBloc] launch prompt option unreadable: $e');
    }
    final snapshot = _service.snapshot.value ?? await _service.refresh();
    if (isClosed) return;
    _emitSnapshot(snapshot, emit);
  }

  void _onServiceSnapshot() {
    final snapshot = _service.snapshot.value;
    if (snapshot == null || isClosed) return;
    add(PermissionSnapshotChanged(snapshot));
  }

  Future<void> _onRefreshRequested(
    PermissionsRefreshRequested event,
    Emitter<PermissionsState> emit,
  ) async {
    final snapshot = await _service.refresh();
    if (isClosed) return;
    _emitSnapshot(snapshot, emit);
  }

  void _onSnapshotChanged(
    PermissionSnapshotChanged event,
    Emitter<PermissionsState> emit,
  ) {
    _emitSnapshot(event.snapshot, emit);
  }

  void _emitSnapshot(
    PermissionSnapshot snapshot,
    Emitter<PermissionsState> emit,
  ) {
    final current = state;
    emit(
      current is PermissionsReady
          ? current.copyWith(
              snapshot: snapshot,
              launchPromptEnabled: _launchPromptEnabled,
            )
          : PermissionsReady(
              snapshot: snapshot,
              launchPromptEnabled: _launchPromptEnabled,
              hasAppSettings: _service.hasAppSettings,
            ),
    );
  }

  Future<void> _onPermissionRequested(
    PermissionRequested event,
    Emitter<PermissionsState> emit,
  ) async {
    final current = state;
    if (current is! PermissionsReady || current.isBusy) return;
    emit(current.copyWith(requesting: event.permission));
    var outcome = PermissionRequestOutcome.unavailable;
    try {
      outcome = await _service.request(event.permission);
    } catch (e) {
      debugPrint('[PermissionsBloc] request failed: $e');
    }
    if (isClosed) return;
    _settle(
      emit,
      PermissionNoticeKind.request,
      outcome,
      permission: event.permission,
    );
  }

  Future<void> _onPromptableRequested(
    PromptablePermissionsRequested event,
    Emitter<PermissionsState> emit,
  ) async {
    final current = state;
    if (current is! PermissionsReady || current.isBusy) return;
    emit(current.copyWith(requestingAll: true));
    PermissionSnapshot? after;
    try {
      after = await _service.promptForMissing();
    } catch (e) {
      debugPrint('[PermissionsBloc] batch request failed: $e');
    }
    if (isClosed) return;
    final missing = after?.hasMissing ?? true;
    _settle(
      emit,
      PermissionNoticeKind.batch,
      missing
          ? PermissionRequestOutcome.denied
          : PermissionRequestOutcome.granted,
    );
  }

  Future<void> _onAppSettingsRequested(
    AppSettingsRequested event,
    Emitter<PermissionsState> emit,
  ) async {
    var opened = false;
    try {
      opened = await _service.openAppSettings();
    } catch (e) {
      debugPrint('[PermissionsBloc] app settings failed: $e');
    }
    if (isClosed || state is! PermissionsReady) return;
    _settle(
      emit,
      PermissionNoticeKind.appSettings,
      opened
          ? PermissionRequestOutcome.openedSettings
          : PermissionRequestOutcome.unavailable,
    );
  }

  void _settle(
    Emitter<PermissionsState> emit,
    PermissionNoticeKind kind,
    PermissionRequestOutcome outcome, {
    AppPermission? permission,
  }) {
    final current = state;
    if (current is! PermissionsReady) return;
    emit(
      current.copyWith(
        snapshot: _service.snapshot.value,
        clearRequesting: true,
        requestingAll: false,
        notice: PermissionNotice(
          serial: ++_noticeSerial,
          kind: kind,
          outcome: outcome,
          permission: permission,
        ),
      ),
    );
  }

  Future<void> _onLaunchPromptToggled(
    LaunchPromptToggled event,
    Emitter<PermissionsState> emit,
  ) async {
    _launchPromptEnabled = event.enabled;
    _launchPromptToggled = true;
    final current = state;
    if (current is PermissionsReady) {
      emit(current.copyWith(launchPromptEnabled: event.enabled));
    }
    try {
      await _service.setLaunchPromptEnabled(event.enabled);
    } catch (e) {
      debugPrint('[PermissionsBloc] launch prompt option not saved: $e');
    }
  }

  @override
  Future<void> close() {
    if (_started) _service.snapshot.removeListener(_onServiceSnapshot);
    return super.close();
  }
}
