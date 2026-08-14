import 'dart:async';

import 'package:flutter/foundation.dart';

/// Global service to manage loading state across the app.
/// Uses ValueNotifier for reactive updates.
class LoadingService {
  static final LoadingService _instance = LoadingService._internal();
  factory LoadingService() => _instance;
  LoadingService._internal();

  /// How long an operation must run before the indicator appears.
  ///
  /// Every statement the app issues passes through here, and the great
  /// majority finish in well under a millisecond. Flipping [isLoading] for
  /// those rebuilt `AppLoadingBar` twice per statement and restarted its
  /// 200 ms `AnimatedContainer` each time — a bar visibly flickering while
  /// auto-save ran, plus animation work driven by database traffic. Now a
  /// query faster than this delay never touches the notifier at all.
  static const Duration showDelay = Duration(milliseconds: 50);

  /// ValueNotifier that tracks if a database operation is in progress
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);

  /// Counter to track nested operations
  int _operationCount = 0;

  /// Pending "show the bar" callback, cancelled when the work finishes first.
  Timer? _showTimer;

  /// Start a loading operation
  void startLoading() {
    _operationCount++;
    if (_operationCount == 1 && !isLoading.value) {
      _showTimer?.cancel();
      _showTimer = Timer(showDelay, () {
        _showTimer = null;
        // Re-check: the work may have finished during the delay.
        if (_operationCount > 0) isLoading.value = true;
      });
    }
  }

  /// End a loading operation
  void stopLoading() {
    if (_operationCount > 0) {
      _operationCount--;
      if (_operationCount == 0) {
        _showTimer?.cancel();
        _showTimer = null;
        if (isLoading.value) isLoading.value = false;
      }
    }
  }

  /// Execute an async operation with loading state
  Future<T> withLoading<T>(Future<T> Function() operation) async {
    startLoading();
    try {
      return await operation();
    } finally {
      stopLoading();
    }
  }

  /// Reset the loading state (useful for error recovery)
  void reset() {
    _showTimer?.cancel();
    _showTimer = null;
    _operationCount = 0;
    isLoading.value = false;
  }
}
