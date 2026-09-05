import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

/// The event editor's description field mounts the same wrapper the note
/// editor does, so Tab-indent and the checkbox toggle came for free — but
/// Enter-continuation lives in `EditorEditTracker`, which this sheet used to
/// skip with an empty `onTextChanged`, so a list typed here simply stopped at
/// the first Enter. Its sibling, the full-height description sheet, gained
/// the tracker first; this pins the parity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_desc');
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
    );
  });

  tearDown(() async => barBloc.close());

  Widget wrap() => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: EventEditorSheet(defaultDate: DateTime.utc(2026, 8, 20)),
      ),
    ),
  );

  CodeLineEditingController descriptionOf(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;

  /// Presses Enter at [offset] on line [index], the way the editor delivers
  /// it: the controller edits and its listeners run.
  Future<void> pressEnter(
    WidgetTester tester, {
    required int index,
    required int offset,
  }) async {
    final controller = descriptionOf(tester);
    controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: offset,
    );
    controller.applyNewLine();
    await tester.pump();
  }

  testWidgets('Enter on a list item carries the marker down', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    descriptionOf(tester).text = '- a';
    await tester.pump();

    await pressEnter(tester, index: 0, offset: 3);

    final controller = descriptionOf(tester);
    expect(controller.text, '- a\n- ');
    expect(controller.selection.baseIndex, 1);
    expect(controller.selection.baseOffset, 2);
  });

  testWidgets('Enter on an empty item ends the list', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    descriptionOf(tester).text = '- a\n- ';
    await tester.pump();

    await pressEnter(tester, index: 1, offset: 2);

    final controller = descriptionOf(tester);
    expect(controller.text, '- a\n');
    expect(controller.selection.baseIndex, 1);
    expect(controller.selection.baseOffset, 0);
  });

  testWidgets('a fenced list line is code, not a list', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    descriptionOf(tester).text = '```\n- a\n```';
    await tester.pump();

    await pressEnter(tester, index: 1, offset: 3);

    expect(descriptionOf(tester).text, '```\n- a\n\n```');
  });
}
