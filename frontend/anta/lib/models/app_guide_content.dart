import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'calendar_guide_content.dart';
import 'guide_content.dart';

/// The "Backup, sync and settings" book's pages, in reading order (§3.3 of
/// `docs/guide-hub-roadmap.md`).
///
/// Every label a row names is the app's own string passed through a
/// placeholder, as the calendar guide does, so the book cannot drift from
/// the screens it describes in any language.
enum AppGuideTopic implements GuideTopic {
  menu('menu', Icons.menu_rounded),
  settings('settings', Icons.tune_rounded),
  backup('backup', Icons.backup_rounded),
  sync('sync', Icons.sync_rounded);

  @override
  final String slug;
  @override
  final IconData icon;

  const AppGuideTopic(this.slug, this.icon);

  @override
  String title(AppLocalizations l10n) => switch (this) {
    menu => l10n.appGuidePageMenu,
    settings => l10n.appGuidePageSettings,
    backup => l10n.appGuidePageBackup,
    sync => l10n.appGuidePageSync,
  };

  @override
  String caption(AppLocalizations l10n) => switch (this) {
    menu => l10n.appGuidePageMenuCaption,
    settings => l10n.appGuidePageSettingsCaption,
    backup => l10n.appGuidePageBackupCaption,
    sync => l10n.appGuidePageSyncCaption,
  };

  @override
  String? lead(AppLocalizations l10n) => switch (this) {
    menu => l10n.appGuideMenuLead,
    settings => l10n.appGuideSettingsLead(l10n.settingsHubTitle),
    backup => l10n.appGuideBackupLead,
    sync => l10n.appGuideSyncLead,
  };

  @override
  List<GuideEntry> entries(AppLocalizations l10n) => [
    for (final row in _rows(l10n)) GuideReadEntry(row),
  ];

  /// None: backup, sync and settings act on her real data, which no sandbox
  /// stands in for.
  @override
  List<GuideEditorCard> get editorCards => const [];

  List<CalendarGuideRow> _rows(AppLocalizations l10n) => switch (this) {
    menu => [
      CalendarGuideRow(
        'menu-account',
        Icons.account_circle_rounded,
        l10n.appGuideMenuAccountTitle,
        l10n.appGuideMenuAccountBody(
          l10n.drawerAccountNotSyncing,
          l10n.sharingSettings,
        ),
      ),
      CalendarGuideRow(
        'menu-calendar',
        Icons.calendar_month_rounded,
        l10n.appGuideMenuCalendarTitle(l10n.calendar),
        l10n.appGuideMenuCalendarBody(
          l10n.calendar,
          l10n.calendarOverview,
          l10n.reportTitle,
          l10n.calendarCategories,
          l10n.alertsTitle,
          l10n.calendarGuideTitle,
          l10n.howToUseAnta,
        ),
      ),
      CalendarGuideRow(
        'menu-notes',
        Icons.pin_rounded,
        l10n.appGuideMenuNotesTitle(l10n.notes),
        l10n.appGuideMenuNotesBody(l10n.counterSettings),
      ),
      CalendarGuideRow(
        'menu-app',
        Icons.settings_rounded,
        l10n.appGuideMenuAppTitle(l10n.appGroupLabel),
        l10n.appGuideMenuAppBody(
          l10n.settingsHubTitle,
          l10n.howToUseAnta,
          l10n.about,
        ),
      ),
      CalendarGuideRow(
        'menu-back',
        Icons.arrow_back_rounded,
        l10n.appGuideMenuBackTitle,
        l10n.appGuideMenuBackBody,
      ),
    ],
    settings => [
      CalendarGuideRow(
        'settings-theme',
        Icons.dark_mode_rounded,
        l10n.appGuideSettingsThemeTitle(l10n.settingsRowTheme),
        l10n.appGuideSettingsThemeBody(l10n.themeSettingsDesc),
      ),
      CalendarGuideRow(
        'settings-language',
        Icons.language_rounded,
        l10n.appGuideSettingsLanguageTitle(l10n.languageSettings),
        l10n.appGuideSettingsLanguageBody,
      ),
      CalendarGuideRow(
        'settings-permissions',
        Icons.lock_open_rounded,
        l10n.appGuideSettingsPermissionsTitle(l10n.permissionsTitle),
        l10n.appGuideSettingsPermissionsBody(l10n.settingsHubTitle),
      ),
      CalendarGuideRow(
        'settings-startup',
        Icons.restore_rounded,
        l10n.appGuideSettingsStartupTitle,
        l10n.appGuideSettingsStartupBody(
          l10n.settingsRowGeneral,
          l10n.startupSection,
          l10n.restoreLocation,
        ),
      ),
      CalendarGuideRow(
        'settings-search',
        Icons.search_rounded,
        l10n.appGuideSettingsSearchTitle,
        l10n.appGuideSettingsSearchBody(
          l10n.settingsHubTitle,
          l10n.autoSaveSection,
          l10n.languageSettings,
        ),
      ),
    ],
    backup => [
      CalendarGuideRow(
        'backup-folder',
        Icons.folder_zip_rounded,
        l10n.appGuideBackupFolderTitle,
        l10n.appGuideBackupFolderBody(l10n.shareFolder),
      ),
      CalendarGuideRow(
        'backup-selection',
        Icons.checklist_rounded,
        l10n.appGuideBackupSelectionTitle,
        l10n.appGuideBackupSelectionBody(l10n.shareSelected),
      ),
      CalendarGuideRow(
        'backup-import',
        Icons.file_download_rounded,
        l10n.appGuideBackupImportTitle,
        l10n.appGuideBackupImportBody(l10n.importNoteOrFolder),
      ),
      CalendarGuideRow(
        'backup-database',
        Icons.storage_rounded,
        l10n.appGuideBackupDatabaseTitle,
        l10n.appGuideBackupDatabaseBody(
          l10n.settingsRowDatabases,
          l10n.settingsHubTitle,
          l10n.shareDatabase,
          l10n.importDatabase,
        ),
      ),
      CalendarGuideRow(
        'backup-switch',
        Icons.swap_horiz_rounded,
        l10n.appGuideBackupSwitchTitle,
        l10n.appGuideBackupSwitchBody,
      ),
      CalendarGuideRow(
        'backup-firstrun',
        Icons.restore_rounded,
        l10n.appGuideBackupFirstRunTitle,
        l10n.appGuideBackupFirstRunBody(l10n.restoreFromBackup),
      ),
    ],
    sync => [
      CalendarGuideRow(
        'sync-signin',
        Icons.login_rounded,
        l10n.appGuideSyncSignInTitle,
        l10n.appGuideSyncSignInBody(
          l10n.sharingSettings,
          l10n.settingsHubTitle,
          l10n.signInWithGoogle,
        ),
      ),
      CalendarGuideRow(
        'sync-on',
        Icons.cloud_upload_rounded,
        l10n.appGuideSyncOnTitle,
        l10n.appGuideSyncOnBody(
          l10n.syncThisDatabase,
          l10n.syncThisDatabaseDesc,
        ),
      ),
      CalendarGuideRow(
        'sync-status',
        Icons.cloud_done_rounded,
        l10n.appGuideSyncStatusTitle,
        l10n.appGuideSyncStatusBody(
          l10n.syncUpToDate,
          l10n.syncOffline,
          l10n.syncNow,
        ),
      ),
      CalendarGuideRow(
        'sync-cadence',
        Icons.autorenew_rounded,
        l10n.appGuideSyncCadenceTitle,
        l10n.appGuideSyncCadenceBody(l10n.syncAutomatic, l10n.syncNow),
      ),
      CalendarGuideRow(
        'sync-other',
        Icons.devices_rounded,
        l10n.appGuideSyncOtherTitle,
        l10n.appGuideSyncOtherBody(l10n.syncThisDatabase),
      ),
      CalendarGuideRow(
        'sync-conflict',
        Icons.call_split_rounded,
        l10n.appGuideSyncConflictTitle,
        l10n.appGuideSyncConflictBody,
      ),
      CalendarGuideRow(
        'sync-stop',
        Icons.logout_rounded,
        l10n.appGuideSyncStopTitle,
        l10n.appGuideSyncStopBody(l10n.syncStop, l10n.signOut),
      ),
      CalendarGuideRow(
        'sync-delete',
        Icons.delete_forever_outlined,
        l10n.appGuideSyncDeleteTitle,
        l10n.appGuideSyncDeleteBody(l10n.syncDeleteCloud),
      ),
      CalendarGuideRow(
        'sync-delete-account',
        Icons.person_remove_outlined,
        l10n.appGuideSyncDeleteAccountTitle,
        l10n.appGuideSyncDeleteAccountBody(l10n.syncDeleteAccount),
      ),
      // Named as the row it points at, so the two are one thing to find.
      CalendarGuideRow(
        'sync-data',
        Icons.privacy_tip_outlined,
        l10n.dataNoticeTitle,
        l10n.appGuideSyncDataBody(l10n.dataNoticeTitle),
      ),
    ],
  };
}
