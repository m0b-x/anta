import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../database/database.dart';
import '../services/database_manager.dart';
import '../l10n/app_localizations.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_drawer.dart';
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

  // Database management
  String _activeDatabaseName = '';
  List<DatabaseInfo> _availableDatabases = [];

  @override
  void initState() {
    super.initState();
    _loadDatabaseInfo();
  }

  Future<void> _loadDatabaseInfo() async {
    setState(() => _isLoading = true);

    try {
      final dbManager = await DatabaseManager.getInstance();
      _activeDatabaseName = dbManager.getActiveDatabaseName();
      _availableDatabases = await dbManager.listDatabases();

      final dbPath = await dbManager.getDatabasePath(_activeDatabaseName);
      final dbFile = File(dbPath);

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
        setState(() {
          _databasePath = dbPath;
          _databaseSizeBytes = stats.size + walBytes;
          _lastModified = stats.modified;
          _isLoading = false;
        });
      } else {
        setState(() {
          _databasePath = dbPath;
          _databaseSizeBytes = null;
          _lastModified = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _databasePath = 'Error loading path';
        _isLoading = false;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SettingsAppBar(
        title: AppLocalizations.of(context)!.databaseSettings,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadDatabaseInfo,
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

            const SizedBox(height: 8),

            // Create new database button
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _showCreateDatabaseDialog(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(AppLocalizations.of(context)!.createNewDatabase),
              ),
            ),
            const SizedBox(height: 8),

            // Import database file button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _importDatabase(context),
                icon: const Icon(Icons.file_download_rounded, size: 18),
                label: Text(AppLocalizations.of(context)!.importDatabase),
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
                  : 'N/A',
            ),
            const Divider(height: 24),
            _buildStatRow(
              context: context,
              colorScheme: colorScheme,
              icon: Icons.update_rounded,
              label: AppLocalizations.of(context)!.lastModified,
              value: _lastModified != null
                  ? _formatDate(_lastModified!)
                  : 'N/A',
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
              child: SelectableText(
                _databasePath ?? 'Unknown',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _copyPath(context),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(AppLocalizations.of(context)!.copyPath),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openInFinder(context),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text(AppLocalizations.of(context)!.openInFinder),
                  ),
                ),
              ],
            ),
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
              child: FilledButton.icon(
                onPressed: () => _optimizeDatabase(context),
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: Text(AppLocalizations.of(context)!.optimizeDatabase),
              ),
            ),
            const SizedBox(height: 12),

            // Share button
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _shareDatabase(context),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(AppLocalizations.of(context)!.shareDatabase),
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

    return Container(
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
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: 20),
          onSelected: (value) {
            switch (value) {
              case 'switch':
                if (!isActive) _switchDatabase(context, db.name);
                break;
              case 'rename':
                _showRenameDatabaseDialog(context, db.name);
                break;
              case 'delete':
                if (isActive) {
                  CustomSnackbar.showError(
                    context,
                    AppLocalizations.of(context)!.cannotDeleteActive,
                  );
                } else {
                  _showDeleteDatabaseDialog(context, db.name);
                }
                break;
            }
          },
          itemBuilder: (context) => [
            if (!isActive)
              PopupMenuItem(
                value: 'switch',
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 20),
                    SizedBox(width: 12),
                    Text(AppLocalizations.of(context)!.switchTo),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, size: 20),
                  SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.rename),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: !isActive,
              child: Row(
                children: [
                  Icon(Icons.delete_rounded, size: 20),
                  SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.delete),
                ],
              ),
            ),
          ],
        ),
      ),
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
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.error}: $e',
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
    AppDialogs.showLoading(this.context, message: l10n.importingDatabase);

    try {
      await dbManager.importDatabase(sourcePath, targetName);

      if (!mounted) return;
      AppNavigator.pop(this.context);

      await _loadDatabaseInfo();

      if (!mounted) return;
      CustomSnackbar.showSuccess(this.context, l10n.databaseImported);
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.error}: $e',
      );
    }
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
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.error}: $e',
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
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.error}: $e',
      );
    }
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
        title: AppLocalizations.of(this.context)!.restartRequired,
        content: AppLocalizations.of(this.context)!.restartRequired,
        actionText: AppLocalizations.of(this.context)!.exitApp,
        icon: Icons.restart_alt_rounded,
        onAction: () => SystemNavigator.pop(),
      );
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.error}: $e',
      );
    }
  }

  Widget _buildStatRow({
    required BuildContext context,
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
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
                Text(
                  AppLocalizations.of(context)!.dangerZone,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.error,
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
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.errorOpeningFolder}: $e',
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

    if (!mounted) return;

    AppDialogs.showLoading(
      this.context,
      message: AppLocalizations.of(this.context)!.preparingShare,
    );

    try {
      final xFile = XFile(_databasePath!);

      if (!mounted) return;
      AppNavigator.pop(this.context);

      await SharePlus.instance.share(ShareParams(files: [xFile]));
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.shareError}: $e',
      );
    }
  }

  Future<void> _optimizeDatabase(BuildContext context) async {
    // Capture size before optimization
    final sizeBefore = _databaseSizeBytes;

    // Show loading dialog
    AppDialogs.showLoading(
      context,
      message: AppLocalizations.of(context)!.optimizing,
    );

    try {
      final db = await AppDatabase.getInstance();
      await db.vacuum();
      await db.rebuildFtsIndex();

      if (!mounted) return;
      AppNavigator.pop(this.context); // Close loading dialog

      // Refresh stats to get new size
      await _loadDatabaseInfo();

      if (!mounted) return;

      // Calculate size difference
      final sizeAfter = _databaseSizeBytes;
      String message;
      if (sizeBefore != null && sizeAfter != null) {
        final savedBytes = sizeBefore - sizeAfter;
        if (savedBytes > 0) {
          message =
              '${AppLocalizations.of(this.context)!.optimizationComplete} (${_formatFileSize(savedBytes)} ${AppLocalizations.of(this.context)!.saved})';
        } else {
          message =
              '${AppLocalizations.of(this.context)!.optimizationComplete} (${AppLocalizations.of(this.context)!.alreadyOptimized})';
        }
      } else {
        message = AppLocalizations.of(this.context)!.optimizationComplete;
      }

      CustomSnackbar.showSuccess(this.context, message);
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(this.context);

      CustomSnackbar.showError(
        this.context,
        '${AppLocalizations.of(this.context)!.error}: $e',
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
        content: AppLocalizations.of(context)!.restartRequired,
        actionText: AppLocalizations.of(context)!.exitApp,
        icon: Icons.check_circle_rounded,
        iconColor: Colors.green,
        onAction: () => SystemNavigator.pop(),
      );
    } catch (e) {
      if (!mounted) return;
      AppNavigator.pop(context); // Close loading dialog

      CustomSnackbar.showError(
        context,
        '${AppLocalizations.of(context)!.errorDeletingData}: $e',
      );
    }
  }
}
