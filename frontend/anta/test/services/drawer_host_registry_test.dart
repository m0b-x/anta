import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/drawer_host_registry.dart';

/// The registry exists for the one case a `BuildContext` cannot serve: a
/// settings page popped by restore, or by a drawer row whose own context died
/// with the drawer, asking for "the drawer beneath me" to come back.
///
/// Its whole contract is the walk in `openTopDrawer` — which host wins, which
/// ones are shed, and which conditions stop the walk without opening anything.
void main() {
  setUp(DrawerHostRegistry.clear);
  tearDown(DrawerHostRegistry.clear);

  Widget host(
    GlobalKey<ScaffoldState> key,
    String label, {
    bool drawer = true,
  }) {
    return Scaffold(
      key: key,
      drawer: drawer ? const Drawer(child: Text('menu')) : null,
      body: Text(label),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(home: child));
  }

  bool isOpen(GlobalKey<ScaffoldState> key) =>
      key.currentState?.isDrawerOpen ?? false;

  testWidgets('the most recently registered mounted host wins', (tester) async {
    final beneath = GlobalKey<ScaffoldState>();
    final above = GlobalKey<ScaffoldState>();

    await pump(
      tester,
      Stack(children: [host(beneath, 'beneath'), host(above, 'above')]),
    );
    DrawerHostRegistry.register(beneath);
    DrawerHostRegistry.register(above);

    DrawerHostRegistry.openTopDrawer();
    await tester.pumpAndSettle();

    expect(isOpen(above), isTrue);
    expect(isOpen(beneath), isFalse);
  });

  testWidgets('re-registering an already known host moves it to the top', (
    tester,
  ) async {
    final first = GlobalKey<ScaffoldState>();
    final second = GlobalKey<ScaffoldState>();

    await pump(
      tester,
      Stack(children: [host(first, 'first'), host(second, 'second')]),
    );
    DrawerHostRegistry.register(first);
    DrawerHostRegistry.register(second);
    DrawerHostRegistry.register(first);

    DrawerHostRegistry.openTopDrawer();
    await tester.pumpAndSettle();

    expect(isOpen(first), isTrue);
    expect(DrawerHostRegistry.hostCount, 2);
  });

  testWidgets('a dead host is pruned on the way past', (tester) async {
    final survivor = GlobalKey<ScaffoldState>();
    final gone = GlobalKey<ScaffoldState>();

    await pump(
      tester,
      Stack(children: [host(survivor, 'survivor'), host(gone, 'gone')]),
    );
    DrawerHostRegistry.register(survivor);
    DrawerHostRegistry.register(gone);

    // The page above is unmounted without ever calling `unregister` — the
    // case a `dispose` that never ran would leave behind.
    await pump(tester, host(survivor, 'survivor'));
    expect(gone.currentState, isNull);

    DrawerHostRegistry.openTopDrawer();
    await tester.pumpAndSettle();

    expect(isOpen(survivor), isTrue);
    expect(DrawerHostRegistry.hostCount, 1);
  });

  testWidgets('a host whose drawer is currently null is a no-op, not a '
      'fall-through', (tester) async {
    final beneath = GlobalKey<ScaffoldState>();
    final searching = GlobalKey<ScaffoldState>();

    await pump(
      tester,
      Stack(
        children: [
          host(beneath, 'beneath'),
          host(searching, 'searching', drawer: false),
        ],
      ),
    );
    DrawerHostRegistry.register(beneath);
    DrawerHostRegistry.register(searching);

    DrawerHostRegistry.openTopDrawer();
    await tester.pumpAndSettle();

    expect(searching.currentState!.hasDrawer, isFalse);
    expect(isOpen(beneath), isFalse);
    expect(DrawerHostRegistry.hostCount, 2);
  });

  testWidgets('a drawer that is already open is left alone', (tester) async {
    final key = GlobalKey<ScaffoldState>();

    await pump(tester, host(key, 'only'));
    DrawerHostRegistry.register(key);
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();

    DrawerHostRegistry.openTopDrawer();
    await tester.pumpAndSettle();

    expect(isOpen(key), isTrue);
    expect(DrawerHostRegistry.hostCount, 1);
  });

  testWidgets('an empty registry is harmless', (tester) async {
    await pump(tester, const Scaffold(body: Text('nothing')));

    expect(DrawerHostRegistry.openTopDrawer, returnsNormally);
  });

  testWidgets('unregister drops the host it names', (tester) async {
    final beneath = GlobalKey<ScaffoldState>();
    final above = GlobalKey<ScaffoldState>();

    await pump(
      tester,
      Stack(children: [host(beneath, 'beneath'), host(above, 'above')]),
    );
    DrawerHostRegistry.register(beneath);
    DrawerHostRegistry.register(above);
    DrawerHostRegistry.unregister(above);

    DrawerHostRegistry.openTopDrawer();
    await tester.pumpAndSettle();

    expect(isOpen(beneath), isTrue);
    expect(isOpen(above), isFalse);
  });
}
