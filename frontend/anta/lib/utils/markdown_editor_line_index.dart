import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:re_editor/re_editor.dart';

import 'markdown_callout_syntax.dart';
import 'markdown_chunker.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';

/// Positional role of a line relative to ``` code fences. Delimiter and
/// interior lines style differently in the editor, and both bypass its
/// text-keyed span memo because the role depends on position, not
/// content. Grammar comes from [MarkdownChunker.isFenceDelimiter] — the
/// same predicate the preview's block scan uses.
enum MarkdownFenceRole { none, delimiter, interior }

/// Positional role of a line inside a callout block: the `> [!TYPE]`
/// [lead] line, one of the contiguous blockquote [body] lines under it,
/// or [none] for every other line (a plain quote included). Grammar
/// comes from [MarkdownCalloutSyntax.blockStep] — the same transition
/// the preview's block scan runs.
enum MarkdownCalloutRole { none, lead, body }

/// Incremental positional index over the editor's [CodeLines]: per-line
/// fence roles, per-line callout roles, the set of task lines whose
/// unchecked box renders indeterminate (subtree partially complete), and
/// the money ledger's per-row display values.
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
/// count, and the four passes re-scan from `p` resuming from the
/// retained entry state of segment `p`. A keystroke, an Enter, a line
/// delete and a paste therefore all take the same path — only the
/// replaced segments are rescanned — instead of the structural edits
/// falling back to a whole-document rebuild.
///
/// Each pass then stops at the first **seam** it can prove: an unchanged
/// segment whose stored entry state equals the state the rescan carries
/// into it resolves every line below it exactly as before, so the old
/// results for those lines are appended back verbatim, shifted by the
/// change in result count above them. The four entry states differ:
///
///   * fence pass — one bit, the in-fence parity;
///   * callout pass — the type of the callout block open on entry (0
///     when none is). It has no result list of its own: the per-line
///     packed roles live in an array the splice renumbers, so a proven
///     seam simply stops the scan and leaves every value below it in
///     place. The pass depends on the fence pass's own seam — a fence
///     that opened above closes any block — so it never settles before
///     the fence roles do;
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
/// per-line fence and callout arrays back to `null`, the result and money lists
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

  /// Per-line callout roles, packed as `((type.index + 1) << 2) | role`
  /// with role 1 = lead and 2 = body; `0` is "no callout here". `null`
  /// means the document holds no callout at all (the common case pays no
  /// per-line storage), and once the array exists every line writes its
  /// value — zeros included — so a stale role can never survive a
  /// rescan. Growable, because a structural edit splices its middle
  /// range. Decoded by [calloutRoleOf] / [calloutTypeOf].
  List<int>? _callout;

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
  int _lastCalloutScans = 0;
  int _lastTaskScans = 0;
  int _lastMoneyScans = 0;

  /// What the most recent index update did: whether it fell back to a
  /// full rebuild, and how many segments each pass actually scanned (0
  /// when the pass did not run). Handed the very same [CodeLines]
  /// instance again the index does nothing at all and this is left
  /// untouched; a fresh wrapper over identical backing lists (an undo to
  /// identical content) *is* an update, and reports all zeros.
  @visibleForTesting
  ({bool rebuilt, int fence, int callout, int tasks, int money})
  get debugLastScan => (
    rebuilt: _lastRebuilt,
    fence: _lastFenceScans,
    callout: _lastCalloutScans,
    tasks: _lastTaskScans,
    money: _lastMoneyScans,
  );

  /// Applies the money feature's enabled flag and global start balance.
  /// When disabled the money pass is skipped entirely (the results are
  /// empty and [moneyValueAt] always returns null), so the index does
  /// exactly the work it did before the feature existed. A change
  /// invalidates the whole index (cheap, rare — a settings change), so
  /// the next access rebuilds all passes — except a start-balance change
  /// while the pass stays off, which nothing below reads: the new value
  /// is recorded and the built fence and task results are kept. Every
  /// transition of [enabled] invalidates, so a later enable still seeds
  /// the histories from whatever balance was recorded meanwhile.
  void configureMoney({required bool enabled, required int startCents}) {
    if (enabled == _moneyEnabled && startCents == _moneyStartCents) return;
    if (!enabled && !_moneyEnabled) {
      _moneyStartCents = startCents;
      return;
    }
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

  /// The packed callout state of the line at [index] — `0` when the line
  /// belongs to no callout block. Handed straight to the span builder's
  /// positional memo key, so the role *and* the block's type both take
  /// part in it without a second lookup; decode it with [calloutRoleOf]
  /// and [calloutTypeOf].
  int calloutAt(CodeLines lines, int index) {
    _ensure(lines);
    final callout = _callout;
    if (callout == null || index < 0 || index >= callout.length) return 0;
    return callout[index];
  }

  /// The callout role of the line at [index]; [MarkdownCalloutRole.none]
  /// outside any block. Convenience over [calloutAt] for callers that do
  /// not need the block's type.
  MarkdownCalloutRole calloutRoleAt(CodeLines lines, int index) =>
      calloutRoleOf(calloutAt(lines, index));

  /// The role packed into [packed] by the callout pass.
  static MarkdownCalloutRole calloutRoleOf(int packed) =>
      MarkdownCalloutRole.values[packed & 3];

  /// The callout type packed into [packed], or `null` when the line
  /// belongs to no block.
  static MarkdownCalloutType? calloutTypeOf(int packed) {
    final type = packed >> 2;
    return type == 0 ? null : MarkdownCalloutType.values[type - 1];
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
    _lastCalloutScans = 0;
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
    final _SegmentState entry = _SegmentState.copy(_states[p]);

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
      _callout?.replaceRange(a, b, List<int>.filled(newMiddleLines, 0));
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
    _scanCallouts(segs, p, last, settled, entry);
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
    _callout = null;
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
    _scanCallouts(segs, 0, last, settled, entry);
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

  /// Callout pass: walks [MarkdownCalloutSyntax.blockStep] down the
  /// document and writes each line's packed role. Resumes at the first
  /// replaced segment from [entry]'s open block and stops at the first
  /// unchanged segment at or past [settled] that the scan enters with
  /// the very same block open — every line below it then keeps the role
  /// the array already holds.
  ///
  /// Fence lines end any open block and hold no role of their own: the
  /// grammar leaves fences to its caller, so this pass answers them from
  /// the fence array instead of calling [MarkdownCalloutSyntax.blockStep]
  /// on them. That is also why the pass may not settle before the fence
  /// pass has ([settled]).
  ///
  /// Per line the cost is one allocation-free
  /// [MarkdownCalloutSyntax.isBlockquoteLine] probe, plus a
  /// [MarkdownCalloutSyntax.parseLead] only on lines that lead with `>`
  /// while no block is open.
  void _scanCallouts(
    List<CodeLineSegment> segs,
    int first,
    int last,
    int settled,
    _SegmentState entry,
  ) {
    final int n = segs.length;
    int open = entry.calloutEntry;
    final List<MarkdownFenceRole>? fence = _fence;
    for (int s = first; s < n; s++) {
      final _SegmentState st = _states[s];
      if (s > last &&
          s >= settled &&
          identical(segs[s].codeLines, st.backing) &&
          st.calloutEntry == open) {
        return;
      }
      st.calloutEntry = open;
      _lastCalloutScans++;
      final List<CodeLine> lines = segs[s].codeLines;
      int g = _segStarts[s];
      List<int>? callout = _callout;
      for (int j = 0; j < lines.length; j++, g++) {
        if (fence != null && fence[g] != MarkdownFenceRole.none) {
          open = 0;
          if (callout != null) callout[g] = 0;
          continue;
        }
        final MarkdownCalloutType? next = MarkdownCalloutSyntax.blockStep(
          lines[j].text,
          open == 0 ? null : MarkdownCalloutType.values[open - 1],
        );
        if (next == null) {
          open = 0;
          if (callout != null) callout[g] = 0;
          continue;
        }
        final int role = open == 0 ? 1 : 2;
        callout ??= _callout = List<int>.filled(_lineCount, 0, growable: true);
        callout[g] = ((next.index + 1) << 2) | role;
        open = next.index + 1;
      }
    }
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
          _taskScratch.clear();
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
    _taskScratch.clear();
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
        _moneyLineScratch.clear();
        _moneyValueScratch.clear();
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
    _moneyLineScratch.clear();
    _moneyValueScratch.clear();
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

  static bool _framesMatch(List<_TaskFrame> frames, List<_TaskSnapshot> snaps) {
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

/// Everything the four passes need to resume at the **entry** of one
/// segment, plus the backing `codeLines` list that identifies it. One
/// mutable object per segment, so a structural edit is a single
/// `replaceRange` over the state list.
///
/// [_SegmentState.copy] exists because the splice's resume state must not
/// alias a live element of `_states`: when the old middle is empty the
/// `replaceRange` removes nothing, so the captured entry object survives
/// further down the list where the renumbering loop and the four passes
/// would write through the alias into the state they are resuming from.
class _SegmentState {
  List<CodeLine> backing;
  bool fenceEntry;

  /// The callout block open at this segment's entry, as its type index
  /// plus one; `0` when none is.
  int calloutEntry;
  int resultCount;
  List<_TaskSnapshot> taskEntry;
  int moneyCount;
  int moneyEntry;
  int entryCount;
  int periodStart;
  int anchorCount;
  int targetCents;
  int targetAnchor;

  _SegmentState(this.backing, int startCents)
    : fenceEntry = false,
      calloutEntry = 0,
      resultCount = 0,
      taskEntry = const [],
      moneyCount = 0,
      moneyEntry = startCents,
      entryCount = 1,
      periodStart = 0,
      anchorCount = 1,
      targetCents = -1,
      targetAnchor = startCents;

  /// Detached copy of [other]. [taskEntry] is shared by reference: the
  /// snapshots are immutable and the list itself is only ever replaced,
  /// never mutated in place.
  _SegmentState.copy(_SegmentState other)
    : backing = other.backing,
      fenceEntry = other.fenceEntry,
      calloutEntry = other.calloutEntry,
      resultCount = other.resultCount,
      taskEntry = other.taskEntry,
      moneyCount = other.moneyCount,
      moneyEntry = other.moneyEntry,
      entryCount = other.entryCount,
      periodStart = other.periodStart,
      anchorCount = other.anchorCount,
      targetCents = other.targetCents,
      targetAnchor = other.targetAnchor;
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
