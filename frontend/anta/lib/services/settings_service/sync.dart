part of '../settings_service.dart';

const List<String> _pairingKeys = [
  SettingsKeys.pairingPairId,
  SettingsKeys.pairingAccountUid,
  SettingsKeys.pairingPartnerUid,
  SettingsKeys.pairingPartnerName,
  SettingsKeys.pairingPendingCode,
  SettingsKeys.pairingPendingExpiresAt,
  SettingsKeys.pairingEndedNotice,
  SettingsKeys.pairingEndedPair,
];

/// Pairing and sync: the pair this database belongs to, the space it is
/// bound to, and the cadence.
mixin _SyncSettings on _ShareSettings {
  /// The cached pairing state for this database. A cache, not the truth: the
  /// server answers which active pair contains the signed-in uid, and
  /// `PairingService` reconciles this against it on sign-in and resume.
  ///
  /// One statement for every row: the pairing is read on each launch, for
  /// an account that never paired too.
  Future<PairingSettings> getPairingSettings() async {
    final values = await _db.userSettingsDao.getValuesFor(_pairingKeys);
    final expiresAt = values[SettingsKeys.pairingPendingExpiresAt];
    return PairingSettings(
      pairId: _nonEmpty(values[SettingsKeys.pairingPairId]),
      accountUid: _nonEmpty(values[SettingsKeys.pairingAccountUid]),
      partnerUid: _nonEmpty(values[SettingsKeys.pairingPartnerUid]),
      partnerName: _nonEmpty(values[SettingsKeys.pairingPartnerName]),
      pendingCode: _nonEmpty(values[SettingsKeys.pairingPendingCode]),
      pendingExpiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(expiresAt) ?? 0,
              isUtc: true,
            ),
      endedNoticePending: _decodeBool(
        values[SettingsKeys.pairingEndedNotice],
        false,
      ),
      endedPairId: _nonEmpty(values[SettingsKeys.pairingEndedPair]),
    );
  }

  /// Transactional on purpose: these rows are one value. A partial write
  /// (a `pairId` without the account it belongs to) is exactly the state
  /// [PairingSettings] exists to make unrepresentable.
  ///
  /// [startAlertsAt] is what may ring on the partner's events, set back in
  /// the same transaction when the pair stored is another one than this
  /// database was last in (share surfaces D38): both are written or
  /// neither, so no pair ever stands under the choice made for another —
  /// written apart, one failed write carried the old pair's choice to the
  /// new one for good, since no later reconcile saw another pair again.
  /// Published once it is stored, as a read of it would be.
  ///
  /// A pair stored is also remembered as the last one
  /// ([SettingsKeys.pairingLastPair]), past its end.
  ///
  /// [clearMarksOfOtherPairs]: the pair stored is another than the one that
  /// stood, so every share mark set under any other pair is cleared in this
  /// same transaction — stamped and queued, so its rows are sent private by
  /// the next drain (`FolderDao.clearSharesExcept`). A pair's id never
  /// comes round again, so such a mark can never be valid again; left to
  /// the pair's first shared read, it read as a share with the new partner
  /// in every list of the app's own until then — seconds, or as long as
  /// the phone was offline. A database with no mark pays the one statement
  /// that says so. Returns how many marks were cleared.
  ///
  /// What a write costs past its eight rows: one that stores no pair,
  /// nothing; one that stores a pair, one read of the last pair, and one
  /// read of the binding ([boundToAnotherAccount]) only when a step must
  /// know whose the database's sharing is — a mark exists to clear,
  /// an alert reset is asked, or the last pair would change. The same pair
  /// adopted again on a database with no mark reads the last pair alone.
  ///
  /// Only when the marks are the adopting account's
  /// ([PairingSettings.accountUid]) to take away (D39's amendment): the
  /// database is bound to no space, or to that account's. One bound to
  /// another account keeps them — that account's sign-in on this phone
  /// would drain their clearing under its own binding, and its partner
  /// would lose everything it shared to someone else's pair.
  ///
  /// The same holds for the rest of the binding owner's sharing state: on
  /// a database bound to another account, a pair stored neither resets the
  /// alert choice nor is remembered as the last pair — remembered, it would
  /// read as another pair at the owner's return and reset the choice then.
  ///
  /// Answers how many marks were cleared, and whether [startAlertsAt] was
  /// stored — the alert pass that follows a reset is owed only then.
  Future<({int marksCleared, bool alertsReset})> setPairingSettings(
    PairingSettings settings, {
    ShareAlerts? startAlertsAt,
    bool clearMarksOfOtherPairs = false,
  }) async {
    var cleared = 0;
    var alertsReset = false;
    await _db.transaction(() async {
      // Read once, and only when a step below needs to know.
      bool? owners;
      Future<bool> owns() async => owners ??=
          settings.pairId == null ||
          !await boundToAnotherAccount(settings.accountUid);
      if (clearMarksOfOtherPairs &&
          settings.pairId != null &&
          await _db.syncDao.anyShareMark() &&
          await owns()) {
        cleared = await _db.folderDao.clearSharesExcept(settings.pairId);
      }
      if (startAlertsAt != null && await owns()) {
        await _db.userSettingsDao.setValue(
          SettingsKeys.shareAlerts,
          startAlertsAt.name,
        );
        alertsReset = true;
      }
      if (settings.pairId != null &&
          await getLastPairId() != settings.pairId &&
          await owns()) {
        await _write(SettingsKeys.pairingLastPair, settings.pairId);
      }
      await _write(SettingsKeys.pairingPairId, settings.pairId);
      await _write(SettingsKeys.pairingAccountUid, settings.accountUid);
      await _write(SettingsKeys.pairingPartnerUid, settings.partnerUid);
      await _write(SettingsKeys.pairingPartnerName, settings.partnerName);
      await _write(SettingsKeys.pairingPendingCode, settings.pendingCode);
      await _write(
        SettingsKeys.pairingPendingExpiresAt,
        settings.pendingExpiresAt?.toUtc().millisecondsSinceEpoch.toString(),
      );
      await _setBool(
        SettingsKeys.pairingEndedNotice,
        settings.endedNoticePending,
      );
      await _write(SettingsKeys.pairingEndedPair, settings.endedPairId);
    });
    if (alertsReset) EventAlerts.configureShareAlerts(startAlertsAt);
    return (marksCleared: cleared, alertsReset: alertsReset);
  }

  /// Whether this database is bound to a space by another account than
  /// [accountUid] — the one signed in, or the one a write is for. What such
  /// a database shares is that account's: nobody else may change it here.
  /// False for a database bound to no space.
  ///
  /// True for a null [accountUid] on a bound database, on purpose. Its one
  /// caller is [setPairingSettings], with the account of the pairing it
  /// stores — null only for a pair stored with no account named, which no
  /// one can show is the binding's owner, so the owner's marks, alert
  /// choice and last pair are kept. The screens' own question
  /// (`ShareSyncSource.boundToAnotherAccount`) answers false with nobody
  /// signed in, on purpose too: it decides what a screen lists and
  /// clears, and with nobody signed in there is nothing to list.
  Future<bool> boundToAnotherAccount(String? accountUid) async {
    final binding = await getSyncBinding();
    return binding != null && binding.accountUid != accountUid;
  }

  /// The last pair this database was in, standing or ended; null when it
  /// never was in one, or its pairing rows were stripped — a restore, a
  /// handed-out copy.
  Future<String?> getLastPairId() async => _nonEmpty(
    await _db.userSettingsDao.getValue(SettingsKeys.pairingLastPair),
  );

  /// The space this database is bound to, or null unless the space, its
  /// owner and the binding account are all stored.
  Future<SyncBinding?> getSyncBinding() async {
    final spaceId = _nonEmpty(
      await _db.userSettingsDao.getValue(SettingsKeys.syncSpaceId),
    );
    final ownerUid = _nonEmpty(
      await _db.userSettingsDao.getValue(SettingsKeys.syncSpaceOwnerUid),
    );
    final accountUid = _nonEmpty(
      await _db.userSettingsDao.getValue(SettingsKeys.syncSpaceAccountUid),
    );
    if (spaceId == null || ownerUid == null || accountUid == null) return null;
    final boundAt = int.tryParse(
      await _db.userSettingsDao.getValue(SettingsKeys.syncSpaceBoundAt) ?? '',
    );
    return SyncBinding(
      spaceId: spaceId,
      ownerUid: ownerUid,
      accountUid: accountUid,
      boundAt: boundAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(boundAt, isUtc: true),
    );
  }

  /// Transactional for the reason [setPairingSettings] is: the four rows are
  /// one value. Null clears all four.
  Future<void> setSyncBinding(SyncBinding? binding) {
    return _db.transaction(() async {
      await _write(SettingsKeys.syncSpaceId, binding?.spaceId);
      await _write(SettingsKeys.syncSpaceOwnerUid, binding?.ownerUid);
      await _write(SettingsKeys.syncSpaceAccountUid, binding?.accountUid);
      await _write(
        SettingsKeys.syncSpaceBoundAt,
        binding?.boundAt?.toUtc().millisecondsSinceEpoch.toString(),
      );
    });
  }

  /// When the sync engine runs on its own; [SyncCadence.automatic] until the
  /// user chooses otherwise.
  Future<SyncCadence> getSyncCadence() async => SyncCadence.parse(
    await _db.userSettingsDao.getValue(SettingsKeys.syncCadence),
  );

  Future<void> setSyncCadence(SyncCadence cadence) =>
      _db.userSettingsDao.setValue(SettingsKeys.syncCadence, cadence.name);
}
