import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/shared_category_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../support/fake_share_service.dart';
import 'support/alert_sheet_robot.dart';
import 'support/layout_errors.dart';

/// One of the partner's own categories from my side (share surfaces §6.4,
/// the slice D spec §3): who it is from, the show switch through the bloc,
/// and my own alerts for it written at once through the real alert service
/// — inert in place under the other two settings and while hidden — and the
/// sheet closing itself when the category leaves.
void main() {
  // The spec's heights were measured with the real faces.
  setUpAll(loadGoldenFonts);

  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [],
  );
  const id = 'p-night';

  late AppDatabase db;
  late _FailingWrites writes;
  late EventAlertService alerts;
  late FakeShareService service;
  late ShareBloc bloc;
  late int reconciles;

  ShareOverview overview({bool shown = true}) => ShareOverview(
    partnerCategories: [
      PartnerSharedCategory(
        category: const CalendarCategory(
          id: id,
          name: 'Night shift',
          colorValue: 0xFF3949AB,
          iconKey: 'work',
          sortOrder: 0,
          isBuiltIn: false,
          fromPartner: true,
        ),
        joinsMine: false,
        shown: shown,
        eventCount: 18,
      ),
    ],
  );

  CategoryAlert seeded(String alertId, {AlertMode mode = AlertMode.notify}) =>
      CategoryAlert(
        id: alertId,
        categoryId: id,
        mode: mode,
        offsetMinutes: 10,
        daysBefore: 1,
        dayMinute: 9 * 60,
      );

  setUp(() async {
    SettingsService.reset();
    EventAlertService.reset();
    writes = _FailingWrites();
    db = await openTestDatabase(interceptor: writes);
    SettingsService.forTesting(db);
    alerts = await EventAlertService.forTesting(db);
    reconciles = 0;
    SharedCategorySheet.reconcile = (_) async => reconciles++;
    service = FakeShareService(availability: const ShareReady(audience))
      ..shareOverview = overview()
      ..shareAlerts = ShareAlerts.category;
  });

  tearDown(() async {
    writes.release();
    SharedCategorySheet.reconcile = AlertScheduler.reconcileAllQuietly;
    EventAlertService.reset();
    SettingsService.reset();
    CalendarCategories.updateCache(const []);
    await db.close();
  });

  Future<void> seedTwo() => alerts.replaceForCategory(id, [
    seeded('a1'),
    seeded('a2', mode: AlertMode.ring),
  ]);

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double scale = 1.0,
    bool dark = false,
    String name = 'Maria',
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.reset);
    bloc = ShareBloc(
      service: () async => service,
      calendarChanges: const Stream.empty(),
    );
    addTearDown(bloc.close);
    bloc.add(const ShareOpened());
    await tester.runAsync(
      () => bloc.stream.firstWhere((state) => state is ShareLoaded),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SharedCategorySheet.show(
                context,
                bloc: bloc,
                categoryId: id,
                partner: PartnerLook(name: name),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Lets the bloc's write and its reload land.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  final sheet = find.byType(SharedCategorySheet);
  final alertRows = find.byType(FormPickerSwitchRow);
  // A widget finder: the semantics one needs the binding, which `main` has
  // not made yet.
  final addAlert = find.byWidgetPredicate(
    (w) =>
        w is FormActionRow &&
        w.identifier == SemanticsIds.sharedCategoryAddAlert,
  );

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder alertSwitch(int index) =>
      find.bySemanticsIdentifier(SemanticsIds.sharedCategoryAlertSwitch(index));

  List<CategoryAlert> stored() => EventAlerts.categoryAlertsFor(id);

  /// The caption the slot shows; its candidates lie invisible under it.
  Finder shownCaption(String text) => find.text(text).hitTestable();

  /// The product of every `Opacity` above [finder].
  double opacityOver(WidgetTester tester, Finder finder) {
    var product = 1.0;
    for (final opacity in tester.widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )) {
      product *= opacity.opacity;
    }
    return product;
  }

  testWidgets('who it is from, the show switch, my alerts and the caption', (
    tester,
  ) async {
    await seedTwo();
    await open(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategorySheet),
      findsOneWidget,
    );
    expect(find.text('Category'), findsOneWidget);
    final title = tester.widget<FormReadTitleRow>(
      find.byType(FormReadTitleRow),
    );
    expect(title.title, 'Night shift');
    expect(title.caption, 'From Maria');
    expect(
      tester
          .widget<FormSwitchRow>(
            find.byWidgetPredicate(
              (w) =>
                  w is FormSwitchRow &&
                  w.identifier == SemanticsIds.sharedCategorySheetShow,
            ),
          )
          .value,
      isTrue,
    );
    expect(find.text('ALERTS'), findsOneWidget);
    expect(alertRows, findsNWidgets(2));
    expect(
      tester.widgetList<FormPickerSwitchRow>(alertRows).map((r) => r.caption),
      [
        'Timed events: 10 min before · Reminder',
        'Timed events: 10 min before · Alarm',
      ],
    );
    expect(addAlert, findsOneWidget);
    expect(
      shownCaption('Every event in this category gets these alerts.'),
      findsOneWidget,
    );
  });

  testWidgets('the title is the sheet\'s level-1 heading, as the read '
      'sheet\'s is', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    final title = tester.getSemantics(find.text('Category'));
    expect(title, isSemantics(isHeader: true, label: 'Category'));
    expect(title.getSemanticsData().headingLevel, 1);
    handle.dispose();
  });

  testWidgets('the show switch goes through the bloc', (tester) async {
    await open(tester);

    service.shareOverview = overview(shown: false);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.sharedCategorySheetShow),
    );
    await settle(tester);

    expect(service.shownSets, [(id, false)]);
    expect(
      shownCaption('Hidden from your calendar, so these never ring'),
      findsOneWidget,
    );
  });

  group('measured at 360 × 780 (spec §3)', () {
    for (final dark in [false, true]) {
      testWidgets('two alerts make it 535 tall '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await seedTwo();
        await open(tester, dark: dark);

        expect(tester.getSize(sheet).height, moreOrLessEquals(535, epsilon: 1));
      });
    }

    testWidgets('no alerts make it 345 tall', (tester) async {
      await open(tester);

      expect(tester.getSize(sheet).height, moreOrLessEquals(345, epsilon: 1));
    });

    testWidgets('hiding the category changes the caption\'s words, never its '
        'height', (tester) async {
      await seedTwo();
      await open(tester);
      final slot = find.byType(FormCaptionSlot);
      final shownSlot = tester.getSize(slot).height;
      final shownSheet = tester.getSize(sheet).height;

      service.shareOverview = overview(shown: false);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedCategorySheetShow),
      );
      await settle(tester);

      expect(
        shownCaption('Hidden from your calendar, so these never ring'),
        findsOneWidget,
      );
      expect(tester.getSize(slot).height, shownSlot);
      expect(tester.getSize(sheet).height, shownSheet);
    });
  });

  group('inert', () {
    for (final (what, setting, shown, caption) in const [
      (
        'under Only alerts I add',
        ShareAlerts.own,
        true,
        'Category alerts are off for shared events',
      ),
      (
        'under Off',
        ShareAlerts.off,
        true,
        'Category alerts are off for shared events',
      ),
      (
        'while hidden',
        ShareAlerts.category,
        false,
        'Hidden from your calendar, so these never ring',
      ),
    ]) {
      testWidgets('$what the rows and Add alert stay in place, disabled; the '
          'label and the caption read at full strength', (tester) async {
        await seedTwo();
        service
          ..shareAlerts = setting
          ..shareOverview = overview(shown: shown);
        await open(tester);

        expect(alertRows, findsNWidgets(2));
        for (final row in tester.widgetList<FormPickerSwitchRow>(alertRows)) {
          expect(row.enabled, isFalse, reason: row.label);
        }
        expect(
          tester.widget<FormActionRow>(find.byType(FormActionRow)).onTap,
          isNull,
        );
        expect(shownCaption(caption), findsOneWidget);
        expect(opacityOver(tester, shownCaption(caption)), 1.0);
        expect(opacityOver(tester, find.text('ALERTS')), 1.0);
        expect(opacityOver(tester, find.text('Night shift')), 1.0);

        await tester.tap(alertSwitch(0), warnIfMissed: false);
        await tester.tap(addAlert, warnIfMissed: false);
        await settle(tester);
        expect(find.byType(AlertEditorSheet), findsNothing);
        expect(reconciles, 0);
        expect(stored().every((alert) => alert.enabled), isTrue);
      });
    }
  });

  group('live-apply', () {
    testWidgets('Add alert writes the new alert at once, then re-plans', (
      tester,
    ) async {
      await seedTwo();
      await open(tester);

      await tap(tester, addAlert);
      await AlertSheetRobot(tester).save();
      await settle(tester);

      expect(stored(), hasLength(3));
      expect(stored().last.categoryId, id);
      expect(alertRows, findsNWidgets(3));
      expect(reconciles, 1);
    });

    testWidgets('an edit writes what the alert sheet hands back', (
      tester,
    ) async {
      await seedTwo();
      await open(tester);

      await tap(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoryAlert(0)),
      );
      final alertSheet = AlertSheetRobot(tester);
      await alertSheet.choosePreset('30 min before');
      await alertSheet.save();
      await settle(tester);

      expect(
        [for (final a in stored()) (a.id, a.offsetMinutes)],
        [('a1', 30), ('a2', 10)],
      );
      expect(reconciles, 1);
    });

    testWidgets('Remove in the alert sheet removes it from storage', (
      tester,
    ) async {
      await seedTwo();
      await open(tester);

      await tap(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.sharedCategoryAlert(0)),
      );
      await AlertSheetRobot(tester).tapRemoveAlert();
      await settle(tester);

      expect([for (final a in stored()) a.id], ['a2']);
      expect(alertRows, findsOneWidget);
      expect(reconciles, 1);
    });

    testWidgets('a switch writes its alert\'s state', (tester) async {
      await seedTwo();
      await open(tester);

      await tester.tap(alertSwitch(0));
      await settle(tester);

      expect(
        [for (final a in stored()) (a.id, a.enabled)],
        [('a1', false), ('a2', true)],
      );
      expect(reconciles, 1);
    });

    testWidgets('two quick switches both hold, in order', (tester) async {
      await seedTwo();
      await open(tester);
      // The first write waits in the database while the second is asked.
      writes.hold = Completer<void>();

      await tester.tap(alertSwitch(0));
      await tester.pump();
      await tester.tap(alertSwitch(1));
      await tester.pump();
      expect(stored().every((alert) => alert.enabled), isTrue);
      expect(reconciles, 0);
      writes.release();
      await settle(tester);

      expect(
        [for (final a in stored()) (a.id, a.enabled)],
        [('a1', false), ('a2', false)],
      );
      expect(reconciles, 2);
      for (final row in tester.widgetList<FormPickerSwitchRow>(alertRows)) {
        expect(row.value, isFalse, reason: row.label);
      }
    });

    testWidgets('a write that fails brings back what is stored and says so '
        'once', (tester) async {
      await seedTwo();
      await open(tester);
      writes
        ..fail = true
        ..hold = Completer<void>();

      await tester.tap(alertSwitch(0));
      await tester.pump();
      await tester.tap(alertSwitch(1));
      await tester.pump();
      writes.release();
      await settle(tester);

      // The write queued behind the failed one is dropped, not tried.
      expect(writes.failures, 1);
      expect(find.text('Save failed'), findsOneWidget);
      for (final row in tester.widgetList<FormPickerSwitchRow>(alertRows)) {
        expect(row.value, isTrue, reason: row.label);
      }
      expect(stored().every((alert) => alert.enabled), isTrue);
      expect(reconciles, 0);

      // The next write starts from what is stored, and holds.
      writes.fail = false;
      await tester.tap(alertSwitch(1));
      await settle(tester);
      expect(
        [for (final a in stored()) (a.id, a.enabled)],
        [('a1', true), ('a2', false)],
      );
      expect(reconciles, 1);
    });
  });

  group('it follows the bloc', () {
    testWidgets('when the category leaves the overview the sheet closes, '
        'silently', (tester) async {
      await open(tester);

      service.shareOverview = const ShareOverview();
      bloc.add(const ShareLoadRequested());
      await settle(tester);

      expect(sheet, findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a leave under an open alert editor closes both, and the '
        'page still answers', (tester) async {
      await open(tester);
      await tap(tester, addAlert);
      expect(find.byType(AlertEditorSheet), findsOneWidget);

      service.shareOverview = const ShareOverview();
      bloc.add(const ShareLoadRequested());
      await settle(tester);

      expect(find.byType(AlertEditorSheet), findsNothing);
      expect(sheet, findsNothing);
      expect(stored(), isEmpty);

      // Opened on a category the overview no longer lists, it closes at once.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);

      // Shared again, it opens and stays.
      service.shareOverview = overview();
      bloc.add(const ShareLoadRequested());
      await settle(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
    });

    testWidgets('✕ closes it', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(sheet, findsNothing);
    });
  });

  group('accessibility guidelines', () {
    for (final dark in [false, true]) {
      testWidgets('targets, labels and text contrast '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        final handle = tester.ensureSemantics();
        await seedTwo();
        await open(tester, dark: dark);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('large text and long names', () {
    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      testWidgets('${locale.languageCode} at 2.0 overflows nothing and is '
          'clamped at the editor\'s height', (tester) async {
        await seedTwo();
        final errors = await layoutErrorsDuring(() async {
          await open(
            tester,
            locale: locale,
            scale: 2.0,
            dark: true,
            name: 'Maximilian-Alexander',
          );
          await tester.drag(
            find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
        });

        expect(errors, isEmpty);
        expect(
          tester.getSize(sheet).height,
          moreOrLessEquals(780 * 0.92, epsilon: 1),
        );
        final from = tester.renderObject<RenderParagraph>(
          find.textContaining('Maximilian-Alexander'),
        );
        expect(from.didExceedMaxLines, isFalse);
      });
    }
  });
}

/// Fails every alert-row write while [fail] is set, so a write can fail
/// without closing the database under the sheet, and holds every one while
/// [hold] is pending, so a second write can be asked while the first waits.
class _FailingWrites extends QueryInterceptor {
  bool fail = false;
  Completer<void>? hold;

  /// Alert-row writes that were tried and failed.
  int failures = 0;

  void release() {
    final pending = hold;
    hold = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<void> _gate(String statement) async {
    if (!statement.contains('calendar_category_alerts')) return;
    final pending = hold;
    if (pending != null) await pending.future;
    if (fail) {
      failures++;
      throw StateError('the write failed');
    }
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
