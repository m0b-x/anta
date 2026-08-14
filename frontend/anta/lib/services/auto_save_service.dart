import 'dart:async';
import 'package:flutter/foundation.dart';

enum SaveStatus { saved, unsaved, saving, error }

class AutoSaveService {
  final Duration saveInterval;
  final Duration debounceDelay;
  final Future<void> Function(String? title, String? content) onSave;
  final void Function(bool hasChanges)? onChangeDetected;

  String _savedTitle = '';
  int _savedContentHash = 0;
  int _savedContentLength = 0;
  bool _hasPendingChanges = false;

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
    stopTracking();

    _savedTitle = title;
    _savedContentHash = content.hashCode;
    _savedContentLength = content.length;
    _contentProvider = contentProvider;
    _latestTitle = title;
    _hasPendingChanges = false;

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

    try {
      await onSave(
        titleChanged ? currentTitle : null,
        contentChanged ? currentContent : null,
      );

      _savedTitle = currentTitle;
      _savedContentHash = currentContent.hashCode;
      _savedContentLength = currentContent.length;
      _hasPendingChanges = false;
      _retryCount = 0;
      _retryTimer?.cancel();

      _updateStatus(SaveStatus.saved);
      onChangeDetected?.call(false);
    } catch (e, stackTrace) {
      debugPrint('[AutoSaveService] Save failed: $e');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);

      _updateStatus(SaveStatus.error);
      _scheduleRetry();
    } finally {
      _isSaving = false;
      _inFlightSave?.complete();
      _inFlightSave = null;
    }
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
    final saveTitle = title ?? _latestTitle;
    final saveContent = content ?? _contentProvider?.call();
    if (saveContent == null) return;
    _latestTitle = saveTitle;
    // Wait for any in-progress save to finish before forcing our own,
    // otherwise _performSave's _isSaving guard would silently drop this.
    if (_isSaving) await _inFlightSave?.future;
    await _performSave(saveTitle, saveContent);
  }

  bool get hasPendingChanges => _hasPendingChanges;

  void _updateStatus(SaveStatus status) {
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
