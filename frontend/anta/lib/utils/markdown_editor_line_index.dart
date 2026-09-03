import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:re_editor/re_editor.dart';

import 'markdown_chunker.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';

/// Positional role of a line relative to ``` code fences. Delimiter and
/// interior lines style differently in the editor, and both bypass its
/// text-keyed span memo because the role depends on position, not
/// content. Grammar comes from [MarkdownChunker.isFenceDelimiter] — the
/// same predicate the preview's block scan uses.
enum MarkdownFenceRole { none, delimiter, interior }

/// Incremental positional index over the editor's [CodeLines]: per-line
/// fence roles, the set of task lines whose unchecked box renders
/// indeterminate (subtree partially complete), and the money ledger's
/// per-row display values.
///
/// Replaces the independent O(total lines) rebuilds the span builder ran
/// on every text mutation. The index exploits the fork's structural
/// sharing: `CodeLines.from` and `CodeLines.sublines` clone untouched
/// segments through `cloneShallowDirty()`, which shares each segment's
/// backing `codeLines` list by reference, so per-segment backing-list
/// identity is a precise dirty flag.
///
/// One `_SegmentState` per segment holds the scan state at the **entry**
/// of that segment. An update matches the incoming segment list against
/// the stored one by backing-list identity, which splits it into an
/// identical prefix `[0, p)`, an identical suffix, and a changed middle.
/// The middle's states are spliced out with `replaceRange`, everything
/// line-numbered below the middle is renumbered by the change in line
/// count, and the three passes re-scan from `p` resuming from the
/// retained entry state of segment `p`. A keystroke, an Enter, a line
/// delete and a paste therefore all take the same path — only the
/// replaced segments are rescanned — instead of the structural edits
/// falling back to a whole-document rebuild.
///
/// Each pass then stops at the first **seam** it can prove: an unchanged
/// segment whose stored entry state equals the state the rescan carries
/// into it resolves every line below it exactly as before, so the old
/// results for those lines are appended back verbatim, shifted by the
/// change in result count above them. The three entry states differ:
///
///   * fence pass — one bit, the in-fence parity;
///   * task pass — the open task-frame stack (line, level, checked and
///     the two descendant counters). The result *count* is deliberately
///     not part of the proof: toggling one child changes the count for
///     every segment below it, so a count-inclusive proof would never
///     fire on the commonest edit. The count is reconciled with a shift
///     instead. The lookup set is spliced alongside the result list —
///     only the rescanned region's lines are removed and re-added, so a
///     keystroke never pays for the whole document's results;
///   * money pass — [MoneyFold]'s whole state: the balance, period
///     start, target cents and target anchor scalars *plus* the two
///     append-only histories. Equal scalars alone are not sufficient —
///     `$^ N` reads back through the entry-balance history and `$~ N`
///     through the checkpoint history, so a rewritten history that lands
///     on the same balance with the same lengths still changes rows
///     below. The proof compares the regenerated history slices
///     element-wise against the ones they replaced. That comparison needs
///     the old tail of both histories kept aside for the whole pass, so
///     the money pass carries a cost bounded by the ledger's *entry
///     count below the caret* — not by line count, and not by the number
///     of segments rescanned. A shorter stash is not possible: a seam can
///     fail its proof on `periodStart` alone while the histories still
///     match and then succeed several segments later, so the old tail
///     still needed can grow as the scan proceeds.
///
/// Only a change with no identical prefix *and* no identical suffix (the
/// document was replaced wholesale, or this is the first build) rebuilds
/// everything. That is the same splice with `p = 0` and a synthetic
/// document-start entry state, over state that has been reset first: the
/// per-line fence array back to `null`, the result and money lists
/// emptied, and both money histories re-seeded with the configured start
/// balance. All paths assume the fork's contract that a published
/// [CodeLines] is never mutated in place — the same assumption the old
/// per-instance caches relied on. `_ensure` drops its `_lines` handle
/// before it starts, so an update that throws part-way leaves the index
/// looking un-built and the next call rebuilds rather than splicing onto
/// half-scanned state.
class MarkdownEditorLineIndex {
  /// Lines longer than this never participate in the **task** pass,
  /// mirroring the span builder's raw-render guard —
  /// [MarkdownListSyntax.scanListShape] has no length bound of its own.
  /// The money pass deliberately does not use it: it bounds itself on
  /// [MarkdownMoneySyntax.maxLineLength], the grammar's own limit and
  /// the one [MarkdownMoneySyntax.parse] enforces, so there is a single
  /// source of truth for how long a money line may be. (The two happen
  /// to be the same 4096 today, and a test pins that.)
  final int maxScannedLineLength;

  MarkdownEditorLineIndex({required this.maxScannedLineLength});

  CodeLines? _lines;
  int _lineCount = 0;
  final List<_SegmentState> _states = <_SegmentState>[];
  List<int> _segStarts = const [];

  /// Per-line fence roles; `null` means no fence anywhere (the common
  /// gym-note case pays no per-line storage). Growable, because a
  /// structural edit splices its middle range.
  List<MarkdownFenceRole>? _fence;

  final List<int> _resultOrder = <int>[];
  final Set<int> _indeterminate = <int>{};

  /// Set while the splice renumbered [_resultOrder] by a line delta. The
  /// renumbered list can hold a transient duplicate — a shifted suffix
  /// result landing on a stale middle result that the task pass has not
  /// replaced yet — so removal by value is unsafe and [_indeterminate]
  /// is rebuilt wholesale once the pass is done. Only structural edits
  /// pay it; a keystroke keeps the set incremental.
  bool _resultsRenumbered = false;

  /// Money pass results: sorted line indices of money lines and the
  /// display value (cents) for each — the running balance after the
  /// line, except `$?` delta lines (net change since the last `$=`),
  /// bare `$!` status lines (remaining budget vs the active target, or
  /// the no-target sentinel), `$^ N` diff lines (move across the last N
  /// balance-changing entries), and `$~ N` span lines (move across the
  /// last N `$=` checkpoints). The entry-balance history is an
  /// append-only result list (seeded with the start balance, one value
  /// per `$=`/`$+`/`$-`/`$*`/`$/`) and the checkpoint-balance history a
  /// parallel one (seeded the same, one value per `$=`), so per-segment
  /// resume state is their lengths plus the current period-start index —
  /// truncate and re-append, exactly like the task pass. The target is a
  /// scalar, not a history: its resume state is the active target cents
  /// (-1 while none is declared — amounts are unsigned, so -1 is
  /// unreachable) and the balance at its declaration.
  final List<int> _moneyLines = <int>[];
  final List<int> _moneyValues = <int>[];
  final List<int> _entryBalances = <int>[];
  final List<int> _anchorBalances = <int>[];
  bool _moneyEnabled = false;
  int _moneyStartCents = 0;

  final List<int> _taskScratch = <int>[];
  final List<int> _moneyLineScratch = <int>[];
  final List<int> _moneyValueScratch = <int>[];
  final List<int> _entryStash = <int>[];
  final List<int> _anchorStash = <int>[];

  bool _lastRebuilt = false;
  int _lastFenceScans = 0;
  int _lastTaskScans = 0;
  int _lastMoneyScans = 0;

  /// What the most recent index update did: whether it fell back to a
  /// full rebuild, and how many segments each pass actually scanned (0
  /// when the pass did not run). Handed the very same [CodeLines]
  /// instance again the index does nothing at all and this is left
  /// untouched; a fresh wrapper over identical backing lists (an undo to
  /// identical content) *is* an update, and reports all zeros.
  @visibleForTesting
  ({bool rebuilt, int fence, int tasks, int money}) get debugLastScan => (
    rebuilt: _lastRebuilt,
    fence: _lastFenceScans,
    tasks: _lastTaskScans,
    money: _lastMoneyScans,
  );

  /// Applies the money feature's enabled flag and global start balance.
  /// When disabled the money pass is skipped entirely (the results are
  /// empty and [moneyValueAt] always returns null), so the index does
  /// exactly the work it did before the feature existed. A change
  /// invalidates the whole index (cheap, rare — a settings change), so
  /// the next access rebuilds all passes.
  void configureMoney({required bool enabled, required int startCents}) {
    if (enabled == _moneyEnabled && startCents == _moneyStartCents) return;
    _moneyEnabled = enabled;
    _moneyStartCents = startCents;
    _lines = null;
  }

  MarkdownFenceRole fenceRoleAt(CodeLines lines, int index) {
    _ensure(lines);
    final fence = _fence;
    if (fence == null || index < 0 || index >= fence.length) {
      return MarkdownFenceRole.none;
    }
    return fence[index];
  }

  bool taskIndeterminate(CodeLines lines, int index) {
    _ensure(lines);
    return _indeterminate.contains(index);
  }

  /// Every line the task pass reports as indeterminate for [lines].
  /// Mirrors [_resultOrder] as a set and is maintained incrementally, so
  /// a test can compare it wholesale against a freshly built index —
  /// including entries the per-line accessors would never ask about.
  @visibleForTesting
  Set<int> debugIndeterminate(CodeLines lines) {
    _ensure(lines);
    return Set<int>.unmodifiable(_indeterminate);
  }

  /// The display value (cents) for the money line at [index], or `null`
  /// when the line is not a money line: the running balance after the
  /// line, for `$?` delta lines the net change since the last `$=`, for
  /// bare `$!` status lines the remaining budget vs the active target
  /// (the no-target sentinel with none declared), for `$^ N` diff lines
  /// the move across the last N entries, for `$~ N` span lines the move
  /// across the last N `$=` checkpoints. Grammar and arithmetic come
  /// from [MarkdownMoneySyntax], shared with the preview.
  int? moneyValueAt(CodeLines lines, int index) {
    _ensure(lines);
    var low = 0;
    var high = _moneyLines.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final line = _moneyLines[mid];
      if (line < index) {
        low = mid + 1;
      } else if (line > index) {
        high = mid - 1;
      } else {
        return _moneyValues[mid];
      }
    }
    return null;
  }

  void _ensure(CodeLines lines) {
    if (identical(lines, _lines)) return;
    // Dropped up front, restored only on a successful exit: a pass that
    // throws part-way must not leave `_lines` pointing at a document the
    // half-updated state no longer describes.
    final bool hadState = _lines != null;
    _lines = null;
    _lastRebuilt = false;
    _lastFenceScans = 0;
    _lastTaskScans = 0;
    _lastMoneyScans = 0;

    final List<CodeLineSegment> segs = lines.segments;
    final int n = segs.length;
    final int m = _states.length;

    if (!hadState) {
      _rebuildAll(lines, segs);
      _lines = lines;
      return;
    }

    final int maxCommon = m < n ? m : n;
    int p = 0;
    while (p < maxCommon && identical(segs[p].codeLines, _states[p].backing)) {
      p++;
    }
    if (p == m && m == n) {
      _lines = lines;
      return;
    }
    int q = 0;
    while (q < maxCommon - p &&
        identical(segs[n - 1 - q].codeLines, _states[m - 1 - q].backing)) {
      q++;
    }
    if (p + q == 0) {
      _rebuildAll(lines, segs);
      _lines = lines;
      return;
    }
    if (p >= m) {
      p = m - 1;
    }

    final int oldMiddleEnd = m - q;
    final int newMiddleEnd = n - q;
    final int newMiddleCount = newMiddleEnd - p;
    final int a = _segStarts[p];
    int oldMiddleLines = 0;
    for (int s = p; s < oldMiddleEnd; s++) {
      oldMiddleLines += _states[s].backing.length;
    }
    final int b = a + oldMiddleLines;
    int newMiddleLines = 0;
    for (int s = p; s < newMiddleEnd; s++) {
      newMiddleLines += segs[s].codeLines.length;
    }
    final int delta = newMiddleLines - oldMiddleLines;
    final _SegmentState entry = _states[p];

    _lineCount = lines.length;
    _states.replaceRange(p, oldMiddleEnd, [
      for (int s = p; s < newMiddleEnd; s++)
        _SegmentState(segs[s].codeLines, _moneyStartCents),
    ]);
    _segStarts = _startsOf(segs);

    _resultsRenumbered = delta != 0;
    if (delta != 0) {
      final List<MarkdownFenceRole>? fence = _fence;
      if (fence != null) {
        fence.replaceRange(
          a,
          b,
          List<MarkdownFenceRole>.filled(
            newMiddleLines,
            MarkdownFenceRole.none,
          ),
        );
      }
      for (int i = 0; i < _resultOrder.length; i++) {
        if (_resultOrder[i] >= b) _resultOrder[i] += delta;
      }
      for (int i = _moneyLines.length - 1; i >= 0; i--) {
        if (_moneyLines[i] < b) break;
        _moneyLines[i] += delta;
      }
      for (int t = p + newMiddleCount; t < n; t++) {
        final _SegmentState st = _states[t];
        final List<_TaskSnapshot> snaps = st.taskEntry;
        if (snaps.isEmpty) continue;
        st.taskEntry = List<_TaskSnapshot>.generate(snaps.length, (i) {
          final _TaskSnapshot snap = snaps[i];
          if (snap.line >= b) return snap.shifted(delta);
          if (snap.line >= a) return snap.orphaned();
          return snap;
        }, growable: false);
      }
    }

    final int last = p + newMiddleCount - 1;
    final int settled = _scanFence(segs, p, last, entry);
    _scanTasks(segs, p, last, settled, entry);
    if (_moneyEnabled) _scanMoney(segs, p, last, settled, entry);
    if (_resultsRenumbered) {
      _indeterminate
        ..clear()
        ..addAll(_resultOrder);
      assert(
        _indeterminate.length == _resultOrder.length,
        'a line may hold at most one indeterminate result',
      );
    }
    _lines = lines;
  }

  List<int> _startsOf(List<CodeLineSegment> segs) {
    final starts = List<int>.filled(segs.length, 0);
    int start = 0;
    for (int s = 0; s < segs.length; s++) {
      starts[s] = start;
      start += segs[s].codeLines.length;
    }
    return starts;
  }

  void _rebuildAll(CodeLines lines, List<CodeLineSegment> segs) {
    _lastRebuilt = true;
    _lineCount = lines.length;
    _segStarts = _startsOf(segs);
    _fence = null;
    _resultsRenumbered = false;
    _resultOrder.clear();
    _indeterminate.clear();
    _moneyLines.clear();
    _moneyValues.clear();
    _entryBalances
      ..clear()
      ..add(_moneyStartCents);
    _anchorBalances
      ..clear()
      ..add(_moneyStartCents);
    _states
      ..clear()
      ..addAll([
        for (final CodeLineSegment seg in segs)
          _SegmentState(seg.codeLines, _moneyStartCents),
      ]);
    final _SegmentState entry = _SegmentState(const [], _moneyStartCents);
    final int last = segs.length - 1;
    final int settled = _scanFence(segs, 0, last, entry);
    _scanTasks(segs, 0, last, settled, entry);
    if (_moneyEnabled) _scanMoney(segs, 0, last, settled, entry);
  }

  /// Returns the first segment index whose fence roles this pass left
  /// untouched — every segment from there on keeps the roles it already
  /// had. The task and money passes need it: their own seam proofs say
  /// nothing about fence roles, and a fence that opened above turns
  /// every task and money row below it inert.
  int _scanFence(
    List<CodeLineSegment> segs,
    int first,
    int last,
    _SegmentState entry,
  ) {
    final int n = segs.length;
    bool inFence = entry.fenceEntry;
    for (int s = first; s < n; s++) {
      final _SegmentState st = _states[s];
      if (s > last &&
          identical(segs[s].codeLines, st.backing) &&
          st.fenceEntry == inFence) {
        return s;
      }
      st.fenceEntry = inFence;
      _lastFenceScans++;
      final List<CodeLine> lines = segs[s].codeLines;
      int g = _segStarts[s];
      List<MarkdownFenceRole>? fence = _fence;
      for (int j = 0; j < lines.length; j++, g++) {
        if (MarkdownChunker.isFenceDelimiter(lines[j].text)) {
          fence ??= _fence = List<MarkdownFenceRole>.filled(
            _lineCount,
            MarkdownFenceRole.none,
            growable: true,
          );
          fence[g] = MarkdownFenceRole.delimiter;
          inFence = !inFence;
        } else if (fence != null) {
          fence[g] = inFence
              ? MarkdownFenceRole.interior
              : MarkdownFenceRole.none;
        }
      }
    }
    return n;
  }

  void _scanTasks(
    List<CodeLineSegment> segs,
    int first,
    int last,
    int settled,
    _SegmentState entry,
  ) {
    final int n = segs.length;
    final int keep = entry.resultCount;
    _taskScratch.clear();
    final frames = <_TaskFrame>[];
    for (final _TaskSnapshot snap in entry.taskEntry) {
      frames.add(
        _TaskFrame(line: snap.line, level: snap.level, checked: snap.checked)
          ..checkedDescendants = snap.checkedDescendants
          ..totalDescendants = snap.totalDescendants,
      );
    }
    final List<MarkdownFenceRole>? fence = _fence;
    for (int s = first; s < n; s++) {
      final _SegmentState st = _states[s];
      if (s > last &&
          s >= settled &&
          identical(segs[s].codeLines, st.backing) &&
          _framesMatch(frames, st.taskEntry)) {
        final int oldCount = st.resultCount;
        if (oldCount >= keep && oldCount <= _resultOrder.length) {
          final int shift = keep + _taskScratch.length - oldCount;
          _spliceResults(keep, oldCount);
          if (shift != 0) {
            for (int t = s; t < n; t++) {
              _states[t].resultCount += shift;
            }
          }
          return;
        }
      }
      st.resultCount = keep + _taskScratch.length;
      st.taskEntry = _snapshot(frames);
      _lastTaskScans++;
      final List<CodeLine> lines = segs[s].codeLines;
      int g = _segStarts[s];
      for (int j = 0; j < lines.length; j++, g++) {
        final String text = lines[j].text;
        if (text.isEmpty ||
            text.length > maxScannedLineLength ||
            (fence != null && fence[g] != MarkdownFenceRole.none)) {
          _closeFrames(frames, 0);
          continue;
        }
        final int shape = MarkdownListSyntax.scanListShape(text);
        if (shape < 0) {
          _closeFrames(frames, 0);
          continue;
        }
        final int level = MarkdownListSyntax.shapeLevel(shape);
        _closeFrames(frames, level);
        if (MarkdownListSyntax.shapeKind(shape) ==
            MarkdownListSyntax.shapeKindTask) {
          final bool checked = MarkdownListSyntax.shapeChecked(shape);
          if (frames.isNotEmpty) {
            if (checked) frames.last.checkedDescendants++;
            frames.last.totalDescendants++;
          }
          frames.add(_TaskFrame(line: g, level: level, checked: checked));
        }
      }
    }
    _closeFrames(frames, 0);
    _spliceResults(keep, _resultOrder.length);
  }

  /// Swaps the rescanned region `[keep, oldCount)` of [_resultOrder] for
  /// the freshly scanned [_taskScratch], keeping [_indeterminate] in step
  /// without touching the untouched results on either side. Skipped while
  /// [_resultsRenumbered] — see that field.
  void _spliceResults(int keep, int oldCount) {
    if (_resultsRenumbered) {
      _resultOrder.replaceRange(keep, oldCount, _taskScratch);
      return;
    }
    for (int i = keep; i < oldCount; i++) {
      _indeterminate.remove(_resultOrder[i]);
    }
    _resultOrder.replaceRange(keep, oldCount, _taskScratch);
    for (int i = 0; i < _taskScratch.length; i++) {
      final bool added = _indeterminate.add(_taskScratch[i]);
      assert(added, 'a line may hold at most one indeterminate result');
    }
    assert(
      _indeterminate.length == _resultOrder.length,
      'the indeterminate set drifted from the append-ordered result list',
    );
  }

  /// Money pass: folds every money line's op into a running balance
  /// (grammar + arithmetic from [MarkdownMoneySyntax]). Resumes at the
  /// first replaced segment by reviving [entry]'s fold state, and stops
  /// at the first unchanged segment at or past [settled] whose stored
  /// fold state *and* regenerated history slices match. Fence lines are
  /// inert, mirroring the preview's ledger pass. Oversized lines are
  /// skipped on [MarkdownMoneySyntax.maxLineLength] — the grammar's own
  /// bound, not the task pass's — so the whole scan agrees with
  /// [MarkdownMoneySyntax.parse] about what can be a money line, and a
  /// pathologically long line costs one length compare instead of a walk
  /// through its leading whitespace.
  void _scanMoney(
    List<CodeLineSegment> segs,
    int first,
    int last,
    int settled,
    _SegmentState entry,
  ) {
    final int n = segs.length;
    final int keep = entry.moneyCount;
    final int keepEntries = entry.entryCount;
    final int keepAnchors = entry.anchorCount;
    _moneyLineScratch.clear();
    _moneyValueScratch.clear();
    _entryStash.clear();
    if (_entryBalances.length > keepEntries) {
      _entryStash.addAll(
        _entryBalances.getRange(keepEntries, _entryBalances.length),
      );
      _entryBalances.length = keepEntries;
    }
    _anchorStash.clear();
    if (_anchorBalances.length > keepAnchors) {
      _anchorStash.addAll(
        _anchorBalances.getRange(keepAnchors, _anchorBalances.length),
      );
      _anchorBalances.length = keepAnchors;
    }
    // All fold rules live in [MoneyFold] — this pass only owns the
    // truncate-and-resume bookkeeping. The persistent histories are
    // adopted by reference and appended in place, so the per-segment
    // resume state stays exactly their lengths.
    final MoneyFold fold = MoneyFold.resume(
      balance: entry.moneyEntry,
      history: _entryBalances,
      anchors: _anchorBalances,
      periodStart: entry.periodStart,
      targetCents: entry.targetCents < 0 ? null : entry.targetCents,
      targetAnchor: entry.targetAnchor,
    );
    final List<MarkdownFenceRole>? fence = _fence;
    for (int s = first; s < n; s++) {
      final _SegmentState st = _states[s];
      if (s > last &&
          s >= settled &&
          identical(segs[s].codeLines, st.backing) &&
          _moneyProven(fold, st, keep, keepEntries, keepAnchors)) {
        final int oldCount = st.moneyCount;
        for (int i = st.entryCount - keepEntries; i < _entryStash.length; i++) {
          _entryBalances.add(_entryStash[i]);
        }
        for (
          int i = st.anchorCount - keepAnchors;
          i < _anchorStash.length;
          i++
        ) {
          _anchorBalances.add(_anchorStash[i]);
        }
        final int shift = keep + _moneyLineScratch.length - oldCount;
        _moneyLines.replaceRange(keep, oldCount, _moneyLineScratch);
        _moneyValues.replaceRange(keep, oldCount, _moneyValueScratch);
        if (shift != 0) {
          for (int t = s; t < n; t++) {
            _states[t].moneyCount += shift;
          }
        }
        _entryStash.clear();
        _anchorStash.clear();
        return;
      }
      st.moneyCount = keep + _moneyLineScratch.length;
      st.moneyEntry = fold.balance;
      st.entryCount = _entryBalances.length;
      st.periodStart = fold.periodStart;
      st.anchorCount = _anchorBalances.length;
      st.targetCents = fold.targetCents ?? -1;
      st.targetAnchor = fold.targetAnchor;
      _lastMoneyScans++;
      final List<CodeLine> lines = segs[s].codeLines;
      int g = _segStarts[s];
      for (int j = 0; j < lines.length; j++, g++) {
        final String text = lines[j].text;
        if (text.isEmpty ||
            text.length > MarkdownMoneySyntax.maxLineLength ||
            (fence != null && fence[g] != MarkdownFenceRole.none) ||
            !MarkdownMoneySyntax.leadsWithMoney(text)) {
          continue;
        }
        final MoneyLineMatch? m = MarkdownMoneySyntax.parse(text);
        if (m == null) continue;
        _moneyLineScratch.add(g);
        _moneyValueScratch.add(fold.step(m));
      }
    }
    _moneyLines.replaceRange(keep, _moneyLines.length, _moneyLineScratch);
    _moneyValues.replaceRange(keep, _moneyValues.length, _moneyValueScratch);
    _entryStash.clear();
    _anchorStash.clear();
  }

  bool _moneyProven(
    MoneyFold fold,
    _SegmentState st,
    int keep,
    int keepEntries,
    int keepAnchors,
  ) {
    if (fold.balance != st.moneyEntry ||
        fold.periodStart != st.periodStart ||
        (fold.targetCents ?? -1) != st.targetCents ||
        fold.targetAnchor != st.targetAnchor ||
        _entryBalances.length != st.entryCount ||
        _anchorBalances.length != st.anchorCount) {
      return false;
    }
    final int entryTail = st.entryCount - keepEntries;
    final int anchorTail = st.anchorCount - keepAnchors;
    if (entryTail < 0 ||
        entryTail > _entryStash.length ||
        anchorTail < 0 ||
        anchorTail > _anchorStash.length ||
        st.moneyCount < keep ||
        st.moneyCount > _moneyLines.length) {
      return false;
    }
    for (int i = 0; i < entryTail; i++) {
      if (_entryBalances[keepEntries + i] != _entryStash[i]) return false;
    }
    for (int i = 0; i < anchorTail; i++) {
      if (_anchorBalances[keepAnchors + i] != _anchorStash[i]) return false;
    }
    return true;
  }

  void _closeFrames(List<_TaskFrame> frames, int level) {
    while (frames.isNotEmpty && frames.last.level >= level) {
      final _TaskFrame frame = frames.removeLast();
      if (!frame.checked &&
          frame.checkedDescendants > 0 &&
          frame.checkedDescendants < frame.totalDescendants) {
        _taskScratch.add(frame.line);
      }
      if (frames.isNotEmpty) {
        frames.last.checkedDescendants += frame.checkedDescendants;
        frames.last.totalDescendants += frame.totalDescendants;
      }
    }
  }

  static bool _framesMatch(
    List<_TaskFrame> frames,
    List<_TaskSnapshot> snaps,
  ) {
    if (frames.length != snaps.length) return false;
    for (int i = 0; i < frames.length; i++) {
      final _TaskFrame frame = frames[i];
      final _TaskSnapshot snap = snaps[i];
      if (frame.line != snap.line ||
          frame.level != snap.level ||
          frame.checked != snap.checked ||
          frame.checkedDescendants != snap.checkedDescendants ||
          frame.totalDescendants != snap.totalDescendants) {
        return false;
      }
    }
    return true;
  }

  static List<_TaskSnapshot> _snapshot(List<_TaskFrame> frames) {
    if (frames.isEmpty) return const [];
    return List<_TaskSnapshot>.generate(
      frames.length,
      (i) => _TaskSnapshot(
        line: frames[i].line,
        level: frames[i].level,
        checked: frames[i].checked,
        checkedDescendants: frames[i].checkedDescendants,
        totalDescendants: frames[i].totalDescendants,
      ),
      growable: false,
    );
  }
}

/// Everything the three passes need to resume at the **entry** of one
/// segment, plus the backing `codeLines` list that identifies it. One
/// mutable object per segment, so a structural edit is a single
/// `replaceRange` over the state list.
class _SegmentState {
  List<CodeLine> backing;
  bool fenceEntry = false;
  int resultCount = 0;
  List<_TaskSnapshot> taskEntry = const [];
  int moneyCount = 0;
  int moneyEntry;
  int entryCount = 1;
  int periodStart = 0;
  int anchorCount = 1;
  int targetCents = -1;
  int targetAnchor;

  _SegmentState(this.backing, int startCents)
    : moneyEntry = startCents,
      targetAnchor = startCents;
}

/// Mutable accumulator for one open task item during a scan: how many
/// task descendants its subtree holds and how many of them are checked.
class _TaskFrame {
  final int line;
  final int level;
  final bool checked;
  int checkedDescendants = 0;
  int totalDescendants = 0;

  _TaskFrame({required this.line, required this.level, required this.checked});
}

/// Immutable copy of the open-frame stack entering a segment, so a
/// rescan can resume mid-document with exact state.
class _TaskSnapshot {
  final int line;
  final int level;
  final bool checked;
  final int checkedDescendants;
  final int totalDescendants;

  const _TaskSnapshot({
    required this.line,
    required this.level,
    required this.checked,
    required this.checkedDescendants,
    required this.totalDescendants,
  });

  _TaskSnapshot shifted(int delta) => _TaskSnapshot(
    line: line + delta,
    level: level,
    checked: checked,
    checkedDescendants: checkedDescendants,
    totalDescendants: totalDescendants,
  );

  /// The frame's line fell inside the replaced range, so it has no image
  /// in the new document. `-1` is unreachable for a recomputed frame, so
  /// the seam proof can never match this snapshot.
  _TaskSnapshot orphaned() => _TaskSnapshot(
    line: -1,
    level: level,
    checked: checked,
    checkedDescendants: checkedDescendants,
    totalDescendants: totalDescendants,
  );
}
