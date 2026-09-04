import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/font_constants.dart';
import '../constants/markdown_constants.dart';
import '../utils/editor_input_policy.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
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

  /// The palette the span builder renders with, so tap zones resolve
  /// nested `{name:…}` runs exactly as drawn.
  final MarkdownColorPalette colorPalette;

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
    this.colorPalette = MarkdownColorPalette.presets,
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

  /// The ghost two-tap state machine. Armed by a pointer-up over the
  /// editor and consumed by the next caret change, so only a *tap* (not
  /// arrow-key navigation, which fires no pointer event) can engage a
  /// ghost. The arming auto-expires so a stale tap can't trigger a
  /// much-later keyboard caret move.
  final GhostEngagement _ghostEngagement = GhostEngagement();
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
          _ghostEngagement.disarm();
          _ghostTapExpiry?.cancel();
          _consumeTapAction(position)?.call();
          // On desktop the editor's inner Listener dispatches this
          // pointer-up before this widget's outer Listener re-arms the
          // flag, so disarm once more after routing finishes.
          scheduleMicrotask(() {
            _ghostEngagement.disarm();
            _ghostTapExpiry?.cancel();
          });
        },
      );

  static const Duration _ghostTapWindow = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _toolbarController = MobileSelectionToolbarController(
      builder: _buildSelectionToolbar,
    );
  }

  /// Rebinds to a swapped-in controller: the page may hand the wrapper a
  /// different document (another note, or a reload) without remounting,
  /// and a listener left on the old controller would report the wrong
  /// document's edits. The pending tap claim and the ghost engagement
  /// both describe the old document, so both are dropped. A swapped
  /// search controller is unbound here; the new one re-binds itself
  /// through `findBuilder` on the next build.
  @override
  void didUpdateWidget(covariant ModernEditorWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _tapClaim = null;
      _ghostTapExpiry?.cancel();
      _ghostEngagement.reset();
    }
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.clearFindController();
    }
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
    _ghostEngagement.arm();
    _ghostTapExpiry?.cancel();
    _ghostTapExpiry = Timer(_ghostTapWindow, _ghostEngagement.disarm);
  }

  /// Applies [GhostEngagement]'s verdict on the new caret position: the
  /// whole-run selection is set in a microtask so we never reenter the
  /// controller from within its own notification, and
  /// [_activatingGhost] keeps a second activation from starting while
  /// one is in flight.
  void _handleGhostCaretChange() {
    final controller = widget.controller;
    final selection = controller.selection;
    final decision = _ghostEngagement.caretChanged(
      selection: selection,
      lineText: _lineTextAt(selection.baseIndex),
    );
    switch (decision) {
      case GhostNone():
        return;
      case GhostEditInPlace():
        _ghostTapExpiry?.cancel();
      case GhostSelectRun(:final lineIndex, :final start, :final end):
        _ghostTapExpiry?.cancel();
        if (_activatingGhost) return;
        _activatingGhost = true;
        scheduleMicrotask(() {
          if (!mounted) {
            _activatingGhost = false;
            return;
          }
          controller.selection = CodeLineSelection(
            baseIndex: lineIndex,
            baseOffset: start,
            extentIndex: lineIndex,
            extentOffset: end,
          );
          _activatingGhost = false;
        });
    }
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
    _handleGhostCaretChange();
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
    final lineIndex = position.index;
    final onOpenLink = widget.onOpenLink;
    final onMoneyTap = widget.onMoneyTap;
    final onOpenTag = widget.onOpenTag;
    final action = EditorInputPolicy.resolveTap(
      lineText: _lineTextAt(lineIndex),
      lineIndex: lineIndex,
      offset: position.offset,
      lineRevealed: MarkdownEditorSpanBuilder.selectionCoversLine(
        widget.controller.selection,
        lineIndex,
      ),
      inFence: widget.isFenceLine?.call(lineIndex) ?? false,
      zones: EditorTapZones(
        checkbox: widget.checkboxTapToggle,
        links: onOpenLink != null,
        money: onMoneyTap != null,
        tags: onOpenTag != null,
        palette: widget.colorPalette,
      ),
    );
    // The toggle's haptic rides in [_toggleTaskLine], beside the edit it
    // confirms; the three openers confirm here. Either way the tactile
    // click is the only feedback an intercepted tap gives — the caret and
    // the keyboard intentionally don't react.
    return switch (action) {
      null => null,
      EditorToggleTaskAction(:final lineIndex) => () => _toggleTaskLine(
        lineIndex,
      ),
      EditorOpenLinkAction(:final url) => () {
        HapticFeedback.selectionClick();
        onOpenLink?.call(url);
      },
      EditorOpenMoneyAction(:final lineIndex) => () {
        HapticFeedback.selectionClick();
        onMoneyTap?.call(lineIndex);
      },
      EditorOpenTagAction(:final tag) => () {
        HapticFeedback.selectionClick();
        onOpenTag?.call(tag);
      },
    };
  }

  /// Flips the task checkbox on [lineIndex] as one atomic, undoable
  /// value change. Interception means the tap never moved the selection,
  /// so it is simply kept — toggling never reads as editing.
  void _toggleTaskLine(int lineIndex) {
    final controller = widget.controller;
    final lines = controller.codeLines;
    if (lineIndex >= lines.length) return;
    final toggled = EditorInputPolicy.toggledTaskLine(lines[lineIndex].text);
    if (toggled == null) return;
    HapticFeedback.lightImpact();
    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: lines.replaceLine(
          lineIndex,
          lines[lineIndex].copyWith(text: toggled),
        ),
        selection: controller.selection,
      );
    });
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
    final indent = EditorInputPolicy.listIndent(
      lineText: lines[lineIndex].text,
      outdent: outdent,
    );
    if (indent == null) return false;
    // Already at column 0 — consume the key but do nothing.
    if (indent.delta == 0) return true;

    final newText = indent.text;
    // Keep the caret on the same content character (never at offset 0,
    // which would make the page's Enter-continuation logic misfire).
    final baseOffset = (selection.baseOffset + indent.delta).clamp(
      0,
      newText.length,
    );
    final extentOffset = (selection.extentOffset + indent.delta).clamp(
      0,
      newText.length,
    );

    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: lines.replaceLine(
          lineIndex,
          lines[lineIndex].copyWith(text: newText),
        ),
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
          return const _HiddenFindPanel();
        },
      ),
    );
  }
}

/// A hidden find panel widget that implements PreferredSizeWidget.
/// This allows us to use re_editor's native search highlighting
/// while using our own NoteSearchBar UI for the search interface.
///
/// The fork hands the `findBuilder` a [CodeFindController]; the search UI
/// lives in the page's own `NoteSearchBar`, which the builder wires up
/// before returning, so this panel needs nothing from it.
class _HiddenFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const _HiddenFindPanel();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
