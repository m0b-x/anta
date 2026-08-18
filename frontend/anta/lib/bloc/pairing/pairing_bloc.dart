import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/pairing_gateway.dart';
import '../../services/pairing_service.dart';
import '../../utils/pairing_error.dart';
import 'pairing_event.dart';
import 'pairing_state.dart';

export 'pairing_event.dart';
export 'pairing_state.dart';

class PairingBloc extends Bloc<PairingEvent, PairingState> {
  final AuthService _authService;
  final PairingGateway _gateway;

  PairingService? _service;
  StreamSubscription<AppUser?>? _authSubscription;
  StreamSubscription<PairingStatus>? _statusSubscription;
  StreamSubscription<PairingError>? _errorSubscription;

  /// The account the last reconcile ran for, so a replayed auth emission does
  /// not run it a second time.
  String? _loadedUid;

  PairingBloc({
    required AuthService authService,
    required PairingGateway gateway,
  }) : _authService = authService,
       _gateway = gateway,
       super(const PairingInitial()) {
    on<LoadPairing>(_onLoad);
    on<GenerateInviteRequested>(_onGenerate);
    on<CancelInviteRequested>(_onCancel);
    on<RedeemCodeRequested>(_onRedeem);
    on<UnpairRequested>(_onUnpair);
    on<EndedNoticeDismissed>(_onDismissEnded);
    on<PairingStatusChanged>(_onStatusChanged);
    on<PairingErrorReported>(_onErrorReported);
    on<PairingAuthChanged>(_onAuthChanged);
  }

  Future<void> _onLoad(LoadPairing event, Emitter<PairingState> emit) async {
    // The bound service, not the platform gate — same rule as `SyncBloc`.
    if (!_authService.isAvailable || !_gateway.isAvailable) {
      emit(const PairingUnavailable());
      return;
    }

    _authSubscription ??= _authService.authStateChanges.listen(
      (user) => add(PairingAuthChanged(user)),
    );

    if (_authService.currentUser == null) {
      emit(const PairingSignedOut());
      return;
    }

    emit(const PairingLoading());
    await _reload(emit);
  }

  Future<void> _reload(Emitter<PairingState> emit) async {
    _loadedUid = _authService.currentUser?.uid;
    final service = await _resolveService();
    PairingError? error;
    try {
      emit(_stateFor(await service.load()));
      return;
    } on PairingException catch (e) {
      // Reconciliation needs the network. Failing it must not read as "not
      // paired", so fall back to the cached state and show why.
      error = e.error;
    }
    emit(
      _stateFor(
        service.status,
        failure: PairingFailure(error, PairingAction.load),
      ),
    );
  }

  Future<void> _onGenerate(
    GenerateInviteRequested event,
    Emitter<PairingState> emit,
  ) async {
    final service = await _resolveService();
    emit(_stateFor(service.status, busy: true));
    await _run(
      emit,
      service,
      PairingAction.generate,
      () => service.generateInvite(),
    );
  }

  Future<void> _onCancel(
    CancelInviteRequested event,
    Emitter<PairingState> emit,
  ) async {
    final service = await _resolveService();
    emit(_stateFor(service.status, busy: true));
    await _run(
      emit,
      service,
      PairingAction.cancel,
      () => service.cancelInvite(),
    );
  }

  Future<void> _onRedeem(
    RedeemCodeRequested event,
    Emitter<PairingState> emit,
  ) async {
    final service = await _resolveService();
    emit(_stateFor(service.status, busy: true));
    await _run(
      emit,
      service,
      PairingAction.redeem,
      () => service.redeem(event.code),
    );
  }

  Future<void> _onUnpair(
    UnpairRequested event,
    Emitter<PairingState> emit,
  ) async {
    final service = await _resolveService();
    emit(_stateFor(service.status, busy: true));
    await _run(emit, service, PairingAction.unpair, () => service.unpair());
  }

  Future<void> _onDismissEnded(
    EndedNoticeDismissed event,
    Emitter<PairingState> emit,
  ) async {
    final service = await _resolveService();
    emit(_stateFor(await service.dismissEndedNotice()));
  }

  void _onStatusChanged(
    PairingStatusChanged event,
    Emitter<PairingState> emit,
  ) {
    // An in-flight action owns the state until it resolves, so a listener
    // firing mid-flight must not clear the spinner.
    if (_isBusy(state)) return;
    emit(_stateFor(event.status));
  }

  void _onErrorReported(
    PairingErrorReported event,
    Emitter<PairingState> emit,
  ) {
    final service = _service;
    if (service == null || _isBusy(state)) return;
    emit(
      _stateFor(
        service.status,
        failure: PairingFailure(event.error, PairingAction.background),
      ),
    );
  }

  Future<void> _onAuthChanged(
    PairingAuthChanged event,
    Emitter<PairingState> emit,
  ) async {
    if (event.user == null) {
      _loadedUid = null;
      emit(const PairingSignedOut());
      return;
    }
    // `authStateChanges` replays the current account to a new listener, so
    // opening the page would otherwise reconcile twice concurrently — two
    // server queries, two adopts, and the second listener rebind cancelling
    // the first.
    if (event.user!.uid == _loadedUid) return;
    await _reload(emit);
  }

  Future<void> _run(
    Emitter<PairingState> emit,
    PairingService service,
    PairingAction action,
    Future<PairingStatus> Function() work,
  ) async {
    try {
      emit(_stateFor(await work()));
    } on PairingException catch (e) {
      emit(_stateFor(service.status, failure: PairingFailure(e.error, action)));
    } catch (_) {
      emit(
        _stateFor(
          service.status,
          failure: PairingFailure(PairingError.unknown, action),
        ),
      );
    }
  }

  /// Deliberately re-resolves every time rather than caching. A database
  /// switch fires `PairingService.reset()`, and a held reference would keep
  /// writing the previous database's pairing through a closed connection —
  /// and its streams would be dead, so the UI would never update again.
  Future<PairingService> _resolveService() async {
    final service = await PairingService.getInstance(_authService, _gateway);
    if (identical(service, _service)) return service;

    _service = service;
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    _statusSubscription = service.changes.listen(
      (status) => add(PairingStatusChanged(status)),
    );
    _errorSubscription = service.errors.listen(
      (error) => add(PairingErrorReported(error)),
    );
    return service;
  }

  bool _isBusy(PairingState state) => switch (state) {
    PairingUnpaired(:final busy) => busy,
    PairingInviting(:final busy) => busy,
    PairingPaired(:final busy) => busy,
    _ => false,
  };

  PairingState _stateFor(
    PairingStatus status, {
    PairingFailure? failure,
    bool busy = false,
  }) {
    if (status.isPaired) {
      return PairingPaired(
        partner: status.partner,
        busy: busy,
        failure: failure,
      );
    }
    if (status.endedNoticePending) {
      return PairingEnded(partnerName: status.endedPartnerName);
    }
    final code = status.pendingCode;
    final expiresAt = status.pendingExpiresAt;
    if (code != null && expiresAt != null) {
      return PairingInviting(
        code: code,
        expiresAt: expiresAt,
        busy: busy,
        failure: failure,
      );
    }
    return PairingUnpaired(busy: busy, failure: failure);
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    return super.close();
  }
}
