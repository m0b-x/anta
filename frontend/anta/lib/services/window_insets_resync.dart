import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks the Android activity to have the window dispatch its insets again.
///
/// The repair half of the stale keyboard inset (`KeyboardInsetTrust` has the
/// story): the embedding can leave the Flutter view holding a keyboard inset
/// the window no longer has, and the window will not send its insets again
/// until they next change. A requested dispatch carries the current ones,
/// and the view republishes its metrics for every dispatch it is handed.
///
/// Android only. Nothing else defers its keyboard inset, so nothing else has
/// an inset to repair.
class WindowInsetsResync {
  const WindowInsetsResync({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'com.alexzamfir.anta/window';
  static const String resyncMethod = 'resyncInsets';

  final MethodChannel _channel;

  /// Fire-and-forget: the answer arrives as window metrics, like any other
  /// inset change, and a failure leaves things exactly as they were.
  void request() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(_resync());
  }

  Future<void> _resync() async {
    try {
      await _channel.invokeMethod<void>(resyncMethod);
    } catch (e) {
      debugPrint('[WindowInsetsResync] resync failed: $e');
    }
  }
}
