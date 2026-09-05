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
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The full-height description editor is a pure text-in / text-out modal: it
/// never persists, so everything that can go wrong is in what it hands back
/// and when it refuses to hand anything back at all.
///
/// The limit guard is the interesting half. It is enforced by disabling Done —
/// never by truncating — and it carries the grandfather rule across from the
/// editor sheet: text is always confirmable at a length it already had, so
/// lowering the setting blocks *growth* instead of trapping the user in a
/// sheet they cannot leave.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_description');
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

  /// Opens the sheet over a trivial host page and records what it returns.
  /// `result.value` stays absent until the sheet actually pops.
  Future<({List<String?> value})> openSheet(
    WidgetTester tester, {
    required String initialText,
    String heading = 'Leg day',
    int limit = 2000,
    int? grandfatheredLength,
    String? scopeCaption,
  }) async {
    final value = <String?>[];
    await tester.pumpWidget(
      // Above the `MaterialApp`, as `main.dart` provides it: the sheet is a
      // route, so a provider inside `home` would sit below it in the tree and
      // the sheet's `context.read` would not find it.
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  value.add(
                    await EventDescriptionSheet.show(
                      context,
                      initialText: initialText,
                      heading: heading,
                      limit: limit,
                      grandfatheredLength:
                          grandfatheredLength ?? initialText.length,
                      scopeCaption: scopeCaption,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (value: value);
  }

  /// Rewrites the description the way the app does — through the controller.
  /// `tester.enterText` cannot be used here: a `CodeEditor` is not an
  /// `EditableText`, so `showKeyboard` finds no state to drive. Going through
  /// the controller is also what exercises the `ValueNotifier` relay that the
  /// counter and the Done button hang off.
  Future<void> setText(WidgetTester tester, String text) async {
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text = text;
    await tester.pump();
  }

  Finder doneButton() => find.widgetWithText(FilledButton, 'Done');

  bool doneEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(doneButton()).onPressed != null;

  testWidgets('Done returns the edited text', (tester) async {
    final result = await openSheet(tester, initialText: 'Squats');

    await setText(tester, 'Squats\nDeadlifts');
    await tester.tap(doneButton());
    await tester.pumpAndSettle();

    expect(result.value, ['Squats\nDeadlifts']);
  });

  testWidgets('close returns null, discarding the edit', (tester) async {
    final result = await openSheet(tester, initialText: 'Squats');

    await setText(tester, 'Squats\nDeadlifts');
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(result.value, [null]);
  });

  /// The sheet mounts the same wrapper the note editor does, so Tab-indent
  /// and the checkbox toggle came for free — but Enter-continuation lives in
  /// [EditorEditTracker], which the sheet used to skip with an empty
  /// `onTextChanged`, so a list typed here simply stopped at the first Enter.
  group('list continuation', () {
    /// Presses Enter at [offset] on line [index], the way the editor
    /// delivers it: the controller edits and its listeners run.
    Future<CodeLineEditingController> pressEnter(
      WidgetTester tester, {
      required int index,
      required int offset,
    }) async {
      final controller = tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .controller!;
      controller.selection = CodeLineSelection.collapsed(
        index: index,
        offset: offset,
      );
      controller.applyNewLine();
      await tester.pump();
      return controller;
    }

    testWidgets('Enter on a list item carries the marker down', (tester) async {
      await openSheet(tester, initialText: '');
      await setText(tester, '- squat');

      final controller = await pressEnter(tester, index: 0, offset: 7);

      expect(controller.text, '- squat\n- ');
      expect(controller.selection.baseIndex, 1);
      expect(controller.selection.baseOffset, 2);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('Enter on an empty item ends the list', (tester) async {
      await openSheet(tester, initialText: '');
      await setText(tester, '- squat\n- ');

      final controller = await pressEnter(tester, index: 1, offset: 2);

      expect(controller.text, '- squat\n');

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('Done is disabled past the limit and comes back under it', (
    tester,
  ) async {
    await openSheet(tester, initialText: 'ab', limit: 8);

    expect(doneEnabled(tester), isTrue);

    await setText(tester, 'a' * 9);
    expect(
      doneEnabled(tester),
      isFalse,
      reason: 'over budget, and the description is never truncated to fit',
    );
    expect(find.textContaining('over the 8 character limit'), findsOneWidget);

    await setText(tester, 'a' * 8);
    expect(doneEnabled(tester), isTrue);

    // The focused editor keeps a cursor-blink timer running, so the sheet has
    // to be dismissed before the tree is torn down.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'the grandfather rule keeps an already-too-long description confirmable',
    (tester) async {
      // The event was written under a larger budget and the limit was lowered
      // afterwards: editing must stay possible, only growing must not.
      const existing = 'aaaaaaaaaaaa';
      final result = await openSheet(
        tester,
        initialText: existing,
        limit: 4,
        grandfatheredLength: existing.length,
      );

      expect(
        doneEnabled(tester),
        isTrue,
        reason: 'a length the text already had is always confirmable',
      );

      await setText(tester, '${existing}a');
      expect(
        doneEnabled(tester),
        isFalse,
        reason: 'growth past the grandfathered length is what is blocked',
      );

      await setText(tester, existing);
      await tester.tap(doneButton());
      await tester.pumpAndSettle();

      expect(result.value, [existing]);
    },
  );

  testWidgets('cancel is never disabled, even over budget', (tester) async {
    final result = await openSheet(tester, initialText: '', limit: 4);

    await setText(tester, 'a' * 40);
    expect(doneEnabled(tester), isFalse);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(result.value, [
      null,
    ], reason: 'an over-limit sheet must never be a trap');
  });

  testWidgets('crossing the limit does not resize the editor', (tester) async {
    // The status band is height-reserved for two lines precisely so the
    // over-limit explanation can appear without reflowing the text under the
    // caret — the worst possible moment to move it. Tested without a caption,
    // the stricter case: the band goes from holding only the counter to
    // holding a two-line message beside it.
    await openSheet(tester, initialText: 'ab', limit: 8);
    final before = tester.getSize(find.byType(ModernEditorWrapper));

    await setText(tester, 'a' * 60);
    expect(doneEnabled(tester), isFalse);

    expect(
      tester.getSize(find.byType(ModernEditorWrapper)),
      before,
      reason: 'the editor must not shrink when the limit message appears',
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
  });

  testWidgets('the scope caption renders when the caller passes one', (
    tester,
  ) async {
    await openSheet(
      tester,
      initialText: 'Squats',
      scopeCaption: 'Applies to every occurrence',
    );

    expect(find.text('Applies to every occurrence'), findsOneWidget);
  });

  testWidgets('the event name sits above the label, not beside it', (
    tester,
  ) async {
    // Stacked rather than a `title · Description` breadcrumb: on a phone the
    // header has ~180dp between the close icon and Done, and a one-line
    // breadcrumb ellipsises away the half naming the sheet.
    await openSheet(tester, initialText: '', heading: 'Leg day');

    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
  });

  testWidgets('a long event name never truncates the label', (tester) async {
    await openSheet(
      tester,
      initialText: '',
      heading: 'Chest and triceps, heavy week, deload after this one',
    );

    expect(find.text('Description'), findsOneWidget);
  });

  testWidgets('an untitled event shows the label alone', (tester) async {
    await openSheet(tester, initialText: '', heading: '');
    expect(find.text('Description'), findsOneWidget);
  });
}
