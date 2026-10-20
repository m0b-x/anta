import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../constants/form_metrics.dart';
import '../constants/markdown_bar_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/utility_button_config.dart';
import '../models/utility_button_definition.dart';
import '../utils/icon_utils.dart';
import 'form_menu_item.dart';
import 'vocabulary_suggestion_bar.dart';

class MarkdownBar extends StatefulWidget {
  final List<CustomMarkdownShortcut> shortcuts;
  final bool isPreviewMode;
  final bool canUndo;
  final bool canRedo;
  final double previewFontSize;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onPaste;
  final VoidCallback onDecreaseFontSize;
  final VoidCallback onIncreaseFontSize;
  final VoidCallback onSettings;
  final VoidCallback? onShare;
  final VoidCallback? onSwitchBar;
  final VoidCallback? onScrollToTop;
  final VoidCallback? onScrollToBottom;
  final VoidCallback? onCounter;

  /// The list indent a hardware Tab runs, for a soft keyboard that has no
  /// Tab key. Null hides the button, like Paste and Counter: a host
  /// without the edit has no state in which it would ever enable.
  final VoidCallback? onIndent;

  /// Shift-Tab's outdent, as [onIndent]. Null hides the button.
  final VoidCallback? onOutdent;

  /// The caret line's heading level (1–6), or null on a plain line, read
  /// when the heading menu opens so that level shows checked — picking it
  /// again removes the heading. Without a reader the line's level is
  /// unknown: no row is checked and Body text is disabled.
  final int? Function()? currentHeadingLevel;

  /// The app-wide haptics setting. Off silences the reorder mode's
  /// vibrations; the bar has no other haptics of its own.
  final bool hapticsEnabled;

  final Function(CustomMarkdownShortcut) onShortcutPressed;
  final Function(List<CustomMarkdownShortcut>)? onReorderComplete;
  final Function(List<UtilityButtonConfig>)? onUtilityReorderComplete;
  final bool showSettings;
  final bool showBackground;

  /// What a bar drawn without its own background stands on, so its edge
  /// fades blend into that ground; `surface` when null.
  final Color? fadeGround;
  final bool showReorder;

  /// Ratio of toolbar width allocated to the shortcuts section (0.0–1.0).
  /// The utility scroller gets (1 - shortcutRatio); both share what the
  /// pinned undo and redo leave of the bar.
  final double shortcutRatio;

  /// When true, toolbar is split into two independently scrollable sections.
  /// When false, all buttons are in a single horizontally scrollable row.
  final bool splitEnabled;

  /// Configuration for utility button visibility and order.
  /// When null, all utility buttons are shown in the default order.
  final List<UtilityButtonConfig>? utilityConfigs;

  /// While this reports an open session the toolbar shows vocabulary
  /// suggestions in place of the shortcut buttons. Same height either way, so
  /// the swap never shifts the editor. Null disables the feature for this bar.
  final VocabularySuggestionController? suggestions;

  const MarkdownBar({
    super.key,
    required this.shortcuts,
    required this.isPreviewMode,
    required this.canUndo,
    required this.canRedo,
    required this.previewFontSize,
    required this.onUndo,
    required this.onRedo,
    this.onPaste,
    required this.onDecreaseFontSize,
    required this.onIncreaseFontSize,
    required this.onSettings,
    required this.onShortcutPressed,
    this.onShare,
    this.onSwitchBar,
    this.onScrollToTop,
    this.onScrollToBottom,
    this.onCounter,
    this.onIndent,
    this.onOutdent,
    this.currentHeadingLevel,
    this.hapticsEnabled = true,
    this.onReorderComplete,
    this.onUtilityReorderComplete,
    this.showSettings = true,
    this.showBackground = true,
    this.fadeGround,
    this.showReorder = true,
    this.shortcutRatio = 0.7,
    this.splitEnabled = true,
    this.utilityConfigs,
    this.suggestions,
  });

  /// The button row's height, every button's 48 dp square. The suggestion
  /// pills match it, and the pressed ink is a circle this wide.
  static const double rowHeight = MarkdownBarMetrics.buttonSize;

  /// Times the normal bar's button rows were built. Debug builds only.
  /// Exists so a test can pin that a vocabulary session's keystrokes
  /// rebuild the pills alone; nothing in the app reads it.
  @visibleForTesting
  static int debugNormalModeBuildCount = 0;

  @override
  State<MarkdownBar> createState() => _MarkdownBarState();
}

class _MarkdownBarState extends State<MarkdownBar> {
  bool _isReorderMode = false;
  late List<CustomMarkdownShortcut> _reorderableShortcuts;
  late List<UtilityButtonConfig> _reorderableUtilities;

  /// The utility scroller's offset, put back at the start after a tap on a
  /// button inside it so the strip opens the same way every time; the
  /// repeatable buttons ([_repeatableUtilityIds]) keep it.
  final ScrollController _utilityScroll = ScrollController();

  /// Undo and redo sit outside the utility scroller (the review's D2): the
  /// "no lost text" action must never scroll away.
  static const Set<String> _pinnedUtilityIds = {
    UtilityButtonId.undo,
    UtilityButtonId.redo,
  };

  /// Buttons tapped several times in a row: the scroller keeps its offset
  /// after them, so the second tap lands on the same button, not on
  /// whichever one the reset slid under the finger. Indent and outdent
  /// belong here too — nesting a sub-item two levels deep is two taps.
  static const Set<String> _repeatableUtilityIds = {
    UtilityButtonId.decreaseFont,
    UtilityButtonId.increaseFont,
    UtilityButtonId.scrollToTop,
    UtilityButtonId.scrollToBottom,
    UtilityButtonId.indent,
    UtilityButtonId.outdent,
  };

  @override
  void initState() {
    super.initState();
    _reorderableShortcuts = List.from(widget.shortcuts);
    _reorderableUtilities = List.from(
      widget.utilityConfigs ?? UtilityButtonConfig.defaults(),
    );
  }

  @override
  void didUpdateWidget(MarkdownBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isReorderMode) {
      _reorderableShortcuts = List.from(widget.shortcuts);
      _reorderableUtilities = List.from(
        widget.utilityConfigs ?? UtilityButtonConfig.defaults(),
      );
    }
  }

  @override
  void dispose() {
    _utilityScroll.dispose();
    super.dispose();
  }

  void _enterReorderMode() {
    if (widget.hapticsEnabled) HapticFeedback.mediumImpact();
    // The panel needs the height the keyboard holds, and a chip dragged
    // past the caret must not type into the note.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isReorderMode = true;
      _reorderableShortcuts = List.from(widget.shortcuts);
      _reorderableUtilities = List.from(
        widget.utilityConfigs ?? UtilityButtonConfig.defaults(),
      );
    });
  }

  void _exitReorderMode() {
    if (widget.hapticsEnabled) HapticFeedback.lightImpact();
    widget.onReorderComplete?.call(_reorderableShortcuts);
    widget.onUtilityReorderComplete?.call(_reorderableUtilities);
    setState(() {
      _isReorderMode = false;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (widget.hapticsEnabled) HapticFeedback.selectionClick();
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _reorderableShortcuts.removeAt(oldIndex);
      _reorderableShortcuts.insert(newIndex, item);
    });
  }

  Widget _buildVerticalDivider(BuildContext context) {
    return Container(
      width: 1,
      height: MarkdownBarMetrics.dividerHeight,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  /// The ground under the strips' edge fades: the bar's own when it draws
  /// one, the host's when it stands on the host's.
  Color? get _fadeGround => widget.showBackground ? null : widget.fadeGround;

  /// The utility buttons that scroll, behind their edge fade.
  Widget _buildUtilityScroller(List<Widget> buttons) {
    return MarkdownBarEdgeFade(
      ground: _fadeGround,
      child: SingleChildScrollView(
        controller: _utilityScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: MarkdownBarMetrics.sidePadding),
        child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isReorderMode) {
      return CodeEditorTapRegion(child: _buildReorderMode(context));
    }

    final suggestions = widget.suggestions;
    if (suggestions == null || widget.isPreviewMode) {
      return CodeEditorTapRegion(child: _buildNormalMode(context));
    }

    return ValueListenableBuilder<VocabularySuggestionSession?>(
      valueListenable: suggestions,
      // Built once per bar build, outside the builder: a session notifies
      // on every keystroke, and only the pills follow it.
      child: _buildNormalMode(context),
      builder: (context, session, normalMode) {
        // The normal bar stays laid out under a session, hidden, and the
        // suggestions fill its box: the two rows are one height in every
        // locale, text scale and shortcut set, which no shared constant
        // could promise — B, I and H sit on a taller line than the icons.
        return CodeEditorTapRegion(
          child: Stack(
            children: [
              Visibility(
                visible: session == null,
                maintainState: true,
                maintainAnimation: true,
                maintainSize: true,
                child: normalMode!,
              ),
              if (session != null)
                Positioned.fill(
                  child: VocabularySuggestionBar(
                    session: session,
                    onAccept: suggestions.accept,
                    onDismiss: suggestions.dismiss,
                    showBackground: widget.showBackground,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNormalMode(BuildContext context) {
    assert(() {
      MarkdownBar.debugNormalModeBuildCount++;
      return true;
    }());
    final visibleShortcuts = widget.shortcuts
        .where((s) => s.isVisible)
        .toList();

    // Build the utility buttons driven by config (order + visibility). Undo
    // and redo pin in every mode; only a bar with a utility scroller of its
    // own puts that scroller back after a tap.
    final hasUtilityScroller = widget.isPreviewMode || widget.splitEnabled;
    final configs = widget.utilityConfigs ?? UtilityButtonConfig.defaults();
    final pinnedButtons = <Widget>[];
    final utilityButtons = <Widget>[];
    for (final config in configs) {
      if (!config.isVisible) continue;
      final pinned = _pinnedUtilityIds.contains(config.id);
      final button = _buildUtilityButtonWidget(
        context,
        config.id,
        resetsScroll:
            hasUtilityScroller &&
            !pinned &&
            !_repeatableUtilityIds.contains(config.id),
      );
      if (button == null) continue;
      (pinned ? pinnedButtons : utilityButtons).add(button);
    }

    final decoration = widget.showBackground
        ? AppTheme.editorBarDecoration(Theme.of(context).colorScheme)
        : null;

    // In preview mode, no shortcut buttons — utility section expands to full width
    if (widget.isPreviewMode) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.only(
          left: MarkdownBarMetrics.sidePadding,
          top: MarkdownBarMetrics.verticalPadding,
          bottom: MarkdownBarMetrics.verticalPadding,
        ),
        child: Row(
          children: [
            ...pinnedButtons,
            Expanded(child: _buildUtilityScroller(utilityButtons)),
          ],
        ),
      );
    }

    // Build shortcut buttons
    final shortcutButtons = visibleShortcuts
        .map(
          (shortcut) => shortcut.id == 'default_header'
              // The heading menu hangs from its own button, so it needs
              // that button's context rather than the whole bar's.
              ? Builder(
                  builder: (buttonContext) => _ShortcutButton(
                    shortcut: shortcut,
                    onTap: () => _showHeaderMenu(buttonContext),
                  ),
                )
              : _ShortcutButton(
                  shortcut: shortcut,
                  onTap: () => widget.onShortcutPressed(shortcut),
                ),
        )
        .toList();

    // Classic mode: one horizontally scrollable row with every button but
    // undo and redo, which hold the trailing edge past a divider.
    if (!widget.splitEnabled) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.symmetric(
          vertical: MarkdownBarMetrics.verticalPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: MarkdownBarEdgeFade(
                ground: _fadeGround,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: MarkdownBarMetrics.sidePadding,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...shortcutButtons,
                      const SizedBox(
                        width: MarkdownBarMetrics.singleRowDividerGap,
                      ),
                      _buildVerticalDivider(context),
                      const SizedBox(
                        width: MarkdownBarMetrics.singleRowDividerGap,
                      ),
                      ...utilityButtons,
                    ],
                  ),
                ),
              ),
            ),
            if (pinnedButtons.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MarkdownBarMetrics.dividerGap,
                ),
                child: _buildVerticalDivider(context),
              ),
              ...pinnedButtons,
              const SizedBox(width: MarkdownBarMetrics.dividerGap),
            ],
          ],
        ),
      );
    }

    // Split mode: left = shortcuts, right = utility
    // Each section scrolls horizontally independently.
    final ratio = widget.shortcutRatio.clamp(
      AppConstants.minToolbarRatio,
      AppConstants.maxToolbarRatio,
    );

    return Container(
      decoration: decoration,
      padding: const EdgeInsets.symmetric(
        vertical: MarkdownBarMetrics.verticalPadding,
      ),
      child: Row(
        children: [
          // Left section: markdown shortcuts (scrolls independently)
          Expanded(
            flex: (ratio * 100).round(),
            child: MarkdownBarEdgeFade(
              ground: _fadeGround,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(
                  left: MarkdownBarMetrics.sidePadding,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: shortcutButtons,
                ),
              ),
            ),
          ),
          // Divider between sections
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MarkdownBarMetrics.dividerGap,
            ),
            child: _buildVerticalDivider(context),
          ),
          // Undo and redo, then the rest of the utility buttons; the ratio
          // shares out what the pinned pair leaves.
          ...pinnedButtons,
          Expanded(
            flex: ((1.0 - ratio) * 100).round(),
            child: _buildUtilityScroller(utilityButtons),
          ),
        ],
      ),
    );
  }

  /// Builds a single utility button widget for the given [id],
  /// or returns null if contextual conditions prevent showing it. A button
  /// that [resetsScroll] puts the utility scroller back at its start after
  /// its own action.
  Widget? _buildUtilityButtonWidget(
    BuildContext context,
    String id, {
    required bool resetsScroll,
  }) {
    final def = UtilityButtonDefinition.getById(id);
    if (def == null) return null;

    final l10n = AppLocalizations.of(context)!;

    // Per-button visibility gate and callback resolution.
    final VoidCallback? onPressed;
    switch (id) {
      case UtilityButtonId.undo:
        onPressed = widget.canUndo ? widget.onUndo : null;
      case UtilityButtonId.redo:
        onPressed = widget.canRedo ? widget.onRedo : null;
      case UtilityButtonId.paste:
        if (widget.isPreviewMode || widget.onPaste == null) return null;
        onPressed = widget.onPaste;
      case UtilityButtonId.decreaseFont:
        onPressed = widget.onDecreaseFontSize;
      case UtilityButtonId.increaseFont:
        onPressed = widget.onIncreaseFontSize;
      case UtilityButtonId.reorder:
        if (!widget.showReorder ||
            widget.isPreviewMode ||
            widget.onReorderComplete == null) {
          return null;
        }
        onPressed = _enterReorderMode;
      case UtilityButtonId.share:
        if (widget.onShare == null) return null;
        onPressed = widget.onShare;
      case UtilityButtonId.switchBar:
        if (widget.onSwitchBar == null) return null;
        onPressed = widget.onSwitchBar;
      case UtilityButtonId.settings:
        if (!widget.showSettings) return null;
        onPressed = widget.onSettings;
      case UtilityButtonId.scrollToTop:
        onPressed = widget.onScrollToTop;
      case UtilityButtonId.scrollToBottom:
        onPressed = widget.onScrollToBottom;
      case UtilityButtonId.counter:
        if (widget.isPreviewMode || widget.onCounter == null) return null;
        onPressed = widget.onCounter;
      case UtilityButtonId.indent:
        if (widget.isPreviewMode || widget.onIndent == null) return null;
        onPressed = widget.onIndent;
      case UtilityButtonId.outdent:
        if (widget.isPreviewMode || widget.onOutdent == null) return null;
        onPressed = widget.onOutdent;
      default:
        return null;
    }

    final action = onPressed;
    return _ToolbarButton(
      icon: def.icon,
      tooltip: def.label(l10n),
      onPressed: action == null || !resetsScroll
          ? action
          : () {
              action();
              if (_utilityScroll.hasClients) _utilityScroll.jumpTo(0);
            },
    );
  }

  /// Whether the heading menu takes focus from the editor. On a touch
  /// screen it must not: the soft keyboard would close and the caret
  /// line's reveal flip, then both reopen. A hardware keyboard loses
  /// neither, and without focus the menu would let it type into the note.
  static bool get _headingMenuTakesFocus => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
  };

  /// The shortcut the page has always received for a heading [level],
  /// which the applier reads from its [CustomMarkdownShortcut.beforeText].
  static CustomMarkdownShortcut _headingShortcut(int level) =>
      CustomMarkdownShortcut(
        id: 'header_level_$level',
        label: 'H$level',
        iconCodePoint: Icons.tag.codePoint,
        iconFontFamily: 'MaterialIcons',
        beforeText: '${'#' * level} ',
        afterText: '',
        insertType: 'header',
      );

  /// Body text and the six levels as the language's choice menu, centred on
  /// the H button, the caret line's own choice checked. The value is the
  /// level, 0 for body text.
  Future<void> _showHeaderMenu(BuildContext anchor) async {
    final l10n = AppLocalizations.of(anchor)!;
    final colorScheme = Theme.of(anchor).colorScheme;
    final labels = [
      l10n.headingBodyText,
      l10n.header1,
      l10n.header2,
      l10n.header3,
      l10n.header4,
      l10n.header5,
      l10n.header6,
    ];

    // A host without a reader cannot say what the caret line is: no row is
    // checked, and Body text, which needs the line's level to remove it,
    // stays in place disabled.
    final readsLevel = widget.currentHeadingLevel != null;
    final current = widget.currentHeadingLevel?.call();
    final side = FormMenuSide();
    // The keyboard stays up under this menu, so it is capped to the room
    // beside it and scrolls past that. A scaled label wraps beyond any
    // estimate, so there the menu is placed as if it took the whole cap:
    // it may stop short of the button, but never covers it.
    final maxHeight = formMenuMaxHeight(anchor);
    final placedHeight =
        maxHeight.isFinite && MediaQuery.textScalerOf(anchor).scale(1) > 1
        ? maxHeight
        : math.min(formMenuHeight(labels.length), maxHeight);
    final selected = await showMenu<int>(
      context: anchor,
      requestFocus: _headingMenuTakesFocus,
      positionBuilder: (_, constraints) => formMenuPosition(
        anchor,
        constraints,
        menuHeight: placedHeight,
        alignment: FormMenuAlignment.center,
        side: side,
      ),
      color: colorScheme.menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
      ),
      menuPadding: FormMetrics.menuPadding,
      constraints: BoxConstraints(
        minWidth: FormMetrics.menuWidth,
        maxWidth: FormMetrics.menuMaxWidth,
        maxHeight: maxHeight,
      ),
      items: [
        for (var level = 0; level < labels.length; level++)
          FormMenuChoiceItem<int>(
            value: level,
            checked: readsLevel && (current ?? 0) == level,
            enabled: readsLevel || level > 0,
            child: _HeadingMenuRow(
              level: level,
              label: labels[level],
              checked: readsLevel && (current ?? 0) == level,
              enabled: readsLevel || level > 0,
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    // Body text removes the heading through the path the menu always had:
    // the caret line's own level, picked again, drops it. Read again now:
    // on a touch screen the editor keeps its keyboard while the menu is
    // open, so the caret may have moved to another line since. A plain
    // line has nothing to remove.
    final level = selected == 0 ? widget.currentHeadingLevel?.call() : selected;
    if (level == null) return;
    widget.onShortcutPressed(_headingShortcut(level));
  }

  /// German at 2.0 wraps the title into a header taller than the panel's
  /// whole cap while the keyboard is still going down: past [maxHeight]
  /// the title scrolls beside Done, which stays in view as the panel's
  /// only exit.
  Widget _reorderHeader(
    ThemeData theme,
    AppLocalizations l10n, {
    required double maxHeight,
  }) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: MarkdownBarMetrics.reorderHeaderPadding,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    size: MarkdownBarMetrics.reorderHeaderGlyphSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: MarkdownBarMetrics.reorderHeaderGap),
                  Expanded(
                    child: Text(
                      l10n.reorderShortcuts,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: MarkdownBarMetrics.reorderHeaderGap),
          FilledButton(
            onPressed: _exitReorderMode,
            child: Text(l10n.doneReordering),
          ),
        ],
      ),
    );
  }

  Widget _buildReorderMode(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final visibleShortcuts = _reorderableShortcuts
        .where((s) => s.isVisible)
        .toList();
    final visibleUtilities = _reorderableUtilities
        .where((u) => u.isVisible)
        .toList();

    // Read in build: the keyboard's inset falls as the editor lets go of
    // focus, and the panel may take the room it leaves.
    final maxHeight =
        (MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom) *
        MarkdownBarMetrics.reorderPanelMaxShare;

    return Container(
      decoration: AppTheme.editorBarDecoration(theme.colorScheme),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _reorderHeader(
            theme,
            l10n,
            maxHeight: maxHeight * MarkdownBarMetrics.reorderHeaderMaxShare,
          ),
          // Both sections scroll together under the header, which stays.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Shortcuts section
                  MarkdownBarReorderWrap(
                    itemCount: visibleShortcuts.length,
                    onReorder: (oldIndex, newIndex) {
                      final oldFullIndex = _reorderableShortcuts.indexOf(
                        visibleShortcuts[oldIndex],
                      );
                      final newFullIndex = newIndex >= visibleShortcuts.length
                          ? _reorderableShortcuts.indexOf(
                                  visibleShortcuts.last,
                                ) +
                                1
                          : _reorderableShortcuts.indexOf(
                              visibleShortcuts[newIndex],
                            );
                      _onReorder(oldFullIndex, newFullIndex);
                    },
                    hapticsEnabled: widget.hapticsEnabled,
                    itemBuilder: (context, index) => _ReorderableShortcutItem(
                      shortcut: visibleShortcuts[index],
                    ),
                  ),
                  // Utilities section
                  if (visibleUtilities.isNotEmpty) ...[
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    Padding(
                      padding: MarkdownBarMetrics.reorderSectionLabelPadding,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.utilities,
                          style: TextStyle(
                            fontSize:
                                MarkdownBarMetrics.reorderSectionLabelFontSize,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    MarkdownBarReorderWrap(
                      itemCount: visibleUtilities.length,
                      onReorder: (oldIndex, newIndex) {
                        final oldFullIndex = _reorderableUtilities.indexOf(
                          visibleUtilities[oldIndex],
                        );
                        final newFullIndex = newIndex >= visibleUtilities.length
                            ? _reorderableUtilities.indexOf(
                                    visibleUtilities.last,
                                  ) +
                                  1
                            : _reorderableUtilities.indexOf(
                                visibleUtilities[newIndex],
                              );
                        _onUtilityReorder(oldFullIndex, newFullIndex);
                      },
                      hapticsEnabled: widget.hapticsEnabled,
                      itemBuilder: (context, index) => _ReorderableUtilityItem(
                        config: visibleUtilities[index],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onUtilityReorder(int oldIndex, int newIndex) {
    if (widget.hapticsEnabled) HapticFeedback.selectionClick();
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _reorderableUtilities.removeAt(oldIndex);
      _reorderableUtilities.insert(newIndex, item);
    });
  }
}

/// The reorder panel's chips, laid out as wide as the panel allows and
/// wrapped onto as many runs as they need, so no chip or label is ever cut
/// at the right edge in a long language or at a large text scale. It does
/// not scroll itself: the panel's scroll view holds both sections, and a
/// drag near that view's edge scrolls it.
class MarkdownBarReorderWrap extends StatefulWidget {
  final int itemCount;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// The app-wide haptics setting, gating the drag's vibrations.
  final bool hapticsEnabled;

  const MarkdownBarReorderWrap({
    super.key,
    required this.itemCount,
    required this.onReorder,
    required this.itemBuilder,
    this.hapticsEnabled = true,
  });

  @override
  State<MarkdownBarReorderWrap> createState() => _MarkdownBarReorderWrapState();
}

class _MarkdownBarReorderWrapState extends State<MarkdownBarReorderWrap> {
  final Map<int, GlobalKey> _itemKeys = {};
  Timer? _autoScrollTimer;
  int? _draggingIndex;
  int? _targetIndex;
  Offset? _lastDragPosition;

  static const double _edgeScrollThreshold =
      MarkdownBarMetrics.reorderEdgeScrollZone;
  static const double _autoScrollSpeed =
      MarkdownBarMetrics.reorderAutoScrollStep;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _lastDragPosition = details.globalPosition;
    _updateTargetIndex(details.globalPosition);
    _handleAutoScroll(details.globalPosition);
  }

  void _updateTargetIndex(Offset globalPosition) {
    if (!mounted || _draggingIndex == null) return;

    int? newTargetIndex;
    double minDistance = double.infinity;

    for (int i = 0; i < widget.itemCount; i++) {
      if (i == _draggingIndex) continue;

      final key = _itemKeys[i];
      if (key?.currentContext == null) continue;

      final renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;

      final itemPosition = renderBox.localToGlobal(Offset.zero);
      final itemSize = renderBox.size;
      final itemCenter = Offset(
        itemPosition.dx + itemSize.width / 2,
        itemPosition.dy + itemSize.height / 2,
      );

      final distance = (globalPosition - itemCenter).distance;
      if (distance < minDistance) {
        minDistance = distance;
        if (globalPosition.dx < itemCenter.dx ||
            (globalPosition.dy < itemCenter.dy &&
                (globalPosition.dx - itemCenter.dx).abs() <
                    itemSize.width / 2)) {
          newTargetIndex = i;
        } else {
          newTargetIndex = i + 1;
        }
      }
    }

    newTargetIndex ??= widget.itemCount;
    newTargetIndex = newTargetIndex.clamp(0, widget.itemCount);

    if (newTargetIndex != _targetIndex && mounted) {
      if (widget.hapticsEnabled) HapticFeedback.selectionClick();
      setState(() => _targetIndex = newTargetIndex);
    }
  }

  /// Scrolls the panel's scroll view while a drag hovers near its top or
  /// bottom edge, faster the closer it gets. The chips wrap to the panel's
  /// width, so there is no horizontal edge left to scroll.
  void _handleAutoScroll(Offset globalPosition) {
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null || viewport is! RenderBox || !viewport.hasSize) {
      return;
    }

    final dy = viewport.globalToLocal(globalPosition).dy;
    final height = viewport.size.height;

    double deltaY = 0;
    if (dy < _edgeScrollThreshold) {
      final speedMultiplier = 1.0 - (dy / _edgeScrollThreshold).clamp(0.0, 1.0);
      deltaY = -_autoScrollSpeed * (0.5 + speedMultiplier * 0.5);
    } else if (dy > height - _edgeScrollThreshold) {
      final distanceFromEdge = height - dy;
      final speedMultiplier =
          1.0 - (distanceFromEdge / _edgeScrollThreshold).clamp(0.0, 1.0);
      deltaY = _autoScrollSpeed * (0.5 + speedMultiplier * 0.5);
    }

    if (deltaY != 0) {
      _startAutoScroll(scrollable.position, deltaY);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(ScrollPosition position, double deltaY) {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final currentY = position.pixels;
      final newY = (currentY + deltaY).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (newY == currentY) return;
      position.jumpTo(newY);
      // Update target index while scrolling to keep the drop indicator accurate
      if (_lastDragPosition != null && mounted) {
        _updateTargetIndex(_lastDragPosition!);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    for (int i = 0; i < widget.itemCount; i++) {
      _itemKeys.putIfAbsent(i, () => GlobalKey());
    }

    return Padding(
      padding: MarkdownBarMetrics.reorderSectionPadding,
      child: Wrap(
        spacing: MarkdownBarMetrics.reorderChipSpacing,
        runSpacing: MarkdownBarMetrics.reorderChipSpacing,
        children: [
          for (var index = 0; index < widget.itemCount; index++)
            _buildItem(context, index),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final child = widget.itemBuilder(context, index);
    final isDragging = _draggingIndex == index;
    final isTarget = _targetIndex == index;

    // A chip wider than the panel shrinks to it and wraps its label rather
    // than overflowing: the Wrap hands the stack the panel's width. The drop
    // marker is positioned in the spacing before the chip and takes no
    // width, because a wider target would reflow the runs under the finger.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DragTarget<int>(
          key: _itemKeys[index],
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) {
            if (_targetIndex != null) {
              widget.onReorder(details.data, _targetIndex!);
            }
            setState(() {
              _draggingIndex = null;
              _targetIndex = null;
            });
          },
          builder: (context, candidateData, rejectedData) {
            return LongPressDraggable<int>(
              data: index,
              onDragStarted: () {
                if (widget.hapticsEnabled) {
                  HapticFeedback.mediumImpact();
                }
                setState(() => _draggingIndex = index);
              },
              onDragUpdate: _onDragUpdate,
              onDragEnd: (_) {
                _stopAutoScroll();
                setState(() {
                  _draggingIndex = null;
                  _targetIndex = null;
                });
              },
              onDraggableCanceled: (_, _) {
                _stopAutoScroll();
                setState(() {
                  _draggingIndex = null;
                  _targetIndex = null;
                });
              },
              feedback: Material(
                elevation: MarkdownBarMetrics.reorderFeedbackElevation,
                borderRadius: BorderRadius.circular(
                  MarkdownBarMetrics.reorderFeedbackRadius,
                ),
                color: Theme.of(context).colorScheme.surface,
                child: child,
              ),
              childWhenDragging: Opacity(
                opacity: MarkdownBarMetrics.reorderDraggedOpacity,
                child: child,
              ),
              child: Opacity(
                opacity: isDragging
                    ? MarkdownBarMetrics.reorderDraggedOpacity
                    : 1.0,
                child: child,
              ),
            );
          },
        ),
        if (isTarget && _draggingIndex != null && !isDragging)
          Positioned(
            key: const ValueKey('reorder-drop-marker'),
            left:
                -(MarkdownBarMetrics.reorderChipSpacing +
                    MarkdownBarMetrics.reorderDropMarkerWidth) /
                2,
            top: 0,
            bottom: 0,
            width: MarkdownBarMetrics.reorderDropMarkerWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(
                  MarkdownBarMetrics.reorderDropMarkerRadius,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReorderableShortcutItem extends StatelessWidget {
  final CustomMarkdownShortcut shortcut;

  const _ReorderableShortcutItem({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: MarkdownBarMetrics.reorderChipMinHeight,
      ),
      padding: MarkdownBarMetrics.reorderChipPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(
          MarkdownBarMetrics.reorderChipRadius,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.drag_indicator,
            size: MarkdownBarMetrics.reorderChipGlyphSize,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: MarkdownBarMetrics.reorderChipHandleGap),
          _buildIcon(context),
          const SizedBox(width: MarkdownBarMetrics.reorderChipLabelGap),
          Flexible(
            child: Text(
              shortcut.localizedLabel(AppLocalizations.of(context)!),
              style: TextStyle(
                fontSize: MarkdownBarMetrics.reorderChipLabelFontSize,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    if (shortcut.id == 'default_bold') {
      return Text(
        'B',
        style: TextStyle(
          fontSize: MarkdownBarMetrics.reorderChipLetterSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    if (shortcut.id == 'default_italic') {
      return Text(
        'I',
        style: TextStyle(
          fontSize: MarkdownBarMetrics.reorderChipLetterSize,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    if (shortcut.id == 'default_header') {
      return Text(
        'H',
        style: TextStyle(
          fontSize: MarkdownBarMetrics.reorderChipLetterSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    return Icon(
      IconUtils.getIconFromData(
        shortcut.iconCodePoint,
        shortcut.iconFontFamily,
      ),
      size: MarkdownBarMetrics.reorderChipGlyphSize,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}

class _ReorderableUtilityItem extends StatelessWidget {
  final UtilityButtonConfig config;

  const _ReorderableUtilityItem({required this.config});

  @override
  Widget build(BuildContext context) {
    final def = UtilityButtonDefinition.getById(config.id);
    if (def == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(
        minHeight: MarkdownBarMetrics.reorderChipMinHeight,
      ),
      padding: MarkdownBarMetrics.reorderChipPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(
          MarkdownBarMetrics.reorderChipRadius,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.drag_indicator,
            size: MarkdownBarMetrics.reorderChipGlyphSize,
            color: theme.colorScheme.onSecondaryContainer.withValues(
              alpha: MarkdownBarMetrics.reorderChipHandleAlpha,
            ),
          ),
          const SizedBox(width: MarkdownBarMetrics.reorderChipHandleGap),
          Icon(
            def.icon,
            size: MarkdownBarMetrics.reorderChipGlyphSize,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: MarkdownBarMetrics.reorderChipLabelGap),
          Flexible(
            child: Text(
              def.label(l10n),
              style: TextStyle(
                fontSize: MarkdownBarMetrics.reorderChipLabelFontSize,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  final CustomMarkdownShortcut shortcut;
  final VoidCallback onTap;

  const _ShortcutButton({required this.shortcut, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _BarButton(
      tooltip: shortcut.localizedLabel(AppLocalizations.of(context)!),
      onTap: onTap,
      // B, I and H are glyphs like the icons beside them: scaled with the
      // system text size they outgrow the row and the bar grows taller
      // than the suggestion bar that replaces it.
      glyph: MediaQuery.withNoTextScaling(child: _buildButtonContent(context)),
    );
  }

  Widget _buildButtonContent(BuildContext context) {
    if (shortcut.id == 'default_bold') {
      return Text(
        'B',
        style: TextStyle(
          fontSize: MarkdownBarMetrics.letterGlyphSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).iconTheme.color,
        ),
      );
    }
    if (shortcut.id == 'default_italic') {
      return Text(
        'I',
        style: TextStyle(
          fontSize: MarkdownBarMetrics.letterGlyphSize,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).iconTheme.color,
        ),
      );
    }
    if (shortcut.id == 'default_header') {
      return Text(
        'H',
        style: TextStyle(
          fontSize: MarkdownBarMetrics.letterGlyphSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    return Icon(
      IconUtils.getIconFromData(
        shortcut.iconCodePoint,
        shortcut.iconFontFamily,
      ),
      size: MarkdownBarMetrics.glyphSize,
      color: Theme.of(context).iconTheme.color,
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return _BarButton(
      tooltip: tooltip,
      onTap: onPressed,
      glyph: Icon(
        icon,
        size: MarkdownBarMetrics.glyphSize,
        color: onPressed == null
            ? onSurface.withValues(alpha: FormMetrics.disabledOpacity)
            : onSurface,
      ),
    );
  }
}

/// Every bar button: a [MarkdownBarMetrics.buttonSize] square that is all
/// hit area, laid edge to edge with its neighbours so no tap lands on dead
/// bar. The pressed ink is an icon button's circle on its own transparent
/// material, because the bar's decorated surface would paint over the
/// page's, and the ink with it.
///
/// A screen reader hears one node per button — the tooltip, the button
/// role and whether it is enabled — and never the glyph, which for B, I
/// and H is a bare letter that names nothing.
class _BarButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onTap;
  final Widget glyph;

  const _BarButton({
    required this.tooltip,
    required this.onTap,
    required this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: onTap,
            radius: MarkdownBar.rowHeight / 2,
            child: SizedBox.square(
              dimension: MarkdownBarMetrics.buttonSize,
              child: Center(child: ExcludeSemantics(child: glyph)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading menu item: the localized level, the marker it types, so the
/// menu teaches the syntax, and the check on the caret line's own choice.
/// Body text is level 0, with no marker. The check's slot is kept on every
/// row so the markers stand in one column. The marker is decoration to a
/// screen reader, which hears the level and the checked state alone. A
/// disabled label is dimmed here, as `FormMenuItemRow` does, because the
/// theme's menu label style is state-independent.
class _HeadingMenuRow extends StatelessWidget {
  final int level;
  final String label;
  final bool checked;
  final bool enabled;

  const _HeadingMenuRow({
    required this.level,
    required this.label,
    required this.checked,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      identifier: SemanticsIds.editorHeadingLevel(level),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: enabled
                  ? null
                  : TextStyle(
                      color: colorScheme.onSurface.withValues(
                        alpha: FormMetrics.disabledOpacity,
                      ),
                    ),
            ),
          ),
          if (level > 0) ...[
            const SizedBox(width: FormMetrics.gap),
            ExcludeSemantics(
              child: Text(
                '#' * level,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(width: FormMetrics.gap),
          SizedBox.square(
            dimension: FormMetrics.menuIconSize,
            child: checked
                ? Icon(
                    Icons.check_rounded,
                    size: FormMetrics.menuIconSize,
                    color: colorScheme.primary,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The cue that a bar strip scrolls: an edge fades out wherever content
/// lies beyond it, driven by the scroll extent, so a strip that fits shows
/// no fade and one scrolled to its end fades only its start.
class MarkdownBarEdgeFade extends StatefulWidget {
  /// The horizontal scroll view the fade masks.
  final Widget child;

  /// The colour the fade paints over a faded edge — whatever the strip
  /// stands on; the theme's `surface`, the bar's own ground, when null.
  final Color? ground;

  const MarkdownBarEdgeFade({super.key, required this.child, this.ground});

  @override
  State<MarkdownBarEdgeFade> createState() => MarkdownBarEdgeFadeState();
}

/// Public so a test can read which edges fade without decoding a shader.
class MarkdownBarEdgeFadeState extends State<MarkdownBarEdgeFade> {
  bool _fadesStart = false;
  bool _fadesEnd = false;

  /// Whether content lies before the leading edge.
  @visibleForTesting
  bool get fadesStart => _fadesStart;

  /// Whether content lies beyond the trailing edge.
  @visibleForTesting
  bool get fadesEnd => _fadesEnd;

  bool _onMetrics(ScrollMetrics metrics, int depth) {
    if (depth != 0) return false;
    final start = metrics.extentBefore > 0;
    final end = metrics.extentAfter > 0;
    if (start != _fadesStart || end != _fadesEnd) {
      setState(() {
        _fadesStart = start;
        _fadesEnd = end;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ground = widget.ground ?? Theme.of(context).colorScheme.surface;
    // The bar's ground painted over a faded edge, not a mask: a ShaderMask
    // is a saveLayer per strip on every frame the bar composites, even with
    // nothing to fade. The strip stays the Stack's first child, so an edge
    // coming and going never rebuilds the scroll view or loses its offset.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics, n.depth),
        // A narrow split strip fading at both ends keeps its middle clear:
        // neither fade reaches past half the strip.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final extent = math.min(
              MarkdownBarMetrics.edgeFadeExtent,
              constraints.maxWidth / 2,
            );
            return Stack(
              fit: StackFit.passthrough,
              children: [
                widget.child,
                if (_fadesStart)
                  _edge(start: true, ground: ground, extent: extent),
                if (_fadesEnd)
                  _edge(start: false, ground: ground, extent: extent),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _edge({
    required bool start,
    required Color ground,
    required double extent,
  }) {
    return Positioned(
      left: start ? 0 : null,
      right: start ? null : 0,
      top: 0,
      bottom: 0,
      width: extent,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradientFor(start: start, ground: ground),
          ),
        ),
      ),
    );
  }

  /// The overlay on one faded edge: the bar's [ground] at the edge, clear
  /// [MarkdownBarMetrics.edgeFadeExtent] in.
  static LinearGradient gradientFor({
    required bool start,
    required Color ground,
  }) {
    return LinearGradient(
      begin: start ? Alignment.centerLeft : Alignment.centerRight,
      end: start ? Alignment.centerRight : Alignment.centerLeft,
      colors: [ground, ground.withValues(alpha: 0)],
    );
  }
}
