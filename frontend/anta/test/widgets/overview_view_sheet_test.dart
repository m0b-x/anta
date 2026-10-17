import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/overview_view.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/widgets/overview_view_sheet.dart';

import '../database/support/db_test_support.dart';
import 'support/layout_errors.dart';
import 'support/overview_view_robot.dart';

/// The saved views sheet (D17): the list the overview shows is saved from
/// here, a view is applied from here, and the list is tidied here without
/// applying anything. What it must get right is handing the whole view to
/// the page and closing on a row tap, keeping the sheet open for every
/// other action, marking the view that is the list shown, and refusing at
/// the cap with a message the user can see.
void main() {
  late AppDatabase db;
  late OverviewViewService service;
  late List<OverviewView> applied;

  const lastYear = OverviewYearPeriod(2025);
  const last90 = OverviewRollingPeriod(OverviewRollingPreset.last90Days);
  const perEvent = OverviewListOptions(rows: OverviewRows.perEvent);

  /// The list the page shows: last 90 days, one row per event, gym only.
  const current = OverviewView(
    id: '',
    name: '',
    period: last90,
    options: perEvent,
    categoryIds: {'gym'},
  );

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    OverviewViewService.reset();
    db = await openTestDatabase();
    service = await OverviewViewService.forTesting(db);
    applied = [];
  });

  tearDown(() async {
    OverviewViewService.reset();
    await db.close();
  });

  Future<String> seed(
    String name, {
    OverviewPeriod period = lastYear,
    OverviewListOptions options = OverviewListOptions.defaults,
    Set<String> categoryIds = const {},
  }) async {
    final view = await service.create(
      name: name,
      period: period,
      options: options,
      categoryIds: categoryIds,
    );
    return view!.id;
  }

  testWidgets('save names the list shown, lists it marked in use and says so', (
    tester,
  ) async {
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);
    expect(robot.canSave, isTrue);

    await robot.saveCurrent('Gym lately');

    final saved = service.views.single;
    expect(saved.name, 'Gym lately');
    expect(saved.matches(last90, perEvent, {'gym'}), isTrue);
    expect(robot.isOpen, isTrue);
    expect(robot.hasRow(saved.id), isTrue);
    expect(robot.isChecked(saved.id), isTrue);
    expect(robot.reports(robot.l10n.overviewViewSaved('Gym lately')), isTrue);
    // Saved already: a second copy is not offered.
    expect(robot.canSave, isFalse);
    expect(applied, isEmpty);
  });

  testWidgets('the ✕ closes right after a save, with the report still up '
      '(device pass, flow 24)', (tester) async {
    final robot = OverviewViewRobot(tester);
    await robot.show(
      current: current,
      applied: applied,
      surface: const Size(412, 952),
    );

    await robot.saveCurrent('Gym lately');
    final report = robot.l10n.overviewViewSaved('Gym lately');
    expect(robot.reports(report), isTrue);
    // A short sheet's header sits right above the report, whose box covers
    // the ✕'s lower edge: the finger lands there.
    await robot.closeUnder(report);

    expect(robot.isOpen, isFalse);
    expect(applied, isEmpty);
  });

  testWidgets('a row tap hands the view over and closes', (tester) async {
    final id = await seed('Last year', categoryIds: {'work'});
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);

    await robot.apply(id);

    expect(applied.single.id, id);
    expect(applied.single.period, lastYear);
    expect(applied.single.categoryIds, {'work'});
    expect(robot.isOpen, isFalse);
  });

  testWidgets('the ✕ closes with nothing applied', (tester) async {
    await seed('Last year');
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);

    await robot.close();

    expect(robot.isOpen, isFalse);
    expect(applied, isEmpty);
  });

  testWidgets('the ✓ sits on the view that is the list shown, and only there', (
    tester,
  ) async {
    final other = await seed('Last year');
    final match = await seed(
      'Gym lately',
      period: last90,
      options: perEvent,
      categoryIds: {'gym'},
    );
    final robot = OverviewViewRobot(tester);
    await robot.show(
      current: current.copyWith(options: perEvent),
      applied: applied,
    );

    expect(robot.isChecked(match), isTrue);
    expect(robot.isChecked(other), isFalse);
  });

  testWidgets('rename renames in place and keeps the sheet open', (
    tester,
  ) async {
    final id = await seed('Last year');
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);

    await robot.rename(id, 'Twenty twenty-five');

    expect(service.views.single.name, 'Twenty twenty-five');
    expect(robot.rowName(id), 'Twenty twenty-five');
    expect(robot.isOpen, isTrue);
    expect(applied, isEmpty);
  });

  testWidgets('update re-points the view at the list shown, in place', (
    tester,
  ) async {
    final id = await seed('Gym');
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);
    expect(robot.isChecked(id), isFalse);

    await robot.updateToCurrent(id);

    final view = service.views.single;
    expect(view.id, id);
    expect(view.name, 'Gym');
    expect(view.matches(last90, perEvent, {'gym'}), isTrue);
    expect(robot.isChecked(id), isTrue);
    expect(robot.isOpen, isTrue);
  });

  testWidgets('move to top reorders in place', (tester) async {
    await seed('First');
    final second = await seed('Second', period: const OverviewYearPeriod(2024));
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);

    await robot.moveToTop(second);

    expect(service.views.map((v) => v.name), ['Second', 'First']);
    expect(robot.isOpen, isTrue);
  });

  // The sheet resizes on a dialog's answer while the dialog's barrier still
  // blocks its semantics; without `FormSheetSemanticsRefresh` the ✕ and the
  // save row stayed reported one row (63 px) off for good.
  group('the semantics geometry follows a resize (device pass, flow 24)', () {
    void expectCoincide((Rect, Rect) rects, String what) {
      final (painted, reported) = rects;
      expect(
        (reported.center - painted.center).distance,
        lessThan(1.0),
        reason: '$what painted at $painted, reported at $reported',
      );
    }

    testWidgets('a save grows the sheet and the ✕ is reported where it is '
        'painted', (tester) async {
      final robot = OverviewViewRobot(tester);
      await robot.show(
        current: current,
        applied: applied,
        surface: const Size(412, 952),
      );
      final before = robot.closeRects.$1;
      expectCoincide(robot.closeRects, 'the ✕ before the save');

      await robot.saveCurrent('Gym lately');
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(robot.closeRects.$1.top, lessThan(before.top));
      expectCoincide(robot.closeRects, 'the ✕ after the save');
      expectCoincide(robot.saveRects, 'the save row after the save');
    });

    testWidgets('a delete shrinks the sheet and the save row is reported '
        'where it is painted', (tester) async {
      final id = await seed('Last year');
      final robot = OverviewViewRobot(tester);
      await robot.show(
        current: current,
        applied: applied,
        surface: const Size(412, 952),
      );
      final before = robot.closeRects.$1;
      expectCoincide(robot.saveRects, 'the save row before the delete');

      await robot.delete(id);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(robot.closeRects.$1.top, greaterThan(before.top));
      expectCoincide(robot.saveRects, 'the save row after the delete');
      expectCoincide(robot.closeRects, 'the ✕ after the delete');
    });
  });

  testWidgets('delete asks first, and only a confirm removes', (tester) async {
    final id = await seed('Last year');
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);

    await robot.delete(id, confirm: false);
    expect(service.views, hasLength(1));

    await robot.delete(id);

    expect(service.views, isEmpty);
    expect(robot.hasRow(id), isFalse);
    expect(robot.isOpen, isTrue);
  });

  testWidgets('at the limit saving refuses with the message and asks no name', (
    tester,
  ) async {
    for (var i = 0; i < OverviewViewService.maxViews; i++) {
      await seed('View $i', period: OverviewYearPeriod(1990 + i));
    }
    final robot = OverviewViewRobot(tester);
    await robot.show(current: current, applied: applied);

    await robot.saveCurrent('One too many');

    expect(robot.dialogOpen, isFalse);
    expect(
      robot.reports(
        robot.l10n.overviewViewLimitReached(OverviewViewService.maxViews),
      ),
      isTrue,
    );
    expect(service.views, hasLength(OverviewViewService.maxViews));
    expect(robot.isOpen, isTrue);
  });

  testWidgets('German at 200 % on a 360 × 780 phone: no overflow', (
    tester,
  ) async {
    await seed('Letztes Jahr mit einem langen Namen');
    final robot = OverviewViewRobot(tester);
    final errors = await layoutErrorsDuring(() async {
      await robot.show(
        current: current,
        applied: applied,
        locale: const Locale('de'),
        textScale: 2.0,
        surface: const Size(360, 780),
      );
    });

    expect(errors, isEmpty);
    expect(find.text('Gespeicherte Ansichten'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.overviewViewsSave),
      findsOneWidget,
    );
    expect(find.byType(OverviewViewSheet), findsOneWidget);
  });
}
