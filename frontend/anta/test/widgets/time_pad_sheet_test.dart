import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/time_pad_sheet.dart';

import '../database/support/db_test_support.dart';

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
  }) async {
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24h),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await TimePadSheet.pick(
                  context,
                  initialMinute: initialMinute,
                  title: 'Start time',
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
