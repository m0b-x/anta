import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../database/database_lifecycle.dart';
import '../models/calendar_event.dart';
import '../repositories/note_repository.dart';
import '../utils/markdown_chunker.dart';
import '../utils/markdown_money_syntax.dart';
import 'settings_service.dart';

/// Derived in-memory cache of money-ledger summaries for calendar-linked
/// notes.
///
/// For every note linked from a calendar event this stores the folded
/// ledger balance, the net change contributed by arithmetic ops, and the
/// note title, so the calendar's day-bar / day-summary providers and the
/// month header can stay pure and synchronous. Nothing is persisted — the
/// cache is a pure function of note content, rebuilt by [refresh] and
/// invalidated per note by the [NoteRepository.noteChanges] stream.
class NoteMoneyLedgerService {
  static NoteMoneyLedgerService? _instance;

  final Map<String, ({int balance, int net, String title})> _ledgers = {};
  StreamSubscription<NoteChange>? _changeSub;

  String _symbol = '';
  bool _suffix = false;
  int _startCents = 0;

  NoteMoneyLedgerService._();

  static Future<NoteMoneyLedgerService> getInstance() async {
    if (_instance != null) return _instance!;
    final service = NoteMoneyLedgerService._();
    // A change to a cached note recomputes its entry in place (the
    // content is already in the repository cache when the event fires),
    // so the calendar's money surfaces self-heal without waiting for
    // the next full refresh; deletions drop the entry.
    service._changeSub = GetIt.I<NoteRepository>().noteChanges.listen(
      service._onNoteChange,
    );
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  static void reset() {
    _instance?._changeSub?.cancel();
    _instance = null;
  }

  /// Synchronous access for the pure day-bar / day-summary providers,
  /// which cannot await [getInstance] from build-time code.
  static NoteMoneyLedgerService? get instanceOrNull => _instance;

  /// Rebuilds the ledger summary for every note linked from [events].
  ///
  /// Reads the global money display config, folds each linked note's
  /// content exactly like the render passes (fence-delimiter lines toggle
  /// parity and are themselves inert, lines inside a fence are inert,
  /// oversized lines are skipped) and drops entries whose note is no
  /// longer linked. Per-note failures are logged and skipped so one
  /// broken note cannot hide the rest.
  Future<void> refresh(List<CalendarEvent> events) async {
    final config = await (await SettingsService.getInstance())
        .getMoneyConfig();
    _symbol = config.symbol;
    _suffix = config.suffix;
    _startCents = config.startCents;

    // Master toggle off: the calendar shows no money surfaces at all.
    if (!config.enabled) {
      _ledgers.clear();
      return;
    }

    final linked = <String>{
      for (final event in events)
        if (event.noteId != null) event.noteId!,
    };
    _ledgers.removeWhere((noteId, _) => !linked.contains(noteId));
    if (linked.isEmpty) return;

    final repository = GetIt.I<NoteRepository>();
    final notes = await repository.getNotesByIds(linked.toList());
    // Content loads run concurrently — a cold start with many linked
    // notes must not serialize N chunk reads.
    await Future.wait(
      notes.map((note) async {
        try {
          final content = await repository.loadContent(note.id);
          final folded = _fold(content);
          _ledgers[note.id] = (
            balance: folded.balance,
            net: folded.net,
            title: note.title,
          );
        } catch (e) {
          debugPrint(
            '[NoteMoneyLedgerService] Refresh error for ${note.id}: $e',
          );
        }
      }),
    );
  }

  /// Ledger summary for [noteId], or `null` when the note is not cached.
  /// Pure map read — safe to call per cell per rebuild.
  ({int balance, int net, String title})? ledgerFor(String noteId) =>
      _ledgers[noteId];

  /// Formats [cents] with an explicit sign using the stored display
  /// config (`+€12.50`, `-8.00 lei`).
  String formatNetSigned(int cents) =>
      MarkdownMoneySyntax.formatCentsSignedWithSymbol(
        cents,
        symbol: _symbol,
        suffix: _suffix,
      );

  /// Folds [content] into its final balance plus the net change over
  /// add/subtract/multiply/divide lines only — set/total/delta lines
  /// never contribute to `net`.
  ({int balance, int net}) _fold(String content) {
    // All fold rules (error-inertness, history appends) live in
    // [MoneyFold]; this fold only layers its op-only `net` on top.
    final fold = MoneyFold(_startCents);
    var net = 0;
    var inFence = false;
    for (final line in content.split('\n')) {
      if (MarkdownChunker.isFenceDelimiter(line)) {
        inFence = !inFence;
        continue;
      }
      if (inFence || line.length > MarkdownMoneySyntax.maxLineLength) {
        continue;
      }
      if (line.isEmpty || !MarkdownMoneySyntax.leadsWithMoney(line)) {
        continue;
      }
      final match = MarkdownMoneySyntax.parse(line);
      if (match == null) continue;
      final before = fold.balance;
      fold.step(match);
      switch (match.kind) {
        case MoneyLineKind.add:
        case MoneyLineKind.subtract:
        case MoneyLineKind.multiply:
        case MoneyLineKind.divide:
          net += fold.balance - before;
        case MoneyLineKind.set:
        case MoneyLineKind.total:
        case MoneyLineKind.delta:
        case MoneyLineKind.target:
        case MoneyLineKind.diff:
        case MoneyLineKind.span:
          break;
      }
    }
    return (balance: fold.balance, net: net);
  }

  void _onNoteChange(NoteChange change) {
    if (!_ledgers.containsKey(change.noteId)) return;
    if (change.type == NoteChangeType.deleted) {
      _ledgers.remove(change.noteId);
      return;
    }
    // Recompute in place rather than evict-and-forget: nothing re-runs
    // refresh() until the next calendar load, so an evicted entry would
    // silently vanish from day bars/summaries for the rest of the
    // session. The repository already has the fresh content cached when
    // this event fires, so the recompute is cheap; the stale value
    // stays visible until it lands (eventual consistency).
    unawaited(_recomputeNote(change.noteId));
  }

  Future<void> _recomputeNote(String noteId) async {
    try {
      final repository = GetIt.I<NoteRepository>();
      final notes = await repository.getNotesByIds([noteId]);
      if (notes.isEmpty) {
        _ledgers.remove(noteId);
        return;
      }
      final content = await repository.loadContent(noteId);
      final folded = _fold(content);
      _ledgers[noteId] = (
        balance: folded.balance,
        net: folded.net,
        title: notes.first.title,
      );
    } catch (e) {
      debugPrint('[NoteMoneyLedgerService] Recompute error for $noteId: $e');
    }
  }
}
