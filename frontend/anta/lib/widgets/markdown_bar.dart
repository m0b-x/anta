import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../constants/form_metrics.dart';
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
  /// again removes the heading. Null reports no level.
  final int? Function()? currentHeadingLevel;

  /// The app-wide haptics setting. Off silences the reorder mode's
  /// vibrations; the bar has no other haptics of its own.
  final bool hapticsEnabled;

  final Function(CustomMarkdownShortcut) onShortcutPressed;
  final Function(List<CustomMarkdownShortcut>)? onReorderComplete;
  final Function(List<UtilityButtonConfig>)? onUtilityReorderComplete;
  final bool showSettings;
  final bool showBackground;
  final bool showReorder;

  /// Ratio of toolbar width allocated to the shortcuts section (0.0–1.0).
  /// The utility section (undo/redo/settings/etc.) gets (1 - shortcutRatio).
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
    this.showReorder = true,
    this.shortcutRatio = 0.7,
    this.splitEnabled = true,
    this.utilityConfigs,
    this.suggestions,
  });

  /// An icon button's height: a 20 px glyph in its 10 px padding. The
  /// suggestion pills match it, and the pressed ink is a circle this wide.
  static const double rowHeight =
      AppConstants.markdownToolbarIconSize +
      2 * AppConstants.markdownToolbarButtonPadding;

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

  void _enterReorderMode() {
    if (widget.hapticsEnabled) HapticFeedback.mediumImpact();
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
      height: 24,
      color: Theme.of(context).colorScheme.outlineVariant,
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

    // Build the utility buttons driven by config (order + visibility).
    final configs = widget.utilityConfigs ?? UtilityButtonConfig.defaults();
    final utilityButtons = <Widget>[];
    for (final config in configs) {
      if (!config.isVisible) continue;
      final button = _buildUtilityButtonWidget(context, config.id);
      if (button != null) {
        if (utilityButtons.isNotEmpty) {
          utilityButtons.add(const SizedBox(width: 4));
        }
        utilityButtons.add(button);
      }
    }

    final utilityContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: utilityButtons,
    );

    final decoration = widget.showBackground
        ? AppTheme.editorBarDecoration(Theme.of(context).colorScheme)
        : null;

    // In preview mode, no shortcut buttons — utility section expands to full width
    if (widget.isPreviewMode) {
      return Container(
        decoration: decoration,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: AppTheme.editorBarVerticalPadding,
          ),
          child: utilityContent,
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

    // Classic mode: single horizontally scrollable row with all buttons
    if (!widget.splitEnabled) {
      return Container(
        decoration: decoration,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: AppTheme.editorBarVerticalPadding,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...shortcutButtons,
              const SizedBox(width: 8),
              _buildVerticalDivider(context),
              const SizedBox(width: 8),
              ...utilityButtons,
            ],
          ),
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
        vertical: AppTheme.editorBarVerticalPadding,
      ),
      child: Row(
        children: [
          // Left section: markdown shortcuts (scrolls independently)
          Expanded(
            flex: (ratio * 100).round(),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: shortcutButtons,
              ),
            ),
          ),
          // Divider between sections
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildVerticalDivider(context),
          ),
          // Right section: utility buttons (scrolls independently)
          Expanded(
            flex: ((1.0 - ratio) * 100).round(),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              child: utilityContent,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single utility button widget for the given [id],
  /// or returns null if contextual conditions prevent showing it.
  Widget? _buildUtilityButtonWidget(BuildContext context, String id) {
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

    return _ToolbarButton(
      icon: def.icon,
      tooltip: def.label(l10n),
      onPressed: onPressed,
    );
  }

  /// The six levels as the language's choice menu, centred on the H button.
  /// Each item carries the same shortcut the page has always received —
  /// its level is read from [CustomMarkdownShortcut.beforeText].
  Future<void> _showHeaderMenu(BuildContext anchor) async {
    final l10n = AppLocalizations.of(anchor)!;
    final colorScheme = Theme.of(anchor).colorScheme;
    final labels = [
      l10n.header1,
      l10n.header2,
      l10n.header3,
      l10n.header4,
      l10n.header5,
      l10n.header6,
    ];
    final headerShortcuts = List.generate(6, (i) {
      final level = i + 1;
      return CustomMarkdownShortcut(
        id: 'header_level_$level',
        label: 'H$level',
        iconCodePoint: Icons.tag.codePoint,
        iconFontFamily: 'MaterialIcons',
        beforeText: '${'#' * level} ',
        afterText: '',
        insertType: 'header',
      );
    });

    final current = widget.currentHeadingLevel?.call();
    final selected = await showMenu<CustomMarkdownShortcut>(
      context: anchor,
      // The editor keeps focus under the menu: taking it would close the
      // keyboard and flip the caret line's reveal, then reopen both.
      requestFocus: false,
      positionBuilder: (_, constraints) => formMenuPosition(
        anchor,
        constraints,
        menuHeight: formMenuHeight(headerShortcuts.length),
        alignment: FormMenuAlignment.center,
      ),
      color: colorScheme.menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
      ),
      menuPadding: FormMetrics.menuPadding,
      constraints: const BoxConstraints(
        minWidth: FormMetrics.menuWidth,
        maxWidth: FormMetrics.menuMaxWidth,
      ),
      items: [
        for (var i = 0; i < headerShortcuts.length; i++)
          FormMenuChoiceItem<CustomMarkdownShortcut>(
            value: headerShortcuts[i],
            checked: current == i + 1,
            child: _HeadingMenuRow(
              level: i + 1,
              label: labels[i],
              marker: headerShortcuts[i].beforeText.trim(),
            ),
          ),
      ],
    );
    if (selected != null && mounted) {
      widget.onShortcutPressed(selected);
    }
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

    return Container(
      decoration: AppTheme.editorBarDecoration(theme.colorScheme),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.reorderShortcuts,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _exitReorderMode,
                  child: Text(l10n.doneReordering),
                ),
              ],
            ),
          ),
          // Shortcuts section
          HorizontalReorderableList(
            itemCount: visibleShortcuts.length,
            onReorder: (oldIndex, newIndex) {
              final oldFullIndex = _reorderableShortcuts.indexOf(
                visibleShortcuts[oldIndex],
              );
              final newFullIndex = newIndex >= visibleShortcuts.length
                  ? _reorderableShortcuts.indexOf(visibleShortcuts.last) + 1
                  : _reorderableShortcuts.indexOf(visibleShortcuts[newIndex]);
              _onReorder(oldFullIndex, newFullIndex);
            },
            hapticsEnabled: widget.hapticsEnabled,
            itemBuilder: (context, index) =>
                _ReorderableShortcutItem(shortcut: visibleShortcuts[index]),
          ),
          // Utilities section
          if (visibleUtilities.isNotEmpty) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.utilities,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            HorizontalReorderableList(
              itemCount: visibleUtilities.length,
              onReorder: (oldIndex, newIndex) {
                final oldFullIndex = _reorderableUtilities.indexOf(
                  visibleUtilities[oldIndex],
                );
                final newFullIndex = newIndex >= visibleUtilities.length
                    ? _reorderableUtilities.indexOf(visibleUtilities.last) + 1
                    : _reorderableUtilities.indexOf(visibleUtilities[newIndex]);
                _onUtilityReorder(oldFullIndex, newFullIndex);
              },
              hapticsEnabled: widget.hapticsEnabled,
              itemBuilder: (context, index) =>
                  _ReorderableUtilityItem(config: visibleUtilities[index]),
            ),
          ],
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

class HorizontalReorderableList extends StatefulWidget {
  final int itemCount;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int itemsPerRow;

  /// The app-wide haptics setting, gating the drag's vibrations.
  final bool hapticsEnabled;

  const HorizontalReorderableList({
    super.key,
    required this.itemCount,
    required this.onReorder,
    required this.itemBuilder,
    this.itemsPerRow = 3,
    this.hapticsEnabled = true,
  });

  @override
  State<HorizontalReorderableList> createState() =>
      _HorizontalReorderableListState();
}

class _HorizontalReorderableListState extends State<HorizontalReorderableList> {
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  Timer? _autoScrollTimer;
  int? _draggingIndex;
  int? _targetIndex;
  Offset? _lastDragPosition;

  static const double _edgeScrollThreshold = 60.0;
  static const double _autoScrollSpeed = 12.0;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
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

  void _handleAutoScroll(Offset globalPosition) {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(globalPosition);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    double deltaX = 0;
    double deltaY = 0;

    // Check horizontal scrolling - use both local bounds and screen edges
    if (localPosition.dx < _edgeScrollThreshold ||
        globalPosition.dx < _edgeScrollThreshold) {
      // Calculate scroll speed based on how close to edge (faster when closer)
      final distanceFromEdge = localPosition.dx < _edgeScrollThreshold
          ? localPosition.dx
          : globalPosition.dx;
      final speedMultiplier =
          1.0 - (distanceFromEdge / _edgeScrollThreshold).clamp(0.0, 1.0);
      deltaX = -_autoScrollSpeed * (0.5 + speedMultiplier * 0.5);
    } else if (localPosition.dx > size.width - _edgeScrollThreshold ||
        globalPosition.dx > screenSize.width - _edgeScrollThreshold) {
      final distanceFromEdge =
          localPosition.dx > size.width - _edgeScrollThreshold
          ? size.width - localPosition.dx
          : screenSize.width - globalPosition.dx;
      final speedMultiplier =
          1.0 - (distanceFromEdge / _edgeScrollThreshold).clamp(0.0, 1.0);
      deltaX = _autoScrollSpeed * (0.5 + speedMultiplier * 0.5);
    }

    // Check vertical scrolling
    if (localPosition.dy < _edgeScrollThreshold) {
      final speedMultiplier =
          1.0 - (localPosition.dy / _edgeScrollThreshold).clamp(0.0, 1.0);
      deltaY = -_autoScrollSpeed * (0.5 + speedMultiplier * 0.5);
    } else if (localPosition.dy > size.height - _edgeScrollThreshold) {
      final distanceFromEdge = size.height - localPosition.dy;
      final speedMultiplier =
          1.0 - (distanceFromEdge / _edgeScrollThreshold).clamp(0.0, 1.0);
      deltaY = _autoScrollSpeed * (0.5 + speedMultiplier * 0.5);
    }

    if (deltaX != 0 || deltaY != 0) {
      _startAutoScroll(deltaX, deltaY);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(double deltaX, double deltaY) {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      bool scrolled = false;

      if (deltaX != 0 && _horizontalScrollController.hasClients) {
        final currentX = _horizontalScrollController.offset;
        final newX = (currentX + deltaX).clamp(
          0.0,
          _horizontalScrollController.position.maxScrollExtent,
        );
        if (newX != currentX) {
          _horizontalScrollController.jumpTo(newX);
          scrolled = true;
        }
      }

      if (deltaY != 0 && _verticalScrollController.hasClients) {
        final currentY = _verticalScrollController.offset;
        final newY = (currentY + deltaY).clamp(
          0.0,
          _verticalScrollController.position.maxScrollExtent,
        );
        if (newY != currentY) {
          _verticalScrollController.jumpTo(newY);
          scrolled = true;
        }
      }

      // Update target index while scrolling to keep the drop indicator accurate
      if (scrolled && _lastDragPosition != null && mounted) {
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

    final rows = <List<int>>[];
    for (var i = 0; i < widget.itemCount; i += widget.itemsPerRow) {
      final end = (i + widget.itemsPerRow > widget.itemCount)
          ? widget.itemCount
          : i + widget.itemsPerRow;
      rows.add(List.generate(end - i, (j) => i + j));
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        controller: _verticalScrollController,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final indices = entry.value;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: rowIndex < rows.length - 1 ? 8 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: indices.asMap().entries.map((itemEntry) {
                    final indexInRow = itemEntry.key;
                    final index = itemEntry.value;
                    final child = widget.itemBuilder(context, index);
                    final isDragging = _draggingIndex == index;
                    final isTarget = _targetIndex == index;

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTarget && _draggingIndex != null && !isDragging)
                          Container(
                            width: 4,
                            height: 44,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        DragTarget<int>(
                          key: _itemKeys[index],
                          onWillAcceptWithDetails: (details) =>
                              details.data != index,
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
                                elevation: 8,
                                borderRadius: BorderRadius.circular(12),
                                color: Theme.of(context).colorScheme.surface,
                                child: child,
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: child,
                              ),
                              child: Opacity(
                                opacity: isDragging ? 0.3 : 1.0,
                                child: child,
                              ),
                            );
                          },
                        ),
                        if (indexInRow < indices.length - 1)
                          const SizedBox(width: 8),
                      ],
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ReorderableShortcutItem extends StatelessWidget {
  final CustomMarkdownShortcut shortcut;

  const _ReorderableShortcutItem({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.drag_indicator,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          _buildIcon(context),
          const SizedBox(width: 8),
          Text(
            shortcut.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
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
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    if (shortcut.id == 'default_italic') {
      return Text(
        'I',
        style: TextStyle(
          fontSize: 16,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
    }
    if (shortcut.id == 'default_header') {
      return Text(
        'H',
        style: TextStyle(
          fontSize: 16,
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
      size: 18,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.drag_indicator,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer.withValues(
              alpha: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            def.icon,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            def.label(l10n),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSecondaryContainer,
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
    return Tooltip(
      message: _label(AppLocalizations.of(context)!),
      preferBelow: false,
      child: _BarInk(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(
            AppConstants.markdownToolbarButtonPadding,
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AppConstants.markdownToolbarButtonMargin,
          ),
          // B, I and H are glyphs like the icons beside them: scaled with
          // the system text size they outgrow the 40 px row and the bar
          // grows taller than the suggestion bar that replaces it.
          child: MediaQuery.withNoTextScaling(
            child: _buildButtonContent(context),
          ),
        ),
      ),
    );
  }

  /// A built-in shortcut's name in the app's language. Built-ins cannot be
  /// renamed, so the stored English label is only ever the seed's; a
  /// user's own shortcut keeps the label they gave it.
  String _label(AppLocalizations l10n) => switch (shortcut.id) {
    'default_bold' => l10n.bold,
    'default_italic' => l10n.italic,
    'default_header' => l10n.headers,
    'default_point_list' => l10n.pointList,
    'default_strikethrough' => l10n.strikethrough,
    'default_highlight' => l10n.shortcutHighlight,
    'default_bullet_list' => l10n.bulletList,
    'default_numbered_list' => l10n.numberedList,
    'default_checkbox' => l10n.checkbox,
    'default_quote' => l10n.quote,
    'default_callout' => l10n.shortcutCallout,
    'default_inline_code' => l10n.inlineCode,
    'default_code_block' => l10n.codeBlock,
    'default_link' => l10n.link,
    'default_checked_checkbox' => l10n.shortcutCheckedCheckbox,
    'default_table' => l10n.shortcutTable,
    'default_horizontal_rule' => l10n.shortcutHorizontalRule,
    'default_image' => l10n.shortcutImage,
    'default_date' => l10n.currentDate,
    'default_ghost' => l10n.shortcutGhostText,
    'default_color_text' => l10n.shortcutColorText,
    'default_color_highlight' => l10n.shortcutColorHighlight,
    'default_money' => l10n.shortcutMoneyAdd,
    'default_money_subtract' => l10n.shortcutMoneySubtract,
    'default_money_multiply' => l10n.shortcutMoneyMultiply,
    'default_money_divide' => l10n.shortcutMoneyDivide,
    'default_money_set' => l10n.shortcutMoneyStart,
    'default_money_total' => l10n.shortcutMoneyTotal,
    'default_money_delta' => l10n.shortcutMoneyChange,
    'default_money_target' => l10n.shortcutMoneyTarget,
    'default_money_diff' => l10n.shortcutMoneyDiff,
    'default_money_span' => l10n.shortcutMoneySpan,
    _ => shortcut.label,
  };

  Widget _buildButtonContent(BuildContext context) {
    if (shortcut.id == 'default_bold') {
      return Text(
        'B',
        style: TextStyle(
          fontSize: AppConstants.markdownToolbarTextSize,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).iconTheme.color,
        ),
      );
    }
    if (shortcut.id == 'default_italic') {
      return Text(
        'I',
        style: TextStyle(
          fontSize: AppConstants.markdownToolbarTextSize,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).iconTheme.color,
        ),
      );
    }
    if (shortcut.id == 'default_header') {
      return Text(
        'H',
        style: TextStyle(
          fontSize: AppConstants.markdownToolbarTextSize,
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
      size: AppConstants.markdownToolbarIconSize,
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
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: _BarInk(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.markdownToolbarButtonMargin,
          ),
          child: Container(
            padding: const EdgeInsets.all(
              AppConstants.markdownToolbarButtonPadding,
            ),
            child: Icon(
              icon,
              size: AppConstants.markdownToolbarIconSize,
              color: onPressed == null
                  ? Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// The pressed feedback every bar button shows: an icon button's circular
/// ink, drawn on its own transparent material because the bar's decorated
/// surface would paint over the page's, and the ink with it. The tap target
/// stays the child's whole box.
class _BarInk extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _BarInk({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        radius: MarkdownBar.rowHeight / 2,
        child: child,
      ),
    );
  }
}

/// A heading menu item: the localized level and, at the trailing edge, the
/// marker it types, so the menu teaches the syntax. The marker is decoration
/// to a screen reader, which hears the level alone.
class _HeadingMenuRow extends StatelessWidget {
  final int level;
  final String label;
  final String marker;

  const _HeadingMenuRow({
    required this.level,
    required this.label,
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: SemanticsIds.editorHeadingLevel(level),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: FormMetrics.gap),
          ExcludeSemantics(
            child: Text(
              marker,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
