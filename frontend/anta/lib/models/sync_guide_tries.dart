import '../constants/calendar_categories.dart';
import '../l10n/app_localizations.dart';
import 'calendar_event.dart';
import 'calendar_guide_coach.dart';
import 'calendar_guide_content.dart';
import 'calendar_guide_demo.dart';
import 'guide_share_world.dart';
import 'share_settings.dart';

/// The two phones of a sync book stage (`docs/guide-hub-roadmap.md` D42,
/// D46): [here] is the phone in her hand, [there] the other — Sam's on a
/// sharing card, her other phone on a sync card. The name is the id's
/// suffix (`…-phone-here` / `…-phone-there`).
enum GuidePhone { here, there }

/// A coach step of a two-phone card: done when [done] reads it off the
/// world (D44), never on a tap, so every road to the result counts alike.
/// Checked after every change on the stage, the beat's landing included.
class GuideShareStep extends GuideCoachStep {
  const GuideShareStep(super.action, super.line, this.done);

  final bool Function(GuideShareWorld world) done;
}

/// The one step that is a tap (D44): opening the other phone, [to]. It
/// counts only once that phone has something to show ([ready]) — a flip
/// before anything was shared looks at nothing — and the flip may come
/// first: a change that lands while she already looks counts the same.
class GuideFlipStep extends GuideCoachStep {
  const GuideFlipStep(
    super.action,
    super.line, {
    required this.to,
    required this.ready,
  });

  final GuidePhone to;
  final bool Function(GuideShareWorld world) ready;
}

/// The sync book's two-phone cards (§11.4), each a slug, its steps and its
/// title. A coach line names a control by the app's own label through a
/// placeholder (D5), and the partner by the guide's "Sam" (D45).
abstract final class SyncGuideTries {
  /// `event`: one switch on the event itself, and what Sam then sees.
  static const GuideCardSpec event = GuideCardSpec('event', [
    GuideShareStep('share', _eventShare, _sharesAny),
    GuideFlipStep(
      'look',
      _eventLook,
      to: GuidePhone.there,
      ready: _theirsShown,
    ),
    GuideShareStep('open', _eventOpen, _theirOpen),
    GuideShareStep('unshare', _eventUnshare, _takenBack),
  ], _eventTitle);

  /// `category`: one mark on the category, and an event added to it later
  /// following by itself.
  static const GuideCardSpec category = GuideCardSpec('category', [
    GuideShareStep('share', _categoryShare, _sharesCategory),
    GuideFlipStep('look', _look, to: GuidePhone.there, ready: _theirsShown),
    GuideShareStep('add', _categoryAdd, _added),
    GuideFlipStep(
      'follow',
      _categoryFollow,
      to: GuidePhone.there,
      ready: _addedArrived,
    ),
  ], _categoryTitle);

  /// `folder`: one mark on the folder, and what Sam can do with its notes.
  static const GuideCardSpec folder = GuideCardSpec('folder', [
    GuideShareStep('share', _folderShare, _sharesFolder),
    GuideFlipStep(
      'look',
      _look,
      to: GuidePhone.there,
      ready: _theirFolderShown,
    ),
    GuideShareStep('open', _folderOpen, _theirFolderOpen),
    GuideShareStep('copy', _folderCopy, _copied),
  ], _folderTitle);

  /// `stop`: every way out, from one event to the pair, each read off Sam's
  /// phone.
  static const GuideCardSpec stop = GuideCardSpec('stop', [
    GuideShareStep('one', _stopOne, _stopEventLeft),
    GuideFlipStep(
      'look',
      _stopLook,
      to: GuidePhone.there,
      ready: _stopEventLeft,
    ),
    GuideShareStep('all', _stopAll, _nothingArrived),
    GuideShareStep('unpair', _stopUnpair, _pairEnded),
  ], _stopTitle);

  /// `pair`: a code made on her phone, entered on Sam's, and the pair both
  /// phones then hold — each step read off the phone it is about.
  static const GuideCardSpec pair = GuideCardSpec('pair', [
    GuideShareStep('invite', _pairInvite, _codeMade),
    GuideFlipStep('look', _look, to: GuidePhone.there, ready: _codeMade),
    GuideShareStep('redeem', _pairRedeem, _samPaired),
    GuideFlipStep('back', _pairBack, to: GuidePhone.here, ready: _herPaired),
  ], _pairTitle);

  /// `look`: her phone alone — the Sharing page's three look rows, and
  /// Sam's events and her shared one drawn as each choice draws them.
  static const GuideCardSpec look = GuideCardSpec('look', [
    GuideShareStep('avatar', _lookAvatar, _pickedAvatar),
    GuideShareStep('plain', _lookPlain, _pickedPlain),
    GuideShareStep('mark', _lookMark, _marksMine),
  ], _lookTitle);

  /// `alerts`: her phone alone — the Sharing page's alerts row, and what
  /// would ring for Sam's event under each of its three choices.
  static const GuideCardSpec alerts = GuideCardSpec('alerts', [
    GuideShareStep('off', _alertsOff, _pickedOff),
    GuideShareStep('own', _alertsOwn, _pickedOwn),
    GuideShareStep('category', _alertsCategory, _pickedCategory),
  ], _alertsTitle);

  /// `sync`: one row turns it on; a note made here reaches the other phone
  /// after the beat, and a tick made there comes back.
  static const GuideCardSpec sync = GuideCardSpec('sync', [
    GuideShareStep('on', _syncOn, _syncsHere),
    GuideShareStep('write', _syncWriteStatus, _wroteSynced),
    GuideFlipStep('look', _syncLook, to: GuidePhone.there, ready: _noteArrived),
    GuideShareStep('edit', _syncEdit, _tickCameBack),
  ], _syncTitle);

  /// `offline`: a note made in airplane mode waits on this phone, and goes
  /// once the phone is back online.
  static const GuideCardSpec offline = GuideCardSpec('offline', [
    GuideShareStep('off', _offlineOff, _hereOffline),
    GuideShareStep('write', _syncWrite, _wroteWaiting),
    GuideFlipStep('look', _syncLook, to: GuidePhone.there, ready: _waited),
    GuideShareStep('on', _offlineOn, _waitedArrived),
  ], _offlineTitle);

  /// `conflict`: one note edited on both phones while offline, and what
  /// both hold once they sync — the later edit, and the other as a copy.
  static const GuideCardSpec conflict = GuideCardSpec('conflict', [
    GuideShareStep('here', _conflictHere, _lineHere),
    GuideShareStep('there', _conflictThere, _lineThere),
    GuideShareStep('online', _conflictOnline, _copiedOnBoth),
  ], _conflictTitle);

  /// The note both phones of the `conflict` card start with.
  static const String packingNote = '${GuideDemoCalendar.idPrefix}packing';

  /// The event the `stop` card's first step takes back on its own.
  static const String stopEvent = '${GuideDemoCalendar.idPrefix}dentist';

  static String _eventTitle(AppLocalizations l10n) => l10n.syncGuideTryEvent;

  static String _eventShare(AppLocalizations l10n) =>
      l10n.syncGuideCoachEventShare(
        l10n.shareWithPartner(l10n.syncGuideDemoPartner),
      );

  static String _eventLook(AppLocalizations l10n) =>
      l10n.syncGuideCoachEventLook(l10n.syncGuideDemoPartner);

  static String _eventOpen(AppLocalizations l10n) =>
      l10n.syncGuideCoachEventOpen;

  static String _eventUnshare(AppLocalizations l10n) =>
      l10n.syncGuideCoachEventUnshare(
        l10n.shareWithPartner(l10n.syncGuideDemoPartner),
      );

  /// "Open Sam's phone." — the one line every sharing card's look shares.
  static String _look(AppLocalizations l10n) =>
      l10n.syncGuideCoachEventLook(l10n.syncGuideDemoPartner);

  /// The category the `category` card shares and adds to, by the app's own
  /// name for the built-in: the coach lines and the stage name it alike.
  static String categoryName(AppLocalizations l10n) =>
      CalendarCategories.builtInLabel(CalendarEventCategory.gym, l10n);

  static String _categoryTitle(AppLocalizations l10n) =>
      l10n.syncGuideTryCategory;

  static String _categoryShare(AppLocalizations l10n) =>
      l10n.syncGuideCoachCategoryShare(
        categoryName(l10n),
        l10n.shareWithPartner(l10n.syncGuideDemoPartner),
      );

  static String _categoryAdd(AppLocalizations l10n) => l10n
      .syncGuideCoachCategoryAdd(l10n.syncGuideAddEventTo(categoryName(l10n)));

  static String _categoryFollow(AppLocalizations l10n) =>
      l10n.syncGuideCoachCategoryFollow(l10n.syncGuideDemoPartner);

  static String _folderTitle(AppLocalizations l10n) => l10n.syncGuideTryFolder;

  static String _folderShare(AppLocalizations l10n) =>
      l10n.syncGuideCoachFolderShare(
        l10n.syncGuideDemoFolderTrips,
        l10n.shareWithPartner(l10n.syncGuideDemoPartner),
      );

  static String _folderOpen(AppLocalizations l10n) =>
      l10n.syncGuideCoachFolderOpen(l10n.syncGuideDemoFolderTrips);

  static String _folderCopy(AppLocalizations l10n) =>
      l10n.syncGuideCoachFolderCopy(l10n.sharedNoteCopy);

  static String _stopTitle(AppLocalizations l10n) => l10n.syncGuideTryStop;

  static String _stopOne(AppLocalizations l10n) =>
      l10n.syncGuideCoachStopOne(l10n.calendarGuideDemoEventDentist);

  /// The one look whose stage draws no words for "from you" before the read
  /// sheet's header: the line says what the outlined picture means.
  static String _stopLook(AppLocalizations l10n) =>
      '${_look(l10n)} ${l10n.syncGuideTryStopFromYou}';

  static String _stopAll(AppLocalizations l10n) =>
      l10n.syncGuideCoachStopAll(l10n.shareStopAll);

  static String _stopUnpair(AppLocalizations l10n) =>
      l10n.syncGuideCoachStopUnpair(l10n.unpair);

  static String _pairTitle(AppLocalizations l10n) => l10n.syncGuideTryPair;

  static String _pairInvite(AppLocalizations l10n) =>
      l10n.syncGuideCoachPairInvite(l10n.pairingGenerateCode);

  static String _pairRedeem(AppLocalizations l10n) =>
      l10n.syncGuideCoachPairRedeem(l10n.pairingConnect);

  static String _pairBack(AppLocalizations l10n) => l10n.syncGuideCoachPairBack;

  static String _lookTitle(AppLocalizations l10n) => l10n.syncGuideTryLook;

  static String _lookAvatar(AppLocalizations l10n) =>
      l10n.syncGuideCoachLookAvatar(l10n.shareEventLook, l10n.shareLookAvatar);

  static String _lookPlain(AppLocalizations l10n) =>
      l10n.syncGuideCoachChooseNext(l10n.shareLookPlain);

  static String _lookMark(AppLocalizations l10n) =>
      l10n.syncGuideCoachLookMark(l10n.shareMarkMine);

  static String _alertsTitle(AppLocalizations l10n) => l10n.syncGuideTryAlerts;

  static String _alertsOff(AppLocalizations l10n) =>
      l10n.syncGuideCoachAlertsOff(l10n.shareAlerts, l10n.shareAlertsOff);

  static String _alertsOwn(AppLocalizations l10n) =>
      l10n.syncGuideCoachChooseNext(l10n.shareAlertsOwn);

  static String _alertsCategory(AppLocalizations l10n) =>
      l10n.syncGuideCoachChooseNext(l10n.shareAlertsCategory);

  static String _syncTitle(AppLocalizations l10n) => l10n.syncGuideTrySync;

  static String _syncOn(AppLocalizations l10n) =>
      l10n.syncGuideCoachSyncOn(l10n.syncThisDatabase);

  static String _syncWrite(AppLocalizations l10n) =>
      l10n.syncGuideCoachSyncWrite(l10n.newNote);

  /// The line after the bind names the lesson the status row draws — its
  /// count of changes sent, then "Up to date" — which is easy to miss while
  /// the line has already moved on (design review B, finding 7).
  static String _syncWriteStatus(AppLocalizations l10n) =>
      l10n.syncGuideCoachSyncWriteStatus(l10n.syncUpToDate, l10n.newNote);

  static String _syncLook(AppLocalizations l10n) => l10n.syncGuideCoachSyncLook;

  static String _syncEdit(AppLocalizations l10n) => l10n.syncGuideCoachSyncEdit;

  static String _offlineTitle(AppLocalizations l10n) =>
      l10n.syncGuideTryOffline;

  static String _offlineOff(AppLocalizations l10n) =>
      l10n.syncGuideCoachOfflineOff;

  static String _offlineOn(AppLocalizations l10n) =>
      l10n.syncGuideCoachOfflineOn;

  static String _conflictTitle(AppLocalizations l10n) =>
      l10n.syncGuideTryConflict;

  static String _conflictHere(AppLocalizations l10n) =>
      l10n.syncGuideCoachConflictHere;

  static String _conflictThere(AppLocalizations l10n) =>
      l10n.syncGuideCoachConflictThere;

  static String _conflictOnline(AppLocalizations l10n) =>
      l10n.syncGuideCoachConflictOnline;

  static bool _syncsHere(GuideShareWorld world) => world.sync!.on;

  /// A note she made is set to travel: made with sync on, or before it and
  /// carried by the bind.
  static bool _wroteSynced(GuideShareWorld world) =>
      world.sync!.on && world.sync!.added.isNotEmpty;

  /// Judged on the other phone: a note she made stands there.
  static bool _noteArrived(GuideShareWorld world) {
    final sync = world.sync!;
    return sync.added.any((id) => sync.noteOn(GuidePhone.there, id) != null);
  }

  /// Judged on this phone: the first line of a note she made stands ticked
  /// here by an edit made on the other phone — a tick made here is no road
  /// to it.
  static bool _tickCameBack(GuideShareWorld world) {
    final sync = world.sync!;
    return sync.added.any((id) {
      final note = sync.noteOn(GuidePhone.here, id);
      return note != null &&
          note.ticked.contains(0) &&
          note.editedOn == GuidePhone.there;
    });
  }

  static bool _hereOffline(GuideShareWorld world) =>
      !world.sync!.isOnline(GuidePhone.here);

  /// A note she made waited on this phone for a connection.
  static bool _wroteWaiting(GuideShareWorld world) => world.sync!.waitedAny;

  /// Ready once something waited: looking while it still waits shows
  /// nothing new there, and a look after it went is no dead end.
  static bool _waited(GuideShareWorld world) => world.sync!.waitedAny;

  /// Judged on the other phone: a note that waited here has arrived there.
  static bool _waitedArrived(GuideShareWorld world) {
    final sync = world.sync!;
    return sync.added.any(
      (id) => sync.hasWaited(id) && sync.noteOn(GuidePhone.there, id) != null,
    );
  }

  static bool _lineHere(GuideShareWorld world) =>
      world.sync!.linesAddedOn(GuidePhone.here) > 0;

  static bool _lineThere(GuideShareWorld world) =>
      world.sync!.linesAddedOn(GuidePhone.there) > 0;

  /// A conflict copy stands on both phones — filed where the conflict was
  /// met, and arrived on the other.
  static bool _copiedOnBoth(GuideShareWorld world) {
    final sync = world.sync!;
    return sync.copies.isNotEmpty &&
        sync.copies.every(
          (id) => GuidePhone.values.every(
            (phone) => sync.noteOn(phone, id) != null,
          ),
        );
  }

  /// A look is learnt by choosing it: the one the page opened on counts
  /// only once she picks it again.
  static bool _pickedAvatar(GuideShareWorld world) =>
      world.pickedEventLook(ShareEventLook.avatar);

  static bool _pickedPlain(GuideShareWorld world) =>
      world.pickedEventLook(ShareEventLook.plain);

  static bool _marksMine(GuideShareWorld world) => world.look.markMine;

  /// Each choice counts once she made it, in any order — the app's own
  /// default, which the card opens on, included only when chosen.
  static bool _pickedOff(GuideShareWorld world) =>
      world.pickedAlerts(ShareAlerts.off);

  static bool _pickedOwn(GuideShareWorld world) =>
      world.pickedAlerts(ShareAlerts.own);

  static bool _pickedCategory(GuideShareWorld world) =>
      world.pickedAlerts(ShareAlerts.category);

  static bool _codeMade(GuideShareWorld world) => world.code != null;

  /// Judged on Sam's phone: it holds the pair — landed, not only entered.
  static bool _samPaired(GuideShareWorld world) => world.theirPaired;

  static bool _herPaired(GuideShareWorld world) => world.paired;

  static bool _sharesAny(GuideShareWorld world) => world.sharesAny;

  static bool _theirsShown(GuideShareWorld world) => world.theirs.isNotEmpty;

  static bool _theirOpen(GuideShareWorld world) => world.theirOpen != null;

  /// Judged on Sam's phone: an event that arrived there has left it.
  static bool _takenBack(GuideShareWorld world) => world.takenBack;

  static bool _sharesCategory(GuideShareWorld world) =>
      world.categories.any((c) => world.isCategoryShared(c.id));

  static bool _added(GuideShareWorld world) => world.addedAny;

  /// The event she added stands on Sam's phone — arrived, not only made.
  static bool _addedArrived(GuideShareWorld world) =>
      world.theirs.any((event) => world.isAdded(event.id));

  static bool _sharesFolder(GuideShareWorld world) =>
      world.folders.any((f) => world.isFolderShared(f.id));

  static bool _theirFolderShown(GuideShareWorld world) =>
      world.theirFolders.isNotEmpty;

  static bool _theirFolderOpen(GuideShareWorld world) =>
      world.theirFolderOpen != null;

  /// The copy stands among Sam's own notes.
  static bool _copied(GuideShareWorld world) => world.copyCount > 0;

  /// Judged on Sam's phone: the event taken back on its own has left it —
  /// the ✕ on the category or the folder takes back something else.
  static bool _stopEventLeft(GuideShareWorld world) => world.hasLeft(stopEvent);

  /// Nothing of hers stands on Sam's phone, however it went — the ✕s one
  /// by one, the page's "Stop sharing", or an unpair done first.
  static bool _nothingArrived(GuideShareWorld world) =>
      world.theirs.isEmpty && world.theirFolders.isEmpty;

  /// The pair has ended on both phones.
  static bool _pairEnded(GuideShareWorld world) =>
      !world.paired && !world.theirPaired;
}
