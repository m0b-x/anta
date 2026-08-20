import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../constants/app_icon_sizes.dart';
import '../constants/app_spacing.dart';
import '../constants/font_constants.dart';
import '../constants/note_search_metrics.dart';
import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../utils/re_editor_search_controller.dart';
import 'note_match_list_sheet.dart';

class NoteSearchBar extends StatefulWidget {
  final ReEditorSearchController searchController;
  final VoidCallback? onClose;
  final Function(int offset)? onNavigateToMatch;
  final bool showReplaceField;
  final Function(String oldContent, String newContent)? onReplace;

  const NoteSearchBar({
    super.key,
    required this.searchController,
    this.onClose,
    this.onNavigateToMatch,
    this.showReplaceField = false,
    this.onReplace,
  });

  @override
  State<NoteSearchBar> createState() => _NoteSearchBarState();
}

class _CloseSearchIntent extends Intent {
  const _CloseSearchIntent();
}

class _NextMatchIntent extends Intent {
  const _NextMatchIntent();
}

class _PreviousMatchIntent extends Intent {
  const _PreviousMatchIntent();
}

class _NoteSearchBarState extends State<NoteSearchBar>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final TextEditingController _replaceController;
  late final FocusNode _searchFocus;
  late final FocusNode _replaceFocus;
  late final AnimationController _animController;

  Timer? _messageTimer;
  Timer? _navigateTimer;
  bool _showReplace = false;
  bool _hapticsEnabled = true;
  bool _entered = false;
  String? _message;

  ReEditorSearchController get _search => widget.searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: _search.query);
    _replaceController = TextEditingController();
    _searchFocus = FocusNode();
    _replaceFocus = FocusNode();
    _animController = AnimationController(
      duration: NoteSearchMetrics.barAnimation,
      vsync: this,
    );
    _loadHaptics();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Entry animation honours the platform's reduce-motion setting, which is
    // only readable once there is a MediaQuery above us.
    if (!_entered) {
      _entered = true;
      _animController.duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : NoteSearchMetrics.barAnimation;
      _animController.forward();
    }
  }

  Future<void> _loadHaptics() async {
    final settings = await SettingsService.getInstance();
    final enabled = await settings.getHapticFeedback();
    if (mounted) setState(() => _hapticsEnabled = enabled);
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _navigateTimer?.cancel();
    _animController
      ..stop()
      ..dispose();
    _searchController.dispose();
    _replaceController.dispose();
    _searchFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  void _selectionHaptic() {
    if (_hapticsEnabled) HapticFeedback.selectionClick();
  }

  void _onSearch(String value) {
    _search.search(value);
    _clearMessage();
    // Navigating on every keystroke scroll-animates the note once per
    // character; settle first, then reveal the first match.
    _navigateTimer?.cancel();
    if (value.isEmpty) return;
    _navigateTimer = Timer(NoteSearchMetrics.navigateDebounce, () {
      if (mounted) _navigateToCurrent();
    });
  }

  void _navigateToCurrent() {
    final match = _search.currentMatch;
    if (match != null) widget.onNavigateToMatch?.call(match.start);
  }

  void _next() {
    final before = _search.currentMatchIndex;
    _search.nextMatch();
    _afterStep(before, forward: true);
  }

  void _previous() {
    final before = _search.currentMatchIndex;
    _search.previousMatch();
    _afterStep(before, forward: false);
  }

  /// Wrap-around is silent otherwise and reads as a stuck button, so it gets
  /// its own haptic and its own screen-reader announcement.
  void _afterStep(int before, {required bool forward}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final after = _search.currentMatchIndex;
      final wrapped =
          _search.matchCount > 1 && (forward ? after < before : after > before);
      if (wrapped) {
        if (_hapticsEnabled) HapticFeedback.lightImpact();
        final l10n = AppLocalizations.of(context)!;
        SemanticsService.sendAnnouncement(
          View.of(context),
          forward ? l10n.wrappedToFirstMatch : l10n.wrappedToLastMatch,
          Directionality.of(context),
        );
      } else {
        _selectionHaptic();
      }
      _navigateToCurrent();
    });
  }

  Future<void> _openMatchList({bool focusJumpField = false}) async {
    if (!_search.hasMatches) return;
    _selectionHaptic();
    final index = await NoteMatchListSheet.show(
      context,
      searchController: _search,
      hapticsEnabled: _hapticsEnabled,
      focusJumpField: focusJumpField,
    );
    if (!mounted) return;
    // Keep the field focused: the page's keyboard-inset math is gated on the
    // search bar owning focus.
    _searchFocus.requestFocus();
    if (index == null) return;
    _search.goToMatch(index);
    _navigateToCurrent();
  }

  Future<void> _close() async {
    _messageTimer?.cancel();
    _navigateTimer?.cancel();
    await _animController.reverse();
    if (!mounted) return;
    _search.closeSearch();
    widget.onClose?.call();
  }

  /// One trailing button, Android search-view style: it empties a query that
  /// has one, and closes search once there is nothing left to clear.
  void _clearOrClose() {
    if (_searchController.text.isEmpty) {
      _close();
      return;
    }
    _searchController.clear();
    _onSearch('');
    _searchFocus.requestFocus();
  }

  void _clearMessage() {
    _messageTimer?.cancel();
    if (_message != null) setState(() => _message = null);
  }

  void _showMessage(String msg) {
    _messageTimer?.cancel();
    setState(() => _message = msg);
    _messageTimer = Timer(NoteSearchMetrics.messageDuration, () {
      if (mounted) setState(() => _message = null);
    });
  }

  void _replaceCurrent() {
    _search.updateReplacement(_replaceController.text);
    final result = _search.replaceCurrent();
    if (result is ReplaceSuccessState) {
      widget.onReplace?.call('', result.newContent);
      _showMessage(AppLocalizations.of(context)!.replacedCount(1));
    }
  }

  void _replaceAll() {
    if (!_search.hasMatches) return;
    final count = _search.matchCount;
    _search.updateReplacement(_replaceController.text);
    final result = _search.replaceAll();
    if (result is ReplaceSuccessState) {
      widget.onReplace?.call('', result.newContent);
      _showMessage(AppLocalizations.of(context)!.replacedCount(count));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: Container(
        color: colors.surfaceContainer,
        child: SafeArea(
          bottom: false,
          child: FocusTraversalGroup(
            child: Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.escape):
                    _CloseSearchIntent(),
                SingleActivator(LogicalKeyboardKey.enter): _NextMatchIntent(),
                SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    _PreviousMatchIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  _CloseSearchIntent: CallbackAction<_CloseSearchIntent>(
                    onInvoke: (_) {
                      _close();
                      return null;
                    },
                  ),
                  _NextMatchIntent: CallbackAction<_NextMatchIntent>(
                    onInvoke: (_) {
                      if (_search.hasMatches) _next();
                      return null;
                    },
                  ),
                  _PreviousMatchIntent: CallbackAction<_PreviousMatchIntent>(
                    onInvoke: (_) {
                      if (_search.hasMatches) _previous();
                      return null;
                    },
                  ),
                },
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) => ListenableBuilder(
                    listenable: _search,
                    builder: (context, _) => _buildBar(value.text.isNotEmpty),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBar(bool hasQuery) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth <
                  NoteSearchMetrics.compactWidthThreshold;
              final buttonWidth = compact
                  ? NoteSearchMetrics.iconButtonWidthCompact
                  : NoteSearchMetrics.touchTarget;
              return Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      hint: l10n.findInNote,
                      // The magnifier would cost a whole control's width on the
                      // one row; the hint already names the surface.
                      icon: null,
                      compact: compact,
                      onChanged: _onSearch,
                      onSubmitted: (_) {
                        if (_search.hasMatches) _next();
                      },
                      suffix: hasQuery
                          ? _MatchCountChip(
                              currentIndex: _search.currentMatchIndex,
                              matchCount: _search.matchCount,
                              isSearchPending: _search.isSearchPending,
                              hasMatches: _search.hasMatches,
                              compact: compact,
                              onTap: _search.hasMatches ? _openMatchList : null,
                              onLongPress: _search.hasMatches
                                  ? () => _openMatchList(focusJumpField: true)
                                  : null,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // Always mounted, disabled while idle: mounting them with the
                  // first keystroke would reflow the whole trailing cluster.
                  _IconBtn(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: l10n.previous,
                    onPressed: _search.hasMatches ? _previous : null,
                    width: buttonWidth,
                  ),
                  _IconBtn(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: l10n.next,
                    onPressed: _search.hasMatches ? _next : null,
                    width: buttonWidth,
                  ),
                  _OptionsMenu(
                    options: _SearchOptions(
                      caseSensitive: _search.caseSensitive,
                      wholeWord: _search.wholeWord,
                      useRegex: _search.useRegex,
                      showReplace: _showReplace,
                      showReplaceOption: widget.showReplaceField,
                      onToggleCase: _search.toggleCaseSensitive,
                      onToggleWholeWord: _search.toggleWholeWord,
                      onToggleRegex: _search.toggleRegex,
                      onToggleReplace: () =>
                          setState(() => _showReplace = !_showReplace),
                    ),
                  ),
                  _IconBtn(
                    icon: Icons.close_rounded,
                    tooltip: hasQuery ? l10n.clearSearch : l10n.close,
                    onPressed: _clearOrClose,
                    muted: true,
                    width: buttonWidth,
                  ),
                ],
              );
            },
          ),
        ),
        if (_showReplace && widget.showReplaceField)
          _ReplaceRow(
            controller: _replaceController,
            focusNode: _replaceFocus,
            hasMatches: _search.hasMatches,
            onReplaceCurrent: _replaceCurrent,
            onReplaceAll: _replaceAll,
            onChanged: (_) => _clearMessage(),
            message: _message,
          ),
      ],
    );
  }
}

class _SearchOptions {
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;
  final bool showReplace;
  final bool showReplaceOption;
  final VoidCallback onToggleCase;
  final VoidCallback onToggleWholeWord;
  final VoidCallback onToggleRegex;
  final VoidCallback onToggleReplace;

  const _SearchOptions({
    required this.caseSensitive,
    required this.wholeWord,
    required this.useRegex,
    required this.showReplace,
    required this.showReplaceOption,
    required this.onToggleCase,
    required this.onToggleWholeWord,
    required this.onToggleRegex,
    required this.onToggleReplace,
  });

  bool get hasActive =>
      caseSensitive ||
      wholeWord ||
      useRegex ||
      (showReplace && showReplaceOption);
}

/// The match counter, riding inside the field's trailing edge. Numbers only —
/// `noSearchResults` and `searching` survive as tooltip and semantics label
/// but are never laid out, since a sentence here is what starves the query.
///
/// Tap opens the match list, long-press opens it with the number field
/// focused; the tint, the caret and the confined ripple are what keep a chip
/// this small reading as a control rather than as text.
class _MatchCountChip extends StatelessWidget {
  final int currentIndex;
  final int matchCount;
  final bool isSearchPending;
  final bool hasMatches;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _MatchCountChip({
    required this.currentIndex,
    required this.matchCount,
    required this.isSearchPending,
    required this.hasMatches,
    required this.compact,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final Color background;
    final Color foreground;
    if (hasMatches) {
      background = colors.secondaryContainer;
      foreground = colors.onSecondaryContainer;
    } else if (isSearchPending) {
      // Transparent while searching: the chip must not strobe between
      // keystrokes.
      background = Colors.transparent;
      foreground = colors.onSurfaceVariant;
    } else {
      background = colors.errorContainer;
      foreground = colors.onErrorContainer;
    }

    final String semanticsLabel;
    final String tooltip;
    if (isSearchPending) {
      semanticsLabel = l10n.searching;
      tooltip = l10n.searching;
    } else if (hasMatches) {
      semanticsLabel = l10n.matchPosition(currentIndex + 1, matchCount);
      tooltip = l10n.jumpToMatch;
    } else {
      semanticsLabel = l10n.noSearchResults;
      tooltip = l10n.noSearchResults;
    }

    return Semantics(
      button: onTap != null,
      liveRegion: true,
      label: semanticsLabel,
      hint: onTap != null ? l10n.jumpToMatch : null,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : l10n.typeMatchNumber,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        // Manual so long-press belongs to the number field, not the tooltip;
        // pointer hover still shows it on desktop.
        triggerMode: TooltipTriggerMode.manual,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(
            NoteSearchMetrics.counterChipRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              height: NoteSearchMetrics.counterChipHeight,
              constraints: BoxConstraints(
                minWidth: compact
                    ? NoteSearchMetrics.counterMinWidthCompact
                    : NoteSearchMetrics.counterMinWidth,
              ),
              // The rounded cap curves in at the trailing edge, so the caret
              // needs more room there than the digits do at the start.
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.md,
                end: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildValue(foreground),
                  if (onTap != null)
                    Icon(
                      Icons.expand_more_rounded,
                      size: NoteSearchMetrics.counterCaretSize,
                      color: foreground,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValue(Color foreground) {
    if (isSearchPending) {
      return SizedBox(
        width: NoteSearchMetrics.counterCaretSize,
        height: NoteSearchMetrics.counterCaretSize,
        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
      );
    }

    final String label;
    if (hasMatches) {
      final total = matchCount > NoteSearchMetrics.maxDisplayedMatches
          ? '${NoteSearchMetrics.maxDisplayedMatches}+'
          : '$matchCount';
      // Padded so the chip keeps its width while stepping 9 -> 10.
      label = '${'${currentIndex + 1}'.padLeft(total.length)}/$total';
    } else {
      label = '0';
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: NoteSearchMetrics.maxTextScaleForFixedExtent,
      child: Text(
        label,
        style: TextStyle(
          fontSize: FontConstants.caption,
          fontWeight: FontWeight.w600,
          color: foreground,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ReplaceRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasMatches;
  final VoidCallback onReplaceCurrent;
  final VoidCallback onReplaceAll;
  final ValueChanged<String> onChanged;
  final String? message;

  const _ReplaceRow({
    required this.controller,
    required this.focusNode,
    required this.hasMatches,
    required this.onReplaceCurrent,
    required this.onReplaceAll,
    required this.onChanged,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Full-size labels: replacing is a deliberate, destructive-ish action and
    // these read as the primary controls of the row. The trimmed padding is
    // what keeps the field usable next to them on a small phone.
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, NoteSearchMetrics.touchTarget),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: FontConstants.body, fontWeight: FontWeight.w600),
      ),
    );

    return Padding(
      // Starts where the search pill starts, so the two rows line up.
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xs,
        0,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _SearchField(
                  controller: controller,
                  focusNode: focusNode,
                  hint: l10n.replaceWith,
                  icon: Icons.find_replace_rounded,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Intrinsic width, not Flexible: three flex children would split
              // the row in thirds and starve the field.
              OutlinedButton(
                onPressed: hasMatches ? onReplaceCurrent : null,
                style: buttonStyle,
                child: Text(
                  l10n.replaceOne,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton(
                onPressed: hasMatches ? onReplaceAll : null,
                style: buttonStyle,
                child: Text(
                  l10n.replaceAll,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (message != null) _SuccessMessage(message: message!),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData? icon;
  final bool compact;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.icon = Icons.search_rounded,
    this.compact = false,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: NoteSearchMetrics.fieldHeight,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NoteSearchMetrics.fieldRadius),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(fontSize: FontConstants.body, color: colors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: FontConstants.body,
          ),
          prefixIcon: icon == null
              ? null
              : Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.md,
                    end: AppSpacing.sm,
                  ),
                  child: Icon(
                    icon,
                    size: AppIconSizes.small,
                    color: colors.onSurfaceVariant,
                  ),
                ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: NoteSearchMetrics.touchTarget,
            minHeight: NoteSearchMetrics.fieldHeight,
          ),
          // No end padding: the counter is flush with the field's right edge
          // and shares its radius, so the two read as one pill.
          suffixIcon: suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.sm,
                  ),
                  child: suffix,
                ),
          // The suffix carries its own minimum width; a tight box here would
          // clip the counter as the total grows.
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: NoteSearchMetrics.fieldHeight,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsetsDirectional.only(
            start: icon == null ? (compact ? AppSpacing.md : AppSpacing.lg) : 0,
            top: AppSpacing.md,
            bottom: AppSpacing.md,
          ),
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.none,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        spellCheckConfiguration: SpellCheckConfiguration.disabled(),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool muted;
  final double width;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.muted = false,
    this.width = NoteSearchMetrics.touchTarget,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: AppIconSizes.medium,
      color: muted ? colors.onSurfaceVariant : colors.primary,
      disabledColor: colors.onSurface.withValues(alpha: 0.38),
      constraints: BoxConstraints.tightFor(
        width: width,
        height: NoteSearchMetrics.touchTarget,
      ),
      padding: EdgeInsets.zero,
    );
  }
}

class _OptionsMenu extends StatelessWidget {
  final _SearchOptions options;

  const _OptionsMenu({required this.options});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // No `constraints` here: on PopupMenuButton that sizes the popup, not the
    // button. Zero padding leaves IconButton's own 48dp minimum.
    return PopupMenuButton<String>(
      iconSize: AppIconSizes.medium,
      padding: EdgeInsets.zero,
      icon: Stack(
        children: [
          Icon(
            Icons.tune_rounded,
            size: AppIconSizes.medium,
            color: options.hasActive ? colors.primary : colors.onSurfaceVariant,
          ),
          if (options.hasActive)
            PositionedDirectional(
              end: 0,
              top: 0,
              child: Container(
                width: AppSpacing.sm,
                height: AppSpacing.sm,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      tooltip: l10n.options,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteSearchMetrics.sheetRadius),
      ),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'replace':
            options.onToggleReplace();
          case 'case':
            options.onToggleCase();
          case 'whole':
            options.onToggleWholeWord();
          case 'regex':
            options.onToggleRegex();
        }
      },
      itemBuilder: (context) => [
        if (options.showReplaceOption)
          _menuItem(
            'replace',
            l10n.findAndReplace,
            Icons.find_replace_rounded,
            options.showReplace,
            colors,
          ),
        _menuItem(
          'case',
          l10n.matchCase,
          Icons.text_fields_rounded,
          options.caseSensitive,
          colors,
        ),
        _menuItem(
          'whole',
          l10n.wholeWord,
          Icons.abc_rounded,
          options.wholeWord,
          colors,
        ),
        _menuItem(
          'regex',
          l10n.useRegex,
          Icons.code_rounded,
          options.useRegex,
          colors,
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String label,
    IconData icon,
    bool active,
    ColorScheme colors,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: AppIconSizes.small,
            color: active ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: active ? colors.primary : colors.onSurface,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (active)
            Icon(
              Icons.check_rounded,
              size: AppIconSizes.buttonIcon,
              color: colors.primary,
            ),
        ],
      ),
    );
  }
}

class _SuccessMessage extends StatelessWidget {
  final String message;

  const _SuccessMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: AppIconSizes.tiny,
                color: colors.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                message,
                style: TextStyle(
                  fontSize: FontConstants.caption,
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
