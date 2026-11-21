import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/shared_refresh/shared_refresh_scheduler.dart';
import '../utils/share_copy.dart';
import 'calendar_guide_content.dart';
import 'guide_content.dart';
import 'sync_guide_tries.dart';

/// The "Sync and sharing" book's pages, in reading order (§11.4 of
/// `docs/guide-hub-roadmap.md`).
///
/// Every label a row names is the app's own string passed through a
/// placeholder, as the other books do, and every row says what the code
/// does (D53): a guide that promises more than the app does costs more
/// trust than none.
enum SyncGuideTopic implements GuideTopic {
  sync('sync', Icons.sync_rounded),
  pair('pair', Icons.link_rounded),
  offline('offline', Icons.cloud_off_rounded),
  event('event', Icons.event_rounded),
  category('category', Icons.category_rounded),
  folder('folder', Icons.folder_rounded),
  look('look', Icons.visibility_rounded),
  alerts('alerts', Icons.notifications_rounded),
  stop('stop', Icons.group_off_rounded),
  private('private', Icons.shield_outlined);

  @override
  final String slug;
  @override
  final IconData icon;

  const SyncGuideTopic(this.slug, this.icon);

  @override
  String title(AppLocalizations l10n) => switch (this) {
    sync => l10n.syncGuidePageSync,
    pair => l10n.syncGuidePagePair,
    offline => l10n.syncGuidePageOffline,
    event => l10n.syncGuidePageEvent,
    category => l10n.syncGuidePageCategory,
    folder => l10n.syncGuidePageFolder,
    look => l10n.syncGuidePageLook,
    alerts => l10n.syncGuidePageAlerts,
    stop => l10n.syncGuidePageStop,
    private => l10n.syncGuidePagePrivate,
  };

  @override
  String caption(AppLocalizations l10n) => switch (this) {
    sync => l10n.syncGuidePageSyncCaption,
    pair => l10n.syncGuidePagePairCaption,
    offline => l10n.syncGuidePageOfflineCaption,
    event => l10n.syncGuidePageEventCaption,
    category => l10n.syncGuidePageCategoryCaption,
    folder => l10n.syncGuidePageFolderCaption,
    look => l10n.syncGuidePageLookCaption,
    alerts => l10n.syncGuidePageAlertsCaption,
    stop => l10n.syncGuidePageStopCaption,
    private => l10n.syncGuidePagePrivateCaption,
  };

  @override
  String? lead(AppLocalizations l10n) => switch (this) {
    sync => l10n.syncGuideSyncLead,
    pair => l10n.syncGuidePairLead,
    offline => l10n.syncGuideOfflineLead,
    event => l10n.syncGuideEventLead,
    category => l10n.syncGuideCategoryLead,
    folder => l10n.syncGuideFolderLead,
    look => l10n.syncGuideLookLead,
    alerts => l10n.syncGuideAlertsLead,
    stop => l10n.syncGuideStopLead,
    private => l10n.syncGuidePrivateLead,
  };

  @override
  List<GuideEntry> entries(AppLocalizations l10n) => [
    for (final row in _rows(l10n)) GuideReadEntry(row),
  ];

  /// None: this book's stages are two phones ([demoCards]).
  @override
  List<GuideEditorCard> get editorCards => const [];

  /// The pages whose two-phone card is built (§11.7); the rest come in
  /// their own slices.
  @override
  List<GuideCardSpec> get demoCards => switch (this) {
    sync => const [SyncGuideTries.sync],
    pair => const [SyncGuideTries.pair],
    offline => const [SyncGuideTries.offline, SyncGuideTries.conflict],
    event => const [SyncGuideTries.event],
    category => const [SyncGuideTries.category],
    folder => const [SyncGuideTries.folder],
    stop => const [SyncGuideTries.stop],
    look => const [SyncGuideTries.look],
    alerts => const [SyncGuideTries.alerts],
    _ => const [],
  };

  /// The guide names no partner, so a label that carries one takes the
  /// stand-in the sharing screens show before a name is known.
  List<CalendarGuideRow> _rows(AppLocalizations l10n) {
    final partner = ShareCopy.partnerName(l10n, null);
    final shareWith = l10n.shareWithPartner(partner);
    final sharingPage = l10n.sharingWithTitle(partner);
    return switch (this) {
      sync => [
        CalendarGuideRow(
          'sync-signin',
          Icons.login_rounded,
          l10n.syncGuideSignInTitle,
          l10n.syncGuideSignInBody(
            l10n.sharingSettings,
            l10n.settingsHubTitle,
            l10n.signInWithGoogle,
          ),
        ),
        CalendarGuideRow(
          'sync-on',
          Icons.cloud_upload_rounded,
          l10n.syncGuideOnTitle,
          l10n.syncGuideOnBody(
            l10n.syncThisDatabase,
            l10n.syncThisDatabaseDesc,
          ),
        ),
        CalendarGuideRow(
          'sync-status',
          Icons.cloud_done_rounded,
          l10n.syncGuideStatusTitle,
          l10n.syncGuideStatusBody(
            l10n.syncUpToDate,
            l10n.syncOffline,
            l10n.syncNow,
          ),
        ),
        CalendarGuideRow(
          'sync-cadence',
          Icons.autorenew_rounded,
          l10n.syncGuideCadenceTitle,
          l10n.syncGuideCadenceBody(l10n.syncAutomatic, l10n.syncNow),
        ),
        CalendarGuideRow(
          'sync-other',
          Icons.devices_rounded,
          l10n.syncGuideOtherTitle,
          l10n.syncGuideOtherBody(l10n.syncThisDatabase),
        ),
      ],
      pair => [
        CalendarGuideRow(
          'pair-one',
          Icons.people_alt_rounded,
          l10n.syncGuidePairOneTitle,
          l10n.syncGuidePairOneBody(l10n.unpair),
        ),
        CalendarGuideRow(
          'pair-code',
          Icons.pin_rounded,
          l10n.syncGuidePairCodeTitle,
          l10n.syncGuidePairCodeBody(
            l10n.pairingSection,
            l10n.sharingSettings,
            l10n.pairingGenerateCode,
            l10n.pairingEnterCode,
          ),
        ),
        CalendarGuideRow(
          'pair-sync',
          Icons.cloud_sync_rounded,
          l10n.syncGuidePairSyncTitle,
          l10n.syncGuidePairSyncBody(l10n.syncThisDatabase),
        ),
        CalendarGuideRow(
          'pair-empty',
          Icons.inbox_rounded,
          l10n.syncGuidePairEmptyTitle,
          l10n.syncGuidePairEmptyBody,
        ),
      ],
      offline => [
        CalendarGuideRow(
          'offline-normal',
          Icons.wifi_off_rounded,
          l10n.syncGuideOfflineNormalTitle,
          l10n.syncGuideOfflineNormalBody(l10n.syncOffline),
        ),
        CalendarGuideRow(
          'offline-conflict',
          Icons.call_split_rounded,
          l10n.syncGuideOfflineConflictTitle,
          l10n.syncGuideOfflineConflictBody,
        ),
        CalendarGuideRow(
          'offline-close',
          Icons.exit_to_app_rounded,
          l10n.syncGuideOfflineCloseTitle,
          l10n.syncGuideOfflineCloseBody,
        ),
      ],
      event => [
        CalendarGuideRow(
          'event-switch',
          Icons.toggle_on_rounded,
          l10n.syncGuideEventSwitchTitle,
          l10n.syncGuideEventSwitchBody(shareWith),
        ),
        CalendarGuideRow(
          'event-theirs',
          Icons.visibility_rounded,
          l10n.syncGuideEventTheirsTitle,
          l10n.syncGuideEventTheirsBody,
        ),
        CalendarGuideRow(
          'event-follow',
          Icons.update_rounded,
          l10n.syncGuideEventFollowTitle,
          l10n.syncGuideEventFollowBody,
        ),
        CalendarGuideRow(
          'event-copy',
          Icons.content_copy_rounded,
          l10n.syncGuideEventCopyTitle,
          l10n.syncGuideEventCopyBody(l10n.sharedEventCopy),
        ),
      ],
      category => [
        CalendarGuideRow(
          'category-where',
          Icons.toggle_on_rounded,
          l10n.syncGuideCategoryWhereTitle,
          l10n.syncGuideCategoryWhereBody(
            shareWith,
            l10n.calendarCategories,
            sharingPage,
            l10n.shareRowCategories,
          ),
        ),
        CalendarGuideRow(
          'category-all',
          Icons.done_all_rounded,
          l10n.syncGuideCategoryAllTitle,
          l10n.syncGuideCategoryAllBody,
        ),
        // The switch's reading names the category; the guide has none to
        // name, so it quotes the reading around an ellipsis.
        CalendarGuideRow(
          'category-out',
          Icons.drive_file_move_rounded,
          l10n.syncGuideCategoryOutTitle,
          l10n.syncGuideCategoryOutBody(l10n.shareThroughCategory('…')),
        ),
        CalendarGuideRow(
          'category-theirs',
          Icons.move_to_inbox_rounded,
          l10n.syncGuideCategoryTheirsTitle,
          l10n.syncGuideCategoryTheirsBody(l10n.calendarCategories),
        ),
      ],
      folder => [
        CalendarGuideRow(
          'folder-where',
          Icons.toggle_on_rounded,
          l10n.syncGuideFolderWhereTitle,
          l10n.syncGuideFolderWhereBody(
            shareWith,
            l10n.shareAddFolder,
            sharingPage,
            l10n.shareRowFolders,
          ),
        ),
        CalendarGuideRow(
          'folder-inside',
          Icons.account_tree_rounded,
          l10n.syncGuideFolderInsideTitle,
          l10n.syncGuideFolderInsideBody,
        ),
        CalendarGuideRow(
          'folder-readonly',
          Icons.lock_outline_rounded,
          l10n.syncGuideFolderReadOnlyTitle,
          l10n.syncGuideFolderReadOnlyBody(l10n.sharedNoteCopy),
        ),
        CalendarGuideRow(
          'folder-note',
          Icons.description_rounded,
          l10n.syncGuideFolderNoteTitle,
          l10n.syncGuideFolderNoteBody,
        ),
      ],
      look => [
        CalendarGuideRow(
          'look-events',
          Icons.event_note_rounded,
          l10n.syncGuideLookEventsTitle,
          l10n.syncGuideLookEventsBody(
            l10n.shareEventLook,
            sharingPage,
            l10n.shareLookOutlined,
            l10n.shareLookAvatar,
            l10n.shareLookPlain,
          ),
        ),
        CalendarGuideRow(
          'look-notes',
          Icons.sticky_note_2_outlined,
          l10n.syncGuideLookNotesTitle,
          l10n.syncGuideLookNotesBody(
            l10n.shareNoteLook,
            l10n.shareLookAvatar,
            l10n.shareLookPlain,
          ),
        ),
        // Named as the switch it explains, so the two are one thing to find.
        CalendarGuideRow(
          'look-mark',
          Icons.bookmark_border_rounded,
          l10n.shareMarkMine,
          l10n.syncGuideLookMarkBody,
        ),
        CalendarGuideRow(
          'look-hide',
          Icons.visibility_off_rounded,
          l10n.syncGuideLookHideTitle,
          l10n.syncGuideLookHideBody(sharingPage, l10n.shareRowCategories),
        ),
      ],
      alerts => [
        CalendarGuideRow(
          'alerts-choices',
          Icons.tune_rounded,
          l10n.syncGuideAlertsChoicesTitle,
          l10n.syncGuideAlertsChoicesBody(
            l10n.shareAlerts,
            sharingPage,
            l10n.shareAlertsOff,
            l10n.shareAlertsOwn,
            l10n.shareAlertsCategory,
          ),
        ),
        CalendarGuideRow(
          'alerts-own',
          Icons.add_alert_rounded,
          l10n.syncGuideAlertsOwnTitle,
          l10n.syncGuideAlertsOwnBody,
        ),
        // What is true on the device the guide is read on, as the read
        // sheet's caption says.
        CalendarGuideRow(
          'alerts-follow',
          Icons.update_rounded,
          l10n.syncGuideAlertsFollowTitle,
          SharedRefreshAvailability.isSupported
              ? l10n.syncGuideAlertsFollowFreshBody
              : l10n.syncGuideAlertsFollowLastReceivedBody,
        ),
        CalendarGuideRow(
          'alerts-from',
          Icons.person_rounded,
          l10n.syncGuideAlertsFromTitle,
          l10n.syncGuideAlertsFromBody,
        ),
      ],
      stop => [
        CalendarGuideRow(
          'stop-one',
          Icons.toggle_off_rounded,
          l10n.syncGuideStopOneTitle,
          l10n.syncGuideStopOneBody,
        ),
        CalendarGuideRow(
          'stop-all',
          Icons.remove_done_rounded,
          l10n.syncGuideStopAllTitle,
          l10n.syncGuideStopAllBody(l10n.shareStopAll, sharingPage),
        ),
        // Named as the button it explains.
        CalendarGuideRow(
          'stop-unpair',
          Icons.link_off_rounded,
          l10n.unpair,
          l10n.syncGuideStopUnpairBody(sharingPage),
        ),
        CalendarGuideRow(
          'stop-when',
          Icons.schedule_rounded,
          l10n.syncGuideStopWhenTitle,
          l10n.syncGuideStopWhenBody,
        ),
        CalendarGuideRow(
          'stop-sync',
          Icons.logout_rounded,
          l10n.syncGuideStopSyncTitle,
          l10n.syncGuideStopSyncBody(
            l10n.syncStop,
            l10n.syncDeleteCloud,
            l10n.syncDeleteAccount,
            l10n.sharingSettings,
          ),
        ),
      ],
      private => [
        CalendarGuideRow(
          'private-never',
          Icons.visibility_off_outlined,
          l10n.syncGuidePrivateNeverTitle,
          l10n.syncGuidePrivateNeverBody,
        ),
        CalendarGuideRow(
          'private-readonly',
          Icons.lock_outline_rounded,
          l10n.syncGuidePrivateReadOnlyTitle,
          l10n.syncGuidePrivateReadOnlyBody,
        ),
        CalendarGuideRow(
          'private-backups',
          Icons.backup_rounded,
          l10n.syncGuidePrivateBackupsTitle,
          l10n.syncGuidePrivateBackupsBody,
        ),
        // Named as the row it points at, so the two are one thing to find.
        CalendarGuideRow(
          'private-data',
          Icons.privacy_tip_outlined,
          l10n.dataNoticeTitle,
          l10n.syncGuidePrivateDataBody(
            l10n.dataNoticeTitle,
            l10n.sharingSettings,
          ),
        ),
      ],
    };
  }
}
