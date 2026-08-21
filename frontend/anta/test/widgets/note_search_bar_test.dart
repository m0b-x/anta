import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/note_match_list_sheet.dart';
import 'package:anta/widgets/note_search_bar.dart';

import '../database/support/db_test_support.dart';

const _note = '''
warmup squat 2x5
bench 3x5
back squat 3x8
row 3x10
front squat 5x3
''';

Future<void> _bootSettings() async {
  DatabaseLifecycle.notifyDatabaseSwitching();
  SettingsService.reset();
  SettingsService.forTesting(await openTestDatabase());
}

Widget _wrap(ReEditorSearchController controller, {List<int>? navigated}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: NoteSearchBar(
        searchController: controller,
        onNavigateToMatch: (offset) => navigated?.add(offset),
      ),
    ),
  );
}

/// Preview-mode search: no editor is mounted, so the controller matches
/// against the pushed content and the bar drives it directly.
ReEditorSearchController _searchFor(String query) {
  return ReEditorSearchController()
    ..openSearch()
    ..updateContent(_note)
    ..searchImmediate(query);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_bootSettings);

  testWidgets('counter chip shows the padded position and opens the list', (
    tester,
  ) async {
    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(controller.matchCount, 3);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.text('1/3'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteMatchListSheet), findsOneWidget);
    // One row per match, each labelled with its 1-based line.
    expect(find.text('Line 1'), findsOneWidget);
    expect(find.text('Line 3'), findsOneWidget);
    expect(find.text('Line 5'), findsOneWidget);
  });

  testWidgets('picking a row jumps to that match and reveals it', (
    tester,
  ) async {
    final controller = _searchFor('squat');
    final navigated = <int>[];
    await tester.pumpWidget(_wrap(controller, navigated: navigated));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1/3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line 5'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteMatchListSheet), findsNothing);
    expect(controller.currentMatchIndex, 2);
    expect(find.text('3/3'), findsOneWidget);
    expect(navigated.last, _note.indexOf('squat', _note.indexOf('front')));
  });

  testWidgets('no-match state shows 0 and stays inert', (tester) async {
    final controller = _searchFor('deadlift');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    // The wording is never laid out — it would be wider than the whole
    // stepper in German — but it still reaches a screen reader.
    expect(find.text('No results found'), findsNothing);
    expect(find.bySemanticsLabel('No results found'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);

    await tester.tap(find.text('0'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteMatchListSheet), findsNothing);
  });

  testWidgets('typing a match number jumps to that match', (tester) async {
    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1/3'));
    await tester.pumpAndSettle();

    final jumpField = find.widgetWithText(TextField, 'Match #');
    expect(jumpField, findsOneWidget);
    expect(find.text('1–3'), findsOneWidget);

    await tester.enterText(jumpField, '3');
    await tester.pumpAndSettle();
    // Typing only previews; the note must not move until submit.
    expect(controller.currentMatchIndex, 0);

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(find.byType(NoteMatchListSheet), findsNothing);
    expect(controller.currentMatchIndex, 2);
    expect(find.text('3/3'), findsOneWidget);
  });

  testWidgets('tapping the go button also submits the jump', (tester) async {
    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1/3'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Match #'), '2');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(NoteMatchListSheet), findsNothing);
    expect(controller.currentMatchIndex, 1);
  });

  testWidgets('an out-of-range match number clamps on submit', (tester) async {
    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1/3'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Match #'), '99');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(controller.currentMatchIndex, 2);
  });

  testWidgets('long-pressing the counter opens the list ready for a number', (
    tester,
  ) async {
    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('1/3'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteMatchListSheet), findsOneWidget);
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Match #'),
    );
    expect(field.autofocus, isTrue);
  });

  testWidgets('the whole bar stays on one row', (tester) async {
    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    // Field, stepper and options share a single row, so the bar is one
    // control tall plus its padding.
    final barHeight = tester.getSize(find.byType(NoteSearchBar)).height;
    expect(barHeight, lessThanOrEqualTo(72));

    final fieldRect = tester.getRect(find.byType(TextField));
    final stepperRect = tester.getRect(find.text('1/3'));
    final optionsRect = tester.getRect(find.byIcon(Icons.tune_rounded));
    expect(fieldRect.center.dy, closeTo(stepperRect.center.dy, 1));
    expect(fieldRect.center.dy, closeTo(optionsRect.center.dy, 1));
  });

  testWidgets('the replace row fits a narrow phone without overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = _searchFor('squat');
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteSearchBar(
            searchController: controller,
            showReplaceField: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find & Replace'));
    await tester.pumpAndSettle();

    // A layout overflow throws here; the field and both buttons must share
    // the row without one starving the others. The buttons carry full-size
    // labels by request, so the floor on the smallest supported phone is
    // tighter than it would otherwise be.
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    final field = tester.getSize(find.byType(TextField).last);
    expect(field.width, greaterThan(100));
  });

  testWidgets('the arrows stay mounted so the cluster never reflows', (
    tester,
  ) async {
    final controller = ReEditorSearchController()
      ..openSearch()
      ..updateContent(_note);
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    IconButton arrow(IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

    // Present but inert with no query — mounting them on the first keystroke
    // would shift every control right of the field.
    expect(arrow(Icons.keyboard_arrow_down_rounded).onPressed, isNull);
    expect(arrow(Icons.keyboard_arrow_up_rounded).onPressed, isNull);
    // The counter is the only thing that appears with the query.
    expect(find.text('1/3'), findsNothing);
    final beforeRect = tester.getRect(
      find.byIcon(Icons.keyboard_arrow_down_rounded),
    );

    await tester.enterText(find.byType(TextField), 'squat');
    // Past both the controller's search debounce and the bar's navigate one.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(arrow(Icons.keyboard_arrow_down_rounded).onPressed, isNotNull);
    expect(arrow(Icons.keyboard_arrow_up_rounded).onPressed, isNotNull);
    expect(find.text('1/3'), findsOneWidget);
    expect(
      tester.getRect(find.byIcon(Icons.keyboard_arrow_down_rounded)),
      beforeRect,
    );
  });

  testWidgets('the query field keeps most of the row on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(411, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = _searchFor('squat');
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    // The counter rides inside the pill, so the field keeps everything the
    // four trailing buttons do not take.
    final pillRect = tester.getRect(find.byType(TextField));
    expect(pillRect.width, greaterThan(200));
    expect(find.text('1/3'), findsOneWidget);

    // It caps the pill: flush with the right edge, full field height.
    final chipRect = tester.getRect(
      find.ancestor(of: find.text('1/3'), matching: find.byType(InkWell)).first,
    );
    expect(chipRect.right, closeTo(pillRect.right, 0.5));
    expect(chipRect.height, closeTo(pillRect.height, 0.5));
  });

  testWidgets('the trailing button clears first, then closes', (tester) async {
    final controller = _searchFor('squat');
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteSearchBar(
            searchController: controller,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // .last targets the trailing button; the in-field clear now shares the
    // close glyph.
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('squat'), findsNothing);
    expect(closed, isFalse);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
