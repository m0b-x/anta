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
import '../services/quick_alarm_request.dart';
import '../services/settings_service.dart';
import '../pages/settings_page.dart';
import '../pages/alerts_page.dart';
import '../pages/all_notes_page.dart';
import '../pages/calendar_page.dart';
import '../pages/calendar_settings_page.dart';
import '../pages/calendar_categories_page.dart';
import '../pages/calendar_appearance_page.dart';
import '../pages/calendar_overview_page.dart';
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
import '../pages/permissions_page.dart';
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
  ///
  /// It also keeps the live page-route stack, which is what lets
  /// [popToFolder] address a route several levels down.
  static final AppRouteObserver routeObserver = AppRouteObserver();

  static NavigatorState get _navigator => navigatorKey.currentState!;

  /// Stamps a route with the destination that can rebuild it.
  ///
  /// This is the whole contract between navigation and
  /// [NavigationHistoryService]: a stamped route is restorable, an unstamped
  /// one is not, and the observer never has to know page types. Pages that
  /// carry closures or live model objects simply go unstamped.
  static RouteSettings? _settingsFor(NavDestination? destination) {
    if (destination == null) return null;
    return RouteSettings(name: destination.kind.name, arguments: destination);
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
    NavDestination? destination,
  }) {
    return Navigator.pushReplacement<T, TO>(
      context,
      MaterialPageRoute(
        builder: (_) => page,
        settings: _settingsFor(destination),
      ),
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

  /// Returns to the page showing [folderId], playing exactly one transition.
  ///
  /// `popUntil` animates every route it passes through (flutter#59990), so a
  /// jump three levels up flickers through two pages. The routes in between
  /// are removed outright instead, and the single remaining pop is the
  /// transition the user should see.
  ///
  /// Removal runs top-down and never touches the current route: that one is
  /// popped, so its page still gets the exit its own `PopScope` arranged.
  ///
  /// The folder is not always on the stack: a note reached by launch restore,
  /// or through a chain of `[[wiki links]]` that walked into another folder,
  /// sits above routes that never included it. That case replaces the current
  /// page with the folder rather than pushing a second copy of it.
  static Future<void> popToFolder(
    BuildContext context, {
    required String folderId,
    required String title,
  }) {
    final navigator = Navigator.of(context);
    final routes = _livePageRoutes(navigator);
    final index = routes.lastIndexWhere((route) {
      final destination = route.settings.arguments;
      return destination is NavDestination &&
          destination.kind == NavDestinationKind.folder &&
          destination.folderId == folderId;
    });

    if (index < 0) {
      if (title.isEmpty) return _replaceWithFolder(context, folderId);
      return pushReplacement<void, void>(
        context,
        OptimizedFolderContentPage(folderId: folderId, title: title),
        destination: NavDestination.folder(folderId: folderId, title: title),
      );
    }
    _collapseOnto(navigator, routes, index);
    return Future<void>.value();
  }

  /// The fallback replacement for a caller that has no title to give — the
  /// editor's "Open folder" runs before the folder name has loaded, and a
  /// blank one would be *stamped*, persisting a stack entry that restores a
  /// folder page captioned with nothing.
  ///
  /// The name is read first and the route stamped with it. A folder that no
  /// longer resolves is opened unstamped instead: recording then truncates
  /// above it, which is the honest answer for a place restore cannot rebuild.
  static Future<void> _replaceWithFolder(
    BuildContext context,
    String folderId,
  ) async {
    final folder = await GetIt.I<FolderStorageService>().getFolderById(
      folderId,
    );
    if (!context.mounted) return;
    final name = folder?.name;
    await pushReplacement<void, void>(
      context,
      OptimizedFolderContentPage(folderId: folderId, title: name ?? ''),
      destination: name == null
          ? null
          : NavDestination.folder(folderId: folderId, title: name),
    );
  }

  /// Returns to an entry of the folder breadcrumb, which the browser's
  /// ancestor menu lists.
  ///
  /// A null [folderId] means the root browser — it is `home`, carries no
  /// folder id and therefore no `NavDestination` stamp, so it is addressed by
  /// [Route.isFirst] instead. Everything else is a stamped folder route and
  /// goes through [popToFolder], which is also what makes an ancestor that is
  /// somehow not on the stack rebuild rather than dead-end.
  ///
  /// The root case is deliberately not `popUntilFirst`: `popUntil` pops one
  /// route at a time, each with its own transition (flutter#59990), so five
  /// levels up would play five of them.
  static Future<void> popToAncestor(
    BuildContext context, {
    String? folderId,
    String? title,
  }) {
    if (folderId != null) {
      return popToFolder(context, folderId: folderId, title: title ?? '');
    }

    final navigator = Navigator.of(context);
    final routes = _livePageRoutes(navigator);
    final index = routes.indexWhere((route) => route.isFirst);
    if (index < 0) {
      popUntilFirst(context);
      return Future<void>.value();
    }
    _collapseOnto(navigator, routes, index);
    return Future<void>.value();
  }

  /// The page routes [routeObserver] recorded that are still live on
  /// [navigator], bottom-first. A navigator torn down without popping leaves
  /// its routes in the observer, so both checks are load-bearing.
  static List<Route<dynamic>> _livePageRoutes(NavigatorState navigator) {
    return routeObserver.pageRoutes
        .where(
          (route) => route.isActive && identical(route.navigator, navigator),
        )
        .toList();
  }

  /// Leaves `routes[index]` on top, playing exactly one transition: every
  /// route above it except the current one is removed outright, and the
  /// current one is popped so its page still gets the exit its own `PopScope`
  /// arranged.
  static void _collapseOnto(
    NavigatorState navigator,
    List<Route<dynamic>> routes,
    int index,
  ) {
    if (index >= routes.length - 1) return;
    for (var i = routes.length - 2; i > index; i--) {
      navigator.removeRoute(routes[i]);
    }
    navigator.pop();
  }

  /// The root browser's "All notes" row. Stamped: it holds no query and no
  /// transient state, so a cold launch back into it lands exactly where the
  /// user left.
  static Future<void> toAllNotes(BuildContext context) {
    return push(
      context,
      const AllNotesPage(),
      destination: const NavDestination(NavDestinationKind.allNotes),
    );
  }

  /// The root browser's "Recent" row — [AllNotesPage] capped and fixed to the
  /// most recently edited notes.
  static Future<void> toRecentNotes(BuildContext context) {
    return push(
      context,
      const AllNotesPage(mode: AllNotesMode.recent),
      destination: const NavDestination(NavDestinationKind.recentNotes),
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

  /// Deliberately unstamped: search is a query surface, not a place, so
  /// launch restore never puts the user back into someone else's half-typed
  /// search.
  static Future<void> toSearch(
    BuildContext context, {
    String? folderId,
    String? folderName,
    String? query,
  }) {
    return push(
      context,
      SearchPage(
        folderId: folderId,
        folderName: folderName,
        initialQuery: query,
      ),
    );
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

  /// The occurrence a **warm** alert tap asked for.
  ///
  /// A live `CalendarPage` cannot be handed new constructor arguments, so
  /// [toCalendarOccurrence] publishes the request here and the page that is
  /// already on the stack serves it. Set back to null by whoever serves it, so
  /// a page mounting later does not replay a trip already made.
  static final ValueNotifier<({DateTime day, String? eventId})?>
  pendingCalendarOccurrence = ValueNotifier(null);

  /// Opens the calendar on [day] with [eventId]'s detail sheet already up —
  /// where a tapped reminder lands (**A12**). A null [eventId] lands on the
  /// day alone: the alarm page's Open event, when the Stop it implies has just
  /// removed a "remove after it rings" event, has nothing left to open
  /// (**A3**).
  ///
  /// A **root** push when the calendar is not open: the tap is delivered by the
  /// platform with no `BuildContext` of its own. Stamped with the plain
  /// calendar destination because the day and the event are where this
  /// particular trip started, not part of the location worth restoring on the
  /// next launch.
  ///
  /// A **warm** tap — one arriving while a calendar route is already on the
  /// stack — collapses onto that route instead. Pushing a second
  /// `CalendarPage` would stack two of the app's heaviest page over each
  /// other, each with its own grid, panel and scroll position, and leave the
  /// user two back gestures from where they were.
  static Future<void> toCalendarOccurrence({
    required DateTime day,
    required String? eventId,
  }) {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      final routes = _livePageRoutes(navigator);
      final index = routes.lastIndexWhere((route) {
        final destination = route.settings.arguments;
        return destination is NavDestination &&
            destination.kind == NavDestinationKind.calendar;
      });
      if (index >= 0) {
        pendingCalendarOccurrence.value = (day: day, eventId: eventId);
        _collapseOnto(navigator, routes, index);
        return Future<void>.value();
      }
    }
    return rootPush<void>(
      CalendarPage(initialDay: day, initialEventId: eventId),
      destination: const NavDestination(NavDestinationKind.calendar),
    );
  }

  /// The quick-alarm sheet, asked for by the platform with no `BuildContext`
  /// of its own — the Quick Settings tile and the launcher shortcut (OS-5,
  /// **B9**). The calendar page owns the sheet, its guard, the bloc and the
  /// snackbar, so the request is published for it and the page is brought
  /// up: collapsed onto when live, the way [toCalendarOccurrence] does, else
  /// root-pushed under the same `calendar` stamp. Published **after** the
  /// navigation, so a live page's listener runs once the collapse is under
  /// way and a pushed page finds the request waiting at mount.
  static Future<void> toCalendarQuickAlarm() {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      final routes = _livePageRoutes(navigator);
      final index = routes.lastIndexWhere((route) {
        final destination = route.settings.arguments;
        return destination is NavDestination &&
            destination.kind == NavDestinationKind.calendar;
      });
      if (index >= 0) {
        _collapseOnto(navigator, routes, index);
        QuickAlarmRequest.instance.publish();
        return Future<void>.value();
      }
    }
    final pushed = rootPush<void>(
      const CalendarPage(),
      destination: const NavDestination(NavDestinationKind.calendar),
    );
    QuickAlarmRequest.instance.publish();
    return pushed;
  }

  /// The overview page: events by category over whole years, a feature like
  /// the calendar itself, so it raises no drawer on pop.
  static Future<void> toCalendarOverview(BuildContext context) {
    return push(
      context,
      const CalendarOverviewPage(),
      destination: const NavDestination(NavDestinationKind.calendarOverview),
    );
  }

  static Future<void> toCalendarSettings(BuildContext context) {
    return push(
      context,
      const CalendarSettingsPage(),
      destination: const NavDestination(NavDestinationKind.calendarSettings),
    );
  }

  static Future<void> toAlerts(BuildContext context) {
    return push(
      context,
      const AlertsPage(),
      destination: const NavDestination(NavDestinationKind.alerts),
    );
  }

  /// The Alerts hub, opened by the platform with no `BuildContext` of its own:
  /// the lock screen's alarm line and Quick Settings launch the show intent
  /// every alarm-clock entry carries (`AlarmService.ACTION_SHOW`, Patch 1 of
  /// the `alarm` fork), and the answer to "you have an alarm" is the list that
  /// holds every armed one (**B2**).
  ///
  /// Collapses onto a live hub route the way [toCalendarOccurrence] collapses
  /// onto a live calendar, so a second tap on the line never stacks two hubs;
  /// otherwise a root push under the same `alerts` stamp [toAlerts] uses, so
  /// the hub reached this way restores like the hub reached from the drawer.
  static Future<void> toAlertsFromPlatform() {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      final routes = _livePageRoutes(navigator);
      final index = routes.lastIndexWhere((route) {
        final destination = route.settings.arguments;
        return destination is NavDestination &&
            destination.kind == NavDestinationKind.alerts;
      });
      if (index >= 0) {
        _collapseOnto(navigator, routes, index);
        return Future<void>.value();
      }
    }
    return rootPush<void>(
      const AlertsPage(),
      destination: const NavDestination(NavDestinationKind.alerts),
    );
  }

  /// A note opened by the platform with no `BuildContext` of its own — *Open
  /// note* on the session chip (**B8**, OS-5). Collapses onto a live editor
  /// of the same note the way [toCalendarOccurrence] collapses onto a live
  /// calendar — a cold start whose remembered location is that very note
  /// would otherwise stack two editors of it — and otherwise root-pushes
  /// under the same stamp [toNoteEditor] uses, so the restore stack records
  /// it like any other note; [metadata] seeds the editor's title bar.
  static Future<void> toNoteFromPlatform({
    required String folderId,
    required String noteId,
    NoteMetadata? metadata,
  }) {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      final routes = _livePageRoutes(navigator);
      final index = routes.lastIndexWhere((route) {
        final destination = route.settings.arguments;
        return destination is NavDestination &&
            destination.kind == NavDestinationKind.note &&
            destination.noteId == noteId;
      });
      if (index >= 0) {
        _collapseOnto(navigator, routes, index);
        return Future<void>.value();
      }
    }
    return rootPush<void>(
      OptimizedNoteEditorPage(
        folderId: folderId,
        noteId: noteId,
        metadata: metadata,
      ),
      destination: NavDestination.note(noteId: noteId, folderId: folderId),
    );
  }

  static Future<SettingsResult?> toPermissions(
    BuildContext context, {
    bool fromDrawer = false,
  }) {
    final routes = _livePageRoutes(Navigator.of(context));
    final top = routes.isEmpty ? null : routes.last.settings.arguments;
    if (top is NavDestination && top.kind == NavDestinationKind.permissions) {
      return Future<SettingsResult?>.value();
    }
    return push<SettingsResult>(
      context,
      PermissionsPage(popsToDrawer: fromDrawer),
      destination: const NavDestination(NavDestinationKind.permissions),
    );
  }

  static Future<void> toCalendarCategories(BuildContext context) {
    return push(
      context,
      const CalendarCategoriesPage(),
      destination: const NavDestination(NavDestinationKind.calendarCategories),
    );
  }

  static Future<void> toCalendarAppearance(BuildContext context) {
    return push(
      context,
      const CalendarAppearancePage(),
      destination: const NavDestination(NavDestinationKind.calendarAppearance),
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
    final before = _navigationFingerprint();

    final settings = await SettingsService.getInstance();
    final mode = await settings.getRestoreLocationMode();
    if (mode == RestoreLocationMode.off) return;

    final planned = mode.apply(await settings.getLastLocationStack());
    if (planned.isEmpty) return;

    final resolved = await _resolveChain(planned);
    if (resolved.isEmpty) return;

    // Phase 1 is several database round-trips long, and the user can navigate
    // during it — a tap on a folder row lands before the replay does. Pushing
    // the remembered chain on top of that would bury the page they just asked
    // for, so a stack that moved cancels the replay outright. Recording is
    // still unsealed by the caller's `finally`, so what they navigated to is
    // what gets remembered.
    if (_navigationFingerprint() != before) return;

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

  /// How far the root navigator has moved, as a value that changes whenever a
  /// route is pushed, popped or replaced above it.
  ///
  /// A `NavigatorState` exposes no history, so this reads the live page routes
  /// [routeObserver] kept: their count plus the identity of the topmost one,
  /// which together survive a push-then-pop that would leave the count alone.
  static (int, Route<dynamic>?) _navigationFingerprint() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return (0, null);
    final routes = _livePageRoutes(navigator);
    return (routes.length, routes.isEmpty ? null : routes.last);
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
            includeDeleted: false,
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
      NavDestinationKind.calendarAppearance => const CalendarAppearancePage(),
      NavDestinationKind.eventTemplates => const EventTemplatesPage(),
      NavDestinationKind.vocabularies => const VocabulariesPage(),
      NavDestinationKind.databaseSettings => const DatabaseSettingsPage(),
      NavDestinationKind.settings => const SettingsPage(),
      NavDestinationKind.syncSettings => const SyncSettingsPage(),
      NavDestinationKind.counterManagement => CounterManagementPage(
        noteId: destination.noteId,
      ),
      NavDestinationKind.allNotes => const AllNotesPage(),
      NavDestinationKind.recentNotes => const AllNotesPage(
        mode: AllNotesMode.recent,
      ),
      NavDestinationKind.alerts => const AlertsPage(),
      NavDestinationKind.permissions => const PermissionsPage(),
      NavDestinationKind.calendarOverview => const CalendarOverviewPage(),
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

/// The app's [RouteObserver], which additionally keeps the page routes it
/// sees pass by.
///
/// A `NavigatorState` exposes no history, so a caller that wants to address
/// a route several levels down — [AppNavigator.popToFolder] — has nothing to
/// hand [NavigatorState.removeRoute] without a record of its own. Modal
/// sheets and dialogs are `PopupRoute`s and never enter the list.
class AppRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  final List<Route<dynamic>> _pageRoutes = [];

  /// The page routes currently on the navigator, bottom-first.
  ///
  /// A navigator torn down without popping its routes never reports them as
  /// popped or removed, so they would accumulate here for the life of the
  /// process — one leaked list entry per disposed navigator, and every
  /// `popToFolder` walking past them. A disposed route has no navigator, so
  /// reading this sheds them. Callers must still filter by [Route.isActive]
  /// and [Route.navigator]: a route can belong to a *live* navigator that is
  /// not the one they are addressing.
  List<Route<dynamic>> get pageRoutes {
    _pageRoutes.removeWhere((route) => route.navigator == null);
    return List.unmodifiable(_pageRoutes);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pageRoutes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pageRoutes.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pageRoutes.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pageRoutes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute is PageRoute) {
        _pageRoutes[index] = newRoute;
      } else {
        _pageRoutes.removeAt(index);
      }
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
