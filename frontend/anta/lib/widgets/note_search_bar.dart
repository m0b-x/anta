import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../utils/re_editor_search_controller.dart';

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

class _NoteSearchBarState extends State<NoteSearchBar>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final TextEditingController _replaceController;
  late final FocusNode _searchFocus;
  late final FocusNode _replaceFocus;
  late final AnimationController _animController;

  bool _showReplace = false;
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
      duration: const Duration(milliseconds: 200),
      vsync: this,
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _searchController.dispose();
    _replaceController.dispose();
    _searchFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _search.search(value);
    _clearMessage();
    // Automatically navigate to first match after search completes
    if (value.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToCurrent();
      });
    }
  }

  void _navigateToCurrent() {
    final match = _search.currentMatch;
    if (match != null) widget.onNavigateToMatch?.call(match.start);
  }

  void _next() {
    _search.nextMatch();
    // Schedule navigation after nextMatch() updates the current index
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToCurrent();
    });
  }

  void _previous() {
    _search.previousMatch();
    // Schedule navigation after previousMatch() updates the current index
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToCurrent();
    });
  }

  Future<void> _close() async {
    await _animController.reverse();
    _search.closeSearch();
    widget.onClose?.call();
  }

  void _clearMessage() {
    if (_message != null) setState(() => _message = null);
  }

  void _showMessage(String msg) {
    setState(() => _message = msg);
    Future.delayed(const Duration(seconds: 2), _clearMessage);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animController,
              curve: Curves.easeOutCubic,
            ),
          ),
      child: ListenableBuilder(
        listenable: _search,
        builder: (context, _) => Container(
          decoration: BoxDecoration(
            color: isDark ? colors.surfaceContainerHighest : colors.surface,
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SearchRow(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearch,
                  onNext: _next,
                  onPrevious: _previous,
                  onClose: _close,
                  hasQuery: _searchController.text.isNotEmpty,
                  hasMatches: _search.hasMatches,
                  hasMoreMatches: _search.hasMoreMatches,
                  isSearchPending: _search.isSearchPending,
                  currentIndex: _search.currentMatchIndex,
                  matchCount: _search.matchCount,
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
            ),
          ),
        ),
      ),
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

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final bool hasQuery;
  final bool hasMatches;
  final bool hasMoreMatches;
  final bool isSearchPending;
  final int currentIndex;
  final int matchCount;
  final _SearchOptions options;

  const _SearchRow({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.hasQuery,
    required this.hasMatches,
    required this.hasMoreMatches,
    required this.isSearchPending,
    required this.currentIndex,
    required this.matchCount,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(child: _buildSearchField(context, colors, l10n)),
          const SizedBox(width: 8),
          if (hasQuery) _buildCounter(colors, l10n),
          _buildActions(colors, l10n),
        ],
      ),
    );
  }

  Widget _buildSearchField(
    BuildContext context,
    ColorScheme colors,
    AppLocalizations l10n,
  ) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
        } else if (event.logicalKey == LogicalKeyboardKey.enter) {
          HardwareKeyboard.instance.isShiftPressed ? onPrevious() : onNext();
        }
      },
      child: _SearchField(
        controller: controller,
        focusNode: focusNode,
        hint: l10n.findInNote,
        hasError: hasQuery && !hasMatches,
        onChanged: onChanged,
        onSubmitted: (_) => onNext(),
        onIconTap: hasMatches ? onNext : null,
      ),
    );
  }

  Widget _buildCounter(ColorScheme colors, AppLocalizations l10n) {
    final isError = !hasMatches && !isSearchPending;
    final countText = hasMoreMatches ? '$matchCount+' : '$matchCount';

    String displayText;
    if (isSearchPending) {
      displayText = l10n.searching;
    } else if (hasMatches) {
      displayText = '${currentIndex + 1}/$countText';
    } else {
      displayText = l10n.noSearchResults;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            (isSearchPending
                    ? colors.secondaryContainer
                    : isError
                    ? colors.errorContainer
                    : colors.primaryContainer)
                .withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSearchPending
              ? colors.onSecondaryContainer
              : isError
              ? colors.onErrorContainer
              : colors.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildActions(ColorScheme colors, AppLocalizations l10n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon: Icons.expand_less_rounded,
          tooltip: l10n.previous,
          onPressed: hasMatches ? onPrevious : null,
        ),
        _IconBtn(
          icon: Icons.expand_more_rounded,
          tooltip: l10n.next,
          onPressed: hasMatches ? onNext : null,
        ),
        _Divider(),
        _OptionsMenu(options: options),
        _IconBtn(
          icon: Icons.close_rounded,
          tooltip: l10n.close,
          onPressed: onClose,
          isClose: true,
        ),
      ],
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
              const SizedBox(width: 8),
              _ActionButton(
                label: l10n.replaceOne,
                onPressed: hasMatches ? onReplaceCurrent : null,
              ),
              const SizedBox(width: 4),
              _ActionButton(
                label: l10n.replaceAll,
                onPressed: hasMatches ? onReplaceAll : null,
                isPrimary: true,
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
  final IconData icon;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onIconTap;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.icon = Icons.search_rounded,
    this.hasError = false,
    this.onChanged,
    this.onSubmitted,
    this.onIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasText = controller.text.isNotEmpty;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasError
              ? colors.error.withValues(alpha: 0.5)
              : colors.outline.withValues(alpha: 0.2),
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(fontSize: 14, color: colors.onSurface),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            fontSize: 14,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: GestureDetector(
              onTap: onIconTap,
              child: Icon(icon, size: 20, color: colors.onSurfaceVariant),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          suffixIcon: hasText && icon == Icons.search_rounded
              ? GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
  final bool isClose;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              size: 22,
              color: enabled
                  ? (isClose ? colors.onSurfaceVariant : colors.primary)
                  : colors.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.3),
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

    return PopupMenuButton<String>(
      icon: Stack(
        children: [
          Icon(
            Icons.tune_rounded,
            size: 20,
            color: options.hasActive ? colors.primary : colors.onSurfaceVariant,
          ),
          if (options.hasActive)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      tooltip: l10n.options,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            size: 20,
            color: active ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
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
            Icon(Icons.check_rounded, size: 18, color: colors.primary),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  const _ActionButton({
    required this.label,
    this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;

    return Material(
      color: isPrimary && enabled ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: !isPrimary
                ? Border.all(
                    color: colors.outline.withValues(
                      alpha: enabled ? 0.3 : 0.1,
                    ),
                  )
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isPrimary && enabled
                  ? colors.onPrimary
                  : colors.onSurface.withValues(alpha: enabled ? 1.0 : 0.4),
            ),
          ),
        ),
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
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: colors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
