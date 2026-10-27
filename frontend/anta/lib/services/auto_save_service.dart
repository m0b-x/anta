import 'dart:async';
import 'package:flutter/foundation.dart';

enum SaveStatus { saved, unsaved, saving, error }

/// Raised by [AutoSaveService.onSave] to refuse a write for now — a
/// deliberate hold, not a failure.
///
/// The note editor holds its writes while a change merged from another
/// device is still being filed (record §3.9, M3/M4). The text stays unsaved
/// and the debounce re-arms, but the status stays `unsaved` and the retry
/// ladder is left for writes that really failed: a run of holds used to show
/// the error dot and burn all three rungs, so a genuine failure afterwards
/// got none (S4b-1 review L8).
class SaveHeld implements Exception {
  const SaveHeld(this.reason);

  final String reason;

  @override
  String toString() => 'SaveHeld: $reason';
}

/// Raised by [AutoSaveService.onSave] when the row itself refuses the write
/// — it is a tombstone, so no write will ever land on it.
///
/// Like [SaveHeld] the text stays unsaved and spends no retry rung, and for
/// the same reason: a refusal is not a failing disk. The debounce is not
/// re-armed either — every rung and every retry would meet the same
/// tombstone, while the editor's delete handler owns the text from here and
/// files it as a new note (A6 review R115).
class SaveRefused implements Exception {
  const SaveRefused(this.reason);

  final String reason;

  @override
  String toString() => 'SaveRefused: $reason';
}

class AutoSaveService {
  final Duration saveInterval;
  final Duration debounceDelay;
  final Future<void> Function(String? title, String? content) onSave;
  final void Function(bool hasChanges)? onChangeDetected;

  String _savedTitle = '';
  int _savedContentHash = 0;
  int _savedContentLength = 0;
  bool _hasPendingChanges = false;

  /// Bumped by [adoptSavedContent]. A write compares it against
  /// [_writeBaseline] when it lands and leaves the baseline alone when it
  /// moved meanwhile: the body a sync merge adopted while the row was being
  /// written is what the row holds, and stamping the written text over it
  /// would read the page clean over text the row does not have (S4b-1
  /// review R1).
  int _baselineGeneration = 0;

  /// [_baselineGeneration] as it stood when the write in flight went out —
  /// see [writeIssued].
  int _writeBaseline = 0;

  String Function()? _contentProvider;
  String _latestTitle = '';

  Timer? _debounceTimer;
  Timer? _intervalTimer;
  bool _isSaving = false;
  bool _disposed = false;
  Completer<void>? _inFlightSave;

  final ValueNotifier<SaveStatus> saveStatusNotifier = ValueNotifier(
    SaveStatus.saved,
  );

  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 2);
  Timer? _retryTimer;
  int _retryCount = 0;

  AutoSaveService({
    required this.onSave,
    this.onChangeDetected,
    this.saveInterval = const Duration(seconds: 30),
    this.debounceDelay = const Duration(seconds: 5),
  });

  void startTracking(
    String title,
    String content, {
    required String Function() contentProvider,
  }) {
    if (_disposed) return;
    stopTracking();

    _savedTitle = title;
    _savedContentHash = content.hashCode;
    _savedContentLength = content.length;
    _contentProvider = contentProvider;
    _latestTitle = title;
    _hasPendingChanges = false;
    // A fresh baseline has nothing unsaved. Loading a note reads as an edit
    // until the caller re-baselines on it, and nothing else clears the
    // `unsaved` that leaves behind until the next real save. A write still
    // in flight reports its own outcome when it lands.
    if (!_isSaving) _updateStatus(SaveStatus.saved);

    _intervalTimer = Timer.periodic(saveInterval, (_) {
      _checkAndSave();
    });
  }

  void stopTracking() {
    _debounceTimer?.cancel();
    _intervalTimer?.cancel();
    _retryTimer?.cancel();
    _debounceTimer = null;
    _intervalTimer = null;
    _retryTimer = null;
    _retryCount = 0;
  }

  void onContentChanged(String currentTitle) {
    if (_disposed) return;
    _latestTitle = currentTitle;
    _hasPendingChanges = true;
    _updateStatus(SaveStatus.unsaved);
    onChangeDetected?.call(true);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      await _checkAndSave();
    });
  }

  Future<void> _checkAndSave() async {
    if (!_hasPendingChanges) return;

    final currentContent = _contentProvider?.call();
    if (currentContent == null) return;

    await _performSave(_latestTitle, currentContent);
  }

  Future<void> _performSave(String currentTitle, String currentContent) async {
    if (_isSaving || _disposed) return;

    final titleChanged = currentTitle != _savedTitle;
    final contentChanged =
        currentContent.length != _savedContentLength ||
        currentContent.hashCode != _savedContentHash;

    if (!titleChanged && !contentChanged) {
      _hasPendingChanges = false;
      _updateStatus(SaveStatus.saved);
      onChangeDetected?.call(false);
      return;
    }

    _isSaving = true;
    _inFlightSave = Completer<void>();
    _updateStatus(SaveStatus.saving);
    _writeBaseline = _baselineGeneration;

    try {
      await onSave(
        titleChanged ? currentTitle : null,
        contentChanged ? currentContent : null,
      );

      // Only what the write carried becomes the baseline: a title-only write
      // must not stamp the body it read as saved, since a sync merge may
      // have adopted a newer one while the write was held (record §3.9, M6).
      // Nor may a body write, when a merge adopted a body of its own during
      // the await: that body is the one the row holds now (R1).
      final adopted = _baselineGeneration != _writeBaseline;
      if (titleChanged) _savedTitle = currentTitle;
      if (contentChanged && !adopted) {
        _savedContentHash = currentContent.hashCode;
        _savedContentLength = currentContent.length;
      }
      _retryCount = 0;
      _retryTimer?.cancel();

      // A write can wait a long time — the page holds it while a synced
      // change is filed — and keystrokes made meanwhile were dropped by the
      // `_isSaving` guard. Reading the page clean over them would let the
      // next reload wipe them (S4b-1 review H1), so they stay pending. So
      // does the text of a body write whose baseline moved: what it wrote is
      // no longer what the row holds.
      final live = _contentProvider?.call();
      if ((contentChanged && adopted) ||
          _latestTitle != _savedTitle ||
          (live != null && !isSavedContent(live))) {
        _hasPendingChanges = true;
        _updateStatus(SaveStatus.unsaved);
        onChangeDetected?.call(true);
        _rearmDebounce();
      } else {
        _hasPendingChanges = false;
        _updateStatus(SaveStatus.saved);
        onChangeDetected?.call(false);
      }
    } on SaveHeld catch (held) {
      debugPrint('[AutoSaveService] Save held: $held');
      _hasPendingChanges = true;
      _updateStatus(SaveStatus.unsaved);
      onChangeDetected?.call(true);
      _rearmDebounce();
    } on SaveRefused catch (refused) {
      debugPrint('[AutoSaveService] Save refused: $refused');
      _hasPendingChanges = true;
      _updateStatus(SaveStatus.unsaved);
      onChangeDetected?.call(true);
    } catch (e, stackTrace) {
      debugPrint('[AutoSaveService] Save failed: $e');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);

      _updateStatus(SaveStatus.error);
      // The flag is still up — the write cleared it only on its way out — and
      // saying so keeps the page's own indicator with the status (R15).
      onChangeDetected?.call(true);
      _scheduleRetry();
    } finally {
      _isSaving = false;
      _inFlightSave?.complete();
      _inFlightSave = null;
    }
  }

  /// Arms the debounce for text a write left unsaved.
  ///
  /// A deadline a keystroke already armed is kept: cancelling it and timing
  /// a fresh [debounceDelay] from here would make that keystroke wait up to
  /// twice its own debounce (R14). Only while tracking — a stopped service
  /// (saves disabled for a delete) writes nothing, and re-arming would loop.
  void _rearmDebounce() {
    if (_disposed || _intervalTimer == null) return;
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(debounceDelay, () async {
      await _checkAndSave();
    });
  }

  void _scheduleRetry() {
    if (_retryCount >= _maxRetries) {
      debugPrint('[AutoSaveService] Max retries ($_maxRetries) reached.');
      return;
    }

    final delay = _initialRetryDelay * (1 << _retryCount);
    _retryCount++;

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () async {
      await _checkAndSave();
    });
  }

  Future<void> forceSave({String? title, String? content}) async {
    _debounceTimer?.cancel();
    // Wait for any in-progress save to finish before forcing our own,
    // otherwise _performSave's _isSaving guard would silently drop this.
    if (_isSaving) await _inFlightSave?.future;
    // Both values are resolved *after* that wait: anything typed while the
    // earlier write was in flight has to land in this save, and reading
    // them first would stamp it as already saved and lose it.
    final saveTitle = title ?? _latestTitle;
    final saveContent = content ?? _contentProvider?.call();
    if (saveContent == null) return;
    _latestTitle = saveTitle;
    await _performSave(saveTitle, saveContent);
  }

  bool get hasPendingChanges => _hasPendingChanges;

  /// Whether [content] is the text last loaded or written — the baseline a
  /// sync merge is judged against: a merged body equal to it is a remote
  /// move, rename or re-save that left the text alone (record §3.9, H1).
  bool isSavedContent(String content) =>
      content.length == _savedContentLength &&
      content.hashCode == _savedContentHash;

  /// The write [onSave] was asked for is going out now.
  ///
  /// Everything [onSave] does before this — a hold the page kept the write
  /// in while it filed a synced change, a title lookup — happened before the
  /// row was touched, so a baseline adopted there is older than what this
  /// write is about to land. Only an adoption from here on owns the row (R1).
  void writeIssued() {
    if (_isSaving) _writeBaseline = _baselineGeneration;
  }

  /// Makes [content] the baseline without touching the title's or the
  /// pending flag: the row now holds it (a sync merge wrote it), so the next
  /// save must compare the editor's text against it, not against the text it
  /// replaced.
  void adoptSavedContent(String content) {
    _savedContentHash = content.hashCode;
    _savedContentLength = content.length;
    _baselineGeneration++;
  }

  void _updateStatus(SaveStatus status) {
    if (_disposed) return;
    if (saveStatusNotifier.value != status) {
      saveStatusNotifier.value = status;
    }
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _debounceTimer?.cancel();
    _intervalTimer?.cancel();
    saveStatusNotifier.dispose();
  }
}
