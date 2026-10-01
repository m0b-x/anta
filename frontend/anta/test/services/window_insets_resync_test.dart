import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/window_insets_resync.dart';

const _channel = MethodChannel(WindowInsetsResync.channelName);

/// The Dart end of the stale-inset repair: one fire-and-forget call, on the
/// one platform whose embedding defers its keyboard inset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('asks the activity for the window insets on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    const WindowInsetsResync().request();
    await pumpEventQueue();

    expect(calls.map((call) => call.method), [WindowInsetsResync.resyncMethod]);
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('says nothing on ${platform.name}, where there is no activity to '
        'answer', () async {
      debugDefaultTargetPlatformOverride = platform;

      const WindowInsetsResync().request();
      await pumpEventQueue();

      expect(calls, isEmpty);
    });
  }

  test('a platform that throws leaves the caller untouched', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      throw PlatformException(code: 'no_view');
    });

    const WindowInsetsResync().request();

    await expectLater(pumpEventQueue(), completes);
  });

  test('a build with no handler on the channel leaves the caller untouched — '
      'a hot restart mid-attach, or an engine without the activity', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(_channel, null);

    const WindowInsetsResync().request();

    await expectLater(pumpEventQueue(), completes);
  });
}
