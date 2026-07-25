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
/// fence roles and the set of task lines whose unchecked box renders
/// indeterminate (subtree partially complete).
///
/// Replaces the two independent O(total lines) rebuilds the span
/// builder ran on every text mutation. The index exploits the fork's
/// structural sharing: `CodeLines.from` clones segments via
/// `cloneShallowDirty()`, which shares each segment's backing
/// `codeLines` list by reference, and a text edit clones only the
/// touched segment's list. So backing-list identity per segment is a
/// precise dirty flag, and a keystroke rescans ~one segment (256 lines)
/// instead of the whole document:
///
///   * fence pass — resumes at the first changed segment with the
///     stored entry parity and stops as soon as it re-enters an
///     unchanged segment with matching parity (suffix roles proven
///     unchanged);
///   * task pass — resumes at the first changed segment by reviving the
///     stored open-frame stack snapshot and truncating the append-
///     ordered result list to the entries recorded above it, then scans
///     to the end (a subtree's indeterminate state can depend on any
///     line below, so there is no cheap suffix proof);
///   * money pass — resumes at the first changed segment by reviving
///     the stored entry balance and truncating the append-ordered
///     result lists, then scans to the end (downstream balances depend
///     on every op above, mirroring the task pass shape).
///
/// Structural edits (Enter, paste, line deletes) change per-segment
/// lengths and fall back to a full rebuild, which the allocation-free
/// [MarkdownListSyntax.scanListShape] keeps cheap. Both paths assume
/// the fork's contract that a published [CodeLines] is never mutated in
/// place — the same assumption the old per-instance caches relied on.
class MarkdownEditorLineIndex {
  /// Lines longer than this never participate in the task index,
  /// mirroring the span builder's raw-render guard.
  final int maxScannedLineLength;

  MarkdownEditorLineIndex({required this.maxScannedLineLength});

  CodeLines? _lines;
  int _lineCount = 0;
  List<List<CodeLine>> _segLists = const [];
  List<int> _segStarts = const [];

  /// Per-line fence roles; `null` means no fence anywhere (the common
  /// gym-note case pays no per-line storage).
  List<MarkdownFenceRole>? _fence;
  List<bool> _segFenceEntry = const [];

  final List<int> _resultOrder = <int>[];
  List<int> _segResultCount = const [];
  List<List<_TaskSnapshot>> _segTaskEntry = const [];
  Set<int>? _indeterminate;

  /// Money pass results: sorted line indices of money lines and the
  /// display value (cents) for each — the running balance after the
  /// line, except `$?` delta lines (net change since the last `$=`),
  /// `$^ N` diff lines (move across the last N balance-changing entries),
  /// and `$~ N` span lines (move across the last N `$=` checkpoints).
  /// The entry-balance history is an append-only result list (seeded
  /// with the start balance, one value per `$=`/`$+`/`$-`/`$*`/`$/`) and
  /// the checkpoint-balance history a parallel one (seeded the same, one
  /// value per `$=`), so per-segment resume state is just their lengths
  /// plus the current period-start index — truncate and re-append,
  /// exactly like the task pass.
  final List<int> _moneyLines = <int>[];
  final List<int> _moneyValues = <int>[];
  final List<int> _entryBalances = <int>[];
  final List<int> _anchorBalances = <int>[];
  List<int> _segMoneyCount = const [];
  List<int> _segMoneyEntry = const [];
  List<int> _segEntryCount = const [];
  List<int> _segPeriodStart = const [];
  List<int> _segAnchorCount = const [];
  bool _moneyEnabled = false;
  int _moneyStartCents = 0;

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
    return _indeterminate?.contains(index) ?? false;
  }

  /// The display value (cents) for the money line at [index], or `null`
  /// when the line is not a money line: the running balance after the
  /// line, for `$?` delta lines the net change since the last `$=`, for
  /// `$^ N` diff lines the move across the last N entries, for `$~ N`
  /// span lines the move across the last N `$=` checkpoints. Grammar and
  /// arithmetic come from [MarkdownMoneySyntax], shared with the preview.
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
    final segs = lines.segments;
    final int n = segs.length;

    int first = -1;
    int last = -1;
    bool structural = _lines == null ||
        n != _segLists.length ||
        lines.length != _lineCount;
    if (!structural) {
      for (int s = 0; s < n; s++) {
        final List<CodeLine> backing = segs[s].codeLines;
        if (identical(backing, _segLists[s])) continue;
        if (backing.length != _segLists[s].length) {
          structural = true;
          break;
        }
        if (first < 0) first = s;
        last = s;
      }
    }

    if (structural) {
      _rebuildAll(lines, segs);
    } else if (first >= 0) {
      _scanFence(segs, first, last);
      _scanTasks(segs, first);
      if (_moneyEnabled) _scanMoney(segs, first);
      _indeterminate = _resultOrder.isEmpty ? null : Set.of(_resultOrder);
      _adoptSegLists(segs);
    } else {
      // New CodeLines wrapper over identical backing lists (no-op edit,
      // undo to identical content): nothing to rescan.
      _adoptSegLists(segs);
    }
    _lines = lines;
  }

  void _adoptSegLists(List<CodeLineSegment> segs) {
    final lists = List<List<CodeLine>>.filled(segs.length, const []);
    for (int s = 0; s < segs.length; s++) {
      lists[s] = segs[s].codeLines;
    }
    _segLists = lists;
  }

  void _rebuildAll(CodeLines lines, List<CodeLineSegment> segs) {
    final int n = segs.length;
    _lineCount = lines.length;
    final starts = List<int>.filled(n, 0);
    int start = 0;
    for (int s = 0; s < n; s++) {
      starts[s] = start;
      start += segs[s].codeLines.length;
    }
    _segStarts = starts;
    _fence = null;
    _segFenceEntry = List<bool>.filled(n, false);
    _resultOrder.clear();
    _segResultCount = List<int>.filled(n, 0);
    _segTaskEntry = List<List<_TaskSnapshot>>.filled(n, const []);
    _moneyLines.clear();
    _moneyValues.clear();
    _entryBalances
      ..clear()
      ..add(_moneyStartCents);
    _anchorBalances
      ..clear()
      ..add(_moneyStartCents);
    _segMoneyCount = List<int>.filled(n, 0);
    _segMoneyEntry = List<int>.filled(n, _moneyStartCents);
    _segEntryCount = List<int>.filled(n, 1);
    _segPeriodStart = List<int>.filled(n, 0);
    _segAnchorCount = List<int>.filled(n, 1);
    if (n > 0) {
      _scanFence(segs, 0, n - 1);
      _scanTasks(segs, 0);
      if (_moneyEnabled) _scanMoney(segs, 0);
    }
    _indeterminate = _resultOrder.isEmpty ? null : Set.of(_resultOrder);
    _adoptSegLists(segs);
  }

  void _scanFence(List<CodeLineSegment> segs, int first, int last) {
    final int n = segs.length;
    bool inFence = _segFenceEntry[first];
    for (int s = first; s < n; s++) {
      // Suffix proof: an unchanged segment entered with the same parity
      // as last time resolves every following line identically.
      if (s > last &&
          identical(segs[s].codeLines, _segLists[s]) &&
          _segFenceEntry[s] == inFence) {
        return;
      }
      _segFenceEntry[s] = inFence;
      final List<CodeLine> lines = segs[s].codeLines;
      int g = _segStarts[s];
      List<MarkdownFenceRole>? fence = _fence;
      for (int j = 0; j < lines.length; j++, g++) {
        if (MarkdownChunker.isFenceDelimiter(lines[j].text)) {
          fence ??= _fence = List<MarkdownFenceRole>.filled(
            _lineCount,
            MarkdownFenceRole.none,
          );
          fence[g] = MarkdownFenceRole.delimiter;
          inFence = !inFence;
        } else if (fence != null) {
          fence[g] =
              inFence ? MarkdownFenceRole.interior : MarkdownFenceRole.none;
        }
      }
    }
  }

  void _scanTasks(List<CodeLineSegment> segs, int first) {
    final int n = segs.length;
    final int keep = _segResultCount[first];
    if (_resultOrder.length > keep) {
      _resultOrder.length = keep;
    }
    final frames = <_TaskFrame>[];
    for (final _TaskSnapshot snap in _segTaskEntry[first]) {
      frames.add(_TaskFrame(
        line: snap.line,
        level: snap.level,
        checked: snap.checked,
      )
        ..checkedDescendants = snap.checkedDescendants
        ..totalDescendants = snap.totalDescendants);
    }
    final List<MarkdownFenceRole>? fence = _fence;
    for (int s = first; s < n; s++) {
      _segResultCount[s] = _resultOrder.length;
      _segTaskEntry[s] = _snapshot(frames);
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
  }

  /// Money pass: folds every money line's op into a running balance
  /// (grammar + arithmetic from [MarkdownMoneySyntax]). Balance state
  /// flows strictly downward, so like the task pass a rescan resumes at
  /// the first changed segment — reviving the stored entry balance and
  /// truncating the append-ordered result lists — then scans to the
  /// end. Fence lines are inert, mirroring the preview's ledger pass.
  void _scanMoney(List<CodeLineSegment> segs, int first) {
    final int n = segs.length;
    final int keep = _segMoneyCount[first];
    if (_moneyLines.length > keep) {
      _moneyLines.length = keep;
      _moneyValues.length = keep;
    }
    var balance = _segMoneyEntry[first];
    var periodStart = _segPeriodStart[first];
    final int keepEntries = _segEntryCount[first];
    if (_entryBalances.length > keepEntries) {
      _entryBalances.length = keepEntries;
    }
    final int keepAnchors = _segAnchorCount[first];
    if (_anchorBalances.length > keepAnchors) {
      _anchorBalances.length = keepAnchors;
    }
    final List<MarkdownFenceRole>? fence = _fence;
    for (int s = first; s < n; s++) {
      _segMoneyCount[s] = _moneyLines.length;
      _segMoneyEntry[s] = balance;
      _segEntryCount[s] = _entryBalances.length;
      _segPeriodStart[s] = periodStart;
      _segAnchorCount[s] = _anchorBalances.length;
      final List<CodeLine> lines = segs[s].codeLines;
      int g = _segStarts[s];
      for (int j = 0; j < lines.length; j++, g++) {
        final String text = lines[j].text;
        if (text.isEmpty ||
            text.length > maxScannedLineLength ||
            (fence != null && fence[g] != MarkdownFenceRole.none) ||
            !MarkdownMoneySyntax.leadsWithMoney(text)) {
          continue;
        }
        final MoneyLineMatch? m = MarkdownMoneySyntax.parse(text);
        if (m == null) continue;
        // Error lines never mutate the fold — including the history and
        // checkpoint appends, or an error `$=` would shift every window
        // here while `collectEntries` (which guards) disagreed.
        if (!MarkdownMoneySyntax.hasError(m)) {
          balance = MarkdownMoneySyntax.apply(balance, m);
          if (MarkdownMoneySyntax.isEntryKind(m.kind)) {
            _entryBalances.add(balance);
            if (m.kind == MoneyLineKind.set) {
              periodStart = _entryBalances.length - 1;
              _anchorBalances.add(balance);
            }
          }
        }
        _moneyLines.add(g);
        _moneyValues.add(
          MarkdownMoneySyntax.displayValue(
            m,
            balance,
            _entryBalances,
            periodStart,
            _anchorBalances,
          ),
        );
      }
    }
  }

  void _closeFrames(List<_TaskFrame> frames, int level) {
    while (frames.isNotEmpty && frames.last.level >= level) {
      final _TaskFrame frame = frames.removeLast();
      if (!frame.checked &&
          frame.checkedDescendants > 0 &&
          frame.checkedDescendants < frame.totalDescendants) {
        _resultOrder.add(frame.line);
      }
      if (frames.isNotEmpty) {
        frames.last.checkedDescendants += frame.checkedDescendants;
        frames.last.totalDescendants += frame.totalDescendants;
      }
    }
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
}
