import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

/// An editor wraps the controller it is given in a delegate of its own, and
/// the handoff used to end in `notifyListeners()` on the host's controller —
/// from `initState`, so in the middle of a build, with nothing changed.
///
/// Every host paid for it: a note read as edited the moment its editor
/// mounted, a builder above the editor was dirtied while the framework was
/// building ("setState() or markNeedsBuild() called during build"), and an
/// editor being replaced had its own listeners run against a context that
/// was already deactivated. The handoff now tells only the listeners this
/// editor registered, which on a first attach is nobody.
void main() {
  const double viewportWidth = 300.0;
  const double viewportHeight = 200.0;

  late CodeIndicatorValueNotifier notifier;

  Widget host(
    CodeLineEditingController controller, {
    Key? editorKey,
    Widget? above,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ?above,
            SizedBox(
              width: viewportWidth,
              height: viewportHeight,
              child: CodeEditor(
                key: editorKey,
                controller: controller,
                autofocus: false,
                wordWrap: false,
                padding: EdgeInsets.zero,
                style: const CodeEditorStyle(fontSize: kTestFontSize),
                indicatorBuilder: (context, editing, chunk, valueNotifier) {
                  notifier = valueNotifier;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('attaching an editor announces nothing to the host', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('first\nsecond');
    addTearDown(controller.dispose);
    var announced = 0;
    controller.addListener(() => announced++);

    await tester.pumpWidget(host(controller));
    await settle(tester);

    expect(announced, 0, reason: 'mounting an editor is not an edit');
    await teardownEditor(tester);
  });

  testWidgets('a builder above the editor is not dirtied by the mount', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('first\nsecond');
    addTearDown(controller.dispose);
    var builds = 0;

    // Built before the editor, and listening to the controller directly:
    // the shape that threw, since it is already clean when the editor's
    // `initState` runs further down the same build.
    await tester.pumpWidget(
      host(
        controller,
        above: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            builds++;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(builds, 1);
    await teardownEditor(tester);
  });

  testWidgets('replacing a mounted editor announces nothing either', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('first\nsecond');
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, editorKey: const ValueKey('one')));
    await settle(tester);
    final first = tester.state(find.byType(CodeEditor));

    var announced = 0;
    controller.addListener(() => announced++);

    // A different key is a remount: the outgoing editor is deactivated,
    // its listeners still on the controller until the frame ends, while
    // the incoming one attaches.
    await tester.pumpWidget(host(controller, editorKey: const ValueKey('two')));
    await settle(tester);

    expect(tester.state(find.byType(CodeEditor)), isNot(same(first)));
    expect(tester.takeException(), isNull);
    expect(announced, 0);
    await teardownEditor(tester);
  });

  testWidgets('a controller swapped into a mounted editor is still shown', (
    tester,
  ) async {
    final first = CodeLineEditingController.fromText('first document');
    final second = CodeLineEditingController.fromText('second document');
    addTearDown(() {
      second.dispose();
      first.dispose();
    });

    await tester.pumpWidget(host(first));
    await settle(tester);
    final state = tester.state(find.byType(CodeEditor));
    expect(textFieldNode().value, 'first document');

    await tester.pumpWidget(host(second));
    await settle(tester);

    // An update, not a remount — the handoff with listeners of its own to
    // refresh, which is the case it exists for.
    expect(tester.state(find.byType(CodeEditor)), same(state));
    expect(textFieldNode().value, 'second document');
    expect(expectedWindow(notifier, second), 'second document');
    await teardownEditor(tester);
  });
}
