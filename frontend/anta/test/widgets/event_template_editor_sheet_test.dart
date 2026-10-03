import 'dart:async';
import 'dart:io';
import 'dart:ui' show CheckedState, Tristate;

import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/event_templates_page.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_look_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/event_template_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/time_pad_sheet.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';
import 'support/template_form_robot.dart';
import 'support/time_pad_support.dart';

/// What the template form writes, field by field, and how it behaves as a
/// form sheet.
///
/// The groups down to "saving a draft as a template" predate the 2026-10
/// rebuild of the form (`docs/calendar-language-tier-2-roadmap.md`). They
/// pinned what the first form wrote, and they are the proof the rebuilt one
/// hands the service the same template for the same input: their bodies
/// passed the rebuild as they were, with `TemplateFormRobot` rewritten
/// underneath, but for the behaviour that record changes on purpose (§4.2,
/// item 8). The groups after them cover what the rebuild added.
///
/// Runs the real service and the real DAO against `NativeDatabase.memory()`,
/// the way `event_template_service_test` does, so a save is checked twice —
/// what `show` returned, and what the service holds afterwards.
///
/// A name starting with "today:" pins a behaviour because the code has it, not
/// because it is wanted. A later slice may close one on purpose, and changes
/// that test in the same change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two databases on purpose: the app's own, which the markdown bar's service
  // is bound to, beside the in-memory one each test's templates and settings
  // live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A template with every field off its default, so a field the form drops
  /// or resets on the way through shows up as a difference.
  const loaded = EventTemplate(
    id: 'the-draft',
    name: 'Leg day',
    categoryId: 'cardio',
    rule: WeeklyRecurrence(
      weekdays: {DateTime.monday, DateTime.thursday},
      interval: 2,
    ),
    time: EventTime(startMinute: 18 * 60, durationMinutes: 90),
    description: 'Squats, then hinge',
    iconKey: 'cake',
    colorValue: 0xFF123456,
    tintIcon: false,
    priority: 1,
    retroactive: true,
    countOccurrences: true,
    countStyle: OccurrenceCountStyle.elapsed,
    tracksPresence: true,
    assumeAbsent: true,
    perOccurrenceDescriptions: true,
    sortOrder: 7,
  );

  /// The opposite: a name, a repeating rule, and the default everywhere else.
  /// Weekly, so that every other repeat chip is a real change from it.
  const plain = EventTemplate(
    id: '',
    name: 'Push day',
    categoryId: 'gym',
    rule: WeeklyRecurrence(weekdays: {DateTime.monday}),
  );

  late AppDatabase db;
  late EventTemplateService service;
  late _TemplateWrites writes;

  // The description sheet the form opens reads the app-wide markdown bar bloc
  // from its `initState`, and the bar's service lives in the app database.
  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_template_form');
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
    CalendarPaletteService.reset();
    SettingsService.reset();
    EventTemplateService.reset();
    writes = _TemplateWrites();
    db = await openTestDatabase(interceptor: writes);
    // The form reads two settings, and the colour row, the icon picker and
    // the time pad one each.
    SettingsService.forTesting(db);
    service = await EventTemplateService.forTesting(db);
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    // The category picker lists the catalogue, and an empty one would resolve
    // every id to the fallback category.
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
  });

  tearDown(() async {
    await barBloc.close();
    CalendarCategories.updateCache(const []);
    EventTemplateService.reset();
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  /// [surface], [locale], [textScale], [use24HourFormat] and [theme] dress
  /// the device for the layout cases; left alone, the app is the bare one
  /// every round-trip case has always opened the form from.
  Future<_Outcome> openSheet(
    WidgetTester tester, {
    EventTemplate? initial,
    EventTemplate? draft,
    Size? surface,
    Locale locale = const Locale('en'),
    double? textScale,
    bool use24HourFormat = false,
    ThemeData? theme,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = _Outcome();
    await tester.pumpWidget(
      // Above the `MaterialApp`, as `main.dart` provides it: a sheet is a
      // route, so a provider inside `home` would sit below it in the tree and
      // the description sheet's `context.read` would not find it.
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          theme: theme,
          builder: textScale == null && !use24HourFormat
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(textScale ?? 1.0),
                    alwaysUse24HourFormat: use24HourFormat,
                  ),
                  child: child!,
                ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome.result = await EventTemplateEditorSheet.show(
                    context,
                    initial: initial,
                    draft: draft,
                  );
                  outcome.returned = true;
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
    return outcome;
  }

  /// Opens the form, lets [edit] drive it, saves, and returns what `show`
  /// handed back — once the form has closed on it and the service holds that
  /// very template.
  Future<EventTemplate> saveFrom(
    WidgetTester tester, {
    EventTemplate? initial,
    EventTemplate? draft,
    Future<void> Function(TemplateFormRobot form)? edit,
  }) async {
    final form = TemplateFormRobot(tester);
    final outcome = await openSheet(tester, initial: initial, draft: draft);
    await edit?.call(form);
    await form.save();

    expect(outcome.returned, isTrue, reason: 'Save left the form open');
    expect(form.isOpen, isFalse);
    final saved = outcome.result!;
    expect(
      [
        for (final template in service.templates)
          if (template.id == saved.id) template,
      ],
      [saved],
      reason: 'the service does not hold what Save returned',
    );
    return saved;
  }

  /// [saveFrom] on a blank form, which cannot save until it has a name.
  Future<EventTemplate> saveNew(
    WidgetTester tester,
    Future<void> Function(TemplateFormRobot form) edit,
  ) {
    return saveFrom(
      tester,
      edit: (form) async {
        await form.enterName('Push day');
        await edit(form);
      },
    );
  }

  /// [template] as the service keeps it once created: under the [id] it
  /// minted, at the place in the order it gave it.
  EventTemplate created(
    EventTemplate template, {
    required String id,
    required int sortOrder,
  }) {
    return EventTemplate(
      id: id,
      name: template.name,
      categoryId: template.categoryId,
      rule: template.rule,
      time: template.time,
      description: template.description,
      iconKey: template.iconKey,
      colorValue: template.colorValue,
      tintIcon: template.tintIcon,
      priority: template.priority,
      retroactive: template.retroactive,
      countOccurrences: template.countOccurrences,
      countStyle: template.countStyle,
      tracksPresence: template.tracksPresence,
      assumeAbsent: template.assumeAbsent,
      perOccurrenceDescriptions: template.perOccurrenceDescriptions,
      sortOrder: sortOrder,
    );
  }

  /// A palette swatch that is not the default category's own colour.
  int swatch() => CalendarPalette.all.firstWhere(
    (argb) => argb != CalendarCategories.resolve('gym').colorValue,
  );

  group('a blank form', () {
    testWidgets('a name alone saves the defaults of every other field', (
      tester,
    ) async {
      final saved = await saveFrom(
        tester,
        edit: (form) => form.enterName('  Push day  '),
      );

      expect(saved.id, isNotEmpty);
      expect(
        saved,
        EventTemplate(
          id: saved.id,
          name: 'Push day',
          categoryId: 'gym',
          rule: const OneTimeRecurrence(),
          time: null,
          description: null,
          iconKey: null,
          colorValue: null,
          tintIcon: true,
          priority: 3,
          retroactive: false,
          countOccurrences: false,
          countStyle: OccurrenceCountStyle.numbered,
          tracksPresence: false,
          assumeAbsent: false,
          perOccurrenceDescriptions: false,
          sortOrder: 0,
        ),
      );
      expect(service.templates, [saved]);
    });

    testWidgets('a typed name stops at 60 characters', (tester) async {
      final saved = await saveFrom(
        tester,
        edit: (form) => form.enterName('N' * 70),
      );

      expect(saved.name, 'N' * 60);
    });

    testWidgets('Save is disabled until the form has a name', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);

      expect(form.canSave, isFalse);
      await form.enterName('   ');
      expect(form.canSave, isFalse);
      await form.save();
      expect(form.isOpen, isTrue);
      expect(outcome.returned, isFalse);
      expect(service.templates, isEmpty);

      await form.enterName('Push day');
      expect(form.canSave, isTrue);
      await form.enterName('');
      expect(form.canSave, isFalse);
    });

    testWidgets('Save is disabled while the write is in flight, and a second '
        'tap adds nothing', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      writes.hold = Completer<void>();

      await form.startSave();
      expect(form.canSave, isFalse);
      expect(form.isOpen, isTrue);
      expect(outcome.returned, isFalse);
      await form.startSave();

      writes.hold!.complete();
      await form.finishSave();
      expect(outcome.result?.name, 'Push day');
      expect(service.templates, [outcome.result]);
    });

    testWidgets('a close while the write is in flight is refused, and the '
        'save returns its template', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      writes.hold = Completer<void>();
      await form.startSave();

      await form.close();
      expect(form.isOpen, isTrue);
      expect(outcome.returned, isFalse);

      writes.hold!.complete();
      await form.finishSave();
      expect(outcome.returned, isTrue);
      expect(outcome.result?.name, 'Push day');
      expect(service.templates, [outcome.result]);
    });

    testWidgets('the close button returns null and writes nothing', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');

      await form.close();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(form.isOpen, isFalse);
      expect(service.templates, isEmpty);
    });

    testWidgets('the system back returns null and writes nothing', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await form.discardChanges();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(form.isOpen, isFalse);
      expect(service.templates, isEmpty);
    });

    testWidgets('a failing save says so and keeps the form open', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      expect(form.saveFailureShown, isFalse);
      writes.refuse = true;

      await form.save();

      expect(form.saveFailureShown, isTrue);
      expect(form.isOpen, isTrue);
      expect(outcome.returned, isFalse);
      expect(service.templates, isEmpty);
    });

    testWidgets('a failed save can be tried again', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      writes.refuse = true;
      await form.save();
      expect(form.canSave, isTrue);

      writes.refuse = false;
      await form.save();

      expect(outcome.result?.name, 'Push day');
      expect(service.templates, [outcome.result]);
    });
  });

  group('time', () {
    testWidgets('All day on stores no time, whatever the form held', (
      tester,
    ) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.setAllDay(true),
      );

      expect(saved.time, isNull);
    });

    testWidgets('All day off stores the default start with no end', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) => form.setAllDay(false));

      expect(saved.time, const EventTime(startMinute: 9 * 60));
    });

    testWidgets('a picked start and end are stored as a start minute and a '
        'duration', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.setAllDay(false);
        await form.pickStart(const TimeOfDay(hour: 18, minute: 30));
        await form.pickEnd(const TimeOfDay(hour: 20, minute: 0));
      });

      expect(
        saved.time,
        const EventTime(startMinute: 18 * 60 + 30, durationMinutes: 90),
      );
    });

    testWidgets('moving the start keeps the duration, not the end', (
      tester,
    ) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.pickStart(const TimeOfDay(hour: 7, minute: 15)),
      );

      expect(
        saved.time,
        const EventTime(startMinute: 7 * 60 + 15, durationMinutes: 90),
      );
    });

    testWidgets('an end before the start is stored as a duration past '
        'midnight', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.setAllDay(false);
        await form.pickEnd(const TimeOfDay(hour: 8, minute: 0));
      });

      expect(
        saved.time,
        const EventTime(startMinute: 9 * 60, durationMinutes: 23 * 60),
      );
    });

    testWidgets('an end equal to the start is stored as a whole day', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) async {
        await form.setAllDay(false);
        await form.pickEnd(const TimeOfDay(hour: 9, minute: 0));
      });

      expect(
        saved.time,
        const EventTime(startMinute: 9 * 60, durationMinutes: 24 * 60),
      );
    });

    testWidgets('the clear button stores no duration', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.clearEnd(),
      );

      expect(saved.time, const EventTime(startMinute: 18 * 60));
    });

    testWidgets('All day on and off again keeps the time it had', (
      tester,
    ) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) async {
          await form.setAllDay(true);
          await form.setAllDay(false);
        },
      );

      expect(saved.time, loaded.time);
    });

    testWidgets('picking a start, picking an end and clearing the end raise '
        'no framework error', (tester) async {
      // The first form flashed a changed time row from between a `ListTile`
      // and its `Material`, which a debug build reports as ink that may be
      // invisible — on every pick, where a test without a filter failed.
      final form = TemplateFormRobot(tester);
      await openSheet(tester);
      await form.setAllDay(false);

      await form.pickStart(const TimeOfDay(hour: 18, minute: 30));
      expect(tester.takeException(), isNull);
      expect(form.startsLabel, '6:30 PM');

      await form.pickEnd(const TimeOfDay(hour: 20, minute: 0));
      expect(tester.takeException(), isNull);
      expect(form.endsLabel, '8:00 PM · 1 h 30 min');

      await form.clearEnd();
      expect(tester.takeException(), isNull);
      expect(form.endsLabel, 'No end time');
    });
  });

  group('repeat', () {
    for (final (repeat, rule) in const <(TemplateRepeat, RecurrenceRule)>[
      (TemplateRepeat.once, OneTimeRecurrence()),
      (TemplateRepeat.daily, DailyRecurrence()),
      (TemplateRepeat.monthly, MonthlyRecurrence()),
      (TemplateRepeat.yearly, YearlyRecurrence()),
      (TemplateRepeat.workdays, WorkdaysRecurrence()),
      (TemplateRepeat.weekends, WeekendsRecurrence()),
    ]) {
      testWidgets('the ${repeat.name} chip stores a ${rule.runtimeType}', (
        tester,
      ) async {
        final saved = await saveFrom(
          tester,
          draft: plain,
          edit: (form) => form.chooseRepeat(repeat),
        );

        expect(saved.rule, rule);
      });
    }

    testWidgets('the weekly chip stores a WeeklyRecurrence with the weekdays '
        'left on', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.weekly);
        await form.toggleWeekday(DateTime.monday);
        await form.toggleWeekday(DateTime.thursday);
        await form.toggleWeekday(DateTime.saturday);
        await form.toggleWeekday(DateTime.saturday);
      });

      expect(
        saved.rule,
        const WeeklyRecurrence(weekdays: {DateTime.monday, DateTime.thursday}),
      );
    });

    testWidgets('Weekly with no weekday on cannot be confirmed, so no such '
        'template is made here', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.weekly);
        expect(form.canConfirmRepeat, isFalse);
        await form.toggleWeekday(DateTime.monday, confirm: false);
        expect(form.canConfirmRepeat, isTrue);
        await form.toggleWeekday(DateTime.monday, confirm: false);
        expect(form.canConfirmRepeat, isFalse);
      });

      expect(saved.rule, const OneTimeRecurrence());
    });

    testWidgets('the weekdays outlive a trip to another kind', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: plain,
        edit: (form) async {
          await form.chooseRepeat(TemplateRepeat.daily);
          await form.chooseRepeat(TemplateRepeat.weekly);
        },
      );

      expect(saved.rule, plain.rule);
    });

    testWidgets('the interval stepper is offered for Daily, Weekly, Monthly '
        'and Yearly only', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      expect(form.intervalVisible, isFalse);
      for (final (repeat, offered) in const [
        (TemplateRepeat.daily, true),
        (TemplateRepeat.weekly, true),
        (TemplateRepeat.monthly, true),
        (TemplateRepeat.yearly, true),
        (TemplateRepeat.workdays, false),
        (TemplateRepeat.weekends, false),
        (TemplateRepeat.once, false),
      ]) {
        await form.chooseRepeat(repeat);
        expect(form.intervalVisible, offered, reason: repeat.name);
      }
    });

    for (final (repeat, rule) in const <(TemplateRepeat, RecurrenceRule)>[
      (TemplateRepeat.daily, DailyRecurrence(interval: 3)),
      (
        TemplateRepeat.weekly,
        WeeklyRecurrence(weekdays: {DateTime.monday}, interval: 3),
      ),
      (TemplateRepeat.monthly, MonthlyRecurrence(interval: 3)),
      (TemplateRepeat.yearly, YearlyRecurrence(interval: 3)),
    ]) {
      testWidgets('the ${repeat.name} rule stores the stepped interval', (
        tester,
      ) async {
        final saved = await saveFrom(
          tester,
          draft: plain,
          edit: (form) async {
            await form.chooseRepeat(repeat);
            await form.stepInterval(up: true);
            await form.stepInterval(up: true);
          },
        );

        expect(saved.rule, rule);
      });
    }

    testWidgets('the interval cannot go under 1', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        expect(form.interval, 1);
        expect(form.canStepInterval(up: false), isFalse);
        await form.stepInterval(up: false);
        expect(form.interval, 1);
      });

      expect(saved.rule, const DailyRecurrence());
    });

    testWidgets('the interval cannot go over 99', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(rule: const DailyRecurrence(interval: 98)),
        edit: (form) async {
          await form.openRepeat();
          expect(form.canStepInterval(up: true), isTrue);
          await form.stepInterval(up: true);
          expect(form.interval, 99);
          expect(form.canStepInterval(up: true), isFalse);
          await form.stepInterval(up: true);
          expect(form.interval, 99);
        },
      );

      expect(saved.rule, const DailyRecurrence(interval: 99));
    });

    testWidgets('the stepped interval follows the rule to another kind', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        await form.stepInterval(up: true);
        await form.stepInterval(up: true);
        await form.chooseRepeat(TemplateRepeat.workdays);
        await form.chooseRepeat(TemplateRepeat.yearly);
      });

      expect(saved.rule, const YearlyRecurrence(interval: 3));
    });

    testWidgets('today: an interval above 99 that came with the template is '
        'saved as it is', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(rule: const DailyRecurrence(interval: 150)),
      );

      expect(saved.rule, const DailyRecurrence(interval: 150));
    });
  });

  group('repeat-only options', () {
    Future<void> turnEveryOptionOn(TemplateFormRobot form) async {
      await form.setTrackPresence(true);
      await form.chooseAssume(absent: true);
      await form.setPerDay(true);
      await form.setCountOccurrences(true);
      await form.chooseScope(retroactive: true);
    }

    void expectOptions(EventTemplate saved, {required bool stored}) {
      expect(saved.tracksPresence, stored);
      expect(saved.assumeAbsent, stored);
      expect(saved.perOccurrenceDescriptions, stored);
      expect(saved.countOccurrences, stored);
      expect(saved.retroactive, stored);
    }

    testWidgets('they are stored while the rule repeats', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        await turnEveryOptionOn(form);
      });

      expectOptions(saved, stored: true);
    });

    testWidgets('they are cleared when the rule goes back to One time', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        await turnEveryOptionOn(form);
        await form.chooseRepeat(TemplateRepeat.once);
      });

      expect(saved.rule, const OneTimeRecurrence());
      expectOptions(saved, stored: false);
    });

    testWidgets('they come back when the rule repeats again', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        await turnEveryOptionOn(form);
        await form.chooseRepeat(TemplateRepeat.once);
        await form.chooseRepeat(TemplateRepeat.monthly);
      });

      expect(saved.rule, const MonthlyRecurrence());
      expectOptions(saved, stored: true);
    });

    testWidgets('Assume present stores no assume-absent', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        await form.setTrackPresence(true);
        await form.chooseAssume(absent: true);
        await form.chooseAssume(absent: false);
      });

      expect(saved.tracksPresence, isTrue);
      expect(saved.assumeAbsent, isFalse);
    });

    testWidgets('Assume absent does not outlive Track presence', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.daily);
        await form.setTrackPresence(true);
        await form.chooseAssume(absent: true);
        await form.setTrackPresence(false);
      });

      expect(saved.tracksPresence, isFalse);
      expect(saved.assumeAbsent, isFalse);
    });

    testWidgets('an assume-absent flag that came without Track presence is '
        'dropped', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(assumeAbsent: true),
      );

      expect(saved.assumeAbsent, isFalse);
    });

    testWidgets('From this date on stores no retroactive flag', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.chooseScope(retroactive: false),
      );

      expect(saved.retroactive, isFalse);
    });

    testWidgets('a yearly rule stores its Every year scope', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseRepeat(TemplateRepeat.yearly);
        await form.chooseScope(retroactive: true);
      });

      expect(saved.retroactive, isTrue);
    });

    testWidgets('Count occurrences is offered only for a kind that carries an '
        'interval', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      expect(form.countOccurrencesVisible, isFalse);
      for (final (repeat, offered) in const [
        (TemplateRepeat.daily, true),
        (TemplateRepeat.weekly, true),
        (TemplateRepeat.monthly, true),
        (TemplateRepeat.yearly, true),
        (TemplateRepeat.workdays, false),
        (TemplateRepeat.weekends, false),
        (TemplateRepeat.once, false),
      ]) {
        await form.chooseRepeat(repeat);
        // Weekly is the form's only once it has a weekday.
        if (repeat == TemplateRepeat.weekly) {
          await form.toggleWeekday(DateTime.monday);
        }
        expect(form.countOccurrencesVisible, offered, reason: repeat.name);
      }
    });

    for (final (repeat, rule) in const <(TemplateRepeat, RecurrenceRule)>[
      (TemplateRepeat.workdays, WorkdaysRecurrence()),
      (TemplateRepeat.weekends, WeekendsRecurrence()),
    ]) {
      testWidgets('a rule set here to ${repeat.name} stores no Count '
          'occurrences, whatever the switch held', (tester) async {
        final saved = await saveNew(tester, (form) async {
          await form.chooseRepeat(TemplateRepeat.daily);
          await form.setCountOccurrences(true);
          await form.chooseRepeat(repeat);
        });

        expect(saved.rule, rule);
        expect(saved.countOccurrences, isFalse);
      });

      testWidgets('a ${repeat.name} template that came counting keeps its '
          'count while its rule is left alone', (tester) async {
        final existing = await service.create(
          plain.copyWith(rule: rule, countOccurrences: true),
        );
        expect(existing.countOccurrences, isTrue);

        final untouched = await saveFrom(tester, initial: existing);
        expect(untouched, existing);

        final renamed = await saveFrom(
          tester,
          initial: existing,
          edit: (form) async {
            expect(form.countOccurrencesVisible, isFalse);
            await form.enterName('Renamed');
          },
        );
        expect(renamed, existing.copyWith(name: 'Renamed'));
      });
    }

    for (final (repeat, style) in const [
      (TemplateRepeat.daily, OccurrenceCountStyle.numbered),
      (TemplateRepeat.monthly, OccurrenceCountStyle.numbered),
      (TemplateRepeat.yearly, OccurrenceCountStyle.elapsed),
    ]) {
      testWidgets('a new ${repeat.name} template that counts occurrences '
          'counts in its kind\'s own style, ${style.name}', (tester) async {
        final saved = await saveNew(tester, (form) async {
          await form.chooseRepeat(repeat);
          await form.setCountOccurrences(true);
        });

        expect(saved.countOccurrences, isTrue);
        expect(saved.countStyle, style);
      });
    }

    testWidgets('the count style that came with the template is kept even '
        'with Count occurrences off', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.setCountOccurrences(false),
      );

      expect(saved.countOccurrences, isFalse);
      expect(saved.countStyle, OccurrenceCountStyle.elapsed);
    });
  });

  group('details', () {
    testWidgets('the description is trimmed', (tester) async {
      final saved = await saveNew(
        tester,
        (form) => form.enterDescription('  Squats, then hinge  '),
      );

      expect(saved.description, 'Squats, then hinge');
    });

    testWidgets('a blank description is stored as none', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.enterDescription('   '),
      );

      expect(saved.description, isNull);
    });

    testWidgets('a description over the limit cannot be confirmed, so the '
        'template keeps the one it had', (tester) async {
      final text = 'd' * (SettingsKeys.defaultEventDescriptionLimit + 1);

      final saved = await saveNew(tester, (form) async {
        await form.openDescription();
        await form.typeDescription(text);
        expect(form.canConfirmDescription, isFalse);
        await form.typeDescription(text.substring(1));
        expect(form.canConfirmDescription, isTrue);
        await form.typeDescription(text);
        await form.cancelDescription();
      });

      expect(saved.description, isNull);
    });

    testWidgets('a description longer than the event editor ever allows that '
        'came with the template still saves untouched', (tester) async {
      final text = 'd' * (SettingsKeys.maxEventDescriptionLimit + 1);

      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(description: text),
      );

      expect(saved.description, text);
    });

    for (var priority = 1; priority <= 5; priority++) {
      testWidgets('priority $priority is stored from its chip', (tester) async {
        final saved = await saveFrom(
          tester,
          draft: plain.copyWith(priority: priority == 5 ? 1 : priority + 1),
          edit: (form) => form.choosePriority(priority),
        );

        expect(saved.priority, priority);
      });
    }

    testWidgets('a picked category is stored', (tester) async {
      final saved = await saveNew(
        tester,
        (form) => form.chooseCategory('cardio'),
      );

      expect(saved.categoryId, 'cardio');
    });

    testWidgets('a category the catalogue no longer has is saved as it came', (
      tester,
    ) async {
      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(categoryId: 'deleted-category'),
      );

      expect(saved.categoryId, 'deleted-category');
    });

    testWidgets('a picked icon is stored', (tester) async {
      final saved = await saveNew(tester, (form) => form.chooseIcon('cake'));

      expect(saved.iconKey, 'cake');
    });

    testWidgets('the icon row\'s reset stores no icon', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.resetIcon(),
      );

      expect(saved.iconKey, isNull);
    });

    testWidgets('a swatch stores its colour and leaves the tint on', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) => form.chooseColor(swatch()));

      expect(saved.colorValue, swatch());
      expect(saved.tintIcon, isTrue);
    });

    testWidgets('the category-colour swatch stores no colour', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: loaded,
        edit: (form) => form.useCategoryColor(),
      );

      expect(saved.colorValue, isNull);
    });

    testWidgets('the Tint switch is hidden while there is no colour', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      expect(form.tintVisible, isFalse);
      await form.chooseColor(swatch());
      expect(form.tintVisible, isTrue);
      await form.useCategoryColor();
      expect(form.tintVisible, isFalse);
    });

    testWidgets('Tint off is stored with the colour', (tester) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseColor(swatch());
        await form.setTint(false);
      });

      expect(saved.colorValue, swatch());
      expect(saved.tintIcon, isFalse);
    });

    testWidgets('a tint switched off is stored even after its colour is gone', (
      tester,
    ) async {
      final saved = await saveNew(tester, (form) async {
        await form.chooseColor(swatch());
        await form.setTint(false);
        await form.useCategoryColor();
      });

      expect(saved.colorValue, isNull);
      expect(saved.tintIcon, isFalse);
    });
  });

  group('editing a template', () {
    testWidgets('an untouched edit writes the template back unchanged', (
      tester,
    ) async {
      final existing = await service.create(loaded);

      final saved = await saveFrom(tester, initial: existing);

      expect(saved, created(loaded, id: existing.id, sortOrder: 0));
      expect(service.templates, [existing]);
    });

    testWidgets('initial wins over draft', (tester) async {
      final existing = await service.create(loaded);

      final saved = await saveFrom(tester, initial: existing, draft: plain);

      expect(saved, existing);
    });

    testWidgets('an edit keeps the id and the place in the order, and '
        'rewrites its own row', (tester) async {
      final first = await service.create(plain);
      final second = await service.create(loaded);

      final saved = await saveFrom(
        tester,
        initial: second,
        edit: (form) => form.enterName('Deadlift day'),
      );

      expect(saved.id, second.id);
      expect(saved.sortOrder, 1);
      expect(saved, second.copyWith(name: 'Deadlift day'));
      expect(service.templates, [first, saved]);
    });

    testWidgets('closing an edit leaves the stored template as it was', (
      tester,
    ) async {
      final existing = await service.create(loaded);
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, initial: existing);
      await form.enterName('Deadlift day');

      await form.close();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(service.templates, [existing]);
    });
  });

  group('saving a draft as a template', () {
    testWidgets('a draft is saved with every field it came with', (
      tester,
    ) async {
      final saved = await saveFrom(tester, draft: loaded);

      expect(saved, created(loaded, id: saved.id, sortOrder: 0));
    });

    testWidgets('a draft becomes a new template at the end of the order', (
      tester,
    ) async {
      final first = await service.create(plain);

      final saved = await saveFrom(tester, draft: loaded);

      expect(saved.id, isNotEmpty);
      expect(saved.id, isNot(loaded.id));
      expect(saved.sortOrder, 1);
      expect(service.templates, [first, saved]);
    });

    for (final (kind, rule) in <(String, RecurrenceRule)>[
      ('holidays-only', const PublicHolidaysOnlyRecurrence()),
      (
        'specific-dates',
        SpecificDatesRecurrence(
          dates: {DateTime.utc(2026, 9, 20), DateTime.utc(2026, 9, 27)},
        ),
      ),
    ]) {
      testWidgets('a $kind rule in the draft collapses to One time and loses '
          'its repeat-only flags', (tester) async {
        final saved = await saveFrom(
          tester,
          draft: loaded.copyWith(rule: rule),
        );

        expect(
          saved,
          created(
            loaded.copyWith(
              rule: const OneTimeRecurrence(),
              retroactive: false,
              countOccurrences: false,
              tracksPresence: false,
              assumeAbsent: false,
              perOccurrenceDescriptions: false,
            ),
            id: saved.id,
            sortOrder: 0,
          ),
        );
      });
    }

    testWidgets('today: a name longer than 60 characters that came with the '
        'draft is saved as it is', (tester) async {
      final name = 'N' * 80;

      final saved = await saveFrom(tester, draft: plain.copyWith(name: name));

      expect(saved.name, name);
    });
  });

  // --- What the 2026-10 rebuild added ---------------------------------------

  const phone = Size(360, 780);

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Finder inForm(Finder matching) => find.descendant(
    of: find.byType(EventTemplateEditorSheet),
    matching: matching,
  );

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(byId(id)).getSemanticsData();

  double formHeight(WidgetTester tester) =>
      tester.getSize(find.byType(EventTemplateEditorSheet)).height;

  List<FormRowGroup> groupsOf(WidgetTester tester) => tester
      .widgetList<FormRowGroup>(inForm(find.byType(FormRowGroup)))
      .toList();

  List<String> sectionsOf(WidgetTester tester) => [
    for (final label in tester.widgetList<FormSectionLabel>(
      inForm(find.byType(FormSectionLabel)),
    ))
      label.text,
  ];

  EventAvatar avatarOf(WidgetTester tester) =>
      tester.widget<EventAvatar>(inForm(find.byType(EventAvatar)));

  /// The description row's one text.
  Finder descriptionText() => find.descendant(
    of: byId(SemanticsIds.templateDescription),
    matching: find.byType(Text),
  );

  ColorScheme colorsOf(WidgetTester tester) => Theme.of(
    tester.element(find.byType(EventTemplateEditorSheet)),
  ).colorScheme;

  /// Brings the form's control carrying [id] into view: its semantics node
  /// exists only near the viewport, the widget that names it everywhere.
  Future<void> reveal(WidgetTester tester, String id) async {
    await tester.ensureVisible(
      inForm(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.identifier == id,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final waysOut = <String, Future<void> Function(WidgetTester tester)>{
    'the ✕': (tester) => TemplateFormRobot(tester).tapClose(),
    'the system back': (tester) => tester.binding.handlePopRoute(),
    'the barrier': (tester) => tester.tapAt(const Offset(10, 10)),
    'a fling on the handle': (tester) =>
        tester.fling(find.byType(FormSheetHandle), const Offset(0, 400), 2000),
  };

  group('chrome', () {
    testWidgets('the header is a close, the title and a text Save on their '
        'ids, on a sheet that takes the form sheet\'s share of the screen', (
      tester,
    ) async {
      await openSheet(tester, surface: phone);

      expect(inForm(find.byType(FormSheetHandle)), findsOneWidget);
      final header = tester.widget<FormSheetHeader>(
        inForm(find.byType(FormSheetHeader)),
      );
      expect(header.title, 'New template');
      expect(header.leadingIcon, Icons.close_rounded);
      expect(header.leadingIdentifier, SemanticsIds.templateClose);
      expect(dataOf(tester, SemanticsIds.templateClose).tooltip, 'Cancel');
      final save = tester.widget<FormHeaderTextButton>(
        inForm(find.byType(FormHeaderTextButton)),
      );
      expect(save.label, 'Save');
      expect(save.identifier, SemanticsIds.templateSave);
      // The filled Save is the event editor's alone.
      expect(inForm(find.byType(FilledButton)), findsNothing);
      expect(formHeight(tester), phone.height * FormMetrics.sheetHeightFactor);
    });

    testWidgets('Save is announced as a button, disabled in place until the '
        'form has a name', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      var save = dataOf(tester, SemanticsIds.templateSave);
      expect(save.label, 'Save');
      expect(save.flagsCollection.isButton, isTrue);
      expect(save.flagsCollection.isEnabled, Tristate.isFalse);

      await form.enterName('Push day');
      save = dataOf(tester, SemanticsIds.templateSave);
      expect(save.flagsCollection.isEnabled, Tristate.isTrue);
    });

    testWidgets('the header draws its hairline once the form is scrolled', (
      tester,
    ) async {
      await openSheet(tester, draft: loaded, surface: phone);
      final scrolled = tester
          .widget<FormSheetHeader>(inForm(find.byType(FormSheetHeader)))
          .scrolled!;
      expect(scrolled.value, isFalse);

      await tester.drag(
        inForm(find.byType(SingleChildScrollView)),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      expect(scrolled.value, isTrue);
    });

    testWidgets('the hairline follows a form that gets shorter: scrolled '
        'over the keyboard it is on, and off again once the keyboard is down '
        'and the form rests at its top', (tester) async {
      // A blank form fits the sheet unscrolled and scrolls only while the
      // keyboard's inset pads it.
      await openSheet(tester, surface: phone);
      final body = inForm(find.byType(SingleChildScrollView));
      final scrolled = tester
          .widget<FormSheetHeader>(inForm(find.byType(FormSheetHeader)))
          .scrolled!;
      double offset() => tester
          .state<ScrollableState>(
            find.descendant(of: body, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(scrolled.value, isFalse);
      await tester.drag(body, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(offset(), greaterThan(0));
      expect(scrolled.value, isTrue);

      // The scroll view goes back to its top without a scroll.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(offset(), 0);
      expect(scrolled.value, isFalse);
    });

    testWidgets('an edit is titled Edit template; a draft is still a new one', (
      tester,
    ) async {
      String title() => tester
          .widget<FormSheetHeader>(inForm(find.byType(FormSheetHeader)))
          .title;
      final form = TemplateFormRobot(tester);
      final existing = await service.create(loaded);

      await openSheet(tester, initial: existing);
      expect(title(), 'Edit template');
      await form.close();

      await openSheet(tester, draft: loaded);
      expect(title(), 'New template');
    });

    final themes = <String, ThemeData Function()>{
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    };
    for (final theme in themes.entries) {
      testWidgets('in ${theme.key} the form is the editor\'s groups on the '
          'page ground, with nothing of the older chrome left', (tester) async {
        await openSheet(tester, draft: loaded, theme: theme.value());
        final colorScheme = colorsOf(tester);

        expect(
          tester
              .widget<Material>(
                find
                    .descendant(
                      of: find.byType(FormSheetFrame),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color,
          colorScheme.pageGround,
        );
        // Capture, WHEN, OCCURRENCES and DETAILS; only the last without a
        // gap under it.
        final groups = groupsOf(tester);
        expect(
          [for (final group in groups) group.children.length],
          [4, 4, 5, 1],
        );
        expect(
          [for (final group in groups) group.trailingGap],
          [true, true, true, false],
        );
        expect(sectionsOf(tester), ['When', 'Occurrences', 'Details']);
        for (final group in groups) {
          final ground = tester.widget<Material>(
            find
                .descendant(
                  of: find.byWidget(group),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(ground.color, colorScheme.rowGroup);
          expect(ground.elevation, 0);
        }
        for (final gone in [
          Card,
          ListTile,
          SwitchListTile,
          ChoiceChip,
          FilterChip,
          SegmentedButton<bool>,
        ]) {
          expect(inForm(find.byType(gone)), findsNothing, reason: '$gone');
        }
        // The name is the form's one field: the description is a row.
        expect(inForm(find.byType(TextField)), findsOneWidget);
      });
    }

    testWidgets('the rows are the editor\'s, in its order, with its glyphs, '
        'labels and hairlines', (tester) async {
      await openSheet(tester, draft: loaded);
      final groups = groupsOf(tester);

      final capture = groups[0].children;
      expect(capture[0], isA<FormTitleRow>());
      final category = capture[1] as FormPickerRow;
      expect(category.glyph, Icons.label_outlined);
      expect(category.label, 'Category');
      final look = capture[2] as FormPickerRow;
      expect(look.glyph, Icons.palette_outlined);
      expect(look.label, 'Icon & color');
      expect(
        tester
            .widget<FormGlyph>(
              find.descendant(
                of: byId(SemanticsIds.templateDescription),
                matching: find.byType(FormGlyph),
              ),
            )
            .icon,
        Icons.notes_rounded,
      );
      // Under the name the hairline starts past the avatar; under every other
      // row of the group past its glyph.
      expect(
        [for (final row in capture) FormRowGroup.indentOf(row)],
        [
          FormMetrics.dividerIndentTitle,
          FormMetrics.dividerIndentGlyph,
          FormMetrics.dividerIndentGlyph,
          FormMetrics.dividerIndentGlyph,
        ],
      );

      final when = groups[1].children;
      final allDay = when[0] as FormSwitchRow;
      expect(allDay.glyph, Icons.schedule_outlined);
      expect(allDay.label, 'All day');
      // Starts and Ends are the switch's sub-rows: no glyph, set in under
      // its label, each in the highlight that reads a new time back.
      for (final (index, label) in const [(1, 'Starts'), (2, 'Ends')]) {
        final row =
            (when[index] as ValueChangeHighlight).child as FormPickerRow;
        expect(row.label, label);
        expect(row.subRow, isTrue);
        expect(row.glyph, isNull);
      }
      final repeat = when[3] as FormPickerRow;
      expect(repeat.glyph, Icons.repeat_rounded);
      expect(repeat.label, 'Repeat');

      final occurrences = groups[2].children;
      for (final (index, glyph, label) in const [
        (0, Icons.numbers_rounded, 'Count occurrences'),
        (2, Icons.how_to_reg_outlined, 'Track presence'),
        (4, Icons.event_note_outlined, 'Separate description per day'),
      ]) {
        final row = occurrences[index] as FormSwitchRow;
        expect(row.glyph, glyph);
        expect(row.label, label);
        // Never a second line of help under a label.
        expect(row.subtitle, isNull);
      }
      expect(occurrences[1], isA<FormChipRow>());
      expect(occurrences[3], isA<FormChipRow>());

      final priority = groups[3].children.single as FormMenuRow<int>;
      expect(priority.glyph, Icons.flag_outlined);
      expect(priority.label, 'Priority');
    });
  });

  group('leaving', () {
    for (final way in waysOut.entries) {
      testWidgets('${way.key} leaves an untouched form at once, with nothing', (
        tester,
      ) async {
        final form = TemplateFormRobot(tester);
        final outcome = await openSheet(tester);

        await way.value(tester);
        await tester.pumpAndSettle();

        expect(form.discardPromptShown, isFalse);
        expect(outcome.returned, isTrue);
        expect(outcome.result, isNull);
        expect(form.isOpen, isFalse);
        expect(service.templates, isEmpty);
      });

      testWidgets('${way.key} asks on a changed form: Keep editing stays, '
          'Discard changes leaves with nothing', (tester) async {
        final form = TemplateFormRobot(tester);
        final outcome = await openSheet(tester);
        await form.enterName('Push day');

        await way.value(tester);
        await tester.pumpAndSettle();
        expect(form.discardPromptShown, isTrue);
        expect(outcome.returned, isFalse);

        await form.keepEditing();
        expect(form.discardPromptShown, isFalse);
        expect(form.isOpen, isTrue);
        expect(form.name, 'Push day');
        expect(outcome.returned, isFalse);

        await way.value(tester);
        await tester.pumpAndSettle();
        expect(form.discardPromptShown, isTrue);
        await form.discardChanges();

        expect(outcome.returned, isTrue);
        expect(outcome.result, isNull);
        expect(form.isOpen, isFalse);
        expect(service.templates, isEmpty);
      });

      testWidgets('${way.key} is ignored while the save is in flight, and the '
          'save returns its template', (tester) async {
        final form = TemplateFormRobot(tester);
        final outcome = await openSheet(tester);
        await form.enterName('Push day');
        writes.hold = Completer<void>();
        await form.startSave();

        await way.value(tester);
        await tester.pumpAndSettle();
        expect(form.discardPromptShown, isFalse);
        expect(form.isOpen, isTrue);
        expect(outcome.returned, isFalse);

        writes.hold!.complete();
        await form.finishSave();
        expect(outcome.returned, isTrue);
        expect(outcome.result?.name, 'Push day');
        expect(service.templates, [outcome.result]);
      });
    }

    testWidgets('a fling during the write of an untouched edit is ignored '
        'too: clean is not idle', (tester) async {
      final existing = await service.create(loaded);
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, initial: existing);
      writes.hold = Completer<void>();
      await form.startSave();

      await waysOut['a fling on the handle']!(tester);
      await tester.pumpAndSettle();
      expect(form.isOpen, isTrue);
      expect(outcome.returned, isFalse);

      writes.hold!.complete();
      await form.finishSave();
      expect(outcome.result, existing);
    });

    testWidgets('while the write is in flight the rows take no touch', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: plain);
      writes.hold = Completer<void>();
      await form.startSave();

      await tester.tap(byId(SemanticsIds.templateAllDay), warnIfMissed: false);
      await tester.tap(byId(SemanticsIds.templateRepeat), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(form.allDay, isTrue);
      expect(find.byType(EventRepeatSheet), findsNothing);

      writes.hold!.complete();
      await form.finishSave();
      expect(outcome.result?.time, isNull);
      expect(outcome.result?.rule, plain.rule);
    });

    testWidgets('a failed save gives the ways out back', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      writes.refuse = true;
      await form.save();
      expect(form.saveFailureShown, isTrue);

      await form.setAllDay(false);
      expect(form.allDay, isFalse);
      await form.tapClose();
      expect(form.discardPromptShown, isTrue);
      await form.discardChanges();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
    });

    for (final seed in ['a draft', 'a stored template']) {
      testWidgets('a form seeded from $seed opens clean', (tester) async {
        final stored = seed == 'a draft' ? null : await service.create(loaded);
        final form = TemplateFormRobot(tester);
        final outcome = await openSheet(
          tester,
          initial: stored,
          draft: stored == null ? loaded : null,
        );

        await form.tapClose();

        expect(form.discardPromptShown, isFalse);
        expect(outcome.returned, isTrue);
        expect(outcome.result, isNull);
      });
    }

    final edits = <String, Future<void> Function(TemplateFormRobot form)>{
      'the name': (form) => form.enterName('Deadlift day'),
      'the category': (form) => form.chooseCategory('gym'),
      'the icon': (form) => form.resetIcon(),
      'the colour': (form) => form.useCategoryColor(),
      'the tint': (form) => form.setTint(true),
      'the description': (form) => form.enterDescription('Hinge first'),
      'All day': (form) => form.setAllDay(true),
      'the start': (form) =>
          form.pickStart(const TimeOfDay(hour: 7, minute: 0)),
      'the end': (form) => form.pickEnd(const TimeOfDay(hour: 20, minute: 0)),
      'the cleared end': (form) => form.clearEnd(),
      'the repeat kind': (form) => form.chooseRepeat(TemplateRepeat.daily),
      'the interval': (form) => form.stepInterval(up: true),
      'a weekday': (form) => form.toggleWeekday(DateTime.friday),
      'the before-start switch': (form) => form.chooseScope(retroactive: false),
      'Count occurrences': (form) => form.setCountOccurrences(false),
      'the count style': (form) =>
          form.chooseCountStyle(OccurrenceCountStyle.numbered),
      'Track presence': (form) => form.setTrackPresence(false),
      'the presence default': (form) => form.chooseAssume(absent: false),
      'Separate description per day': (form) => form.setPerDay(false),
      'the priority': (form) => form.choosePriority(4),
    };
    for (final edit in edits.entries) {
      testWidgets('a change of ${edit.key} makes the form ask', (tester) async {
        final form = TemplateFormRobot(tester);
        final outcome = await openSheet(tester, draft: loaded);
        await edit.value(form);

        await form.tapClose();
        expect(form.discardPromptShown, isTrue);
        await form.discardChanges();

        expect(outcome.returned, isTrue);
        expect(outcome.result, isNull);
        expect(service.templates, isEmpty);
      });
    }

    testWidgets('a picker or a sub-sheet left without a change leaves the '
        'form clean', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: loaded);

      await form.openRepeat();
      await form.confirmRepeat();
      await form.openLook();
      await form.confirmLook();
      await form.openDescription();
      await form.confirmDescription();
      await form.openCategoryPicker();
      await tester.tap(byId(SemanticsIds.categoryPickClose));
      await tester.pumpAndSettle();
      await form.openStartPad();
      await cancelTimePad(tester);
      await form.openEndPad();
      await cancelTimePad(tester);
      await form.openPriorityMenu();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await form.tapClose();
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);
    });

    testWidgets('a change taken back leaves the form clean', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: loaded);

      await form.enterName('Deadlift day');
      await form.enterName(loaded.name);
      await form.setAllDay(true);
      await form.setAllDay(false);
      await form.setCountOccurrences(false);
      await form.setCountOccurrences(true);
      await form.setTrackPresence(false);
      await form.setTrackPresence(true);

      await form.tapClose();
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);
    });

    testWidgets('a repeat changed and changed back leaves the form clean', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: plain);
      final opened = form.repeatLabel;

      await form.chooseRepeat(TemplateRepeat.daily);
      expect(form.repeatLabel, isNot(opened));
      await form.chooseRepeat(TemplateRepeat.weekly);
      expect(form.repeatLabel, opened);

      // Save would write the template the form opened with, so leaving has
      // nothing to ask about.
      await form.tapClose();
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(service.templates, isEmpty);
    });

    testWidgets('a stored Workdays template that counts occurrences: its rule '
        'changed and changed back would save without the count, so the form '
        'asks', (tester) async {
      final existing = await service.create(
        const EventTemplate(
          id: '',
          name: 'Walk',
          categoryId: 'gym',
          rule: WorkdaysRecurrence(),
          countOccurrences: true,
        ),
      );
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, initial: existing);
      final opened = form.repeatLabel;

      await form.chooseRepeat(TemplateRepeat.daily);
      await form.chooseRepeat(TemplateRepeat.workdays);
      expect(form.repeatLabel, opened);

      await form.tapClose();
      expect(form.discardPromptShown, isTrue);
      await form.discardChanges();
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(service.templates, [existing]);
    });

    testWidgets('a short drag snaps back and pops nothing', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      final before = tester.getTopLeft(find.byType(FormSheetHandle));

      await tester.timedDrag(
        find.byType(FormSheetHandle),
        const Offset(0, 40),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();

      expect(outcome.returned, isFalse);
      expect(form.isOpen, isTrue);
      expect(tester.getTopLeft(find.byType(FormSheetHandle)), before);
    });

    testWidgets('Save never asks', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');

      await form.startSave();
      expect(form.discardPromptShown, isFalse);
      await form.finishSave();

      expect(form.discardPromptShown, isFalse);
      expect(outcome.result?.name, 'Push day');
    });
  });

  group('the name', () {
    testWidgets('a title row on its id, wearing what the stamped event will '
        'wear', (tester) async {
      await openSheet(tester);

      final row = tester.widget<FormTitleRow>(
        inForm(find.byType(FormTitleRow)),
      );
      expect(row.hint, 'Template name');
      expect(row.maxLength, 60);
      expect(row.counterFrom, 50);
      expect(row.identifier, SemanticsIds.templateName);
      expect(row.textCapitalization, TextCapitalization.sentences);
      expect(
        dataOf(tester, SemanticsIds.templateName).flagsCollection.isTextField,
        isTrue,
      );
      final gym = CalendarCategories.resolve('gym');
      expect(avatarOf(tester).icon, CalendarIcons.forKey(gym.iconKey));
      expect(avatarOf(tester).color, gym.color);
    });

    testWidgets('a new form opens on its name; an edit and a draft do not', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final existing = await service.create(loaded);

      await openSheet(tester);
      expect(form.nameFocused, isTrue);
      await form.close();

      await openSheet(tester, draft: loaded);
      expect(form.nameFocused, isFalse);
      await form.close();

      await openSheet(tester, initial: existing);
      expect(form.nameFocused, isFalse);
    });

    testWidgets('a tap in the title row beside its text — its bottom-left '
        'area, under the avatar — focuses the name', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);
      expect(form.nameFocused, isFalse);

      final row = tester.getRect(inForm(find.byType(FormTitleRow)));
      final field = tester.getRect(inForm(find.byType(TextField)));
      final point = Offset(row.left + 8, row.bottom - 4);
      expect(field.contains(point), isFalse);
      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(form.nameFocused, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the name is named by its hint for a screen reader, empty '
        'and typed', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);
      expect(dataOf(tester, SemanticsIds.templateName).label, 'Template name');

      await form.enterName('Push day');
      await tester.pumpAndSettle();
      final typed = dataOf(tester, SemanticsIds.templateName);
      expect(typed.label, 'Template name');
      expect(typed.value, 'Push day');
    });

    testWidgets('the counter appears from 50 characters and turns to the '
        'error colour at the limit', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      await form.enterName('N' * 49);
      expect(inForm(find.text('49/60')), findsNothing);
      await form.enterName('N' * 50);
      expect(
        tester.widget<Text>(inForm(find.text('50/60'))).style!.color,
        colorsOf(tester).onSurfaceVariant,
      );
      await form.enterName('N' * 60);
      expect(
        tester.widget<Text>(inForm(find.text('60/60'))).style!.color,
        colorsOf(tester).error,
      );
    });
  });

  group('the category and the look', () {
    testWidgets('the category row reads the category and moves the look a '
        'template has not set', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);
      final cardio = CalendarCategories.resolve('cardio');
      expect(form.categoryLabel, 'Gym');

      await form.chooseCategory('cardio');

      expect(form.categoryLabel, 'Cardio');
      expect(avatarOf(tester).icon, CalendarIcons.forKey(cardio.iconKey));
      expect(avatarOf(tester).color, cardio.color);
    });

    testWidgets('a dismissed category picker changes nothing', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);

      await form.openCategoryPicker();
      await tester.tap(byId(SemanticsIds.categoryPickClose));
      await tester.pumpAndSettle();

      expect(form.categoryLabel, 'Cardio');
    });

    testWidgets('the Icon & color sheet opens on the form\'s look and its '
        'category', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);

      await form.openLook();

      final sheet = tester.widget<EventLookSheet>(find.byType(EventLookSheet));
      expect(
        sheet.draft,
        const EventLookDraft(
          iconKey: 'cake',
          colorValue: 0xFF123456,
          tintIcon: false,
        ),
      );
      expect(sheet.category.id, 'cardio');
    });

    testWidgets('the look round-trips through the sheet, and the avatar and '
        'the row follow it', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      final gym = CalendarCategories.resolve('gym');
      Color dot() {
        final box = tester.widget<Container>(
          find.descendant(
            of: byId(SemanticsIds.templateLook),
            matching: find.byType(Container),
          ),
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      await form.enterName('Push day');
      expect(form.lookLabel, 'Default');
      expect(dot(), gym.color);

      await form.chooseColor(swatch());
      await form.cancelLook();
      expect(form.lookLabel, 'Custom');
      expect(dot(), Color(swatch()));
      expect(avatarOf(tester).color, Color(swatch()));

      // Tint off: the colour stays the event's, the icon goes back to the
      // category's.
      await form.setTint(false);
      await form.cancelLook();
      expect(dot(), Color(swatch()));
      expect(avatarOf(tester).color, gym.color);

      await form.chooseIcon('cake');
      await form.cancelLook();
      expect(avatarOf(tester).icon, CalendarIcons.forKey('cake'));

      await form.save();
      expect(outcome.result?.iconKey, 'cake');
      expect(outcome.result?.colorValue, swatch());
      expect(outcome.result?.tintIcon, isFalse);
    });

    testWidgets('a look back at its defaults reads Default again', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);
      expect(form.lookLabel, 'Custom');

      await form.resetIcon();
      expect(form.lookLabel, 'Custom');
      await form.useCategoryColor();
      await form.cancelLook();

      expect(form.lookLabel, 'Default');
      final cardio = CalendarCategories.resolve('cardio');
      expect(avatarOf(tester).icon, CalendarIcons.forKey(cardio.iconKey));
      expect(avatarOf(tester).color, cardio.color);
    });

    testWidgets('a cancelled Icon & color sheet changes nothing', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');

      await form.chooseColor(swatch(), confirm: false);
      await form.cancelLook();
      expect(form.lookLabel, 'Default');

      await form.save();
      expect(outcome.result?.colorValue, isNull);
    });
  });

  group('the description row', () {
    testWidgets('with no description it invites one, in the hint colour', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, surface: phone);

      expect(form.descriptionLabel, 'Add description');
      final text = tester.widget<Text>(descriptionText());
      // A label, so it wraps whole where a description is clamped.
      expect(text.maxLines, isNull);
      expect(text.style!.color, colorsOf(tester).onSurfaceVariant);
      final data = dataOf(tester, SemanticsIds.templateDescription);
      expect(data.label, 'Add description');
      expect(data.flagsCollection.isButton, isTrue);
      expect(
        tester.getSize(byId(SemanticsIds.templateDescription)).height,
        FormMetrics.rowMinHeight,
      );
    });

    testWidgets('a short description is read back on one line, named for a '
        'screen reader', (tester) async {
      final form = TemplateFormRobot(tester);
      // Short enough for one line in the test font, which draws every glyph
      // a full em wide.
      await openSheet(
        tester,
        draft: plain.copyWith(description: 'Squats first'),
        surface: phone,
      );

      expect(form.descriptionLabel, 'Squats first');
      final text = tester.widget<Text>(descriptionText());
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.color, colorsOf(tester).onSurface);
      // The text alone does not say which row it is.
      expect(
        dataOf(tester, SemanticsIds.templateDescription).label,
        'Description, Squats first',
      );
      expect(
        tester.renderObject<RenderParagraph>(descriptionText()).size.height,
        FormMetrics.labelLineHeight,
      );
      expect(
        tester.getSize(byId(SemanticsIds.templateDescription)).height,
        FormMetrics.rowMinHeight,
      );
    });

    testWidgets('a long description is clamped to two lines', (tester) async {
      await openSheet(
        tester,
        draft: plain.copyWith(
          description:
              'Squats first, then the hinge, then lunges with the '
              'dumbbells and a long cool-down on the mat.',
        ),
        surface: phone,
      );

      final paragraph = tester.renderObject<RenderParagraph>(descriptionText());
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(paragraph.size.height, 2 * FormMetrics.labelLineHeight);
      // The row grows by the second line and no further.
      expect(
        tester.getSize(byId(SemanticsIds.templateDescription)).height,
        2 * FormMetrics.labelLineHeight + 2 * FormMetrics.pairVerticalPadding,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('markdown markers are dropped and the lines run on', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      await openSheet(
        tester,
        draft: plain.copyWith(
          description:
              '## Plan\n**Squats** first\n- [x] warm up\n- [ ] ~~rest~~',
        ),
      );

      expect(form.descriptionLabel, 'Plan Squats first ✓ warm up rest');
    });

    testWidgets('a line that starts like a ledger row previews as it is '
        'written: a description has no ledger', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: plain.copyWith(description: '\$= 500'));

      // A note's preview would read this line as a money row and say "500".
      expect(form.descriptionLabel, '\$= 500');
      expect(
        dataOf(tester, SemanticsIds.templateDescription).label,
        'Description, \$= 500',
      );
      await form.close();

      // The markers around such a line still go.
      await openSheet(
        tester,
        draft: plain.copyWith(
          description: '## Budget\n- \$+ 45.00 **chalk**\n\$\$ Total',
        ),
      );
      expect(form.descriptionLabel, 'Budget \$+ 45.00 chalk \$\$ Total');
    });

    testWidgets('a description of blanks reads as none, and is stored as '
        'none', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(
        tester,
        draft: plain.copyWith(description: ' \n  '),
      );

      expect(form.descriptionLabel, 'Add description');
      await form.save();
      expect(outcome.result?.description, isNull);
    });

    testWidgets('the row opens the description sheet on the text, under the '
        'name, with the setting\'s limit and the length it came with', (
      tester,
    ) async {
      await (await SettingsService.getInstance()).setEventDescriptionLimit(500);
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);
      await form.enterName('  Deadlift day ');

      await form.openDescription();

      final sheet = tester.widget<EventDescriptionSheet>(
        find.byType(EventDescriptionSheet),
      );
      expect(sheet.initialText, 'Squats, then hinge');
      expect(sheet.heading, 'Deadlift day');
      expect(sheet.limit, 500);
      expect(sheet.grandfatheredLength, 'Squats, then hinge'.length);
      // A template's description has one scope.
      expect(sheet.scopeCaption, isNull);
    });

    testWidgets('a confirmed description is the row\'s and the template\'s', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: plain);

      await form.enterDescription('Squats\n**Hinge** after');

      expect(form.descriptionLabel, 'Squats Hinge after');
      await form.save();
      expect(outcome.result?.description, 'Squats\n**Hinge** after');
    });

    testWidgets('a cancelled description sheet changes nothing', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: loaded);

      await form.openDescription();
      await form.typeDescription('Hinge first');
      await form.cancelDescription();

      expect(form.descriptionLabel, 'Squats, then hinge');
      await form.tapClose();
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);
    });

    testWidgets('the grandfathered length is the one the form opened with, '
        'whatever was confirmed since', (tester) async {
      final long = 'd' * (SettingsKeys.defaultEventDescriptionLimit + 50);
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(
        tester,
        draft: plain.copyWith(description: long),
      );

      await form.enterDescription('short');
      await form.openDescription();
      expect(
        tester
            .widget<EventDescriptionSheet>(find.byType(EventDescriptionSheet))
            .grandfatheredLength,
        long.length,
      );
      // Back to the length it had is allowed; a character more is not.
      await form.typeDescription(long);
      expect(form.canConfirmDescription, isTrue);
      await form.typeDescription('${long}d');
      expect(form.canConfirmDescription, isFalse);
      await form.typeDescription(long);
      await form.confirmDescription();

      expect(form.canSave, isTrue);
      await form.save();
      expect(outcome.result?.description, long);
    });

    testWidgets('the palette of the settings reaches the row and the sheet', (
      tester,
    ) async {
      await (await SettingsService.getInstance()).setCustomColors({
        'brand': const Color(0xFF00AA00),
      });
      final form = TemplateFormRobot(tester);
      await openSheet(
        tester,
        draft: plain.copyWith(description: '{brand:Heavy} {nope:week}'),
      );

      // A colour run is consumed only when its name resolves.
      expect(form.descriptionLabel, 'Heavy {nope:week}');
      await form.openDescription();
      expect(
        tester
            .widget<EventDescriptionSheet>(find.byType(EventDescriptionSheet))
            .colorPalette,
        await (await SettingsService.getInstance()).getColorPalette(),
      );
    });

    testWidgets('Save is disabled while the description is over a limit that '
        'arrived after it was confirmed', (tester) async {
      await (await SettingsService.getInstance()).setEventDescriptionLimit(500);
      final form = TemplateFormRobot(tester);
      // The form opens with the default limit and learns the stored one a
      // moment later; held here, that moment lasts as long as the test needs.
      writes.holdSettings = Completer<void>();
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      await form.enterDescription('d' * 600);
      expect(form.canSave, isTrue);

      writes.holdSettings!.complete();
      await tester.pumpAndSettle();
      expect(form.canSave, isFalse);
      await form.save();
      expect(form.isOpen, isTrue);
      expect(service.templates, isEmpty);

      // The way out is the sheet that says why.
      await form.openDescription();
      expect(form.canConfirmDescription, isFalse);
      await form.typeDescription('d' * 500);
      await form.confirmDescription();
      expect(form.canSave, isTrue);
      await form.save();
      expect(outcome.result?.description, 'd' * 500);
    });
  });

  group('the time rows', () {
    testWidgets('All day takes the time rows away and brings them back', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      expect(form.allDay, isTrue);
      expect(form.startsLabel, isNull);
      expect(form.endsLabel, isNull);

      await form.setAllDay(false);
      expect(form.startsLabel, '9:00 AM');
      expect(form.endsLabel, 'No end time');
      expect(inForm(find.byTooltip('Remove end time')), findsNothing);
    });

    testWidgets('Starts and Ends follow the phone\'s clock', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);
      expect(form.startsLabel, '6:00 PM');
      expect(form.endsLabel, '7:30 PM · 1 h 30 min');
      await form.close();

      await openSheet(tester, draft: loaded, use24HourFormat: true);
      expect(form.startsLabel, '18:00');
      expect(form.endsLabel, '19:30 · 1 h 30 min');
    });

    testWidgets('an end on the next day says so in the row\'s label', (
      tester,
    ) async {
      String endsRowLabel() => tester
          .widget<FormPickerRow>(
            inForm(
              find.byWidgetPredicate(
                (widget) =>
                    widget is FormPickerRow &&
                    widget.identifier == SemanticsIds.templateEnds,
              ),
            ),
          )
          .label;
      final form = TemplateFormRobot(tester);
      await openSheet(
        tester,
        draft: plain.copyWith(
          time: const EventTime(startMinute: 22 * 60, durationMinutes: 60),
        ),
      );
      expect(endsRowLabel(), 'Ends');
      expect(form.endsLabel, '11:00 PM · 1 h');

      await form.pickEnd(const TimeOfDay(hour: 6, minute: 0));

      expect(endsRowLabel(), 'Ends next day');
      expect(form.endsLabel, '6:00 AM · 8 h');
    });

    testWidgets('the pads open as the editor\'s do: on the row\'s time, the '
        'end counted from the start', (tester) async {
      TimePadSheet pad() =>
          tester.widget<TimePadSheet>(find.byType(TimePadSheet));
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);

      await form.openStartPad();
      expect(pad().title, 'Start time');
      expect(pad().initialMinute, 18 * 60);
      expect(pad().periodAfter, isNull);
      // "Ends at…" while there is a duration to keep.
      expect(pad().caption, isNotNull);
      await cancelTimePad(tester);

      await form.openEndPad();
      expect(pad().title, 'End time');
      expect(pad().initialMinute, 19 * 60 + 30);
      expect(pad().periodAfter, 18 * 60);
      expect(pad().caption, isNotNull);
      await cancelTimePad(tester);
      expect(form.startsLabel, '6:00 PM');
      expect(form.endsLabel, '7:30 PM · 1 h 30 min');

      // With no end yet the start pad has nothing to keep, and the end pad
      // opens an hour after the start — past midnight folded back.
      await form.clearEnd();
      await form.pickStart(const TimeOfDay(hour: 23, minute: 30));
      await form.openStartPad();
      expect(pad().caption, isNull);
      await cancelTimePad(tester);
      await form.openEndPad();
      expect(pad().initialMinute, 30);
      expect(pad().periodAfter, 23 * 60 + 30);
      await cancelTimePad(tester);
    });
  });

  group('the Repeat sheet', () {
    EventRepeatSheet sheetOf(WidgetTester tester) =>
        tester.widget<EventRepeatSheet>(find.byType(EventRepeatSheet));

    Finder inRepeat(Finder matching) =>
        find.descendant(of: find.byType(EventRepeatSheet), matching: matching);

    testWidgets('it opens as the template variant, on the form\'s repeat', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      // Tall enough for the sheet's last row to be on screen.
      await openSheet(tester, draft: loaded, surface: const Size(412, 1600));

      await form.openRepeat();

      expect(sheetOf(tester).forTemplate, isTrue);
      expect(
        sheetOf(tester).draft,
        const EventRepeatDraft(
          recurring: true,
          kind: RepeatKind.weekly,
          interval: 2,
          weekdays: {DateTime.monday, DateTime.thursday},
          retroactive: true,
        ),
      );
      // A template has no holidays-only kind and no end date.
      expect(inRepeat(find.text('Public holidays only')), findsNothing);
      expect(inRepeat(find.text('Ends')), findsNothing);
      expect(
        inRepeat(
          find.text('Also on matching days before the day it is added'),
        ).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('the sheet is handed a default appearance, whatever the '
        'calendar\'s own is: the variant has no date picker to pass it to', (
      tester,
    ) async {
      final settings = await SettingsService.getInstance();
      await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
      await settings.setCalendarHighlightWeekends(true);
      // The setting really is off its default, or the sheet's default below
      // would prove nothing.
      expect(
        await settings.getCalendarAppearance(),
        isNot(const CalendarAppearance()),
      );
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded, surface: const Size(412, 1600));

      await form.openRepeat();

      expect(sheetOf(tester).appearance, const CalendarAppearance());
    });

    testWidgets('a rule that is not weekly reaches the sheet with no '
        'weekday, so Weekly waits for one', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(
        tester,
        draft: plain.copyWith(rule: const DailyRecurrence(interval: 3)),
      );

      await form.openRepeat();
      expect(
        sheetOf(tester).draft,
        const EventRepeatDraft(
          recurring: true,
          kind: RepeatKind.daily,
          interval: 3,
        ),
      );

      await form.chooseRepeat(TemplateRepeat.weekly);
      expect(form.canConfirmRepeat, isFalse);
      expect(
        inRepeat(find.text('Pick at least one weekday')).hitTestable(),
        findsOneWidget,
      );
      // Still Daily under the sheet: nothing was confirmed.
      expect(form.repeatLabel, 'Every 3 days');
    });

    testWidgets('a blank form opens it on Does not repeat', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      expect(form.repeatLabel, 'Does not repeat');
      await form.openRepeat();

      expect(sheetOf(tester).draft.recurring, isFalse);
      expect(sheetOf(tester).draft.weekdays, isEmpty);
      expect(sheetOf(tester).draft.retroactive, isFalse);
    });

    testWidgets('a confirmed repeat is read back on the row and stored', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');

      await form.chooseRepeat(TemplateRepeat.weekly);
      await form.toggleWeekday(DateTime.monday);
      expect(form.repeatLabel, 'Weekly · Mon');
      await form.toggleWeekday(DateTime.thursday);
      await form.stepInterval(up: true);
      expect(form.repeatLabel, 'Every 2 weeks · Mon, Thu');
      await form.chooseScope(retroactive: true);
      expect(form.repeatLabel, 'Every 2 weeks · Mon, Thu · also before');

      await form.save();
      expect(
        outcome.result?.rule,
        const WeeklyRecurrence(
          weekdays: {DateTime.monday, DateTime.thursday},
          interval: 2,
        ),
      );
      expect(outcome.result?.retroactive, isTrue);
    });

    for (final (repeat, label) in const [
      (TemplateRepeat.once, 'Does not repeat'),
      (TemplateRepeat.daily, 'Daily'),
      (TemplateRepeat.monthly, 'Monthly'),
      (TemplateRepeat.yearly, 'Yearly'),
      (TemplateRepeat.workdays, 'Workdays'),
      (TemplateRepeat.weekends, 'Weekends'),
    ]) {
      testWidgets('the row reads $label for the ${repeat.name} kind', (
        tester,
      ) async {
        final form = TemplateFormRobot(tester);
        await openSheet(tester, draft: plain);
        expect(form.repeatLabel, 'Weekly · Mon');

        await form.chooseRepeat(repeat);

        expect(form.repeatLabel, label);
      });
    }

    testWidgets('a cancelled Repeat sheet changes nothing', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: plain);

      await form.chooseRepeat(TemplateRepeat.daily, confirm: false);
      await form.stepInterval(up: true, confirm: false);
      await form.cancelRepeat();
      expect(form.repeatLabel, 'Weekly · Mon');
      expect(form.occurrencesVisible, isTrue);

      await form.tapClose();
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);
    });

    testWidgets('a weekly rule with no weekday that came with the template '
        'is written back as it came', (tester) async {
      const rule = WeeklyRecurrence(weekdays: {}, interval: 3);
      final existing = await service.create(plain.copyWith(rule: rule));
      expect(existing.rule, rule);

      final saved = await saveFrom(
        tester,
        initial: existing,
        edit: (form) async {
          expect(form.repeatLabel, 'Every 3 weeks');
          // The sheet can show it and cannot confirm it.
          await form.openRepeat();
          expect(form.canConfirmRepeat, isFalse);
          await form.cancelRepeat();
          await form.enterName('Renamed');
        },
      );

      expect(saved, existing.copyWith(name: 'Renamed'));
    });

    testWidgets('an interval above 99 is shown, kept by a Done that changed '
        'nothing, and kept by a change beside it', (tester) async {
      const rule = DailyRecurrence(interval: 150);
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(
        tester,
        draft: plain.copyWith(rule: rule),
      );
      expect(form.repeatLabel, 'Every 150 days');

      await form.openRepeat();
      expect(form.interval, 150);
      expect(form.canStepInterval(up: true), isFalse);
      expect(form.canStepInterval(up: false), isTrue);
      await form.confirmRepeat();
      expect(form.repeatLabel, 'Every 150 days');

      // Not a change: the form is as it opened.
      await form.tapClose();
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);

      final beside = await saveFrom(
        tester,
        draft: plain.copyWith(rule: rule),
        edit: (form) => form.chooseScope(retroactive: true),
      );
      expect(beside.rule, rule);
      expect(beside.retroactive, isTrue);
    });

    testWidgets('stepping an interval above 99 brings it into the sheet\'s '
        'range', (tester) async {
      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(rule: const DailyRecurrence(interval: 150)),
        edit: (form) async {
          await form.stepInterval(up: false);
          expect(form.interval, 99);
          expect(form.repeatLabel, 'Every 99 days');
        },
      );

      expect(saved.rule, const DailyRecurrence(interval: 99));
    });

    testWidgets('a rule a template cannot carry reads Does not repeat and '
        'opens the sheet on it', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(
        tester,
        draft: loaded.copyWith(rule: const PublicHolidaysOnlyRecurrence()),
      );

      expect(form.repeatLabel, 'Does not repeat');
      expect(form.occurrencesVisible, isFalse);
      await form.openRepeat();
      expect(sheetOf(tester).draft.recurring, isFalse);
      // What the draft held for a repeating rule is parked, not lost.
      expect(sheetOf(tester).draft.retroactive, isTrue);
    });
  });

  group('occurrences', () {
    testWidgets('the group is there only while the rule repeats', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester);

      expect(form.occurrencesVisible, isFalse);
      expect(sectionsOf(tester), ['When', 'Details']);

      await form.chooseRepeat(TemplateRepeat.daily);
      expect(form.occurrencesVisible, isTrue);
      expect(sectionsOf(tester), ['When', 'Occurrences', 'Details']);

      await form.chooseRepeat(TemplateRepeat.once);
      expect(form.occurrencesVisible, isFalse);
      expect(sectionsOf(tester), ['When', 'Details']);
    });

    testWidgets('what the group held is parked across One time and comes '
        'back as it was', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      await form.chooseRepeat(TemplateRepeat.daily);
      await form.setCountOccurrences(true);
      await form.chooseCountStyle(OccurrenceCountStyle.elapsed);
      await form.setTrackPresence(true);
      await form.chooseAssume(absent: true);
      await form.setPerDay(true);

      await form.chooseRepeat(TemplateRepeat.once);
      expect(form.occurrencesVisible, isFalse);

      await form.chooseRepeat(TemplateRepeat.monthly);
      expect(form.countsOccurrences, isTrue);
      expect(form.countStyle, OccurrenceCountStyle.elapsed);
      expect(form.tracksPresence, isTrue);
      expect(form.assumesAbsent, isTrue);
      expect(form.perDay, isTrue);

      await form.save();
      expect(outcome.result?.countOccurrences, isTrue);
      expect(outcome.result?.countStyle, OccurrenceCountStyle.elapsed);
      expect(outcome.result?.tracksPresence, isTrue);
      expect(outcome.result?.assumeAbsent, isTrue);
      expect(outcome.result?.perOccurrenceDescriptions, isTrue);
    });

    testWidgets('a parked Count occurrences sits out Workdays and comes back '
        'with a kind that can count', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      await form.chooseRepeat(TemplateRepeat.daily);
      await form.setCountOccurrences(true);

      await form.chooseRepeat(TemplateRepeat.workdays);
      expect(form.countOccurrencesVisible, isFalse);
      expect(form.occurrencesVisible, isTrue);

      await form.chooseRepeat(TemplateRepeat.yearly);
      expect(form.countsOccurrences, isTrue);

      await form.save();
      expect(outcome.result?.countOccurrences, isTrue);
    });

    testWidgets('the count-style chips come with the switch, on the kind\'s '
        'own style, with the first three labels under them', (tester) async {
      String example() =>
          tester.widget<FormCaption>(inForm(find.byType(FormCaption))).text;
      final form = TemplateFormRobot(tester);
      await openSheet(tester);
      await form.chooseRepeat(TemplateRepeat.daily);
      await form.cancelRepeat();

      expect(form.countStyle, isNull);
      await form.setCountOccurrences(true);
      expect(form.countStyle, OccurrenceCountStyle.numbered);
      expect(example(), 'Day 1 · Day 2 · Day 3');

      await form.chooseCountStyle(OccurrenceCountStyle.elapsed);
      expect(form.countStyle, OccurrenceCountStyle.elapsed);
      expect(example(), '0 days · 1 day · 2 days');

      await form.setCountOccurrences(false);
      expect(form.countStyle, isNull);
      expect(inForm(find.byType(FormCaption)), findsNothing);
    });

    testWidgets('the style follows the kind until one is picked, and is kept '
        'from then on', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester);
      await form.enterName('Push day');
      await form.chooseRepeat(TemplateRepeat.daily);
      await form.setCountOccurrences(true);
      expect(form.countStyle, OccurrenceCountStyle.numbered);

      await form.chooseRepeat(TemplateRepeat.yearly);
      expect(form.countStyle, OccurrenceCountStyle.elapsed);
      await form.chooseRepeat(TemplateRepeat.monthly);
      expect(form.countStyle, OccurrenceCountStyle.numbered);

      await form.chooseCountStyle(OccurrenceCountStyle.numbered);
      await form.chooseRepeat(TemplateRepeat.yearly);
      expect(form.countStyle, OccurrenceCountStyle.numbered);

      await form.save();
      expect(outcome.result?.rule, const YearlyRecurrence());
      expect(outcome.result?.countStyle, OccurrenceCountStyle.numbered);
    });

    testWidgets('a template that came counting keeps its style across kinds', (
      tester,
    ) async {
      final saved = await saveFrom(
        tester,
        draft: plain.copyWith(
          rule: const DailyRecurrence(),
          countOccurrences: true,
          countStyle: OccurrenceCountStyle.elapsed,
        ),
        edit: (form) async {
          expect(form.countStyle, OccurrenceCountStyle.elapsed);
          await form.chooseRepeat(TemplateRepeat.monthly);
          expect(form.countStyle, OccurrenceCountStyle.elapsed);
        },
      );

      expect(saved.countStyle, OccurrenceCountStyle.elapsed);
    });

    testWidgets('a yearly template that came without counting counts from 0 '
        'once switched on, and keeps its stored style while it is off', (
      tester,
    ) async {
      final yearly = plain.copyWith(rule: const YearlyRecurrence());
      final existing = await service.create(yearly);
      expect(existing.countStyle, OccurrenceCountStyle.numbered);

      final untouched = await saveFrom(tester, initial: existing);
      expect(untouched, existing);

      final counting = await saveFrom(
        tester,
        initial: existing,
        edit: (form) async {
          await form.setCountOccurrences(true);
          expect(form.countStyle, OccurrenceCountStyle.elapsed);
        },
      );
      expect(counting.countOccurrences, isTrue);
      expect(counting.countStyle, OccurrenceCountStyle.elapsed);
    });

    testWidgets('Count occurrences switched on and off again writes back '
        'what it read', (tester) async {
      final existing = await service.create(
        plain.copyWith(rule: const YearlyRecurrence()),
      );
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, initial: existing);

      await form.setCountOccurrences(true);
      await form.setCountOccurrences(false);
      await form.tapClose();

      // The style shown while it was on was never written into the form.
      expect(form.discardPromptShown, isFalse);
      expect(outcome.returned, isTrue);
    });

    testWidgets('the presence default is offered only while presence is '
        'tracked, and opens on Assume present', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: plain);

      expect(form.assumesAbsent, isNull);
      await form.setTrackPresence(true);
      expect(form.assumesAbsent, isFalse);
      await form.chooseAssume(absent: true);
      expect(form.assumesAbsent, isTrue);

      await form.setTrackPresence(false);
      expect(form.assumesAbsent, isNull);
      // Parked with its switch, like every repeat-only choice.
      await form.setTrackPresence(true);
      expect(form.assumesAbsent, isTrue);
    });
  });

  group('focus', () {
    final pickers =
        <String, (Future<void> Function(TemplateFormRobot form), Type)>{
          'the category picker': (
            (form) => form.openCategoryPicker(),
            CategoryPickerSheet,
          ),
          'the Icon & color sheet': ((form) => form.openLook(), EventLookSheet),
          'the description sheet': (
            (form) => form.openDescription(),
            EventDescriptionSheet,
          ),
          'the start pad': ((form) => form.openStartPad(), TimePadSheet),
          'the end pad': ((form) => form.openEndPad(), TimePadSheet),
          'the Repeat sheet': ((form) => form.openRepeat(), EventRepeatSheet),
        };
    for (final MapEntry(key: name, value: (open, type)) in pickers.entries) {
      testWidgets('focus is dropped before $name opens, and is not handed '
          'back when it closes', (tester) async {
        final form = TemplateFormRobot(tester);
        await openSheet(tester, draft: loaded);
        await form.focusName();
        expect(form.nameFocused, isTrue);

        await open(form);
        expect(find.byType(type), findsOneWidget);
        expect(form.nameFocused, isFalse);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(type), findsNothing);
        expect(form.isOpen, isTrue);
        expect(form.nameFocused, isFalse);
      });
    }

    testWidgets('focus is dropped before the Priority menu opens, and is not '
        'handed back when it closes', (tester) async {
      final form = TemplateFormRobot(tester);
      await openSheet(tester, draft: loaded);
      await form.focusName();
      expect(form.nameFocused, isTrue);

      await form.openPriorityMenu();
      expect(byId(SemanticsIds.templatePriorityItem(1)), findsOneWidget);
      expect(form.nameFocused, isFalse);

      await tester.tap(byId(SemanticsIds.templatePriorityItem(5)));
      await tester.pumpAndSettle();
      expect(form.priorityLabel, 'Lowest');
      expect(form.nameFocused, isFalse);
    });
  });

  group('ids and layout', () {
    const rowIds = [
      SemanticsIds.templateName,
      SemanticsIds.templateCategory,
      SemanticsIds.templateLook,
      SemanticsIds.templateDescription,
      SemanticsIds.templateAllDay,
      SemanticsIds.templateStarts,
      SemanticsIds.templateEnds,
      SemanticsIds.templateEndsClear,
      SemanticsIds.templateRepeat,
      SemanticsIds.templateCount,
      SemanticsIds.templateCountStyleNumbered,
      SemanticsIds.templateCountStyleElapsed,
      SemanticsIds.templatePresence,
      SemanticsIds.templateAssumePresent,
      SemanticsIds.templateAssumeAbsent,
      SemanticsIds.templatePerDay,
      SemanticsIds.templatePriority,
    ];

    testWidgets('every control carries its id, one node to a row', (
      tester,
    ) async {
      final form = TemplateFormRobot(tester);
      // Tall enough for every row to be on screen, where its node exists.
      await openSheet(tester, draft: loaded, surface: const Size(412, 1800));

      for (final id in [
        SemanticsIds.templateClose,
        SemanticsIds.templateSave,
        ...rowIds,
      ]) {
        expect(byId(id), findsOneWidget, reason: id);
        expect(dataOf(tester, id).identifier, id);
      }
      // A row is one announcement: its label and what it reads.
      for (final MapEntry(key: id, value: parts) in const {
        SemanticsIds.templateCategory: ['Category', 'Cardio'],
        SemanticsIds.templateLook: ['Icon & color', 'Custom'],
        SemanticsIds.templateStarts: ['Starts', '6:00 PM'],
        SemanticsIds.templateEnds: ['Ends', '7:30 PM · 1 h 30 min'],
        SemanticsIds.templateRepeat: [
          'Repeat',
          'Every 2 weeks · Mon, Thu · also before',
        ],
        SemanticsIds.templatePriority: ['Priority', 'Highest'],
      }.entries) {
        final data = dataOf(tester, id);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: id);
        for (final part in parts) {
          expect(data.label, contains(part), reason: id);
        }
      }
      for (final MapEntry(key: id, value: label) in const {
        SemanticsIds.templateAllDay: 'All day',
        SemanticsIds.templateCount: 'Count occurrences',
        SemanticsIds.templatePresence: 'Track presence',
        SemanticsIds.templatePerDay: 'Separate description per day',
      }.entries) {
        expect(dataOf(tester, id).label, label, reason: id);
      }
      // The end's clear button is the row's second target, with its own name.
      expect(
        dataOf(tester, SemanticsIds.templateEndsClear).tooltip,
        'Remove end time',
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.templateCountStyleElapsed,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.templateAssumeAbsent,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      await form.openPriorityMenu();
      for (var p = 1; p <= 5; p++) {
        final id = SemanticsIds.templatePriorityItem(p);
        expect(byId(id), findsOneWidget, reason: id);
        expect(
          dataOf(tester, id).flagsCollection.isChecked,
          p == loaded.priority ? CheckedState.isTrue : CheckedState.isFalse,
          reason: id,
        );
      }
    });

    testWidgets('on a 360 × 780 phone nothing overflows and every control '
        'keeps a 48 dp target', (tester) async {
      await openSheet(tester, draft: loaded, surface: phone);

      expect(tester.takeException(), isNull);
      expect(formHeight(tester), phone.height * FormMetrics.sheetHeightFactor);
      for (final id in rowIds) {
        await reveal(tester, id);
        expect(tester.takeException(), isNull, reason: id);
        // The name's id is on its field, one text line; its target is the
        // row around it, which hands a tap anywhere in it to the field.
        final rect = id == SemanticsIds.templateName
            ? tester.getRect(
                find
                    .descendant(
                      of: inForm(find.byType(FormTitleRow)),
                      matching: find.byType(GestureDetector),
                    )
                    .first,
              )
            : tester.getRect(byId(id));
        expect(
          rect.height,
          greaterThanOrEqualTo(FormMetrics.rowMinHeight),
          reason: id,
        );
        expect(
          rect.left,
          greaterThanOrEqualTo(RowMetrics.groupInset),
          reason: id,
        );
        expect(
          rect.right,
          lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
          reason: id,
        );
      }
      expect(
        tester.getSize(inForm(find.byType(FormTitleRow))).height,
        greaterThanOrEqualTo(FormMetrics.titleRowMinHeight),
      );
      expect(
        tester.getSize(byId(SemanticsIds.templateClose)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(byId(SemanticsIds.templateSave)).height,
        FormMetrics.headerHeight,
      );
    });

    testWidgets('the keyboard\'s inset pads the scroll view and never the '
        'sheet: the header stays in reach', (tester) async {
      final form = TemplateFormRobot(tester);
      final outcome = await openSheet(tester, draft: plain, surface: phone);
      double bodyBottomPadding() => tester
          .widget<SingleChildScrollView>(
            inForm(find.byType(SingleChildScrollView)),
          )
          .padding!
          .resolve(TextDirection.ltr)
          .bottom;
      expect(bodyBottomPadding(), FormMetrics.bodyBottom);
      final height = formHeight(tester);

      const keyboard = 320.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(bodyBottomPadding(), FormMetrics.bodyBottom + keyboard);
      expect(formHeight(tester), height);
      // The header is the sheet's first child, above the scroll view the
      // inset pads.
      await form.save();
      expect(outcome.result, isNotNull);
    });

    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out '
        'without overflow and every label reads whole', (tester) async {
      final form = TemplateFormRobot(tester);
      // Every week, not every two: the Repeat sheet is opened below, and its
      // stepper is the Repeat sheet's own to lay out — its suite drives it
      // at this scale, interval by interval. Here it only has to open.
      final outcome = await openSheet(
        tester,
        draft: loaded.copyWith(
          clearDescription: true,
          rule: const WeeklyRecurrence(
            weekdays: {DateTime.monday, DateTime.thursday},
          ),
        ),
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(formHeight(tester), phone.height * FormMetrics.sheetHeightFactor);
      expect(
        tester
            .widget<FormSheetHeader>(inForm(find.byType(FormSheetHeader)))
            .title,
        'Neue Vorlage',
      );
      expect(
        tester
            .widget<FormHeaderTextButton>(
              inForm(find.byType(FormHeaderTextButton)),
            )
            .label,
        'Speichern',
      );

      // A label wraps as far as it needs to and is never cut: no line limit,
      // a box as tall as its text, inside the group. The chips are in the
      // list — a chip's 32 dp is a minimum.
      for (final label in [
        'Kategorie',
        'Symbol & Farbe',
        'Beschreibung hinzufügen',
        'Ganztägig',
        'Beginn',
        'Ende',
        'Wiederholung',
        'Wiederholungen zählen',
        'Ab 1 zählen',
        'Ab 0 zählen',
        'Anwesenheit erfassen',
        'Als besucht',
        'Als verpasst',
        'Eigene Beschreibung pro Tag',
        'Priorität',
      ]) {
        final text = inForm(find.text(label));
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        expect(tester.widget<Text>(text).maxLines, isNull, reason: label);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          paragraph.size.height,
          moreOrLessEquals(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width),
            epsilon: 0.01,
          ),
          reason: label,
        );
        final rect = tester.getRect(text);
        expect(
          rect.left,
          greaterThanOrEqualTo(RowMetrics.groupInset),
          reason: label,
        );
        expect(
          rect.right,
          lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
          reason: label,
        );
      }
      expect(sectionsOf(tester), ['Wann', 'Vorkommen', 'Details']);
      for (final chip in inForm(find.byType(FormChip)).evaluate()) {
        expect(
          tester.getSize(find.byWidget(chip.widget)).height,
          greaterThanOrEqualTo(FormMetrics.chipTapTarget),
        );
      }

      // The sub-sheets open and close at this scale as well, and Save still
      // reports the template.
      await form.openRepeat();
      expect(tester.takeException(), isNull);
      await form.cancelRepeat();
      await form.openStartPad();
      expect(tester.takeException(), isNull);
      await cancelTimePad(tester);
      await form.openLook();
      expect(tester.takeException(), isNull);
      await form.cancelLook();
      await form.save();
      expect(tester.takeException(), isNull);
      expect(outcome.result?.name, loaded.name);
    });

    testWidgets('en, de and ro at 1.0, 1.3 and 2.0 on both phone sizes, '
        'light and dark: nothing overflows, top to bottom', (tester) async {
      final themes = [AppTheme.light(), AppTheme.dark()];
      for (final surface in const [phone, Size(412, 915)]) {
        for (final locale in AppLocalizations.supportedLocales) {
          for (final textScale in const [1.0, 1.3, 2.0]) {
            for (final theme in themes) {
              final state =
                  '$locale at $textScale on ${surface.width.round()} dp, '
                  '${theme.brightness.name}';
              final form = TemplateFormRobot(tester);
              await openSheet(
                tester,
                draft: loaded,
                surface: surface,
                locale: locale,
                textScale: textScale,
                theme: theme,
              );
              expect(tester.takeException(), isNull, reason: state);
              expect(
                formHeight(tester),
                surface.height * FormMetrics.sheetHeightFactor,
                reason: state,
              );

              // Down to the last row, through every group on the way.
              for (final id in [
                SemanticsIds.templateEnds,
                SemanticsIds.templateAssumeAbsent,
                SemanticsIds.templatePriority,
              ]) {
                await reveal(tester, id);
                expect(tester.takeException(), isNull, reason: '$state, $id');
                expect(
                  tester.getRect(byId(id)).right,
                  lessThanOrEqualTo(surface.width - RowMetrics.groupInset),
                  reason: '$state, $id',
                );
              }
              await form.close();
              expect(form.isOpen, isFalse, reason: state);
            }
          }
        }
      }
    });
  });

  group('the callers', () {
    Future<void> pumpApp(WidgetTester tester, Widget home) async {
      await tester.pumpWidget(
        BlocProvider<MarkdownBarBloc>.value(
          value: barBloc,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: home,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the templates page creates through the form and lists what '
        'it saved', (tester) async {
      final form = TemplateFormRobot(tester);
      await pumpApp(tester, const EventTemplatesPage());
      expect(find.text('No templates yet'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(form.isOpen, isTrue);
      await form.enterName('Push day');
      await form.save();

      expect(form.isOpen, isFalse);
      expect(service.templates.single.name, 'Push day');
      expect(find.widgetWithText(ListTile, 'Push day'), findsOneWidget);
    });

    testWidgets('the templates page edits a template in the form; a form '
        'left through the ✕ leaves the list as it was', (tester) async {
      final existing = await service.create(loaded);
      final form = TemplateFormRobot(tester);
      await pumpApp(tester, const EventTemplatesPage());

      await tester.tap(find.widgetWithText(ListTile, 'Leg day'));
      await tester.pumpAndSettle();
      expect(form.name, 'Leg day');
      await form.enterName('Deadlift day');
      await form.close();
      expect(find.widgetWithText(ListTile, 'Leg day'), findsOneWidget);
      expect(service.templates, [existing]);

      await tester.tap(find.widgetWithText(ListTile, 'Leg day'));
      await tester.pumpAndSettle();
      await form.enterName('Deadlift day');
      await form.save();

      expect(find.widgetWithText(ListTile, 'Deadlift day'), findsOneWidget);
      expect(service.templates, [existing.copyWith(name: 'Deadlift day')]);
    });

    testWidgets('the event editor\'s Save as template hands the form its '
        'draft, and stays open under it', (tester) async {
      final form = TemplateFormRobot(tester);
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => EventEditorSheet.show(
                context,
                defaultDate: DateTime.utc(2026, 9, 25),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(EventEditorSheet),
          matching: find.byType(EditableText),
        ),
        'Leg day',
      );
      await tester.pumpAndSettle();

      final action = find.widgetWithText(FormActionRow, 'Save as template');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();

      // A draft: named, not focused, and clean — the ✕ would leave at once.
      expect(form.isOpen, isTrue);
      expect(form.name, 'Leg day');
      expect(form.nameFocused, isFalse);
      expect(form.repeatLabel, 'Does not repeat');
      await form.save();

      expect(form.isOpen, isFalse);
      expect(service.templates.single.name, 'Leg day');
      expect(service.templates.single.rule, const OneTimeRecurrence());
      expect(find.text('Template saved'), findsOneWidget);
      expect(find.byType(EventEditorSheet), findsOneWidget);
    });

    testWidgets('the Template saved confirmation is painted above the editor '
        'sheet, where a finger can reach it', (tester) async {
      final form = TemplateFormRobot(tester);
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => EventEditorSheet.show(
                context,
                defaultDate: DateTime.utc(2026, 9, 25),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(EventEditorSheet),
          matching: find.byType(EditableText),
        ),
        'Leg day',
      );
      await tester.pumpAndSettle();
      final action = find.widgetWithText(FormActionRow, 'Save as template');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      await form.save();

      // A bar on the page's `Scaffold` is drawn under the sheet, a route
      // above that page: a hit test at the message finds the sheet instead.
      // Raised in the overlay, the message is the topmost thing where it
      // stands, with the editor still open under it.
      final message = find.text('Template saved');
      expect(message.hitTestable(), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.ancestor(of: message, matching: find.byType(EventEditorSheet)),
        findsNothing,
      );
      expect(find.byType(EventEditorSheet), findsOneWidget);
      expect(
        tester.getRect(message).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(EventEditorSheet)).bottom),
      );
    });
  });
}

class _Outcome {
  EventTemplate? result;
  bool returned = false;
}

/// Holds or refuses the write of a template row, so a test can look at the
/// form while a save is in flight and after one has failed — the two states a
/// real store reaches only by being slow or broken. It can hold the read of a
/// setting the same way, for the moment a form is open before its settings
/// have arrived.
class _TemplateWrites extends QueryInterceptor {
  /// While set and not completed, a template write waits for it.
  Completer<void>? hold;

  /// While true, a template write throws instead of reaching the database.
  bool refuse = false;

  /// While set and not completed, a read of the settings waits for it.
  Completer<void>? holdSettings;

  Future<void> _gate(String statement) async {
    if (!statement.contains('calendar_event_templates')) return;
    if (refuse) throw StateError('write refused');
    await hold?.future;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.contains('user_settings')) await holdSettings?.future;
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await _gate(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await _gate(statement);
    return super.runUpdate(executor, statement, args);
  }
}
