import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/window_insets_resync.dart';

/// The window channel is spelled twice — once in Dart, once in Kotlin — and
/// no build step compares the two. A rename on either side would compile,
/// run, and silently turn the stale-inset repair into a call nobody answers,
/// which is a failure only a phone with a stuck keyboard inset would show.
void main() {
  final activity = File(
    'android/app/src/main/kotlin/com/alexzamfir/anta/MainActivity.kt',
  );

  test('the activity registers the channel Dart calls', () {
    expect(
      activity.readAsStringSync(),
      contains('"${WindowInsetsResync.channelName}"'),
    );
  });

  test('the activity answers the method Dart invokes', () {
    expect(
      activity.readAsStringSync(),
      contains('"${WindowInsetsResync.resyncMethod}" ->'),
    );
  });
}
