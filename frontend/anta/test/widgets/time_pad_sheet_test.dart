import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/time_pad_sheet.dart';

import '../database/support/db_test_support.dart';

/// Every typing rule lives in the pure `TimePadEntry`; what these cases pin is
/// the sheet around it — which key pops, what Done and ✕ return, and since
/// the 2026-09-27 Tier 1 pass the sub-sheet chrome they sit in.
void main() {
  late AppDatabase db;

  setUp(() async {
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Future<_Result> open(
    WidgetTester tester, {
    int initialMinute = 9 * 60,
    bool use24h = true,
    TimePadCaption? caption,
    int? periodAfter,
    String title = 'Start time',
    Locale locale = const Locale('en'),
    Size? size,
    double textScale = 1.0,
  }) async {
    if (size != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
    }
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: use24h,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await TimePadSheet.pick(
                  context,
                  initialMinute: initialMinute,
                  title: title,
                  caption: caption,
                  periodAfter: periodAfter,
                );
                result.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  Future<void> press(WidgetTester tester, String id) async {
    await tester.tap(byId(id));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await press(tester, SemanticsIds.timePadDigit(int.parse(digit)));
    }
  }

  VoidCallback? onPressedOf(WidgetTester tester, String id) => tester
      .widget<FilledButton>(
        find.descendant(of: byId(id), matching: find.byType(FilledButton)),
      )
      .onPressed;

  testWidgets('the last minute digit closes the sheet with the time', (
    tester,
  ) async {
    final result = await open(tester);

    await type(tester, '1830');
    await tester.pumpAndSettle();

    expect(result.closed, isTrue);
    expect(result.value, 18 * 60 + 30);
    expect(find.byType(TimePadSheet), findsNothing);
  });

  testWidgets('a lone hour digit that cannot grow moves to the minutes', (
    tester,
  ) async {
    final result = await open(tester);

    await type(tester, '930');
    await tester.pumpAndSettle();

    expect(result.value, 9 * 60 + 30);
  });

  testWidgets(':30 finishes on the hour already there', (tester) async {
    final result = await open(tester, initialMinute: 9 * 60);

    await press(tester, SemanticsIds.timePadHalfPast);
    await tester.pumpAndSettle();

    expect(result.value, 9 * 60 + 30);
  });

  testWidgets('Done keeps the minutes nobody typed', (tester) async {
    final result = await open(tester, initialMinute: 9 * 60 + 15);

    await type(tester, '18');
    expect(result.closed, isFalse);
    await press(tester, SemanticsIds.timePadDone);
    await tester.pumpAndSettle();

    expect(result.value, 18 * 60 + 15);
  });

  testWidgets('keys that cannot make a time are switched off', (tester) async {
    await open(tester);

    await type(tester, '2');

    expect(onPressedOf(tester, SemanticsIds.timePadDigit(3)), isNotNull);
    expect(onPressedOf(tester, SemanticsIds.timePadDigit(5)), isNotNull);
    expect(onPressedOf(tester, SemanticsIds.timePadDigit(6)), isNull);
    expect(onPressedOf(tester, SemanticsIds.timePadDigit(9)), isNull);
  });

  testWidgets('backspace steps back into the typed hour', (tester) async {
    await open(tester);

    await type(tester, '18');
    await press(tester, SemanticsIds.timePadBackspace);

    expect(
      find.descendant(
        of: byId(SemanticsIds.timePadHour),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a 12-hour time waits for AM or PM, which finishes it', (
    tester,
  ) async {
    final result = await open(tester, use24h: false);

    await type(tester, '130');
    await tester.pumpAndSettle();
    expect(result.closed, isFalse);
    expect(find.text('AM or PM?'), findsOneWidget);

    await press(tester, SemanticsIds.timePadPm);
    await tester.pumpAndSettle();

    expect(result.value, 13 * 60 + 30);
  });

  testWidgets('the caption follows the typing, in the pad\'s own format', (
    tester,
  ) async {
    await open(
      tester,
      caption: (minute, formatTime) => 'at ${formatTime(minute)}',
    );
    expect(find.text('at 09:00'), findsOneWidget);

    await type(tester, '18');

    expect(find.text('at 18:00'), findsOneWidget);
  });

  testWidgets('a hardware keyboard types into the pad', (tester) async {
    final result = await open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pumpAndSettle();

    expect(result.value, 7 * 60 + 45);
  });

  testWidgets('cancel reports nothing', (tester) async {
    final result = await open(tester);

    await type(tester, '18');
    await press(tester, SemanticsIds.timePadCancel);
    await tester.pumpAndSettle();

    expect(result.closed, isTrue);
    expect(result.value, isNull);
  });

  testWidgets("Done is the header's text button and waits for an hour it "
      'can commit', (tester) async {
    // 12-hour mode: a lone "0" can never be an hour there, which is the one
    // state the pad refuses to finish from.
    final result = await open(tester, use24h: false);

    expect(find.byType(FormSheetHeader), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    expect(
      find.ancestor(
        of: byId(SemanticsIds.timePadDone),
        matching: find.byType(FormHeaderTextButton),
      ),
      findsOneWidget,
    );
    TextButton done() => tester.widget<TextButton>(
      find.descendant(
        of: byId(SemanticsIds.timePadDone),
        matching: find.byType(TextButton),
      ),
    );
    expect(done().onPressed, isNotNull);

    // Disabled, never hidden, while the hour cannot be committed.
    await type(tester, '0');
    expect(done().onPressed, isNull);
    expect(result.closed, isFalse);

    await type(tester, '7');
    expect(done().onPressed, isNotNull);
    await press(tester, SemanticsIds.timePadDone);
    await tester.pumpAndSettle();
    expect(result.value, 7 * 60);
  });

  testWidgets("the title is its own node, not the pad's focus root", (
    tester,
  ) async {
    // The root `Focus` used to carry a focusable node of its own, which
    // merged the header's title into it: the device read one focusable
    // "Start time" node and the title had no node of its own to be found by.
    await open(tester);

    final title = tester.getSemantics(find.text('Start time'));
    expect(title.label, 'Start time');
    expect(title.getSemanticsData().flagsCollection.isFocused, Tristate.none);
  });

  testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
      'overflows, the caption wraps whole and the keypad stays whole', (
    tester,
  ) async {
    final result = await open(
      tester,
      title: 'Startzeit',
      caption: TimePadCaptions.endsAfter(
        lookupAppLocalizations(const Locale('de')),
        90,
      ),
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Startzeit'), findsOneWidget);
    expect(find.text('Fertig'), findsOneWidget);
    expect(find.byTooltip('Abbrechen'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FormSheetHeader)).height,
      FormMetrics.headerHeight,
    );
    // "Endet um 10:30 · 1 Std. 30 Min." needs a second line at this scale
    // and the band holds two: exactly two lines of `bodyMedium` as the
    // scaler draws them, with the caption inside it. (The wrap itself is
    // pinned on a wider surface — the test font's em-square glyphs are twice
    // Roboto's width, so here it would need a third line the phone never
    // does.)
    final caption = find.text('Endet um 10:30 · 1 Std. 30 Min.');
    expect(caption, findsOneWidget);
    expect(
      tester.widget<Text>(caption).maxLines,
      FormMetrics.timePadCaptionLines,
    );
    final band = tester.getRect(
      find.ancestor(of: caption, matching: find.byType(SizedBox)).first,
    );
    final line = TextPainter(
      text: TextSpan(
        text: ' ',
        style: Theme.of(tester.element(caption)).textTheme.bodyMedium,
      ),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(2.0),
    );
    expect(band.height, closeTo(2 * line.preferredLineHeight, 0.01));
    line.dispose();
    expect(tester.getRect(caption).top, greaterThanOrEqualTo(band.top));
    expect(tester.getRect(caption).bottom, lessThanOrEqualTo(band.bottom));
    // The keypad's own 1.4 clamp keeps every key on screen; the bottom row
    // is reachable without scrolling.
    expect(
      tester.getRect(byId(SemanticsIds.timePadHalfPast)).bottom,
      lessThanOrEqualTo(780),
    );

    await type(tester, '1830');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result.value, 18 * 60 + 30);
  });

  testWidgets('at text scale 2.0 a caption that needs two lines gets them '
      'whole', (tester) async {
    // 600 dp wide: two lines in the test font too, so the band's second
    // line can be seen holding the tail that a one-line band cut to "Mi…".
    await open(
      tester,
      title: 'Startzeit',
      caption: TimePadCaptions.endsAfter(
        lookupAppLocalizations(const Locale('de')),
        90,
      ),
      locale: const Locale('de'),
      size: const Size(600, 1000),
      textScale: 2.0,
    );

    final caption = find.text('Endet um 10:30 · 1 Std. 30 Min.');
    final paragraph = tester.renderObject<RenderParagraph>(caption);
    expect(paragraph.didExceedMaxLines, isFalse);
    final replica = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
      maxLines: FormMetrics.timePadCaptionLines,
    )..layout(maxWidth: paragraph.size.width);
    expect(replica.computeLineMetrics().length, 2);
    replica.dispose();
  });

  group('captions', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    String format(int minute) {
      final wrapped = minute % (24 * 60);
      return '${(wrapped ~/ 60).toString().padLeft(2, '0')}:'
          '${(wrapped % 60).toString().padLeft(2, '0')}';
    }

    test('a start names where the end lands and how long it is', () {
      final caption = TimePadCaptions.endsAfter(l10n, 90);
      expect(caption(18 * 60, format), 'Ends 19:30 · 1 h 30 min');
      expect(caption(23 * 60, format), 'Ends 00:30 next day · 1 h 30 min');
    });

    test('an end names its length after the start', () {
      final caption = TimePadCaptions.afterStart(l10n, 17 * 60 + 30);
      expect(caption(19 * 60 + 45, format), '2 h 15 min after 17:30');
      expect(caption(17 * 60 + 45, format), '15 min after 17:30');
      expect(caption(60, format), '7 h 30 min after 17:30 · Ends next day');
    });
  });
}

class _Result {
  int? value;
  bool closed = false;
}
