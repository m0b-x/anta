import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/shortcut_editor_page.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/markdown_bar_service.dart';

/// The shortcut editor's "before" / "after" fields continue a list on
/// Enter, exactly as the note editor does. They used to do it with a
/// second, private list grammar that knew `-` and `N.` and nothing else,
/// dropped indentation, and parsed an unbounded digit run with
/// `int.parse` — so a 20-digit ordinal plus Enter threw a
/// `FormatException` out of a text-field listener.
///
/// These cases are the shapes the shared [MarkdownListUtils] grammar
/// answers and the private pair did not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;
  late CounterBloc counterBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_shortcut_editor');
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
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    )..add(const LoadMarkdownBar());
    counterBloc = CounterBloc(
      counterService: await CounterService.getInstance(),
    );
  });

  tearDown(() async {
    await barBloc.close();
    await counterBloc.close();
  });

  /// Mounts the page and returns the "before text" field's controller —
  /// the one `_handleTextChange` watches.
  Future<TextEditingController> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<MarkdownBarBloc>.value(value: barBloc),
          BlocProvider<CounterBloc>.value(value: counterBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ShortcutEditorPage(onSave: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField).at(1);
    expect(field, findsOneWidget);
    return tester.widget<TextField>(field).controller!;
  }

  /// Rewrites the field the way typing would: the text grows and the
  /// caret sits at its end, which is the shape `_handleTextChange` reads.
  void type(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  testWidgets('Enter continues a `*` bullet the old grammar ignored', (
    tester,
  ) async {
    final controller = await pumpPage(tester);

    type(controller, '* squat');
    type(controller, '* squat\n');
    await tester.pump();

    expect(controller.text, '* squat\n* ');
  });

  testWidgets('Enter keeps a nested item at its own depth', (tester) async {
    final controller = await pumpPage(tester);

    type(controller, '  - squat');
    type(controller, '  - squat\n');
    await tester.pump();

    expect(controller.text, '  - squat\n  - ');
  });

  testWidgets('Enter continues an `N)` ordered item', (tester) async {
    final controller = await pumpPage(tester);

    type(controller, '3) third');
    type(controller, '3) third\n');
    await tester.pump();

    expect(controller.text, '3) third\n4) ');
  });

  testWidgets('Enter after an ordinal too large for an int does not throw', (
    tester,
  ) async {
    final controller = await pumpPage(tester);

    // `int.parse` on this threw a `FormatException` straight out of the
    // controller listener; the shared grammar's `int.tryParse` falls back.
    type(controller, '99999999999999999999. x');
    type(controller, '99999999999999999999. x\n');
    await tester.pump();

    expect(controller.text, startsWith('99999999999999999999. x\n'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter on an empty item drops the item line', (tester) async {
    final controller = await pumpPage(tester);

    type(controller, '- squat\n- ');
    type(controller, '- squat\n- \n');
    await tester.pump();

    expect(controller.text, '- squat\n');
  });
}
