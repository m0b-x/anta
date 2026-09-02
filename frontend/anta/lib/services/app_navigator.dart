import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'dart:async';
import '../models/counter.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/nav_destination.dart';
import '../models/note_metadata.dart';
import '../models/restore_location_mode.dart';
import '../repositories/note_repository.dart';
import '../services/drawer_host_registry.dart';
import '../services/folder_storage_service.dart';
import '../services/navigation_history_service.dart';
import '../services/settings_service.dart';
import '../pages/settings_page.dart';
import '../pages/calendar_page.dart';
import '../pages/calendar_settings_page.dart';
import '../pages/calendar_categories_page.dart';
import '../pages/event_templates_page.dart';
import '../pages/vocabularies_page.dart';
import '../pages/counter_management_page.dart';
import '../pages/counter_per_note_page.dart';
import '../pages/database_settings_page.dart';
import '../pages/developer_options_page.dart';
import '../pages/markdown_colors_page.dart';
import '../pages/markdown_settings_page.dart';
import '../pages/note_bar_assignment_page.dart';
import '../pages/note_money_currency_page.dart';
import '../pages/optimized_folder_content_page.dart';
import '../pages/optimized_note_editor_page.dart';
import '../pages/search_page.dart';
import '../pages/shortcut_editor_page.dart';
import '../pages/sync_settings_page.dart';

enum SettingsResult { openDrawer }

abstract final class AppNavigator {
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Observes route push/pop so pages can react to becoming visible again
  /// (e.g. the calendar reloads events after its settings page closes).
  /// Registered on the root `MaterialApp` alongside
  /// `NavigationHistoryObserver`, which is what tracks the restorable stack.
  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

  static NavigatorState get _navigator => navigatorKey.currentState!;

  /// Stamps a route with the destination that can rebuild it.
  ///
  /// This is the whole contract between navigation and
  /// [NavigationHistoryService]: a stamped route is restorable, an unstamped
  /// one is not, and the observer never has to know page types. Pages that
  /// carry closures or live model objects simply go unstamped.
  static RouteSettings? _settingsFor(NavDestination? destination) {
    if (destination == null) return null;
    return RouteSettings(
      name: destination.kind.name,
      arguments: destination,
    );
  }

  static Future<T?> push<T>(
    BuildContext context,
    Widget page, {
    NavDestination? destination,
  }) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(
        builder: (_) => page,
        settings: _settingsFor(destination),
      ),
    );
  }

  static Future<T?> pushNoAnimation<T>(
    BuildContext context,
    Widget page, {
    Duration reverseTransitionDuration = const Duration(milliseconds: 150),
    NavDestination? destination,
  }) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: reverseTransitionDuration,
        settings: _settingsFor(destination),
      ),
    );
  }

  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    Widget page, {
    TO? result,
  }) {
    return Navigator.pushReplacement<T, TO>(
      context,
      MaterialPageRoute(builder: (_) => page),
      result: result,
    );
  }

  static void pop<T>(BuildContext context, [T? result]) {
    Navigator.pop(context, result);
  }

  static Future<bool> maybePop<T>(BuildContext context, [T? result]) {
    return Navigator.of(context).maybePop(result);
  }

  static void popUntilFirst(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static bool canPop(BuildContext context) {
    return Navigator.canPop(context);
  }

  static Future<T?> rootPush<T>(Widget page, {NavDestination? destination}) {
    return _navigator.push<T>(
      MaterialPageRoute(
        builder: (_) => page,
        settings: _settingsFor(destination),
      ),
    );
  }

  /// Pushes onto the root navigator with no transition. Restore replays a
  /// whole chain at once, and three stacked slide-ins on cold launch read as
  /// a slideshow rather than as an app that never left.
  static Future<T?> rootPushInstant<T>(
    Widget page, {
    NavDestination? destination,
  }) {
    return _navigator.push<T>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 150),
        settings: _settingsFor(destination),
      ),
    );
  }

  static void rootPop<T>([T? result]) {
    _navigator.pop(result);
  }

  // --- Page-specific navigation ---

  static Future<void> toFolder(
    BuildContext context, {
    required String folderId,
    required String title,
  }) {
    return push(
      context,
      OptimizedFolderContentPage(folderId: folderId, title: title),
      destination: NavDestination.folder(folderId: folderId, title: title),
    );
  }

  static Future<void> toNoteEditor(
    BuildContext context, {
    required String folderId,
    String? noteId,
    NoteMetadata? metadata,
  }) {
    return push(
      context,
      OptimizedNoteEditorPage(
        folderId: folderId,
        noteId: noteId,
        metadata: metadata,
      ),
      destination: noteId == null
          ? null
          : NavDestination.note(noteId: noteId, folderId: folderId),
    );
  }

  static Future<void> toNoteEditorInstant(
    BuildContext context, {
    required String folderId,
    required String noteId,
    NoteMetadata? metadata,
  }) {
    return pushNoAnimation(
      context,
      OptimizedNoteEditorPage(
        folderId: folderId,
        noteId: noteId,
        metadata: metadata,
      ),
      destination: NavDestination.note(noteId: noteId, folderId: folderId),
    );
  }

  static Future<void> toSearch(
    BuildContext context, {
    String? folderId,
    String? query,
  }) {
    return push(context, SearchPage(folderId: folderId, initialQuery: query));
  }

  static Future<SettingsResult?> toDatabaseSettings(BuildContext context) {
    return push<SettingsResult>(
      context,
      const DatabaseSettingsPage(),
      destination: const NavDestination(NavDestinationKind.databaseSettings),
    );
  }

  static Future<SettingsResult?> toSettings(BuildContext context) {
    return push<SettingsResult>(
      context,
      const SettingsPage(),
      destination: const NavDestination(NavDestinationKind.settings),
    );
  }

  static Future<SettingsResult?> toSyncSettings(BuildContext context) {
    return push<SettingsResult>(
      context,
      const SyncSettingsPage(),
      destination: const NavDestination(NavDestinationKind.syncSettings),
    );
  }

  static Future<SettingsResult?> toMarkdownSettings(
    BuildContext context, {
    required List<CustomMarkdownShortcut> allShortcuts,
  }) {
    return push<SettingsResult>(
      context,
      MarkdownSettingsPage(allShortcuts: allShortcuts),
    );
  }

  static Future<SettingsResult?> toCounterManagement(
    BuildContext context, {
    String? noteId,
  }) {
    return push<SettingsResult>(
      context,
      CounterManagementPage(noteId: noteId),
      destination: NavDestination.counterManagement(noteId: noteId),
    );
  }

  static Future<void> toCalendar(BuildContext context) {
    return push(
      context,
      const CalendarPage(),
      destination: const NavDestination(NavDestinationKind.calendar),
    );
  }

  static Future<void> toCalendarSettings(BuildContext context) {
    return push(
      context,
      const CalendarSettingsPage(),
      destination: const NavDestination(NavDestinationKind.calendarSettings),
    );
  }

  static Future<void> toCalendarCategories(BuildContext context) {
    return push(
      context,
      const CalendarCategoriesPage(),
      destination: const NavDestination(NavDestinationKind.calendarCategories),
    );
  }

  static Future<void> toEventTemplates(BuildContext context) {
    return push(
      context,
      const EventTemplatesPage(),
      destination: const NavDestination(NavDestinationKind.eventTemplates),
    );
  }

  static Future<void> toVocabularies(BuildContext context) {
    return push(
      context,
      const VocabulariesPage(),
      destination: const NavDestination(NavDestinationKind.vocabularies),
    );
  }

  static Future<void> toCounterPerNote(
    BuildContext context, {
    required Counter counter,
  }) {
    return push(context, CounterPerNotePage(counter: counter));
  }

  static Future<SettingsResult?> toDeveloperOptions(BuildContext context) {
    return push<SettingsResult>(context, const DeveloperOptionsPage());
  }

  static Future<void> toShortcutEditor(
    BuildContext context, {
    CustomMarkdownShortcut? shortcut,
    required Function(CustomMarkdownShortcut) onSave,
  }) {
    return push(
      context,
      ShortcutEditorPage(shortcut: shortcut, onSave: onSave),
    );
  }

  static Future<void> toNoteBarAssignment(BuildContext context) {
    return push(context, const NoteBarAssignmentPage());
  }

  static Future<void> toNoteMoneyCurrency(BuildContext context) {
    return push(context, const NoteMoneyCurrencyPage());
  }

  static Future<void> toMarkdownColors(BuildContext context) {
    return push(context, const MarkdownColorsPage());
  }

  // --- Last-location restore ---

  /// Reopens the chain of pages the user was looking at when the app last
  /// went away — folders, notes, the calendar and its sub-pages, and the
  /// drawer's settings pages alike.
  ///
  /// Recording is not done here: [NavigationHistoryService] owns it, driven by
  /// a navigator observer. This method only replays, and it does so in two
  /// strictly separated phases.
  ///
  /// **Phase 1 resolves the whole chain before anything is pushed.** Entries
  /// whose target no longer exists truncate the chain there, so the user lands
  /// on the deepest ancestor that still resolves rather than on an error.
  ///
  /// **Phase 2 pushes, and must never await a push.** A Navigator push future
  /// completes when the route is *popped*, not when it settles — awaiting the
  /// first push once deferred every later one until the user pressed Back,
  /// which made Back appear to open a note instead of returning to the folder.
  /// Keeping resolution entirely in phase 1 is what removes the temptation to
  /// interleave an `await` between two pushes.
  ///
  /// Nothing is written back after a truncation: the replay pushes are stamped
  /// like any other navigation, so the observer records what actually landed
  /// and the debounced write heals the stored value on its own.
  static Future<void> restoreLastLocation() async {
    try {
      await _replayLastLocation();
    } finally {
      // Recording stays sealed until the stored stack has been read and the
      // replay queued — including on every early return above, or the empty
      // stack the root page publishes at launch would overwrite it.
      GetIt.I<NavigationHistoryService>().beginRecording();
    }
  }

  static Future<void> _replayLastLocation() async {
    final settings = await SettingsService.getInstance();
    final mode = await settings.getRestoreLocationMode();
    if (mode == RestoreLocationMode.off) return;

    final planned = mode.apply(await settings.getLastLocationStack());
    if (planned.isEmpty) return;

    final resolved = await _resolveChain(planned);
    if (resolved.isEmpty) return;

    // Only the bottom-most drawer-owned page needs the continuation: popping
    // a page above it lands on another restored page, and the Navigator
    // handles that. Popping out of the settings layer entirely is the only
    // moment the drawer would otherwise have been reopened by the row that
    // pushed it — and under restore there was no row.
    final drawerIndex = resolved.indexWhere(
      (entry) => entry.destination.kind.reopensDrawerOnPop,
    );

    for (var i = 0; i < resolved.length; i++) {
      final entry = resolved[i];
      final push = rootPushInstant<Object?>(
        _pageFor(entry),
        destination: entry.destination,
      );
      if (i == drawerIndex) {
        unawaited(
          push.then((result) {
            if (result == SettingsResult.openDrawer) {
              DrawerHostRegistry.openTopDrawer();
            }
          }),
        );
      } else {
        unawaited(push);
      }
    }
  }

  /// Resolves as long a prefix of [planned] as still exists, stopping at the
  /// first entry whose target is gone. Note entries are re-pointed at the
  /// folder the note lives in *now* — a note that was moved since it was
  /// recorded is followed, not abandoned.
  static Future<List<_RestoredEntry>> _resolveChain(
    List<NavDestination> planned,
  ) async {
    final resolved = <_RestoredEntry>[];

    for (final destination in planned) {
      switch (destination.kind) {
        case NavDestinationKind.folder:
          final folder = await GetIt.I<FolderStorageService>().getFolderById(
            destination.folderId!,
          );
          if (folder == null) return resolved;
          resolved.add(
            _RestoredEntry(destination: destination.withTitle(folder.name)),
          );

        case NavDestinationKind.note:
          final metadata = await _resolveNote(destination.noteId!);
          if (metadata == null) return resolved;
          resolved.add(
            _RestoredEntry(
              destination: destination.withFolderId(metadata.folderId),
              metadata: metadata,
            ),
          );

        case NavDestinationKind.counterManagement:
          final noteId = destination.noteId;
          if (noteId != null && await _resolveNote(noteId) == null) {
            return resolved;
          }
          resolved.add(_RestoredEntry(destination: destination));

        default:
          resolved.add(_RestoredEntry(destination: destination));
      }
    }

    return resolved;
  }

  static Future<NoteMetadata?> _resolveNote(String noteId) async {
    final repository = GetIt.I<NoteRepository>();
    final notes = await repository.getNotesByIds([noteId]);
    if (notes.isEmpty) return null;
    return repository.noteToMetadata(notes.first);
  }

  /// Builds the page for a resolved entry.
  ///
  /// The note editor is handed the metadata phase 1 already fetched for the
  /// existence check: seeding its title bar from it is what keeps a restored
  /// note from reading "New note" until the first edit.
  static Widget _pageFor(_RestoredEntry entry) {
    final destination = entry.destination;
    return switch (destination.kind) {
      NavDestinationKind.folder => OptimizedFolderContentPage(
        folderId: destination.folderId,
        title: destination.title,
      ),
      NavDestinationKind.note => OptimizedNoteEditorPage(
        folderId: destination.folderId!,
        noteId: destination.noteId,
        metadata: entry.metadata,
      ),
      NavDestinationKind.calendar => const CalendarPage(),
      NavDestinationKind.calendarSettings => const CalendarSettingsPage(),
      NavDestinationKind.calendarCategories => const CalendarCategoriesPage(),
      NavDestinationKind.eventTemplates => const EventTemplatesPage(),
      NavDestinationKind.vocabularies => const VocabulariesPage(),
      NavDestinationKind.databaseSettings => const DatabaseSettingsPage(),
      NavDestinationKind.settings => const SettingsPage(),
      NavDestinationKind.syncSettings => const SyncSettingsPage(),
      NavDestinationKind.counterManagement => CounterManagementPage(
        noteId: destination.noteId,
      ),
    };
  }
}

/// A stack entry that phase 1 proved still exists, carrying anything it had
/// to load along the way so phase 2 does not have to load it again.
class _RestoredEntry {
  const _RestoredEntry({required this.destination, this.metadata});

  final NavDestination destination;
  final NoteMetadata? metadata;
}
