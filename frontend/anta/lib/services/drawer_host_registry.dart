import 'package:flutter/material.dart';

/// Tracks the mounted pages that host the app drawer, so a page can be told
/// to reopen it without a `BuildContext` from inside that page's `Scaffold`.
///
/// This exists for one case: a settings page rebuilt by restore. In normal use
/// the drawer row that pushed a settings page awaits its result and reopens
/// the drawer on `SettingsResult.openDrawer` — an arrangement that only works
/// because there is a live awaiter holding a context inside the host scaffold.
/// A restored page has no such awaiter, so the "reopen the drawer beneath me"
/// intent needs a home that does not depend on who pushed the route.
///
/// Deliberately dumb: [openTopDrawer] targets the most recently registered
/// host still mounted, which under a restored chain is the folder page or note
/// editor directly beneath the settings page. The drawer rows keep their
/// existing await-pattern; this is the designated replacement for it if the
/// two ever need to be unified.
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

  /// Opens the drawer on the innermost mounted host, if there is one. Hosts
  /// whose state has gone away are dropped on the way past rather than in a
  /// separate sweep — nothing else would ever notice them.
  static void openTopDrawer() {
    while (_hosts.isNotEmpty) {
      final host = _hosts.last;
      final state = host.currentState;
      if (state == null) {
        _hosts.removeLast();
        continue;
      }
      if (!state.hasDrawer || state.isDrawerOpen) return;
      state.openDrawer();
      return;
    }
  }

  @visibleForTesting
  static void clear() => _hosts.clear();

  @visibleForTesting
  static int get hostCount => _hosts.length;
}
