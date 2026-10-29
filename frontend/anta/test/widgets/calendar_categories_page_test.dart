import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/category_alert.dart';
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
  ///
  /// [bloc] puts the app's calendar bloc above the app, where the app has it;
  /// [textScale] scales the text as the phone's setting would.
  Future<void> pumpPage(
    WidgetTester tester, {
    double width = 900,
    double height = 2000,
    CalendarBloc? bloc,
    double? textScale,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      builder: textScale == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      home: CalendarCategoriesPage(key: ValueKey(pumps++)),
    );
    await tester.pumpWidget(
      bloc == null
          ? app
          : BlocProvider<CalendarBloc>.value(value: bloc, child: app),
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

  testWidgets('the search field survives a delete that drops the count', (
    tester,
  ) async {
    // 13 categories — one over the threshold, so the field is showing and the
    // next delete takes the set back under it.
    await addCustoms(4);
    await pumpPage(tester);
    expect(CalendarCategories.all, hasLength(13));
    expect(find.byType(SettingsSearchField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'custom');
    await tester.pumpAndSettle();

    await openRowMenu(tester, 3);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // The menu is gone by now, so this is the confirmation's own button; the
    // dialog title reads "Delete category" and does not collide.
    await tester.tap(find.text('Delete'));
    await settleWrites(tester);

    expect(CalendarCategories.all, hasLength(12));
    expect(
      find.byType(SettingsSearchField),
      findsOneWidget,
      reason:
          'the query is still live — retracting the field here would strand '
          'the list filtered with nothing on screen able to clear it',
    );
    expect(find.text('Gym'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('Gym'), findsOneWidget);
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

  testWidgets('the reorderable list owns the nearest enclosing Scrollable', (
    tester,
  ) async {
    await addCustoms(4);
    await pumpPage(tester);

    // Invariant 6, and until now only a comment.
    // `SliverReorderableListState.didChangeDependencies` binds its
    // `EdgeDraggingAutoScroller` to `Scrollable.of(context)` — the *nearest*
    // one. Wrapping this page's list in an outer scroll view with
    // `shrinkWrap: true` hands that lookup the list's own inner viewport,
    // which then has no scroll extent, and dragging a row to the edge
    // silently stops scrolling past the fold. Nothing about that failure is
    // visible in a static tree or an analyzer run, so it is asserted here:
    // the list's element must find no `Scrollable` above its own.
    final listContext = tester.element(find.byType(ReorderableListView));
    final own = Scrollable.of(
      tester.element(
        find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(Card).first,
        ),
      ),
    );
    expect(
      Scrollable.maybeOf(listContext),
      isNull,
      reason:
          'a Scrollable above the list is the shrink-wrap trap: edge '
          'auto-scroll would bind to a viewport with no extent',
    );
    expect(
      own.position.maxScrollExtent >= 0,
      isTrue,
      reason: 'the list must own a real scroll position to auto-scroll into',
    );
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

    expect(CalendarCategories.all.map((c) => c.id).take(2), ['cardio', 'gym']);
    expect(
      CalendarCategories.all.map((c) => c.sortOrder).toList(),
      List.generate(CalendarCategories.all.length, (i) => i),
      reason: 'reorder writes dense 0..N-1, so nothing ties on sort_order',
    );
  });

  testWidgets('a catalogue change behind the page is picked up, so a reorder '
      'stays dense', (tester) async {
    // The removed one sits *between* two live customs: `reorder` numbers only
    // the ids it is handed, and a dead id in the middle of the list costs its
    // index — the gap the dense `0..N-1` invariant cannot have.
    final gone = await service.create(
      name: 'Pilates',
      colorValue: 0xFF445566,
      iconKey: 'event',
    );
    await service.create(
      name: 'Fitness',
      colorValue: 0xFF112233,
      iconKey: 'event',
    );
    await pumpPage(tester);
    expect(find.text('Pilates'), findsOneWidget);

    // What a pulled page leaves behind: the row is a tombstone,
    // `CategoryService` is reloaded and the signal fires, all of it under
    // this page. Started in the fake zone and drained the way a tap's write
    // is — a drift transaction does not complete inside one `runAsync`.
    final pulled = db.calendarCategoryDao
        .softDeleteById(gone.id)
        .then((_) => service.reload())
        .then((_) => CalendarEventService.notifyExternalChange());
    await settleWrites(tester);
    await pulled;
    await tester.pump();

    expect(
      find.text('Pilates'),
      findsNothing,
      reason: 'Delete on a row the pull already removed no-ops in the service '
          'and the page would report a delete another device did',
    );

    await openRowMenu(tester, 1);
    await tester.tap(find.text('Move to top'));
    await settleWrites(tester);

    expect(
      CalendarCategories.all.map((c) => c.sortOrder).toList(),
      List.generate(CalendarCategories.all.length, (i) => i),
      reason: 'reorder numbers only the ids it is handed, so an order built '
          'from the stale catalogue leaves the live rows no longer dense — '
          'and the facade tie-breaks on id, which makes a position arbitrary',
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

  testWidgets('a query takes both order writers out of reach', (tester) async {
    await addCustoms(4);
    await pumpPage(tester);
    final before = CalendarCategories.all.map((c) => c.id).toList();

    await tester.enterText(find.byType(TextField), 'gym');
    await tester.pumpAndSettle();

    await openRowMenu(tester, 0);
    expect(
      find.text('Move to top'),
      findsNothing,
      reason: 'it rewrites the whole order, and the ranked list cannot show '
          'the promotion — invariant 5, the same reason the handles are dead',
    );
    // The barrier, to get the row menu out of the way.
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<void>>(
            find.ancestor(
              of: find.text('Sort A–Z'),
              matching: find.byType(PopupMenuItem<void>),
            ),
          )
          .enabled,
      isFalse,
      reason: 'disabled, not hidden',
    );
    await tester.tap(find.text('Sort A–Z'));
    await settleWrites(tester);

    expect(CalendarCategories.all.map((c) => c.id).toList(), before);
  });

  testWidgets('a write that fails says so', (tester) async {
    await pumpPage(tester);
    // What a multi-database switch leaves behind a page that stayed open. The
    // eye renders the stored flag rather than an optimistic one, so without a
    // message the tap is indistinguishable from a no-op.
    await tester.runAsync(db.close);

    await tester.tap(find.byIcon(Icons.visibility).first);
    await settleWrites(tester);

    expect(find.text("Couldn't save the change"), findsOneWidget);
  });

  testWidgets('a load that throws leaves no spinner behind', (tester) async {
    // Unbound, `CategoryService.getInstance()` opens the file-backed
    // database; a `path_provider` that refuses makes that open fail the way a
    // real one can, before any file is touched. Before the guard the spinner
    // was the page for good and the error escaped unhandled.
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      pathProvider,
      (call) async => throw PlatformException(code: 'unavailable'),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));
    CategoryService.reset();

    await pumpPage(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // v42, D19: a bell on the row of a category whose events inherit an
  // enabled alert.
  group('the alerts bell', () {
    tearDown(EventAlerts.resetCache);

    testWidgets('marks a category with an enabled alert and no other', (
      tester,
    ) async {
      EventAlerts.updateCategoryCache(
        byCategory: {
          'birthday': const [
            CategoryAlert(id: 'c1', categoryId: 'birthday', daysBefore: 1),
          ],
          'gym': const [
            CategoryAlert(id: 'c2', categoryId: 'gym', enabled: false),
          ],
        },
      );
      await pumpPage(tester);

      final bell = find.byTooltip('Has alerts');
      expect(bell, findsOneWidget);
      final birthdays = CalendarCategories.labelOf(
        CalendarCategories.byId('birthday')!,
        AppLocalizations.of(tester.element(bell))!,
      );
      expect(
        find.descendant(
          of: find.ancestor(of: bell, matching: find.byType(ListTile)),
          matching: find.text(birthdays),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no category with alerts draws no bell', (tester) async {
      await pumpPage(tester);

      expect(find.byTooltip('Has alerts'), findsNothing);
    });

    testWidgets('a screen reader hears the bell', (tester) async {
      final semantics = tester.ensureSemantics();
      EventAlerts.updateCategoryCache(
        byCategory: {
          'gym': const [CategoryAlert(id: 'c1', categoryId: 'gym')],
        },
      );
      await pumpPage(tester);

      // Folded into the row's own announcement, after its name and count.
      expect(find.bySemanticsLabel(RegExp('Has alerts')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the bell never makes a row taller, at text scale 2.0 on '
        '360 × 780', (tester) async {
      Finder gymRow() =>
          find.ancestor(of: find.text('Gym'), matching: find.byType(ListTile));

      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);
      final unbelled = tester.getSize(gymRow()).height;

      EventAlerts.updateCategoryCache(
        byCategory: {
          'gym': const [CategoryAlert(id: 'c1', categoryId: 'gym')],
        },
      );
      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: gymRow(), matching: find.byTooltip('Has alerts')),
        findsOneWidget,
      );
      expect(tester.getSize(gymRow()).height, unbelled);
    });
  });

  // v42: deleting a category moves its events onto Other's alerts, so the
  // calendar's badges and the hub are told.
  group('what the calendar is told', () {
    late CalendarBloc bloc;
    late _RecordingObserver observer;
    late BlocObserver previousObserver;

    setUp(() {
      previousObserver = Bloc.observer;
      observer = _RecordingObserver();
      Bloc.observer = observer;
      bloc = CalendarBloc(
        service: Completer<CalendarEventService>().future,
        alertReconciler: (_, _) async {},
        alertWriter: (_, _, {knownIds}) async {},
      );
    });

    tearDown(() async {
      await bloc.close();
      Bloc.observer = previousObserver;
    });

    testWidgets('a delete announces the alerts changed', (tester) async {
      await service.create(
        name: 'Fitness',
        colorValue: 0xFF112233,
        iconKey: 'event',
      );
      await pumpPage(tester, bloc: bloc);

      await openRowMenu(tester, CalendarCategories.all.length - 1);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await settleWrites(tester);

      expect(service.categories.map((c) => c.name), isNot(contains('Fitness')));
      expect(observer.events.whereType<CategoryAlertsChanged>(), hasLength(1));
      await tester.pump(const Duration(seconds: 10));
    });
  });
}

class _RecordingObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}
