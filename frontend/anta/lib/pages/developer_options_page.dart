import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/dev_options.dart';
import '../services/dev_options_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_drawer.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';
import '../services/app_navigator.dart';

/// Developer options page for debugging features
class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  DevOptionsService? _service;
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  @override
  void initState() {
    super.initState();
    _loadService();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadService() async {
    final service = await DevOptionsService.getInstance();
    if (mounted) {
      setState(() {
        _service = service;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveOption() async {
    await _service?.saveOptions();
  }

  void _onHapticFeedback() {
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final devOptions = DevOptions.instance;

    return Scaffold(
      appBar: SettingsAppBar(title: l10n.developerOptions),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(
                listenable: devOptions,
                builder: (context, _) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: SettingsSearchField(
                          controller: _searchController,
                          hint: l10n.searchSettings,
                          onChanged: (value) => setState(
                            () => _query = SettingsQuery.parse(value),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SettingsSectionList(
                          query: _query,
                          style: SettingsSectionStyle.compact,
                          sections: _buildSections(l10n, devOptions),
                          header: [_buildWarningBanner(l10n, colorScheme)],
                          footer: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                _onHapticFeedback();
                                await _service?.resetOptions();
                                if (context.mounted) {
                                  CustomSnackbar.showSuccess(
                                    context,
                                    l10n.developerOptionsReset,
                                  );
                                }
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.resetToDefaults),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () async {
                                _onHapticFeedback();
                                devOptions.lockDeveloperMode();
                                await _service?.saveOptions();
                                if (context.mounted) {
                                  CustomSnackbar.showSuccess(
                                    context,
                                    l10n.developerModeLocked,
                                  );
                                  AppNavigator.pop(
                                    context,
                                    SettingsResult.openDrawer,
                                  );
                                }
                              },
                              icon: const Icon(Icons.lock_rounded),
                              label: Text(l10n.lockDeveloperMode),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildWarningBanner(AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.developerOptionsWarning,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<SettingsSectionData> _buildSections(
    AppLocalizations l10n,
    DevOptions devOptions,
  ) {
    SettingsEntry toggle({
      required String title,
      required String description,
      required bool value,
      required void Function(bool) apply,
    }) {
      return SettingsEntry(
        title: title,
        description: description,
        builder: (context, titleWidget, descriptionWidget) => SwitchListTile(
          title: titleWidget,
          subtitle: descriptionWidget,
          value: value,
          onChanged: (next) async {
            _onHapticFeedback();
            apply(next);
            await _saveOption();
          },
          dense: true,
        ),
      );
    }

    return [
      SettingsSectionData(
        icon: Icons.palette_outlined,
        title: l10n.visualizationDebug,
        entries: [
          toggle(
            title: l10n.colorMarkdownBlocks,
            description: l10n.colorMarkdownBlocksDesc,
            value: devOptions.colorMarkdownBlocks,
            apply: (v) => devOptions.colorMarkdownBlocks = v,
          ),
          toggle(
            title: l10n.showBlockBoundaries,
            description: l10n.showBlockBoundariesDesc,
            value: devOptions.showBlockBoundaries,
            apply: (v) => devOptions.showBlockBoundaries = v,
          ),
          toggle(
            title: l10n.showWhitespace,
            description: l10n.showWhitespaceDesc,
            value: devOptions.showWhitespace,
            apply: (v) => devOptions.showWhitespace = v,
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.speed_outlined,
        title: l10n.performanceMonitoring,
        entries: [
          toggle(
            title: l10n.showRenderTime,
            description: l10n.showRenderTimeDesc,
            value: devOptions.showRenderTime,
            apply: (v) => devOptions.showRenderTime = v,
          ),
          toggle(
            title: l10n.showFpsCounter,
            description: l10n.showFpsCounterDesc,
            value: devOptions.showFpsCounter,
            apply: (v) => devOptions.showFpsCounter = v,
          ),
          toggle(
            title: l10n.showChunkIndicators,
            description: l10n.showChunkIndicatorsDesc,
            value: devOptions.showChunkIndicators,
            apply: (v) => devOptions.showChunkIndicators = v,
          ),
          toggle(
            title: l10n.showRepaintRainbow,
            description: l10n.showRepaintRainbowDesc,
            value: devOptions.showRepaintRainbow,
            apply: (v) => devOptions.showRepaintRainbow = v,
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.edit_note_outlined,
        title: l10n.editorDebug,
        entries: [
          toggle(
            title: l10n.showCursorInfo,
            description: l10n.showCursorInfoDesc,
            value: devOptions.showCursorInfo,
            apply: (v) => devOptions.showCursorInfo = v,
          ),
          toggle(
            title: l10n.showSelectionDetails,
            description: l10n.showSelectionDetailsDesc,
            value: devOptions.showSelectionDetails,
            apply: (v) => devOptions.showSelectionDetails = v,
          ),
          toggle(
            title: l10n.logParserEvents,
            description: l10n.logParserEventsDesc,
            value: devOptions.logParserEvents,
            apply: (v) => devOptions.logParserEvents = v,
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.storage_outlined,
        title: l10n.storageData,
        entries: [
          toggle(
            title: l10n.showNoteSize,
            description: l10n.showNoteSizeDesc,
            value: devOptions.showNoteSize,
            apply: (v) => devOptions.showNoteSize = v,
          ),
          toggle(
            title: l10n.showDatabaseStats,
            description: l10n.showDatabaseStatsDesc,
            value: devOptions.showDatabaseStats,
            apply: (v) => devOptions.showDatabaseStats = v,
          ),
        ],
      ),
    ];
  }
}
