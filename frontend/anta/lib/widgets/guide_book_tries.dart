import '../models/calendar_guide_content.dart';
import '../models/sync_guide_tries.dart';
import 'calendar_guide_try_card.dart';
import 'guide_sync_try_alerts.dart';
import 'guide_sync_try_category.dart';
import 'guide_sync_try_conflict.dart';
import 'guide_sync_try_event.dart';
import 'guide_sync_try_folder.dart';
import 'guide_sync_try_look.dart';
import 'guide_sync_try_offline.dart';
import 'guide_sync_try_pair.dart';
import 'guide_sync_try_stop.dart';
import 'guide_sync_try_sync.dart';

/// The demo behind a book page's card that is no editor
/// (`GuideTopic.demoCards`, `docs/guide-hub-roadmap.md` §11.3). It lives in
/// the widgets layer because a demo builds the stage's widgets and a model
/// cannot name one; a new card adds its line here.
///
/// [now] is the clock a card reads its day from, once.
GuideCardDemo guideBookCardDemo(
  GuideCardSpec card, {
  DateTime Function() now = DateTime.now,
}) => switch (card) {
  SyncGuideTries.sync => GuideSyncSyncDemo(card, now: now),
  SyncGuideTries.offline => GuideSyncOfflineDemo(card, now: now),
  SyncGuideTries.conflict => GuideSyncConflictDemo(card, now: now),
  SyncGuideTries.pair => GuideSyncPairDemo(card, now: now),
  SyncGuideTries.event => GuideSyncEventDemo(card, now: now),
  SyncGuideTries.category => GuideSyncCategoryDemo(card, now: now),
  SyncGuideTries.folder => GuideSyncFolderDemo(card, now: now),
  SyncGuideTries.stop => GuideSyncStopDemo(card, now: now),
  SyncGuideTries.look => GuideSyncLookDemo(card, now: now),
  SyncGuideTries.alerts => GuideSyncAlertsDemo(card, now: now),
  _ => throw ArgumentError.value(card.slug, 'card', 'No stage for this card'),
};
