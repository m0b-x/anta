import 'package:flutter/widgets.dart';

/// Keeps every page route pushed, so a suite can read where a row went —
/// its arguments, its builder — without the page under it. Popup routes (a
/// dialog, a menu, a sheet) are left out.
class PageRouteRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pushed.add(route);
  }
}
