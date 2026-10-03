import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

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

    FormActionRow templateRow() => tester.widget<FormActionRow>(
      find.widgetWithText(FormActionRow, 'Save as template'),
    );

    expect(templateRow().onTap, isNull);

    await tester.enterText(find.byType(TextField), 'Leg day');
    await tester.pump();

    expect(templateRow().onTap, isNotNull);
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

  testWidgets('a tap in the title row beside its text — its bottom-left '
      'area, under the avatar — focuses the title', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    bool focused() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byType(FormTitleRow),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;
    // A new event opens on its title; dropped first, so the tap is what
    // focuses it.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(focused(), isFalse);

    final row = tester.getRect(find.byType(FormTitleRow));
    final field = tester.getRect(
      find.descendant(
        of: find.byType(FormTitleRow),
        matching: find.byType(TextField),
      ),
    );
    final point = Offset(row.left + 8, row.bottom - 4);
    expect(field.contains(point), isFalse);
    await tester.tapAt(point);
    await tester.pump();

    expect(focused(), isTrue);
  });

  testWidgets('the title is named by its hint for a screen reader, empty and '
      'typed', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    SemanticsData data() => tester
        .getSemantics(find.bySemanticsIdentifier(SemanticsIds.eventTitle))
        .getSemanticsData();
    expect(data().label, 'Title');
    expect(data().flagsCollection.isTextField, isTrue);

    await tester.enterText(find.byType(TextField), 'Leg day');
    await tester.pumpAndSettle();
    expect(data().label, 'Title');
    expect(data().value, 'Leg day');
  });
}
