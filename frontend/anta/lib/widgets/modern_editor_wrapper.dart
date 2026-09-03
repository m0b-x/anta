import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/font_constants.dart';
import '../constants/markdown_constants.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/markdown_link_patterns.dart';
import '../utils/markdown_list_syntax.dart';
import '../utils/markdown_list_utils.dart';
import '../utils/markdown_money_syntax.dart';
import '../utils/markdown_tag_syntax.dart';
import '../utils/re_editor_search_controller.dart';
import 'editor_chunk_overlay.dart';
import 'scroll_progress_indicator.dart';

/// Wraps the CodeEditor with custom toolbar and scroll indicator.
class ModernEditorWrapper extends StatefulWidget {
  final CodeLineEditingController controller;
  final FocusNode focusNode;
  final CodeScrollController scrollController;
  final ReEditorSearchController searchController;
  final double editorFontSize;
  final VoidCallback onTextChanged;
  final bool showLineNumbers;
  final bool wordWrap;
  final bool showCursorLine;

  /// Whether tapping a task item's checkbox toggles it (live markdown
  /// rendering). Taps are claimed at pointer level via the editor's
  /// tap interceptor, so toggling never moves the caret or raises the
  /// keyboard, and re-tapping the same box re-toggles.
  final bool checkboxTapToggle;

  /// Opens the url of a tapped `[text](url)` link (live markdown
  /// rendering). Null disables link tap-to-open.
  final ValueChanged<String>? onOpenLink;

  /// Opens the ledger detail for a tapped `$$` / `$?` money chip (live
  /// markdown rendering). Null disables money tap-to-detail.
  final void Function(int lineIndex)? onMoneyTap;

  /// Searches for a tapped `#tag` (live markdown rendering), receiving
  /// the tag with its leading `#` preserved — the same string the
  /// preview's tag recognizer passes. Null disables tag tap-to-search.
  final void Function(String tag)? onOpenTag;

  /// Whether a line sits inside (or delimits) a ``` code fence — fence
  /// text renders raw, so taps there always fall through to editing.
  final bool Function(int lineIndex)? isFenceLine;

  final GlobalKey? lineNumbersKey;
  final GlobalKey? scrollIndicatorKey;

  /// Whether the scroll-progress rail is painted down the right edge. Off
  /// for short embedded editors, where a progress rail beside three lines
  /// of text reads as clutter.
  final bool showScrollIndicator;

  /// Number of lines per chunk for debug visualization (matches preview mode)
  final int linesPerChunk;

  /// Whether to show colored backgrounds for chunks (debug mode)
  final bool showChunkColors;

  /// Whether to show borders around chunks (debug mode)
  final bool showChunkBorders;

  const ModernEditorWrapper({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.searchController,
    required this.editorFontSize,
    required this.onTextChanged,
    this.showLineNumbers = false,
    this.wordWrap = true,
    this.showCursorLine = false,
    this.checkboxTapToggle = false,
    this.onOpenLink,
    this.onMoneyTap,
    this.onOpenTag,
    this.isFenceLine,
    this.lineNumbersKey,
    this.scrollIndicatorKey,
    this.showScrollIndicator = true,
    this.linesPerChunk = 10,
    this.showChunkColors = false,
    this.showChunkBorders = false,
  });

  /// Number of times a tap has been resolved against the markdown
  /// grammars since the counter was last reset. Only exists so tests can
  /// pin that a claimed tap resolves once (tap-down) and reuses the memo
  /// at tap-up; nothing in the app reads it.
  @visibleForTesting
  static int debugTapResolveCount = 0;

  @override
  State<ModernEditorWrapper> createState() => _ModernEditorWrapperState();
}

/// The action resolved for the tap currently claimed by the interceptor,
/// together with everything [_ModernEditorWrapperState._resolveTapAction]
/// read to produce it. Reused at tap-up only while all of it still holds.
class _TapClaim {
  const _TapClaim({
    required this.index,
    required this.offset,
    required this.lineText,
    required this.selection,
    required this.inFence,
    required this.action,
  });

  final int index;
  final int offset;
  final String? lineText;
  final CodeLineSelection selection;
  final bool inFence;
  final VoidCallback action;
}

class _ModernEditorWrapperState extends State<ModernEditorWrapper> {
  late final SelectionToolbarController _toolbarController;

  /// Armed by a pointer-up over the editor and consumed by the next
  /// caret change, so only a *tap* (not arrow-key navigation, which
  /// fires no pointer event) can engage a ghost. Auto-expires so a
  /// stale tap can't trigger a much-later keyboard caret move.
  bool _pendingGhostTapCheck = false;
  Timer? _ghostTapExpiry;

  /// Reentrancy guard while we programmatically set the selection to
  /// activate a ghost.
  bool _activatingGhost = false;

  /// The pending tap claim (see [_claimTapAction] / [_consumeTapAction]).
  _TapClaim? _tapClaim;

  /// Claims taps on checkbox boxes and concealed links at pointer level
  /// (via the fork's [CodeEditorTapInterceptor]) so the editor never
  /// moves the caret, never requests focus (no keyboard rise on an
  /// unfocused editor), and every tap fires — including re-taps on the
  /// same spot. The claim's action is memoized at tap-down and reused at
  /// tap-up while every input it was resolved from is unchanged, so the
  /// grammars run once per tap instead of twice; any change (a different
  /// position, the line's text, the selection, the line's fence role)
  /// falls back to a fresh resolve, so a text change between down and up
  /// still can never fire the wrong action.
  late final CodeEditorTapInterceptor _tapInterceptor =
      CodeEditorTapInterceptor(
        shouldIntercept: (position) => _claimTapAction(position) != null,
        onTap: (position) {
          // The tap was claimed — it must not double as a ghost-arming
          // tap, or the action's own controller notification could
          // re-activate a ghost the caret already sits in.
          _pendingGhostTapCheck = false;
          _ghostTapExpiry?.cancel();
          _consumeTapAction(position)?.call();
          // On desktop the editor's inner Listener dispatches this
          // pointer-up before this widget's outer Listener re-arms the
          // flag, so disarm once more after routing finishes.
          scheduleMicrotask(() {
            _pendingGhostTapCheck = false;
            _ghostTapExpiry?.cancel();
          });
        },
      );

  /// The ghost run engaged by the last tap (whole-run selection). A
  /// second tap on the same, unmodified ghost switches to edit mode:
  /// the caret stays where the tap put it instead of re-selecting the
  /// run. Cleared as soon as the selection leaves the run or its line
  /// changes.
  int _engagedGhostLine = -1;
  int _engagedGhostStart = -1;
  int _engagedGhostEnd = -1;
  String _engagedGhostText = '';

  static const Duration _ghostTapWindow = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _toolbarController = MobileSelectionToolbarController(
      builder: _buildSelectionToolbar,
    );
  }

  @override
  void dispose() {
    _ghostTapExpiry?.cancel();
    widget.searchController.clearFindController();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Arms the ghost-tap check. Called from a [Listener] wrapping the
  /// editor, so it fires on every pointer release over the text area.
  void _onEditorPointerUp(PointerUpEvent event) {
    _pendingGhostTapCheck = true;
    _ghostTapExpiry?.cancel();
    _ghostTapExpiry = Timer(_ghostTapWindow, () {
      _pendingGhostTapCheck = false;
    });
  }

  /// When a tap lands the caret strictly inside a ghost run, select the
  /// whole `{{ … }}` run so it reads as an active "fill-in" field — the
  /// native selection highlight is the "you tapped it" signal. Typing
  /// replaces the run (markers included); tapping away simply collapses
  /// the selection, leaving the placeholder intact, so nothing is ever
  /// lost. Tapping the same ghost a second time switches to edit mode:
  /// the caret stays where that tap put it so the inner text can be
  /// edited in place. The selection is set in a microtask so we never
  /// reenter the controller from within its own notification.
  void _maybeActivateTappedGhost() {
    if (!_pendingGhostTapCheck || _activatingGhost) return;
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isCollapsed) return;
    final lineIndex = selection.baseIndex;
    final lines = controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final lineText = lines[lineIndex].text;
    if (!GhostText.mightContain(lineText)) return;
    final ghost = GhostText.ghostAtOffset(lineText, selection.baseOffset);
    if (ghost == null) return;

    if (lineIndex == _engagedGhostLine &&
        lineText == _engagedGhostText &&
        ghost.start == _engagedGhostStart &&
        ghost.end == _engagedGhostEnd) {
      // Second tap on the engaged ghost: leave the collapsed caret in
      // place for editing.
      _pendingGhostTapCheck = false;
      _ghostTapExpiry?.cancel();
      _clearEngagedGhost();
      return;
    }
    _engagedGhostLine = lineIndex;
    _engagedGhostStart = ghost.start;
    _engagedGhostEnd = ghost.end;
    _engagedGhostText = lineText;

    _pendingGhostTapCheck = false;
    _ghostTapExpiry?.cancel();
    _activatingGhost = true;
    scheduleMicrotask(() {
      if (!mounted) {
        _activatingGhost = false;
        return;
      }
      controller.selection = CodeLineSelection(
        baseIndex: lineIndex,
        baseOffset: ghost.start,
        extentIndex: lineIndex,
        extentOffset: ghost.end,
      );
      _activatingGhost = false;
    });
  }

  Widget _buildSelectionToolbar({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    final isCollapsed = controller.selection.isCollapsed;

    // Build button items based on selection state
    final buttonItems = <ContextMenuButtonItem>[
      // Cut and Copy only when text is selected
      if (!isCollapsed) ...[
        ContextMenuButtonItem(
          label: MaterialLocalizations.of(context).cutButtonLabel,
          onPressed: () {
            controller.cut();
            onDismiss();
          },
        ),
        ContextMenuButtonItem(
          label: MaterialLocalizations.of(context).copyButtonLabel,
          onPressed: () {
            controller.copy();
            onDismiss();
          },
        ),
      ],
      // Paste is always available
      ContextMenuButtonItem(
        label: MaterialLocalizations.of(context).pasteButtonLabel,
        onPressed: () {
          controller.paste();
          onDismiss();
        },
      ),
      // Select All is always available
      ContextMenuButtonItem(
        label: MaterialLocalizations.of(context).selectAllButtonLabel,
        onPressed: () {
          controller.selectAll();
          onRefresh();
        },
      ),
    ];

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: buttonItems,
    );
  }

  void _onControllerChanged() {
    widget.onTextChanged();
    _maybeActivateTappedGhost();
    _maybeClearEngagedGhost();
  }

  /// Resolves the action for a tap-down and memoizes it as the pending
  /// claim, so [_consumeTapAction] can fire it at tap-up without running
  /// every grammar a second time. A failed claim clears the memo.
  VoidCallback? _claimTapAction(CodeLinePosition position) {
    final action = _resolveTapAction(position);
    _tapClaim = action == null
        ? null
        : _TapClaim(
            index: position.index,
            offset: position.offset,
            lineText: _lineTextAt(position.index),
            selection: widget.controller.selection,
            inFence: widget.isFenceLine?.call(position.index) ?? false,
            action: action,
          );
    return action;
  }

  /// The action for a claimed tap's tap-up. Reuses the memo from
  /// [_claimTapAction] when nothing it was resolved from moved, and
  /// re-resolves otherwise. Single-shot: the memo is dropped either way,
  /// so an abandoned claim (slop, cancel, another pointer) can never be
  /// consumed by a later tap.
  VoidCallback? _consumeTapAction(CodeLinePosition position) {
    final claim = _tapClaim;
    _tapClaim = null;
    if (claim != null &&
        claim.index == position.index &&
        claim.offset == position.offset &&
        claim.selection == widget.controller.selection &&
        claim.inFence == (widget.isFenceLine?.call(position.index) ?? false) &&
        claim.lineText == _lineTextAt(position.index)) {
      return claim.action;
    }
    return _resolveTapAction(position);
  }

  /// The text of [lineIndex], or null when it is out of range.
  String? _lineTextAt(int lineIndex) {
    final lines = widget.controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) return null;
    return lines[lineIndex].text;
  }

  /// Resolves what a tap at [position] does instead of editing: toggle
  /// a task checkbox, open a concealed link, open a money row's ledger
  /// detail, or search a `#tag`. Returns null when the tap should fall
  /// through to normal caret placement — on reveal (selection-covered)
  /// lines the raw markdown is showing and taps mean editing; fence
  /// lines render raw; and ghost runs pass through because ghost
  /// engagement rides the selection change (ghosts win).
  VoidCallback? _resolveTapAction(CodeLinePosition position) {
    ModernEditorWrapper.debugTapResolveCount++;
    final controller = widget.controller;
    final lines = controller.codeLines;
    final lineIndex = position.index;
    if (lineIndex < 0 || lineIndex >= lines.length) return null;
    if (MarkdownEditorSpanBuilder.selectionCoversLine(
      controller.selection,
      lineIndex,
    )) {
      return null;
    }
    if (widget.isFenceLine?.call(lineIndex) ?? false) return null;
    final text = lines[lineIndex].text;
    // Overlong lines render raw (the builder's length guard), so their
    // constructs are visible markdown and taps mean editing.
    if (text.length > MarkdownEditorSpanBuilder.maxStyledLineLength) {
      return null;
    }
    final offset = position.offset;
    // Hit-testing clamps taps in blank space (right of the text, or
    // below the last line) to the line-end offset — those always mean
    // caret placement, never an action.
    if (offset >= text.length) return null;
    if (GhostText.mightContain(text) &&
        GhostText.ghostAtOffset(text, offset) != null) {
      return null;
    }
    if (widget.checkboxTapToggle) {
      final item = MarkdownListSyntax.parse(text);
      // The toggle zone starts at the list marker, not the bracket, so
      // fat-finger taps just left of the box still toggle; everything
      // left of the marker is indent and keeps caret placement, and the
      // content right of the box stays editable.
      if (item != null &&
          item.kind == MarkdownListKind.task &&
          offset >= item.indent.length &&
          offset <= item.bracketStart + 3) {
        return () => _toggleTaskLine(lineIndex);
      }
    }
    final onOpenLink = widget.onOpenLink;
    if (onOpenLink != null) {
      final url = _linkUrlAt(text, offset);
      if (url != null) {
        // Tactile confirmation — the caret and keyboard intentionally
        // don't react to an intercepted tap.
        return () {
          HapticFeedback.selectionClick();
          onOpenLink(url);
        };
      }
    }
    final onMoneyTap = widget.onMoneyTap;
    if (onMoneyTap != null && MarkdownMoneySyntax.leadsWithMoney(text)) {
      final money = MarkdownMoneySyntax.parse(text);
      // Only a display row's painted chip (`$$` / `$?` / bare `$!` /
      // `$^` / `$~` — the shared [MarkdownMoneySyntax.isDisplayKind]
      // grouping) is a zone: from the marker up to the amount range
      // (the chip is wider than its two source chars, so the spaces and
      // any concealed accent token ride along); heading hashes,
      // `$^`/`$~` count digits, label text, op lines, and `$! N`
      // declarations stay editable. When a value slot moved the chip
      // into the label, its single `$` is a zone too — the marker keeps
      // its own (it still renders the kind's glyph there), so both the
      // glyph and the value open the sheet while the label around them
      // stays editable. Exactly the slot offset, never the space beside
      // it.
      if (money != null &&
          MarkdownMoneySyntax.isDisplayKind(money.kind) &&
          ((offset >= money.markerStart && offset < money.amountStart) ||
              (money.valueSlot >= 0 && offset == money.valueSlot))) {
        return () {
          HapticFeedback.selectionClick();
          onMoneyTap(lineIndex);
        };
      }
    }
    final onOpenTag = widget.onOpenTag;
    if (onOpenTag != null) {
      final tag = _tagAt(text, offset);
      if (tag != null) {
        return () {
          HapticFeedback.selectionClick();
          onOpenTag(tag);
        };
      }
    }
    return null;
  }

  /// Flips the task checkbox on [lineIndex] as one atomic, undoable
  /// value change. Interception means the tap never moved the selection,
  /// so it is simply kept — toggling never reads as editing.
  void _toggleTaskLine(int lineIndex) {
    final controller = widget.controller;
    final lines = controller.codeLines;
    if (lineIndex >= lines.length) return;
    final lineText = lines[lineIndex].text;
    final current = MarkdownListSyntax.parse(lineText);
    if (current == null || current.kind != MarkdownListKind.task) return;
    // Tactile confirmation — the caret and keyboard intentionally
    // don't react to an intercepted tap.
    HapticFeedback.lightImpact();
    final toggled = lineText.replaceRange(
      current.bracketStart + 1,
      current.bracketStart + 2,
      current.checked ? ' ' : 'x',
    );
    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: CodeLines.of([
          for (int i = 0; i < lines.length; i++)
            if (i == lineIndex) CodeLine(toggled) else lines[i],
        ]),
        selection: controller.selection,
      );
    });
  }

  /// The url of the `[text](url)` link covering [offset] in [text], or
  /// null. Grammar comes from [MarkdownLinkPatterns] (shared with the
  /// span builder's rendering). To stay aligned with what the editor
  /// actually renders as a link: opens preceded by `!` or an odd run of
  /// backslashes never count, brackets inside inline-code backtick runs
  /// never count, and links whose structural chars sit inside ghost runs
  /// never count. The zone excludes the construct's outermost boundary
  /// offsets, so taps that resolve to the edges (including clamped taps
  /// in blank space) still place the caret.
  String? _linkUrlAt(String text, int offset) {
    final ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];
    final codeRuns = _inlineCodeRuns(text);
    var searchFrom = 0;
    while (searchFrom < text.length) {
      final open = text.indexOf('[', searchFrom);
      if (open < 0) return null;
      searchFrom = open + 1;
      if (open > 0) {
        final before = text.codeUnitAt(open - 1);
        if (before == 0x21) continue;
        if (before == 0x5C && _oddBackslashRunBefore(text, open)) continue;
      }
      if (_inRanges(codeRuns, open)) continue;
      final link = MarkdownLinkPatterns.matchInlineLinkAt(text, open);
      if (link == null) continue;
      if (_inGhosts(ghosts, link.textEnd) || _inGhosts(ghosts, link.urlEnd)) {
        continue;
      }
      if (offset <= link.start) return null;
      if (offset < link.end) return link.urlOf(text);
      searchFrom = link.end;
    }
    return null;
  }

  /// The `#tag` (leading `#` kept, as the preview's recognizer passes
  /// it) covering [offset] in [text], or null. Grammar comes from
  /// [MarkdownTagSyntax] — the one module both render surfaces scan
  /// with — so the zone can never claim something the editor did not
  /// paint as a tag: `#` must sit on a word boundary and be followed by
  /// a letter-led body, so heading hashes (`## x`), `#3`, and `set #1`
  /// are never tags. Tags conceal and substitute nothing, so the tapped
  /// offset maps 1:1 onto source code units. Tags inside inline-code
  /// backtick runs never count (code runs render literally), and tags
  /// whose `#` sits in a ghost run never count — ghosts win. Like the
  /// link zone, the construct's outermost boundary offsets are excluded
  /// so taps that resolve to an edge still place the caret.
  String? _tagAt(String text, int offset) {
    final ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];
    final codeRuns = _inlineCodeRuns(text);
    var searchFrom = 0;
    while (searchFrom < text.length) {
      final hash = text.indexOf('#', searchFrom);
      if (hash < 0) return null;
      searchFrom = hash + 1;
      if (!MarkdownTagSyntax.isWordBoundaryBefore(text, hash)) continue;
      final end = MarkdownTagSyntax.tryParseTagAt(text, hash);
      if (end == null) continue;
      if (_inRanges(codeRuns, hash)) continue;
      if (_inGhosts(ghosts, hash)) continue;
      if (offset <= hash) return null;
      if (offset < end) return text.substring(hash, end);
      searchFrom = end;
    }
    return null;
  }

  /// Inline-code backtick runs, mirroring the span builder's `` ` ``
  /// rule (non-empty, no space just inside the opening backtick or
  /// before the closing one): links never render inside them, so taps
  /// there must edit, not open.
  List<(int, int)> _inlineCodeRuns(String text) {
    List<(int, int)>? runs;
    var pos = 0;
    while (true) {
      final tick = text.indexOf('`', pos);
      if (tick < 0) break;
      final innerStart = tick + 1;
      if (innerStart >= text.length ||
          _isSpaceChar(text.codeUnitAt(innerStart))) {
        pos = tick + 1;
        continue;
      }
      var close = text.indexOf('`', innerStart);
      var end = -1;
      while (close != -1) {
        if (close > innerStart && !_isSpaceChar(text.codeUnitAt(close - 1))) {
          end = close;
          break;
        }
        close = text.indexOf('`', close + 1);
      }
      if (end < 0) {
        pos = tick + 1;
        continue;
      }
      (runs ??= []).add((tick, end + 1));
      pos = end + 1;
    }
    return runs ?? const [];
  }

  bool _oddBackslashRunBefore(String text, int index) {
    var count = 0;
    var i = index - 1;
    while (i >= 0 && text.codeUnitAt(i) == 0x5C) {
      count++;
      i--;
    }
    return count.isOdd;
  }

  bool _isSpaceChar(int c) => c == 0x20 || c == 0x09;

  bool _inRanges(List<(int, int)> ranges, int index) {
    for (final (start, end) in ranges) {
      if (index >= start && index < end) return true;
      if (start > index) break;
    }
    return false;
  }

  bool _inGhosts(List<GhostMatch> ghosts, int index) {
    for (final g in ghosts) {
      if (index >= g.start && index < g.end) return true;
      if (g.start > index) break;
    }
    return false;
  }

  /// Drops the engaged-ghost state once the selection leaves the run or
  /// its line's text changes, so a much-later tap on the same ghost
  /// starts fresh in replace mode instead of edit mode.
  void _maybeClearEngagedGhost() {
    if (_engagedGhostLine < 0) return;
    final controller = widget.controller;
    final selection = controller.selection;
    final lines = controller.codeLines;
    if (selection.baseIndex != _engagedGhostLine ||
        selection.extentIndex != _engagedGhostLine ||
        _engagedGhostLine >= lines.length ||
        lines[_engagedGhostLine].text != _engagedGhostText) {
      _clearEngagedGhost();
      return;
    }
    final base = selection.baseOffset;
    final extent = selection.extentOffset;
    final lo = base < extent ? base : extent;
    final hi = base < extent ? extent : base;
    if (lo < _engagedGhostStart || hi > _engagedGhostEnd) {
      _clearEngagedGhost();
    }
  }

  void _clearEngagedGhost() {
    _engagedGhostLine = -1;
    _engagedGhostStart = -1;
    _engagedGhostEnd = -1;
    _engagedGhostText = '';
  }

  /// Overrides re_editor's Tab / Shift-Tab so that, when the caret sits on
  /// a single list item, the whole item is indented / outdented at its
  /// start (the markdown-editor convention) instead of inserting spaces
  /// at the caret. Multi-line selections and non-list lines fall through
  /// to re_editor's default indent behavior.
  late final Map<Type, Action<Intent>> _shortcutOverrides = {
    CodeShortcutIndentIntent: CallbackAction<CodeShortcutIndentIntent>(
      onInvoke: (intent) {
        _onListIndent(outdent: false);
        return null;
      },
    ),
    CodeShortcutOutdentIntent: CallbackAction<CodeShortcutOutdentIntent>(
      onInvoke: (intent) {
        _onListIndent(outdent: true);
        return null;
      },
    ),
  };

  void _onListIndent({required bool outdent}) {
    if (_tryListIndent(outdent: outdent)) return;
    // Not a list line — preserve re_editor's default behavior.
    if (outdent) {
      widget.controller.applyOutdent();
    } else {
      widget.controller.applyIndent();
    }
  }

  /// Indents (or outdents) the current single list line by one [
  /// MarkdownListUtils.indentUnit]. Returns `true` when it handled the
  /// keystroke (the caret was on a list item), `false` to fall back.
  bool _tryListIndent({required bool outdent}) {
    final controller = widget.controller;
    final selection = controller.selection;
    if (!selection.isSameLine) return false;
    final lineIndex = selection.extentIndex;
    final lines = controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) return false;
    final lineText = lines[lineIndex].text;
    if (!MarkdownListUtils.isListLine(lineText)) return false;

    const unit = '  '; // MarkdownListUtils.indentUnit spaces
    final String newText;
    final int delta;
    if (outdent) {
      if (lineText.startsWith(unit)) {
        newText = lineText.substring(2);
        delta = -2;
      } else if (lineText.startsWith(' ') || lineText.startsWith('\t')) {
        newText = lineText.substring(1);
        delta = -1;
      } else {
        // Already at column 0 — consume the key but do nothing.
        return true;
      }
    } else {
      newText = '$unit$lineText';
      delta = 2;
    }

    // Keep the caret on the same content character (never at offset 0,
    // which would make the page's Enter-continuation logic misfire).
    final baseOffset = (selection.baseOffset + delta).clamp(0, newText.length);
    final extentOffset = (selection.extentOffset + delta).clamp(
      0,
      newText.length,
    );

    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: CodeLines.of([
          for (int i = 0; i < lines.length; i++)
            if (i == lineIndex) CodeLine(newText) else lines[i],
        ]),
        selection: CodeLineSelection(
          baseIndex: lineIndex,
          baseOffset: baseOffset,
          extentIndex: lineIndex,
          extentOffset: extentOffset,
        ),
      );
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showDebugOverlay = widget.showChunkColors || widget.showChunkBorders;
    // Account for bottom system navigation bar (gesture bar on phones)
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;

    return Stack(
      children: [
        Listener(
          onPointerUp: _onEditorPointerUp,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildCodeEditor(context),
          ),
        ),
        // Chunk debug overlay - positioned behind scrollbar but above editor
        if (showDebugOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: EditorChunkOverlay(
                scrollController: widget.scrollController,
                editingController: widget.controller,
                linesPerChunk: widget.linesPerChunk,
                fontSize: widget.editorFontSize,
                lineHeight: MarkdownConstants.lineHeight,
                showColors: widget.showChunkColors,
                showBorders: widget.showChunkBorders,
                editorPadding: EdgeInsets.only(
                  left: AppSpacing.lg,
                  top: AppSpacing.lg,
                  right: AppSpacing.lg + AppConstants.editorScrollbarPadding,
                  bottom: AppSpacing.lg + bottomSafeArea,
                ),
              ),
            ),
          ),
        // Scrollbar positioned on the right - uses IgnorePointer except for the thumb area
        if (widget.showScrollIndicator)
          Positioned(
            top: 8,
            bottom: 8,
            right: 0,
            child: KeyedSubtree(
              key: widget.scrollIndicatorKey,
              child: ScrollProgressIndicator(
                scrollController: widget.scrollController.verticalScroller,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCodeEditor(BuildContext context) {
    final theme = Theme.of(context);
    // Account for bottom system navigation bar (gesture bar on phones)
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: CodeEditor(
        controller: widget.controller,
        focusNode: widget.focusNode,
        scrollController: widget.scrollController,
        // Enable mobile selection toolbar (copy/paste/cut/select all)
        toolbarController: _toolbarController,
        style: CodeEditorStyle(
          fontSize: widget.editorFontSize,
          fontFamily: FontConstants.editorFontFamily,
          fontHeight: MarkdownConstants.lineHeight,
          textColor: theme.textTheme.bodyLarge?.color,
          backgroundColor: Colors.transparent,
          cursorColor: theme.colorScheme.primary,
          cursorWidth: 2.5,
          cursorLineColor: widget.showCursorLine
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : null,
          selectionColor: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
        wordWrap: widget.wordWrap,
        readOnly: false,
        autofocus: false,
        tapInterceptor:
            (widget.checkboxTapToggle ||
                widget.onOpenLink != null ||
                widget.onMoneyTap != null ||
                widget.onOpenTag != null)
            ? _tapInterceptor
            : null,
        chunkAnalyzer: const NonCodeChunkAnalyzer(),
        // List-aware Tab / Shift-Tab: indent/outdent the whole list item
        // when the caret is on one; otherwise re_editor's default applies.
        shortcutOverrideActions: _shortcutOverrides,
        // Add small right padding for visible scrollbar (6-12px width)
        // Add bottom safe area to account for phone navigation bar
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          top: AppSpacing.lg,
          right: AppSpacing.lg + AppConstants.editorScrollbarPadding,
          bottom: AppSpacing.lg + bottomSafeArea,
        ),
        indicatorBuilder: widget.showLineNumbers
            ? (context, editingController, chunkController, notifier) {
                return KeyedSubtree(
                  key: widget.lineNumbersKey,
                  child: DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                );
              }
            : null,
        scrollbarBuilder: (context, child, details) => child,
        findBuilder: (context, controller, readOnly) {
          widget.searchController.setFindController(controller);
          return _HiddenFindPanel(controller: controller);
        },
      ),
    );
  }
}

/// A hidden find panel widget that implements PreferredSizeWidget.
/// This allows us to use re_editor's native search highlighting
/// while using our own NoteSearchBar UI for the search interface.
class _HiddenFindPanel extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController? controller;

  const _HiddenFindPanel({required this.controller});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
