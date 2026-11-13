import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/shared_event_sheet.dart';

import '../goldens/support/golden_fonts.dart';
import 'support/alert_sheet_robot.dart';
import 'support/layout_errors.dart';

/// The read sheet of a partner's event (share surfaces §6.9, the spec's §8):
/// the measured states, the YOURS group under each setting, my alerts
/// written and nothing of the partner's, the copy, and the sheet following
/// the event while it is open.
void main() {
  // The spec's heights were measured with the real faces; the test font's
  // square glyphs wrap the long rows a line earlier.
  setUpAll(() async {
    await initializeDateFormatting();
    await loadGoldenFonts();
  });

  // A Thursday well ahead, so "next" never starts at today.
  final day = DateTime.utc(2027, 11, 11);

  CalendarEvent timedOneOff({String id = 'p1', bool fromPartner = true}) =>
      CalendarEvent(
        id: id,
        title: 'Night shift',
        categoryId: 'shifts',
        startDate: day,
        time: const EventTime(startMinute: 21 * 60, durationMinutes: 10 * 60),
        fromPartner: fromPartner,
      );

  CalendarEvent allDayOneOff() => CalendarEvent(
    id: 'p1',
    title: 'Night shift',
    categoryId: 'shifts',
    startDate: day,
    fromPartner: true,
  );

  CalendarEvent recurring({
    String? description,
    String categoryId = 'shifts',
  }) => CalendarEvent(
    id: 'p1',
    title: 'Night shift',
    categoryId: categoryId,
    startDate: day,
    rule: WeeklyRecurrence(weekdays: {DateTime.wednesday, DateTime.thursday}),
    time: const EventTime(startMinute: 21 * 60, durationMinutes: 10 * 60),
    description: description,
    fromPartner: true,
  );

  const hourBefore = EventAlert(
    id: 'a1',
    eventId: 'p1',
    mode: AlertMode.ring,
    offsetMinutes: 60,
  );
  // One line beside its tier and ✕ at 360, as the spec's rows are: the
  // real wording of "the day before" wraps there, the render's did not.
  const dayBefore = EventAlert(
    id: 'a2',
    eventId: 'p1',
    dayMinute: 20 * 60,
    offsetMinutes: 15,
  );

  void publishAlerts(List<EventAlert> alerts) =>
      EventAlerts.updateCache(byEvent: {'p1': List.unmodifiable(alerts)});

  /// A built-in the partner shares, with an alert of my own on it: the one
  /// case in which a partner's event inherits here. Its category is taken
  /// by the id this phone holds — an id it does not hold inherits nothing,
  /// never Other's.
  void holdGymWithAnAlert() {
    CalendarCategories.updateCache(const [
      CalendarCategory(
        id: 'gym',
        name: 'Gym',
        colorValue: 0xFF43A047,
        iconKey: 'fitness_center',
        sortOrder: 0,
        isBuiltIn: true,
      ),
    ]);
    EventAlerts.updateCategoryCache(
      byCategory: {
        'gym': List.unmodifiable(const [
          CategoryAlert(id: 'c1', categoryId: 'gym', offsetMinutes: 30),
        ]),
      },
    );
  }

  tearDown(() {
    EventAlerts.resetCache();
    EventAlerts.configureShareAlerts(null);
    CalendarCategories.updateCache(const []);
  });

  Future<_Outcome> open(
    WidgetTester tester, {
    required CalendarEvent event,
    ShareAlerts shareAlerts = ShareAlerts.own,
    Size surface = const Size(360, 780),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    String name = 'Maria',
    Stream<CalendarEvent?>? changes,
    Future<CalendarEvent?> Function()? onCopy,
    Future<NoteMetadata?> Function(String noteId)? resolveNote,
    bool dark = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final outcome = _Outcome();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          // The 24-hour clock the spec's renders were measured on.
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                outcome.exit = await SharedEventSheet.show(
                  context,
                  event: event,
                  day: day,
                  partner: PartnerLook(name: name),
                  changes: changes,
                  shareAlerts: shareAlerts,
                  onAlertsChanged:
                      (alerts, {required knownIds, required added}) =>
                          outcome.writes.add((alerts, knownIds, added)),
                  onCopy: onCopy,
                  resolveNote: resolveNote,
                );
                outcome.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  }

  final sheet = find.byType(SharedEventSheet);

  double sheetHeight(WidgetTester tester) => tester.getSize(sheet).height;

  double scrollExtent(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
      )
      .position
      .maxScrollExtent;

  Finder removeButton(int index) =>
      find.bySemanticsIdentifier(SemanticsIds.eventAlertRemove(index));

  IconButton iconButtonIn(WidgetTester tester, Finder scope) =>
      tester.widget<IconButton>(
        find.descendant(of: scope, matching: find.byType(IconButton)),
      );

  group('the caption says what is true on the device (D32)', () {
    tearDown(() => SharedRefreshAvailability.debugSupported = null);

    for (final (locale, closed, lastReceived) in const [
      (
        Locale('en'),
        'Only Maria can change this event. Your alerts follow its changes, '
            'even while ANTA is closed.',
        'Only Maria can change this event. Your alerts follow what this '
            'phone last received.',
      ),
      (
        Locale('de'),
        'Nur Maria kann dieses Ereignis ändern. Deine Erinnerungen folgen '
            'seinen Änderungen, auch wenn ANTA geschlossen ist.',
        'Nur Maria kann dieses Ereignis ändern. Deine Erinnerungen folgen '
            'dem Stand, den dieses Telefon zuletzt empfangen hat.',
      ),
      (
        Locale('ro'),
        'Doar Maria poate modifica acest eveniment. Alertele tale îi urmează '
            'modificările, chiar și când ANTA este închisă.',
        'Doar Maria poate modifica acest eveniment. Alertele tale urmează ce '
            'a primit ultima dată acest telefon.',
      ),
    ]) {
      testWidgets('${locale.languageCode}: where the phone checks while the '
          'app is closed, alerts follow the event\'s changes', (tester) async {
        SharedRefreshAvailability.debugSupported = true;

        await open(tester, event: timedOneOff(), locale: locale);

        expect(find.text(closed), findsOneWidget);
        expect(find.text(lastReceived), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${locale.languageCode}: elsewhere, they follow what the '
          'phone last received', (tester) async {
        SharedRefreshAvailability.debugSupported = false;

        await open(tester, event: timedOneOff(), locale: locale);

        expect(find.text(lastReceived), findsOneWidget);
        expect(find.text(closed), findsNothing);
      });
    }
  });

  group('measured at 360 × 780 (spec §8)', () {
    testWidgets('a timed one-off with nothing of mine on it is 497 tall', (
      tester,
    ) async {
      await open(tester, event: timedOneOff());

      expect(sheetHeight(tester), moreOrLessEquals(497, epsilon: 1));
      expect(scrollExtent(tester), 0);
      expect(find.text('From Maria'), findsOneWidget);
      expect(find.text('YOURS'), findsOneWidget);
      expect(find.text('Copy to my calendar'), findsOneWidget);
      expect(
        find.text(
          'Only Maria can change this event. Your alerts follow what this '
          'phone last received.',
        ),
        findsOneWidget,
      );
      // Nothing that writes the partner's event, and no ALERTS group.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('ALERTS'), findsNothing);
      expect(find.byType(EventDetailSheet), findsNothing);
    });

    testWidgets('an all-day one-off with two alerts under Off is 621 tall', (
      tester,
    ) async {
      publishAlerts([hourBefore, dayBefore]);
      await open(tester, event: allDayOneOff(), shareAlerts: ShareAlerts.off);

      expect(sheetHeight(tester), moreOrLessEquals(621, epsilon: 1));
      expect(scrollExtent(tester), 0);
    });

    testWidgets('a series under Category with one inherited alert is 700 '
        'tall', (tester) async {
      holdGymWithAnAlert();
      await open(
        tester,
        event: recurring(categoryId: 'gym'),
        shareAlerts: ShareAlerts.category,
      );

      final yours = find.ancestor(
        of: find.text('Add alert'),
        matching: find.byType(FormRowGroup),
      );
      expect(tester.getSize(yours).height, moreOrLessEquals(143, epsilon: 1));
      // The spec's 700 was measured on a one-line "then" caption; the
      // detail sheet's own wording, reused unchanged, lists three dates and
      // takes a second line at 360 — 18 dp, just past the clamp.
      expect(
        sheetHeight(tester) + scrollExtent(tester),
        moreOrLessEquals(700 + 18, epsilon: 1),
      );
    });

    testWidgets('taller than the clamp, the body scrolls under a fixed '
        'header', (tester) async {
      publishAlerts([hourBefore, dayBefore]);
      await open(
        tester,
        event: recurring(
          description: 'Ward B this month. **Home by 8**, asleep by 9.',
        ),
      );

      expect(sheetHeight(tester), moreOrLessEquals(780 * 0.92, epsilon: 1));
      expect(scrollExtent(tester), greaterThan(0));
      final header = tester.getTopLeft(find.text('From Maria'));
      await tester.drag(
        find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('From Maria')), header);
    });
  });

  group('YOURS', () {
    testWidgets('under Off every row stays in place, disabled, with the '
        'caption', (tester) async {
      publishAlerts([hourBefore, dayBefore]);
      await open(tester, event: allDayOneOff(), shareAlerts: ShareAlerts.off);

      expect(find.text('Alerts for shared events are off'), findsOneWidget);
      for (final row in tester.widgetList<FormPickerRow>(
        find.ancestor(
          of: find.textContaining('before'),
          matching: find.byType(FormPickerRow),
        ),
      )) {
        expect(row.enabled, isFalse, reason: row.label);
      }
      final remove = iconButtonIn(tester, removeButton(0));
      expect(remove.onPressed, isNull);
      expect(remove.disabledColor, isNotNull, reason: 'the ✕ dims (§1)');
      final add = tester.widget<FormActionRow>(
        find.widgetWithText(FormActionRow, 'Add alert'),
      );
      expect(add.onTap, isNull);
    });

    testWidgets('under Category the inherited alert is read-only, from its '
        'category', (tester) async {
      holdGymWithAnAlert();
      await open(
        tester,
        event: recurring(categoryId: 'gym'),
        shareAlerts: ShareAlerts.category,
      );

      final inherited = tester.widget<FormPickerRow>(
        find.byWidgetPredicate(
          (w) => w is FormPickerRow && (w.caption ?? '').startsWith('From '),
        ),
      );
      expect(inherited.onTap, isNull);
      expect(inherited.enabled, isTrue);
      expect(find.text('Alerts for shared events are off'), findsNothing);
    });

    testWidgets('under Only mine nothing is inherited', (tester) async {
      holdGymWithAnAlert();
      await open(tester, event: recurring(categoryId: 'gym'));

      expect(
        find.byWidgetPredicate(
          (w) => w is FormPickerRow && (w.caption ?? '').startsWith('From '),
        ),
        findsNothing,
      );
    });

    testWidgets('under Category an event in a category this phone does not '
        'hold inherits nothing — never Other\'s', (tester) async {
      EventAlerts.updateCategoryCache(
        byCategory: {
          'other': List.unmodifiable(const [
            CategoryAlert(id: 'c9', categoryId: 'other', offsetMinutes: 30),
          ]),
        },
      );
      await open(tester, event: recurring(), shareAlerts: ShareAlerts.category);

      expect(
        find.byWidgetPredicate(
          (w) => w is FormPickerRow && (w.caption ?? '').startsWith('From '),
        ),
        findsNothing,
      );
    });

    testWidgets('an alert added is written at once, mine alone', (
      tester,
    ) async {
      final outcome = await open(tester, event: timedOneOff());

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventAddAlert),
      );
      await tester.pumpAndSettle();
      await AlertSheetRobot(tester).save();
      await tester.pumpAndSettle();

      expect(outcome.writes, hasLength(1));
      final (alerts, known, added) = outcome.writes.single;
      expect(added, isTrue);
      expect(known, isEmpty);
      expect(alerts, hasLength(1));
      expect(alerts.single.eventId, 'p1');
      expect(alerts.single.categoryId, isNull, reason: 'a row of my own');
      // The sheet grew by the new row and stayed open.
      expect(sheet, findsOneWidget);
      expect(removeButton(0), findsOneWidget);
    });

    testWidgets('an alert removed is written at once, bounded by what was '
        'shown', (tester) async {
      publishAlerts([hourBefore, dayBefore]);
      final outcome = await open(tester, event: timedOneOff());

      await tester.tap(removeButton(0));
      await tester.pumpAndSettle();

      final (alerts, known, added) = outcome.writes.single;
      expect(added, isFalse);
      expect(known, {'a1', 'a2'});
      expect(alerts.map((a) => a.id), ['a2']);
      expect(removeButton(1), findsNothing);
    });
  });

  testWidgets('Copy to my calendar closes the sheet with the copy', (
    tester,
  ) async {
    final copy = timedOneOff(id: 'mine-1', fromPartner: false);
    final outcome = await open(
      tester,
      event: timedOneOff(),
      onCopy: () async => copy,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy));
    await tester.pumpAndSettle();

    expect(sheet, findsNothing);
    expect(outcome.exit, isA<SharedEventCopied>());
    expect((outcome.exit! as SharedEventCopied).copy.id, 'mine-1');
    expect(
      find.byType(EventEditorSheet),
      findsNothing,
      reason:
          'the caller '
          'opens the editor, never this sheet',
    );
  });

  testWidgets('a copy that could not be made leaves the sheet open', (
    tester,
  ) async {
    final outcome = await open(
      tester,
      event: timedOneOff(),
      onCopy: () async => null,
    );

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy));
    await tester.pumpAndSettle();

    expect(sheet, findsOneWidget);
    expect(outcome.closed, isFalse);
  });

  group('the Linked note row (§6.9 item 2, C12)', () {
    final handover = NoteMetadata(
      id: 'n1',
      folderId: 'f1',
      title: 'Handover',
      preview: '',
      contentLength: 0,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2027, 11, 1),
      updatedAt: DateTime(2027, 11, 1),
      fromPartner: true,
    );
    Finder row() => find.bySemanticsIdentifier(SemanticsIds.sharedEventNote);
    CalendarEvent linked() => timedOneOff().copyWith(noteId: 'n1');

    testWidgets("shown under DETAILS for the partner's note on this phone; "
        'a tap closes the sheet for the caller to open it', (tester) async {
      final asked = <String>[];
      final outcome = await open(
        tester,
        event: linked(),
        resolveNote: (id) async {
          asked.add(id);
          return handover;
        },
      );

      expect(asked, ['n1']);
      expect(row(), findsOneWidget);
      expect(find.text('DETAILS'), findsOneWidget);
      expect(find.text('Linked note'), findsOneWidget);
      expect(find.text('Handover'), findsOneWidget);

      await tester.tap(row());
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(outcome.exit, isA<SharedEventOpenNote>());
      expect((outcome.exit! as SharedEventOpenNote).note, handover);
    });

    testWidgets('absent — never "Not found" — for a note of mine or one not '
        'on this phone', (tester) async {
      await open(tester, event: linked(), resolveNote: (_) async => null);

      expect(row(), findsNothing);
      expect(find.text('DETAILS'), findsNothing);
      expect(find.text('Not found'), findsNothing);
    });

    testWidgets('a note that left the phone while the sheet was open: the tap '
        'finds it gone, the row goes, and nothing opens', (tester) async {
      var onPhone = true;
      final outcome = await open(
        tester,
        event: linked(),
        resolveNote: (_) async => onPhone ? handover : null,
      );
      expect(row(), findsOneWidget);

      onPhone = false;
      await tester.tap(row());
      await tester.pumpAndSettle();

      expect(sheet, findsOneWidget);
      expect(outcome.closed, isFalse);
      expect(row(), findsNothing);
    });

    testWidgets('no link, nothing asked', (tester) async {
      final asked = <String>[];
      await open(
        tester,
        event: timedOneOff(),
        resolveNote: (id) async {
          asked.add(id);
          return handover;
        },
      );

      expect(asked, isEmpty);
      expect(row(), findsNothing);
    });
  });

  group('while open it follows the event', () {
    testWidgets('a change by the partner redraws it in place', (tester) async {
      final changes = StreamController<CalendarEvent?>();
      addTearDown(changes.close);
      await open(tester, event: timedOneOff(), changes: changes.stream);

      changes.add(timedOneOff().copyWith(title: 'Late shift'));
      await tester.pumpAndSettle();

      expect(find.text('Late shift'), findsOneWidget);
      expect(find.text('Night shift'), findsNothing);
      expect(sheet, findsOneWidget);
    });

    testWidgets('when it leaves, the sheet closes and says why', (
      tester,
    ) async {
      final changes = StreamController<CalendarEvent?>();
      addTearDown(changes.close);
      final outcome = await open(
        tester,
        event: timedOneOff(),
        changes: changes.stream,
      );

      changes.add(null);
      await tester.pumpAndSettle();

      expect(sheet, findsNothing);
      expect(outcome.exit, isA<SharedEventGone>());
    });

    testWidgets('an event no longer the partner\'s has left too', (
      tester,
    ) async {
      final changes = StreamController<CalendarEvent?>();
      addTearDown(changes.close);
      final outcome = await open(
        tester,
        event: timedOneOff(),
        changes: changes.stream,
      );

      changes.add(timedOneOff(fromPartner: false));
      await tester.pumpAndSettle();

      expect(outcome.exit, isA<SharedEventGone>());
    });

    /// The navigator still answers: the page's button opens the sheet again
    /// and its ✕ closes it.
    Future<void> expectNavigatorUsable(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    }

    testWidgets('a leave under an open alert editor closes both, the sheet '
        'with its result', (tester) async {
      final changes = StreamController<CalendarEvent?>.broadcast();
      addTearDown(changes.close);
      final outcome = await open(
        tester,
        event: timedOneOff(),
        changes: changes.stream,
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventAddAlert),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertEditorSheet), findsOneWidget);

      changes.add(null);
      await tester.pumpAndSettle();

      expect(find.byType(AlertEditorSheet), findsNothing);
      expect(sheet, findsNothing);
      expect(outcome.exit, isA<SharedEventGone>());
      expect(outcome.writes, isEmpty, reason: 'nothing saved for it');
      await expectNavigatorUsable(tester);
    });

    testWidgets('a leave under a dialog closes the dialog, then the sheet', (
      tester,
    ) async {
      final changes = StreamController<CalendarEvent?>.broadcast();
      addTearDown(changes.close);
      final outcome = await open(
        tester,
        event: timedOneOff(),
        changes: changes.stream,
      );
      unawaited(
        showDialog<bool>(
          context: tester.element(sheet),
          builder: (context) => const AlertDialog(content: Text('Allow?')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Allow?'), findsOneWidget);

      changes.add(null);
      await tester.pumpAndSettle();

      expect(find.text('Allow?'), findsNothing);
      expect(sheet, findsNothing);
      expect(outcome.exit, isA<SharedEventGone>());
      await expectNavigatorUsable(tester);
    });

    testWidgets('a leave while the copy is made waits for it, and the copy '
        'wins', (tester) async {
      final changes = StreamController<CalendarEvent?>();
      addTearDown(changes.close);
      final made = Completer<CalendarEvent?>();
      final outcome = await open(
        tester,
        event: timedOneOff(),
        changes: changes.stream,
        onCopy: () => made.future,
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy),
      );
      await tester.pump();

      changes.add(null);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget, reason: 'the leave waits for the copy');

      made.complete(timedOneOff(id: 'mine-1', fromPartner: false));
      await tester.pumpAndSettle();

      expect(sheet, findsNothing);
      expect(outcome.exit, isA<SharedEventCopied>());
      expect((outcome.exit! as SharedEventCopied).copy.id, 'mine-1');
    });

    testWidgets('a leave while a copy fails closes once the copy has '
        'failed', (tester) async {
      final changes = StreamController<CalendarEvent?>();
      addTearDown(changes.close);
      final made = Completer<CalendarEvent?>();
      final outcome = await open(
        tester,
        event: timedOneOff(),
        changes: changes.stream,
        onCopy: () => made.future,
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy),
      );
      await tester.pump();

      changes.add(null);
      await tester.pumpAndSettle();
      made.complete(null);
      await tester.pumpAndSettle();

      expect(sheet, findsNothing);
      expect(outcome.exit, isA<SharedEventGone>());
    });
  });

  testWidgets('semantics: the root carries its id, the header says whose', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, event: timedOneOff());

    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedEventSheet),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('From Maria'), findsWidgets);
    // The title is the sheet's heading: a screen reader's way to whose it is.
    final title = tester.getSemantics(find.text('From Maria'));
    expect(title, isSemantics(isHeader: true, label: 'From Maria'));
    expect(title.getSemanticsData().headingLevel, 1);
    handle.dispose();
  });

  group('accessibility guidelines', () {
    testWidgets('every target is 48 dp and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      publishAlerts([hourBefore, dayBefore]);
      await open(tester, event: timedOneOff(), onCopy: () async => null);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the ✕ and each remove button are 48 × 48', (tester) async {
      publishAlerts([hourBefore, dayBefore]);
      await open(tester, event: timedOneOff());

      final close = find.descendant(
        of: find.byType(FormSheetHeader),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(close), const Size(48, 48));
      for (final index in [0, 1]) {
        final remove = find.descendant(
          of: removeButton(index),
          matching: find.byType(IconButton),
        );
        expect(tester.getSize(remove), const Size(48, 48), reason: '$index');
      }
    });

    // The text-contrast guideline samples the 11 sp label's anti-aliased
    // edge, not its colour; the label's token pair is what is pinned.
    for (final dark in [false, true]) {
      testWidgets('the YOURS label reads 4.5:1 on the page ground '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await open(tester, event: timedOneOff(), dark: dark);

        final label = tester.widget<Text>(find.text('YOURS'));
        final scheme = Theme.of(tester.element(sheet)).colorScheme;
        expect(label.style?.color, scheme.onSurfaceVariant);
        expect(
          _contrast(scheme.onSurfaceVariant, scheme.pageGround),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('large text and long names', () {
    for (final (scale, locale) in [
      (1.3, const Locale('en')),
      (2.0, const Locale('en')),
      (2.0, const Locale('de')),
    ]) {
      testWidgets('${locale.languageCode} at $scale overflows nothing', (
        tester,
      ) async {
        publishAlerts([hourBefore, dayBefore]);
        final errors = await layoutErrorsDuring(() async {
          await open(
            tester,
            event: recurring(description: 'Ward B this month.'),
            locale: locale,
            textScale: scale,
            name: 'Maximilian-Alexander',
            dark: true,
          );
          await tester.drag(
            find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
        });

        expect(errors, isEmpty);
        expect(sheetHeight(tester), moreOrLessEquals(780 * 0.92, epsilon: 1));
        // The name is the whole title, never cut (decision i).
        final title = locale.languageCode == 'de'
            ? 'Von Maximilian-Alexander'
            : 'From Maximilian-Alexander';
        expect(find.text(title), findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(title),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      });
    }
  });
}

/// The WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

class _Outcome {
  SharedEventExit? exit;
  bool closed = false;
  final writes = <(List<EventAlert>, Set<String>, bool)>[];
}
