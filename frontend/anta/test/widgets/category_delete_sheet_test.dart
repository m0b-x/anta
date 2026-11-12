import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart' show kFallbackCategoryId;
import 'package:anta/models/category_alert.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/category_delete_robot.dart';

/// The delete sheet (decision C1 of `docs/calendar-categories-roadmap.md`)
/// over the real service and DAO on `NativeDatabase.memory()`: what earns a
/// case is what the user is told before the delete — the counts, where the
/// events go, what else changes — that only Delete writes, with the target
/// the user chose, and pops what the DAO answered, and that nothing under
/// the finger moves from the first frame on. Roboto is loaded, so the large
/// text cases are measured as a phone draws them.
void main() {
  late AppDatabase db;
  late CategoryService service;
  late _ReadGate gate;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    CategoryService.reset();
    gate = _ReadGate();
    db = await openTestDatabase(interceptor: gate);
    service = await CategoryService.forTesting(db);
  });

  tearDown(() async {
    gate.release();
    EventAlertService.reset();
    CategoryService.reset();
    await db.close();
  });

  Future<CalendarCategory> custom(String name) =>
      service.create(name: name, colorValue: 0xFF112233, iconKey: 'event');

  Future<void> addEvents(String categoryId, int count) async {
    for (var i = 0; i < count; i++) {
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: '$categoryId-e$i',
          title: 'Event $i',
          category: categoryId,
          startDate: DateTime.utc(2026, 8, 1),
          ruleKind: 'oneTime',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> addTemplates(String categoryId, int count) async {
    for (var i = 0; i < count; i++) {
      await db.eventTemplateDao.upsertTemplate(
        EventTemplatesCompanion(
          id: Value('$categoryId-t$i'),
          name: Value('Template $i'),
          category: Value(categoryId),
          sortOrder: Value(i),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<void> addAlerts(String categoryId, int count) async {
    final alerts = await EventAlertService.forTesting(db);
    await alerts.replaceForCategory(categoryId, [
      for (var i = 0; i < count; i++)
        CategoryAlert(id: '$categoryId-a$i', categoryId: categoryId),
    ]);
  }

  /// A category with all three segments in its counts line.
  Future<CalendarCategory> threeSegments(String name) async {
    final category = await custom(name);
    await addEvents(category.id, 12);
    await addAlerts(category.id, 3);
    await addTemplates(category.id, 2);
    return category;
  }

  Future<CalendarCategoryRow> rowOf(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => db.calendarCategoryDao.getByIdsIncludingDeleted([id]),
      ))!.single;

  const phone = Size(360, 780);

  group('the impact caption', () {
    testWidgets('names events, alerts and templates', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 2);
      await addAlerts(dentist.id, 2);
      await addTemplates(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(robot.impactCaption, '2 events · 2 alerts · 1 template');
    });

    testWidgets('omits the alerts at zero', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      await addTemplates(dentist.id, 2);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(robot.impactCaption, '1 event · 2 templates');
    });

    testWidgets('omits the templates at zero', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 3);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(robot.impactCaption, '3 events');
    });

    testWidgets('always says the events, "No events" at zero', (tester) async {
      final dentist = await custom('Dentist');
      await addAlerts(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(robot.impactCaption, 'No events · 1 alert');
    });

    testWidgets('German at 2.0 breaks only after a dot, never inside a '
        'segment', (tester) async {
      final dentist = await threeSegments('Zahnarzttermine');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: dentist,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );

      final paragraph = robot.captionParagraph;
      final text = paragraph.text.toPlainText();
      Set<double> linesOf(int start, int end) => {
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        ))
          box.top,
      };
      expect(
        linesOf(0, text.length).length,
        greaterThan(1),
        reason: 'the case must wrap to say anything',
      );
      // The no-break space and the dot the segments are joined with.
      final separator = '${String.fromCharCode(0xA0)}· ';
      var start = 0;
      for (final segment in text.split(separator)) {
        expect(
          linesOf(start, start + segment.length),
          hasLength(1),
          reason: '"$segment" was split',
        );
        start += segment.length + separator.length;
      }
      for (var i = text.indexOf('·'); i != -1; i = text.indexOf('·', i + 1)) {
        expect(
          linesOf(i - 1, i + 1),
          hasLength(1),
          reason: 'a line starts with the dot at $i',
        );
      }
    });
  });

  group('the Move row', () {
    testWidgets('is disabled in place with nothing to move', (tester) async {
      final dentist = await custom('Dentist');
      await addAlerts(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(robot.target, findsOneWidget);
      expect(robot.moveEnabled, isFalse);
      expect(robot.targetLabel, 'Other');
      expect(robot.deleteEnabled, isTrue);
    });

    testWidgets('is enabled for templates alone', (tester) async {
      final dentist = await custom('Dentist');
      await addTemplates(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(robot.moveEnabled, isTrue);
    });

    testWidgets('picks a target that never offers the deleted category', (
      tester,
    ) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);
      expect(robot.moveEnabled, isTrue);
      expect(robot.targetLabel, 'Other');

      await robot.openPicker();
      expect(robot.pickerOffers('Gym'), isTrue);
      expect(robot.pickerOffers('Dentist'), isFalse);
      await robot.pick('Gym');

      expect(robot.isOpen, isTrue);
      expect(robot.targetLabel, 'Gym');
    });

    testWidgets('flashes once after the picker closes itself', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);
      expect(robot.moveFlashes, isFalse, reason: 'an opened row never flashes');

      await robot.openPicker();
      await robot.pick('Gym', settle: false);
      var flashed = false;
      for (var i = 0; i < 20 && !flashed; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        flashed = robot.moveFlashes;
      }
      expect(flashed, isTrue, reason: 'the written row flashes');

      await tester.pumpAndSettle();
      expect(robot.moveFlashes, isFalse, reason: 'and the flash fades');
      expect(robot.targetLabel, 'Gym');
    });
  });

  group('Delete', () {
    testWidgets('moves the events and templates to the chosen target and '
        'pops true', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 2);
      await addTemplates(dentist.id, 1);
      await addAlerts(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);
      await robot.openPicker();
      await robot.pick('Gym');

      await robot.confirm();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isTrue);
      expect(robot.isOpen, isFalse);
      final events = (await tester.runAsync(db.calendarEventDao.getAll))!;
      expect(
        {
          for (final row in events)
            if (row.id.startsWith(dentist.id)) row.id: row.category,
        },
        {'${dentist.id}-e0': 'gym', '${dentist.id}-e1': 'gym'},
      );
      final templates = (await tester.runAsync(db.eventTemplateDao.getAll))!;
      expect(templates.single.category, 'gym');
      final alerts = (await tester.runAsync(db.categoryAlertDao.getAllActive))!;
      expect(alerts.where((a) => a.categoryId == dentist.id), isEmpty);
      expect((await rowOf(tester, dentist.id)).isDeleted, isTrue);
    });

    testWidgets('with no pick moves the events to Other', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);

      await robot.confirm();

      expect(outcome.result, isTrue);
      final events = (await tester.runAsync(db.calendarEventDao.getAll))!;
      expect(events.single.category, kFallbackCategoryId);
    });

    testWidgets('pops false when the category is already gone', (tester) async {
      final dentist = await custom('Dentist');
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);
      // A pull deleted it while the sheet was up.
      await tester.runAsync(() => service.deleteCategory(dentist.id));
      await tester.pump();

      await robot.confirm();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isFalse);
    });

    testWidgets('while it runs, Delete and ✕ are disabled and neither the '
        'barrier nor back leaves', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);
      gate.holdNext('calendar_categories');

      await robot.tapDelete();
      await tester.pump(const Duration(milliseconds: 100));

      expect(gate.held, isTrue);
      expect(robot.isOpen, isTrue);
      expect(robot.deleteEnabled, isFalse);
      expect(robot.closeEnabled, isFalse);
      expect(robot.close, findsOneWidget, reason: 'disabled, never hidden');
      expect(robot.moveEnabled, isFalse);
      await robot.tapBarrier();
      expect(robot.isOpen, isTrue, reason: 'the barrier left mid-write');
      await robot.systemBack();
      expect(robot.isOpen, isTrue, reason: 'back left mid-write');
      expect(outcome.returned, isFalse);

      gate.release();
      await robot.settleWrites();

      expect(outcome.returned, isTrue);
      expect(outcome.result, isTrue);
      expect(robot.isOpen, isFalse);
    });

    testWidgets('a failed write keeps the sheet, says so in the overlay and '
        'gives Delete back', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);
      gate.failNext('calendar_categories');

      await robot.confirm();

      expect(robot.isOpen, isTrue);
      expect(outcome.returned, isFalse);
      expect(find.text(robot.l10n.categoryChangeFailed), findsOneWidget);
      expect(robot.deleteEnabled, isTrue);
      expect(robot.closeEnabled, isTrue);
      expect((await rowOf(tester, dentist.id)).isDeleted, isFalse);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('leaving', () {
    Future<void> expectUntouched(
      WidgetTester tester,
      CalendarCategoryRow before,
      CategoryDeleteOutcome outcome,
    ) async {
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(find.byType(AlertDialog), findsNothing, reason: 'it never asks');
      final after = await rowOf(tester, before.id);
      expect(after.isDeleted, isFalse);
      expect(after.version, before.version);
      expect(CalendarCategories.byId(before.id), isNotNull);
    }

    testWidgets('✕ pops null and writes nothing', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final before = await rowOf(tester, dentist.id);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);

      await robot.tapClose();

      await expectUntouched(tester, before, outcome);
    });

    testWidgets('the barrier pops null and writes nothing', (tester) async {
      final dentist = await custom('Dentist');
      final before = await rowOf(tester, dentist.id);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);

      await robot.tapBarrier();

      await expectUntouched(tester, before, outcome);
    });

    testWidgets('system back pops null and writes nothing', (tester) async {
      final dentist = await custom('Dentist');
      final before = await rowOf(tester, dentist.id);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);

      await robot.systemBack();

      await expectUntouched(tester, before, outcome);
    });

    testWidgets('a drag down pops null and writes nothing', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final before = await rowOf(tester, dentist.id);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);

      await robot.dragDown();

      expect(robot.isOpen, isFalse);
      await expectUntouched(tester, before, outcome);
      final events = (await tester.runAsync(db.calendarEventDao.getAll))!;
      expect(events.single.category, dentist.id);
    });

    testWidgets('a picked target is dropped with the sheet', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final before = await rowOf(tester, dentist.id);
      final robot = CategoryDeleteRobot(tester);
      final outcome = await robot.show(category: dentist);
      await robot.openPicker();
      await robot.pick('Gym');

      await robot.tapClose();

      await expectUntouched(tester, before, outcome);
      final events = (await tester.runAsync(db.calendarEventDao.getAll))!;
      expect(events.single.category, dentist.id);
    });

    testWidgets('counts that cannot be read open nothing and say so on the '
        'page', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final before = await rowOf(tester, dentist.id);
      gate.failNext('calendar_event_templates');
      final robot = CategoryDeleteRobot(tester);

      final outcome = await robot.show(category: dentist);

      expect(robot.isOpen, isFalse);
      expect(outcome.returned, isTrue);
      expect(outcome.result, isNull);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            lookupAppLocalizations(const Locale('en')).categoryChangeFailed,
          ),
        ),
        findsOneWidget,
      );
      expect((await rowOf(tester, dentist.id)).version, before.version);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('the consequences caption', () {
    testWidgets('says only the views with no alerts and no templates', (
      tester,
    ) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(
        robot.consequences,
        'Saved views, digests and reports that pick only Dentist show '
        'nothing until you pick again.',
      );
    });

    testWidgets('says the alerts only when there are some', (tester) async {
      final dentist = await custom('Dentist');
      await addAlerts(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist);

      expect(
        robot.consequences,
        'Its alerts are removed. Saved views, digests and reports that pick '
        'only Dentist show nothing until you pick again.',
      );
    });

    testWidgets('leads with the templates, then the alerts, at the same '
        'height', (tester) async {
      final plain = await custom('Dentist');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: plain);
      final height = robot.consequencesHeight;
      await robot.tapClose();

      final withBoth = await custom('Doctor');
      await addTemplates(withBoth.id, 2);
      await addAlerts(withBoth.id, 1);
      await robot.show(category: withBoth);

      expect(
        robot.consequences,
        'Its templates move with the events. Its alerts are removed. Saved '
        'views, digests and reports that pick only Doctor show nothing until '
        'you pick again.',
      );
      expect(robot.consequencesHeight, height);
    });

    testWidgets('German at 2.0 keeps one height with nothing and with '
        'templates and alerts', (tester) async {
      // One category, so the name inside the caption is the same text both
      // times: only what the counts add may differ.
      final dentist = await custom('Zahnarzt');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: dentist,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );
      final height = robot.consequencesHeight;
      expect(
        robot.consequences,
        startsWith('Gespeicherte Ansichten'),
        reason: 'neither the templates nor the alerts sentence',
      );
      await robot.tapClose();

      await addTemplates(dentist.id, 2);
      await addAlerts(dentist.id, 1);
      await robot.show(
        category: dentist,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );

      expect(
        robot.consequences,
        startsWith(
          'Die Vorlagen der Kategorie werden mit den Ereignissen verschoben. '
          'Die Erinnerungen der Kategorie werden entfernt.',
        ),
      );
      expect(robot.consequencesHeight, height);
      expect(tester.takeException(), isNull);
    });
  });

  group('layout', () {
    testWidgets('✕, Delete and the Move row are 48 dp targets', (tester) async {
      final dentist = await custom('Dentist');
      await addEvents(dentist.id, 1);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist, surface: phone);

      for (final target in [robot.close, robot.delete]) {
        final size = robot.sizeOf(target);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(robot.sizeOf(robot.target).height, greaterThanOrEqualTo(48));
      expect(robot.sizeOf(robot.target).width, greaterThanOrEqualTo(48));
    });

    testWidgets('the header and the Move row hold still from the first frame '
        'through a pick', (tester) async {
      final dentist = await threeSegments('Dentist');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: dentist,
        textScale: 2.0,
        surface: phone,
        settle: false,
      );
      expect(robot.isOpen, isTrue);
      expect(robot.impactCaption, '12 events · 3 alerts · 2 templates');
      final header = robot.inSheet(robot.header);
      final move = robot.inSheet(robot.target);

      await tester.pumpAndSettle();
      expect(robot.inSheet(robot.header), header);
      expect(robot.inSheet(robot.target), move);

      await robot.openPicker();
      await robot.pick('Gym');

      expect(robot.targetLabel, 'Gym');
      expect(robot.inSheet(robot.header), header);
      expect(robot.inSheet(robot.target), move);
    });

    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      testWidgets('the title is whole at 2.0 on 360 × 780, '
          '${locale.languageCode}', (tester) async {
        final dentist = await threeSegments('Dentist');
        final robot = CategoryDeleteRobot(tester);
        await robot.show(
          category: dentist,
          locale: locale,
          textScale: 2.0,
          surface: phone,
        );

        expect(robot.titleParagraph.didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('every built-in name is one line at 2.0 on 360 × 780, '
          '${locale.languageCode}', (tester) async {
        final builtIns = CalendarCategories.all.where((c) => c.isBuiltIn);
        expect(builtIns, isNotEmpty);
        final robot = CategoryDeleteRobot(tester);
        const oneLine =
            FormMetrics.titleFontSize * FormMetrics.titleLineHeight * 2.0;

        for (final category in builtIns) {
          await robot.show(
            category: category,
            locale: locale,
            textScale: 2.0,
            surface: phone,
          );
          final name = CalendarCategories.labelOf(category, robot.l10n);
          expect(robot.leadsWithAvatar, isFalse, reason: 'the glyph at 2.0');
          expect(
            robot.nameSize(name).height,
            moreOrLessEquals(oneLine, epsilon: 0.5),
            reason: name,
          );
          await robot.tapClose();
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the avatar leads at 1.0', (tester) async {
      final dentist = await custom('Dentist');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: dentist, surface: phone);

      expect(robot.leadsWithAvatar, isTrue);
    });

    testWidgets('German at 2.0 on 360 × 780 lays out without an overflow', (
      tester,
    ) async {
      final dentist = await threeSegments('Zahnarzttermine');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: dentist,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );

      expect(tester.takeException(), isNull);
      expect(
        robot.impactCaption,
        '12 Ereignisse · 3 Erinnerungen · 2 Vorlagen',
      );
      expect(robot.targetLabel, 'Sonstiges');
      expect(robot.deleteEnabled, isTrue);
    });

    testWidgets('Romanian at 2.0 on 360 × 780 lays out without an overflow', (
      tester,
    ) async {
      final dentist = await threeSegments('Programări la dentist');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: dentist,
        locale: const Locale('ro'),
        textScale: 2.0,
        surface: phone,
      );

      expect(tester.takeException(), isNull);
      expect(robot.impactCaption, '12 evenimente · 3 alerte · 2 șabloane');
      expect(robot.targetLabel, 'Altele');
      expect(robot.deleteEnabled, isTrue);
    });

    testWidgets('German at 2.0 on 412 × 915 lays out without an overflow', (
      tester,
    ) async {
      final dentist = await threeSegments('Zahnarzttermine');
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: dentist,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(412, 915),
      );

      expect(tester.takeException(), isNull);
      expect(robot.titleParagraph.didExceedMaxLines, isFalse);
      expect(robot.deleteEnabled, isTrue);
    });

    for (final (dark, scale) in const [(false, 1.0), (true, 2.0)]) {
      testWidgets('meets the tap-target, label and contrast guidelines, '
          '${dark ? 'dark' : 'light'} at $scale', (tester) async {
        final dentist = await threeSegments('Dentist');
        final robot = CategoryDeleteRobot(tester);
        await robot.show(
          category: dentist,
          textScale: scale,
          surface: phone,
          dark: dark,
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  });

  group('the share sentence', () {
    const maria = ShareAudience(id: 'pair-1', displayName: 'Maria', members: []);
    const ready = ShareReady(maria);
    const views =
        'Saved views, digests and reports that pick only Work show nothing '
        'until you pick again.';

    /// A custom category holding [events] events, shared when [shared] says
    /// so, as the catalogue hands it to the page.
    Future<CalendarCategory> category(
      String name, {
      int events = 0,
      bool shared = false,
    }) async {
      final created = await custom(name);
      await addEvents(created.id, events);
      if (shared) await service.setShared(created.id, maria.id);
      return CalendarCategories.byId(created.id)!;
    }

    testWidgets('a shared category: the partner stops seeing its events, or '
        'they stay shared through a shared target — first, at one height', (
      tester,
    ) async {
      final work = await category('Work', events: 42, shared: true);
      await category('Travel', shared: true);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: work, share: ready, surface: phone);
      final height = robot.consequencesHeight;
      expect(robot.consequences, 'Maria stops seeing its 42 events. $views');

      await robot.openPicker();
      await robot.pick('Travel');
      expect(robot.consequences, 'They stay shared through Travel. $views');
      expect(robot.consequencesHeight, height);

      await robot.openPicker();
      await robot.pick('Other');
      expect(robot.consequences, 'Maria stops seeing its 42 events. $views');
      expect(robot.consequencesHeight, height);
      await robot.tapClose();
    });

    testWidgets('a private category moving to a shared one: the partner will '
        'see its events through it', (tester) async {
      final work = await category('Work', events: 12);
      await category('Travel', shared: true);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(category: work, share: ready, surface: phone);
      final height = robot.consequencesHeight;
      expect(robot.consequences, views);

      await robot.openPicker();
      await robot.pick('Travel');
      expect(
        robot.consequences,
        'Maria will see its 12 events through Travel. $views',
      );
      expect(robot.consequencesHeight, height);
      await robot.tapClose();
    });

    testWidgets('an event shared on its own is left out of the count: it '
        'neither stops nor starts being seen', (tester) async {
      final work = await category('Work', events: 3, shared: true);
      final gym = await category('Gym', events: 3);
      await category('Travel', shared: true);
      await db.calendarEventDao.setSharedPair('${work.id}-e0', maria.id);
      await db.calendarEventDao.setSharedPair('${gym.id}-e0', maria.id);
      final robot = CategoryDeleteRobot(tester);

      await robot.show(category: work, share: ready, surface: phone);
      expect(robot.consequences, 'Maria stops seeing its 2 events. $views');
      await robot.tapClose();

      await robot.show(category: gym, share: ready, surface: phone);
      await robot.openPicker();
      await robot.pick('Travel');
      expect(
        robot.consequences,
        'Maria will see its 2 events through Travel. '
        '${views.replaceFirst('Work', 'Gym')}',
      );
      await robot.tapClose();
    });

    testWidgets('nothing is said with nothing to move, with no sharing '
        'involved, or while not paired', (tester) async {
      final robot = CategoryDeleteRobot(tester);
      // No category shared: the paired sheet is the unpaired one.
      final gym = await category('Gym', events: 3);
      await robot.show(category: gym, share: ready, surface: phone);
      final height = robot.consequencesHeight;
      expect(robot.consequences, startsWith('Saved views'));
      await robot.tapClose();
      await robot.show(category: gym, surface: phone);
      expect(robot.consequencesHeight, height);
      await robot.tapClose();

      final empty = await category('Work', shared: true);
      await robot.show(category: empty, share: ready, surface: phone);
      expect(robot.consequences, views);
      await robot.tapClose();

      final shared = await category('Trips', events: 3, shared: true);
      await robot.show(category: shared, surface: phone);
      expect(robot.consequences, startsWith('Saved views'));
      await robot.tapClose();
    });

    testWidgets('German at 2.0: the sentence follows the pick at one height', (
      tester,
    ) async {
      final work = await category('Work', events: 42, shared: true);
      await category('Travel', shared: true);
      final robot = CategoryDeleteRobot(tester);
      await robot.show(
        category: work,
        share: const ShareReady(
          ShareAudience(
            id: 'pair-1',
            displayName: 'Maximilian-Alexander',
            members: [],
          ),
        ),
        locale: const Locale('de'),
        textScale: 2.0,
        surface: phone,
      );
      final height = robot.consequencesHeight;
      expect(robot.consequences, startsWith('Maximilian-Alexander sieht'));
      await robot.openPicker();
      await robot.pick('Travel');
      expect(robot.consequences, startsWith('Sie bleiben über Travel geteilt.'));
      expect(robot.consequencesHeight, height);
      await robot.tapClose();
    });
  });
}

/// Holds or fails the next read of one table: the cascade's own read of the
/// category inside its transaction, held so a case can look at the sheet
/// mid-write or failed so it can see the sheet survive a write error; the
/// counts `show` reads, failed so nothing opens.
class _ReadGate extends QueryInterceptor {
  Completer<void>? _hold;
  String? _table;
  bool _fail = false;
  bool held = false;

  void holdNext(String table) {
    _table = table;
    _fail = false;
    _hold = Completer<void>();
  }

  void failNext(String table) {
    _table = table;
    _fail = true;
  }

  void release() {
    final hold = _hold;
    _hold = null;
    _table = null;
    _fail = false;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final table = _table;
    if (_fail && table != null && statement.contains(table)) {
      _table = null;
      _fail = false;
      throw StateError('read of $table failed');
    }
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    if (hold != null && table != null && statement.contains(table)) {
      _table = null;
      held = true;
      await hold.future;
    }
    return rows;
  }
}
