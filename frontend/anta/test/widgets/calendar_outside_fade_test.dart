import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart'
    show CalendarFormat, TableCalendar, isSameDay;

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/day_cell_tint.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';

import '../database/support/db_test_support.dart';

/// Outside-month days used to be wrapped in `Opacity` — once in the day cell
/// and once again around its marker strip, so 22-26 offscreen compositing
/// layers per page paint for what is only ever a colour change. The fade now
/// lives in the colours.
///
/// One branch is a deliberate exception: where the chip is opaque the number is
/// painted on top of it, so fading the two independently destroys their
/// contrast and washes the digit out. That branch keeps a single composite
/// layer.
///
/// These assertions pin the three things that could silently break: that an
/// inside cell is never faded, that the opaque branch keeps its composite, and
/// that `_onAccent` keeps its brightness estimate on the raw accent (fading
/// first inverts the day number on a pale accent).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accent = Color(0xFF1A73E8);
  const paleAccent = Color(0xFFFFF176);
  const wash = Color(0x33FF5722);
  const edge = Color(0x884CAF50);

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox.square(dimension: 60, child: child)),
    ),
  );

  CalendarDayCell cell({
    required bool isOutside,
    bool isSelected = false,
    bool isToday = false,
    Color cellAccent = accent,
  }) => CalendarDayCell(
    day: DateTime.utc(2026, 8, 10),
    isToday: isToday,
    isSelected: isSelected,
    isOutside: isOutside,
    isWeekend: false,
    todayStyle: CalendarTodayStyle.tonal,
    highlightWeekends: false,
    accent: cellAccent,
    tint: const DayCellTint(wash: wash, edge: edge),
  );

  Color textColor(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).style!.color!;

  List<Color> boxColors(WidgetTester tester) => [
    for (final d
        in tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>())
      if (d.color != null) d.color!,
  ];

  testWidgets('an outside cell fades its colours and allocates no Opacity', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: true)));

    expect(find.byType(Opacity), findsNothing);

    final colors = boxColors(tester);
    expect(
      colors.any((c) => (c.a - wash.a * 0.35).abs() < 0.01),
      isTrue,
      reason: 'the tint wash alpha should be multiplied, not replaced',
    );
    // colorScheme.onSurface is opaque, so the faded number lands exactly on
    // the factor.
    expect((textColor(tester).a - 0.35).abs(), lessThan(0.01));
  });

  testWidgets('an inside cell keeps every colour at full strength', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: false, isSelected: true)));

    expect(find.byType(Opacity), findsNothing);

    final colors = boxColors(tester);
    expect(colors.any((c) => c.a == accent.a), isTrue);
    expect(colors.any((c) => c.a == wash.a), isTrue);
    expect(textColor(tester).a, 1.0);
  });

  testWidgets('an opaque chip fades as a composite, not per layer', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: true, isSelected: true)));

    // The number sits on top of the chip. Fading both independently would
    // wash the digit out against its own background, so this one branch keeps
    // a single composite layer — and only this branch.
    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.35);

    final colors = boxColors(tester);
    expect(
      colors.any((c) => c.a == accent.a),
      isTrue,
      reason: 'the chip keeps full alpha; the Opacity layer does the fading',
    );
    expect(
      textColor(tester).a,
      1.0,
      reason: 'number and chip must keep their relative contrast',
    );
    // The wash is outside the chip, so it still fades by colour.
    expect(colors.any((c) => (c.a - wash.a * 0.35).abs() < 0.01), isTrue);
  });

  testWidgets('the edge stripe fades with the rest of the cell', (
    tester,
  ) async {
    await tester.pumpWidget(host(cell(isOutside: true)));

    final decorated = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null)
        .toList();

    expect(
      decorated.any((d) => (d.color!.a - edge.a * 0.35).abs() < 0.01),
      isTrue,
    );
  });

  testWidgets('the number brightness is estimated on the un-faded accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(cell(isOutside: true, isSelected: true, cellAccent: paleAccent)),
    );

    // A pale accent wants black87. Folding the fade in before the estimate
    // would darken the accent past the threshold and flip this to white.
    final color = textColor(tester);
    expect(color.r, Colors.black87.r);
    expect(color.g, Colors.black87.g);
    expect(color.b, Colors.black87.b);
  });

  testWidgets('day bars fade through the opacity parameter', (tester) async {
    const barColor = Color(0xFFE53935);
    await tester.pumpWidget(
      host(
        const CalendarDayBars(
          bars: [
            DayBar(
              key: 'event:x',
              color: barColor,
              priority: 0,
              semanticLabel: 'x',
            ),
          ],
          opacity: 0.35,
        ),
      ),
    );

    expect(find.byType(Opacity), findsNothing);

    final colors = boxColors(tester);
    expect(colors, isNotEmpty);
    expect((colors.first.a - barColor.a * 0.35).abs(), lessThan(0.01));
  });

  testWidgets('day bars default to full strength', (tester) async {
    const barColor = Color(0xFFE53935);
    await tester.pumpWidget(
      host(
        const CalendarDayBars(
          bars: [
            DayBar(
              key: 'event:x',
              color: barColor,
              priority: 0,
              semanticLabel: 'x',
            ),
          ],
        ),
      ),
    );

    expect(boxColors(tester).first.a, barColor.a);
  });

  /// The cases above build the cell with an explicit `isOutside`, so neither
  /// of the page's two derivations is exercised by them. The page derived the
  /// flag twice — `table_calendar` picks `outsideBuilder` on
  /// `day.month != focusedDay.month` alone, with no notion of the format,
  /// while `markerBuilder` gated it on the month format — so in a week row
  /// spanning a month boundary the day's number, chip, tint and stripe faded
  /// while its bars stayed at full strength.
  group('the page\'s own derivation', () {
    late Directory tempDir;
    late CalendarBloc bloc;
    late ImportExportBloc importExportBloc;
    late AppDatabase testDb;

    // A week that spans a month boundary: Monday 2026-08-31 to Sunday
    // 2026-09-06, with the one event of the row on a day of September.
    final focus = DateTime.utc(2026, 8, 31);
    final outsideDay = DateTime.utc(2026, 9, 2);

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_outside_fade');
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

    Future<void> dispatch(CalendarPageEvent event) async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 30));
      bloc.add(event);
      await next;
    }

    setUp(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      testDb = await openTestDatabase();
      SettingsService.forTesting(testDb);

      final service = await CalendarEventService.getInstance();
      await service.tombstoneAll();
      bloc = CalendarBloc(service: service);
      await dispatch(const LoadCalendarEvents());
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'e1',
            title: 'Leg day',
            categoryId: 'gym',
            startDate: outsideDay,
            rule: const OneTimeRecurrence(),
          ),
        ),
      );
      await dispatch(
        SelectCalendarDay(
          day: focus,
          focusedDay: focus,
          source: CalendarSelectionSource.navigation,
        ),
      );

      final noteRepository = NoteRepository(database: testDb);
      importExportBloc = ImportExportBloc(
        service: ImportExportService(
          noteStorage: NoteStorageService(repository: noteRepository),
          folderStorage: FolderStorageService(
            repository: FolderRepository(database: testDb),
          ),
          noteRepository: noteRepository,
        ),
      );
    });

    tearDown(() async {
      await bloc.close();
      await importExportBloc.close();
      SettingsService.reset();
      await testDb.close();
    });

    Future<void> pumpCalendar(WidgetTester tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CalendarBloc>.value(value: bloc),
            BlocProvider<ImportExportBloc>.value(value: importExportBloc),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const CalendarPage(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Rect boxOf(Element element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    /// What [finder] matches on the page the user is looking at, each with the
    /// box it is painted in: the month pager keeps a neighbouring page laid
    /// out beside it, and a boundary day is on both of them — with a different
    /// answer on each, which is the whole point.
    List<(T, Rect)> onScreen<T extends Widget>(
      WidgetTester tester,
      Finder finder,
    ) {
      final grid = tester.getRect(find.byType(TableCalendar<CalendarEvent>));
      return [
        for (final element in finder.evaluate())
          if (grid.contains(boxOf(element).center))
            (element.widget as T, boxOf(element)),
      ];
    }

    (CalendarDayCell, Rect) cellFor(WidgetTester tester, DateTime day) =>
        onScreen<CalendarDayCell>(
          tester,
          find.byWidgetPredicate(
            (w) => w is CalendarDayCell && isSameDay(w.day, day),
          ),
        ).single;

    /// The marker strip of [day]'s own cell — the grid draws one per day with
    /// bars (a holiday has them too), and the pair is what must agree.
    CalendarDayBars barsOf(WidgetTester tester, DateTime day) {
      final (_, cell) = cellFor(tester, day);
      return onScreen<CalendarDayBars>(
        tester,
        find.descendant(
          of: find.byType(TableCalendar<CalendarEvent>),
          matching: find.byType(CalendarDayBars),
        ),
      ).where((bars) => cell.contains(bars.$2.center)).single.$1;
    }

    // The format is picked in `setUp`: a dispatch from a test body would wait
    // on the bloc's real async work inside `FakeAsync`, which never advances.
    group('switched to a single week', () {
      setUp(
        () => dispatch(const ChangeCalendarFormat(format: CalendarFormat.week)),
      );

      testWidgets('nothing fades — the bars included', (tester) async {
        await pumpCalendar(tester);

        expect(cellFor(tester, outsideDay).$1.isOutside, isFalse);
        expect(barsOf(tester, outsideDay).opacity, 1.0);
      });
    });

    testWidgets('in a month grid the cell and its bars fade alike', (
      tester,
    ) async {
      await pumpCalendar(tester);

      expect(cellFor(tester, outsideDay).$1.isOutside, isTrue);
      expect(barsOf(tester, outsideDay).opacity, CalendarDayCell.outsideAlpha);
    });
  });
}
