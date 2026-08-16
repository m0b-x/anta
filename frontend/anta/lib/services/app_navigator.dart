import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'dart:async';
import '../models/counter.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/note_metadata.dart';
import '../repositories/note_repository.dart';
import '../services/folder_storage_service.dart';
import '../services/settings_service.dart';
import '../pages/controls_settings_page.dart';
import '../pages/calendar_page.dart';
import '../pages/calendar_settings_page.dart';
import '../pages/calendar_categories_page.dart';
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
  /// (e.g. the root folder page clears the restored location when the user
  /// navigates back to it). Registered on the root `MaterialApp`.
  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

  static NavigatorState get _navigator => navigatorKey.currentState!;

  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));
  }

  static Future<T?> pushNoAnimation<T>(
    BuildContext context,
    Widget page, {
    Duration reverseTransitionDuration = const Duration(milliseconds: 150),
  }) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: reverseTransitionDuration,
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

  static Future<T?> rootPush<T>(Widget page) {
    return _navigator.push<T>(MaterialPageRoute(builder: (_) => page));
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
    _rememberFolder(folderId, title);
    return push(
      context,
      OptimizedFolderContentPage(folderId: folderId, title: title),
    );
  }

  static Future<void> toNoteEditor(
    BuildContext context, {
    required String folderId,
    String? noteId,
    NoteMetadata? metadata,
  }) {
    if (noteId != null) _rememberNote(noteId);
    return push(
      context,
      OptimizedNoteEditorPage(
        folderId: folderId,
        noteId: noteId,
        metadata: metadata,
      ),
    );
  }

  static Future<void> toNoteEditorInstant(
    BuildContext context, {
    required String folderId,
    required String noteId,
    NoteMetadata? metadata,
  }) {
    _rememberNote(noteId);
    return pushNoAnimation(
      context,
      OptimizedNoteEditorPage(
        folderId: folderId,
        noteId: noteId,
        metadata: metadata,
      ),
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
    return push<SettingsResult>(context, const DatabaseSettingsPage());
  }

  static Future<SettingsResult?> toControlsSettings(BuildContext context) {
    return push<SettingsResult>(context, const ControlsSettingsPage());
  }

  static Future<SettingsResult?> toSyncSettings(BuildContext context) {
    return push<SettingsResult>(context, const SyncSettingsPage());
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
    return push<SettingsResult>(context, CounterManagementPage(noteId: noteId));
  }

  static Future<void> toCalendar(BuildContext context) {
    return push(context, const CalendarPage());
  }

  static Future<void> toCalendarSettings(BuildContext context) {
    return push(context, const CalendarSettingsPage());
  }

  static Future<void> toCalendarCategories(BuildContext context) {
    return push(context, const CalendarCategoriesPage());
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

  // --- Last-location persistence & restore ---

  static void _rememberFolder(String folderId, String title) {
    unawaited(
      SettingsService.getInstance().then(
        (s) => s.saveLastFolder(folderId, title),
      ),
    );
  }

  static void _rememberNote(String noteId) {
    unawaited(
      SettingsService.getInstance().then((s) => s.saveLastNote(noteId)),
    );
  }

  /// Reopens the folder (and note) the user was last viewing, pushed onto the
  /// root navigator so the back button still returns to the home screen.
  ///
  /// Validates that the targets still exist; if the folder is gone the stored
  /// location is cleared and nothing is restored. Safe to call once after the
  /// root page is mounted.
  static Future<void> restoreLastLocation() async {
    final settings = await SettingsService.getInstance();
    final folderId = await settings.getLastFolderId();
    if (folderId == null || folderId.isEmpty) return;

    final folder = await GetIt.I<FolderStorageService>().getFolderById(
      folderId,
    );
    if (folder == null) {
      await settings.clearLastLocation();
      return;
    }

    // Resolve any remembered note up front so the folder and note are pushed
    // together as a single back-stack (Home -> Folder -> Note). We must NOT
    // `await` the folder's push future before pushing the note: Navigator's
    // push future only completes when that route is *popped*, so awaiting it
    // deferred the note push until the user pressed Back -- which made Back
    // appear to open a note instead of returning to the folder/home.
    NoteMetadata? noteToRestore;
    final noteId = await settings.getLastNoteId();
    if (noteId != null && noteId.isNotEmpty) {
      final noteRepository = GetIt.I<NoteRepository>();
      final notes = await noteRepository.getNotesByIds([noteId]);
      if (notes.isEmpty) {
        // The note was deleted since it was remembered: restore the folder
        // only and forget the stale note.
        await settings.saveLastFolder(folder.id, folder.name);
      } else {
        noteToRestore = noteRepository.noteToMetadata(notes.first);
      }
    }

    unawaited(
      rootPush(
        OptimizedFolderContentPage(folderId: folder.id, title: folder.name),
      ),
    );

    if (noteToRestore == null) return;

    // Pass the metadata we already fetched for the existence check: the
    // editor seeds its title bar from it, so a metadata-less push showed
    // "New note" instead of the note's real title until the next edit.
    unawaited(
      rootPush(
        OptimizedNoteEditorPage(
          folderId: folder.id,
          noteId: noteToRestore.id,
          metadata: noteToRestore,
        ),
      ),
    );
  }
}
