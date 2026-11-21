import 'calendar_category.dart';
import 'calendar_event.dart';
import 'folder.dart';
import 'guide_sync_world.dart';
import 'note_metadata.dart';
import 'share_settings.dart';

/// Everything one two-phone "Try it" card holds (`docs/guide-hub-roadmap.md`
/// §11.3): her side, what has reached the other phone, and nothing else.
/// Owned by the card's demo and gone with the page — never written to the
/// database, a setting or a preference (D41), so a stage may be tried by
/// someone who never signed in.
///
/// What the other phone shows is derived from her side and what has
/// arrived ([theirs]), never stored a second time: a change she makes is in
/// flight ([inFlight]) until [deliver] — the stage's beat (D47) — lands it.
///
/// How it grows for the next cards, without a rewrite: each kind they teach
/// — categories, folders, notes — takes the pair events have here, her items
/// with her marks and the marks as the other phone last received them, and
/// [deliver] copies every kind's marks in one step. The looks and the alert
/// choice are the receiving phone's own settings — hers, on the cards about
/// her phone alone, where what Sam shares ([partnerEvents]) arrives — plain
/// fields that travel nowhere; pairing is a flag [deliver] waits on, as a sync card's "online" of
/// each phone is, whose two phones hold notes of their own and land what
/// waits when both are online.
final class GuideShareWorld {
  GuideShareWorld({
    required this.day,
    required List<CalendarEvent> events,
    List<CalendarCategory> categories = const [],
    List<Folder> folders = const [],
    List<NoteMetadata> notes = const [],
    List<CalendarEvent> partnerEvents = const [],
    ShareLook look = const ShareLook(),
    ShareAlerts shareAlerts = ShareAlerts.own,
    Set<String> ownAlerts = const {},
    Set<String> alarmedCategories = const {},
    bool paired = true,
    this.sync,
  }) : _paired = paired,
       _arrivedPaired = paired,
       _events = List.of(events),
       categories = List.unmodifiable(categories),
       folders = List.unmodifiable(folders),
       notes = List.unmodifiable(notes),
       partnerEvents = List.unmodifiable([
         for (final event in partnerEvents) asTheirs(event),
       ]),
       _look = look,
       _shareAlerts = shareAlerts,
       ownAlerts = Set.unmodifiable(ownAlerts),
       alarmedCategories = Set.unmodifiable(alarmedCategories),
       // What stands on her phone when the page opens has long reached the
       // other one; only what she adds on the stage travels.
       _landed = {for (final event in events) event.id};

  /// The one day her events stand on, date-only UTC.
  final DateTime day;

  /// A sync card's two phones of her own (§11.4 `sync`, `offline`): their
  /// notes, each phone's connection and what waits — a world of its own,
  /// held here so every card and step reads one world; null on a sharing
  /// card, whose phones are hers and Sam's.
  final GuideSyncWorld? sync;

  final List<CalendarEvent> _events;

  /// Her events of [day], in the order her phone lists them — the seed, then
  /// each one she added ([addEvent]).
  List<CalendarEvent> get events => List.unmodifiable(_events);

  /// Her categories, in the order her Categories page lists them.
  final List<CalendarCategory> categories;

  /// Her folders, in the order her browser lists them.
  final List<Folder> folders;

  /// Her notes, each in one of [folders].
  final List<NoteMetadata> notes;

  /// What Sam shares with her, on [day]: Sam's events as they stand on her
  /// phone — read-only, flagged as the partner's. The cards about her phone
  /// alone draw them among her own; nothing she does sends them anywhere.
  final List<CalendarEvent> partnerEvents;

  /// The events she added an alert of her own to — on a partner's event, a
  /// row of hers that rings or not as [shareAlerts] says.
  final Set<String> ownAlerts;

  /// Her categories that carry an alert of their own.
  final Set<String> alarmedCategories;

  ShareLook _look;

  /// How her phone draws what is shared: the Sharing page's "How shared
  /// things look" as it stands on the stage.
  ShareLook get look => _look;

  /// Every events look she has picked since the page opened — never the one
  /// the page opened on, so a step about a look is done by choosing it.
  final Set<ShareEventLook> _eventLooksPicked = {};

  /// She picks how a partner's events are drawn.
  void setEventLook(ShareEventLook value) {
    _look = _look.copyWith(eventLook: value);
    _eventLooksPicked.add(value);
  }

  /// She picks how a partner's folders and notes are drawn.
  void setNoteLook(ShareNoteLook value) =>
      _look = _look.copyWith(noteLook: value);

  /// Her switch for the sign on what she shares.
  void setMarkMine(bool on) => _look = _look.copyWith(markMine: on);

  /// She has picked [value] for the events' look on the stage.
  bool pickedEventLook(ShareEventLook value) =>
      _eventLooksPicked.contains(value);

  ShareAlerts _shareAlerts;

  /// What may ring on her phone for a partner's event: the Sharing page's
  /// "Alerts for shared events" as it stands on the stage.
  ShareAlerts get shareAlerts => _shareAlerts;

  /// Every choice she has made for [shareAlerts] since the page opened —
  /// never the one it opened on.
  final Set<ShareAlerts> _alertsPicked = {};

  void setShareAlerts(ShareAlerts value) {
    _shareAlerts = value;
    _alertsPicked.add(value);
  }

  /// She has chosen [value] for [shareAlerts] on the stage.
  bool pickedAlerts(ShareAlerts value) => _alertsPicked.contains(value);

  /// What would ring for [event] on her phone: her own alert on it, and her
  /// category's — each only as far as the app's own rule
  /// ([ShareAlerts.inheritsOn]) arms it, so the stage never says more rings
  /// than the scheduler would arm.
  ({bool own, bool categoryAlarm}) ringsFor(CalendarEvent event) {
    final inherits = _shareAlerts.inheritsOn(event);
    if (inherits == null) return (own: false, categoryAlarm: false);
    return (
      own: ownAlerts.contains(event.id),
      categoryAlarm: inherits && alarmedCategories.contains(event.categoryId),
    );
  }

  /// The events she marks shared: what her switches say.
  final Set<String> _shared = {};

  /// Her marks as the other phone last received them.
  Set<String> _arrived = const {};

  /// Every event she has shared since the page opened, so taking one back
  /// is something the world shows rather than a tap.
  final Set<String> _everShared = {};

  /// Every event the other phone has shown since the page opened, so one
  /// leaving it is something the world shows ([takenBack]).
  final Set<String> _everArrived = {};

  /// The events the other phone has received at all, shared or not: an
  /// event she adds reaches it only with the beat.
  Set<String> _landed;

  /// The events she added on the stage.
  final Set<String> _added = {};

  final Set<String> _sharedCategories = {};
  Set<String> _arrivedCategories = const {};

  final Set<String> _sharedFolders = {};
  Set<String> _arrivedFolders = const {};

  /// Whether she is paired, and whether the other phone last heard so —
  /// both from the start on every card but the one that makes the pair.
  bool _paired;
  bool _arrivedPaired;

  /// The code her phone made (`pair` card), as the pairing service stores
  /// one, and when it runs out: the real life of an invite from the moment
  /// it was made, which the stage holds still.
  String? _code;
  DateTime? _codeMadeAt;
  DateTime? _codeExpiresAt;

  /// The other phone entered her code and the pair is on its way to both.
  bool _redeemed = false;

  /// The event the other phone has open in its read sheet, if any.
  String? _theirOpen;

  /// The folder the other phone has open, if any.
  String? _theirFolderOpen;

  /// Her notes the other phone copied into its own, in the order copied.
  final List<String> _copied = [];

  bool isShared(String eventId) => _shared.contains(eventId);

  /// She shares at least one event.
  bool get sharesAny => _shared.isNotEmpty;

  /// She shares anything at all — an event, a category or a folder.
  bool get sharesAnything =>
      _shared.isNotEmpty ||
      _sharedCategories.isNotEmpty ||
      _sharedFolders.isNotEmpty;

  /// An event she shared is no longer shared — the un-share, whether or not
  /// it has reached the other phone yet.
  bool get withdrawn => _everShared.any((id) => !_shared.contains(id));

  /// An event the other phone showed has left it: taken back as Sam sees
  /// it, which a share undone within one beat never is — nothing arrived.
  bool get takenBack {
    final shown = {for (final event in theirs) event.id};
    return _everArrived.any((id) => !shown.contains(id));
  }

  /// [eventId] reached the other phone and has left it since — [takenBack]
  /// for one event, so a step about that event is not done by another's.
  bool hasLeft(String eventId) =>
      _everArrived.contains(eventId) &&
      theirs.every((event) => event.id != eventId);

  /// Her switch on [eventId]. Nothing reaches the other phone until
  /// [deliver].
  void share(String eventId, bool on) {
    assert(_events.any((event) => event.id == eventId), eventId);
    if (on) {
      _shared.add(eventId);
      _everShared.add(eventId);
    } else {
      _shared.remove(eventId);
    }
  }

  bool isCategoryShared(String categoryId) =>
      _sharedCategories.contains(categoryId);

  /// Her mark on a whole category: every event in it, and every one she
  /// adds to it later, goes with it.
  void shareCategory(String categoryId, bool on) {
    assert(categories.any((c) => c.id == categoryId), categoryId);
    if (on) {
      _sharedCategories.add(categoryId);
    } else {
      _sharedCategories.remove(categoryId);
    }
  }

  /// Her events filed under [categoryId].
  int eventCountOf(String categoryId) =>
      _events.where((event) => event.categoryId == categoryId).length;

  /// She adds [event] to her day. It reaches the other phone with the next
  /// beat, shared or not as its category or its own mark says.
  void addEvent(CalendarEvent event) {
    assert(_events.every((e) => e.id != event.id), event.id);
    _events.add(event);
    _added.add(event.id);
  }

  /// She added an event on the stage.
  bool get addedAny => _added.isNotEmpty;

  bool isAdded(String eventId) => _added.contains(eventId);

  bool isFolderShared(String folderId) => _sharedFolders.contains(folderId);

  /// Her mark on a folder: its notes go with it.
  void shareFolder(String folderId, bool on) {
    assert(folders.any((f) => f.id == folderId), folderId);
    if (on) {
      _sharedFolders.add(folderId);
    } else {
      _sharedFolders.remove(folderId);
    }
  }

  /// Her notes in [folderId].
  List<NoteMetadata> notesIn(String folderId) => [
    for (final note in notes)
      if (note.folderId == folderId) note,
  ];

  bool get paired => _paired;

  /// Whether the other phone still holds the pair.
  bool get theirPaired => _arrivedPaired;

  /// Takes back everything she shares and keeps the pair.
  void stopAll() {
    _shared.clear();
    _sharedCategories.clear();
    _sharedFolders.clear();
  }

  /// Ends the pair: nothing of hers is shared any more, and the other phone
  /// learns it with the beat.
  void unpair() {
    stopAll();
    _paired = false;
  }

  String? get code => _code;
  DateTime? get codeMadeAt => _codeMadeAt;
  DateTime? get codeExpiresAt => _codeExpiresAt;

  /// Her phone makes [code] at [madeAt], good until [expiresAt]. One code at
  /// a time, as the pairing sheet holds one invite.
  void makeCode(String code, DateTime madeAt, DateTime expiresAt) {
    _code = code;
    _codeMadeAt = madeAt;
    _codeExpiresAt = expiresAt;
  }

  /// The other phone enters [code], as normalized: her code, while neither
  /// phone is paired, sets the pair on its way — both phones hold it once
  /// the beat lands ([deliver]); anything else pairs nobody. Whether the
  /// code was taken.
  bool redeem(String code) {
    if (_code == null || code != _code || _paired || _redeemed) return false;
    _redeemed = true;
    return true;
  }

  /// A right code was entered and has yet to land.
  bool get redeeming => _redeemed && !_paired;

  static bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// What she changed has not reached the other phone yet.
  bool get inFlight =>
      !_same(_shared, _arrived) ||
      !_same(_sharedCategories, _arrivedCategories) ||
      !_same(_sharedFolders, _arrivedFolders) ||
      _landed.length != _events.length ||
      _paired != _arrivedPaired ||
      redeeming;

  /// Every change in flight reaches the other phone at once — and a code
  /// the other phone entered pairs both. A folder it had open that is no
  /// longer shared closes there, as a partner's page does.
  void deliver() {
    if (_redeemed) _paired = true;
    _arrived = Set.unmodifiable(_shared);
    _arrivedCategories = Set.unmodifiable(_sharedCategories);
    _arrivedFolders = Set.unmodifiable(_sharedFolders);
    _landed = {for (final event in _events) event.id};
    _arrivedPaired = _paired;
    _everArrived.addAll([for (final event in theirs) event.id]);
    if (_theirFolderOpen case final open?
        when !theirFolders.any((f) => f.id == open)) {
      _theirFolderOpen = null;
    }
  }

  /// The other phone's day: the events whose share has arrived — their own
  /// or their category's — as a partner's events reach a phone: read-only,
  /// marked as from her. Nothing while the pair is over.
  List<CalendarEvent> get theirs => [
    if (_arrivedPaired)
      for (final event in _events)
        if (_landed.contains(event.id) &&
            (_arrived.contains(event.id) ||
                _arrivedCategories.contains(event.categoryId)))
          asTheirs(event),
  ];

  String? get theirOpen => _theirOpen;

  /// The other phone opens [eventId]'s read sheet; only an event it shows.
  void openTheirs(String eventId) {
    assert(_arrived.contains(eventId), eventId);
    _theirOpen = eventId;
  }

  void closeTheirs() => _theirOpen = null;

  /// The other phone's folders from her: those whose share has arrived, as
  /// a partner's folders reach a phone.
  List<Folder> get theirFolders => [
    if (_arrivedPaired)
      for (final folder in folders)
        if (_arrivedFolders.contains(folder.id))
          folder.copyWith(fromPartner: true, share: FolderShare.none),
  ];

  String? get theirFolderOpen => _theirFolderOpen;

  /// The other phone opens [folderId]; only a folder it shows.
  void openTheirFolder(String folderId) {
    assert(theirFolders.any((f) => f.id == folderId), folderId);
    _theirFolderOpen = folderId;
  }

  void closeTheirFolder() => _theirFolderOpen = null;

  /// The notes of [folderId] as the other phone reads them: hers, marked as
  /// from her.
  List<NoteMetadata> theirNotesIn(String folderId) => [
    for (final note in notesIn(folderId)) _noteAsTheirs(note),
  ];

  /// The other phone keeps a copy of [noteId] among its own notes. The copy
  /// is theirs at once — no beat, nothing of hers changes.
  void copyTheirs(String noteId) {
    assert(notes.any((note) => note.id == noteId), noteId);
    _copied.add(noteId);
  }

  /// How many notes the other phone copied from hers.
  int get copyCount => _copied.length;

  /// The other phone's copies, in the order copied: each her note's own
  /// fields, unmarked — a copy is theirs, not shared.
  List<NoteMetadata> get copies => [
    for (final id in _copied) notes.firstWhere((note) => note.id == id),
  ];

  /// [event] as it arrives on a partner's phone: its own fields, flagged as
  /// the partner's, never marked as shared by its reader. Public for a
  /// stage's template, which draws what the other phone may come to show.
  static CalendarEvent asTheirs(CalendarEvent event) => CalendarEvent(
    id: event.id,
    title: event.title,
    categoryId: event.categoryId,
    startDate: event.startDate,
    rule: event.rule,
    time: event.time,
    description: event.description,
    iconKey: event.iconKey,
    colorValue: event.colorValue,
    tintIcon: event.tintIcon,
    priority: event.priority,
    fromPartner: true,
  );

  static NoteMetadata _noteAsTheirs(NoteMetadata note) => NoteMetadata(
    id: note.id,
    folderId: note.folderId,
    title: note.title,
    preview: note.preview,
    contentLength: note.contentLength,
    chunkCount: note.chunkCount,
    isCompressed: note.isCompressed,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    fromPartner: true,
  );
}
