import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../bloc/optimized_note/optimized_note_event.dart';
import '../services/auto_save_service.dart';

/// Builds the [AutoSaveService] a [NoteSaveCoordinator] saves through.
/// Injected so a test can shorten the debounce and interval without the
/// coordinator knowing anything about timings.
typedef AutoSaveFactory =
    AutoSaveService Function({
      required Future<void> Function(String? title, String? content) onSave,
      required void Function(bool hasChanges) onChangeDetected,
    });

/// The note editor page's whole persistence orchestration: when a
/// brand-new note is first written, which title a save is allowed to
/// carry, and what the app bar's unsaved indicator shows.
///
/// The page owns one of these and keeps no save state of its own.
/// Nothing here touches the widget tree — the two places that used to
/// need it (the duplicate-title snackbar and the bloc dispatch) arrive as
/// callbacks — so the save contract is testable as plain Dart.
///
/// Layering: the coordinator dispatches [OptimizedNoteEvent]s to the
/// page's bloc and reads the live title/content through getters; it never
/// reaches a repository or a DAO itself.
class NoteSaveCoordinator {
  NoteSaveCoordinator({
    required this.folderId,
    required String? noteId,
    required this.originalTitle,
    required String Function() title,
    required String Function() content,
    required Future<bool> Function({required String title, String? excludeId})
    titleExists,
    required void Function(OptimizedNoteEvent event) dispatch,
    required void Function(String title) onDuplicateTitle,
    AutoSaveFactory? autoSaveFactory,
  }) : _effectiveNoteId = noteId,
       _title = title,
       _content = content,
       _titleExists = titleExists,
       _dispatch = dispatch,
       _onDuplicateTitle = onDuplicateTitle {
    _autoSave = (autoSaveFactory ?? _defaultAutoSave)(
      onSave: _save,
      onChangeDetected: _setHasChanges,
    );
  }

  /// Folder the note lives in: the uniqueness scope for its title and the
  /// parent an early create writes into.
  final String folderId;

  /// The note's persisted title when the page opened (`null` for a new
  /// note). A save whose title would collide falls back to exactly this
  /// one, so a rename that cannot be applied never rewrites what is
  /// stored.
  final String? originalTitle;

  final String Function() _title;
  final String Function() _content;
  final Future<bool> Function({required String title, String? excludeId})
  _titleExists;
  final void Function(OptimizedNoteEvent event) _dispatch;
  final void Function(String title) _onDuplicateTitle;

  late final AutoSaveService _autoSave;

  final ValueNotifier<bool> _hasChanges = ValueNotifier<bool>(false);

  String? _effectiveNoteId;
  bool _isCreatingNewNote = false;

  /// One-shot guard so auto-save does not raise the duplicate-title
  /// warning on every keystroke after a collision. Cleared the moment the
  /// user picks a title that does not collide.
  bool _warnedDuplicateTitle = false;

  bool _disposed = false;

  static AutoSaveService _defaultAutoSave({
    required Future<void> Function(String? title, String? content) onSave,
    required void Function(bool hasChanges) onChangeDetected,
  }) => AutoSaveService(onSave: onSave, onChangeDetected: onChangeDetected);

  /// Whether anything typed since the last successful write is still
  /// unsaved — the app bar's dirty indicator.
  ValueListenable<bool> get hasChanges => _hasChanges;

  /// The auto-save service's own status (saved / unsaved / saving /
  /// error), forwarded so the app bar has a single thing to listen to.
  ValueListenable<SaveStatus> get saveStatus => _autoSave.saveStatusNotifier;

  /// The id every save writes to: the note the page opened, or the id a
  /// brand-new note was given when it was first persisted. `null` until
  /// then.
  String? get effectiveNoteId => _effectiveNoteId;

  /// Whether an early create is in flight. Guards a second create from
  /// racing the first, which would leave two notes for one editor.
  bool get isCreatingNewNote => _isCreatingNewNote;

  /// Starts auto-save tracking for a note that already exists. A
  /// brand-new note starts tracking later, from [noteCreated].
  void start() {
    if (_effectiveNoteId == null) return;
    _track();
  }

  /// The editor's text changed: mark the page dirty, then either feed the
  /// auto-save debounce or — for a note that has never been written —
  /// persist it as soon as it holds anything worth keeping.
  void onContentChanged() {
    markChanged();
    if (_effectiveNoteId != null) {
      _autoSave.onContentChanged(_title());
    } else {
      _maybeCreateNewNoteEarly();
    }
  }

  /// The bloc reported the early create landed: adopt the new id and
  /// start tracking, so the next keystroke auto-saves as an update.
  void noteCreated(String id) {
    _effectiveNoteId = id;
    _isCreatingNewNote = false;
    _track();
  }

  /// Marks the note dirty for the edits that bypass the text listener — a
  /// checkbox toggled through the tap interceptor, a search-and-replace
  /// applied by the find controller.
  void markChanged() => _setHasChanges(true);

  /// Writes now instead of waiting for the debounce; the preview toggle
  /// takes one as a natural checkpoint. [content] lets a caller that has
  /// already read the editor text hand it over instead of paying for a
  /// second read.
  ///
  /// A note that has never been persisted has nothing to force: it is
  /// created through [saveOnLifecyclePause] / [saveBeforeExit] instead.
  Future<void> forceSave({String? content}) async {
    if (_effectiveNoteId == null) return;
    await _autoSave.forceSave(title: _title(), content: content);
  }

  /// The OS is about to suspend or kill the app. An existing note forces
  /// a save; a brand-new one is created on the spot so the text survives
  /// a process death. Fire-and-forget by design: the lifecycle callback
  /// is synchronous and the platform will not wait for us.
  void saveOnLifecyclePause() {
    if (_effectiveNoteId != null) {
      unawaited(forceSave());
    } else {
      unawaited(_createNewNoteEarly());
    }
  }

  /// The user is leaving the page: flush an existing note, or create a
  /// brand-new one when it holds anything. An empty new note is
  /// deliberately not created — opening the editor and backing out must
  /// not litter the folder.
  Future<void> saveBeforeExit() async {
    if (_effectiveNoteId != null) {
      await forceSave();
      return;
    }
    if (_isCreatingNewNote) return;
    final title = _title().trim();
    final content = _content().trim();
    if (title.isEmpty && content.isEmpty) return;
    // Awaited, unlike the fire-and-forget lifecycle path: the caller is
    // holding the pop, and the title lookup inside would otherwise finish
    // after this object is disposed and drop the create.
    await _createNewNoteEarly();
  }

  void dispose() {
    _disposed = true;
    _autoSave.dispose();
    _hasChanges.dispose();
  }

  void _track() {
    _autoSave.startTracking(_title(), _content(), contentProvider: _content);
  }

  /// The auto-save write. The title is validated against sibling notes
  /// *before* dispatching: a colliding title still saves the content (the
  /// user never loses keystrokes) but keeps [originalTitle] and warns
  /// once, mirroring the rename dialog instead of raising a snackbar per
  /// save.
  Future<void> _save(String? title, String? content) async {
    final noteId = _effectiveNoteId;
    if (noteId == null) return;

    var titleToSave = title;
    final trimmed = title?.trim() ?? '';
    if (trimmed.isNotEmpty &&
        trimmed.toLowerCase() != (originalTitle?.trim().toLowerCase() ?? '')) {
      final exists = await _titleExists(title: trimmed, excludeId: noteId);
      if (exists) {
        titleToSave = originalTitle ?? '';
        if (!_warnedDuplicateTitle && !_disposed) {
          _warnedDuplicateTitle = true;
          _onDuplicateTitle(trimmed);
        }
      } else {
        // A unique title re-arms the warning so a later collision is
        // reported again.
        _warnedDuplicateTitle = false;
      }
    }

    final completer = Completer<void>();
    if (_disposed) return;
    _dispatch(
      UpdateOptimizedNote(
        noteId: noteId,
        title: titleToSave,
        content: content,
        completer: completer,
      ),
    );
    await completer.future;
  }

  /// Persists a brand-new note as soon as it has any title or content, so
  /// the rest of the session runs on the ordinary update path.
  void _maybeCreateNewNoteEarly() {
    if (_effectiveNoteId != null || _isCreatingNewNote) return;
    if (_title().trim().isNotEmpty || _content().trim().isNotEmpty) {
      unawaited(_createNewNoteEarly());
    }
  }

  /// Creates the note and switches the coordinator to update mode.
  ///
  /// The same per-folder uniqueness rule as rename and auto-save applies:
  /// a colliding title is dropped (the note is created untitled) rather
  /// than losing the content, and the user is told once — they can rename
  /// from the browser afterwards.
  Future<void> _createNewNoteEarly() async {
    if (_effectiveNoteId != null || _isCreatingNewNote) return;
    final title = _title().trim();
    final content = _content().trim();
    if (title.isEmpty && content.isEmpty) return;

    var titleToCreate = title;
    if (title.isNotEmpty) {
      final exists = await _titleExists(title: title);
      if (_disposed) return;
      if (exists) {
        titleToCreate = '';
        _warnedDuplicateTitle = true;
        _onDuplicateTitle(title);
      }
    }

    _isCreatingNewNote = true;
    if (_disposed) return;
    _dispatch(
      CreateOptimizedNote(
        folderId: folderId,
        title: titleToCreate,
        content: content,
      ),
    );
  }

  /// Publishes the dirty flag, deferring past the current frame when one
  /// is running.
  ///
  /// Change detection fires from inside a controller notification, which
  /// can land mid-build; writing a [ValueNotifier] there would rebuild a
  /// listener during layout. Outside a frame the write is immediate, so
  /// gesture-driven callers ([markChanged]) stay synchronous.
  void _setHasChanges(bool value) {
    if (_disposed || _hasChanges.value == value) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      _hasChanges.value = value;
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _hasChanges.value == value) return;
      _hasChanges.value = value;
    });
  }
}
