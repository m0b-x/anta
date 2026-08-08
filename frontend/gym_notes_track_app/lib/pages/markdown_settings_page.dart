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
import '../widgets/unified_app_bars.dart';
import '../services/app_navigator.dart';

class MarkdownSettingsPage extends StatefulWidget {
  final List<CustomMarkdownShortcut> allShortcuts;

  const MarkdownSettingsPage({super.key, required this.allShortcuts});

  @override
  State<MarkdownSettingsPage> createState() => _MarkdownSettingsPageState();
}

class _MarkdownSettingsPageState extends State<MarkdownSettingsPage> {
  late List<CustomMarkdownShortcut> _shortcuts;
  final ScrollController _scrollController = ScrollController();
  double _toolbarRatio = SettingsKeys.defaultToolbarShortcutRatio;
  bool _toolbarSplitEnabled = SettingsKeys.defaultToolbarSplitEnabled;
  List<UtilityButtonConfig> _utilityConfigs = UtilityButtonConfig.defaults();
  bool _profileExpanded = true;
  bool _utilityExpanded = true;
  bool _shortcutsExpanded = true;
  bool _toolbarExpanded = true;
  bool _moneyExpanded = true;
  bool _moneyEnabled = false;
  int _moneyStartCents = 0;
  String _moneySymbol = '';
  bool _moneySuffix = false;
  SettingsService? _settingsService;

  List<MarkdownBarProfile> _profiles = [];
  String _editingProfileId = MarkdownBarProfile.defaultProfileId;

  @override
  void initState() {
    super.initState();
    _shortcuts = List.from(widget.allShortcuts);
    _loadToolbarSettings();
    _syncFromBlocState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    if (mounted) {
      setState(() {
        _toolbarRatio = ratio;
        _toolbarSplitEnabled = splitEnabled;
        _utilityConfigs = utilityConfigs;
        _moneyEnabled = moneyConfig.enabled;
        _moneyStartCents = moneyConfig.startCents;
        _moneySymbol = moneyConfig.symbol;
        _moneySuffix = moneyConfig.suffix;
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

  void _addShortcut() {
    AppNavigator.toShortcutEditor(
      context,
      onSave: (shortcut) {
        setState(() {
          _shortcuts.add(shortcut);
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
    });
    _saveShortcuts();
  }

  void _removeAllCustom() {
    setState(() {
      _shortcuts = MarkdownSettingsUtils.removeAllCustom(_shortcuts);
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
            onTap: () => setState(() => _profileExpanded = !_profileExpanded),
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
          TweenAnimationBuilder<double>(
            tween: Tween(end: _profileExpanded ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            builder: (context, value, child) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: child,
              ),
            ),
            child: Column(
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
            onTap: () => setState(() => _toolbarExpanded = !_toolbarExpanded),
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
          TweenAnimationBuilder<double>(
            tween: Tween(end: _toolbarExpanded ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            builder: (context, value, child) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: child,
              ),
            ),
            child: Column(
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.palette_outlined,
              size: 26,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              l10n.markdownColorsTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 17,
              ),
            ),
            subtitle: Text(l10n.markdownColorsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => AppNavigator.toMarkdownColors(context),
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
            onTap: () => setState(() => _moneyExpanded = !_moneyExpanded),
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
          TweenAnimationBuilder<double>(
            tween: Tween(end: _moneyExpanded ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            builder: (context, value, child) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: child,
              ),
            ),
            child: Column(
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

  Widget _buildUtilityButtonsSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _utilityExpanded = !_utilityExpanded),
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
          TweenAnimationBuilder<double>(
            tween: Tween(end: _utilityExpanded ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            builder: (context, value, child) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: child,
              ),
            ),
            child: Column(
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
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  scrollController: _scrollController,
                  itemCount: _utilityConfigs.length,
                  onReorderItem: _reorderUtility,
                  itemBuilder: (context, index) {
                    final config = _utilityConfigs[index];
                    final isLocked =
                        UtilityButtonDefinition.getById(config.id)?.isLocked ??
                        false;
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
                                  alpha: 0.4,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _utilityIcon(config.id),
                                size: 24,
                                color: config.isVisible
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                              ),
                            ],
                          ),
                          title: Text(_utilityLabel(config.id)),
                          subtitle: Text(
                            isLocked
                                ? l10n.alwaysVisible
                                : (config.isVisible
                                      ? l10n.visible
                                      : l10n.hidden),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          trailing: isLocked
                              ? Icon(
                                  Icons.lock,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.3,
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    config.isVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () =>
                                      _toggleUtilityVisibility(index),
                                  tooltip: config.isVisible
                                      ? l10n.hide
                                      : l10n.show,
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
      ),
    );
  }

  Widget _buildShortcutsSection(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _shortcutsExpanded = !_shortcutsExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Icon(
                  Icons.keyboard,
                  size: 26,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.markdownShortcuts,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _shortcutsExpanded ? 0.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: _shortcutsExpanded ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            builder: (context, value, child) => ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: child,
              ),
            ),
            child: _shortcuts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard,
                            size: 64,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noCustomShortcutsYet,
                            style: TextStyle(
                              fontSize: 18,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.tapToAddShortcut,
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    scrollController: _scrollController,
                    padding: const EdgeInsets.only(
                      top: 16,
                      bottom: 110, // Extra space at bottom for FAB
                    ),
                    itemCount: _shortcuts.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _shortcuts.removeAt(oldIndex);
                        _shortcuts.insert(newIndex, item);
                      });
                      _saveShortcuts();
                    },
                    itemBuilder: (context, index) {
                      final shortcut = _shortcuts[index];
                      return Opacity(
                        key: ValueKey(shortcut.id),
                        opacity: shortcut.isVisible ? 1.0 : 0.5,
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
                                    alpha: 0.4,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                MarkdownSettingsUtils.buildShortcutIcon(
                                  context,
                                  shortcut,
                                ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Text(shortcut.label),
                                if (shortcut.isDefault) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.2),
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
                                ],
                              ],
                            ),
                            subtitle: Text(
                              MarkdownSettingsUtils.getShortcutSubtitle(
                                context,
                                shortcut,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    shortcut.isVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => _toggleVisibility(index),
                                  tooltip: shortcut.isVisible
                                      ? l10n.hide
                                      : l10n.show,
                                ),
                                if (!shortcut.isDefault) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _editShortcut(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () => _deleteShortcut(index),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Divider(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ],
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
        body: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileSelector(context),
              _buildToolbarRatioAdjuster(context),
              _buildColorsSection(context),
              _buildMoneySection(context),
              _buildUtilityButtonsSection(context),
              _buildShortcutsSection(context),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addShortcut,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
