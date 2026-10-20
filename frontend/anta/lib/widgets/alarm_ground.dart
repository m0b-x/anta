import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// What a ring is shown on: the page ground, edge to edge, with both system
/// bars drawn over it.
///
/// The alarm page and the lock-screen cover both stand on it, so a ring on a
/// locked phone goes cover, page, cover with no step in tone between them.
///
/// **It says what the system bars wear** over its own ground. Before U2.10
/// nothing else in the app did for a page with no app bar: the status icons
/// were whatever the page underneath had left — white on this light ground
/// after Calendar settings — and under the dark theme the navigation bar was
/// the phone's own light band across the bottom of a dark page, on the one
/// screen with nothing else down there.
///
/// **And it hands the navigation bar back.** Android keeps a bar's style
/// until somebody sets another, and before U2.10 the app's other pages set
/// none for the navigation bar: left alone, one ring would strip the bar's
/// contrast band from every page after it and leave its buttons in this
/// theme's colour whatever theme came next. So when the last ground leaves
/// the screen the bar is put back in the state the app asks for at launch
/// ([barsAfter]). Since U2.10 the root `AppSystemBars` region (`main.dart`),
/// keyed on the app's resolved theme, is what the rest of the app's bars
/// wear, but the hand-back is sent after the frame that removed the ground
/// has already sent that region: [barsAfter] holds until the next frame the
/// app composites, which on an idle page waits for the next interaction.
class AlarmGround extends StatefulWidget {
  const AlarmGround({super.key, this.child});

  /// What stands on the ground: the alarm page. The cover passes nothing.
  final Widget? child;

  /// What the two bars wear over the ground of a theme of [brightness]:
  /// transparent, with no divider and no contrast band, and with icons that
  /// read on the ground — dark on the light one, light on the dark one.
  ///
  /// The navigation buttons are asked for, not promised. Since Android 15 a
  /// window in the phone's own light theme has them forced dark whatever the
  /// app says (`FORCE_LIGHT_NAVIGATION_BARS` in `dumpsys window`, seen on the
  /// API 36 emulator): under the app's dark theme on a phone left in light
  /// mode they come out mid-grey on the dark ground — legible, with no band
  /// behind them, and not the light ones asked for here.
  @visibleForTesting
  static SystemUiOverlayStyle barsOver(Brightness brightness) {
    final icons = _iconsOver(brightness);
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS names the bar's background, not its icons.
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// What the navigation bar goes back to once no ground is on screen: what
  /// the app asks for at launch, whatever the phone's brightness and the
  /// app's theme — until the next frame the app composites, when the root
  /// `AppSystemBars` region takes the bars over again.
  ///
  /// That is what `MaterialApp` itself sets every time it builds its theme —
  /// [SystemUiOverlayStyle.light] or [SystemUiOverlayStyle.dark], which say
  /// the same of this bar: black, with light buttons — over the transparent
  /// divider `main.dart` set before it, with contrast enforcement where the
  /// platform has it by default, on. The colour and the buttons are read off
  /// Flutter's constant, not written out again, so they move with it.
  ///
  /// What the phone draws from there is its own. Below Android 15 it draws
  /// what it is asked for, light buttons on black. From 15 the colour is no
  /// longer passed on to it (Flutter's Android embedding drops a bar colour
  /// from API 35) and it forces the buttons of a light window dark
  /// (`FORCE_LIGHT_NAVIGATION_BARS`), so a phone in light mode reads the same
  /// whatever is handed back — which is how a hand-back by the phone's own
  /// brightness looked right on the API 36 emulator while, below 15, it left
  /// dark buttons on a light band under every page after the first ring.
  ///
  /// Only the navigation bar: the status bar is restyled by the next page's
  /// own app bar.
  @visibleForTesting
  static SystemUiOverlayStyle barsAfter() {
    const atLaunch = SystemUiOverlayStyle.light;
    return SystemUiOverlayStyle(
      systemNavigationBarColor: atLaunch.systemNavigationBarColor,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          atLaunch.systemNavigationBarIconBrightness,
      systemNavigationBarContrastEnforced: true,
    );
  }

  static Brightness _iconsOver(Brightness ground) =>
      ground == Brightness.dark ? Brightness.light : Brightness.dark;

  @override
  State<AlarmGround> createState() => _AlarmGroundState();
}

class _AlarmGroundState extends State<AlarmGround> {
  /// The grounds on screen. A count, because they overlap: the cover is up
  /// while the page under it is still leaving, and a second ring's page is
  /// pushed before the first one's is gone.
  static int _onScreen = 0;

  @override
  void initState() {
    super.initState();
    _onScreen++;
  }

  @override
  void dispose() {
    _onScreen--;
    // A microtask, not a call: this runs at the end of a frame that has
    // already queued the style of whatever is on screen now, and a second
    // style set in the same turn would replace that one instead of following
    // it — the next page's status bar would wait for a frame that may never
    // come.
    if (_onScreen == 0) scheduleMicrotask(_handBackNavigationBar);
    super.dispose();
  }

  static void _handBackNavigationBar() {
    if (_onScreen > 0) return;
    SystemChrome.setSystemUIOverlayStyle(AlarmGround.barsAfter());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AlarmGround.barsOver(theme.brightness),
      child: ColoredBox(
        color: theme.colorScheme.pageGround,
        child: widget.child,
      ),
    );
  }
}
