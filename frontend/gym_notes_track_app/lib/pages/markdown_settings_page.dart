import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../config/default_markdown_shortcuts.dart';
import '../constants/app_constants.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/markdown_bar_profile.dart';
import '../models/utility_button_config.dart';
import '../models/utility_button_definition.dart';
import '../services/settings_service.dart';
import '../utils/markdown_settings_utils.dart';
import '../widgets/app_drawer.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_loading_bar.dart';
import '../widgets/markdown_bar.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/unified_app_bars.dart';
import '../services/app_navigator.dart';

class MarkdownSettingsPage extends StatefulWidget {
  final List<CustomMarkdownShortcut> allShortcuts;

  const MarkdownSettingsPage({super.key, required this.allShortcuts});

  @override
  State<MarkdownSettingsPage> createState() => _MarkdownSettingsPageState();
}

class _MarkdownSettingsPageState extends State<MarkdownSettingsPage>
    with SingleTickerProviderStateMixin {
  late List<CustomMarkdownShortcut> _shortcuts;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _shortcutSearchController =
      TextEditingController();
  String _shortcutQuery = '';
  final Set<String> _selectedCategories = <String>{};
  bool _uncategorizedSelected = false;
  final TextEditingController _utilitySearchController =
      TextEditingController();
  String _utilityQuery = '';
  double _toolbarRatio = SettingsKeys.defaultToolbarShortcutRatio;
  bool _toolbarSplitEnabled = SettingsKeys.defaultToolbarSplitEnabled;
  List<UtilityButtonConfig> _utilityConfigs = UtilityButtonConfig.defaults();
  bool _profileExpanded = true;
  bool _utilityExpanded = true;
  bool _shortcutsExpanded = true;
  bool _toolbarExpanded = true;
  bool _colorsExpanded = true;
  bool _moneyExpanded = true;
  bool _moneyEnabled = false;
  int _moneyStartCents = 0;
  String _moneySymbol = '';
  bool _moneySuffix = false;
  SettingsService? _settingsService;

  List<MarkdownBarProfile> _profiles = [];
  String _editingProfileId = MarkdownBarProfile.defaultProfileId;

  /// Drives the cross-fade of the shortcut list slivers when the section is
  /// folded. A sliver cannot be height-clipped the way the box sections are,
  /// so the list stays mounted until the fade-out completes.
  late final AnimationController _shortcutsFoldController;
  bool _shortcutsListMounted = true;

  /// False until persisted fold state has been applied, so restoring it snaps
  /// instead of playing five folds on entry.
  bool _foldAnimationsEnabled = false;

  /// Section ids persisted in [SettingsKeys.markdownSectionsCollapsed].
  static const String _sectionProfiles = 'profiles';
  static const String _sectionToolbar = 'toolbar';
  static const String _sectionColors = 'colors';
  static const String _sectionMoney = 'money';
  static const String _sectionUtility = 'utility';
  static const String _sectionShortcuts = 'shortcuts';

  @override
  void initState() {
    super.initState();
    _shortcuts = List.from(widget.allShortcuts);
    _shortcutsFoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _shortcutsExpanded ? 1.0 : 0.0,
    )..addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _shortcutsListMounted = false);
      }
    });
    _loadToolbarSettings();
    _syncFromBlocState();
  }

  @override
  void dispose() {
    _shortcutsFoldController.dispose();
    _shortcutSearchController.dispose();
    _utilitySearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _anySectionExpanded =>
      _profileExpanded ||
      _toolbarExpanded ||
      _colorsExpanded ||
      _moneyExpanded ||
      _utilityExpanded ||
      _shortcutsExpanded;

  Set<String> get _collapsedSections => {
    if (!_profileExpanded) _sectionProfiles,
    if (!_toolbarExpanded) _sectionToolbar,
    if (!_colorsExpanded) _sectionColors,
    if (!_moneyExpanded) _sectionMoney,
    if (!_utilityExpanded) _sectionUtility,
    if (!_shortcutsExpanded) _sectionShortcuts,
  };

  /// Applies persisted fold state. [animated] is false on the initial load so
  /// the restored state is already in place on the first frame.
  void _applyCollapsedSections(Set<String> collapsed, {bool animated = true}) {
    _profileExpanded = !collapsed.contains(_sectionProfiles);
    _toolbarExpanded = !collapsed.contains(_sectionToolbar);
    _colorsExpanded = !collapsed.contains(_sectionColors);
    _moneyExpanded = !collapsed.contains(_sectionMoney);
    _utilityExpanded = !collapsed.contains(_sectionUtility);
    _shortcutsExpanded = !collapsed.contains(_sectionShortcuts);

    if (_shortcutsExpanded) {
      _shortcutsListMounted = true;
      if (animated) {
        _shortcutsFoldController.forward();
      } else {
        _shortcutsFoldController.value = 1.0;
      }
    } else if (animated) {
      _shortcutsFoldController.reverse();
    } else {
      _shortcutsFoldController.value = 0.0;
      _shortcutsListMounted = false;
    }
  }

  Future<void> _saveCollapsedSections() async {
    final settings = await _getSettingsService();
    await settings.setCollapsedMarkdownSections(_collapsedSections);
  }

  void _toggleShortcutsExpanded() {
    setState(() {
      _shortcutsExpanded = !_shortcutsExpanded;
      if (_shortcutsExpanded) {
        _shortcutsListMounted = true;
        _shortcutsFoldController.forward();
      } else {
        _shortcutsFoldController.reverse();
      }
    });
    _saveCollapsedSections();
  }

  void _toggleSection(void Function() mutate) {
    setState(mutate);
    _saveCollapsedSections();
  }

  void _setAllSectionsExpanded(bool expanded) {
    setState(() {
      _applyCollapsedSections(
        expanded
            ? const <String>{}
            : {
                _sectionProfiles,
                _sectionToolbar,
                _sectionColors,
                _sectionMoney,
                _sectionUtility,
                _sectionShortcuts,
              },
      );
    });
    _saveCollapsedSections();
  }

  Future<SettingsService> _getSettingsService() async {
    return _settingsService ??= await SettingsService.getInstance();
  }

  void _syncFromBlocState() {
    final state = context.read<MarkdownBarBloc>().state;
    if (state is MarkdownBarLoaded) {
      setState(() {
        _profiles = state.profiles;
        _editingProfileId = state.editingProfileId ?? state.activeProfileId;
        _shortcuts = List.from(state.currentShortcuts);
      });
    }
  }

  void _switchEditingProfile(String profileId) {
    context.read<MarkdownBarBloc>().add(
      SwitchEditingProfile(profileId: profileId),
    );
  }

  Future<void> _addBarProfile() async {
    final name = await _showNameDialog(
      title: AppLocalizations.of(context)!.addBar,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    context.read<MarkdownBarBloc>().add(AddBarProfile(name: name));
  }

  Future<void> _renameBarProfile(String profileId) async {
    final profile = _profiles.firstWhere((p) => p.id == profileId);
    if (profile.isDefault) return;
    final name = await _showNameDialog(
      title: AppLocalizations.of(context)!.renameBar,
      initialValue: profile.name,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    context.read<MarkdownBarBloc>().add(
      RenameBarProfile(profileId: profileId, newName: name),
    );
  }

  Future<void> _duplicateBarProfile(String profileId) async {
    final profile = _profiles.firstWhere((p) => p.id == profileId);
    final name = await _showNameDialog(
      title: AppLocalizations.of(context)!.duplicateBar,
      initialValue: '${profile.name} (copy)',
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    context.read<MarkdownBarBloc>().add(
      DuplicateBarProfile(sourceId: profileId, newName: name),
    );
  }

  Future<void> _deleteBarProfile(String profileId) async {
    final profile = _profiles.firstWhere((p) => p.id == profileId);
    if (profile.isDefault) return;
    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.deleteBar,
      content: AppLocalizations.of(context)!.deleteBarConfirm,
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
    );
    if (!confirmed) return;
    if (!mounted) return;
    context.read<MarkdownBarBloc>().add(DeleteBarProfile(profileId: profileId));
  }

  Future<String?> _showNameDialog({
    required String title,
    String initialValue = '',
  }) {
    return AppDialogs.textInput(
      context,
      title: title,
      hintText: AppLocalizations.of(context)!.barName,
      initialValue: initialValue,
      maxLength: AppConstants.maxBarProfileNameLength,
    );
  }

  Future<void> _loadToolbarSettings() async {
    final settings = await _getSettingsService();
    final ratio = await settings.getToolbarShortcutRatio();
    final splitEnabled = await settings.getToolbarSplitEnabled();
    final utilityConfigs = await settings.getToolbarUtilityConfig();
    final moneyConfig = await settings.getMoneyConfig();
    final collapsedSections = await settings.getCollapsedMarkdownSections();
    if (mounted) {
      setState(() {
        _toolbarRatio = ratio;
        _toolbarSplitEnabled = splitEnabled;
        _utilityConfigs = utilityConfigs;
        _moneyEnabled = moneyConfig.enabled;
        _moneyStartCents = moneyConfig.startCents;
        _moneySymbol = moneyConfig.symbol;
        _moneySuffix = moneyConfig.suffix;
        _applyCollapsedSections(collapsedSections, animated: false);
        _foldAnimationsEnabled = true;
      });
    }
  }

  Future<void> _saveToolbarRatio(double value) async {
    final settings = await _getSettingsService();
    await settings.setToolbarShortcutRatio(value);
  }

  Future<void> _saveToolbarSplitEnabled(bool value) async {
    final settings = await _getSettingsService();
    await settings.setToolbarSplitEnabled(value);
  }

  Future<void> _saveUtilityConfigs() async {
    final settings = await _getSettingsService();
    await settings.setToolbarUtilityConfig(_utilityConfigs);
  }

  /// Formats a cent amount as a plain decimal string (e.g. `10.00`).
  String _formatMoneyCents(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  }

  /// Parses a decimal amount ("1000", "1000.5", "-40", "1000,50") into
  /// cents without floating point. Accepts a leading `-` so a negative
  /// start balance (debt) round-trips through the dialog exactly as
  /// [_formatMoneyCents] displays it. Returns `null` for invalid input.
  int? _parseMoneyCents(String input) {
    final text = input.trim().replaceAll(',', '.');
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) return null;
    final intPart = int.tryParse(match.group(2)!);
    if (intPart == null) return null;
    var cents = intPart * 100;
    final decimals = match.group(3);
    if (decimals != null) {
      var d = int.parse(decimals);
      if (decimals.length == 1) d *= 10;
      cents += d;
    }
    return match.group(1)!.isEmpty ? cents : -cents;
  }

  Future<void> _editMoneyStartBalance() async {
    final result = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.moneyStartBalance,
      initialValue: _formatMoneyCents(_moneyStartCents),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (result == null) return;
    final cents = _parseMoneyCents(result);
    if (cents == null) return;
    final settings = await _getSettingsService();
    await settings.setMoneyStartCents(cents);
    if (mounted) {
      setState(() {
        _moneyStartCents = cents;
      });
    }
  }

  Future<void> _editMoneyCurrencySymbol() async {
    final result = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.moneyCurrencySymbolLabel,
      initialValue: _moneySymbol,
      maxLength: 8,
    );
    if (result == null) return;
    final symbol = result.trim();
    final settings = await _getSettingsService();
    await settings.setMoneyCurrencySymbol(symbol);
    if (mounted) {
      setState(() {
        _moneySymbol = symbol;
      });
    }
  }

  Future<void> _saveMoneySuffix(bool value) async {
    final settings = await _getSettingsService();
    await settings.setMoneyCurrencySuffix(value);
  }

  Future<void> _saveMoneyEnabled(bool value) async {
    final settings = await _getSettingsService();
    await settings.setMoneyLedgerEnabled(value);
  }

  void _toggleUtilityVisibility(int index) {
    final config = _utilityConfigs[index];
    // Prevent hiding locked buttons (e.g. settings).
    if (UtilityButtonDefinition.getById(config.id)?.isLocked ?? false) return;
    setState(() {
      _utilityConfigs[index] = config.copyWith(isVisible: !config.isVisible);
    });
    _saveUtilityConfigs();
  }

  void _reorderUtility(int oldIndex, int newIndex) {
    setState(() {
      final item = _utilityConfigs.removeAt(oldIndex);
      _utilityConfigs.insert(newIndex, item);
    });
    _saveUtilityConfigs();
  }

  /// Returns a user-friendly label for a utility button ID.
  String _utilityLabel(String id) {
    final def = UtilityButtonDefinition.getById(id);
    if (def != null) return def.label(AppLocalizations.of(context)!);
    return id;
  }

  /// Returns the icon for a utility button ID.
  IconData _utilityIcon(String id) {
    return UtilityButtonDefinition.getById(id)?.icon ?? Icons.help_outline;
  }

  void _saveShortcuts() {
    context.read<MarkdownBarBloc>().add(
      UpdateShortcuts(
        profileId: _editingProfileId,
        shortcuts: List.from(_shortcuts),
      ),
    );
  }

  /// Distinct non-empty categories in first-appearance order. The category
  /// set is derived from the shortcuts themselves — there is no separate
  /// persisted registry.
  List<String> get _shortcutCategories {
    final seen = <String>{};
    final result = <String>[];
    for (final shortcut in _shortcuts) {
      final category = shortcut.category;
      if (category == null || category.isEmpty) continue;
      if (seen.add(category)) result.add(category);
    }
    return result;
  }

  bool get _hasUncategorizedShortcuts => _shortcuts.any(
    (s) => s.category == null || s.category!.isEmpty,
  );

  bool get _isFilteringShortcuts =>
      _shortcutQuery.trim().isNotEmpty ||
      _selectedCategories.isNotEmpty ||
      _uncategorizedSelected;

  /// Shortcuts matching the current search query and category chips, each
  /// paired with its index into [_shortcuts] so every action keeps operating
  /// on the real position regardless of what is being shown.
  List<({CustomMarkdownShortcut shortcut, int index})>
  get _filteredShortcuts {
    final query = _shortcutQuery.trim().toLowerCase();
    final result = <({CustomMarkdownShortcut shortcut, int index})>[];
    for (var i = 0; i < _shortcuts.length; i++) {
      final shortcut = _shortcuts[i];
      if (_selectedCategories.isNotEmpty || _uncategorizedSelected) {
        final category = shortcut.category;
        final matches = (category == null || category.isEmpty)
            ? _uncategorizedSelected
            : _selectedCategories.contains(category);
        if (!matches) continue;
      }
      if (query.isNotEmpty) {
        final haystack =
            '${shortcut.label}\n${shortcut.category ?? ''}\n'
                    '${shortcut.beforeText}\n${shortcut.afterText}'
                .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      result.add((shortcut: shortcut, index: i));
    }
    return result;
  }

  void _clearShortcutFilters() {
    _shortcutSearchController.clear();
    setState(() {
      _shortcutQuery = '';
      _selectedCategories.clear();
      _uncategorizedSelected = false;
    });
  }

  void _toggleCategoryFilter(String category) {
    setState(() {
      if (!_selectedCategories.remove(category)) {
        _selectedCategories.add(category);
      }
    });
  }

  void _toggleUncategorizedFilter() {
    setState(() => _uncategorizedSelected = !_uncategorizedSelected);
  }

  /// Drops selected chips whose category no longer exists on any shortcut,
  /// so the list can never end up filtered by a category the user just
  /// renamed or removed.
  void _pruneCategorySelection() {
    final available = _shortcutCategories.toSet();
    _selectedCategories.removeWhere((key) => !available.contains(key));
    if (!_hasUncategorizedShortcuts) _uncategorizedSelected = false;
  }

  Future<void> _setShortcutCategory(int index) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CategoryDialog(
        initialValue: _shortcuts[index].category ?? '',
        existingCategories: _shortcutCategories,
      ),
    );
    if (result == null) return;
    final category = result.trim();
    setState(() {
      _shortcuts[index] = _shortcuts[index].copyWith(
        category: category.isEmpty ? null : category,
        clearCategory: category.isEmpty,
      );
      _pruneCategorySelection();
    });
    _saveShortcuts();
  }

  void _addShortcut() {
    // Creating while a single category is filtered keeps the new shortcut in
    // view instead of dropping it into an unrelated bucket.
    final presetCategory =
        _selectedCategories.length == 1 && !_uncategorizedSelected
        ? _selectedCategories.first
        : null;
    AppNavigator.toShortcutEditor(
      context,
      onSave: (shortcut) {
        setState(() {
          _shortcuts.add(
            presetCategory == null
                ? shortcut
                : shortcut.copyWith(category: presetCategory),
          );
        });
        _saveShortcuts();
      },
    );
  }

  void _editShortcut(int index) {
    final shortcut = _shortcuts[index];

    if (shortcut.isDefault) {
      return;
    }

    AppNavigator.toShortcutEditor(
      context,
      shortcut: shortcut,
      onSave: (updatedShortcut) {
        setState(() {
          _shortcuts[index] = updatedShortcut;
        });
        _saveShortcuts();
      },
    );
  }

  void _toggleVisibility(int index) {
    setState(() {
      _shortcuts[index] = _shortcuts[index].copyWith(
        isVisible: !_shortcuts[index].isVisible,
      );
    });
    _saveShortcuts();
  }

  void _deleteShortcut(int index) async {
    final shortcut = _shortcuts[index];

    if (shortcut.isDefault) {
      return;
    }

    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.deleteShortcut,
      content: AppLocalizations.of(context)!.deleteShortcutConfirm,
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
    );
    if (!confirmed) return;
    setState(() {
      _shortcuts.removeAt(index);
      _pruneCategorySelection();
    });
    _saveShortcuts();
  }

  void _showResetDialog() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.resetDialogTitle,
      content: AppLocalizations.of(context)!.resetDialogMessage,
      confirmText: AppLocalizations.of(context)!.reset,
    );
    if (!confirmed) return;
    _resetToDefault();
  }

  void _showRemoveCustomDialog() async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.removeCustomDialogTitle,
      content: AppLocalizations.of(context)!.removeCustomDialogMessage,
      confirmText: AppLocalizations.of(context)!.remove,
      isDestructive: true,
    );
    if (!confirmed) return;
    _removeAllCustom();
  }

  void _resetToDefault() {
    final customShortcuts = _shortcuts.where((s) => !s.isDefault).toList();
    setState(() {
      _shortcuts = [...DefaultMarkdownShortcuts.shortcuts, ...customShortcuts];
      _pruneCategorySelection();
    });
    _saveShortcuts();
  }

  void _removeAllCustom() {
    setState(() {
      _shortcuts = MarkdownSettingsUtils.removeAllCustom(_shortcuts);
      _pruneCategorySelection();
    });
    _saveShortcuts();
  }

  void _showProfilePickerMenu(BuildContext context, RenderBox box) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    const itemHeight = 48.0;
    const maxVisible = 5;

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(
          Offset(box.size.width, box.size.height),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        maxHeight: itemHeight * maxVisible,
        minWidth: box.size.width,
      ),
      items: _profiles.map((p) {
        final isSelected = p.id == _editingProfileId;
        return PopupMenuItem<String>(
          value: p.id,
          height: itemHeight,
          child: Row(
            children: [
              Icon(
                p.isDefault ? Icons.view_day : Icons.dashboard_customize,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? theme.colorScheme.primary : null,
                  ),
                ),
              ),
              if (p.isDefault)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.defaultBar,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              if (isSelected)
                Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
            ],
          ),
        );
      }).toList(),
    ).then((id) {
      if (id != null) _switchEditingProfile(id);
    });
  }

  Widget _buildProfileSelector(BuildContext context) {
    // Guard: service hasn't loaded yet.
    if (_profiles.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final editingProfile = _profiles.firstWhere(
      (p) => p.id == _editingProfileId,
      orElse: () => _profiles.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                _toggleSection(() => _profileExpanded = !_profileExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  Icons.dashboard_customize,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.manageBarProfiles,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _profileExpanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          _FoldableContent(
            expanded: _profileExpanded,
            animate: _foldAnimationsEnabled,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Profile selector row
                Row(
                  children: [
                    Expanded(
                      child: Builder(
                        builder: (selectorContext) => InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            final box =
                                selectorContext.findRenderObject()!
                                    as RenderBox;
                            _showProfilePickerMenu(selectorContext, box);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  editingProfile.isDefault
                                      ? Icons.view_day
                                      : Icons.dashboard_customize,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    editingProfile.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (editingProfile.isDefault)
                                  Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      l10n.defaultBar,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                Icon(
                                  Icons.unfold_more,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      tooltip: l10n.addBar,
                      onPressed: _addBarProfile,
                      visualDensity: VisualDensity.compact,
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 20),
                      tooltip: '',
                      onSelected: (action) {
                        switch (action) {
                          case 'rename':
                            _renameBarProfile(_editingProfileId);
                            break;
                          case 'duplicate':
                            _duplicateBarProfile(_editingProfileId);
                            break;
                          case 'assign':
                            AppNavigator.toNoteBarAssignment(context);
                            break;
                          case 'delete':
                            _deleteBarProfile(_editingProfileId);
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (!editingProfile.isDefault) ...[
                          PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                const Icon(Icons.edit, size: 18),
                                const SizedBox(width: 8),
                                Text(l10n.renameBar),
                              ],
                            ),
                          ),
                        ],
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Row(
                            children: [
                              const Icon(Icons.copy, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.duplicateBar),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'assign',
                          child: Row(
                            children: [
                              const Icon(Icons.link, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.perNoteBarAssignment),
                            ],
                          ),
                        ),
                        if (!editingProfile.isDefault)
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.deleteBar,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  Widget _buildToolbarRatioAdjuster(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ratio = _toolbarRatio.clamp(
      AppConstants.minToolbarRatio,
      AppConstants.maxToolbarRatio,
    );
    final percentLeft = (ratio * 100).round();
    final percentRight = 100 - percentLeft;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                _toggleSection(() => _toolbarExpanded = !_toolbarExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  Icons.view_column,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.toolbarLayout,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _toolbarExpanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          _FoldableContent(
            expanded: _toolbarExpanded,
            animate: _foldAnimationsEnabled,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Split toolbar toggle row
                Row(
                  children: [
                    Text(l10n.splitToolbar, style: theme.textTheme.bodyLarge),
                    const Spacer(),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _toolbarSplitEnabled,
                        onChanged: (value) {
                          setState(() {
                            _toolbarSplitEnabled = value;
                          });
                          _saveToolbarSplitEnabled(value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Live toolbar preview
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MarkdownBar(
                    shortcuts: _shortcuts,
                    isPreviewMode: false,
                    canUndo: true,
                    canRedo: false,
                    previewFontSize: 14,
                    shortcutRatio: ratio,
                    splitEnabled: _toolbarSplitEnabled,
                    utilityConfigs: _utilityConfigs,
                    showBackground: false,
                    showReorder: false,
                    showSettings: true,
                    onUndo: () {},
                    onRedo: () {},
                    onDecreaseFontSize: () {},
                    onIncreaseFontSize: () {},
                    onSettings: () {},
                    onShortcutPressed: (_) {},
                    onReorderComplete: (_) {},
                  ),
                ),
                // Ratio adjuster — only when split mode is enabled
                if (_toolbarSplitEnabled) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${l10n.shortcuts} $percentLeft%  ·  ${l10n.utilities} $percentRight%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor: theme.colorScheme.outline.withValues(
                        alpha: 0.2,
                      ),
                      thumbColor: theme.colorScheme.primary,
                    ),
                    child: Slider(
                      value: ratio,
                      min: AppConstants.minToolbarRatio,
                      max: AppConstants.maxToolbarRatio,
                      onChanged: (value) {
                        setState(() {
                          _toolbarRatio = value;
                        });
                      },
                      onChangeEnd: (value) {
                        _saveToolbarRatio(value);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 4),
              ],
            ),
          ),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  /// Entry point for the markdown colour palette. The palette drives
  /// `{name:text}` runs and `==name:text==` highlights on both render
  /// surfaces; editing lives on its own page.
  Widget _buildColorsSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same header shape as every other foldable section — a ListTile
          // here supplied its own text/icon colours and height, which made
          // this row read as a different kind of thing. It folds like its
          // neighbours; the actual navigation lives on the "Edit colors"
          // button inside the fold, same as any other settings entry point.
          InkWell(
            onTap: () =>
                _toggleSection(() => _colorsExpanded = !_colorsExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.markdownColorsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _colorsExpanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          _FoldableContent(
            expanded: _colorsExpanded,
            animate: _foldAnimationsEnabled,
            builder: (context) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => AppNavigator.toMarkdownColors(context),
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: Text(l10n.editColors),
                ),
              ),
            ),
          ),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  Widget _buildMoneySection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                _toggleSection(() => _moneyExpanded = !_moneyExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  Icons.savings_outlined,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.moneySection,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _moneyExpanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          _FoldableContent(
            expanded: _moneyExpanded,
            animate: _foldAnimationsEnabled,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                // Master switch — the whole feature is opt-in.
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.moneyLedgerEnabledLabel,
                            style: theme.textTheme.bodyLarge,
                          ),
                          Text(
                            l10n.moneyLedgerEnabledDesc,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _moneyEnabled,
                        onChanged: (value) {
                          setState(() {
                            _moneyEnabled = value;
                          });
                          _saveMoneyEnabled(value);
                        },
                      ),
                    ),
                  ],
                ),
                // Dependent rows dim and go inert while the feature is
                // off — the values persist and apply once re-enabled.
                IgnorePointer(
                  ignoring: !_moneyEnabled,
                  child: Opacity(
                    opacity: _moneyEnabled ? 1.0 : 0.45,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Start balance row
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.moneyStartBalance),
                          subtitle: Text(
                            l10n.moneyStartBalanceDesc,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          trailing: Text(
                            _formatMoneyCents(_moneyStartCents),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: _editMoneyStartBalance,
                        ),
                        // Currency symbol row
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.moneyCurrencySymbolLabel),
                          subtitle: Text(
                            l10n.moneyCurrencySymbolDesc,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          trailing: Text(
                            _moneySymbol.isEmpty ? '—' : _moneySymbol,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onTap: _editMoneyCurrencySymbol,
                        ),
                        // Symbol-after-amount toggle row
                        Row(
                          children: [
                            Text(
                              l10n.moneyCurrencySuffixLabel,
                              style: theme.textTheme.bodyLarge,
                            ),
                            const Spacer(),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _moneySuffix,
                                onChanged: (value) {
                                  setState(() {
                                    _moneySuffix = value;
                                  });
                                  _saveMoneySuffix(value);
                                },
                              ),
                            ),
                          ],
                        ),
                        // Per-note currency row
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.moneyPerNoteCurrency),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              AppNavigator.toNoteMoneyCurrency(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  /// The utility registry is fixed at compile time, so this only becomes true
  /// if enough `UtilityButtonDefinition`s are added to make the list unwieldy.
  bool get _showUtilitySearch =>
      _utilityConfigs.length > AppConstants.listSearchThreshold;

  bool get _isFilteringUtilities =>
      _showUtilitySearch && _utilityQuery.trim().isNotEmpty;

  /// Utility buttons matching the search query, each paired with its index
  /// into [_utilityConfigs] so toggling visibility always hits the real entry.
  List<({UtilityButtonConfig config, int index})> get _filteredUtilityConfigs {
    final query = _utilityQuery.trim().toLowerCase();
    final result = <({UtilityButtonConfig config, int index})>[];
    for (var i = 0; i < _utilityConfigs.length; i++) {
      final config = _utilityConfigs[i];
      if (_isFilteringUtilities &&
          !_utilityLabel(config.id).toLowerCase().contains(query)) {
        continue;
      }
      result.add((config: config, index: i));
    }
    return result;
  }

  Widget _buildUtilityList(
    BuildContext context,
    List<({UtilityButtonConfig config, int index})> entries,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l10n.noMatchesFound,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    Widget buildCard(
      UtilityButtonConfig config,
      int globalIndex,
      int renderIndex,
    ) {
      final isLocked =
          UtilityButtonDefinition.getById(config.id)?.isLocked ?? false;
      return Opacity(
        key: ValueKey(config.id),
        opacity: config.isVisible ? 1.0 : 0.5,
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            minLeadingWidth: 0,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.drag_handle,
                  size: 24,
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: _isFilteringUtilities ? 0.15 : 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _utilityIcon(config.id),
                  size: 24,
                  color: config.isVisible
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
            title: Text(_utilityLabel(config.id)),
            subtitle: Text(
              isLocked
                  ? l10n.alwaysVisible
                  : (config.isVisible ? l10n.visible : l10n.hidden),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            trailing: isLocked
                ? Icon(
                    Icons.lock,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  )
                : IconButton(
                    icon: Icon(
                      config.isVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () => _toggleUtilityVisibility(globalIndex),
                    tooltip: config.isVisible ? l10n.hide : l10n.show,
                  ),
          ),
        ),
      );
    }

    if (_isFilteringUtilities) {
      return Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            buildCard(entries[i].config, entries[i].index, i),
        ],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      onReorderItem: _reorderUtility,
      itemBuilder: (context, index) =>
          buildCard(entries[index].config, entries[index].index, index),
    );
  }

  Widget _buildUtilityButtonsSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                _toggleSection(() => _utilityExpanded = !_utilityExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(Icons.tune, size: 26, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.utilityButtons,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _utilityExpanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          _FoldableContent(
            expanded: _utilityExpanded,
            animate: _foldAnimationsEnabled,
            builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  l10n.utilityButtonsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                if (_showUtilitySearch) ...[
                  SettingsSearchField(
                    controller: _utilitySearchController,
                    hint: l10n.searchUtilityButtons,
                    onChanged: (value) =>
                        setState(() => _utilityQuery = value),
                  ),
                  const SizedBox(height: 8),
                  if (_isFilteringUtilities) ...[
                    _buildReorderLockedHint(context, horizontalPadding: 0),
                    const SizedBox(height: 4),
                  ],
                ],
                _buildUtilityList(context, _filteredUtilityConfigs),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  /// The shortcuts section as slivers. Unlike the other sections it cannot be
  /// a single box: a shrink-wrapped list inside the page scroll view resolves
  /// `Scrollable.of` to its own dead viewport, which is what stopped a drag
  /// from scrolling the page.
  List<Widget> _buildShortcutSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredShortcuts;
    final categories = _shortcutCategories;
    final showChips = categories.isNotEmpty || _hasUncategorizedShortcuts;
    // Short lists carry no search chrome; the threshold trips on its own as
    // the list grows.
    final showSearch = _shortcuts.length > AppConstants.listSearchThreshold;

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildShortcutsHeader(context, filtered.length),
        ),
      ),
    ];

    if (!_shortcutsListMounted) {
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
      return slivers;
    }

    slivers.add(
      SliverFadeTransition(
        opacity: _shortcutsFoldController,
        sliver: SliverMainAxisGroup(
          slivers: [
            if (showSearch || showChips)
              SliverPersistentHeader(
                pinned: true,
                delegate: _ShortcutFilterHeaderDelegate(
                  height: (showSearch ? 56.0 : 0.0) + (showChips ? 46.0 : 0.0),
                  background: theme.colorScheme.surface,
                  child: _buildShortcutFilterBar(
                    context,
                    categories: categories,
                    showSearch: showSearch,
                    showChips: showChips,
                  ),
                ),
              ),
            if (_isFilteringShortcuts && filtered.isNotEmpty)
              SliverToBoxAdapter(child: _buildReorderLockedHint(context)),
            _buildShortcutListSliver(context, filtered),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );

    return slivers;
  }

  Widget _buildShortcutsHeader(BuildContext context, int shownCount) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: _toggleShortcutsExpanded,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(Icons.keyboard, size: 26, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            l10n.markdownShortcuts,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
          ),
          if (_shortcuts.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _isFilteringShortcuts
                    ? l10n.shortcutCountFiltered(shownCount, _shortcuts.length)
                    : '${_shortcuts.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          AnimatedRotation(
            turns: _shortcutsExpanded ? 0.0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.expand_more),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutFilterBar(
    BuildContext context, {
    required List<String> categories,
    required bool showSearch,
    required bool showChips,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SettingsSearchField(
              controller: _shortcutSearchController,
              hint: l10n.searchShortcuts,
              onChanged: (value) => setState(() => _shortcutQuery = value),
            ),
          ),
        if (showChips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final category in categories)
                            _buildCategoryChip(
                              context,
                              label: category,
                              selected: _selectedCategories.contains(category),
                              onToggle: () => _toggleCategoryFilter(category),
                            ),
                          if (_hasUncategorizedShortcuts)
                            _buildCategoryChip(
                              context,
                              label: l10n.uncategorized,
                              selected: _uncategorizedSelected,
                              onToggle: _toggleUncategorizedFilter,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Always occupies its slot so activating a filter never
                  // shifts the chip row sideways.
                  IgnorePointer(
                    ignoring: !_isFilteringShortcuts,
                    child: AnimatedOpacity(
                      opacity: _isFilteringShortcuts ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton(
                          onPressed: _clearShortcutFilters,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: Text(
                            l10n.clearFilters,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onToggle(),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  Widget _buildReorderLockedHint(
    BuildContext context, {
    double horizontalPadding = 16,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 8),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.clearSearchToReorder,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutListSliver(
    BuildContext context,
    List<({CustomMarkdownShortcut shortcut, int index})> filtered,
  ) {
    if (_shortcuts.isEmpty) {
      return SliverToBoxAdapter(child: _buildNoShortcutsState(context));
    }
    if (filtered.isEmpty) {
      return SliverToBoxAdapter(child: _buildNoMatchesState(context));
    }

    const padding = EdgeInsets.fromLTRB(16, 8, 16, 0);

    if (_isFilteringShortcuts) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) => _buildShortcutCard(
            context,
            filtered[index].shortcut,
            filtered[index].index,
            index,
            reorderable: false,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: padding,
      sliver: SliverReorderableList(
        itemCount: filtered.length,
        proxyDecorator: _buildShortcutDragProxy,
        onReorderItem: (oldIndex, newIndex) {
          setState(() {
            final item = _shortcuts.removeAt(oldIndex);
            _shortcuts.insert(newIndex, item);
          });
          _saveShortcuts();
        },
        itemBuilder: (context, index) => _buildShortcutCard(
          context,
          filtered[index].shortcut,
          filtered[index].index,
          index,
          reorderable: true,
        ),
      ),
    );
  }

  Widget _buildShortcutDragProxy(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.02 * t,
          child: Material(
            color: Colors.transparent,
            elevation: 6 * t,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildShortcutCard(
    BuildContext context,
    CustomMarkdownShortcut shortcut,
    int globalIndex,
    int renderIndex, {
    required bool reorderable,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final category = shortcut.category;

    final card = Opacity(
      opacity: shortcut.isVisible ? 1.0 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          minLeadingWidth: 0,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The handle keeps its slot while filtering so clearing the
              // filter does not shift every row sideways.
              reorderable
                  ? ReorderableDragStartListener(
                      index: renderIndex,
                      child: Icon(
                        Icons.drag_handle,
                        size: 24,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.drag_handle,
                      size: 24,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.15,
                      ),
                    ),
              const SizedBox(width: 8),
              MarkdownSettingsUtils.buildShortcutIcon(context, shortcut),
            ],
          ),
          title: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(shortcut.label),
              if (shortcut.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.defaultLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              if (category != null && category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            MarkdownSettingsUtils.getShortcutSubtitle(context, shortcut),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  shortcut.isVisible ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => _toggleVisibility(globalIndex),
                tooltip: shortcut.isVisible ? l10n.hide : l10n.show,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case 'category':
                      _setShortcutCategory(globalIndex);
                      break;
                    case 'edit':
                      _editShortcut(globalIndex);
                      break;
                    case 'delete':
                      _deleteShortcut(globalIndex);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'category',
                    child: Row(
                      children: [
                        const Icon(Icons.label_outline, size: 18),
                        const SizedBox(width: 8),
                        Text(l10n.setCategory),
                      ],
                    ),
                  ),
                  if (!shortcut.isDefault) ...[
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 18),
                          const SizedBox(width: 8),
                          Text(l10n.edit),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            l10n.delete,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!reorderable) {
      return KeyedSubtree(key: ValueKey(shortcut.id), child: card);
    }
    return ReorderableDelayedDragStartListener(
      key: ValueKey(shortcut.id),
      index: renderIndex,
      child: card,
    );
  }

  Widget _buildNoShortcutsState(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noCustomShortcutsYet,
              style: TextStyle(
                fontSize: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tapToAddShortcut,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesState(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noShortcutsMatchFilter,
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _clearShortcutFilters,
              child: Text(l10n.clearFilters),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MarkdownBarBloc, MarkdownBarState>(
      listener: (context, state) {
        if (state is MarkdownBarLoaded) {
          setState(() {
            _profiles = state.profiles;
            _editingProfileId = state.editingProfileId ?? state.activeProfileId;
            _shortcuts = List.from(state.currentShortcuts);
          });
        }
      },
      child: LoadingScaffold(
        drawer: const AppDrawer(),
        appBar: SettingsAppBar(
          title: AppLocalizations.of(context)!.markdownShortcuts,
          actions: [
            IconButton(
              icon: Icon(
                _anySectionExpanded ? Icons.unfold_less : Icons.unfold_more,
              ),
              tooltip: _anySectionExpanded
                  ? AppLocalizations.of(context)!.collapseAll
                  : AppLocalizations.of(context)!.expandAll,
              onPressed: () => _setAllSectionsExpanded(!_anySectionExpanded),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'reset_all') {
                  _showResetDialog();
                } else if (value == 'remove_custom') {
                  _showRemoveCustomDialog();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'reset_all',
                  child: Row(
                    children: [
                      const Icon(Icons.refresh),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context)!.resetToDefault),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove_custom',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_sweep),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context)!.removeAllCustom),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildProfileSelector(context)),
            SliverToBoxAdapter(child: _buildToolbarRatioAdjuster(context)),
            SliverToBoxAdapter(child: _buildColorsSection(context)),
            SliverToBoxAdapter(child: _buildMoneySection(context)),
            SliverToBoxAdapter(child: _buildUtilityButtonsSection(context)),
            ..._buildShortcutSlivers(context),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addShortcut,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

/// Pins the shortcut search field and category chips above the list while it
/// scrolls. Fixed extent — [minExtent] equals [maxExtent] so nothing resizes
/// under the finger.
class _ShortcutFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color background;
  final Widget child;

  const _ShortcutFilterHeaderDelegate({
    required this.height,
    required this.background,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: background,
      child: SizedBox(height: height, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _ShortcutFilterHeaderDelegate oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.background != background ||
        oldDelegate.child != child;
  }
}

/// Height-folds a settings section's content.
///
/// Unlike a `TweenAnimationBuilder` wrapped around a prebuilt child, this does
/// not build the content at all while the section is closed — `Align`'s
/// `heightFactor` only clips painting, so the old shape still constructed and
/// laid out every collapsed section on each rebuild. Content is built once per
/// parent rebuild and handed to `AnimatedBuilder` as its `child`, so animation
/// ticks never rebuild it.
///
/// [animate] is false until persisted fold state has loaded, so restoring it
/// snaps instead of playing five folds on entry.
class _FoldableContent extends StatefulWidget {
  final bool expanded;
  final bool animate;
  final WidgetBuilder builder;

  const _FoldableContent({
    required this.expanded,
    required this.animate,
    required this.builder,
  });

  @override
  State<_FoldableContent> createState() => _FoldableContentState();
}

class _FoldableContentState extends State<_FoldableContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _factor;
  late bool _contentMounted;

  @override
  void initState() {
    super.initState();
    _contentMounted = widget.expanded;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.expanded ? 1.0 : 0.0,
    )..addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _contentMounted = false);
      }
    });
    _factor = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(covariant _FoldableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (!widget.animate) {
      _controller.value = widget.expanded ? 1.0 : 0.0;
      _contentMounted = widget.expanded;
      return;
    }
    if (widget.expanded) {
      _contentMounted = true;
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _factor.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_contentMounted) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _factor,
      child: widget.builder(context),
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _factor.value,
          child: child,
        ),
      ),
    );
  }
}

/// Assigns the free-text category of a single shortcut. Categories already in
/// use are offered as chips so the taxonomy stays consistent without a
/// separate registry to maintain.
class _CategoryDialog extends StatefulWidget {
  final String initialValue;
  final List<String> existingCategories;

  const _CategoryDialog({
    required this.initialValue,
    required this.existingCategories,
  });

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applySuggestion(String category) {
    _controller.value = TextEditingValue(
      text: category,
      selection: TextSelection.collapsed(offset: category.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.setCategory),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: AppConstants.maxBarProfileNameLength,
              decoration: InputDecoration(
                labelText: l10n.shortcutCategory,
                hintText: l10n.categoryHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            if (widget.existingCategories.isNotEmpty) ...[
              Text(
                l10n.existingCategories,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.existingCategories
                    .map(
                      (category) => ActionChip(
                        label: Text(category),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        labelStyle: theme.textTheme.bodySmall,
                        onPressed: () => _applySuggestion(category),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(l10n.noCategory),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
