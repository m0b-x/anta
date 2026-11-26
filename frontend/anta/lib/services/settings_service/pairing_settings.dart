part of '../settings_service.dart';

/// The pairing rows of `user_settings`, read and written as one value so a
/// half-updated pairing (a `pairId` without the account it belongs to) is not
/// representable.
class PairingSettings extends Equatable {
  final String? pairId;
  final String? accountUid;
  final String? partnerUid;
  final String? partnerName;
  final String? pendingCode;
  final DateTime? pendingExpiresAt;
  final bool endedNoticePending;

  /// The pair the partner ended while its leave notice may still be told
  /// ([SettingsKeys.pairingEndedPair]); it outlives [endedNoticePending].
  final String? endedPairId;

  const PairingSettings({
    this.pairId,
    this.accountUid,
    this.partnerUid,
    this.partnerName,
    this.pendingCode,
    this.pendingExpiresAt,
    this.endedNoticePending = false,
    this.endedPairId,
  });

  static const PairingSettings empty = PairingSettings();

  bool get isPaired => pairId != null;

  bool get hasPendingInvite => pendingCode != null;

  /// Non-clearing by design: every field that needs to become null is cleared
  /// by building a fresh instance instead, so no call site can drop a field by
  /// forgetting to pass it.
  PairingSettings copyWith({
    String? pairId,
    String? accountUid,
    String? partnerUid,
    String? partnerName,
    String? pendingCode,
    DateTime? pendingExpiresAt,
    bool? endedNoticePending,
  }) => PairingSettings(
    pairId: pairId ?? this.pairId,
    accountUid: accountUid ?? this.accountUid,
    partnerUid: partnerUid ?? this.partnerUid,
    partnerName: partnerName ?? this.partnerName,
    pendingCode: pendingCode ?? this.pendingCode,
    pendingExpiresAt: pendingExpiresAt ?? this.pendingExpiresAt,
    endedNoticePending: endedNoticePending ?? this.endedNoticePending,
    endedPairId: endedPairId,
  );

  PairingSettings clearPendingInvite() => PairingSettings(
    pairId: pairId,
    accountUid: accountUid,
    partnerUid: partnerUid,
    partnerName: partnerName,
    endedNoticePending: endedNoticePending,
    endedPairId: endedPairId,
  );

  @override
  List<Object?> get props => [
    pairId,
    accountUid,
    partnerUid,
    partnerName,
    pendingCode,
    pendingExpiresAt,
    endedNoticePending,
    endedPairId,
  ];
}
