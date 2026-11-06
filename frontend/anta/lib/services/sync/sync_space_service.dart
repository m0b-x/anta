import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../constants/app_version.dart';
import '../../database/crdt/synced_tables.dart';
import '../../database/database.dart';
import '../../database/migrations/database_schema.dart';
import '../database_manager.dart';
import 'sync_binding_service.dart';
import 'sync_gateway.dart';
import 'sync_space_registry.dart';
import 'sync_suspension.dart';

/// Why a bind, a download or a stop failed, in the terms the Sharing page
/// words.
enum SyncBindFailure {
  /// No connection reached the cloud.
  offline,

  /// The account's daily quota ran out.
  quotaExhausted,

  /// The cloud refused the call: the rules are not deployed, or the space is
  /// another account's.
  permissionDenied,

  /// A restore or import is rewriting this database right now.
  suspended,

  /// This database syncs already: stop syncing first.
  alreadyBound,

  /// Another database of this install syncs with the chosen space —
  /// [SyncSpaceException.holderDatabase] names it.
  spaceHeldByAnotherDatabase,

  /// A space name empty after trimming, or over
  /// [SyncSpaceService.maxSpaceNameLength] code points.
  invalidSpaceName,

  /// The new database a download needs could not be created or opened; the
  /// user is still on the database they started from.
  newDatabaseFailed,

  unknown,
}

class SyncSpaceException implements Exception {
  final SyncBindFailure failure;

  /// For [SyncBindFailure.spaceHeldByAnotherDatabase]: the database that
  /// holds the space, as the Databases page lists it.
  final String? holderDatabase;

  const SyncSpaceException(this.failure, {this.holderDatabase});

  @override
  String toString() =>
      'SyncSpaceException(${failure.name}'
      '${holderDatabase == null ? '' : ': $holderDatabase'})';
}

/// What a "Sync this database" tap led to (record §2 D1, D2).
sealed class SyncBindStart extends Equatable {
  const SyncBindStart();
}

/// Bound in the tap: the account's first space created, or the one space
/// bound by a database that holds nothing.
final class SyncBindStartBound extends SyncBindStart {
  final SyncSpaceRef space;

  const SyncBindStartBound(this.space);

  @override
  List<Object?> get props => [space];
}

/// The picker's data: the account's spaces, most recently written first.
final class SyncBindStartPick extends SyncBindStart {
  final List<SyncSpaceInfo> spaces;

  /// Whether this database holds anything a person made — the picker leads
  /// with "Merge this database into the space" then.
  final bool holdsData;

  /// The spaces another database of this install holds, with its name:
  /// binding one is refused, so the picker can say so before the tap.
  final Map<SyncSpaceRef, String> heldBy;

  const SyncBindStartPick({
    required this.spaces,
    required this.holdsData,
    this.heldBy = const {},
  });

  @override
  List<Object?> get props => [spaces, holdsData, heldBy];
}

/// The bind flow below the Sharing page (record §3.6): the account's spaces,
/// creating one, binding this database or a new one to one, and stopping.
///
/// Holds nothing per database: the database, its binding service and the
/// database manager are resolved on every call, so a download's switch — or
/// any other — never leaves it speaking to a closed database. Only the
/// gateway is kept, global like the identity.
class SyncSpaceService {
  /// The rules' cap on a space name, in code points (record §3.3).
  static const int maxSpaceNameLength = 100;

  final SyncGateway _gateway;
  final Future<AppDatabase> Function() _database;
  final Future<SyncBindingService> Function() _binding;
  final Future<DatabaseManager> Function() _databases;

  SyncSpaceService({
    required SyncGateway gateway,
    Future<AppDatabase> Function() database = AppDatabase.getInstance,
    Future<SyncBindingService> Function() binding =
        SyncBindingService.getInstance,
    Future<DatabaseManager> Function() databases = DatabaseManager.getInstance,
  }) : _gateway = gateway,
       _database = database,
       _binding = binding,
       _databases = databases;

  /// The "Sync this database" tap (D1, D2): no space yet → the account's
  /// first space, named after this database (the default one after the
  /// app), created and bound; this
  /// database holding nothing and exactly one space that no other database
  /// here holds → that space bound; otherwise the picker's data.
  Future<SyncBindStart> start({required String accountUid}) =>
      _mapped(() async {
        await _ensureBindable();
        final spaces = await listSpaces(accountUid);
        if (spaces.isEmpty) {
          final created = await _createAndBind(
            accountUid: accountUid,
            name: await _defaultSpaceName(),
          );
          return SyncBindStartBound(created.ref);
        }
        final holdsData = await databaseHoldsData();
        final heldBy = await _heldBy(spaces);
        if (!holdsData && spaces.length == 1 && heldBy.isEmpty) {
          await _bind(spaces.single.ref, accountUid: accountUid);
          return SyncBindStartBound(spaces.single.ref);
        }
        return SyncBindStartPick(
          spaces: spaces,
          holdsData: holdsData,
          heldBy: heldBy,
        );
      });

  /// The account's spaces, the most recently written first; a space never
  /// written to sorts after every written one, the newest created first.
  Future<List<SyncSpaceInfo>> listSpaces(String accountUid) => _mapped(
    () async {
      final spaces = [...await _gateway.listSpaces(accountUid)];
      int newestFirst(DateTime? a, DateTime? b) {
        if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
        return b.compareTo(a);
      }

      spaces.sort((a, b) {
        final written = newestFirst(a.lastWriteAt, b.lastWriteAt);
        if (written != 0) return written;
        return newestFirst(a.createdAt, b.createdAt);
      });
      return spaces;
    },
  );

  /// Whether this database holds anything a person made (D2: one that holds
  /// nothing skips the picker): a live row in any table that syncs. Not
  /// counted: `content_chunks`, which only exist inside a note, and the
  /// built-in calendar categories, which every database seeds on open —
  /// edited or not, since a bind settles them against the space's under the
  /// floor either way. Tombstones are not counted: they hold nothing to keep.
  Future<bool> databaseHoldsData() async {
    final db = await _database();
    final probes = [
      for (final synced in syncedTables)
        if (!synced.travelsWithParent)
          'EXISTS (SELECT 1 FROM ${synced.name} WHERE is_deleted = 0'
              '${synced.name == 'calendar_categories' ? ' AND is_built_in = 0' : ''})',
    ];
    final row = await db
        .customSelect('SELECT (${probes.join(' OR ')}) AS held')
        .getSingle();
    return row.read<bool>('held');
  }

  /// "Upload as a new space": created under [name], trimmed — this
  /// database's name when null, the app's for the default database — then
  /// this database bound to it. A name outside 1..[maxSpaceNameLength] code
  /// points is refused before the gateway.
  Future<SyncSpaceInfo> createAndBind({
    required String accountUid,
    String? name,
  }) => _mapped(() async {
    await _ensureBindable();
    return _createAndBind(
      accountUid: accountUid,
      name: name ?? await _defaultSpaceName(),
    );
  });

  /// The name a space this database creates takes unless one is given: the
  /// database's, as the Databases page lists it — but the app's for the
  /// owner's default database, whose `gym_notes` is a file name kept from the
  /// app's first life, and spaces cannot be renamed yet (review BA-L2,
  /// record §8). A QA build's own default keeps its name.
  Future<String> _defaultSpaceName() async {
    final name = (await _databases()).getActiveDatabaseName();
    return name == DatabaseManager.defaultDatabaseName(qaEnabled: false)
        ? kAppName
        : name;
  }

  /// "Merge this database into the space": this database bound to [space],
  /// its rows settled against the space's under the floor (D15).
  Future<void> bindExisting(SyncSpaceRef space, {required String accountUid}) =>
      _mapped(() async {
        await _ensureBindable();
        await _bind(space, accountUid: accountUid);
      });

  /// "Download the space into a new database": a new database named after
  /// [space], made active — the open database switches in place — and bound
  /// with nothing local to merge, so the pull fills it. Returns its name.
  ///
  /// The name is the space's through [DatabaseManager.suggestDatabaseName],
  /// the rule a database import already follows: every character outside
  /// `[a-zA-Z0-9_-]` becomes `_`, at most 50 characters, `_1`, `_2`, … until
  /// no file has it. A failure after the create switches back to the
  /// database the user started from and deletes the new file, which holds
  /// nothing but the schema.
  ///
  /// The space is read first, so offline or a space gone from the cloud is
  /// refused before anything here changes (review BA-M3). From the switch to
  /// the bind, [DatabaseManager.markDownloadInFlight] lets a launch after a
  /// kill switch back (BA-M2). The database the user started from keeps its
  /// own binding and claim.
  Future<String> downloadIntoNewDatabase(
    SyncSpaceInfo space, {
    required String accountUid,
  }) => _mapped(() async {
    if (SyncSuspension.isSuspended) {
      throw const SyncSpaceException(SyncBindFailure.suspended);
    }
    await _ensureNotHeld(space.ref);
    if (await _gateway.readSpace(space.ref) == null) {
      throw const SyncSpaceException(SyncBindFailure.permissionDenied);
    }
    final databases = await _databases();
    final previous = databases.getActiveDatabaseName();
    // Past the holder check, a claim on the space by the database left is
    // stale — it does not sync the space — and would stop the new database's
    // own bind: dropped, as a Merge's claim would replace it.
    final registry = databases.spaceRegistry;
    final stale = SyncSpaceClaim(space: space.ref, databaseName: previous);
    if (registry.claims().contains(stale)) await registry.release(previous);
    final String name;
    try {
      name = await databases.suggestDatabaseName(space.name);
      await databases.createDatabase(name);
    } catch (e, st) {
      debugPrint('[SyncSpaceService] new database not created: $e\n$st');
      throw const SyncSpaceException(SyncBindFailure.newDatabaseFailed);
    }
    try {
      await databases.markDownloadInFlight(from: previous, to: name);
      await databases.setActiveDatabaseName(name);
      await _database();
    } catch (e, st) {
      debugPrint('[SyncSpaceService] new database not opened: $e\n$st');
      await _returnTo(previous, leaving: name);
      throw const SyncSpaceException(SyncBindFailure.newDatabaseFailed);
    }
    try {
      await (await _binding()).bind(space: space.ref, accountUid: accountUid);
    } catch (_) {
      await _returnTo(previous, leaving: name);
      rethrow;
    }
    try {
      await databases.clearDownloadInFlight();
    } catch (e, st) {
      // Bound already: a marker left behind only lands the next launch on
      // the database the user started from.
      debugPrint('[SyncSpaceService] download marker not cleared: $e\n$st');
    }
    return name;
  });

  /// "Stop syncing this database" (D6 A): unbound, the claim released by the
  /// unbind; the space stays. Allowed whatever the account — signed out or
  /// another account's is D5's way out. Unbound already, it writes nothing:
  /// an unbind would raise the floor a restore or the last unbind wrote, and
  /// the space would win edits made since (D15).
  Future<void> stopSyncing() => _mapped(() async {
    final binding = await _binding();
    if (await binding.read() == null) return;
    await binding.unbind();
  });

  Future<SyncSpaceInfo> _createAndBind({
    required String accountUid,
    required String name,
  }) async {
    final trimmed = name.trim();
    final size = trimmed.runes.length;
    if (size == 0 || size > maxSpaceNameLength) {
      throw const SyncSpaceException(SyncBindFailure.invalidSpaceName);
    }
    final db = await _database();
    final created = await _gateway.createSpace(
      ownerUid: accountUid,
      name: trimmed,
      deviceId: db.deviceId,
      schema: DatabaseSchema.currentVersion,
    );
    await _bind(created.ref, accountUid: accountUid);
    return created;
  }

  Future<void> _bind(SyncSpaceRef space, {required String accountUid}) async {
    await _ensureNotHeld(space);
    await (await _binding()).bind(space: space, accountUid: accountUid);
  }

  /// The refusals [SyncBindingService.bind] makes again inside its
  /// transaction, made first so a space is never created for a bind that
  /// cannot happen.
  Future<void> _ensureBindable() async {
    if (SyncSuspension.isSuspended) {
      throw const SyncSpaceException(SyncBindFailure.suspended);
    }
    if (await (await _binding()).read() != null) {
      throw const SyncSpaceException(SyncBindFailure.alreadyBound);
    }
  }

  Future<void> _ensureNotHeld(SyncSpaceRef space) async {
    final holder = await _holderOf(space);
    if (holder != null) {
      throw SyncSpaceException(
        SyncBindFailure.spaceHeldByAnotherDatabase,
        holderDatabase: holder,
      );
    }
  }

  Future<Map<SyncSpaceRef, String>> _heldBy(List<SyncSpaceInfo> spaces) async {
    final heldBy = <SyncSpaceRef, String>{};
    for (final space in spaces) {
      final holder = await _holderOf(space.ref);
      if (holder != null) heldBy[space.ref] = holder;
    }
    return heldBy;
  }

  /// The database of this install that holds [space], by one rule for the
  /// picker, Merge and Download (review BA-L1): another database's live
  /// claim, or the active database itself when its binding is to [space]. Its
  /// claim alone is never in the way — unbound, that claim is stale, a
  /// release that failed.
  Future<String?> _holderOf(SyncSpaceRef space) async {
    final databases = await _databases();
    final self = databases.getActiveDatabaseName();
    final other = await databases.spaceRegistry.holderOf(space, except: self);
    if (other != null) return other;
    final bound = await (await _binding()).read();
    final syncsIt =
        bound != null &&
        bound.spaceId == space.spaceId &&
        bound.ownerUid == space.ownerUid;
    return syncsIt ? self : null;
  }

  /// Back to [previous], then [leaving] deleted — only once the switch back
  /// has landed, so the open database is never the one deleted. Logged, not
  /// thrown: the caller reports the failure that brought it here.
  Future<void> _returnTo(String previous, {required String leaving}) async {
    try {
      final databases = await _databases();
      await databases.setActiveDatabaseName(previous);
      await databases.clearDownloadInFlight();
      await _database();
      await databases.deleteDatabase(leaving);
    } catch (e, st) {
      debugPrint('[SyncSpaceService] returning to "$previous" failed: $e\n$st');
    }
  }

  /// Every failure as a [SyncSpaceException]: the gateway's and the binding's
  /// typed ones mapped, anything else [SyncBindFailure.unknown].
  Future<T> _mapped<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on SyncSpaceException {
      rethrow;
    } on SyncBindRefusal catch (e) {
      throw SyncSpaceException(switch (e.reason) {
        SyncBindRefusalReason.suspended => SyncBindFailure.suspended,
        SyncBindRefusalReason.alreadyBound => SyncBindFailure.alreadyBound,
        SyncBindRefusalReason.spaceHeldByAnotherDatabase =>
          SyncBindFailure.spaceHeldByAnotherDatabase,
      }, holderDatabase: e.holderDatabase);
    } on SyncGatewayException catch (e) {
      throw SyncSpaceException(switch (e.failure) {
        SyncGatewayFailure.offline => SyncBindFailure.offline,
        SyncGatewayFailure.quotaExhausted => SyncBindFailure.quotaExhausted,
        SyncGatewayFailure.permissionDenied => SyncBindFailure.permissionDenied,
        SyncGatewayFailure.invalidData ||
        SyncGatewayFailure.unknown => SyncBindFailure.unknown,
      });
    } catch (e, st) {
      debugPrint('[SyncSpaceService] failed: $e\n$st');
      throw const SyncSpaceException(SyncBindFailure.unknown);
    }
  }
}
