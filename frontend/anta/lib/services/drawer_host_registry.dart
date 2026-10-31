import 'package:flutter/material.dart';

/// Tracks the mounted pages that host the app drawer.
///
/// It existed so a settings page could reopen the drawer beneath it without
/// a `BuildContext` inside the host's `Scaffold`. Back now always lands on
/// the route beneath (settings rework D3), so nothing asks for a host any
/// more; the registrations stay until the rework's S7 sweep removes the
/// registry with the hosts that call it.
abstract final class DrawerHostRegistry {
  static final List<GlobalKey<ScaffoldState>> _hosts = [];

  /// Call from `initState` of a page whose `Scaffold` carries the drawer.
  static void register(GlobalKey<ScaffoldState> key) {
    _hosts.remove(key);
    _hosts.add(key);
  }

  /// Call from `dispose`.
  static void unregister(GlobalKey<ScaffoldState> key) {
    _hosts.remove(key);
  }

  @visibleForTesting
  static void clear() => _hosts.clear();

  @visibleForTesting
  static int get hostCount => _hosts.length;
}
