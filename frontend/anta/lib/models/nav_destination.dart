import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The destinations the app can rebuild from nothing but a settings row.
///
/// This enum **is** the restore allowlist. A page earns a member here only if
/// its identity is fully expressible as strings (no callbacks, no live model
/// objects) and it is somewhere a user parks rather than passes through. That
/// excludes `ShortcutEditorPage` (carries an `onSave` closure), the vocabulary
/// editor and the guide's topic page (passed through on the way back to their
/// parent) and `SearchPage` (a query surface, not a place — restoring it empty
/// is pointless and restoring a stale query is worse). Every settings page
/// has one (D3): `counterPerNote` names its counter by id and replay looks it
/// up, `markdownSettings` re-reads its shortcuts from `MarkdownBarBloc`, and
/// `developerOptions` is replayed only while developer mode is unlocked.
///
/// Names are persisted, so they are load-bearing: rename a member and every
/// existing install's stored stack loses that entry. New members are
/// appended.
enum NavDestinationKind {
  folder,
  note,
  calendar,
  calendarSettings,
  calendarCategories,
  calendarAppearance,
  eventTemplates,
  vocabularies,
  databaseSettings,
  settings,
  syncSettings,
  counterManagement,
  allNotes,
  recentNotes,
  alerts,
  permissions,
  calendarOverview,
  calendarGuide,
  calendarReport,
  settingsHub,
  markdownSettings,
  markdownColors,
  noteBarAssignment,
  noteMoneyCurrency,
  counterPerNote,
  developerOptions;

  /// Whether popping this page should raise the drawer beneath it — never,
  /// since back always lands on the route beneath (D3). Nothing reads it any
  /// more; it goes with the settings rework's S7 sweep.
  bool get reopensDrawerOnPop => false;

  /// Whether this destination belongs to the folder/note substrate rather
  /// than to the calendar or settings layered on top. Backs the "folders and
  /// notes" restore mode.
  ///
  /// The two note lists count as substrate: they show nothing but notes, and
  /// a note opened from one of them sits above it — a mode that dropped them
  /// would truncate the chain below that note and lose it too.
  bool get isNoteSubstrate => switch (this) {
    NavDestinationKind.folder ||
    NavDestinationKind.note ||
    NavDestinationKind.allNotes ||
    NavDestinationKind.recentNotes => true,
    _ => false,
  };

  /// Forward-compatible parsing: an unknown name (a kind written by a newer
  /// build) yields `null` so the caller can skip it rather than throw.
  static NavDestinationKind? fromName(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// One entry in the remembered navigation stack — a route the app can push
/// again from cold, described by its [kind] plus whatever string [params]
/// that kind needs to name its target.
///
/// A flat `Map<String, String>` rather than a sealed hierarchy of eleven
/// near-empty subclasses: the compatibility requirement here is fundamentally
/// stringly (a kind this build has never heard of must degrade, not crash),
/// and the map shape makes that the default path instead of a special case.
/// The named constructors and typed getters carry the type safety at the two
/// call sites that actually need it — recording and replay.
class NavDestination extends Equatable {
  const NavDestination(this.kind, [this.params = const {}]);

  NavDestination.folder({required String folderId, required String title})
    : kind = NavDestinationKind.folder,
      params = {_folderIdKey: folderId, _titleKey: title};

  NavDestination.note({required String noteId, required String folderId})
    : kind = NavDestinationKind.note,
      params = {_noteIdKey: noteId, _folderIdKey: folderId};

  NavDestination.counterManagement({String? noteId})
    : kind = NavDestinationKind.counterManagement,
      params = noteId == null || noteId.isEmpty ? const {} : {_noteIdKey: noteId};

  NavDestination.counterPerNote({required String counterId})
    : kind = NavDestinationKind.counterPerNote,
      params = {_counterIdKey: counterId};

  static const String _folderIdKey = 'folderId';
  static const String _titleKey = 'title';
  static const String _noteIdKey = 'noteId';
  static const String _counterIdKey = 'counterId';

  /// Bumped only if the *list* semantics change — a new kind alone does not
  /// need it, since unknown kinds are already skipped. A version this build
  /// does not recognise means "restore nothing", never a crash.
  static const int stackVersion = 1;

  final NavDestinationKind kind;
  final Map<String, String> params;

  String? get folderId => params[_folderIdKey];
  String? get noteId => params[_noteIdKey];
  String? get counterId => params[_counterIdKey];
  String get title => params[_titleKey] ?? '';

  /// A copy carrying a freshly resolved [title] — restore refreshes folder
  /// titles from the database rather than trusting a name stored days ago.
  NavDestination withTitle(String title) => NavDestination(kind, {
    ...params,
    _titleKey: title,
  });

  /// A copy pointing at [folderId] — restore follows a note that was moved
  /// to another folder since it was recorded.
  NavDestination withFolderId(String folderId) => NavDestination(kind, {
    ...params,
    _folderIdKey: folderId,
  });

  Map<String, dynamic> toJson() => {
    'k': kind.name,
    if (params.isNotEmpty) 'p': params,
  };

  /// Returns `null` for anything this build cannot rebuild — an unknown kind,
  /// a malformed entry, or a kind whose required params are missing.
  /// [decodeStack] says which of those it skips and which it truncates at.
  static NavDestination? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = NavDestinationKind.fromName(
      json['k'] is String ? json['k'] as String : null,
    );
    if (kind == null) return null;

    final params = <String, String>{};
    final raw = json['p'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is String) {
          params[entry.key as String] = entry.value as String;
        }
      }
    }

    final destination = NavDestination(kind, params);
    return destination._hasRequiredParams ? destination : null;
  }

  bool get _hasRequiredParams => switch (kind) {
    NavDestinationKind.folder =>
      (folderId ?? '').isNotEmpty && params.containsKey(_titleKey),
    NavDestinationKind.note =>
      (noteId ?? '').isNotEmpty && (folderId ?? '').isNotEmpty,
    NavDestinationKind.counterPerNote => (counterId ?? '').isNotEmpty,
    _ => true,
  };

  /// Encodes a bottom-to-top stack as the single `last_location_stack` value.
  static String encodeStack(List<NavDestination> stack) => jsonEncode({
    'v': stackVersion,
    'stack': [for (final destination in stack) destination.toJson()],
  });

  /// Decodes [encodeStack]'s output, degrading to an empty stack rather than
  /// throwing: a corrupt settings row must never keep the app from launching.
  ///
  /// An entry whose kind this build has never heard of — a newer build's
  /// page — is dropped and the rest kept (settings rework §4.3). That is
  /// sound because no entry is rebuilt from the one beneath it: a folder
  /// carries its own id, a note its own id (replay re-points it at the folder
  /// it lives in now), a settings page nothing, and replay checks each
  /// target's existence on its own, truncating at the first that is gone.
  /// Dropping an entry only takes one page out of the way back.
  ///
  /// Anything else this build cannot rebuild — a malformed entry, a known
  /// kind missing its params — is a damaged row, not a newer one, and still
  /// truncates the stack there, keeping the surviving prefix.
  static List<NavDestination> decodeStack(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || !trimmed.startsWith('{')) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return const [];
      if (decoded['v'] != stackVersion) return const [];
      final entries = decoded['stack'];
      if (entries is! List) return const [];

      final stack = <NavDestination>[];
      for (final entry in entries) {
        final destination = fromJson(entry);
        if (destination != null) {
          stack.add(destination);
        } else if (_isUnknownKind(entry)) {
          continue;
        } else {
          break;
        }
      }
      return stack;
    } on FormatException {
      return const [];
    }
  }

  static bool _isUnknownKind(Object? entry) {
    if (entry is! Map) return false;
    final name = entry['k'];
    return name is String && NavDestinationKind.fromName(name) == null;
  }

  @override
  List<Object?> get props => [kind, params];

  @override
  String toString() =>
      params.isEmpty ? 'NavDestination(${kind.name})' : 'NavDestination(${kind.name}, $params)';
}
