import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole, Tristate;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/pages/calendar_categories_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart' show FormTrailingButton;
import 'package:anta/widgets/settings_reorder.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/category_editor_robot.dart';

/// The page carries its slices at once — two sections, reorder inside a
/// section, archive, search, the FAB's create and the usage counts — so what
/// earns a test is where they *interact*: search and reorder are mutually
/// exclusive, an archived category moves to its own section rather than
/// disappearing (the management page is the one surface that shows
/// everything), an order written by tap or drag survives the service round
/// trip and stays dense over the full list, a drop never crosses a section,
/// and the row menu says what it cannot do by disabling it in place.
///
/// Runs the real service and the real DAO against `NativeDatabase.memory()`,
/// the way `category_service_test` does; `CategoryService.getInstance()` hands
/// back whatever `forTesting` already installed. Roboto is loaded, so the
/// German and Romanian rows at 2.0 are measured as a phone draws them.
void main() {
  late AppDatabase db;
  late CategoryService service;
  late CalendarEventService events;

  /// Distinguishes successive pumps of the same page so a re-pump rebuilds
  /// from scratch. Without it the element tree reuses the existing `State` and
  /// `initState` — the only place the categories are read — never runs again.
  var pumps = 0;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    CategoryService.reset();
    CalendarEventService.reset();
    db = await openTestDatabase();
    service = await CategoryService.forTesting(db);
    // The page reads its usage counts from the event service, which owns
    // them; binding it here keeps `getInstance()` off `path_provider`.
    events = await CalendarEventService.forTesting(db);
    pumps = 0;
  });

  tearDown(() async {
    EventAlerts.resetCache();
    CategoryService.reset();
    CalendarEventService.reset();
    await db.close();
  });

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(byId(id)).getSemanticsData();

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

  /// A viewport tall enough that every row is built unless a test says
  /// otherwise — most assertions here are about which rows exist, not about
  /// scrolling to them.
  ///
  /// [bloc] puts the app's calendar bloc above the app, where the app has it;
  /// [textScale] scales the text as the phone's setting would.
  Future<void> pumpPage(
    WidgetTester tester, {
    double width = 900,
    double height = 2000,
    CalendarBloc? bloc,
    double? textScale,
    Locale locale = const Locale('en'),
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
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

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(CalendarCategoriesPage)))!;

  Future<void> addCustoms(int count) async {
    for (var i = 0; i < count; i++) {
      await service.create(
        name: 'Custom $i',
        colorValue: 0xFF112233,
        iconKey: 'event',
      );
    }
  }

  Future<CalendarCategory> custom(String name) =>
      service.create(name: name, colorValue: 0xFF112233, iconKey: 'event');

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

  Future<void> openRowMenu(WidgetTester tester, String categoryId) async {
    await tester.tap(byId(SemanticsIds.categoryRowMenu(categoryId)));
    await tester.pumpAndSettle();
  }

  Future<void> openBarMenu(WidgetTester tester) async {
    await tester.tap(byId(SemanticsIds.categoryBarMenu));
    await tester.pumpAndSettle();
  }

  Future<void> pickRowItem(
    WidgetTester tester,
    String categoryId,
    String item,
  ) async {
    await openRowMenu(tester, categoryId);
    await tester.tap(byId(item));
    await tester.pumpAndSettle();
  }

  /// The popup's barrier, to get an open menu out of the way.
  Future<void> dismissMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
  }

  Tristate enabledOf(WidgetTester tester, String item) =>
      dataOf(tester, item).flagsCollection.isEnabled;

  /// The group a category's row is drawn in.
  Finder shellOf(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(ContentRowShell),
  );

  Finder inRow(String label, Finder matching) =>
      find.descendant(of: shellOf(label), matching: matching);

  /// Every header and row id in the dump's traversal order — the order a
  /// device flow's `expect --ordered` reads.
  List<String> listedIds(WidgetTester tester) {
    final ids = <String>[];
    void visit(SemanticsNode node) {
      final id = node.getSemanticsData().identifier;
      if (id.startsWith('category-row-') ||
          id.startsWith('category-section-')) {
        ids.add(id);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    var root = tester.getSemantics(find.byType(CustomScrollView));
    for (var up = root.parent; up != null; up = up.parent) {
      root = up;
    }
    visit(root);
    return ids;
  }

  String caption(AppLocalizations l10n, List<String> segments) =>
      segments.join(' · ');

  /// Every stored row's slot, version and stamp, by id.
  Future<Map<String, (int, int, Object)>> stored(WidgetTester tester) async {
    return {
      for (final row in (await tester.runAsync(db.calendarCategoryDao.getAll))!)
        row.id: (row.sortOrder, row.version, row.hlcTimestamp),
    };
  }

  /// The handle of the row [id].
  Finder handleOf(String id) => find.descendant(
    of: byId(SemanticsIds.categoryRow(id)),
    matching: find.byType(ReorderHandle),
  );

  /// Lifts a row by its handle at [from], which lifts at once, carries it to
  /// [to] and drops it, then lets the write land.
  Future<void> dragFromTo(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await settleWrites(tester);
  }

  /// Whether [highlight]'s own box draws the flash's border.
  bool flashes(WidgetTester tester, Finder highlight) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: highlight, matching: find.byType(DecoratedBox)).first,
    );
    return (box.decoration as BoxDecoration).border != null;
  }

  /// How many rows on screen draw the flash.
  int flashingRows(WidgetTester tester) => find
      .byType(ValueChangeHighlight)
      .evaluate()
      .where((element) => flashes(tester, find.byWidget(element.widget)))
      .length;

  group('search', () {
    testWidgets('the field appears only above the threshold, on its own id', (
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
      expect(byId(SemanticsIds.categorySearch), findsOneWidget);
    });

    testWidgets('the field survives a delete that drops the count', (
      tester,
    ) async {
      // 13 categories — one over the threshold, so the field is showing and
      // the next delete takes the set back under it.
      await addCustoms(4);
      await pumpPage(tester);
      expect(CalendarCategories.all, hasLength(13));

      await tester.enterText(find.byType(TextField), 'custom');
      await tester.pumpAndSettle();

      final doomed = CalendarCategories.all.last;
      await pickRowItem(tester, doomed.id, SemanticsIds.categoryMenuDelete);
      await tester.tap(byId(SemanticsIds.sheetConfirm));
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

    testWidgets('a query switches reorder off in place and says why', (
      tester,
    ) async {
      await addCustoms(4);
      await pumpPage(tester);
      expect(find.byType(SliverReorderableList), findsOneWidget);
      final gymLabel = dataOf(tester, SemanticsIds.categoryRow('gym')).label;
      expect(gymLabel, endsWith('Reorder Gym'));

      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pumpAndSettle();

      expect(
        find.byType(SliverReorderableList),
        findsNothing,
        reason:
            'render indices no longer map to real positions while filtering',
      );
      expect(
        find.text('Clear the search to reorder'),
        findsOneWidget,
        reason: 'the page has no filters, so its line names only the search',
      );
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Cardio'), findsNothing);
      final handle = tester.widget<ReorderHandle>(
        inRow('Gym', find.byType(ReorderHandle)),
      );
      expect((handle.enabled, handle.index), (false, null));
      expect(
        tester.getSize(inRow('Gym', find.byType(ReorderHandle))),
        const Size.square(FormMetrics.dragHandleSlot),
        reason: 'greyed in place, never removed',
      );
      expect(
        dataOf(tester, SemanticsIds.categoryRow('gym')).label,
        isNot(contains('Reorder')),
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.byType(SliverReorderableList), findsOneWidget);
      expect(find.text('Cardio'), findsOneWidget);
    });

    testWidgets('the reorderable sliver scrolls the one Scrollable there is', (
      tester,
    ) async {
      await addCustoms(4);
      await pumpPage(tester);

      // `SliverReorderableListState.didChangeDependencies` binds its
      // `EdgeDraggingAutoScroller` to `Scrollable.of(context)` — the
      // *nearest* one. A second Scrollable around the page's scroll view
      // (a shrink-wrapped list inside another) hands it a viewport with no
      // extent, and dragging a row to the edge silently stops scrolling.
      final sliver = tester.element(find.byType(SliverReorderableList));
      final own = Scrollable.of(sliver);
      expect(
        Scrollable.maybeOf(own.context),
        isNull,
        reason: 'a Scrollable above the list is the shrink-wrap trap',
      );
      expect(own.position.maxScrollExtent >= 0, isTrue);
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

    testWidgets('an empty search keeps the field and says so in one caption', (
      tester,
    ) async {
      await addCustoms(4);
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('No categories match'), findsOneWidget);
      expect(find.byType(SettingsSearchField), findsOneWidget);
      expect(find.byType(ContentSectionHeader), findsNothing);
      expect(find.text('Clear search'), findsNothing);
      expect(find.byIcon(Icons.search_off_rounded), findsNothing);
      expect(
        tester.getTopLeft(find.text('No categories match')).dx,
        RowMetrics.groupInset + FormMetrics.groupCaptionPadding.left,
      );

      // The field's own ✕ is the way back.
      await tester.tap(byId(SemanticsIds.settingsSearchClear));
      await tester.pumpAndSettle();

      expect(find.text('No categories match'), findsNothing);
      expect(find.text('Gym'), findsOneWidget);
    });

    testWidgets('a query draws a header only over a section with matches', (
      tester,
    ) async {
      await addCustoms(4);
      await service.setHidden('cardio', true);
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.categorySectionInUse.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(l10n.categorySectionArchived.toUpperCase()),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField), 'cardio');
      await tester.pumpAndSettle();
      expect(find.text(l10n.categorySectionInUse.toUpperCase()), findsNothing);
      expect(
        find.text(l10n.categorySectionArchived.toUpperCase()),
        findsOneWidget,
      );
    });
  });

  group('sections and rows', () {
    testWidgets('In use heads the list; Archived is drawn only with an '
        'archived row, over it', (tester) async {
      await pumpPage(tester);
      final l10n = l10nOf(tester);
      expect(
        find.text(l10n.categorySectionInUse.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(l10n.categorySectionArchived.toUpperCase()),
        findsNothing,
      );
      expect(listedIds(tester).first, SemanticsIds.categorySectionInUseHeader);

      await service.setHidden('gym', true);
      await pumpPage(tester);

      expect(
        listedIds(
          tester,
        ).skipWhile((id) => id != SemanticsIds.categorySectionArchivedHeader),
        [
          SemanticsIds.categorySectionArchivedHeader,
          SemanticsIds.categoryRow('gym'),
        ],
        reason: 'the management page is the one surface that shows everything',
      );
    });

    testWidgets('an archived row dims only its leading and keeps its handle, '
        'its texts, its ⋮ and its height', (tester) async {
      await pumpPage(tester);
      final listedHeight = tester.getSize(shellOf('Gym')).height;

      await service.setHidden('gym', true);
      await pumpPage(tester);

      Iterable<double> dimmersOver(Finder target) => tester
          .widgetList<Opacity>(
            find.ancestor(of: target, matching: find.byType(Opacity)),
          )
          .map((o) => o.opacity);

      expect(dimmersOver(inRow('Gym', find.byType(EventAvatar))), [
        FormMetrics.disabledOpacity,
      ]);
      // Still a control to hold: `outline` at the disabled opacity measured
      // 1.60:1 on `rowGroup`.
      expect(
        dimmersOver(inRow('Gym', find.byIcon(Icons.drag_handle))),
        isEmpty,
      );
      expect(dimmersOver(find.text('Gym')), isEmpty);
      expect(
        dimmersOver(inRow('Gym', find.byType(FormTrailingButton))),
        isEmpty,
      );
      // The last row of a group carries no hairline, as the listed Gym (the
      // first of nine) did: the height compares the row alone.
      expect(
        tester.getSize(shellOf('Gym')).height,
        listedHeight - RowMetrics.dividerThickness + RowMetrics.groupGap,
      );
      expect(
        dataOf(tester, SemanticsIds.categoryRow('gym')).label,
        contains('\n${l10nOf(tester).categoryRowArchived}\n'),
      );

      // Under a query the locked handle's own dim is the only one.
      await addCustoms(4);
      await pumpPage(tester);
      await tester.enterText(find.byType(TextField), 'gym');
      await tester.pumpAndSettle();
      expect(dimmersOver(inRow('Gym', find.byIcon(Icons.drag_handle))), [
        FormMetrics.disabledOpacity,
      ]);
    });

    testWidgets('the row is one node: name, caption, state, the handle\'s '
        'name; the ⋮ a sibling with its tooltip and id', (tester) async {
      await addEvents('gym', 2);
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      final row = dataOf(tester, SemanticsIds.categoryRow('gym'));
      expect(
        row.label,
        'Gym\n'
        '${caption(l10n, [l10n.categoryEventCount(2), l10n.categoryCaptionBuiltIn])}'
        '\nReorder Gym',
      );
      expect(row.hasAction(SemanticsAction.tap), isTrue);
      expect(row.flagsCollection.isButton, isTrue);
      expect(
        tester
            .getSemantics(byId(SemanticsIds.categoryRow('gym')))
            .childrenCount,
        0,
      );

      final menu = dataOf(tester, SemanticsIds.categoryRowMenu('gym'));
      expect(menu.tooltip, l10n.categoryActions);
      expect(menu.hasAction(SemanticsAction.tap), isTrue);
    });

    testWidgets('the handle and the ⋮ are 48 dp targets; a row is 62 dp at '
        '1.0 with its text and hairline at 106', (tester) async {
      await pumpPage(tester, width: 360, height: 780);

      expect(
        tester.getSize(inRow('Gym', find.byType(ReorderHandle))),
        const Size.square(FormMetrics.dragHandleSlot),
      );
      expect(
        tester.getSize(inRow('Gym', find.byType(FormTrailingButton))),
        const Size.square(FormMetrics.trailingButtonSize),
      );
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text('Gym'),
                matching: find.byType(InkWell),
              ),
            )
            .height,
        RowMetrics.twoLineMinHeight,
      );
      final card = tester.getTopLeft(shellOf('Gym')).dx + RowMetrics.groupInset;
      expect(
        tester.getTopLeft(find.text('Gym')).dx - card,
        RowMetrics.reorderAvatarTextInset,
      );
      expect(
        tester.widget<ContentRowShell>(shellOf('Gym')).dividerIndent,
        RowMetrics.reorderAvatarTextInset,
      );
      expect(
        tester.getTopRight(inRow('Gym', find.byType(FormTrailingButton))).dx,
        360 - RowMetrics.groupInset,
        reason: 'no gap before the ⋮',
      );
    });

    testWidgets('the leading is the avatar at linear 1.3 and the tinted glyph '
        'at linear 2.0', (tester) async {
      await pumpPage(tester, width: 360, height: 780, textScale: 1.3);
      expect(inRow('Gym', find.byType(EventAvatar)), findsOneWidget);
      expect(
        tester.widget<ContentRowShell>(shellOf('Gym')).dividerIndent,
        RowMetrics.reorderAvatarTextInset,
      );

      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);
      expect(inRow('Gym', find.byType(EventAvatar)), findsNothing);
      final glyph = tester.widget<Icon>(
        inRow(
          'Gym',
          find.byWidgetPredicate(
            (w) =>
                w is Icon && w.color == CalendarCategories.byId('gym')!.color,
          ),
        ),
      );
      expect(glyph.size, RowMetrics.glyphSize);
      expect(glyph.color, CalendarCategories.byId('gym')!.color);
      expect(
        tester.widget<ContentRowShell>(shellOf('Gym')).dividerIndent,
        RowMetrics.reorderGlyphTextInset,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the caption reads the count, then Built in, then Alerts on', (
      tester,
    ) async {
      EventAlerts.updateCategoryCache(
        byCategory: {
          'birthday': const [
            CategoryAlert(id: 'c1', categoryId: 'birthday', daysBefore: 1),
          ],
          // A switched-off alert reminds nobody.
          'gym': const [
            CategoryAlert(id: 'c2', categoryId: 'gym', enabled: false),
          ],
        },
      );
      final pilates = await custom('Pilates');
      await addEvents('gym', 2);
      await pumpPage(tester);
      final l10n = l10nOf(tester);
      String captionOf(String id) =>
          dataOf(tester, SemanticsIds.categoryRow(id)).label.split('\n')[1];

      expect(
        captionOf('gym'),
        caption(l10n, [
          l10n.categoryEventCount(2),
          l10n.categoryCaptionBuiltIn,
        ]),
      );
      expect(
        captionOf('birthday'),
        caption(l10n, [
          l10n.categoryEventCount(0),
          l10n.categoryCaptionBuiltIn,
          l10n.categoryCaptionAlertsOn,
        ]),
      );
      expect(captionOf(pilates.id), l10n.categoryEventCount(0));
    });

    testWidgets('a longer caption moves no row above it', (tester) async {
      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);
      final tops = {
        for (final label in ['Gym', 'Cardio', 'Rest'])
          label: tester.getTopLeft(shellOf(label)).dy,
      };

      EventAlerts.updateCategoryCache(
        byCategory: {
          'rest': const [CategoryAlert(id: 'c1', categoryId: 'rest')],
        },
      );
      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);

      expect(
        dataOf(tester, SemanticsIds.categoryRow('rest')).label,
        contains(l10nOf(tester).categoryCaptionAlertsOn),
      );
      for (final entry in tops.entries) {
        expect(
          tester.getTopLeft(shellOf(entry.key)).dy,
          entry.value,
          reason: entry.key,
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('menus', () {
    testWidgets('the row menu lists four radio items with their ids, '
        'disabled in place', (tester) async {
      final pilates = await custom('Pilates');
      await pumpPage(tester);

      await openRowMenu(tester, 'gym');
      for (final item in [
        SemanticsIds.categoryMenuMoveToTop,
        SemanticsIds.categoryMenuEdit,
        SemanticsIds.categoryMenuArchive,
        SemanticsIds.categoryMenuDelete,
      ]) {
        expect(
          dataOf(tester, item).role,
          SemanticsRole.menuItemRadio,
          reason: item,
        );
      }
      expect(find.text('Archive'), findsOneWidget);
      expect(find.text('Delete…'), findsOneWidget);
      for (final item in tester.widgetList(
        find.byWidgetPredicate((w) => w is PopupMenuItem),
      )) {
        expect((item as PopupMenuItem).height, FormMetrics.menuRowHeight);
      }
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuMoveToTop),
        Tristate.isFalse,
        reason: 'Gym is first in its section already',
      );
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuDelete),
        Tristate.isFalse,
        reason: 'a built-in is never deleted — and never missing either',
      );
      expect(enabledOf(tester, SemanticsIds.categoryMenuEdit), Tristate.isTrue);
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuArchive),
        Tristate.isTrue,
      );
      await dismissMenu(tester);

      await openRowMenu(tester, pilates.id);
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuMoveToTop),
        Tristate.isTrue,
      );
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuDelete),
        Tristate.isTrue,
      );
    });

    testWidgets('Archive is disabled on the last category in use; Restore is '
        'offered on an archived one', (tester) async {
      await tester.runAsync(() async {
        for (final category in CalendarCategories.all.skip(1)) {
          await service.setHidden(category.id, true);
        }
      });
      await pumpPage(tester);
      expect(CalendarCategories.visible.map((c) => c.id), ['gym']);

      await openRowMenu(tester, 'gym');
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuArchive),
        Tristate.isFalse,
      );
      await dismissMenu(tester);

      await openRowMenu(tester, 'cardio');
      expect(find.text('Restore'), findsOneWidget);
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuArchive),
        Tristate.isTrue,
      );
    });

    testWidgets('a query disables Move to top and Sort A–Z, and Sort writes '
        'nothing', (tester) async {
      await addCustoms(4);
      await pumpPage(tester);
      final before = CalendarCategories.all.map((c) => c.id).toList();

      await tester.enterText(find.byType(TextField), 'custom');
      await tester.pumpAndSettle();

      final second = CalendarCategories.all.firstWhere(
        (c) => c.name == 'Custom 1',
      );
      await openRowMenu(tester, second.id);
      expect(
        enabledOf(tester, SemanticsIds.categoryMenuMoveToTop),
        Tristate.isFalse,
        reason:
            'it rewrites the order, and the ranked list cannot show the '
            'promotion — the same reason the handles are dead',
      );
      await dismissMenu(tester);

      await openBarMenu(tester);
      expect(
        dataOf(tester, SemanticsIds.categorySortAz).role,
        SemanticsRole.menuItemRadio,
      );
      expect(enabledOf(tester, SemanticsIds.categorySortAz), Tristate.isFalse);
      await tester.tap(byId(SemanticsIds.categorySortAz));
      await settleWrites(tester);

      expect(CalendarCategories.all.map((c) => c.id).toList(), before);
    });

    testWidgets('sort A–Z orders by the localized label', (tester) async {
      await pumpPage(tester);

      await openBarMenu(tester);
      await tester.tap(byId(SemanticsIds.categorySortAz));
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

    testWidgets('Move to top moves a row to the top of its own section', (
      tester,
    ) async {
      final pilates = await custom('Pilates');
      final yoga = await custom('Yoga');
      await service.setHidden(pilates.id, true);
      await service.setHidden(yoga.id, true);
      await pumpPage(tester);

      await pickRowItem(tester, 'cardio', SemanticsIds.categoryMenuMoveToTop);
      await settleWrites(tester);
      expect(CalendarCategories.all.map((c) => c.id).take(2), [
        'cardio',
        'gym',
      ]);

      await pickRowItem(tester, yoga.id, SemanticsIds.categoryMenuMoveToTop);
      await settleWrites(tester);

      expect(
        CalendarCategories.all.map((c) => c.id).toList(),
        [
          'cardio',
          'gym',
          'rest',
          'holiday',
          'competition',
          'measurement',
          'mobility',
          'birthday',
          'other',
          yoga.id,
          pilates.id,
        ],
        reason: 'the archived rows swap their own slots; In use is untouched',
      );
      expect(
        CalendarCategories.all.map((c) => c.sortOrder).toList(),
        List.generate(CalendarCategories.all.length, (i) => i),
        reason: 'reorder writes dense 0..N-1, so nothing ties on sort_order',
      );
    });

    testWidgets('an archived row keeps its slot in the full order while In use '
        'is reordered around it', (tester) async {
      // Cardio holds slot 1, between two rows still in use: a write of the
      // sections end to end would move it, and restoring it would no longer
      // bring it back where it was.
      await service.setHidden('cardio', true);
      await pumpPage(tester);
      final before = await stored(tester);

      await pickRowItem(tester, 'rest', SemanticsIds.categoryMenuMoveToTop);
      await settleWrites(tester);

      final ids = CalendarCategories.all.map((c) => c.id).toList();
      expect(ids.take(4), ['rest', 'cardio', 'gym', 'holiday']);
      expect(ids.indexOf('cardio'), 1);
      expect(
        CalendarCategories.all.map((c) => c.sortOrder).toList(),
        List.generate(ids.length, (i) => i),
      );
      final after = await stored(tester);
      expect(after['cardio'], before['cardio'], reason: 'slot, version, stamp');
    });

    testWidgets('a catalogue change behind the page is picked up, so a '
        'reorder stays dense', (tester) async {
      // The removed one sits *between* two live customs: `reorder` numbers
      // only the ids it is handed, and a dead id in the middle of the list
      // costs its index — the gap the dense `0..N-1` invariant cannot have.
      final gone = await custom('Pilates');
      final fitness = await custom('Fitness');
      await pumpPage(tester);
      expect(find.text('Pilates'), findsOneWidget);

      // What a pulled page leaves behind: the row is a tombstone,
      // `CategoryService` is reloaded and the signal fires, all of it under
      // this page.
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
        reason:
            'Delete on a row the pull already removed no-ops in the '
            'service and the page would report a delete another device did',
      );

      await pickRowItem(tester, fitness.id, SemanticsIds.categoryMenuMoveToTop);
      await settleWrites(tester);

      expect(
        CalendarCategories.all.map((c) => c.sortOrder).toList(),
        List.generate(CalendarCategories.all.length, (i) => i),
      );
    });

    testWidgets('a write that fails says so', (tester) async {
      await pumpPage(tester);
      // What a multi-database switch leaves behind a page that stayed open.
      // The sections render the stored flag rather than an optimistic one, so
      // without a message the tap is indistinguishable from a no-op.
      await tester.runAsync(db.close);

      await pickRowItem(tester, 'gym', SemanticsIds.categoryMenuArchive);
      await settleWrites(tester);

      expect(find.text("Couldn't save the change"), findsOneWidget);
    });
  });

  testWidgets('a load that throws leaves no spinner behind', (tester) async {
    // Unbound, `CategoryService.getInstance()` opens the file-backed
    // database; a `path_provider` that refuses makes that open fail the way a
    // real one can, before any file is touched.
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
    expect(find.byType(ContentRowShell), findsNothing);
    expect(tester.takeException(), isNull);
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
      final fitness = await custom('Fitness');
      await pumpPage(tester, bloc: bloc);

      await pickRowItem(tester, fitness.id, SemanticsIds.categoryMenuDelete);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await settleWrites(tester);

      expect(service.categories.map((c) => c.name), isNot(contains('Fitness')));
      expect(observer.events.whereType<CategoryAlertsChanged>(), hasLength(1));
      await tester.pump(const Duration(seconds: 10));
    });
  });

  // The categories rework's safety net (docs/calendar-categories-roadmap.md
  // §7 S0), carried through the rebuild: what the page does end to end,
  // reached the way the device flow reaches it — by semantics id.
  group('the page end to end', () {
    setUp(() {
      // The editor reads the palette through the settings.
      CalendarPaletteService.reset();
      SettingsService.reset();
      SettingsService.forTesting(db);
    });

    tearDown(() {
      CalendarPaletteService.reset();
      SettingsService.reset();
    });

    testWidgets('every control a device flow targets carries its id', (
      tester,
    ) async {
      final fitness = await custom('Fitness');
      await service.setHidden(fitness.id, true);
      await pumpPage(tester);

      for (final id in [
        SemanticsIds.categoryAdd,
        SemanticsIds.categoryBarMenu,
        SemanticsIds.categorySectionInUseHeader,
        SemanticsIds.categorySectionArchivedHeader,
        SemanticsIds.categoryRow(fitness.id),
        SemanticsIds.categoryRowMenu(fitness.id),
        SemanticsIds.categoryRowMenu('gym'),
      ]) {
        expect(byId(id), findsOneWidget, reason: id);
      }
      expect(
        dataOf(tester, SemanticsIds.categoryAdd).tooltip,
        'Create category',
      );

      await openBarMenu(tester);
      expect(byId(SemanticsIds.categorySortAz), findsOneWidget);
      await dismissMenu(tester);

      await openRowMenu(tester, fitness.id);
      for (final item in [
        SemanticsIds.categoryMenuMoveToTop,
        SemanticsIds.categoryMenuArchive,
        SemanticsIds.categoryMenuEdit,
        SemanticsIds.categoryMenuDelete,
      ]) {
        expect(byId(item), findsOneWidget, reason: item);
      }
    });

    testWidgets('a delete taken through moves the events to Other and says '
        'so', (tester) async {
      final fitness = await custom('Fitness');
      for (final id in ['fitness-1', 'fitness-2']) {
        await events.upsert(
          CalendarEvent(
            id: id,
            title: 'Session $id',
            categoryId: fitness.id,
            startDate: DateTime.utc(2026, 8, 1),
          ),
        );
      }
      await pumpPage(tester);
      final l10n = l10nOf(tester);
      final before = (await tester.runAsync(
        () => db.calendarCategoryDao.getByIdsIncludingDeleted([fitness.id]),
      ))!.single;

      await pickRowItem(tester, fitness.id, SemanticsIds.categoryMenuDelete);
      expect(
        find.textContaining(l10n.deleteCategoryConfirmWithEvents(2, 'Fitness')),
        findsOneWidget,
      );
      expect(find.textContaining(l10n.deleteCategoryHideHint), findsOneWidget);
      await tester.tap(byId(SemanticsIds.sheetConfirm));
      await tester.pump();
      await settleWrites(tester);

      final stored = (await tester.runAsync(db.calendarEventDao.getAll))!;
      expect(
        {
          for (final row in stored)
            if (row.id.startsWith('fitness-')) row.id: row.category,
        },
        {'fitness-1': kFallbackCategoryId, 'fitness-2': kFallbackCategoryId},
      );
      // A tombstone with a fresh stamp, never a hard delete: the stamp is
      // what carries the delete to another device.
      final tombstone = (await tester.runAsync(
        () => db.calendarCategoryDao.getByIdsIncludingDeleted([fitness.id]),
      ))!.single;
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.version, before.version + 1);
      expect(tombstone.hlcTimestamp.compareTo(before.hlcTimestamp), isPositive);
      expect(byId(SemanticsIds.categoryRow(fitness.id)), findsNothing);
      expect(find.text('Fitness'), findsNothing);
      expect(find.text(l10n.categoryDeleted), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a delete with no events asks without the hiding hint', (
      tester,
    ) async {
      final fitness = await custom('Fitness');
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      await pickRowItem(tester, fitness.id, SemanticsIds.categoryMenuDelete);

      expect(find.text(l10n.deleteCategoryConfirm('Fitness')), findsOneWidget);
      expect(find.textContaining(l10n.deleteCategoryHideHint), findsNothing);

      await tester.tap(byId(SemanticsIds.sheetCancel));
      await tester.pumpAndSettle();
      expect(byId(SemanticsIds.categoryRow(fitness.id)), findsOneWidget);
    });

    testWidgets('a long press drags a row one slot down, persisted densely '
        'over the full list', (tester) async {
      // A custom past a gap, the way the device fixture seeds its customs at
      // 100: with the built-ins alone already dense, a swap of two would read
      // dense whatever `reorder` wrote. Archived, so the full list the write
      // numbers spans both sections.
      await db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: 'gapped',
          name: 'Pilates',
          colorValue: 0xFF445566,
          iconKey: 'event',
          sortOrder: const Value(100),
          isHidden: const Value(true),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await service.reload();
      await pumpPage(tester);
      final before = {
        for (final row in (await tester.runAsync(
          db.calendarCategoryDao.getAll,
        ))!)
          row.id: row,
      };
      expect(before['gapped']!.sortOrder, 100);

      final from = tester.getCenter(byId(SemanticsIds.categoryRow('gym')));
      final to = tester.getCenter(byId(SemanticsIds.categoryRow('cardio')));

      // The whole row lifts on a long press (the delayed listener), so the
      // finger holds past the timeout before it moves.
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var step = 1; step <= 10; step++) {
        await gesture.moveTo(Offset.lerp(from, to, step / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await settleWrites(tester);

      final rows = [...(await tester.runAsync(db.calendarCategoryDao.getAll))!]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(rows.map((r) => r.id).take(2), ['cardio', 'gym']);
      expect(
        rows.map((r) => r.sortOrder).toList(),
        List.generate(rows.length, (i) => i),
        reason: 'reorder writes dense 0..N-1: no gap, no tie',
      );
      expect(rows.last.id, 'gapped');
      expect(CalendarCategories.all.map((c) => c.id).take(2), [
        'cardio',
        'gym',
      ]);

      // Only the rows whose slot changed are written, all under one stamp; a
      // row the drag left in place keeps its version and its stamp.
      final moved = {'cardio', 'gym', 'gapped'};
      final stamps = {
        for (final row in rows)
          if (moved.contains(row.id)) row.hlcTimestamp,
      };
      expect(stamps, hasLength(1));
      for (final row in rows) {
        final was = before[row.id]!;
        if (moved.contains(row.id)) {
          expect(row.version, was.version + 1, reason: row.id);
          expect(row.hlcTimestamp, isNot(was.hlcTimestamp), reason: row.id);
        } else {
          expect(row.version, was.version, reason: row.id);
          expect(row.hlcTimestamp, was.hlcTimestamp, reason: row.id);
        }
      }
    });

    testWidgets('a drop across the sections is refused and writes nothing', (
      tester,
    ) async {
      final pilates = await custom('Pilates');
      final yoga = await custom('Yoga');
      await service.setHidden(pilates.id, true);
      await service.setHidden(yoga.id, true);
      await pumpPage(tester);
      final before = {
        for (final row in (await tester.runAsync(
          db.calendarCategoryDao.getAll,
        ))!)
          row.id: (row.sortOrder, row.version),
      };
      final order = CalendarCategories.all.map((c) => c.id).toList();

      // By the handle, which lifts at once: past the archived rows' end.
      final from = tester.getCenter(inRow('Gym', find.byType(ReorderHandle)));
      final to = tester.getBottomLeft(shellOf('Yoga')) + Offset(from.dx, 40);
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 16));
      for (var step = 1; step <= 20; step++) {
        await gesture.moveTo(Offset.lerp(from, to, step / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Lifted, so the drop below is real: the list stands an empty box in
      // for the row, and the proxy carries it as one card of its own.
      expect(find.text('Gym'), findsOneWidget);
      expect(shellOf('Gym'), findsNothing);
      expect(
        tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text('Gym'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .borderRadius,
        const BorderRadius.all(Radius.circular(RowMetrics.groupRadius)),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await settleWrites(tester);

      expect(CalendarCategories.all.map((c) => c.id).toList(), order);
      final after = {
        for (final row in (await tester.runAsync(
          db.calendarCategoryDao.getAll,
        ))!)
          row.id: (row.sortOrder, row.version),
      };
      expect(after, before);
      expect(CalendarCategories.byId('gym')!.isHidden, isFalse);
      expect(listedIds(tester)[1], SemanticsIds.categoryRow('gym'));
    });

    testWidgets('a row alone in its section, dropped among the other '
        'section\'s rows, writes nothing', (tester) async {
      for (final id in [
        'gym',
        'cardio',
        'rest',
        'holiday',
        'competition',
        'measurement',
        'mobility',
        'birthday',
      ]) {
        await service.setHidden(id, true);
      }
      await pumpPage(tester);
      final before = await stored(tester);
      final revision = CalendarCategories.revision;

      final from = tester.getCenter(handleOf('other'));
      final to = Offset(
        from.dx,
        tester.getCenter(byId(SemanticsIds.categoryRow('holiday'))).dy,
      );
      await dragFromTo(tester, from, to);

      expect(
        CalendarCategories.revision,
        revision,
        reason: 'no reorder reached the service: nothing republished',
      );
      expect(await stored(tester), before);
      expect(listedIds(tester).take(2), [
        SemanticsIds.categorySectionInUseHeader,
        SemanticsIds.categoryRow('other'),
      ]);
    });

    testWidgets('a drop on the neighbouring header lands at the row\'s own '
        'section\'s edge, persisted', (tester) async {
      final pilates = await custom('Pilates');
      final yoga = await custom('Yoga');
      await service.setHidden(pilates.id, true);
      await service.setHidden(yoga.id, true);
      await pumpPage(tester);
      // Carries the row by its handle until its top edge, which is where the
      // list reads a drop from, lies on the Archived header's.
      Future<void> dropOnHeader(String id) async {
        final from = tester.getCenter(handleOf(id));
        final top = tester
            .getTopLeft(
              find.ancestor(
                of: byId(SemanticsIds.categoryRow(id)),
                matching: find.byType(ContentRowShell),
              ),
            )
            .dy;
        final header = tester
            .getTopLeft(byId(SemanticsIds.categorySectionArchivedHeader))
            .dy;
        await dragFromTo(tester, from, from + Offset(0, header + 2 - top));
      }

      // In use's first row onto the Archived header: In use's last slot.
      await dropOnHeader('gym');
      expect(CalendarCategories.all.map((c) => c.id).toList(), [
        'cardio',
        'rest',
        'holiday',
        'competition',
        'measurement',
        'mobility',
        'birthday',
        'other',
        'gym',
        pilates.id,
        yoga.id,
      ]);

      // Archived's last row onto its own header: Archived's first slot.
      await dropOnHeader(yoga.id);
      final ids = CalendarCategories.all.map((c) => c.id).toList();
      expect(ids.sublist(ids.length - 2), [yoga.id, pilates.id]);
      expect(
        CalendarCategories.all.map((c) => c.sortOrder).toList(),
        List.generate(ids.length, (i) => i),
      );
      final rows = [...(await tester.runAsync(db.calendarCategoryDao.getAll))!]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(rows.map((r) => r.id).toList(), ids, reason: 'persisted');
    });

    testWidgets('a short tap on the handle opens nothing; a tap on the texts '
        'opens the editor', (tester) async {
      final fitness = await custom('Fitness');
      await pumpPage(tester);

      await tester.tap(handleOf(fitness.id));
      await tester.pumpAndSettle();
      expect(byId(SemanticsIds.categoryEditorName), findsNothing);

      await tester.tap(find.text('Fitness'));
      await tester.pumpAndSettle();
      expect(byId(SemanticsIds.categoryEditorName), findsOneWidget);
      await CategoryEditorRobot(tester).close();
    });

    testWidgets('Move up and Move down are the row\'s actions inside its '
        'section, absent at its edges and under a query', (tester) async {
      final semantics = tester.ensureSemantics();
      await addCustoms(4);
      await pumpPage(tester);
      final l10n = l10nOf(tester);
      final up = CustomSemanticsAction(label: l10n.categoryMoveUp);
      final down = CustomSemanticsAction(label: l10n.categoryMoveDown);
      Set<CustomSemanticsAction> actionsOf(String id) => {
        for (final action in [up, down])
          if (dataOf(tester, SemanticsIds.categoryRow(id))
                  .customSemanticsActionIds
                  ?.contains(CustomSemanticsAction.getIdentifier(action)) ??
              false)
            action,
      };

      expect(actionsOf('cardio'), {up, down});
      expect(actionsOf('gym'), {down}, reason: 'In use\'s first row');
      final last = CalendarCategories.all.last.id;
      expect(actionsOf(last), {up}, reason: 'In use\'s last row');

      tester.semantics.customAction(
        find.semantics.byPredicate(
          (node) =>
              node.getSemanticsData().identifier ==
              SemanticsIds.categoryRow('cardio'),
        ),
        down,
      );
      await tester.pump();
      await settleWrites(tester);
      expect(CalendarCategories.all.map((c) => c.id).take(3), [
        'gym',
        'rest',
        'cardio',
      ]);
      expect(
        CalendarCategories.all.map((c) => c.sortOrder).toList(),
        List.generate(CalendarCategories.all.length, (i) => i),
      );

      await tester.enterText(find.byType(TextField), 'c');
      await tester.pumpAndSettle();
      expect(actionsOf('cardio'), isEmpty, reason: 'like the handle');
      semantics.dispose();
    });

    testWidgets('the archive item writes the flag and moves the row under '
        'Archived; Restore brings it back to its slot', (tester) async {
      await pumpPage(tester);

      await pickRowItem(tester, 'cardio', SemanticsIds.categoryMenuArchive);
      await settleWrites(tester);

      final cardio = (await tester.runAsync(
        () => db.calendarCategoryDao.getByIdsIncludingDeleted(['cardio']),
      ))!.single;
      expect(cardio.isHidden, isTrue);
      expect(cardio.isDeleted, isFalse);
      expect(listedIds(tester).sublist(listedIds(tester).length - 2), [
        SemanticsIds.categorySectionArchivedHeader,
        SemanticsIds.categoryRow('cardio'),
      ]);

      await pickRowItem(tester, 'cardio', SemanticsIds.categoryMenuArchive);
      await settleWrites(tester);

      expect(CalendarCategories.byId('cardio')!.isHidden, isFalse);
      expect(listedIds(tester).take(3), [
        SemanticsIds.categorySectionInUseHeader,
        SemanticsIds.categoryRow('gym'),
        SemanticsIds.categoryRow('cardio'),
      ]);
      expect(byId(SemanticsIds.categorySectionArchivedHeader), findsNothing);
    });

    testWidgets('a row tap opens the editor on that category', (tester) async {
      await custom('Fitness');
      await pumpPage(tester);

      await tester.tap(find.text('Fitness'));
      await tester.pumpAndSettle();

      final editor = CategoryEditorRobot(tester);
      expect(byId(SemanticsIds.categoryEditorName), findsOneWidget);
      expect(editor.nameText, 'Fitness');
      await editor.close();
    });

    testWidgets('a create through the FAB is listed when the editor closes', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(find.text('Pilates'), findsNothing);

      await tester.tap(byId(SemanticsIds.categoryAdd));
      await tester.pumpAndSettle();
      final editor = CategoryEditorRobot(tester);
      await editor.typeName('Pilates');
      await editor.save();
      await settleWrites(tester);
      await tester.pumpAndSettle();

      final created = service.categories.singleWhere(
        (c) => c.name == 'Pilates',
      );
      expect(byId(SemanticsIds.categoryRow(created.id)), findsOneWidget);
      expect(shellOf('Pilates'), findsOneWidget);
    });

    testWidgets('a create scrolls its row into view and flashes it, at 2.0 '
        'among 40 categories', (tester) async {
      await tester.runAsync(() => addCustoms(31));
      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);
      expect(CalendarCategories.all, hasLength(40));
      expect(find.text('Custom 30'), findsNothing, reason: 'unbuilt at first');
      await tester.pump(const Duration(milliseconds: 100));
      expect(flashingRows(tester), 0, reason: 'a mounted row never flashes');

      await tester.tap(byId(SemanticsIds.categoryAdd));
      await tester.pumpAndSettle();
      final editor = CategoryEditorRobot(tester);
      await editor.typeName('Pilates');
      await editor.save();
      await settleWrites(tester);

      Finder highlight() => find.ancestor(
        of: find.text('Pilates'),
        matching: find.byType(ValueChangeHighlight),
      );
      bool flashing() =>
          highlight().evaluate().isNotEmpty && flashes(tester, highlight());

      var flashed = false;
      for (var i = 0; i < 40 && !flashed; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        flashed = flashing();
      }
      expect(flashed, isTrue, reason: 'the new row flashes once revealed');
      expect(flashingRows(tester), 1, reason: 'and no other row does');
      final created = service.categories.singleWhere(
        (c) => c.name == 'Pilates',
      );
      final row = tester.getRect(byId(SemanticsIds.categoryRow(created.id)));
      final list = tester.getRect(find.byType(CustomScrollView));
      expect(row.top, greaterThanOrEqualTo(list.top));
      expect(row.bottom, lessThanOrEqualTo(list.bottom));
      await tester.pumpAndSettle();
      expect(flashing(), isFalse, reason: 'the flash fades out');

      // Scrolled out, its subtree is dropped; scrolled back, it is built
      // afresh and must not flash again.
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      position.jumpTo(0);
      await tester.pump();
      expect(find.text('Pilates'), findsNothing);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Pilates'), findsOneWidget);
      expect(flashingRows(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the FAB steps aside while the keyboard is up', (tester) async {
      await addCustoms(4);
      await pumpPage(
        tester,
        width: 360,
        height: 780,
        textScale: 2.0,
        locale: const Locale('de'),
      );
      await tester.enterText(find.byType(TextField), 'c');
      await tester.pumpAndSettle();
      expect(byId(SemanticsIds.categoryAdd), findsOneWidget);
      final firstRow = tester.getTopLeft(
        byId(SemanticsIds.categoryRow('cardio')),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      expect(byId(SemanticsIds.categoryAdd), findsNothing);
      expect(
        tester.getTopLeft(byId(SemanticsIds.categoryRow('cardio'))),
        firstRow,
        reason: 'the FAB floats: no row moves for it',
      );

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(byId(SemanticsIds.categoryAdd), findsOneWidget);
    });
  });

  group('large text and long words', () {
    /// One line of the name at [scale]: its 20 px line, scaled.
    double oneLine(double scale) => FormMetrics.labelLineHeight * scale;

    Future<void> expectOneLine(
      WidgetTester tester,
      String label,
      double scale,
    ) async {
      final list = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(find.text(label), 100, scrollable: list);
      expect(
        tester.getSize(find.text(label)).height,
        oneLine(scale),
        reason: label,
      );
    }

    for (final locale in const [Locale('de'), Locale('ro')]) {
      testWidgets('every built-in name is one line at 2.0 on 360 × 780, '
          '${locale.languageCode}', (tester) async {
        final sample = locale.languageCode == 'de'
            ? await custom('Familienbesuch')
            : await custom('Măsurătoare');
        await pumpPage(
          tester,
          width: 360,
          height: 780,
          textScale: 2.0,
          locale: locale,
        );
        final l10n = l10nOf(tester);

        for (final category in CalendarCategories.all) {
          if (!category.isBuiltIn) continue;
          await expectOneLine(
            tester,
            CalendarCategories.labelOf(category, l10n),
            2.0,
          );
        }
        if (locale.languageCode == 'ro') {
          await expectOneLine(tester, sample.name, 2.0);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('"Familienbesuch" is one line at 2.0 on 412 and at 1.3 on '
        '360', (tester) async {
      await custom('Familienbesuch');
      await pumpPage(
        tester,
        width: 412,
        height: 915,
        textScale: 2.0,
        locale: const Locale('de'),
      );
      await expectOneLine(tester, 'Familienbesuch', 2.0);

      await pumpPage(
        tester,
        width: 360,
        height: 780,
        textScale: 1.3,
        locale: const Locale('de'),
      );
      await expectOneLine(tester, 'Familienbesuch', 1.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the last row clears the FAB at the end of the list', (
      tester,
    ) async {
      await pumpPage(tester, width: 360, height: 780, textScale: 2.0);
      final fab = tester.getRect(byId(SemanticsIds.categoryAdd));
      expect(fab.size, const Size.square(56));
      expect(fab.right, lessThanOrEqualTo(360));

      final list = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      final last = CalendarCategories.all.last;
      final row = tester.getRect(byId(SemanticsIds.categoryRow(last.id)));
      final menu = tester.getRect(byId(SemanticsIds.categoryRowMenu(last.id)));
      expect(row.bottom, lessThanOrEqualTo(fab.top));
      expect(menu.bottom, lessThanOrEqualTo(fab.top));
      expect(AppSpacing.fabClearance, greaterThan(fab.height));
    });
  });

  group('accessibility guidelines', () {
    // The query runs put the reorder hint on screen; the last one raises the
    // keyboard over it as well.
    for (final (scale, dark, query, keyboard) in const [
      (1.0, false, false, false),
      (2.0, true, false, false),
      (1.0, false, true, false),
      (2.0, false, true, true),
    ]) {
      final state = [
        if (dark) 'dark',
        if (query) 'a live query',
        if (keyboard) 'the keyboard up',
      ];
      testWidgets('tap targets, labelled taps and contrast at $scale'
          '${state.isEmpty ? '' : ', ${state.join(', ')}'}', (tester) async {
        final handle = tester.ensureSemantics();
        await service.setHidden('rest', true);
        if (query) await addCustoms(4);
        await pumpPage(
          tester,
          width: 360,
          height: 780,
          textScale: scale,
          dark: dark,
        );
        if (query) {
          await tester.enterText(find.byType(TextField), 'c');
          await tester.pumpAndSettle();
          expect(find.byType(ReorderLockedHint), findsOneWidget);
        }
        if (keyboard) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 330);
          addTearDown(tester.view.reset);
          await tester.pumpAndSettle();
        }

        // At the top, then at the end: at 2.0 the rows below the fold are
        // judged only once they are on screen.
        final list = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        );
        for (final atEnd in [false, true]) {
          if (atEnd) {
            final position = tester.state<ScrollableState>(list).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(
            tester,
            meetsGuideline(
              query
                  ? const _MergedTextFieldsAsideLabelGuideline()
                  : labeledTapTargetGuideline,
            ),
          );
          await expectLater(
            tester,
            meetsGuideline(const _HeadersAsideContrastGuideline()),
          );
        }

        // The headers by their tokens instead.
        final colors = Theme.of(
          tester.element(find.byType(CalendarCategoriesPage)),
        ).colorScheme;
        final text = colors.onSurfaceVariant.computeLuminance();
        final ground = colors.pageGround.computeLuminance();
        final ratio =
            (math.max(text, ground) + 0.05) / (math.min(text, ground) + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
        handle.dispose();
      });
    }
  });
}

/// Flutter's labelled-tap-target guideline with the text-field flag read
/// from the node's merged data. The stock check means to skip text fields
/// but reads the node's own flags, and the search field sits under an
/// `AutomationId`'s `MergeSemantics`: once a query replaces the hint the
/// field has no label and the stock check reports it. Every other node is
/// judged as the stock guideline judges it.
class _MergedTextFieldsAsideLabelGuideline extends AccessibilityGuideline {
  const _MergedTextFieldsAsideLabelGuideline();

  @override
  String get description =>
      '${labeledTapTargetGuideline.description}, merged text fields aside';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(view.owner!.semanticsOwner!.rootSemanticsNode!);
    }
    return result;
  }

  Evaluation _traverse(SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(child);
      return true;
    });
    if (node.isMergedIntoParent || node.isInvisible) return result;
    final data = node.getSemanticsData();
    if (data.flagsCollection.isHidden || data.flagsCollection.isTextField) {
      return result;
    }
    if (!data.hasAction(SemanticsAction.longPress) &&
        !data.hasAction(SemanticsAction.tap)) {
      return result;
    }
    if (data.label.isEmpty && data.tooltip.isEmpty) {
      result += Evaluation.fail(
        '$node: expected tappable node to have semantic label, '
        'but none was found.',
      );
    }
    return result;
  }
}

/// Android's text-contrast guideline with the section headers taken out by
/// id and judged from their tokens in the test instead: the guideline reads
/// the ink from the screenshot, and an 11 px label's anti-aliased strokes
/// never reach their colour — `onSurfaceVariant` on `pageGround`, well over
/// 4.5:1, sampled at 3.59:1.
class _HeadersAsideContrastGuideline extends MinimumTextContrastGuideline {
  const _HeadersAsideContrastGuideline();

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) ||
      data.identifier.startsWith('category-section-');

  @override
  String get description => '${super.description}, the section headers aside';
}

class _RecordingObserver extends BlocObserver {
  final List<Object?> events = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}
