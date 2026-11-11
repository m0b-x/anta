import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/settings_keys.dart';
import 'sync_gateway.dart';

/// One database of this install holding one space.
class SyncSpaceClaim extends Equatable {
  final SyncSpaceRef space;
  final String databaseName;

  const SyncSpaceClaim({required this.space, required this.databaseName});

  static const _spaceId = 'spaceId';
  static const _ownerUid = 'ownerUid';
  static const _databaseName = 'databaseName';

  Map<String, String> toJson() => {
    _spaceId: space.spaceId,
    _ownerUid: space.ownerUid,
    _databaseName: databaseName,
  };

  /// Null for an entry missing a field, which is dropped rather than failing
  /// every later read.
  static SyncSpaceClaim? fromJson(Object? json) {
    if (json is! Map) return null;
    final spaceId = json[_spaceId];
    final ownerUid = json[_ownerUid];
    final databaseName = json[_databaseName];
    if (spaceId is! String || ownerUid is! String || databaseName is! String) {
      return null;
    }
    return SyncSpaceClaim(
      space: SyncSpaceRef(ownerUid: ownerUid, spaceId: spaceId),
      databaseName: databaseName,
    );
  }

  @override
  List<Object?> get props => [space, databaseName];
}

/// A cloud copy whose deletion began on this install and has not finished
/// (cloud-multi-user-roadmap §5): the space is marked and the database that
/// synced with it unbound, so this record is what the "Finish deleting" row
/// and `SyncSpaceService.finishPendingDeletions` work from. The owner is
/// [SyncSpaceRef.ownerUid]: only that account may finish it.
class SyncPendingDeletion extends Equatable {
  final SyncSpaceRef space;

  /// The space's name when the deletion began, for the row that offers to
  /// finish it — the space itself may be half empty by now.
  final String spaceName;

  const SyncPendingDeletion({required this.space, required this.spaceName});

  static const _spaceId = 'spaceId';
  static const _ownerUid = 'ownerUid';
  static const _spaceName = 'spaceName';

  Map<String, String> toJson() => {
    _spaceId: space.spaceId,
    _ownerUid: space.ownerUid,
    _spaceName: spaceName,
  };

  /// Null for an entry missing a field, dropped as a claim's is.
  static SyncPendingDeletion? fromJson(Object? json) {
    if (json is! Map) return null;
    final spaceId = json[_spaceId];
    final ownerUid = json[_ownerUid];
    final spaceName = json[_spaceName];
    if (spaceId is! String || ownerUid is! String || spaceName is! String) {
      return null;
    }
    return SyncPendingDeletion(
      space: SyncSpaceRef(ownerUid: ownerUid, spaceId: spaceId),
      spaceName: spaceName,
    );
  }

  @override
  List<Object?> get props => [space, spaceName];
}

/// Which database of this install holds which space (record §3.6): one
/// database ↔ one space, a space at most once per install — the databases of
/// one install share one `device_id`, and two writers with one node id in a
/// space break the clock.
///
/// Install-wide, so it lives in `SharedPreferences` (the QA build's prefix
/// applies there) rather than in the per-database `user_settings`, and it is
/// never in a backup. `SyncBindingService` claims on a bind and releases on
/// every unbind; `DatabaseManager` releases on a delete and follows a rename.
/// Beside the claims, under their own keys, it keeps the deletions this
/// install began and has not finished ([SyncPendingDeletion]) and the
/// account being deleted with them ([pendingAccountDeletion]).
class SyncSpaceRegistry {
  final SharedPreferences _prefs;
  final Future<bool> Function(String databaseName) _databaseExists;

  /// [databaseExists] tells a live holder from one whose file is gone — a
  /// database deleted outside the app, or by a build from before the
  /// registry — so a stale claim never keeps a space from being bound.
  SyncSpaceRegistry(
    this._prefs, {
    required Future<bool> Function(String databaseName) databaseExists,
  }) : _databaseExists = databaseExists;

  /// Every claim as stored, the stale ones included.
  List<SyncSpaceClaim> claims() {
    final raw = _prefs.getString(SettingsKeys.syncBoundSpaces);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final entry in decoded) ?SyncSpaceClaim.fromJson(entry)];
    } on FormatException catch (e, st) {
      debugPrint('[SyncSpaceRegistry] unreadable claims dropped: $e\n$st');
      return const [];
    }
  }

  /// The database of this install holding [space], other than [except] — the
  /// database asking, whose own claim is never in its way. Null when none
  /// does, or when the holder's file no longer exists.
  Future<String?> holderOf(SyncSpaceRef space, {String? except}) async {
    for (final claim in claims()) {
      if (claim.space != space || claim.databaseName == except) continue;
      if (await _databaseExists(claim.databaseName)) return claim.databaseName;
    }
    return null;
  }

  /// [databaseName] now holds [space]: whatever either held before is
  /// dropped, so neither can appear twice.
  Future<void> claim(SyncSpaceRef space, String databaseName) => _write([
    for (final claim in claims())
      if (claim.space != space && claim.databaseName != databaseName) claim,
    SyncSpaceClaim(space: space, databaseName: databaseName),
  ]);

  /// [databaseName] holds no space any more.
  Future<void> release(String databaseName) => _write([
    for (final claim in claims())
      if (claim.databaseName != databaseName) claim,
  ]);

  /// [from] was renamed to [to]: its claim follows it.
  Future<void> rename(String from, String to) => _write([
    for (final claim in claims())
      claim.databaseName == from
          ? SyncSpaceClaim(space: claim.space, databaseName: to)
          : claim,
  ]);

  /// Every deletion this install began and has not finished, in the order
  /// they began; an unreadable entry is dropped.
  List<SyncPendingDeletion> pendingDeletions() {
    final raw = _prefs.getString(SettingsKeys.syncPendingDeletions);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded) ?SyncPendingDeletion.fromJson(entry),
      ];
    } on FormatException catch (e, st) {
      debugPrint('[SyncSpaceRegistry] unreadable deletions dropped: $e\n$st');
      return const [];
    }
  }

  /// [deletion] began: recorded once per space. A space recorded already
  /// changes nothing — a second "Delete cloud copy" of a marked space
  /// records it again before its unbind (review F6), and keeps its place in
  /// the order the deletions began.
  Future<void> addPendingDeletion(SyncPendingDeletion deletion) async {
    final pending = pendingDeletions();
    if (pending.any((entry) => entry.space == deletion.space)) return;
    await _writeDeletions([...pending, deletion]);
  }

  /// The deletion of [space] finished, or its space is gone.
  Future<void> clearPendingDeletion(SyncSpaceRef space) => _writeDeletions([
    for (final pending in pendingDeletions())
      if (pending.space != space) pending,
  ]);

  /// The account whose own deletion was asked for on this install and has
  /// not finished (cloud-multi-user-roadmap §6.1), or null. Its cloud copies
  /// are among [pendingDeletions]; this is what says the account itself
  /// goes once they are gone.
  String? pendingAccountDeletion() {
    final uid = _prefs.getString(SettingsKeys.syncPendingAccountDeletion);
    return uid == null || uid.isEmpty ? null : uid;
  }

  /// [accountUid]'s deletion began; another account's record is replaced —
  /// one install deletes one account at a time, the one signed in.
  Future<void> setPendingAccountDeletion(String accountUid) =>
      _prefs.setString(SettingsKeys.syncPendingAccountDeletion, accountUid);

  /// [accountUid]'s deletion finished or was given up; another account's
  /// record is left alone.
  Future<void> clearPendingAccountDeletion(String accountUid) async {
    if (pendingAccountDeletion() != accountUid) return;
    await _prefs.remove(SettingsKeys.syncPendingAccountDeletion);
  }

  Future<void> _writeDeletions(List<SyncPendingDeletion> deletions) async {
    if (deletions.isEmpty) {
      await _prefs.remove(SettingsKeys.syncPendingDeletions);
      return;
    }
    await _prefs.setString(
      SettingsKeys.syncPendingDeletions,
      jsonEncode([for (final deletion in deletions) deletion.toJson()]),
    );
  }

  Future<void> _write(List<SyncSpaceClaim> claims) async {
    if (claims.isEmpty) {
      await _prefs.remove(SettingsKeys.syncBoundSpaces);
      return;
    }
    await _prefs.setString(
      SettingsKeys.syncBoundSpaces,
      jsonEncode([for (final claim in claims) claim.toJson()]),
    );
  }
}
