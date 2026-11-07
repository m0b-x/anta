import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/app_dialogs.dart';

import '../goldens/support/golden_fonts.dart';

/// `AppDialogs.textInput`, the one text prompt: what its callers have always
/// had — a cancel that returns null, Enter and Save returning the text — and
/// what the saved lists' name dialog brought into it (D33 of
/// `docs/calendar-overview-list-roadmap.md`): the suggestion selected whole,
/// a soft warning line per keystroke on the counter's line, Save held while
/// the text is empty, and
/// the ids a device flow taps.
void main() {
  late List<String?> answers;

  Future<void> open(
    WidgetTester tester, {
    String initialValue = 'Suggested name',
    bool selectAll = false,
    bool allowEmpty = true,
    String? Function(String text)? warningFor,
    String? fieldIdentifier,
    String? confirmIdentifier,
    int? maxLength,
  }) async {
    answers = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => answers.add(
                  await AppDialogs.textInput(
                    context,
                    title: 'Name it',
                    labelText: 'Name',
                    initialValue: initialValue,
                    maxLength: maxLength,
                    selectAll: selectAll,
                    allowEmpty: allowEmpty,
                    warningFor: warningFor,
                    fieldIdentifier: fieldIdentifier,
                    confirmIdentifier: confirmIdentifier,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(field()).controller!;

  FilledButton save(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    ),
  );

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  /// [text]'s style as drawn: the ambient default under the widget's own.
  TextStyle resolvedStyle(WidgetTester tester, String text) {
    final finder = inDialog(text);
    return DefaultTextStyle.of(
      tester.element(finder),
    ).style.merge(tester.widget<Text>(finder).style);
  }

  /// The dialog's card, not the route-filling box `AlertDialog` reports.
  double dialogHeight(WidgetTester tester) => tester
      .getSize(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first,
      )
      .height;

  testWidgets('by default the caret ends the text, Save returns it, and '
      'cancel returns null', (tester) async {
    await open(tester);
    expect(
      controllerOf(tester).selection,
      const TextSelection.collapsed(offset: 'Suggested name'.length),
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm), findsOne);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(answers, ['Suggested name']);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, ['Suggested name', null]);
  });

  testWidgets('selectAll opens with the whole suggestion selected, so typing '
      'replaces it', (tester) async {
    await open(tester, selectAll: true);
    expect(
      controllerOf(tester).selection,
      const TextSelection(baseOffset: 0, extentOffset: 'Suggested name'.length),
    );
  });

  testWidgets('without allowEmpty Save and Enter do nothing while the trimmed '
      'text is empty', (tester) async {
    await open(tester, allowEmpty: false);
    expect(save(tester).onPressed, isNotNull);

    await tester.enterText(field(), '   ');
    await tester.pump();
    expect(save(tester).onPressed, isNull);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(answers, isEmpty);

    await tester.enterText(field(), 'Kept');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(answers, ['Kept']);
  });

  testWidgets('warningFor is asked per keystroke and its line, in the error '
      'colour at the counter\'s metrics, never blocks Save', (tester) async {
    const taken = '"Taken" already exists';
    final asked = <String>[];
    await open(
      tester,
      maxLength: 60,
      warningFor: (text) {
        asked.add(text);
        return text == 'Taken' ? taken : null;
      },
    );
    expect(inDialog(taken), findsNothing);

    await tester.enterText(field(), 'Taken');
    await tester.pump();
    expect(asked.last, 'Taken');
    expect(inDialog(taken), findsOneWidget);
    final line = resolvedStyle(tester, taken);
    final counter = resolvedStyle(tester, '5/60');
    expect(line.color, Theme.of(tester.element(field())).colorScheme.error);
    expect(line.fontSize, counter.fontSize);
    expect(line.height, counter.height);
    expect(save(tester).onPressed, isNotNull);

    await tester.enterText(field(), 'Free');
    await tester.pump();
    expect(asked.last, 'Free');
    expect(inDialog(taken), findsNothing);

    await tester.enterText(field(), 'Taken');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(answers, ['Taken']);
  });

  testWidgets('the counter is onSurfaceVariant, never the warning\'s red, '
      'with no warning up', (tester) async {
    for (final warningFor in <String? Function(String)?>[
      null,
      (text) => text == 'Taken' ? 'Already exists' : null,
    ]) {
      await open(tester, maxLength: 60, warningFor: warningFor);
      await tester.enterText(field(), 'Free');
      await tester.pump();
      expect(
        resolvedStyle(tester, '4/60').color,
        Theme.of(tester.element(field())).colorScheme.onSurfaceVariant,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('beside a counter the warning takes the counter\'s line: the '
      'dialog does not grow', (tester) async {
    await open(
      tester,
      maxLength: 60,
      warningFor: (text) => text == 'Taken' ? 'Already exists' : null,
    );
    await tester.enterText(field(), 'Taker');
    await tester.pump();
    final before = dialogHeight(tester);
    final fieldBefore = tester.getSize(field()).height;

    await tester.enterText(field(), 'Taken');
    await tester.pump();

    expect(inDialog('Already exists'), findsOneWidget);
    expect(tester.getSize(field()).height, fieldBefore);
    expect(dialogHeight(tester), before);
  });

  testWidgets('the identifiers land on the field and on Save, replacing the '
      'generic confirm id', (tester) async {
    await open(
      tester,
      fieldIdentifier: SemanticsIds.filterPresetName,
      confirmIdentifier: SemanticsIds.filterPresetNameSave,
    );

    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.filterPresetName),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.filterPresetNameSave),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm), findsNothing);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.filterPresetNameSave),
    );
    await tester.pumpAndSettle();
    expect(answers, ['Suggested name']);
  });

  // Measured with Roboto: the test font's square glyphs are about twice as
  // wide and break words no device breaks.
  group('a confirm at 2.0 in German', () {
    setUpAll(loadGoldenFonts);

    testWidgets('a confirm taller than the screen scrolls at 2.0 in German: '
        'nothing overflows, the whole body is reachable, its title and labels '
        'break no word, and confirm still answers (review D2-1, D3-3)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final de = lookupAppLocalizations(const Locale('de'));
      final body = [
        de.syncMergeConfirmBody,
        de.syncStopConfirmBody,
        de.syncMergeConfirmBody,
      ].join(' ');
      final confirmed = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => confirmed.add(
                    await AppDialogs.confirm(
                      context,
                      title: de.syncMergeConfirmTitle('Telefon'),
                      content: body,
                      confirmText: de.syncMergeConfirmAction,
                      icon: Icons.merge_rounded,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final scrollable = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.getRect(find.text(body)).bottom,
        lessThanOrEqualTo(tester.getRect(scrollable).bottom + 0.5),
      );

      // Medium weight keeps the clamped title above the body (D4-2).
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text(de.syncMergeConfirmTitle('Telefon')),
            )
            .text
            .style
            ?.fontWeight,
        FontWeight.w500,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(body))
            .text
            .style
            ?.fontWeight,
        isNot(FontWeight.w500),
      );

      // The title and the labels clamp their scale: whole, and no word wider
      // than the line it sits on (a narrower line breaks it mid-word).
      for (final text in [
        de.syncMergeConfirmTitle('Telefon'),
        de.syncMergeConfirmAction,
        de.cancel,
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse, reason: text);
        expect(
          paragraph.size.width + 0.5,
          greaterThanOrEqualTo(paragraph.getMinIntrinsicWidth(double.infinity)),
          reason: text,
        );
      }
      final confirm = tester.getRect(
        find.bySemanticsIdentifier(SemanticsIds.sheetConfirm),
      );
      final label = tester.getRect(find.text(de.syncMergeConfirmAction));
      expect(confirm.left, lessThanOrEqualTo(label.left));
      expect(confirm.right, greaterThanOrEqualTo(label.right));

      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
      await tester.pumpAndSettle();
      expect(confirmed, [true]);
    });

    testWidgets('an action dialog — the sync restart prompt — clamps its '
        'title and its button the same way: medium weight, no word broken, '
        'the label inside its button (review RC3c-2)', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final de = lookupAppLocalizations(const Locale('de'));
      var acted = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => AppDialogs.action(
                    context,
                    title: de.restartRequiredTitle,
                    content: de.restartRequiredNewDatabase,
                    actionText: de.exitApp,
                    icon: Icons.restart_alt_rounded,
                    onAction: () => acted++,
                    actionIdentifier: SemanticsIds.sharingSyncRestart,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final title = tester.renderObject<RenderParagraph>(
        find.text(de.restartRequiredTitle),
      );
      expect(title.text.style?.fontWeight, FontWeight.w500);
      for (final paragraph in [
        title,
        tester.renderObject<RenderParagraph>(find.text(de.exitApp)),
      ]) {
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.size.width + 0.5,
          greaterThanOrEqualTo(paragraph.getMinIntrinsicWidth(double.infinity)),
        );
      }
      final button = tester.getRect(
        find.bySemanticsIdentifier(SemanticsIds.sharingSyncRestart),
      );
      final label = tester.getRect(find.text(de.exitApp));
      expect(button.left, lessThanOrEqualTo(label.left));
      expect(button.right, greaterThanOrEqualTo(label.right));

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharingSyncRestart),
      );
      expect(acted, 1);
    });
  });
}
