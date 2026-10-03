import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/widgets/form_rows.dart';

import 'support/layout_errors.dart';
import 'support/removed_holidays_robot.dart';

/// The sheet is the durable undo for a removed built-in holiday: it lists the
/// service's suppressions and restoring one **deletes** that row, keyed per
/// `(date, holiday)`, so a second suppression on the same day survives.
///
/// `PublicHolidayService` has no in-memory binding — it opens the app
/// database through `path_provider`, in a background isolate — so the
/// singleton is warmed in the real async zone and every read the sheet makes
/// is drained through the robot's `runAsync` loop. Every case drives the
/// sheet through [RemovedHolidaysRobot] (`support/`), so a rebuild of the
/// chrome rewrites the robot and leaves these bodies alone. The last group
/// pins the sub-sheet of the UI language the sheet became in Tier 3
/// (slice 5): the read row with its Restore as a second target, a failed
/// restore, German at 200 % on a phone, the targets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PublicHolidayService service;

  final en = lookupAppLocalizations(const Locale('en'));
  final christmas = DateTime.utc(2026, 12, 25);
  final allSaints = DateTime.utc(2026, 11, 1);
  final labourDay = DateTime.utc(2026, 5, 1);
  String nameOf(PublicHoliday holiday) => PublicHolidays.nameOf(holiday, en);

  /// The seam that makes `restoreSuppressed` throw: the service cannot be
  /// faked, so a trigger on its own database aborts every delete on the
  /// holidays table while every read still answers. Dropped by [allowDeletes]
  /// and, defensively, before every test — the service's `importData`
  /// clears the table with a delete of its own.
  const refuseTrigger = 'refuse_holiday_delete';
  Future<void> refuseDeletes(WidgetTester tester) => tester.runAsync(() async {
    final db = await AppDatabase.getInstance();
    await db.customStatement(
      'CREATE TRIGGER $refuseTrigger BEFORE DELETE ON public_holidays '
      "BEGIN SELECT RAISE(ABORT, 'refused'); END",
    );
  });
  Future<void> allowDeletes(WidgetTester tester) => tester.runAsync(() async {
    final db = await AppDatabase.getInstance();
    await db.customStatement('DROP TRIGGER IF EXISTS $refuseTrigger');
  });

  /// A stored suppression, in the backup's row shape the service imports.
  Map<String, Object?> suppression(PublicHoliday holiday, DateTime date) => {
    'dateMs': date.millisecondsSinceEpoch,
    'nameKey': holiday.name,
    'profile': 'germany',
    'customLabel': null,
    'suppressed': true,
  };

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_removed_holidays');
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
    // Warmed here, in the real async zone, and emptied: the file-backed
    // database outlives a test, and its open never completes under the
    // `FakeAsync` a `testWidgets` body runs in.
    service = await PublicHolidayService.getInstance();
    await (await AppDatabase.getInstance()).customStatement(
      'DROP TRIGGER IF EXISTS $refuseTrigger',
    );
    await service.importData(const []);
  });

  tearDown(PublicHolidayService.reset);

  /// Seeds [rows] from inside a test body, where the service's writes need
  /// the real event loop.
  Future<void> seed(WidgetTester tester, List<Map<String, Object?>> rows) =>
      tester.runAsync(() => service.importData(rows));

  testWidgets('the list is loading until the service answers', (tester) async {
    await seed(tester, [suppression(PublicHoliday.christmasDay, christmas)]);
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);

    expect(robot.isLoading, isTrue);
    expect(robot.rows, isEmpty);

    await robot.settle();

    expect(robot.isLoading, isFalse);
    expect(robot.rows, hasLength(1));
  });

  testWidgets('an empty list says so', (tester) async {
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);
    await robot.settle();

    expect(robot.isEmpty, isTrue);
    expect(robot.rows, isEmpty);
  });

  testWidgets('a suppressed holiday is one row with its name and the date it '
      'was removed on', (tester) async {
    await seed(tester, [
      suppression(PublicHoliday.christmasDay, christmas),
      suppression(PublicHoliday.allSaints, allSaints),
    ]);
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);
    await robot.settle();

    expect(robot.isEmpty, isFalse);
    expect(
      robot.rows,
      unorderedEquals(<RemovedHolidayRow>[
        (name: nameOf(PublicHoliday.christmasDay), date: 'December 25, 2026'),
        (name: nameOf(PublicHoliday.allSaints), date: 'November 1, 2026'),
      ]),
    );
    expect(nameOf(PublicHoliday.christmasDay), 'Christmas Day');
  });

  testWidgets('restore deletes the suppression and drops the row', (
    tester,
  ) async {
    await seed(tester, [
      suppression(PublicHoliday.christmasDay, christmas),
      suppression(PublicHoliday.allSaints, allSaints),
    ]);
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);
    await robot.settle();

    await robot.restore(nameOf(PublicHoliday.christmasDay));

    expect(robot.rows, [
      (name: nameOf(PublicHoliday.allSaints), date: 'November 1, 2026'),
    ]);
    final left = await tester.runAsync(() => service.suppressedHolidays());
    expect(left, hasLength(1));
    expect(left!.single.holiday, PublicHoliday.allSaints);
    expect(left.single.date, allSaints);
  });

  testWidgets('the restored message is drawn over the sheet', (tester) async {
    await seed(tester, [suppression(PublicHoliday.christmasDay, christmas)]);
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);
    await robot.settle();

    await robot.restore(nameOf(PublicHoliday.christmasDay));

    expect(robot.isOpen, isTrue);
    expect(robot.message, 'Holiday restored');
    expect(
      robot.messageReachable,
      isTrue,
      reason: 'the bar is in the overlay, above the modal route',
    );
    expect(robot.scaffoldSnackbarShown, isFalse);
  });

  testWidgets('two suppressions on one day keep the other when one is '
      'restored', (tester) async {
    await seed(tester, [
      suppression(PublicHoliday.christmasDay, christmas),
      suppression(PublicHoliday.secondChristmasDay, christmas),
    ]);
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);
    await robot.settle();
    expect(robot.rows, hasLength(2));

    await robot.restore(nameOf(PublicHoliday.christmasDay));

    expect(robot.rows, [
      (
        name: nameOf(PublicHoliday.secondChristmasDay),
        date: 'December 25, 2026',
      ),
    ]);
    final left = await tester.runAsync(() => service.suppressedHolidays());
    expect(left!.single.holiday, PublicHoliday.secondChristmasDay);
    expect(left.single.date, christmas);
  });

  testWidgets('the scrim and the system back close the sheet', (tester) async {
    final robot = RemovedHolidaysRobot(tester);
    await robot.show(service);
    await robot.settle();

    await robot.tapBarrier();
    expect(robot.isOpen, isFalse);

    await robot.show(service);
    await robot.settle();
    await robot.systemBack();
    expect(robot.isOpen, isFalse);
  });

  group('the sub-sheet of the language', () {
    const phone = Size(360, 780);

    testWidgets('a holiday is a read row with its Restore as a second target: '
        'the row one node of name and date without a tap, the button its '
        'own with its id and tooltip; the ✕ carries its id and closes', (
      tester,
    ) async {
      await seed(tester, [suppression(PublicHoliday.christmasDay, christmas)]);
      final robot = RemovedHolidaysRobot(tester);
      await robot.show(service);
      await robot.settle();
      final name = nameOf(PublicHoliday.christmasDay);

      final row = robot.rowNode(name);
      expect(row.label, contains(name));
      expect(row.label, contains('December 25, 2026'));
      expect(row.hasAction(SemanticsAction.tap), isFalse);

      final restoreId = robot.restoreId(name);
      expect(
        restoreId,
        SemanticsIds.holidayRestoreButton('christmasDay', christmas),
      );
      final restore = robot.nodeOf(restoreId);
      expect(restore.tooltip, 'Restore');
      expect(restore.flagsCollection.isButton, isTrue);
      expect(restore.hasAction(SemanticsAction.tap), isTrue);

      final close = robot.nodeOf(SemanticsIds.removedHolidaysClose);
      expect(close.tooltip, 'Close');
      expect(close.flagsCollection.isButton, isTrue);
      await robot.close();
      expect(robot.isOpen, isFalse);
      final left = await tester.runAsync(() => service.suppressedHolidays());
      expect(left, hasLength(1), reason: 'closing restores nothing');
    });

    testWidgets('a failed restore keeps the row, re-reads the list and says '
        'so over the sheet', (tester) async {
      await seed(tester, [suppression(PublicHoliday.christmasDay, christmas)]);
      final robot = RemovedHolidaysRobot(tester);
      await robot.show(service);
      await robot.settle();
      final name = nameOf(PublicHoliday.christmasDay);
      await refuseDeletes(tester);

      await robot.restore(name);

      expect(robot.isOpen, isTrue);
      expect(robot.rows, [(name: name, date: 'December 25, 2026')]);
      expect(robot.message, "Couldn't restore the holiday");
      expect(robot.messageReachable, isTrue);
      final left = await tester.runAsync(() => service.suppressedHolidays());
      expect(left!.single.holiday, PublicHoliday.christmasDay);
      await allowDeletes(tester);
    });

    testWidgets('German at text scale 2.0 on 360 × 780 lays out with no '
        'layout error: the name and the date whole, the date under a long '
        'name, every control inside the sheet', (tester) async {
      await seed(tester, [suppression(PublicHoliday.labourDay, labourDay)]);
      final robot = RemovedHolidaysRobot(tester);
      final name = PublicHolidays.nameOf(
        PublicHoliday.labourDay,
        lookupAppLocalizations(const Locale('de')),
      );
      expect(name, 'Tag der Arbeit');
      final errors = await layoutErrorsDuring(() async {
        await robot.show(
          service,
          locale: const Locale('de'),
          textScale: 2.0,
          surface: phone,
        );
        await robot.settle();

        expect(robot.rows, [(name: name, date: '1. Mai 2026')]);
        expect(robot.rowWhole(name), isTrue);
        // The pair's wrap: a name this wide at 200 % leaves the date no room
        // beside it, so the date drops under the name instead of squeezing it.
        expect(
          robot.dateRect(name).top,
          greaterThanOrEqualTo(robot.nameRect(name).bottom),
        );
        final sheet = robot.sheetRect;
        for (final id in [
          SemanticsIds.removedHolidaysClose,
          robot.restoreId(name),
        ]) {
          final rect = robot.targetOf(id);
          expect(rect.left, greaterThanOrEqualTo(sheet.left), reason: id);
          expect(rect.right, lessThanOrEqualTo(sheet.right), reason: id);
        }
      });
      expect(errors, isEmpty);
    });

    testWidgets('every control is a 48 dp target at 360 × 780', (tester) async {
      await seed(tester, [suppression(PublicHoliday.christmasDay, christmas)]);
      final robot = RemovedHolidaysRobot(tester);
      await robot.show(service, surface: phone);
      await robot.settle();
      final name = nameOf(PublicHoliday.christmasDay);

      for (final id in [
        SemanticsIds.removedHolidaysClose,
        robot.restoreId(name),
      ]) {
        final rect = robot.targetOf(id);
        expect(
          rect.width,
          greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
          reason: id,
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(FormMetrics.trailingButtonSize),
          reason: id,
        );
      }
      expect(
        robot.rowRect(name).height,
        greaterThanOrEqualTo(FormMetrics.rowMinHeight),
      );
    });
  });
}
