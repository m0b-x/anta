import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/handlers/counter_shortcut_handler.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/services/counter_service.dart';

/// The counter shortcut counts once and writes the number it reached at the
/// caret — and with no caret it does neither: a count that lands in no note
/// is a number nobody can see.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CounterService service;
  late CounterBloc bloc;
  late String sets;

  // The handler asks the singleton, so the suite opens the real one over a
  // file, once: `AppDatabase` keeps its instance per name across cases.
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_counter_shortcut');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    service = await CounterService.getInstance();
    sets = await service.addCounter(name: 'Sets', startValue: 3);
    bloc = CounterBloc(counterService: service);
  });

  tearDown(() async {
    await bloc.close();
    await service.flush();
    CounterService.reset();
  });

  CustomMarkdownShortcut shortcut() => CustomMarkdownShortcut(
    id: 'counter',
    label: 'Sets',
    iconCodePoint: Icons.add.codePoint,
    iconFontFamily: 'MaterialIcons',
    beforeText: 'Set ',
    afterText: '',
    insertType: 'counter',
    counterId: sets,
  );

  /// Runs the shortcut on a field showing [controller], in real time: the
  /// handler's awaits and its flush timer are not the fake clock's.
  Future<void> press(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<CounterBloc>.value(
          value: bloc,
          child: Scaffold(
            body: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(TextField));
    await tester.runAsync(() async {
      CounterShortcutHandler().execute(
        context: context,
        shortcut: shortcut(),
        controller: controller,
        focusNode: focusNode,
        onTextChanged: () {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }

  testWidgets('at the caret it writes the number it counted to', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Day\n');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 4);

    await press(tester, controller);

    expect(controller.text, 'Day\nSet 4');
    expect(controller.selection, const TextSelection.collapsed(offset: 9));
    expect(service.getGlobalValue(sets), 4);
  });

  testWidgets('with no caret it writes nothing and counts nothing', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Day\n');
    addTearDown(controller.dispose);
    expect(controller.selection.isValid, isFalse);

    await press(tester, controller);

    expect(controller.text, 'Day\n');
    expect(service.getGlobalValue(sets), 3);
  });
}
