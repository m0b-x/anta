import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/simple_markdown_preview.dart';

import '../database/support/db_test_support.dart';

class _StubNoteRepository extends NoteRepository {
  _StubNoteRepository({required super.database});

  List<Note> notes = const [];
  Completer<List<Note>>? pending;

  @override
  Future<List<Note>> getNotesByIds(List<String> ids) {
    final hold = pending;
    if (hold != null) return hold.future;
    return Future.value([
      for (final note in notes)
        if (ids.contains(note.id)) note,
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;
  late AppDatabase settingsDb;
  late _StubNoteRepository notes;

  final startDate = DateTime.utc(2026, 9, 25);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_new');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await initializeDateFormatting('en');
    notes = _StubNoteRepository(database: await AppDatabase.getInstance());
    GetIt.I.registerSingleton<NoteRepository>(notes);
  });

  tearDownAll(() async {
    GetIt.I.unregister<NoteRepository>();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    SettingsService.reset();
    settingsDb = await openTestDatabase();
    SettingsService.forTesting(settingsDb);
    notes.notes = const [];
    notes.pending = null;
  });

  tearDown(() async {
    await barBloc.close();
    EventAlerts.resetCache();
    EventSkips.resetCache();
    SettingsService.reset();
    await settingsDb.close();
  });

  void phone(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
  }

  CalendarEvent eventOf({
    RecurrenceRule rule = const OneTimeRecurrence(),
    EventTime? time,
    String? description,
    String? noteId,
    int? colorValue,
    bool tintIcon = true,
    bool retroactive = false,
    DateTime? endDate,
    bool perOccurrenceDescriptions = false,
  }) => CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: startDate,
    rule: rule,
    time: time,
    description: description,
    noteId: noteId,
    colorValue: colorValue,
    tintIcon: tintIcon,
    retroactive: retroactive,
    endDate: endDate,
    perOccurrenceDescriptions: perOccurrenceDescriptions,
  );

  Future<List<EventEditorResult?>> open(
    WidgetTester tester, {
    CalendarEvent? initial,
    DateTime? day,
    String? pendingDay,
    bool showBack = false,
    bool settle = true,
  }) async {
    phone(tester);
    final results = <EventEditorResult?>[];
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          key: UniqueKey(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  results.add(
                    await EventEditorSheet.show(
                      context,
                      defaultDate: startDate,
                      initialEvent: initial,
                      occurrenceDay: day,
                      pendingOccurrenceDescription: pendingDay,
                      showBack: showBack,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return results;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    final target = find.byTooltip(tooltip);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> typeTitle(
    WidgetTester tester, [
    String title = 'Leg day',
  ]) async {
    await tester.enterText(find.byType(TextField).first, title);
    await tester.pumpAndSettle();
  }

  Future<EventEditorSaved> saveAnd(
    WidgetTester tester,
    List<EventEditorResult?> results,
  ) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save').first);
    await tester.pumpAndSettle();
    return results.single as EventEditorSaved;
  }

  Finder row(String label) => find.widgetWithText(FormPickerRow, label);

  FormPickerRow pickerRow(WidgetTester tester, String label) =>
      tester.widget<FormPickerRow>(row(label));

  CodeLineEditingController descriptionOf(WidgetTester tester) =>
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;

  Future<void> pickRepeat(WidgetTester tester, String kind) async {
    await tapText(tester, 'Repeat');
    await tapText(tester, kind);
    await tapText(tester, 'Done');
  }

  final dialog = find.text('Unsaved changes');

  group('capture group', () {
    testWidgets('a new event opens with the title focused, editing does not', (
      tester,
    ) async {
      await open(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isTrue,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    testWidgets('editing never autofocuses the title', (tester) async {
      await open(tester, initial: eventOf());
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isFalse,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isFalse,
      );
    });

    testWidgets('the title counter appears from 100 characters', (
      tester,
    ) async {
      await open(tester);
      await typeTitle(tester, 'a' * 99);
      expect(find.text('99/120'), findsNothing);

      await typeTitle(tester, 'a' * 100);
      expect(find.text('100/120'), findsOneWidget);

      await typeTitle(tester, 'a' * 120);
      final counter = tester.widget<Text>(find.text('120/120'));
      expect(
        counter.style?.color,
        Theme.of(tester.element(find.text('120/120'))).colorScheme.error,
      );
    });

    testWidgets('the title is one field that refuses newlines', (tester) async {
      await open(tester);
      await typeTitle(tester, 'Leg\nday');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Legday',
      );
    });

    testWidgets('the description cell starts at one line and grows to ten', (
      tester,
    ) async {
      await open(tester);
      double editorHeight() => tester.getSize(find.byType(CodeEditor)).height;

      expect(editorHeight(), 22);

      descriptionOf(tester).text = List.filled(12, 'line').join('\n');
      await tester.pump();
      expect(editorHeight(), 220, reason: 'sized in the same frame');

      descriptionOf(tester).text = 'one\ntwo\nthree';
      await tester.pump();
      expect(editorHeight(), 66);
    });

    testWidgets('the placeholder shows only while the description is empty', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Add description'), findsOneWidget);

      descriptionOf(tester).text = 'Heavy week';
      await tester.pump();
      expect(find.text('Add description'), findsNothing);

      descriptionOf(tester).text = '';
      await tester.pump();
      expect(find.text('Add description'), findsOneWidget);
    });

    testWidgets('the look row reads Default or Custom with the event colour', (
      tester,
    ) async {
      await open(tester);
      expect(row('Icon & color'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      final gymColor = tester
          .widget<EventAvatar>(find.byType(EventAvatar))
          .color;
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color == gymColor,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a colour override reads Custom and tints the avatar', (
      tester,
    ) async {
      await open(tester, initial: eventOf(colorValue: 0xFFE53935));
      expect(find.text('Custom'), findsOneWidget);
      expect(
        tester.widget<EventAvatar>(find.byType(EventAvatar)).color,
        const Color(0xFFE53935),
      );
    });

    testWidgets('a colour override with tint off keeps the category avatar', (
      tester,
    ) async {
      await open(
        tester,
        initial: eventOf(colorValue: 0xFFE53935, tintIcon: false),
      );
      expect(find.text('Custom'), findsOneWidget);
      expect(
        tester.widget<EventAvatar>(find.byType(EventAvatar)).color,
        isNot(const Color(0xFFE53935)),
      );
    });
  });

  group('when', () {
    testWidgets('a one-time event with one date has a Date row and Add date', (
      tester,
    ) async {
      await open(tester);
      expect(row('Date'), findsOneWidget);
      expect(find.text('Fri, Sep 25, 2026'), findsOneWidget);
      expect(find.widgetWithText(FormActionRow, 'Add date'), findsOneWidget);
      expect(find.byTooltip('Remove date'), findsNothing);
      expect(find.text('Does not repeat'), findsOneWidget);
    });

    testWidgets('several dates are rows with a remove button each', (
      tester,
    ) async {
      final results = await open(
        tester,
        initial: eventOf(
          rule: SpecificDatesRecurrence(
            dates: {
              startDate,
              DateTime.utc(2026, 10, 2),
              DateTime.utc(2026, 10, 9),
            },
          ),
        ),
      );
      expect(find.byTooltip('Remove date'), findsNWidgets(3));
      expect(row('Fri, Sep 25, 2026'), findsOneWidget);
      expect(row('Fri, Oct 2, 2026'), findsOneWidget);
      expect(row('Fri, Oct 9, 2026'), findsOneWidget);
      expect(find.text('Does not repeat'), findsOneWidget);
      expect(find.text('Track presence'), findsOneWidget);
      expect(find.text('Count occurrences'), findsNothing);

      await tester.tap(find.byTooltip('Remove date').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove date'), findsNWidgets(2));
      expect(row('Fri, Sep 25, 2026'), findsNothing);

      await tester.tap(find.byTooltip('Remove date').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove date'), findsNothing);
      expect(row('Date'), findsOneWidget);
      expect(find.text('Fri, Oct 2, 2026'), findsOneWidget);

      final saved = await saveAnd(tester, results);
      expect(saved.event.rule, isA<OneTimeRecurrence>());
      expect(saved.event.startDate, DateTime.utc(2026, 10, 2));
    });

    testWidgets('from four dates the group bundles them into one row that '
        'opens the month grid', (tester) async {
      final results = await open(
        tester,
        initial: eventOf(
          rule: SpecificDatesRecurrence(
            dates: {
              startDate,
              DateTime.utc(2026, 10, 2),
              DateTime.utc(2026, 10, 9),
              DateTime.utc(2026, 10, 16),
            },
          ),
        ),
      );
      expect(row('Dates'), findsOneWidget);
      expect(find.text('4 dates · Sep 25 – Oct 16, 2026'), findsOneWidget);
      expect(find.byTooltip('Remove date'), findsNothing);
      expect(find.widgetWithText(FormActionRow, 'Add date'), findsOneWidget);

      await tapText(tester, 'Dates');
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CalendarDayCell && w.day == DateTime.utc(2026, 10, 2),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(row('Dates'), findsNothing);
      expect(find.byTooltip('Remove date'), findsNWidgets(3));
      final saved = await saveAnd(tester, results);
      expect((saved.event.rule as SpecificDatesRecurrence).dates, {
        startDate,
        DateTime.utc(2026, 10, 9),
        DateTime.utc(2026, 10, 16),
      });
    });

    testWidgets('the bundled row keeps the group at one height for any count', (
      tester,
    ) async {
      Set<DateTime> series(int count) => {
        for (var i = 0; i < count; i++)
          DateTime.utc(2026, 9, 25).add(Duration(days: i * 3)),
      };
      Finder whenGroup() => find.byType(FormRowGroup).at(1);

      await open(
        tester,
        initial: eventOf(rule: SpecificDatesRecurrence(dates: series(4))),
      );
      final fourDates = tester.getSize(whenGroup()).height;

      await open(
        tester,
        initial: eventOf(rule: SpecificDatesRecurrence(dates: series(300))),
      );
      final last = series(300).reduce((a, b) => a.isAfter(b) ? a : b);
      expect(
        find.text(
          '300 dates · Sep 25, 2026 – ${DateFormat.yMMMd('en').format(last)}',
        ),
        findsOneWidget,
      );
      expect(tester.getSize(whenGroup()).height, fourDates);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a span across years names both years', (tester) async {
      await open(
        tester,
        initial: eventOf(
          rule: SpecificDatesRecurrence(
            dates: {
              DateTime.utc(2026, 12, 30),
              DateTime.utc(2026, 12, 31),
              DateTime.utc(2027, 1, 1),
              DateTime.utc(2027, 1, 2),
            },
          ),
        ).copyWith(startDate: DateTime.utc(2026, 12, 30)),
      );
      expect(find.text('4 dates · Dec 30, 2026 – Jan 2, 2027'), findsOneWidget);
    });

    testWidgets('removing a date keeps the earliest as the anchor', (
      tester,
    ) async {
      final results = await open(
        tester,
        initial: eventOf(
          rule: SpecificDatesRecurrence(
            dates: {startDate, DateTime.utc(2026, 10, 2)},
          ),
        ),
      );
      await tester.tap(find.byTooltip('Remove date').first);
      await tester.pumpAndSettle();
      final saved = await saveAnd(tester, results);
      expect(saved.event.startDate, DateTime.utc(2026, 10, 2));
      expect(saved.event.rule, isA<OneTimeRecurrence>());
    });

    testWidgets('Add date adds a day through the multi picker', (tester) async {
      final results = await open(tester);
      await typeTitle(tester);
      await tapText(tester, 'Add date');

      final target = DateTime.utc(2026, 9, 15);
      await tester.tap(
        find.byWidgetPredicate((w) => w is CalendarDayCell && w.day == target),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Remove date'), findsNWidgets(2));
      final saved = await saveAnd(tester, results);
      expect(saved.event.startDate, target);
      expect((saved.event.rule as SpecificDatesRecurrence).dates, {
        target,
        startDate,
      });
    });

    testWidgets('re-picking the single date re-anchors an implicit weekday', (
      tester,
    ) async {
      final results = await open(tester);
      await typeTitle(tester);
      await pickRepeat(tester, 'Weekly');
      expect(find.text('Weekly · Fri'), findsOneWidget);

      await tapText(tester, 'Start date');
      final target = DateTime.utc(2026, 9, 15);
      await tester.tap(
        find.byWidgetPredicate((w) => w is CalendarDayCell && w.day == target),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weekly · Tue'), findsOneWidget);
      final saved = await saveAnd(tester, results);
      expect((saved.event.rule as WeeklyRecurrence).weekdays, {2});
      expect(saved.event.startDate, target);
    });

    testWidgets('the repeat row reads the rule, its scope and its end', (
      tester,
    ) async {
      await open(
        tester,
        initial: eventOf(
          rule: const WeeklyRecurrence(weekdays: {1, 4}),
          retroactive: true,
          endDate: DateTime.utc(2026, 12, 31),
        ),
      );
      expect(
        find.text('Weekly · Mon, Thu · also before · until Dec 31, 2026'),
        findsOneWidget,
      );
      expect(row('Start date'), findsOneWidget);
    });

    testWidgets('a weekly rule reads its days', (tester) async {
      await open(
        tester,
        initial: eventOf(rule: const WeeklyRecurrence(weekdays: {1, 4})),
      );
      expect(find.text('Weekly · Mon, Thu'), findsOneWidget);
    });

    testWidgets('the repeat sheet applies its draft to the saved rule', (
      tester,
    ) async {
      final results = await open(tester);
      await typeTitle(tester);
      await pickRepeat(tester, 'Monthly');
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Count occurrences'), findsOneWidget);

      final saved = await saveAnd(tester, results);
      expect(saved.event.rule, const MonthlyRecurrence());
    });

    testWidgets('cancelling the repeat sheet changes nothing', (tester) async {
      final results = await open(tester);
      await typeTitle(tester);
      await tapText(tester, 'Repeat');
      await tapText(tester, 'Monthly');
      await tester.tap(
        find.descendant(
          of: find.byType(EventRepeatSheet),
          matching: find.byTooltip('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Does not repeat'), findsOneWidget);
      final saved = await saveAnd(tester, results);
      expect(saved.event.rule, const OneTimeRecurrence());
    });

    testWidgets('a kind change re-resolves the count style until touched', (
      tester,
    ) async {
      await open(tester);
      await typeTitle(tester);
      await pickRepeat(tester, 'Yearly');
      await tapText(tester, 'Count occurrences');
      expect(find.text('0 years · 1 year · 2 years'), findsOneWidget);

      await pickRepeat(tester, 'Weekly');
      expect(find.text('Week 1 · Week 2 · Week 3'), findsOneWidget);

      await tapText(tester, 'Count from 0');
      expect(find.text('0 weeks · 1 week · 2 weeks'), findsOneWidget);

      await pickRepeat(tester, 'Daily');
      expect(find.text('0 days · 1 day · 2 days'), findsOneWidget);
    });

    testWidgets('the end time reads its length, clears with its button and '
        'says when it crosses midnight', (tester) async {
      final results = await open(
        tester,
        initial: eventOf(
          time: const EventTime(startMinute: 23 * 60, durationMinutes: 120),
        ),
      );
      expect(row('Starts'), findsOneWidget);
      expect(find.text('11:00 PM'), findsOneWidget);
      expect(row('Ends next day'), findsOneWidget);
      expect(find.text('1:00 AM · 2 h'), findsOneWidget);

      await tapTooltip(tester, 'Remove end time');
      expect(row('Ends'), findsOneWidget);
      expect(find.text('No end time'), findsOneWidget);
      expect(find.byTooltip('Remove end time'), findsNothing);

      final saved = await saveAnd(tester, results);
      expect(saved.event.time?.durationMinutes, isNull);
    });

    testWidgets('all day hides the time rows', (tester) async {
      await open(
        tester,
        initial: eventOf(time: const EventTime(startMinute: 18 * 60)),
      );
      expect(row('Starts'), findsOneWidget);
      await tapText(tester, 'All day');
      expect(row('Starts'), findsNothing);
      expect(row('Ends'), findsNothing);
    });
  });

  group('occurrences, alerts and details', () {
    testWidgets('the skipped days row reads the count', (tester) async {
      EventSkips.updateCache(
        byEvent: {
          'e1': {DateTime.utc(2026, 9, 26), DateTime.utc(2026, 9, 27)},
        },
      );
      await open(tester, initial: eventOf(rule: const DailyRecurrence()));
      expect(row('Skipped days'), findsOneWidget);
      expect(find.text('2 days skipped'), findsOneWidget);
    });

    testWidgets('a new event has no skipped days row', (tester) async {
      await open(tester);
      await pickRepeat(tester, 'Daily');
      expect(row('Skipped days'), findsNothing);
    });

    testWidgets('the priority menu sets the value', (tester) async {
      final results = await open(tester);
      await typeTitle(tester);
      expect(find.text('Normal'), findsOneWidget);

      await tapText(tester, 'Priority');
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Highest'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Highest'), findsOneWidget);
      expect(find.byType(MenuItemButton), findsNothing);
      final saved = await saveAnd(tester, results);
      expect(saved.event.priority, kMinEventPriority);
    });

    testWidgets('alerts read Reminder or Alarm and remove with their button', (
      tester,
    ) async {
      EventAlerts.updateCache(
        byEvent: {
          'e1': List<EventAlert>.unmodifiable(const [
            EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 30),
            EventAlert(
              id: 'a2',
              eventId: 'e1',
              mode: AlertMode.ring,
              offsetMinutes: 0,
            ),
          ]),
        },
      );
      final results = await open(
        tester,
        initial: eventOf(time: const EventTime(startMinute: 18 * 60)),
      );
      expect(find.text('Reminder'), findsOneWidget);
      expect(find.text('Alarm'), findsOneWidget);
      expect(find.byTooltip('Remove alert'), findsNWidgets(2));
      expect(find.text('Remove after it rings'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove alert').last);
      await tester.pumpAndSettle();
      expect(find.text('Alarm'), findsNothing);
      expect(find.text('Remove after it rings'), findsNothing);

      final saved = await saveAnd(tester, results);
      expect(saved.alerts!.single.id, 'a1');
    });

    testWidgets('a linked note reads None until one is linked', (tester) async {
      await open(tester);
      expect(row('Linked note'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.byTooltip('Remove link'), findsNothing);
    });

    testWidgets('a linked note shows its title and unlinks', (tester) async {
      final now = DateTime.now();
      notes.notes = [
        Note(
          id: 'n1',
          folderId: 'f1',
          title: 'Leg day log',
          preview: '',
          contentLength: 0,
          chunkCount: 0,
          isCompressed: false,
          position: 0,
          label: 0,
          createdAt: now,
          updatedAt: now,
          hlcTimestamp: '',
          deviceId: '',
          version: 1,
          isDeleted: false,
        ),
      ];
      final results = await open(tester, initial: eventOf(noteId: 'n1'));
      expect(find.text('Leg day log'), findsOneWidget);
      expect(find.byTooltip('Remove link'), findsOneWidget);

      await tapTooltip(tester, 'Remove link');
      expect(find.text('None'), findsOneWidget);
      final saved = await saveAnd(tester, results);
      expect(saved.event.noteId, isNull);
    });

    testWidgets('while the title loads the value is empty', (tester) async {
      notes.pending = Completer<List<Note>>();
      await open(tester, initial: eventOf(noteId: 'n1'), settle: false);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Untitled Note'), findsNothing);
      expect(find.text('Not found'), findsNothing);
      expect(find.byTooltip('Remove link'), findsOneWidget);
      expect(pickerRow(tester, 'Linked note').value, '');

      notes.pending!.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('Not found'), findsOneWidget);
    });

    testWidgets('a missing note reads Not found and still unlinks', (
      tester,
    ) async {
      final results = await open(tester, initial: eventOf(noteId: 'gone'));
      expect(find.text('Not found'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        pickerRow(tester, 'Linked note').semanticsLabel,
        'Linked note no longer exists',
      );

      await tapTooltip(tester, 'Remove link');
      expect(find.text('None'), findsOneWidget);
      final saved = await saveAnd(tester, results);
      expect(saved.event.noteId, isNull);
    });

    testWidgets('switching per-day descriptions on while editing a day shows '
        'the scope strip and keeps the description on screen', (tester) async {
      await open(
        tester,
        initial: eventOf(rule: const DailyRecurrence()),
        day: startDate,
      );
      expect(find.text('This day'), findsNothing);

      await tapText(tester, 'Separate description per day');

      expect(find.text('All days'), findsOneWidget);
      expect(find.text('This day'), findsOneWidget);
      final editor = tester.getRect(find.byType(CodeEditor));
      final screen = tester.view.physicalSize.height;
      expect(editor.top, greaterThanOrEqualTo(0));
      expect(editor.bottom, lessThanOrEqualTo(screen));
    });

    testWidgets('Save as template and Delete event are action rows', (
      tester,
    ) async {
      await open(tester, initial: eventOf());
      expect(
        find.widgetWithText(FormActionRow, 'Save as template'),
        findsOneWidget,
      );
      final delete = tester.widget<FormActionRow>(
        find.widgetWithText(FormActionRow, 'Delete event'),
      );
      expect(delete.destructive, isTrue);
    });
  });

  group('layout stress', () {
    testWidgets('at text scale 2.0 nothing overflows and values drop under '
        'their labels', (tester) async {
      phone(tester);
      final results = <EventEditorResult?>[];
      await tester.pumpWidget(
        BlocProvider<MarkdownBarBloc>.value(
          value: barBloc,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    results.add(
                      await EventEditorSheet.show(
                        context,
                        defaultDate: startDate,
                        initialEvent: eventOf(
                          rule: const WeeklyRecurrence(weekdays: {1, 4}),
                          time: const EventTime(
                            startMinute: 18 * 60,
                            durationMinutes: 75,
                          ),
                        ),
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

      expect(tester.takeException(), isNull);
      final repeatValue = pickerRow(tester, 'Wiederholung').value!;
      expect(repeatValue, isNot(isEmpty));
      final label = tester.getRect(find.text('Wiederholung'));
      final value = tester.getRect(find.text(repeatValue));
      expect(value.top, greaterThanOrEqualTo(label.bottom - 1));
      expect(value.left, label.left);
      await tester.scrollUntilVisible(
        find.text('Ereignis löschen'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a 360 × 780 phone everything through Priority is above '
        'the fold', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 780);
      final results = <EventEditorResult?>[];
      await tester.pumpWidget(
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
                    results.add(
                      await EventEditorSheet.show(
                        context,
                        defaultDate: startDate,
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

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('Priority')).bottom, lessThan(780));
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Save')).bottom,
        lessThan(780 * 0.08 + 48 + 22 + 8),
      );
    });
  });

  group('review follow-ups', () {
    testWidgets('the capture group hairlines start at 70, 52 and 16', (
      tester,
    ) async {
      await open(tester);
      final group = find.byType(FormRowGroup).first;
      final dividers = tester
          .widgetList<Divider>(
            find.descendant(of: group, matching: find.byType(Divider)),
          )
          .map((d) => d.indent)
          .toList();
      expect(dividers, [70, 52, 16]);
    });

    testWidgets('a chip toggles from the top edge of its 48 dp target', (
      tester,
    ) async {
      await open(tester);
      await typeTitle(tester);
      await pickRepeat(tester, 'Yearly');
      await tapText(tester, 'Count occurrences');
      final chip = find.widgetWithText(FormChip, 'Count from 1');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      final rect = tester.getRect(chip);
      expect(rect.height, 48);
      await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
      await tester.pumpAndSettle();
      expect(tester.widget<FormChip>(chip).selected, isTrue);
      expect(find.text('Year 1 · Year 2 · Year 3'), findsOneWidget);
    });

    testWidgets('the description counter shows from 90 % of the limit, the '
        'error line and a disabled Save past it, and a grandfathered length '
        'still saves', (tester) async {
      await (await SettingsService.getInstance()).setEventDescriptionLimit(500);
      final results = await open(
        tester,
        initial: eventOf(description: 'x' * 520),
      );
      expect(find.text('520 / 500'), findsOneWidget);
      expect(
        find.textContaining('over the 500 character limit'),
        findsNothing,
        reason: 'a length the event already had is grandfathered',
      );
      FilledButton save() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save().onPressed, isNotNull);

      descriptionOf(tester).text = 'x' * 521;
      await tester.pump();
      expect(find.text('521 / 500'), findsOneWidget);
      expect(
        find.textContaining('over the 500 character limit'),
        findsOneWidget,
      );
      expect(save().onPressed, isNull);

      descriptionOf(tester).text = 'x' * 449;
      await tester.pump();
      expect(find.text('449 / 500'), findsNothing);
      descriptionOf(tester).text = 'x' * 450;
      await tester.pump();
      expect(find.text('450 / 500'), findsOneWidget);
      expect(save().onPressed, isNotNull);

      final saved = await saveAnd(tester, results);
      expect(saved.event.description, 'x' * 450);
    });

    testWidgets('Reset day tombstones a materialised day', (tester) async {
      final results = await open(
        tester,
        initial: eventOf(
          rule: const DailyRecurrence(),
          description: 'template',
          perOccurrenceDescriptions: true,
        ),
        day: startDate,
        pendingDay: 'own text',
      );
      expect(find.text('This day'), findsOneWidget);
      expect(find.text('Reset day'), findsOneWidget);
      expect(descriptionOf(tester).text, 'own text');

      await tapText(tester, 'Reset day');
      expect(find.text('Reset day'), findsNothing);
      expect(descriptionOf(tester).text, 'template');

      final saved = await saveAnd(tester, results);
      expect(saved.occurrenceDay, startDate);
      expect(saved.occurrenceDescription, isNull);
    });

    testWidgets('the full editor opens on the description and folds back', (
      tester,
    ) async {
      final results = await open(tester, initial: eventOf(description: 'one'));
      await tapTooltip(tester, 'Open full editor');
      expect(find.byType(EventDescriptionSheet), findsOneWidget);
      final full = tester
          .widget<CodeEditor>(
            find.descendant(
              of: find.byType(EventDescriptionSheet),
              matching: find.byType(CodeEditor),
            ),
          )
          .controller!;
      expect(full.text, 'one');
      full.text = 'one\ntwo';
      await tester.pump();
      await tapText(tester, 'Done');
      expect(find.byType(EventDescriptionSheet), findsNothing);
      expect(descriptionOf(tester).text, 'one\ntwo');
      final saved = await saveAnd(tester, results);
      expect(saved.event.description, 'one\ntwo');
    });

    testWidgets(
      'with live rendering off the preview toggle swaps the surface',
      (tester) async {
        await (await SettingsService.getInstance()).setLiveMarkdownRendering(
          false,
        );
        await open(tester, initial: eventOf(description: '# Plan'));
        expect(find.byTooltip('Show rendered description'), findsOneWidget);
        await tapTooltip(tester, 'Show rendered description');
        expect(find.byType(CodeEditor), findsNothing);
        expect(find.byType(SimpleMarkdownPreview), findsOneWidget);
        expect(find.byTooltip('Edit description'), findsOneWidget);
        await tapTooltip(tester, 'Edit description');
        expect(find.byType(CodeEditor), findsOneWidget);
      },
    );

    testWidgets('the birthday category pre-fills a yearly counted rule', (
      tester,
    ) async {
      CalendarCategories.updateCache([
        for (final (i, seed) in CalendarCategories.builtInSeeds.indexed)
          CalendarCategory(
            id: seed.id,
            name: seed.id,
            colorValue: seed.colorValue,
            iconKey: seed.iconKey,
            sortOrder: i,
            isBuiltIn: true,
          ),
      ]);
      addTearDown(() => CalendarCategories.updateCache(const []));
      final results = await open(tester);
      await typeTitle(tester, 'Mum');
      await tapText(tester, 'Category');
      await tapText(tester, 'Birthday');
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text('0 years · 1 year · 2 years'), findsOneWidget);
      final saved = await saveAnd(tester, results);
      expect(saved.event.rule, const YearlyRecurrence());
      expect(saved.event.countOccurrences, isTrue);
      expect(saved.event.countStyle, OccurrenceCountStyle.elapsed);
    });

    testWidgets('the Icon & color sheet writes back into the saved event', (
      tester,
    ) async {
      final results = await open(
        tester,
        initial: eventOf(colorValue: 0xFFE53935).copyWith(iconKey: 'cake'),
      );
      expect(find.text('Custom'), findsOneWidget);
      await tapText(tester, 'Icon & color');
      await tapTooltip(tester, 'Reset to Default');
      await tapText(tester, 'Tint icon with color');
      await tapText(tester, 'Done');
      expect(find.text('Custom'), findsOneWidget);

      final saved = await saveAnd(tester, results);
      expect(saved.event.iconKey, isNull);
      expect(saved.event.colorValue, 0xFFE53935);
      expect(saved.event.tintIcon, isFalse);
    });

    testWidgets('the Repeat sheet carries the end date and also-before into '
        'the saved event', (tester) async {
      final results = await open(
        tester,
        initial: eventOf(
          rule: const DailyRecurrence(),
          endDate: DateTime.utc(2026, 12, 31),
        ),
      );
      expect(find.text('Daily · until Dec 31, 2026'), findsOneWidget);
      await tapText(tester, 'Repeat');
      await tester.tap(find.text('Also before the start date').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove end date').hitTestable());
      await tester.pumpAndSettle();
      await tapText(tester, 'Done');
      expect(find.text('Daily · also before'), findsOneWidget);

      final saved = await saveAnd(tester, results);
      expect(saved.event.retroactive, isTrue);
      expect(saved.event.endDate, isNull);
    });
  });

  group('focus and scroll', () {
    testWidgets('adding an alert keeps the scroll position and does not '
        'hand focus back to the title', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 640);
      final results = <EventEditorResult?>[];
      await tester.pumpWidget(
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
                    results.add(
                      await EventEditorSheet.show(
                        context,
                        defaultDate: startDate,
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
      final title = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(title.focusNode.hasFocus, isTrue);

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      final before = tester.getRect(find.text('ALERTS'));

      await tapText(tester, 'Add alert');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertEditorSheet),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reminder'), findsOneWidget);
      expect(
        tester.getRect(find.text('ALERTS')).top,
        closeTo(before.top, 1),
        reason: 'the form scrolled away from the alert that was just added',
      );
      expect(title.focusNode.hasFocus, isFalse);
    });
  });

  group('leaving with unsaved changes', () {
    testWidgets('an untouched form closes at once', (tester) async {
      final results = await open(tester);
      await tapTooltip(tester, 'Cancel');
      expect(dialog, findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('a typed title asks first, and Keep editing keeps it', (
      tester,
    ) async {
      final results = await open(tester);
      await typeTitle(tester);
      await tapTooltip(tester, 'Cancel');

      expect(dialog, findsOneWidget);
      await tapText(tester, 'Keep editing');
      expect(dialog, findsNothing);
      expect(results, isEmpty);
      expect(find.byType(EventEditorSheet), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Leg day',
      );

      await tapTooltip(tester, 'Cancel');
      await tapText(tester, 'Discard changes');
      expect(results.single, isNull);
    });

    testWidgets('with a sheet behind, Discard reports back', (tester) async {
      final results = await open(tester, initial: eventOf(), showBack: true);
      await typeTitle(tester, 'Push day');
      await tapTooltip(tester, 'Back');
      expect(dialog, findsOneWidget);
      await tapText(tester, 'Discard changes');
      expect(results.single, isA<EventEditorBack>());
    });

    testWidgets('the seeded default alert alone is not dirty', (tester) async {
      await (await SettingsService.getInstance()).setAlertDefaultAllDay((
        mode: AlertMode.notify,
        daysBefore: 0,
        dayMinute: 9 * 60,
      ));
      final results = await open(tester);
      expect(find.text('On the day, 09:00'), findsOneWidget);

      await tapTooltip(tester, 'Cancel');
      expect(dialog, findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('removing the only alert is dirty', (tester) async {
      EventAlerts.updateCache(
        byEvent: {
          'e1': List<EventAlert>.unmodifiable(const [
            EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 30),
          ]),
        },
      );
      final results = await open(
        tester,
        initial: eventOf(time: const EventTime(startMinute: 18 * 60)),
      );
      await tapTooltip(tester, 'Remove alert');
      await tapTooltip(tester, 'Cancel');
      expect(dialog, findsOneWidget);
      await tapText(tester, 'Discard changes');
      expect(results.single, isNull);
    });

    testWidgets('saving an alert unchanged is not dirty', (tester) async {
      EventAlerts.updateCache(
        byEvent: {
          'e1': List<EventAlert>.unmodifiable(const [
            EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 30),
          ]),
        },
      );
      final results = await open(
        tester,
        initial: eventOf(time: const EventTime(startMinute: 18 * 60)),
      );
      await tapText(tester, '30 min before');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertEditorSheet),
          matching: find.widgetWithText(FilledButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();
      await tapTooltip(tester, 'Cancel');
      expect(dialog, findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('confirming the skipped days unchanged is not dirty', (
      tester,
    ) async {
      EventSkips.updateCache(
        byEvent: {
          'e1': {DateTime.utc(2026, 9, 26)},
        },
      );
      final results = await open(
        tester,
        initial: eventOf(rule: const DailyRecurrence()),
      );
      await tapText(tester, 'Skipped days');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      await tapTooltip(tester, 'Cancel');
      expect(dialog, findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('a description edit is dirty', (tester) async {
      final results = await open(tester, initial: eventOf());
      descriptionOf(tester).text = 'Heavy week';
      await tester.pump();
      await tapTooltip(tester, 'Cancel');
      expect(dialog, findsOneWidget);
      await tapText(tester, 'Discard changes');
      expect(results.single, isNull);
    });

    testWidgets('the system back gesture asks on a dirty form', (tester) async {
      final results = await open(tester);
      await typeTitle(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(results, isEmpty);
      await tapText(tester, 'Discard changes');
      expect(results.single, isNull);
    });

    testWidgets('the barrier asks on a dirty form', (tester) async {
      final results = await open(tester);
      await typeTitle(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(results, isEmpty);
      await tapText(tester, 'Keep editing');
      expect(find.byType(EventEditorSheet), findsOneWidget);
    });

    testWidgets('a downward fling on the handle closes a clean form', (
      tester,
    ) async {
      final results = await open(tester);
      await tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      );
      await tester.pumpAndSettle();

      expect(dialog, findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('a downward fling on the handle asks on a dirty form', (
      tester,
    ) async {
      final results = await open(tester);
      await typeTitle(tester);
      await tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      );
      await tester.pumpAndSettle();

      expect(dialog, findsOneWidget);
      expect(results, isEmpty);
      await tapText(tester, 'Discard changes');
      expect(results.single, isNull);
    });

    testWidgets('a short drag snaps back and pops nothing', (tester) async {
      final results = await open(tester);
      final before = tester.getTopLeft(find.byType(FormSheetHandle));
      await tester.timedDrag(
        find.byType(FormSheetHandle),
        const Offset(0, 40),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();

      expect(results, isEmpty);
      expect(find.byType(EventEditorSheet), findsOneWidget);
      expect(tester.getTopLeft(find.byType(FormSheetHandle)), before);
    });

    testWidgets('Save never asks', (tester) async {
      final results = await open(tester);
      await typeTitle(tester);
      final saved = await saveAnd(tester, results);
      expect(dialog, findsNothing);
      expect(saved.event.title, 'Leg day');
    });
  });
}
