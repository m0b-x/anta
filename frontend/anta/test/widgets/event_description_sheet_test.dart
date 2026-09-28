import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
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
///
/// Since the 2026-09-27 Tier 1 pass the sheet is a form sheet with the
/// editor's leave guard: every exit but Done asks once the text differs from
/// what the sheet opened with, and leaves silently otherwise.
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

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  /// Opens the sheet over a trivial host page and records what it returns.
  /// `result.value` stays absent until the sheet actually pops.
  Future<({List<String?> value})> openSheet(
    WidgetTester tester, {
    required String initialText,
    String heading = 'Leg day',
    int limit = 2000,
    int? grandfatheredLength,
    String? scopeCaption,
    Locale locale = const Locale('en'),
    Size? size,
    double textScale = 1.0,
  }) async {
    if (size != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
    }
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
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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

  CodeLineEditingController controllerOf(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;

  Finder doneButton() => find.descendant(
    of: byId(SemanticsIds.descriptionDone),
    matching: find.byType(TextButton),
  );

  bool doneEnabled(WidgetTester tester) =>
      tester.widget<TextButton>(doneButton()).onPressed != null;

  final dialog = find.text('Unsaved changes');

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> tapClose(WidgetTester tester) async {
    await tester.tap(byId(SemanticsIds.descriptionClose));
    await tester.pumpAndSettle();
  }

  /// ✕ on a dirty sheet, through the dialog — the way every case that edited
  /// the text has to leave.
  Future<void> closeDiscarding(WidgetTester tester) async {
    await tapClose(tester);
    expect(dialog, findsOneWidget);
    await tapText(tester, 'Discard changes');
    expect(find.byType(EventDescriptionSheet), findsNothing);
  }

  testWidgets('Done returns the edited text and never asks', (tester) async {
    final result = await openSheet(tester, initialText: 'Squats');

    await setText(tester, 'Squats\nDeadlifts');
    await tester.tap(doneButton());
    await tester.pumpAndSettle();

    expect(dialog, findsNothing);
    expect(result.value, ['Squats\nDeadlifts']);
  });

  group('leaving with unsaved changes', () {
    testWidgets('a dirty close asks; Keep editing keeps the sheet and the '
        'text, Discard changes pops null', (tester) async {
      final result = await openSheet(tester, initialText: 'Squats');

      await setText(tester, 'Squats\nDeadlifts');
      await tapClose(tester);

      expect(dialog, findsOneWidget);
      expect(result.value, isEmpty);
      await tapText(tester, 'Keep editing');
      expect(dialog, findsNothing);
      expect(find.byType(EventDescriptionSheet), findsOneWidget);
      expect(controllerOf(tester).text, 'Squats\nDeadlifts');

      await tapClose(tester);
      expect(dialog, findsOneWidget);
      await tapText(tester, 'Discard changes');
      expect(result.value, [null]);
    });

    testWidgets('a clean close pops null without asking', (tester) async {
      final result = await openSheet(tester, initialText: 'Squats');

      await tapClose(tester);

      expect(dialog, findsNothing);
      expect(result.value, [null]);
    });

    testWidgets('typing back to the original is not dirty', (tester) async {
      final result = await openSheet(tester, initialText: 'Squats');

      await setText(tester, 'Squats!');
      await setText(tester, 'Squats');
      await tapClose(tester);

      expect(dialog, findsNothing);
      expect(result.value, [null]);
    });

    testWidgets('the system back gesture asks on a dirty sheet', (
      tester,
    ) async {
      final result = await openSheet(tester, initialText: 'Squats');
      await setText(tester, 'Squats\nDeadlifts');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(result.value, isEmpty);
      await tapText(tester, 'Discard changes');
      expect(result.value, [null]);
    });

    testWidgets('the system back gesture pops a clean sheet silently', (
      tester,
    ) async {
      final result = await openSheet(tester, initialText: 'Squats');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(result.value, [null]);
    });

    testWidgets('the barrier asks on a dirty sheet', (tester) async {
      final result = await openSheet(tester, initialText: 'Squats');
      await setText(tester, 'Squats\nDeadlifts');

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(result.value, isEmpty);
      await tapText(tester, 'Keep editing');
      expect(find.byType(EventDescriptionSheet), findsOneWidget);

      await closeDiscarding(tester);
      expect(result.value, [null]);
    });

    testWidgets('the barrier pops a clean sheet silently', (tester) async {
      final result = await openSheet(tester, initialText: 'Squats');

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(result.value, [null]);
    });

    testWidgets('a downward fling on the handle pops a clean sheet', (
      tester,
    ) async {
      final result = await openSheet(tester, initialText: 'Squats');

      await tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      );
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(result.value, [null]);
    });

    testWidgets('a downward fling on the handle asks on a dirty sheet', (
      tester,
    ) async {
      final result = await openSheet(tester, initialText: 'Squats');
      await setText(tester, 'Squats\nDeadlifts');

      await tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      );
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(result.value, isEmpty);
      await tapText(tester, 'Discard changes');
      expect(result.value, [null]);
    });
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
      final controller = controllerOf(tester);
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

      await closeDiscarding(tester);
    });

    testWidgets('Enter on an empty item ends the list', (tester) async {
      await openSheet(tester, initialText: '');
      await setText(tester, '- squat\n- ');

      final controller = await pressEnter(tester, index: 1, offset: 2);

      expect(controller.text, '- squat\n');

      await closeDiscarding(tester);
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
    await closeDiscarding(tester);
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

    // Over budget the only way out is to leave: ✕ still works, through the
    // guard like any other dirty exit.
    await closeDiscarding(tester);

    expect(result.value, [
      null,
    ], reason: 'an over-limit sheet must never be a trap');
  });

  testWidgets('crossing the limit does not resize the editor', (tester) async {
    // The status band is height-reserved precisely so the over-limit
    // explanation can appear without reflowing the text under the caret — the
    // worst possible moment to move it. Tested without a caption, the stricter
    // case: the band goes from holding the subject and the counter to holding
    // a two-line message beside them.
    await openSheet(tester, initialText: 'ab', limit: 8);
    final before = tester.getSize(find.byType(ModernEditorWrapper));

    await setText(tester, 'a' * 60);
    expect(doneEnabled(tester), isFalse);

    expect(
      tester.getSize(find.byType(ModernEditorWrapper)),
      before,
      reason: 'the editor must not shrink when the limit message appears',
    );

    await closeDiscarding(tester);
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

  testWidgets('the event name sits in the band below the header, never '
      'beside the title', (tester) async {
    // A line of its own under the header rather than a `title · Description`
    // breadcrumb: on a phone the header has ~180dp between the close icon
    // and Done, and a one-line breadcrumb ellipsises away the half naming
    // the sheet.
    await openSheet(tester, initialText: '', heading: 'Leg day');

    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FormSheetHeader),
        matching: find.text('Description'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FormSheetHeader),
        matching: find.text('Leg day'),
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('Leg day')).dy,
      greaterThan(tester.getBottomLeft(find.text('Description')).dy),
    );
    expect(
      tester.getBottomLeft(find.text('Leg day')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(ModernEditorWrapper)).dy),
    );
  });

  testWidgets('a long event name never truncates the title', (tester) async {
    await openSheet(
      tester,
      initialText: '',
      heading: 'Chest and triceps, heavy week, deload after this one',
    );

    final title = find.descendant(
      of: find.byType(FormSheetHeader),
      matching: find.text('Description'),
    );
    expect(title, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(title);
    final unconstrained = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    expect(
      unconstrained.width,
      lessThanOrEqualTo(paragraph.size.width),
      reason: 'the title was squeezed by the event name',
    );
    // The name is the line that gives way.
    expect(
      tester
          .widget<Text>(
            find.text('Chest and triceps, heavy week, deload after this one'),
          )
          .maxLines,
      1,
    );
  });

  testWidgets('an untitled event shows the title alone', (tester) async {
    await openSheet(tester, initialText: '', heading: '');
    expect(find.text('Description'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data?.isEmpty ?? false)),
      findsNothing,
      reason: 'no empty subject line is reserved for a missing name',
    );
  });

  testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
      'overflows and the band keeps the editor still', (tester) async {
    await openSheet(
      tester,
      initialText: 'ab',
      heading: 'Beintag',
      limit: 8,
      scopeCaption: 'Gilt für jeden Termin',
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Beschreibung'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
    expect(find.byTooltip('Abbrechen'), findsOneWidget);
    expect(find.text('Beintag'), findsOneWidget);
    expect(find.text('Gilt für jeden Termin'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FormSheetHeader)).height,
      FormMetrics.headerHeight,
    );
    final before = tester.getRect(find.byType(ModernEditorWrapper));

    // Over the limit the message is the band's only text (D23): two lines
    // where the subject and the caption were, so the editor does not move.
    await setText(tester, 'a' * 20);
    expect(tester.takeException(), isNull);
    expect(doneEnabled(tester), isFalse);
    expect(tester.getRect(find.byType(ModernEditorWrapper)), before);
    expect(find.text('Beintag'), findsNothing);
    expect(find.text('Gilt für jeden Termin'), findsNothing);
    final message = find.textContaining('überschreitet das Limit von 8');
    expect(message, findsOneWidget);
    expect(tester.widget<Text>(message).maxLines, 2);
    final paragraph = tester.renderObject<RenderParagraph>(message);
    final replica = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
      maxLines: 2,
    )..layout(maxWidth: paragraph.size.width);
    expect(replica.computeLineMetrics().length, 2);
    replica.dispose();

    // Back under the limit the subject and the caption return, still
    // without moving the editor.
    await setText(tester, 'abc');
    expect(find.text('Beintag'), findsOneWidget);
    expect(find.text('Gilt für jeden Termin'), findsOneWidget);
    expect(message, findsNothing);
    expect(tester.getRect(find.byType(ModernEditorWrapper)), before);

    await tapClose(tester);
    expect(find.text('Ungespeicherte Änderungen'), findsOneWidget);
    await tapText(tester, 'Änderungen verwerfen');
    expect(find.byType(EventDescriptionSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the band reserves two lines for a subject alone and three '
      'with a scope caption', (tester) async {
    // D23: the reservation comes from the sheet's static inputs — a line
    // for the subject and two for the caption while both exist, else two
    // (the over-limit message's). Reserving a third line for a subject
    // without a caption left two empty lines above the event name.
    Finder bandOf(String subject) => find
        .ancestor(of: find.text(subject), matching: find.byType(ConstrainedBox))
        .first;
    double lineAt(Finder text) {
      final style = Theme.of(tester.element(text)).textTheme.bodySmall!;
      return style.fontSize! * FormMetrics.statusLineFactor;
    }

    await openSheet(tester, initialText: '', heading: 'Leg day');
    final subject = find.text('Leg day');
    final band = tester.getRect(bandOf('Leg day'));
    expect(band.height, closeTo(2 * lineAt(subject), 0.01));
    // The band is the header's neighbour, and the subject sits inside it.
    expect(band.top, tester.getRect(find.byType(FormSheetHeader)).bottom);
    expect(tester.getRect(subject).top, greaterThanOrEqualTo(band.top));
    expect(tester.getRect(subject).bottom, lessThanOrEqualTo(band.bottom));
    await tapClose(tester);
    expect(find.byType(EventDescriptionSheet), findsNothing);

    await openSheet(
      tester,
      initialText: '',
      heading: 'Leg day',
      scopeCaption: 'Applies to every occurrence',
    );
    expect(
      tester.getRect(bandOf('Leg day')).height,
      closeTo(3 * lineAt(find.text('Leg day')), 0.01),
    );
    expect(
      tester.getRect(find.text('Applies to every occurrence')).bottom,
      lessThanOrEqualTo(tester.getRect(bandOf('Leg day')).bottom),
    );
  });

  testWidgets("the header's title is a text node of its own, never a "
      'scrollable', (tester) async {
    // The frame's drag surface is a gesture detector with vertical-drag
    // callbacks; exposed to semantics it announced them as scroll actions
    // and folded the title into a `Scroll "Description"` node.
    await openSheet(tester, initialText: '');

    final title = tester.getSemantics(
      find.descendant(
        of: find.byType(FormSheetHeader),
        matching: find.text('Description'),
      ),
    );
    final data = title.getSemanticsData();
    expect(data.label, 'Description');
    expect(data.hasAction(SemanticsAction.scrollUp), isFalse);
    expect(data.hasAction(SemanticsAction.scrollDown), isFalse);
  });
}
