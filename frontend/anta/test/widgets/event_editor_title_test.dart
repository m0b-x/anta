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

/// Regression guard for item 1.2 of the calendar performance roadmap: the
/// title field used to carry `onChanged: (_) => setState(() {})`, so every
/// keystroke rebuilt the whole sheet and remounted the description's
/// `CodeEditor` subtree. Save and "Save as template" must still react to the
/// title (the latter had no `ListenableBuilder` at all and depended entirely
/// on that `setState`), while the description editor stays mounted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_title');
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
    final barService = await MarkdownBarService.getInstance();
    barBloc = MarkdownBarBloc(barService: barService);
  });

  tearDown(() async {
    await barBloc.close();
  });

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

  testWidgets('header Save enables once a title is entered', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    FilledButton saveButton() =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Leg day');
    await tester.pump();

    expect(saveButton().onPressed, isNotNull);
  });

  testWidgets('Save as template enables once a title is entered '
      '(regression guard: this button has no other listener wired to the '
      'title controller)', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    OutlinedButton templateButton() =>
        tester.widget<OutlinedButton>(find.byType(OutlinedButton));

    expect(templateButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Leg day');
    await tester.pump();

    expect(templateButton().onPressed, isNotNull);
  });

  testWidgets('a title keystroke does not remount the description editor', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final before = tester.element(find.byType(CodeEditor));

    await tester.enterText(find.byType(TextField), 'Leg day');
    await tester.pump();

    final after = tester.element(find.byType(CodeEditor));
    expect(identical(before, after), isTrue);
  });
}
