import 'package:equatable/equatable.dart';

import 'calendar_category.dart';
import 'calendar_event.dart';

/// Through what one of this person's events is shared: its own mark wins,
/// as the grant itself does (`CalendarEventDao.sharedPairsOf`), else its
/// category's.
enum EventShareVia { own, category }

/// One of this person's events shared singly — its own mark is set.
class MySharedEvent extends Equatable {
  final CalendarEvent event;

  /// Its category is shared too, so taking the event's own mark away leaves
  /// it shared all the same.
  final bool categoryShared;

  const MySharedEvent({required this.event, required this.categoryShared});

  @override
  List<Object?> get props => [event, categoryShared];
}

/// A category the partner shares with this person (§6.4): one of the
/// partner's own, or a built-in both have, which draws under this person's
/// own row of the same id.
class PartnerSharedCategory extends Equatable {
  /// The partner's own row, or this person's built-in for [joinsMine].
  final CalendarCategory category;

  /// A built-in the partner shares: its events join this person's own
  /// category of that id (D14).
  final bool joinsMine;

  /// Not in `shareHiddenCategories`: its events show here.
  final bool shown;

  /// The partner's live events in it, hidden or shown.
  final int eventCount;

  const PartnerSharedCategory({
    required this.category,
    required this.joinsMine,
    required this.shown,
    required this.eventCount,
  });

  /// This row with [shown] replaced: [ShareOverview.withPartnerShown] copies
  /// through here, so a field added to the row is carried where it is
  /// declared rather than at every copy.
  PartnerSharedCategory copyWith({bool? shown}) => PartnerSharedCategory(
    category: category,
    joinsMine: joinsMine,
    shown: shown ?? this.shown,
    eventCount: eventCount,
  );

  @override
  List<Object?> get props => [category, joinsMine, shown, eventCount];
}

/// A folder a share act wrote the mark of, by its name as it stood: what a
/// snackbar words and `ShareService.undo` writes back.
class ShareFolderRef extends Equatable {
  final String id;
  final String name;

  const ShareFolderRef({required this.id, required this.name});

  @override
  List<Object?> get props => [id, name];
}

/// One of this person's folders shared with the partner by its own mark, no
/// mark above it covering it — a folder shared through an outer one is not
/// listed apart (§6.2, D37).
class MySharedFolder extends Equatable {
  final String id;
  final String name;

  /// The name of the folder it lies in; null at the root.
  final String? parentName;

  /// The live notes in it and in every folder under it.
  final int noteCount;

  const MySharedFolder({
    required this.id,
    required this.name,
    required this.parentName,
    required this.noteCount,
  });

  @override
  List<Object?> get props => [id, name, parentName, noteCount];
}

/// One of the partner's folders at the top of what they share, as the
/// shared reader placed it: a folder whose parent they keep private stands
/// at the top here (`SharedRowDao.placeFolders`).
class PartnerSharedFolder extends Equatable {
  final String id;
  final String name;

  /// The live notes in it and in every folder under it.
  final int noteCount;

  const PartnerSharedFolder({
    required this.id,
    required this.name,
    required this.noteCount,
  });

  @override
  List<Object?> get props => [id, name, noteCount];
}

/// What the Sharing page lists and says (`docs/cloud-share-surfaces-roadmap.md`
/// §6.1, §6.2), read at one moment by `ShareService.overview`.
class ShareOverview extends Equatable {
  /// This person's shared categories, in the catalogue's order, archived
  /// ones included.
  final List<CalendarCategory> categories;

  /// This person's events shared singly, in the store's start order.
  final List<MySharedEvent> events;

  /// What the partner shares: their own categories by name, then the
  /// built-ins in this person's order.
  final List<PartnerSharedCategory> partnerCategories;

  /// The partner's events that came without a category of theirs — shared
  /// singly from a category they keep private.
  final List<CalendarEvent> partnerEvents;

  /// This person's shared folders by name, read for the Sharing page alone;
  /// empty in a summary's overview, which reads [folderCount] only.
  final List<MySharedFolder> folders;

  /// How many folders [folders] lists, read in a summary too — "1 folder" on
  /// the Pairing row.
  final int folderCount;

  /// The partner's top-level shared folders by name, read for the Sharing
  /// page alone.
  final List<PartnerSharedFolder> partnerFolders;

  /// Whether the partner shares a live folder here, read in a summary too
  /// (the statement [anyMark] comes from), where [partnerFolders] stays
  /// empty.
  final bool partnerSharesFolders;

  /// When the last shared read that read every table to its end finished;
  /// null before the first.
  final DateTime? readAt;

  /// A shared read failed after the last one that completed ("Could not
  /// check"); a read cut by leaving the app is no failure.
  final bool readFailed;

  /// A share act's writes still wait in the outbox ("Sending…"); an
  /// ordinary edit queued alone says nothing.
  final bool sending;

  /// While [sending]: every share entry still queued is one the push set
  /// aside, which the Sync page lists as held back and no run sends until a
  /// start or "Sync now" — "Waiting to send", as offline, never "Sending…"
  /// for ever.
  final bool sendingParked;

  /// The engine's last call found no network ("Waiting to send").
  final bool offline;

  /// The partner writes documents this build cannot read yet ("Update
  /// ANTA").
  final bool partnerNewerWire;

  /// The partner's rows not shown because a row of this person's holds
  /// their id ("{n} items could not be shown").
  final int refusedCount;

  /// Any live category, event or folder of this database carries a share
  /// mark, as the database says (`SyncDao.anyLiveShareMark`) — folders
  /// included, which [categories] and [events] do not list. A deleted row's
  /// mark is not counted: nothing the person can see is shared through it.
  final bool anyMark;

  /// This person's live events per category id, the tick sheet's counts —
  /// read with the rest so the page asks its bloc, never the calendar. Read
  /// for the Sharing page alone; empty in a summary's overview.
  final Map<String, int> eventCounts;

  const ShareOverview({
    this.categories = const [],
    this.events = const [],
    this.partnerCategories = const [],
    this.partnerEvents = const [],
    this.folders = const [],
    this.folderCount = 0,
    this.partnerFolders = const [],
    this.partnerSharesFolders = false,
    this.readAt,
    this.readFailed = false,
    this.sending = false,
    this.sendingParked = false,
    this.offline = false,
    this.partnerNewerWire = false,
    this.refusedCount = 0,
    this.anyMark = false,
    this.eventCounts = const {},
  });

  /// What an account that is not paired is shown: nothing, read from
  /// nowhere.
  static const empty = ShareOverview();

  /// How old the last completed read may grow before the Sharing page says
  /// "May be out of date" (D22). Nothing is removed for age: the rows stay
  /// readable on a long trip without a network.
  static const Duration staleAfter = Duration(days: 7);

  /// Whether the last completed read is [staleAfter] old or more at [now];
  /// never before the first read, which is "not read yet", not "old".
  bool isStale(DateTime now) {
    final at = readAt;
    return at != null && now.difference(at) >= staleAfter;
  }

  /// Whether this person shares anything — what enables "Stop sharing
  /// everything", which clears folders too.
  bool get sharesAnything =>
      anyMark || categories.isNotEmpty || events.isNotEmpty;

  /// Whether this phone holds anything the partner shares — a category,
  /// an event shared singly, a folder — in a summary as on the Sharing
  /// page: what "Stop syncing" says leaves the phone (D30).
  bool get holdsPartnerRows =>
      partnerCategories.isNotEmpty ||
      partnerEvents.isNotEmpty ||
      partnerFolders.isNotEmpty ||
      partnerSharesFolders;

  /// This overview with the partner's category [id] shown or hidden and
  /// every other field as it stands: what the bloc shows from a switch's
  /// tap until that write's own read lands, so the switch never waits on
  /// storage. A field added to this class is carried here too.
  ShareOverview withPartnerShown(String id, bool shown) => ShareOverview(
    categories: categories,
    events: events,
    partnerCategories: [
      for (final shared in partnerCategories)
        shared.category.id == id ? shared.copyWith(shown: shown) : shared,
    ],
    partnerEvents: partnerEvents,
    folders: folders,
    folderCount: folderCount,
    partnerFolders: partnerFolders,
    partnerSharesFolders: partnerSharesFolders,
    readAt: readAt,
    readFailed: readFailed,
    sending: sending,
    sendingParked: sendingParked,
    offline: offline,
    partnerNewerWire: partnerNewerWire,
    refusedCount: refusedCount,
    anyMark: anyMark,
    eventCounts: eventCounts,
  );

  @override
  List<Object?> get props => [
    categories,
    events,
    partnerCategories,
    partnerEvents,
    folders,
    folderCount,
    partnerFolders,
    partnerSharesFolders,
    readAt,
    readFailed,
    sending,
    sendingParked,
    offline,
    partnerNewerWire,
    refusedCount,
    anyMark,
    eventCounts,
  ];
}

/// What one share act changed, for its snackbar and its Undo
/// (`docs/cloud-share-surfaces-roadmap.md` §6.3, §6.14): the rows whose mark
/// was written, as they stood before the write — a surface words them, and
/// `ShareService.undo` writes each back.
class ShareChange extends Equatable {
  final List<CalendarCategory> sharedCategories;
  final List<CalendarCategory> unsharedCategories;
  final List<CalendarEvent> sharedEvents;
  final List<CalendarEvent> unsharedEvents;
  final List<ShareFolderRef> sharedFolders;
  final List<ShareFolderRef> unsharedFolders;

  /// Folders inside one of [sharedFolders] whose own mark the act cleared,
  /// since the outer mark now covers them (`FolderDao.setSharedPair`): still
  /// shared, through it — "Lisbon is now shared through Trips". Undo marks
  /// each again.
  final List<ShareFolderRef> coveredFolders;

  /// Folders inside one of [unsharedFolders] whose own mark the act cleared
  /// with it — a mark under a mark only a merge from another device leaves:
  /// un-sharing a folder leaves nothing shared under it
  /// (`FolderDao.setSharedPair`). Undo marks the outer folder alone, which
  /// covers these again: the state the person had.
  final List<ShareFolderRef> clearedInnerFolders;

  /// Events in [unsharedCategories] that stay shared on their own mark
  /// (case C10): "2 events stay shared on their own".
  final int keptOnTheirOwn;

  const ShareChange({
    this.sharedCategories = const [],
    this.unsharedCategories = const [],
    this.sharedEvents = const [],
    this.unsharedEvents = const [],
    this.sharedFolders = const [],
    this.unsharedFolders = const [],
    this.coveredFolders = const [],
    this.clearedInnerFolders = const [],
    this.keptOnTheirOwn = 0,
  });

  /// Nothing was written: no snackbar, no Undo.
  static const none = ShareChange();

  bool get isEmpty =>
      sharedCategories.isEmpty &&
      unsharedCategories.isEmpty &&
      sharedEvents.isEmpty &&
      unsharedEvents.isEmpty &&
      sharedFolders.isEmpty &&
      unsharedFolders.isEmpty;

  @override
  List<Object?> get props => [
    sharedCategories,
    unsharedCategories,
    sharedEvents,
    unsharedEvents,
    sharedFolders,
    unsharedFolders,
    coveredFolders,
    clearedInnerFolders,
    keptOnTheirOwn,
  ];
}
