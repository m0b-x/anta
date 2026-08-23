import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/agenda_day_list_sheet.dart';

/// The sheet is deliberately dumb — it reads no facade and localizes nothing —
/// so what is worth pinning is exactly that contract: it draws what it was
/// handed, in order, and hands back the day that was tapped.
void main() {
  final entries = [
    AgendaDayListEntry(
      day: DateTime.utc(2026, 8, 15),
      icon: Icons.celebration_rounded,
      color: const Color(0xFFFFB300),
      title: 'Assumption of Mary',
      subtitle: 'Saturday, August 15',
    ),
    AgendaDayListEntry(
      day: DateTime.utc(2026, 12, 25),
      icon: Icons.celebration_rounded,
      color: const Color(0xFFFFB300),
      title: 'Christmas Day',
      subtitle: 'Friday, December 25',
    ),
  ];

  final list = AgendaDayList(
    title: 'Holidays',
    subtitle: '2 holidays · Aug 15 – Dec 25',
    entries: entries,
  );

  /// Opens the sheet the way the agenda does and captures its result.
  Future<_Picked> openSheet(WidgetTester tester, AgendaDayList list) async {
    final picked = _Picked();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked.result = await AgendaDayListSheet.show(
                  context,
                  list,
                  editTooltip: 'Edit event',
                );
                picked.returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('the header repeats the card that opened it', (tester) async {
    await openSheet(tester, list);

    // Same title and same subtitle as the card, so the count the user tapped
    // is the count they are now looking at.
    expect(find.text('Holidays'), findsOneWidget);
    expect(find.text('2 holidays · Aug 15 – Dec 25'), findsOneWidget);
  });

  testWidgets('every entry is drawn, title and subtitle', (tester) async {
    await openSheet(tester, list);

    expect(find.text('Assumption of Mary'), findsOneWidget);
    expect(find.text('Saturday, August 15'), findsOneWidget);
    expect(find.text('Christmas Day'), findsOneWidget);
    expect(find.text('Friday, December 25'), findsOneWidget);
  });

  testWidgets('tapping an entry returns its day', (tester) async {
    final picked = await openSheet(tester, list);

    await tester.tap(find.text('Christmas Day'));
    await tester.pumpAndSettle();

    expect(picked.result?.focusDay, DateTime.utc(2026, 12, 25));
  });

  testWidgets('dismissing returns null rather than a day', (tester) async {
    final picked = await openSheet(tester, list);

    // Tapping the scrim is how a user backs out; the caller must be able to
    // tell that apart from a pick, or it would focus a day nobody chose.
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();

    expect(picked.returned, isTrue);
    expect(picked.result, isNull);
  });

  testWidgets('an entry with no subtitle still renders', (tester) async {
    await openSheet(
      tester,
      AgendaDayList(
        title: 'Holidays',
        subtitle: '1 holiday',
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2026, 8, 15),
            icon: Icons.celebration_rounded,
            color: const Color(0xFFFFB300),
            title: 'Assumption of Mary',
          ),
        ],
      ),
    );

    expect(find.text('Assumption of Mary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row without an action carries no trailing widget', (
    tester,
  ) async {
    // Holiday and fasting days have no editor to open, so their rows must not
    // grow an empty action strip.
    await openSheet(tester, list);

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('a row with an action offers it and resolves it', (tester) async {
    // Collapsing the events layer must never put editing further away than it
    // was in the list it replaced.
    var ran = 0;
    final picked = await openSheet(
      tester,
      AgendaDayList(
        title: 'Gym',
        subtitle: '1 event · Aug 15',
        entries: [
          AgendaDayListEntry(
            day: DateTime.utc(2026, 8, 15),
            icon: Icons.fitness_center,
            color: const Color(0xFF1E88E5),
            title: 'Leg day',
            subtitle: 'Saturday, August 15',
            onEdit: () => ran++,
          ),
        ],
      ),
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // The sheet resolves the intent rather than running it, so the caller can
    // open the editor after this sheet is gone instead of stacked on it.
    expect(ran, 0);
    expect(picked.result?.focusDay, isNull);
    expect(picked.result?.edit, isNotNull);

    picked.result!.edit!();
    expect(ran, 1);
  });
}

/// Mutable holder for the sheet's result — it is awaited inside a button
/// callback, so the value arrives after the tap that dismissed the sheet.
class _Picked {
  AgendaDayListResult? result;
  bool returned = false;
}
