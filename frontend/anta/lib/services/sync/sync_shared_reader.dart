part of 'sync_engine.dart';

/// The reader's side of a share (`docs/cloud-sharing-foundations.md` §5,
/// §6): the rows the bound account's partner shares with it, read into the
/// same tables as the person's own under that partner's `owner_id`, kept
/// true to the owner's copy, and removed when they stop being shared.
///
/// A second, smaller pull, after a run's own pull and drain. Nothing here
/// may hurt that run: a failure of this read is logged and tried again
/// later, never a failure or a pause of the account's own sync — the rules
/// this depends on may not be deployed yet, a pair may end between two
/// calls. Only a halt goes through, since it ends the run itself.
class _SharedReader {
  _SharedReader(this._e);

  final SyncEngine _e;

  /// The bindings of the shareable tables, parents first.
  late final List<SyncTableBinding<Object>> _tables = [
    for (final table in sharedTables) ?_e._bindingFor(table),
  ];

  /// Reads what the partner of [bound]'s account shares with it — when
  /// there may be anything to read or to remove, and a read is due.
  ///
  /// An account that never paired, shares nothing and holds no shared row
  /// asks nothing: three local reads, no call. Otherwise the pair is asked
  /// of the server, and that answer drives three things:
  ///
  /// - **this account's own marks** follow it — every mark of a pair that
  ///   is not the account's is cleared (decision c), so a share never
  ///   outlives its pair on the owner's side either;
  /// - **the shared rows held** are removed, all of them, when there is no
  ///   pair any more or it is another one;
  /// - **each shareable table** is read from its cursor, and again from the
  ///   start, with what is no longer returned removed, when the server
  ///   counts fewer shared rows than this device holds — or once a day
  ///   whatever it counts.
  ///
  /// [asked]: the user asked for this run, which reads now whatever the
  /// interval says.
  Future<void> read(
    SyncBinding bound, {
    required bool asked,
    required _RunTally tally,
  }) async {
    final source = _e._partners;
    if (source == null || !_e._foreground) return;
    final db = _e._db;
    final uid = bound.accountUid;
    final holder = await db.sharedRowDao.owner();
    if (holder == null &&
        !await db.syncDao.anyShareMark() &&
        !await source.pairedLocally(uid)) {
      return;
    }
    if (!asked && !await _due(SyncDao.keySharedReadAt, _interval)) return;
    final touched = <SyncInvalidation>{};
    var stamps = true;
    try {
      final partner = await source.activePartner(uid);
      await _e._reached(tally);
      await _e._checkHalt(bound);
      await _keepMarks(partner, touched);
      if (holder != null &&
          (partner == null ||
              holder != partner.partnerUid ||
              await db.syncDao.getValue(SyncDao.keySharedPair) !=
                  partner.pairId)) {
        await _forget(touched);
      }
      if (partner == null) return;
      if (await db.sharedRowDao.owner() == null) {
        await db.sharedRowDao.begin(
          owner: partner.partnerUid,
          pair: partner.pairId,
          boundUid: uid,
        );
      }
      final whole =
          await _readsNewerWireNow() ||
          await _due(SyncDao.keySharedFullAt, SyncEngine.fullPullInterval);
      var complete = true;
      for (final table in _tables) {
        final read = await _readTable(
          bound,
          partner,
          table,
          whole: whole,
          touched: touched,
          tally: tally,
        );
        if (!read) {
          complete = false;
          break;
        }
      }
      if (whole && complete) {
        await db.syncDao.setValue(
          SyncDao.keySharedFullAt,
          '${_e._now().millisecondsSinceEpoch}',
        );
      }
    } on _Halted {
      stamps = false;
      rethrow;
    } on SyncGatewayException catch (error) {
      // Offline, the next run asks again; anything else waits the interval
      // out — rules not deployed yet answer the same every time.
      stamps = error.failure != SyncGatewayFailure.offline;
      debugPrint('[SyncEngine] shared rows not read: $error');
    } catch (error, stack) {
      _warn('reading shared rows failed: $error\n$stack');
    } finally {
      if (stamps) {
        await db.syncDao.setValue(
          SyncDao.keySharedReadAt,
          '${_e._now().millisecondsSinceEpoch}',
        );
      }
      await _e._puller.notifyRun(touched);
    }
  }

  /// How long a shared read is not repeated unasked: each one asks the
  /// server for the pair, a page and a count per shareable table.
  static const Duration _interval = SyncEngine.sharedReadInterval;

  /// Whether the time stored under [key] is at least [interval] old, or
  /// absent, or ahead of the clock.
  Future<bool> _due(String key, Duration interval) async {
    final at = int.tryParse(await _e._db.syncDao.getValue(key) ?? '');
    if (at == null) return true;
    final age = _e._now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age >= interval || age.isNegative;
  }

  /// Whether this build now reads the wire it once skipped documents of
  /// ([SyncDao.keySharedNewerWire]) — the app was updated since — in which
  /// case the mark is spent and every table is read again from the start:
  /// the cursor passed those documents, and nothing else brings them back.
  Future<bool> _readsNewerWireNow() async {
    final dao = _e._db.syncDao;
    final skipped = int.tryParse(
      await dao.getValue(SyncDao.keySharedNewerWire) ?? '',
    );
    if (skipped == null || skipped > _e._schema) return false;
    await dao.deleteValue(SyncDao.keySharedNewerWire);
    return true;
  }

  /// Clears this account's own marks of every pair but [partner]'s — all of
  /// them when it has none. Stamped writes, queued like any edit: the
  /// documents under them are sent again private by the next drain.
  Future<void> _keepMarks(
    SharePartner? partner,
    Set<SyncInvalidation> touched,
  ) async {
    final db = _e._db;
    if (!await db.syncDao.anyShareMark()) return;
    final cleared = await db.folderDao.clearSharesExcept(partner?.pairId);
    if (cleared == 0) return;
    touched
      ..add(SyncInvalidation.folders)
      ..add(SyncInvalidation.calendar);
  }

  /// Removes every shared row this database holds and tells the caches.
  Future<void> _forget(Set<SyncInvalidation> touched) async {
    final removed = await _e._db.sharedRowDao.removeAll();
    for (final MapEntry(key: table, value: keys) in removed.entries) {
      await _announceGone(table, keys, touched);
    }
  }

  /// Tells the caches of the rows of [table] under [keys] that were removed
  /// here, as a merged page's deletions are told.
  Future<void> _announceGone(
    String table,
    List<String> keys,
    Set<SyncInvalidation> touched,
  ) async {
    if (keys.isEmpty) return;
    final binding = _e._bindingFor(table);
    if (binding != null) touched.add(binding.invalidation);
    try {
      await _e._hooks.afterPage(table, [
        for (final key in keys)
          SyncAppliedRow(
            rowKey: key,
            result: MergeResult.applied,
            tombstone: true,
          ),
      ]);
    } catch (error, stack) {
      _warn('afterPage for the removed shared $table failed: $error\n$stack');
    }
  }

  /// Reads [table]'s shared rows; false when the app left the foreground
  /// before its end.
  ///
  /// From the cursor first. Then the server is asked how many rows are
  /// shared (decision f): fewer than this device holds means some left —
  /// a mark cleared, a row moved out, a cloud copy deleted — which no query
  /// can report, so the table is read again from the start and what is no
  /// longer returned is removed. [whole] reads it that way at once.
  ///
  /// A read from the start is exact for a row that stays shared: its
  /// document is at its old place in the order until a push of it commits
  /// and at a later one from then on, so a walk that had not reached the
  /// old place meets the new one.
  Future<bool> _readTable(
    SyncBinding bound,
    SharePartner partner,
    SyncTableBinding<Object> table, {
    required bool whole,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    final retryKey = SyncDao.keySharedRetry(name);
    var fromStart = whole || await db.syncDao.getValue(retryKey) != null;
    while (true) {
      final seen = fromStart ? <String>{} : null;
      final walk = await _readPages(
        bound,
        partner,
        table,
        seen: seen,
        touched: touched,
        tally: tally,
      );
      if (!walk.complete) return false;
      if (walk.waiting) {
        await db.syncDao.setValue(retryKey, '1');
      } else if (fromStart) {
        await db.syncDao.deleteValue(retryKey);
      }
      if (seen != null) {
        final gone = await db.sharedRowDao.removeAbsent(
          name,
          partner.partnerUid,
          seen,
        );
        await _announceGone(name, gone, touched);
        return true;
      }
      await _e._checkHalt(bound);
      final shared = await _e._gateway.sharedCount(
        name,
        pair: partner.pairId,
        owner: partner.partnerUid,
      );
      await _e._reached(tally);
      if (shared >= await db.sharedRowDao.countOf(name, partner.partnerUid)) {
        return true;
      }
      fromStart = true;
    }
  }

  /// Walks [table]'s shared rows page after page — from the start when
  /// [seen] is given, which collects the key of every document met, a
  /// skipped one included; else from the stored cursor, re-reading the
  /// gateway's overlap before it as a resumed pull does.
  ///
  /// `complete` is false when the app left the foreground before the end;
  /// `waiting` says a note's text could not be read yet, so the table is
  /// read from the start again next time rather than once a day.
  Future<({bool complete, bool waiting})> _readPages(
    SyncBinding bound,
    SharePartner partner,
    SyncTableBinding<Object> table, {
    required Set<String>? seen,
    required Set<SyncInvalidation> touched,
    required _RunTally tally,
  }) async {
    final db = _e._db;
    final name = table.table;
    final key = SyncDao.keySharedCursor(name);
    final stored = seen != null ? null : await db.syncDao.getValue(key);
    var cursor = stored == null ? null : SyncCursor(stored);
    var resumed = cursor != null;
    SyncCursor? scan;
    var waiting = false;
    while (true) {
      await _e._checkHalt(bound);
      if (!_e._foreground) return (complete: false, waiting: waiting);
      final page = await _e._gateway.sharedPage(
        name,
        pair: partner.pairId,
        owner: partner.partnerUid,
        after: cursor,
        limit: table.pullPageLimit,
        resumed: resumed,
        scan: scan,
      );
      await _e._reached(tally);
      tally.pages++;
      seen
        ?..addAll(page.envelopes.map((envelope) => envelope.rowKey))
        ..addAll(page.skipped);
      final next = page.next;
      final moved = next != null && next.value != cursor?.value;
      if (page.envelopes.isNotEmpty) {
        waiting |= await _apply(bound, partner, table, page, touched, tally);
      } else if (moved) {
        await db.transaction(() async {
          await _stillReading(bound, partner);
          await db.syncDao.setValue(key, next.value);
        });
      }
      final rested = !moved && page.scan?.value == scan?.value;
      cursor = next ?? cursor;
      scan = page.scan;
      resumed = scan != null;
      if (!page.hasMore || (page.envelopes.isEmpty && rested)) break;
    }
    return (complete: true, waiting: waiting);
  }

  /// Merges one page of [table]'s shared rows in one transaction with its
  /// cursor, and tells the caches; returns whether a note of it has to wait
  /// for its text.
  ///
  /// Three kinds of document are passed over, each on purpose:
  ///
  /// - one that is not [partner]'s, or names another pair — the query pins
  ///   both, so this is a gateway that answered wrongly, and nothing of
  ///   another account's is stored on its word;
  /// - one a newer wire wrote (decision h): the highest such wire is
  ///   remembered, the person told to update, and the tables read again
  ///   once this build reads it ([_readsNewerWireNow]);
  /// - one whose merge refuses it — it would take the place of a row of
  ///   this person's own ([SharedRowRefused]), or it is malformed.
  ///
  /// A page of notes is one transaction whatever its bodies weigh: what a
  /// partner shares is a folder, not a library, and the page is fifty notes
  /// at most.
  Future<bool> _apply(
    SyncBinding bound,
    SharePartner partner,
    SyncTableBinding<Object> table,
    SyncPullPage page,
    Set<SyncInvalidation> touched,
    _RunTally tally,
  ) async {
    final db = _e._db;
    final name = table.table;
    final envelopes = <SyncEnvelope>[];
    int? newer;
    for (final envelope in page.envelopes) {
      if (envelope.ownerId != partner.partnerUid ||
          envelope.sharedPair != partner.pairId) {
        _warn('a shared $name page held ${envelope.rowKey}, not shared so');
        continue;
      }
      final wire = envelope.wire;
      if (wire != null && wire > _e._schema) {
        if (newer == null || wire > newer) newer = wire;
        continue;
      }
      envelopes.add(envelope);
    }
    const floor = CrdtMerge.everyStamp;
    List<PreparedNoteBody?>? prepared;
    var fetched = const <String, String>{};
    Set<String>? asked;
    await _e._hooks.beforePage(name);
    await _e._checkHalt(bound);
    if (table is NotesBinding) {
      final missing = await NotesBinding.missingChunks(
        db,
        envelopes,
        floor: floor,
      );
      fetched = await _fetchChunks(
        bound,
        partner,
        envelopes,
        page.spaces,
        missing.toSet(),
        tally,
      );
      asked = missing.toSet();
      prepared = await table.readyBodies(
        db,
        envelopes,
        await table.prepareBodies(
          db,
          envelopes,
          floor: floor,
          fetched: fetched,
          asked: asked,
        ),
        floor: floor,
      );
    }
    final rows = <SyncAppliedRow>[];
    var changed = false;
    var waiting = false;
    await db.transaction(() async {
      await _stillReading(bound, partner);
      for (final (i, envelope) in envelopes.indexed) {
        final MergeOutcome outcome;
        try {
          outcome = await db.transaction(
            () => table is NotesBinding
                ? table.mergeRemote(
                    db,
                    envelope,
                    floor: floor,
                    fetched: fetched,
                    asked: asked,
                    prepared: prepared?[i],
                    shared: true,
                  )
                : table.mergeShared(db, envelope),
          );
        } on SyncGatewayException {
          rethrow;
        } on ChunkRowsMoved {
          rethrow;
        } catch (error) {
          if (_abortsTransaction(error)) rethrow;
          if (error is ChunksMissing) waiting = true;
          debugPrint(
            '[SyncEngine] shared $name/${envelope.rowKey} not stored: $error',
          );
          continue;
        }
        rows.add(
          SyncAppliedRow(
            rowKey: envelope.rowKey,
            result: outcome.result,
            tombstone: isTombstone(envelope),
            moved: outcome.moved,
            previousParent: outcome.previousParent,
            content: outcome.mergedContent,
          ),
        );
        if (outcome.result == MergeResult.inserted ||
            outcome.result == MergeResult.applied) {
          changed = true;
        }
      }
      if (table is FoldersBinding) {
        for (final id in await db.sharedRowDao.placeFolders(
          partner.partnerUid,
        )) {
          changed = true;
          rows.add(
            SyncAppliedRow(
              rowKey: id,
              result: MergeResult.applied,
              tombstone: false,
              moved: true,
            ),
          );
        }
      }
      final next = page.next;
      if (next != null) {
        await db.syncDao.setValue(SyncDao.keySharedCursor(name), next.value);
      }
      if (newer != null) {
        final dao = db.syncDao;
        final known = int.tryParse(
          await dao.getValue(SyncDao.keySharedNewerWire) ?? '',
        );
        if (known == null || newer > known) {
          await dao.setValue(SyncDao.keySharedNewerWire, '$newer');
        }
      }
    });
    if (changed) touched.add(table.invalidation);
    tally.pulled += rows.length;
    try {
      await _e._hooks.afterPage(name, List.unmodifiable(rows));
    } catch (error, stack) {
      _warn('afterPage for the shared $name failed: $error\n$stack');
    }
    return waiting;
  }

  /// First inside every transaction of this reader: the binding is the one
  /// the run began under, and the database still reads [partner]'s rows —
  /// an unbind, or a removal of everything shared, committing between the
  /// page's read and its merge must not have rows land after it.
  Future<void> _stillReading(SyncBinding bound, SharePartner partner) async {
    await _e._puller._checkStillBound(bound);
    final db = _e._db;
    if (await db.sharedRowDao.owner() != partner.partnerUid ||
        await db.syncDao.getValue(SyncDao.keySharedPair) != partner.pairId) {
      throw const _Halted(SyncRunSkip.rebound);
    }
  }

  /// Reads, from the spaces their notes lie in, the chunks among [missing]
  /// that the live manifests of [envelopes] name — each from the space of a
  /// note that names it, since a hash is a document of its own in every
  /// space ([SyncGateway.readSharedChunks]). A chunk that fails its hash is
  /// left out, and so is everything of a space that refuses the read — it
  /// does not name the pair, yet or any more: the notes naming those chunks
  /// then fail their merge as waiting for their text, and the rest of the
  /// page lands.
  Future<Map<String, String>> _fetchChunks(
    SyncBinding bound,
    SharePartner partner,
    List<SyncEnvelope> envelopes,
    Map<String, SyncSpaceRef> spaces,
    Set<String> missing,
    _RunTally tally,
  ) async {
    if (missing.isEmpty) return const {};
    final bySpace = <SyncSpaceRef, Set<String>>{};
    final placed = <String>{};
    for (final envelope in envelopes) {
      final space = spaces[envelope.rowKey];
      final named = dataOf(envelope)[NotesBinding.chunksKey];
      if (space == null || isTombstone(envelope) || named is! List) continue;
      for (final hash in named.whereType<String>()) {
        if (missing.contains(hash) && placed.add(hash)) {
          bySpace.putIfAbsent(space, () => {}).add(hash);
        }
      }
    }
    final fetched = <String, String>{};
    const batch = SyncGateway.rowReadBatch;
    for (final MapEntry(key: space, value: hashes) in bySpace.entries) {
      final keys = hashes.toList();
      for (var at = 0; at < keys.length; at += batch) {
        await _e._checkHalt(bound);
        final SyncPullPage page;
        try {
          page = await _e._gateway.readSharedChunks(
            space,
            keys.skip(at).take(batch).toList(),
            pair: partner.pairId,
          );
        } on SyncGatewayException catch (error) {
          if (error.failure != SyncGatewayFailure.permissionDenied) rethrow;
          debugPrint(
            '[SyncEngine] the text in ${space.spaceId} is not shared: $error',
          );
          break;
        }
        await _e._reached(tally);
        for (final envelope in page.envelopes) {
          try {
            fetched[envelope.rowKey] = ContentChunksBinding.textOf(envelope);
          } on FormatException catch (error) {
            debugPrint('[SyncEngine] chunk ${envelope.rowKey} refused: $error');
          }
        }
      }
    }
    return fetched;
  }
}
