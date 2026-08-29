import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/calendar_categories_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/widgets/settings_search_field.dart';

import '../database/support/db_test_support.dart';

/// The page carries five slices at once — reorder, hide, search, the app-bar
/// create action and the usage counts — so what earns a test is where they
/// *interact*: search and reorder are mutually exclusive, a hidden category
/// stays listed rather than disappearing (the management page is the one
/// surface that shows everything), an order written by tap survives the
/// service round trip, and the delete confirmation says what it will do.
///
/// Runs the real service and the real DAO against `NativeDatabase.memory()`,
/// the way `category_service_test` does; `CategoryService.getInstance()` hands
/// back whatever `forTesting` already installed.
void main() {
  late AppDatabase db;
  late CategoryService service;

  /// Distinguishes successive pumps of the same page so a re-pump rebuilds
  /// from scratch. Without it the element tree reuses the existing `State` and
  /// `initState` — the only place the categories are read — never runs again.
  var pumps = 0;

  setUp(() async {
    CategoryService.reset();
    CalendarEventService.reset();
    db = await openTestDatabase();
    service = await CategoryService.forTesting(db);
    // The page reads its usage counts from the event service, which owns
    // them; binding it here keeps `getInstance()` off `path_provider`.
    await CalendarEventService.forTesting(db);
    pumps = 0;
  });

  tearDown(() async {
    CategoryService.reset();
    CalendarEventService.reset();
    await db.close();
  });

  /// Pumps until [ready] holds. The page renders a `CircularProgressIndicator`
  /// while it loads and that animates forever, so `pumpAndSettle` spins on it
  /// rather than settling — the same bounded loop the calendar page's own
  /// widget tests use, for the same reason.
  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (ready()) return;
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('the awaited condition never held');
  }

  /// Lets a database *write* finish.
  ///
  /// `testWidgets` runs its body inside `FakeAsync`, where drift's batched
  /// transaction — the one behind `CategoryService.reorder` — never completes,
  /// however many frames are pumped. Only `runAsync` hands the real event loop
  /// back, so any tap that persists something has to be drained through here
  /// before the store is worth asserting on. Plain selects resolve on
  /// microtasks and need none of this.
  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// A viewport tall enough that every row is built — the assertions here are
  /// about which rows exist, not about scrolling to them.
  Future<void> pumpPage(WidgetTester tester, {double width = 900}) async {
    tester.view.physicalSize = Size(width, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: CalendarCategoriesPage(key: ValueKey(pumps++)),
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    await tester.pump();
  }

  Future<void> addCustoms(int count) async {
    for (var i = 0; i < count; i++) {
      await service.create(
        name: 'Custom $i',
        colorValue: 0xFF112233,
        iconKey: 'event',
      );
    }
  }

  Future<void> addEvents(String categoryId, int count) async {
    for (var i = 0; i < count; i++) {
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: '$categoryId-$i',
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

  /// The options menu of the row at [index] — scoped to the cards, so the app
  /// bar's own overflow button is never in the running.
  Future<void> openRowMenu(WidgetTester tester, int index) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(Card),
            matching: find.byIcon(Icons.more_vert),
          )
          .at(index),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the search field appears only above the threshold', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(
      CalendarCategories.all.length,
      lessThanOrEqualTo(12),
      reason: 'the built-in catalog must stay under the search threshold',
    );
    expect(find.byType(SettingsSearchField), findsNothing);

    await addCustoms(4);
    await pumpPage(tester);

    expect(find.byType(SettingsSearchField), findsOneWidget);
  });

  testWidgets('a query switches reorder off and says why', (tester) async {
    await addCustoms(4);
    await pumpPage(tester);
    expect(find.byType(ReorderableListView), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gym');
    await tester.pumpAndSettle();

    expect(
      find.byType(ReorderableListView),
      findsNothing,
      reason: 'render indices no longer map to real positions while filtering',
    );
    expect(find.text('Clear search and filters to reorder'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Cardio'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('Cardio'), findsOneWidget);
  });

  testWidgets('an icon keyword reaches a category its name does not', (
    tester,
  ) async {
    await addCustoms(4);
    await pumpPage(tester);

    // "dumbbell" is a keyword on `fitness_center`, which is Gym's icon; the
    // word appears in no category name at all.
    await tester.enterText(find.byType(TextField), 'dumbbell');
    await tester.pumpAndSettle();

    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Cardio'), findsNothing);
  });

  testWidgets('a query with no hits offers a way back', (tester) async {
    await addCustoms(4);
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No categories match'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('No categories match'), findsNothing);
    expect(find.text('Gym'), findsOneWidget);
  });

  testWidgets('a hidden category stays listed, dimmed', (tester) async {
    await service.setHidden('gym', true);
    await pumpPage(tester);

    expect(
      find.text('Gym'),
      findsOneWidget,
      reason: 'the management page is the one surface that shows everything',
    );
    final dimmed = tester.widgetList<Opacity>(
      find.ancestor(of: find.text('Gym'), matching: find.byType(Opacity)),
    );
    expect(dimmed.map((o) => o.opacity), contains(0.5));
  });

  testWidgets('the visibility button round-trips the flag', (tester) async {
    await pumpPage(tester);
    expect(CalendarCategories.byId('gym')!.isHidden, isFalse);

    await tester.tap(
      find
          .descendant(
            of: find.byType(Card),
            matching: find.byIcon(Icons.visibility),
          )
          .first,
    );
    await pumpUntil(tester, () => CalendarCategories.byId('gym')!.isHidden);

    expect(CalendarCategories.visible.map((c) => c.id), isNot(contains('gym')));
    expect(
      CalendarCategories.all.map((c) => c.id),
      contains('gym'),
      reason: 'hiding is archiving — dropping it would repaint its events grey',
    );
  });

  testWidgets('the row subtitle carries the event count', (tester) async {
    await addEvents('gym', 2);
    await pumpPage(tester);

    expect(find.text('Built-in category · 2 events'), findsOneWidget);
    expect(find.text('Built-in category · No events'), findsWidgets);
  });

  testWidgets('a row fits a narrow phone', (tester) async {
    // Handle + avatar leading, two actions trailing and a two-part subtitle is
    // the widest this row ever gets; an overflow here would throw.
    await addEvents('gym', 12);
    await pumpPage(tester, width: 360);

    expect(find.text('Gym'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('move to top persists a new order', (tester) async {
    await pumpPage(tester);
    expect(CalendarCategories.all.first.id, 'gym');

    await openRowMenu(tester, 1);
    await tester.tap(find.text('Move to top'));
    await settleWrites(tester);

    expect(CalendarCategories.all.map((c) => c.id).take(2), [
      'cardio',
      'gym',
    ]);
    expect(
      CalendarCategories.all.map((c) => c.sortOrder).toList(),
      List.generate(CalendarCategories.all.length, (i) => i),
      reason: 'reorder writes dense 0..N-1, so nothing ties on sort_order',
    );
  });

  testWidgets('sort A–Z orders by the localized label', (tester) async {
    await pumpPage(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort A–Z'));
    await settleWrites(tester);

    expect(CalendarCategories.all.map((c) => c.id).toList(), [
      'birthday',
      'cardio',
      'competition',
      'gym',
      'holiday',
      'measurement',
      'mobility',
      'other',
      'rest',
    ]);
  });

  testWidgets('deleting a category with events says what it will do', (
    tester,
  ) async {
    final custom = await service.create(
      name: 'Fitness',
      colorValue: 0xFF112233,
      iconKey: 'event',
    );
    await addEvents(custom.id, 3);
    await pumpPage(tester);

    await openRowMenu(tester, CalendarCategories.all.length - 1);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Move 3 events to Other and delete "Fitness"?'),
      findsOneWidget,
    );
    expect(find.textContaining('Hiding it instead'), findsOneWidget);
  });

  testWidgets('a built-in offers no delete', (tester) async {
    await pumpPage(tester);

    await openRowMenu(tester, 0);

    expect(find.text('Move to top'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(
      find.text('Delete'),
      findsNothing,
      reason: 'built-ins can be hidden; they still cannot be deleted',
    );
  });
}
