import 'dart:convert';

import 'package:equatable/equatable.dart';

/// The destinations the app can rebuild from nothing but a settings row.
///
/// This enum **is** the restore allowlist. A page earns a member here only if
/// its identity is fully expressible as strings (no callbacks, no live model
/// objects, no bloc-supplied arguments) and it is somewhere a user parks
/// rather than passes through. That excludes `ShortcutEditorPage` (carries an
/// `onSave` closure), `CounterPerNotePage` (carries a `Counter`),
/// `MarkdownSettingsPage` (needs `allShortcuts` from `MarkdownBarBloc`),
/// `SearchPage` (a query surface, not a place — restoring it empty is
/// pointless and restoring a stale query is worse) and `DeveloperOptionsPage`
/// (gated, and a cold launch into it is pure surprise).
///
/// Names are persisted, so they are load-bearing: rename a member and every
/// existing install's stored stack truncates at that entry.
enum NavDestinationKind {
  folder,
  note,
  calendar,
  calendarSettings,
  calendarCategories,
  eventTemplates,
  vocabularies,
  databaseSettings,
  settings,
  syncSettings,
  counterManagement;

  /// Whether popping this page should raise the drawer beneath it.
  ///
  /// Mirrors how the page is reached in the running app: the drawer's
  /// settings rows await their push and reopen the drawer on
  /// `SettingsResult.openDrawer`, while Calendar deliberately does not — it
  /// sits above the divider as a feature, not a setting. Restore has to
  /// reproduce that distinction, because a restored page has no awaiting
  /// drawer row to reproduce it for.
  bool get reopensDrawerOnPop => switch (this) {
    NavDestinationKind.databaseSettings ||
    NavDestinationKind.settings ||
    NavDestinationKind.syncSettings ||
    NavDestinationKind.counterManagement => true,
    _ => false,
  };

  /// Whether this destination belongs to the folder/note substrate rather
  /// than to the calendar or settings layered on top. Backs the "folders and
  /// notes" restore mode.
  bool get isNoteSubstrate =>
      this == NavDestinationKind.folder || this == NavDestinationKind.note;

  /// Forward-compatible parsing: an unknown name (a kind written by a newer
  /// build) yields `null` so the caller can truncate rather than throw.
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

  static const String _folderIdKey = 'folderId';
  static const String _titleKey = 'title';
  static const String _noteIdKey = 'noteId';

  /// Bumped only if the *list* semantics change — a new kind alone does not
  /// need it, since unknown kinds already truncate. A version this build does
  /// not recognise means "restore nothing", never a crash.
  static const int stackVersion = 1;

  final NavDestinationKind kind;
  final Map<String, String> params;

  String? get folderId => params[_folderIdKey];
  String? get noteId => params[_noteIdKey];
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
  /// a malformed entry, or a kind whose required params are missing. Callers
  /// treat `null` as "truncate here": every entry's parent precedes it, so a
  /// prefix of the stack is always a coherent chain.
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
  /// An entry this build cannot rebuild truncates the stack there, keeping
  /// the surviving prefix — the user lands on the deepest ancestor we can
  /// prove we can restore.
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
        if (destination == null) break;
        stack.add(destination);
      }
      return stack;
    } on FormatException {
      return const [];
    }
  }

  @override
  List<Object?> get props => [kind, params];

  @override
  String toString() =>
      params.isEmpty ? 'NavDestination(${kind.name})' : 'NavDestination(${kind.name}, $params)';
}
