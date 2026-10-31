import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/drawer_host_registry.dart';

/// Nothing asks the registry for a host since back always lands on the route
/// beneath (settings rework D3); what is left is its registration side,
/// which the drawer hosts still call until S7 removes it.
void main() {
  setUp(DrawerHostRegistry.clear);
  tearDown(DrawerHostRegistry.clear);

  test('registering a known host again keeps one entry for it', () {
    final first = GlobalKey<ScaffoldState>();
    final second = GlobalKey<ScaffoldState>();

    DrawerHostRegistry.register(first);
    DrawerHostRegistry.register(second);
    DrawerHostRegistry.register(first);

    expect(DrawerHostRegistry.hostCount, 2);
  });

  test('unregister drops the host it names', () {
    final beneath = GlobalKey<ScaffoldState>();
    final above = GlobalKey<ScaffoldState>();

    DrawerHostRegistry.register(beneath);
    DrawerHostRegistry.register(above);
    DrawerHostRegistry.unregister(above);

    expect(DrawerHostRegistry.hostCount, 1);
  });
}
