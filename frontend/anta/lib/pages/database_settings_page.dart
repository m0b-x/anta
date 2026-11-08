import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../core/di/injection.dart';
import '../database/database.dart';
import '../services/body_search_indexer.dart';
import '../services/database_manager.dart';
import '../services/import_export_service.dart';
import '../l10n/app_localizations.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/automation_id.dart';
import '../widgets/database_import_dialog.dart';
import '../widgets/form_rows.dart';
import '../widgets/unified_app_bars.dart';
import '../services/app_navigator.dart';

/// Database settings page for managing database location and operations
class DatabaseSettingsPage extends StatefulWidget {
  const DatabaseSettingsPage({super.key});

  @override
  State<DatabaseSettingsPage> createState() => _DatabaseSettingsPageState();
}

class _DatabaseSettingsPageState extends State<DatabaseSettingsPage> {
  String? _databasePath;
  int? _databaseSizeBytes;
  DateTime? _lastModified;
  bool _isLoading = true;

  /// What Optimize would give back, read from the open active database;
  /// null while it is not open or the read failed.
  int? _reclaimableBytes;

  // Database management
  String _activeDatabaseName = '';
  List<DatabaseInfo> _availableDatabases = [];

  @override
  void initState() {
    super.initState();
    _loadDatabaseInfo();
  }

  /// [inPlace] keeps the page on screen while the values update, so a
  /// refresh or an Optimize leaves the scroll and every button where it was.
  Future<void> _loadDatabaseInfo({bool inPlace = false}) async {
    if (!inPlace) setState(() => _isLoading = true);

    try {
      final dbManager = await DatabaseManager.getInstance();
      _activeDatabaseName = dbManager.getActiveDatabaseName();
      _availableDatabases = await dbManager.listDatabases();

      final dbPath = await dbManager.getDatabasePath(_activeDatabaseName);
      final dbFile = File(dbPath);
      // Read in the same load as the size, so the frame that shows the card
      // already carries it.
      final reclaimable = await _readReclaimable();

      if (await dbFile.exists()) {
        final stats = await dbFile.stat();
        // Since the connection runs in WAL mode, committed data sits in the
        // `-wal` sidecar until a checkpoint folds it back. Reporting only the
        // main file would under-state the size right after heavy writing —
        // exactly when a user goes looking.
        final walFile = File('$dbPath-wal');
        final walBytes = await walFile.exists()
            ? (await walFile.stat()).size
            : 0;
        if (!mounted) return;
        setState(() {
          _databasePath = dbPath;
          _databaseSizeBytes = stats.size + walBytes;
          _lastModified = stats.modified;
          _reclaimableBytes = reclaimable;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _databasePath = dbPath;
          _databaseSizeBytes = null;
          _lastModified = null;
          _reclaimableBytes = reclaimable;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _databasePath = AppLocalizations.of(context)!.databasePathError;
        _reclaimableBytes = null;
        _isLoading = false;
      });
    }
  }

  /// Only from a database already open: the page never opens one to measure
  /// it.
  Future<int?> _readReclaimable() async {
    final open = AppDatabase.openInstanceOf(_activeDatabaseName);
    if (open == null) return null;
    try {
      return await (await open).reclaimableBytes();
    } catch (e) {
      debugPrint('[DatabaseSettings] reclaimable read failed: $e');
      return null;
    }
  }

  String _formatFileSize(int bytes) {
    final l10n = AppLocalizations.of(context)!;
    final locale = l10n.localeName;
    if (bytes < 1024) {
      return l10n.databaseSizeBytes(NumberFormat('0', locale).format(bytes));
    }
    if (bytes < 1024 * 1024) {
      return l10n.databaseSizeKilobytes(
        NumberFormat('0.0', locale).format(bytes / 1024),
      );
    }
    return l10n.databaseSizeMegabytes(
      NumberFormat('0.00', locale).format(bytes / (1024 * 1024)),
    );
  }

  /// Always in the tree and as tall as the longest thing it may say, so the
  /// Share button under it never moves: the neutral sentence when the value
  /// is unknown, or the widest reading each unit up to the file's can give.
  /// The file's own size is not enough: no reclaimable space exceeds it, yet
  /// a smaller unit can read wider ("999.5 KB" beside "1.20 MB").
  Widget _buildReclaimableCaption(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const padding = EdgeInsets.only(top: FormMetrics.settingsValueUnderGap);
    final reclaimable = _reclaimableBytes;
    final file = math.max(_databaseSizeBytes ?? 0, reclaimable ?? 0);
    // The figures are tabular, so in the file's own unit the file reads
    // widest; below it, the last value before the next unit ("1024.0 KB"
    // once rounded).
    final widest = [
      if (file >= 1024) 1023,
      if (file >= 1024 * 1024) 1024 * 1024 - 1,
      file,
    ];
    return FormCaptionSlot(
      candidates: [
        FormCaption(text: l10n.databaseReclaimableUnknown, padding: padding),
        for (final bytes in widest)
          FormCaption(
            text: l10n.databaseReclaimable(_formatFileSize(bytes)),
            padding: padding,
          ),
      ],
      child: FormCaption(
        text: reclaimable == null
            ? l10n.databaseReclaimableUnknown
            : l10n.databaseReclaimable(_formatFileSize(reclaimable)),
        padding: padding,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final locale = AppLocalizations.of(context)!.localeName;
    return DateFormat.yMd(locale).add_Hm().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: AppLocalizations.of(context)!.databaseSettings,
        identifier: SemanticsIds.settingsBarDatabases,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _loadDatabaseInfo(inPlace: true),
                child: Semantics(
                  identifier: SemanticsIds.databasesPage,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Database Selection (combines active + available)
                      _buildDatabaseSelectionCard(context, colorScheme),

                      const SizedBox(height: 16),

                      // Database Details (location + stats combined)
                      _buildDatabaseDetailsCard(context, colorScheme),

                      const SizedBox(height: 16),

                      // Actions section (Maintenance + Share)
                      _buildActionsCard(context, colorScheme),

                      const SizedBox(height: 16),

                      // Danger zone card
                      _buildDangerCard(context, colorScheme),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildDatabaseSelectionCard(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.storage_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.availableDatabases,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.activeDatabaseDesc,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Database list (scrollable, max 3 visible)
            if (_availableDatabases.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    AppLocalizations.of(context)!.noDatabases,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 240, // ~3 items (80px each with margin)
                ),
                child: Semantics(
                  identifier: SemanticsIds.databasesList,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _availableDatabases.length,
                    itemBuilder: (context, index) => _buildDatabaseItem(
                      context,
                      colorScheme,
                      _availableDatabases[index],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // Create new database button
            SizedBox(
              width: double.infinity,
              child: AutomationId(
                identifier: SemanticsIds.databaseCreate,
                child: FilledButton.tonalIcon(
                  onPressed: () => _showCreateDatabaseDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.createNewDatabase),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Import database file button
            SizedBox(
              width: double.infinity,
              child: AutomationId(
                identifier: SemanticsIds.databaseImport,
                child: OutlinedButton.icon(
                  onPressed: () => _importDatabase(context),
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.importDatabase),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseDetailsCard(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)!.databaseStats,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats rows
            _buildStatRow(
              context: context,
              colorScheme: colorScheme,
              icon: Icons.storage_rounded,
              label: AppLocalizations.of(context)!.size,
              value: _databaseSizeBytes != null
                  ? _formatFileSize(_databaseSizeBytes!)
                  : AppLocalizations.of(context)!.unknownValue,
            ),
            const Divider(height: 24),
            _buildStatRow(
              context: context,
              colorScheme: colorScheme,
              icon: Icons.update_rounded,
              label: AppLocalizations.of(context)!.lastModified,
              value: _lastModified != null
                  ? _formatDate(_lastModified!)
                  : AppLocalizations.of(context)!.unknownValue,
            ),
            const Divider(height: 24),

            // Location
            Text(
              AppLocalizations.of(context)!.databaseLocation,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Semantics(
                identifier: SemanticsIds.databasePath,
                child: SelectableText(
                  _databasePath ?? AppLocalizations.of(context)!.unknownValue,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            _buildPathActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.build_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context)!.maintenance,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.maintenanceDesc,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Optimize button
            SizedBox(
              width: double.infinity,
              child: AutomationId(
                identifier: SemanticsIds.databaseOptimize,
                child: FilledButton.icon(
                  onPressed: () => _optimizeDatabase(context),
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.optimizeDatabase),
                ),
              ),
            ),
            _buildReclaimableCaption(context),
            const SizedBox(height: 12),

            // Share button
            SizedBox(
              width: double.infinity,
              child: AutomationId(
                identifier: SemanticsIds.databaseShare,
                child: FilledButton.tonalIcon(
                  onPressed: () => _shareDatabase(context),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.shareDatabase),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseItem(
    BuildContext context,
    ColorScheme colorScheme,
    DatabaseInfo db,
  ) {
    final isActive = db.name == _activeDatabaseName;

    final item = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(color: colorScheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: ListTile(
        leading: Icon(
          isActive ? Icons.dataset_rounded : Icons.dataset_outlined,
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
        title: Text(
          db.name,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          '${_formatFileSize(db.size)} • ${_formatDate(db.lastModified)}',
          style: TextStyle(fontSize: 12),
        ),
        trailing: AutomationId(
          identifier: SemanticsIds.databaseMore(db.name),
          child: _buildDatabaseMenu(context, db.name, isActive),
        ),
      ),
    );
    return Semantics(
      container: true,
      identifier: SemanticsIds.databaseRow(db.name),
      child: item,
    );
  }

  Widget _buildDatabaseMenu(BuildContext context, String name, bool isActive) {
    // The label is Flexible so a long one ("Zu dieser Datenbank wechseln" at
    // 2.0) wraps inside the popup's width instead of overflowing it.
    Widget entry(String identifier, IconData icon, String label) => Semantics(
      identifier: identifier,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );

    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 20),
      onSelected: (value) {
        switch (value) {
          case 'switch':
            if (!isActive) _confirmSwitchDatabase(context, name);
            break;
          case 'rename':
            _showRenameDatabaseDialog(context, name);
            break;
          case 'delete':
            if (isActive) {
              CustomSnackbar.showError(context, l10n.cannotDeleteActive);
            } else {
              _showDeleteDatabaseDialog(context, name);
            }
            break;
        }
      },
      itemBuilder: (context) => [
        if (!isActive)
          PopupMenuItem(
            value: 'switch',
            child: entry(
              SemanticsIds.databaseMenuSwitch,
              Icons.swap_horiz_rounded,
              l10n.switchTo,
            ),
          ),
        PopupMenuItem(
          value: 'rename',
          child: entry(
            SemanticsIds.databaseMenuRename,
            Icons.edit_rounded,
            l10n.rename,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          enabled: !isActive,
          child: entry(
            SemanticsIds.databaseMenuDelete,
            Icons.delete_rounded,
            l10n.delete,
          ),
        ),
      ],
    );
  }

  void _showCreateDatabaseDialog(BuildContext context) async {
    final name = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.createNewDatabase,
      labelText: AppLocalizations.of(context)!.newDatabaseName,
      hintText: AppLocalizations.of(context)!.enterDatabaseName,
      confirmText: AppLocalizations.of(context)!.create,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;
    await _createDatabase(context, name.trim());
  }

  Future<void> _createDatabase(BuildContext context, String name) async {
    final dbManager = await DatabaseManager.getInstance();

    if (!dbManager.isValidDatabaseName(name)) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.invalidDatabaseName,
      );
      return;
    }

    if (await dbManager.databaseExists(name)) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseExists,
      );
      return;
    }

    if (!mounted) return;
    AppDialogs.showLoading(
      this.context,
      message: AppLocalizations.of(this.context)!.creatingDatabase,
    );

    try {
      await dbManager.createDatabase(name);

      if (!mounted) return;
      AppNavigator.pop(this.context);

      await _loadDatabaseInfo();

      if (!mounted) return;
      CustomSnackbar.showSuccess(
        this.context,
        AppLocalizations.of(this.context)!.databaseCreated,
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] create failed: $e\n$st');
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseCreateFailed,
      );
    }
  }

  Future<void> _importDatabase(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await FilePicker.pickFile(type: FileType.any);
    if (result == null) return;
    final sourcePath = result.path;
    if (sourcePath == null) return;

    final dbManager = await DatabaseManager.getInstance();

    if (!await dbManager.isSqliteFile(sourcePath)) {
      if (!mounted) return;
      CustomSnackbar.showError(this.context, l10n.invalidDatabaseFile);
      return;
    }

    final suggested = await dbManager.suggestDatabaseName(
      p.basenameWithoutExtension(sourcePath),
    );

    if (!mounted) return;
    final input = await AppDialogs.textInput(
      this.context,
      title: l10n.importDatabase,
      labelText: l10n.newDatabaseName,
      hintText: l10n.enterDatabaseName,
      initialValue: suggested,
      confirmText: l10n.import,
    );
    if (input == null || input.trim().isEmpty) return;
    final targetName = input.trim();

    if (!dbManager.isValidDatabaseName(targetName)) {
      if (!mounted) return;
      CustomSnackbar.showError(this.context, l10n.invalidDatabaseName);
      return;
    }

    if (await dbManager.databaseExists(targetName)) {
      if (!mounted) return;
      CustomSnackbar.showError(this.context, l10n.databaseExists);
      return;
    }

    if (!mounted) return;
    final imported = await DatabaseImportDialog.run(
      this.context,
      (progress) =>
          dbManager.importDatabase(sourcePath, targetName, progress: progress),
    );
    if (!imported || !mounted) return;

    await _loadDatabaseInfo();

    if (!mounted) return;
    CustomSnackbar.showSuccess(this.context, l10n.databaseImported);
  }

  void _showRenameDatabaseDialog(BuildContext context, String oldName) async {
    final newName = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.renameDatabase,
      labelText: AppLocalizations.of(context)!.newDatabaseName,
      initialValue: oldName,
      confirmText: AppLocalizations.of(context)!.rename,
    );
    if (newName == null || newName.trim().isEmpty) return;
    if (!context.mounted) return;
    await _renameDatabase(context, oldName, newName.trim());
  }

  Future<void> _renameDatabase(
    BuildContext context,
    String oldName,
    String newName,
  ) async {
    if (oldName == newName) return;

    final dbManager = await DatabaseManager.getInstance();

    if (!dbManager.isValidDatabaseName(newName)) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.invalidDatabaseName,
      );
      return;
    }

    if (await dbManager.databaseExists(newName)) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseExists,
      );
      return;
    }

    if (!mounted) return;
    AppDialogs.showLoading(
      this.context,
      message: AppLocalizations.of(this.context)!.renamingDatabase,
    );

    try {
      await dbManager.renameDatabase(oldName, newName);

      if (!mounted) return;
      AppNavigator.pop(this.context);

      await _loadDatabaseInfo();

      if (!mounted) return;
      CustomSnackbar.showSuccess(
        this.context,
        AppLocalizations.of(this.context)!.databaseRenamed,
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] rename failed: $e\n$st');
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseRenameFailed,
      );
    }
  }

  void _showDeleteDatabaseDialog(BuildContext context, String name) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.delete,
      content: AppLocalizations.of(context)!.deleteDatabaseConfirm(name),
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
      icon: Icons.warning_rounded,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    await _deleteDatabase(context, name);
  }

  Future<void> _deleteDatabase(BuildContext context, String name) async {
    final dbManager = await DatabaseManager.getInstance();

    try {
      await dbManager.deleteDatabase(name);

      if (!mounted) return;
      await _loadDatabaseInfo();

      if (!mounted) return;
      CustomSnackbar.showSuccess(
        this.context,
        AppLocalizations.of(this.context)!.databaseDeleted,
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] delete failed: $e\n$st');
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseDeleteFailed,
      );
    }
  }

  /// The switch writes the active name before the restart dialog, which has
  /// no way back, so the question comes first.
  Future<void> _confirmSwitchDatabase(BuildContext context, String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.switchTo,
      content: l10n.databaseSwitchConfirm(name),
      confirmText: l10n.switchTo,
      icon: Icons.swap_horiz_rounded,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    await _switchDatabase(context, name);
  }

  Future<void> _switchDatabase(
    BuildContext context,
    String databaseName,
  ) async {
    AppDialogs.showLoading(
      context,
      message: AppLocalizations.of(context)!.switchingDatabase,
    );

    try {
      final dbManager = await DatabaseManager.getInstance();
      await dbManager.setActiveDatabaseName(databaseName);

      if (!mounted) return;
      AppNavigator.pop(this.context);

      // Show restart dialog
      await AppDialogs.action(
        this.context,
        title: AppLocalizations.of(this.context)!.restartRequiredTitle,
        content: AppLocalizations.of(this.context)!.restartRequiredNewDatabase,
        actionText: AppLocalizations.of(this.context)!.exitApp,
        icon: Icons.restart_alt_rounded,
        onAction: () => SystemNavigator.pop(),
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] switch failed: $e\n$st');
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseSwitchFailed,
      );
    }
  }

  /// Side by side at ordinary sizes; stacked, each the card's width, from
  /// the scale where half a card no longer holds "Copiază Calea" whole.
  /// Decided by the scale, so the pair never changes shape with a locale.
  Widget _buildPathActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final copy = FilledButton.tonalIcon(
      onPressed: () => _copyPath(context),
      icon: const Icon(Icons.copy_rounded, size: 18),
      label: Text(l10n.copyPath),
    );
    final open = FilledButton.tonalIcon(
      onPressed: () => _openInFinder(context),
      icon: const Icon(Icons.folder_open_rounded, size: 18),
      label: Text(l10n.openInFinder),
    );
    final scaler = MediaQuery.textScalerOf(context);
    final stacked =
        scaler.scale(RowMetrics.titleFontSize) / RowMetrics.titleFontSize >=
        RowMetrics.compactLeadingTextScale;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [copy, const SizedBox(height: 12), open],
      );
    }
    return Row(
      children: [
        Expanded(child: copy),
        const SizedBox(width: 12),
        Expanded(child: open),
      ],
    );
  }

  Widget _buildStatRow({
    required BuildContext context,
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final labelStyle = TextStyle(
      fontSize: 14,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );
    // The value beside its label only while both fit one line: beside an
    // unbounded value, "Ultima Modificare" at 2.0 got 28 dp and one letter
    // a line. Measured, because a value's length is data.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - 20 - 12;
        final besides =
            _singleLineWidth(context, label, labelStyle) +
                12 +
                _singleLineWidth(context, value, valueStyle) <=
            room;
        final labelText = Text(label, style: labelStyle);
        final valueText = Text(value, style: valueStyle);
        return Row(
          crossAxisAlignment: besides
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: besides
                  ? Row(
                      children: [
                        Expanded(child: labelText),
                        valueText,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [labelText, valueText],
                    ),
            ),
          ],
        );
      },
    );
  }

  double _singleLineWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  Widget _buildDangerCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.warning_rounded,
                    size: 20,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    AppLocalizations.of(context)!.dangerZone,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.dangerZoneDesc,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AutomationId(
                identifier: SemanticsIds.databaseDeleteAll,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(color: colorScheme.error),
                  ),
                  onPressed: () => _showDeleteConfirmation(context),
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.deleteAllData),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyPath(BuildContext context) {
    if (_databasePath != null) {
      Clipboard.setData(ClipboardData(text: _databasePath!));
      CustomSnackbar.show(context, AppLocalizations.of(context)!.pathCopied);
    }
  }

  Future<void> _openInFinder(BuildContext context) async {
    if (_databasePath == null) return;

    final directory = p.dirname(_databasePath!);

    try {
      if (Platform.isMacOS) {
        await Process.run('open', [directory]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [directory]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directory]);
      } else {
        CustomSnackbar.show(
          context,
          AppLocalizations.of(context)!.notSupportedOnPlatform,
        );
      }
    } catch (e, st) {
      debugPrint('[DatabaseSettings] open folder failed: $e\n$st');
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.errorOpeningFolder,
      );
    }
  }

  Future<void> _shareDatabase(BuildContext context) async {
    if (_databasePath == null) return;

    final dbFile = File(_databasePath!);
    if (!await dbFile.exists()) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseNotFound,
      );
      return;
    }

    final dbManager = await DatabaseManager.getInstance();
    if (!mounted) return;

    try {
      // The helper pops its own dialog exactly once, on success or failure;
      // the page itself is never popped. The share runs after the spinner is
      // gone, as it did before, so it never sits behind the share sheet.
      // The sheet gets a snapshot, never the live file: a write landing
      // while the OS copies it could tear the copy (D11).
      final snapshot = await AppDialogs.runWithLoading<String>(
        this.context,
        message: AppLocalizations.of(this.context)!.preparingShare,
        work: () => dbManager.snapshotForShare(_activeDatabaseName),
      );
      if (snapshot == null) return;
      await getIt<ImportExportService>().shareExport(
        ExportResult.snapshot(snapshot),
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] share failed: $e\n$st');
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.shareError,
      );
    }
  }

  Future<void> _optimizeDatabase(BuildContext context) async {
    // Show loading dialog
    AppDialogs.showLoading(
      context,
      message: AppLocalizations.of(context)!.optimizing,
    );

    try {
      final db = await AppDatabase.getInstance();
      // What the file held free before the run is what the run gives back,
      // never a size delta: the size before counts the `-wal` sidecar, whose
      // pages the run's checkpoint folds back, so a delta counted them as
      // freed — and one taken while the vacuum still sat in the WAL once
      // read negative.
      final reclaimableBefore = await db.reclaimableBytes();
      await db.optimize();
      // A VACUUM may renumber the rowids of tables without an INTEGER PRIMARY
      // KEY, and the body search ledger keys on the notes' rowids; the probe
      // would find the drift at the next search anyway, this makes it sooner.
      BodySearchIndexer.markActiveDirty();

      if (!mounted) return;
      AppNavigator.pop(this.context); // Close loading dialog

      await _loadDatabaseInfo(inPlace: true);

      if (!mounted) return;
      final l10n = AppLocalizations.of(this.context)!;
      CustomSnackbar.showSuccess(
        this.context,
        reclaimableBefore == 0
            ? l10n.optimizeAlreadyCompact
            : l10n.optimizeFreed(_formatFileSize(reclaimableBefore)),
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] optimize failed: $e\n$st');
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        AppLocalizations.of(this.context)!.databaseOptimizeFailed,
      );
    }
  }

  void _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await AppDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.deleteAllData,
      content: AppLocalizations.of(context)!.deleteConfirmation,
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
      icon: Icons.warning_rounded,
    );
    if (!confirmed) return;
    await _performDatabaseDeletion();
  }

  Future<void> _performDatabaseDeletion() async {
    // Show loading dialog
    AppDialogs.showLoading(
      context,
      message: AppLocalizations.of(context)!.deletingData,
    );

    try {
      await AppDatabase.deleteAllData();

      if (!mounted) return;
      AppNavigator.pop(context); // Close loading dialog

      // Show success and exit app (user needs to restart)
      await AppDialogs.action(
        context,
        title: AppLocalizations.of(context)!.dataDeleted,
        content: AppLocalizations.of(context)!.restartRequiredAfterDeletion,
        actionText: AppLocalizations.of(context)!.exitApp,
        icon: Icons.check_circle_rounded,
        iconColor: Theme.of(context).colorScheme.primary,
        onAction: () => SystemNavigator.pop(),
      );
    } catch (e, st) {
      debugPrint('[DatabaseSettings] delete all data failed: $e\n$st');
      if (!mounted) return;
      AppNavigator.pop(context); // Close loading dialog

      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.errorDeletingData,
      );
    }
  }
}
