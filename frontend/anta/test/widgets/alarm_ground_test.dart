import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/widgets/alarm_ground.dart';

/// What a ring is shown on: the alarm page stands on it and the lock-screen
/// cover is nothing else.
///
/// Two things are pinned here that the page's own suite cannot see. One is
/// what the phone is actually told — the page suite reads the style the
/// ground declares, this one reads what reaches the platform. The other is
/// what happens after: Android keeps a navigation bar's style until somebody
/// sets another, no other page of the app sets one, and a ring must not
/// leave every page after it without the bar's contrast band and with the
/// buttons of a theme that may be gone by then.
///
/// What it leaves instead is what the app had before the ring, and that is
/// not the phone's own choice: `MaterialApp` asks for a black bar with light
/// buttons every time it builds its theme. From Android 15 the colour never
/// reaches the phone (Flutter's embedding drops it) and the phone forces dark
/// buttons on a light window, so the emulator reads the same whatever is
/// handed back; below it the phone draws what it is asked for, and a hand-back
/// by the phone's brightness left dark buttons on a light band under every
/// page after the first ring. The hand-back is therefore pinned twice: by what
/// it says, and against what `MaterialApp` itself says in the same Flutter.
void main() {
  /// Every style the platform was handed, oldest first, as the channel
  /// carries it.
  late List<Map<Object?, Object?>> sent;

  setUp(() {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            sent.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app(Widget home, {ThemeData? theme}) =>
      MaterialApp(theme: theme, home: home);

  /// A page of the app's own: an app bar, which says what the status bar
  /// wears and nothing about the navigation bar.
  Widget ordinaryPage() =>
      Scaffold(appBar: AppBar(title: const Text('Calendar settings')));

  const noBand = 'systemNavigationBarContrastEnforced';
  const buttons = 'systemNavigationBarIconBrightness';
  const barColor = 'systemNavigationBarColor';
  const divider = 'systemNavigationBarDividerColor';
  const statusIcons = 'statusBarIconBrightness';

  final themes = {'light': AppTheme.light(), 'dark': AppTheme.dark()};

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    testWidgets('in the $name theme it paints the page ground, edge to edge, '
        'and nothing else', (tester) async {
      await tester.pumpWidget(app(const AlarmGround(), theme: theme));

      final box = find.descendant(
        of: find.byType(AlarmGround),
        matching: find.byType(ColoredBox),
      );
      // One box: the cover is found by it, and a second one would be a
      // second thing on a locked phone.
      expect(box, findsOneWidget);
      expect(
        tester.widget<ColoredBox>(box).color,
        theme.colorScheme.pageGround,
      );
      expect(tester.getSize(box), tester.getSize(find.byType(MaterialApp)));
    });

    testWidgets('in the $name theme the phone is told what both bars wear', (
      tester,
    ) async {
      await tester.pumpWidget(app(const AlarmGround(), theme: theme));
      await tester.pump();

      final icons = theme.brightness == Brightness.dark
          ? 'Brightness.light'
          : 'Brightness.dark';
      final style = sent.last;
      expect(SystemChrome.latestStyle, AlarmGround.barsOver(theme.brightness));
      expect(style['statusBarColor'], 0);
      expect(style[statusIcons], icons);
      expect(style['systemNavigationBarColor'], 0);
      expect(style['systemNavigationBarDividerColor'], 0);
      expect(style[buttons], icons);
      expect(style[noBand], isFalse);
    });
  }

  testWidgets('it carries what stands on it', (tester) async {
    await tester.pumpWidget(
      app(const AlarmGround(child: Center(child: Text('ringing')))),
    );

    expect(find.text('ringing'), findsOneWidget);
  });

  testWidgets('when it leaves for a page of the app, that page restyles the '
      'status bar and the navigation bar is handed back as the app asks for '
      'it at launch', (tester) async {
    await tester.pumpWidget(app(const AlarmGround(), theme: AppTheme.dark()));
    await tester.pump();
    expect(sent.last[noBand], isFalse);
    expect(sent.last[buttons], 'Brightness.light');
    sent.clear();

    await tester.pumpWidget(app(ordinaryPage(), theme: AppTheme.dark()));
    await tester.pump();

    // First what the page under it says — the status bar, and not a word
    // about the navigation bar…
    expect(sent.first[statusIcons], isNotNull);
    expect(sent.first[noBand], isNull);
    expect(sent.first[buttons], isNull);
    // …then the hand-back: the band is on again, over the black bar with
    // light buttons the app itself asks for whenever it builds its theme.
    final handBack = sent.firstWhere((style) => style[noBand] != null);
    expect(handBack[noBand], isTrue);
    expect(handBack[buttons], 'Brightness.light');
    expect(handBack[barColor], 0xFF000000);
    expect(handBack[divider], 0);
    // The status bar is the next page's to style, not the ground's.
    expect(handBack[statusIcons], isNull);
    expect(sent.indexOf(handBack), greaterThan(0));
    expect(sent.where((style) => style[noBand] == false), isEmpty);
  });

  for (final phone in Brightness.values) {
    for (final MapEntry(key: name, value: theme) in themes.entries) {
      testWidgets('on a phone in ${phone.name} mode, under the $name theme, '
          'the bar goes back black with light buttons: the same four '
          'times', (tester) async {
        // Neither the phone's brightness nor the app's theme is in it. A
        // hand-back by the phone's — dark buttons on a light phone — set a
        // bit the app never has, and below Android 15 nothing covers it.
        tester.platformDispatcher.platformBrightnessTestValue = phone;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(app(const AlarmGround(), theme: theme));
        await tester.pump();
        sent.clear();

        await tester.pumpWidget(app(ordinaryPage(), theme: theme));
        await tester.pump();

        final handBack = sent.firstWhere((style) => style[noBand] != null);
        expect(handBack[noBand], isTrue);
        expect(handBack[buttons], 'Brightness.light');
        expect(handBack[barColor], 0xFF000000);
        expect(handBack[divider], 0);
        expect(handBack[statusIcons], isNull);
      });
    }
  }

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    testWidgets('what it hands back is what MaterialApp itself asked for when '
        'the app came up in the $name theme', (tester) async {
      // The day a Flutter upgrade changes what `MaterialApp` asks for, this
      // fails, and the ground has to follow.
      //
      // First something no part of the app would say, so that what is read
      // next is what MaterialApp said and not what an earlier case left.
      const nobodys = SystemUiOverlayStyle(statusBarColor: Color(0xFF123456));
      SystemChrome.setSystemUIOverlayStyle(nobodys);
      await tester.pump();
      expect(SystemChrome.latestStyle, nobodys);

      // The app as it stands at launch: a first page with no app bar, so
      // that nothing but MaterialApp has said what the bars wear.
      await tester.pumpWidget(app(const Scaffold(), theme: theme));
      await tester.pump();
      final atLaunch = SystemChrome.latestStyle!;
      expect(atLaunch, isNot(nobodys));

      await tester.pumpWidget(app(const AlarmGround(), theme: theme));
      await tester.pump();
      sent.clear();
      await tester.pumpWidget(app(const Scaffold(), theme: theme));
      await tester.pump();

      final handBack = sent.firstWhere((style) => style[noBand] != null);
      expect(handBack[barColor], atLaunch.systemNavigationBarColor!.toARGB32());
      expect(
        handBack[buttons],
        '${atLaunch.systemNavigationBarIconBrightness!}',
      );
    });
  }

  testWidgets('with two grounds up, the first to leave hands nothing back: '
      'the other is still what the bars are over', (tester) async {
    // The cover while the page under it is still leaving; a second ring's
    // page pushed before the first one's is gone.
    Widget grounds({required bool both}) => app(
      Stack(
        fit: StackFit.expand,
        children: [
          if (both) const AlarmGround(key: ValueKey('first')),
          const AlarmGround(key: ValueKey('second')),
        ],
      ),
    );
    await tester.pumpWidget(grounds(both: true));
    await tester.pump();
    sent.clear();

    await tester.pumpWidget(grounds(both: false));
    await tester.pump();

    expect(sent.where((style) => style[noBand] == true), isEmpty);

    await tester.pumpWidget(app(ordinaryPage()));
    await tester.pump();

    expect(sent.where((style) => style[noBand] == true), isNotEmpty);
  });
}
