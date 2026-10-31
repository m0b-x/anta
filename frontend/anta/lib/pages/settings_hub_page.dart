import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/app_settings/app_settings_bloc.dart';
import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/dev_options.dart';
import '../services/app_navigator.dart';
import '../services/permission_service.dart';
import '../utils/settings_search.dart';
import '../widgets/app_settings_dialogs.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// The one page every settings page is opened from (D2 of
/// `docs/settings-rework-roadmap.md`): a row per page whose subtitle names
/// what the page holds, searchable by the pages' own section titles, so
/// "holiday" finds Calendar settings without the user knowing which page
/// keeps it.
///
/// The hub keeps no state of its own — no folds, no settings key; the query
/// lives only as long as the page.
class SettingsHubPage extends StatefulWidget {
  const SettingsHubPage({super.key});

  @override
  State<SettingsHubPage> createState() => _SettingsHubPageState();
}

class _SettingsHubPageState extends State<SettingsHubPage> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final permissions = getIt.isRegistered<PermissionService>()
        ? getIt<PermissionService>().snapshot
        : null;

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.settingsHubTitle,
        showMenuButton: false,
        identifier: SemanticsIds.settingsBarHub,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: FormMetrics.settingsSearchPadding,
              child: SettingsSearchField(
                controller: _searchController,
                hint: l10n.settingsHubSearchHint,
                identifier: SemanticsIds.settingsHubSearch,
                onChanged: (value) =>
                    setState(() => _query = SettingsQuery.parse(value)),
              ),
            ),
            Expanded(
              // The rows that come and go with the app's state — Developer
              // options with the unlock, the Permissions subtitle with the
              // snapshot — are entries, so the list is rebuilt from both.
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  DevOptions.instance,
                  ?permissions,
                ]),
                builder: (context, _) => SettingsSectionList(
                  listIdentifier: SemanticsIds.settingsHubList,
                  query: _query,
                  sections: _buildSections(
                    colorScheme,
                    l10n,
                    missingPermissions:
                        permissions?.value?.missingEssential.length ?? 0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Each row's `keywords` mirror the section titles of the page it opens
  /// (or, for a page without sections, the words its title and main nouns
  /// are), so they move with those sections: a slice that moves a section
  /// between pages edits these lists in the same change.
  List<SettingsSectionData> _buildSections(
    ColorScheme colorScheme,
    AppLocalizations l10n, {
    required int missingPermissions,
  }) {
    return [
      SettingsSectionData(
        icon: Icons.calendar_month_rounded,
        title: l10n.settingsSectionCalendar,
        entries: [
          SettingsEntry(
            title: l10n.calendarSettingsRow,
            description: l10n.settingsRowCalendarDesc,
            keywords: [
              l10n.calendarSection,
              l10n.calendarAppearanceSection,
              l10n.calendarFilteringSection,
              l10n.calendarCategories,
              l10n.fastingSectionTitle,
              l10n.calendarEventsSection,
              l10n.calendarAlertsSection,
            ],
            identifier: SemanticsIds.settingsHubRow('calendarSettings'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.tune_rounded,
              title,
              description,
              () => AppNavigator.toCalendarSettings(context),
            ),
          ),
          SettingsEntry(
            title: l10n.calendarAppearanceSection,
            description: l10n.settingsRowAppearanceDesc,
            keywords: [
              l10n.calendarAppearanceDayCellSection,
              l10n.calendarAppearanceMarkersSection,
              l10n.calendarAppearanceRailSection,
              l10n.calendarAppearanceWeekSection,
              l10n.calendarAppearanceColorSection,
              l10n.calendarAppearanceLabelsSection,
            ],
            identifier: SemanticsIds.settingsHubRow('calendarAppearance'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.palette_rounded,
              title,
              description,
              () => AppNavigator.toCalendarAppearance(context),
            ),
          ),
          SettingsEntry(
            title: l10n.calendarCategories,
            description: l10n.calendarCategoriesRowDesc,
            keywords: [l10n.createCategory, l10n.deleteCategory],
            identifier: SemanticsIds.settingsHubRow('calendarCategories'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.category_rounded,
              title,
              description,
              () => AppNavigator.toCalendarCategories(context),
            ),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.notes_rounded,
        title: l10n.settingsSectionNotes,
        entries: [
          SettingsEntry(
            title: l10n.settingsRowEditor,
            description: l10n.settingsRowEditorDesc,
            keywords: [
              l10n.markdownShortcuts,
              l10n.toolbarLayout,
              l10n.utilityButtons,
              l10n.markdownColorsTitle,
              l10n.vocabularySection,
              l10n.moneySection,
            ],
            identifier: SemanticsIds.settingsHubRow('markdownSettings'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.text_format_rounded,
              title,
              description,
              _openMarkdownSettings,
            ),
          ),
          SettingsEntry(
            title: l10n.counterSettings,
            description: l10n.settingsRowCountersDesc,
            keywords: [l10n.counterScope, l10n.startValue, l10n.resetCounter],
            identifier: SemanticsIds.settingsHubRow('counterManagement'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.pin_rounded,
              title,
              description,
              () => AppNavigator.toCounterManagement(context),
            ),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.apps_rounded,
        title: l10n.settingsSectionApp,
        entries: [
          SettingsEntry(
            title: l10n.settingsRowGeneral,
            description: l10n.settingsRowGeneralDesc,
            keywords: [
              l10n.startupSection,
              l10n.displaySection,
              l10n.editorSection,
              l10n.autoSaveSection,
              l10n.feedbackSection,
              l10n.deprecatedSection,
            ],
            identifier: SemanticsIds.settingsHubRow('settings'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.settings_rounded,
              title,
              description,
              () => AppNavigator.toSettings(context),
            ),
          ),
          SettingsEntry(
            title: l10n.languageSettings,
            description: l10n.languageSettingsDesc,
            keywords: [l10n.english, l10n.german, l10n.romanian],
            identifier: SemanticsIds.settingsHubRow('language'),
            builder: (_, title, description) =>
                BlocBuilder<AppSettingsBloc, AppSettingsState>(
                  buildWhen: (previous, current) =>
                      previous.localeCode != current.localeCode,
                  builder: (context, state) => _valueRow(
                    colorScheme,
                    Icons.language_rounded,
                    title,
                    description,
                    languageName(l10n, state.localeCode),
                    () => showLanguageDialog(context),
                  ),
                ),
          ),
          SettingsEntry(
            title: l10n.settingsRowTheme,
            description: l10n.themeSettingsDesc,
            keywords: [
              l10n.selectTheme,
              l10n.lightTheme,
              l10n.darkTheme,
              l10n.systemTheme,
            ],
            identifier: SemanticsIds.settingsAppearance,
            builder: (_, title, description) =>
                BlocBuilder<AppSettingsBloc, AppSettingsState>(
                  buildWhen: (previous, current) =>
                      previous.themeMode != current.themeMode,
                  builder: (context, state) => _valueRow(
                    colorScheme,
                    Icons.brightness_6_rounded,
                    title,
                    description,
                    _themeName(l10n, state.themeMode),
                    () => showThemeDialog(context),
                  ),
                ),
          ),
          SettingsEntry(
            title: l10n.settingsRowDatabases,
            description: l10n.settingsRowDatabasesDesc,
            keywords: [
              l10n.availableDatabases,
              l10n.createNewDatabase,
              l10n.importDatabase,
              l10n.shareDatabase,
              l10n.maintenance,
              l10n.dangerZone,
            ],
            identifier: SemanticsIds.settingsHubRow('databaseSettings'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.storage_rounded,
              title,
              description,
              () => AppNavigator.toDatabaseSettings(context),
            ),
          ),
          SettingsEntry(
            title: l10n.sharingSettings,
            description: l10n.settingsRowSharingDesc,
            keywords: [l10n.accountSection, l10n.pairingSection],
            identifier: SemanticsIds.settingsHubRow('syncSettings'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.cloud_sync_rounded,
              title,
              description,
              () => AppNavigator.toSyncSettings(context),
            ),
          ),
          SettingsEntry(
            title: l10n.permissionsTitle,
            // The attention line replaces the subtitle while an essential
            // permission is off, as the drawer's row has it.
            description: missingPermissions > 0
                ? l10n.permissionsRowAttention(missingPermissions)
                : l10n.permissionsRowDesc,
            descriptionStyle: missingPermissions > 0
                ? TextStyle(color: colorScheme.error)
                : null,
            keywords: [
              l10n.permissionsEssentialSection,
              l10n.permissionsRecommendedSection,
              l10n.permissionsOptionsSection,
            ],
            identifier: SemanticsIds.settingsHubRow('permissions'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.verified_user_rounded,
              title,
              description,
              () => AppNavigator.toPermissions(context),
            ),
          ),
          if (DevOptions.instance.developerModeUnlocked)
            SettingsEntry(
              title: l10n.developerOptions,
              description: l10n.developerOptionsDesc,
              keywords: [
                l10n.visualizationDebug,
                l10n.performanceMonitoring,
                l10n.editorDebug,
                l10n.storageData,
              ],
              identifier: SemanticsIds.settingsHubRow('developerOptions'),
              builder: (_, title, description) => _pageRow(
                colorScheme,
                Icons.developer_mode_rounded,
                title,
                description,
                () => AppNavigator.toDeveloperOptions(context),
              ),
            ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.school_rounded,
        title: l10n.settingsSectionHowTo,
        entries: [
          SettingsEntry(
            title: l10n.calendarGuideTitle,
            identifier: SemanticsIds.settingsHubRow('calendarGuide'),
            builder: (_, title, description) => _pageRow(
              colorScheme,
              Icons.school_rounded,
              title,
              description,
              () => AppNavigator.toCalendarGuide(context),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _pageRow(
    ColorScheme colorScheme,
    IconData glyph,
    Widget title,
    Widget? description,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(glyph, color: colorScheme.primary),
      title: title,
      subtitle: description,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  /// A row that opens a dialog and reads its current answer as its value —
  /// Language and Theme — in place of a page row's chevron.
  Widget _valueRow(
    ColorScheme colorScheme,
    IconData glyph,
    Widget title,
    Widget? description,
    String value,
    VoidCallback onTap,
  ) {
    return SettingsYieldingTile(
      leading: Icon(glyph, color: colorScheme.primary),
      title: title,
      subtitle: description,
      value: value,
      trailing: (maxWidth) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          value,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
      onTap: onTap,
    );
  }

  /// The shortcuts the markdown page edits are the bar bloc's, read at the
  /// tap; a bar still loading opens an empty list.
  void _openMarkdownSettings() {
    final state = context.read<MarkdownBarBloc>().state;
    AppNavigator.toMarkdownSettings(
      context,
      allShortcuts: state is MarkdownBarLoaded
          ? state.currentShortcuts
          : <CustomMarkdownShortcut>[],
    );
  }

  static String _themeName(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.systemTheme,
        ThemeMode.light => l10n.lightTheme,
        ThemeMode.dark => l10n.darkTheme,
      };
}
