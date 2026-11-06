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

/// Which database of this install holds which space (record §3.6): one
/// database ↔ one space, a space at most once per install — the databases of
/// one install share one `device_id`, and two writers with one node id in a
/// space break the clock.
///
/// Install-wide, so it lives in `SharedPreferences` (the QA build's prefix
/// applies there) rather than in the per-database `user_settings`, and it is
/// never in a backup. `SyncBindingService` claims on a bind and releases on
/// every unbind; `DatabaseManager` releases on a delete and follows a rename.
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
