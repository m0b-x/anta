import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/calendar_bounds.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/agenda_day_list_sheet.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/category_editor_sheet.dart';
import 'package:anta/widgets/color_palette_sheet.dart';
import 'package:anta/widgets/color_picker_sheet.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_template_editor_sheet.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

import '../database/support/db_test_support.dart';

/// `showModalBottomSheet(useSafeArea: true)` guards the **status bar** only —
/// its route wraps the sheet in `SafeArea(bottom: false)`. A sheet sitting on
/// the bottom edge of the screen therefore runs underneath the system
/// navigation bar (gesture pill or three-button bar) unless it pads itself,
/// and the last row of a scrollable is what disappears under it.
///
/// Every calendar sheet answers this the same way: the larger of the keyboard
/// inset and the system's bottom inset, added to the scrollable's bottom
/// padding (or to the whole sheet where a fixed footer sits below the scroll
/// view). These tests pin that the padding actually responds to the inset,
/// which a `const EdgeInsets` cannot do.
///
/// **Add every new sheet here.** This is the app's most-repeated defect — four
/// separate rounds of it have shipped — and it is invisible in review because
/// a sheet padded by `viewInsets` alone looks correct with the keyboard up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const navBar = 48.0;
  const surface = Size(800, 1200);

  // The colour sheets resolve settings before presenting (the picker reads
  // its remembered geometry, the palette warms its service), so they need a
  // backend bound or they never open inside a widget test.
  late AppDatabase db;

  // The two editor sheets read the app-wide markdown bar bloc from their
  // `initState`, so it has to exist above the `MaterialApp` — see [openFrom].
  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_sheet_clearance');
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
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
  });

  tearDown(() async {
    await barBloc.close();
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  /// A device with a three-button navigation bar and no keyboard.
  void sizeSurfaceWithNavBar(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
  }

  /// The same device with an IME taller than the sheet's own box.
  ///
  /// Split screen, a handwriting pane, or the stale inset frame Android hands
  /// back after a mid-animation pause all land here. The bug this guards is
  /// the whole body being wrapped in `Padding(bottom: clearance)`: content
  /// height becomes `factor * H - clearance`, which at this inset is zero or
  /// negative, so the sheet paints nothing and hit-tests nothing — a blank,
  /// dead ~92% sheet.
  void sizeSurfaceWithTallKeyboard(WidgetTester tester, {double inset = 1180}) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    // The keyboard covers the navigation bar, which is exactly why the
    // clearance is a `max` rather than a sum.
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
  }

  /// Bottom padding of the sheet's scrollable, resolved to pixels.
  double listBottomPadding(WidgetTester tester) {
    final list = tester.widget<ListView>(find.byType(ListView));
    return list.padding!.resolve(TextDirection.ltr).bottom;
  }

  /// Bottom padding of the outermost `SingleChildScrollView` on screen — the
  /// shape every form sheet uses, where `find.byType` returns tree order and
  /// the sheet's own scroll view is therefore first.
  double scrollBottomPadding(WidgetTester tester) {
    final view = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .first;
    return view.padding!.resolve(TextDirection.ltr).bottom;
  }

  Future<void> openFrom(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      // Above the `MaterialApp`, as `main.dart` provides it: a sheet is a
      // route, so a provider inside `home` sits below it in the tree and the
      // sheet's `context.read` would not find it.
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the event detail sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    final day = DateTime.utc(2026, 8, 25);
    await openFrom(
      tester,
      (context) => EventDetailSheet.show(
        context,
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: day,
          rule: const DailyRecurrence(),
        ),
        day: day,
      ),
    );

    expect(
      listBottomPadding(tester),
      greaterThanOrEqualTo(navBar),
      reason:
          'the description and the occurrence chips are the last things in '
          'the list, and they rendered under the nav bar',
    );
  });

  /// Opens the drill-down on a one-entry August list, the fixture all three
  /// mode variants below share.
  Future<void> openDayListSheet(WidgetTester tester) {
    return openFrom(
      tester,
      (context) => AgendaDayListSheet.show(
        context,
        AgendaDayList(
          title: 'Holidays',
          subtitle: '2 holidays',
          source: const AgendaDayListHolidaySource(),
          color: const Color(0xFFFFB300),
          entries: [
            AgendaDayListEntry(
              day: DateTime.utc(2026, 8, 15),
              icon: Icons.celebration_rounded,
              color: const Color(0xFFFFB300),
              title: 'Assumption of Mary',
              subtitle: 'Saturday, August 15',
            ),
          ],
        ),
        resolve: (_, _) => const [],
        appearance: const CalendarAppearance(),
        today: DateTime.utc(2026, 8, 1),
        windowStart: DateTime.utc(2026, 8, 1),
        windowEnd: DateTime.utc(2026, 8, 31),
      ),
    );
  }

  testWidgets('the agenda day list sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openDayListSheet(tester);

    expect(listBottomPadding(tester), greaterThanOrEqualTo(navBar));
  });

  testWidgets('the day list sheet clears the navigation bar in month mode', (
    tester,
  ) async {
    // Month mode is a `CustomScrollView`, so its clearance is a trailing
    // sliver rather than a list padding — a different code path, and the one
    // the rows under the mini calendar end on.
    sizeSurfaceWithNavBar(tester);
    await openDayListSheet(tester);
    await tester.tap(find.byIcon(Icons.calendar_view_month_rounded));
    await tester.pumpAndSettle();

    final spacer =
        tester
                .widgetList<SliverToBoxAdapter>(find.byType(SliverToBoxAdapter))
                .last
                .child
            as SizedBox;
    expect(spacer.height, greaterThanOrEqualTo(navBar));
  });

  testWidgets('the day list sheet clears the navigation bar in year mode', (
    tester,
  ) async {
    // Year mode is a `GridView` with its own padding; the last row of tiles is
    // what runs under the bar without it.
    sizeSurfaceWithNavBar(tester);
    await openDayListSheet(tester);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    final padding = tester
        .widget<GridView>(find.byType(GridView))
        .padding!
        .resolve(TextDirection.ltr)
        .bottom;
    expect(padding, greaterThanOrEqualTo(navBar));
  });

  testWidgets('a sheet on a device without a navigation bar is unpadded', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
    final day = DateTime.utc(2026, 8, 25);
    await openFrom(
      tester,
      (context) => EventDetailSheet.show(
        context,
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: day,
          rule: const OneTimeRecurrence(),
        ),
        day: day,
      ),
    );

    expect(
      listBottomPadding(tester),
      24,
      reason:
          'the clearance is additive — with nothing to clear the sheet keeps '
          'exactly its designed padding',
    );
  });

  testWidgets('the colour picker sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(tester, (context) => ColorPickerSheet.show(context));
    await tester.pumpAndSettle();

    // This sheet ends in a fixed action row rather than a scrollable, so the
    // clearance is on the whole sheet: the assertion is that Select sits
    // clear of the bar, not that some padding value exists.
    final selectBottom = tester
        .getRect(find.widgetWithText(FilledButton, 'Select'))
        .bottom;
    expect(
      selectBottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - navBar),
      reason: 'Cancel and Select ran under the gesture bar',
    );
  });

  testWidgets('the colour palette sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(tester, (context) => ColorPaletteSheet.show(context));

    final padding = tester
        .widgetList<SliverPadding>(find.byType(SliverPadding))
        .last
        .padding
        .resolve(TextDirection.ltr)
        .bottom;
    expect(padding, greaterThanOrEqualTo(navBar));
  });

  testWidgets('the category editor sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(tester, (context) => CategoryEditorSheet.show(context));

    expect(scrollBottomPadding(tester), greaterThanOrEqualTo(navBar));
  });

  testWidgets('the category editor sheet keeps its header when the keyboard is '
      'taller than the sheet', (tester) async {
    // The regression: with the clearance on the whole body, the Column's
    // height went to zero here and the sheet rendered as a blank rectangle
    // that swallowed every tap. The clearance belongs on the scroll view,
    // which can simply become scrollable instead.
    sizeSurfaceWithTallKeyboard(tester);
    await openFrom(tester, (context) => CategoryEditorSheet.show(context));

    final box = tester.getSize(find.byType(CategoryEditorSheet));
    expect(box.height.isFinite, isTrue);
    expect(box.height, greaterThan(0));

    final body = tester.getSize(
      find
          .descendant(
            of: find.byType(CategoryEditorSheet),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(
      body.height,
      box.height,
      reason: 'the body was shortened by the inset instead of the scrollable',
    );

    // Present *and* reachable: a `RenderErrorBox` is also "present".
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryEditorSheet), findsNothing);
  });

  testWidgets('the event template editor sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(tester, (context) => EventTemplateEditorSheet.show(context));

    expect(scrollBottomPadding(tester), greaterThanOrEqualTo(navBar));
  });

  testWidgets('the event editor sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(
      tester,
      (context) => EventEditorSheet.show(
        context,
        defaultDate: DateTime.utc(2026, 8, 20),
      ),
    );

    // The markdown bar only docks while the description has focus, so with the
    // form idle the clearance is the scroll view's job.
    expect(scrollBottomPadding(tester), greaterThanOrEqualTo(navBar));
  });

  testWidgets('the event description sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(
      tester,
      (context) => EventDescriptionSheet.show(
        context,
        initialText: '',
        heading: 'Leg day',
        limit: 2000,
        grandfatheredLength: 0,
      ),
    );

    // This sheet's bar is permanently docked, so the clearance rides the bar
    // rather than a scrollable — and the body must keep the sheet's full box.
    final box = tester.getSize(find.byType(EventDescriptionSheet));
    final body = tester.getSize(
      find
          .descendant(
            of: find.byType(EventDescriptionSheet),
            matching: find.byType(Column),
          )
          .first,
    );
    expect(
      body.height,
      box.height,
      reason: 'the body was shortened by the inset instead of the footer',
    );
    expect(
      tester.getRect(find.byType(ModernEditorWrapper)).bottom,
      lessThanOrEqualTo(surface.height - navBar),
      reason: 'the editor and the bar below it ran under the gesture bar',
    );
  });

  testWidgets('the date picker sheet clears the navigation bar', (
    tester,
  ) async {
    sizeSurfaceWithNavBar(tester);
    await openFrom(
      tester,
      (context) => CalendarDatePickerSheet.pickSingle(
        context,
        initialDate: DateTime.utc(2026, 8, 20),
        firstDate: CalendarBounds.earliest,
        lastDate: CalendarBounds.latest,
        appearance: const CalendarAppearance(),
      ),
    );

    expect(scrollBottomPadding(tester), greaterThanOrEqualTo(navBar));
  });

  testWidgets('the date picker sheet clears the navigation bar in multi mode', (
    tester,
  ) async {
    // Multi mode ends in a fixed count/Clear row below the grid, so the
    // clearance moves onto that row — same split the colour picker uses.
    sizeSurfaceWithNavBar(tester);
    await openFrom(
      tester,
      (context) => CalendarDatePickerSheet.pickMulti(
        context,
        initialSelection: {DateTime.utc(2026, 8, 20)},
        firstDate: CalendarBounds.earliest,
        lastDate: CalendarBounds.latest,
        appearance: const CalendarAppearance(),
      ),
    );

    expect(
      tester.getRect(find.widgetWithText(TextButton, 'Clear')).bottom,
      lessThanOrEqualTo(surface.height - navBar),
      reason: 'the selection footer ran under the gesture bar',
    );
  });
}
