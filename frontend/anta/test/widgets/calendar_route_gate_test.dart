import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/keyboard_coupled_size.dart';

import '../database/support/db_test_support.dart';

/// Guards the two things `_CalendarViewState` does *because* it is a
/// [RouteAware] page rather than the only thing on screen.
///
/// **The route-covered keyboard gate.** The calendar's keyboard coupling
/// listens to the ambient view insets, and a covered page keeps its element
/// subtree alive — so a keyboard raised in the note editor pushed on top of
/// the calendar used to collapse and re-expand a grid nobody was looking at,
/// rebuilding 42 cells twice per open/close cycle. `didPushNext` now mutes
/// `_handleKeyboardInset` and `didPopNext` unmutes it and re-syncs.
///
/// This file is the only place in the suite that registers
/// `AppNavigator.routeObserver` in `navigatorObservers` —
/// `calendar_keyboard_collapse_test.dart` deliberately does not, which is why
/// every case there exercises the *un*covered path. Without the observer the
/// gate can never engage and all of these tests would pass vacuously, so the
/// registration is load-bearing, not incidental setup.
///
/// **The resolver-output eviction.** `_evictColdResolverOutputs` prunes the
/// three per-day output memos to `CalendarBloc.dayCacheWindowFor`'s ±3 month
/// window on every genuine focused-month change; before it existed the memos
/// only ever cleared on a generation change and grew by a month of days for
/// every month the user paged through. The maps are private, so the map
/// *size* is not observable from here — what is observable is the eviction
/// itself: every read is a `??=`, so a day that was evicted comes back as a
/// freshly allocated `List<DayBar>` and a day that survived comes back as the
/// very same instance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;

  /// One database per test, shared by the settings facade and the repositories
  /// the page-level `ImportExportBloc` needs — same arrangement, and same
  /// reasons, as `calendar_keyboard_collapse_test.dart`.
  late AppDatabase testDb;
  late DateTime today;

  /// Three months apart by two: `near` is evicted by a focus on `far`
  /// (window `[near+1, near+8)`), `mid` is not. Both are in the future so the
  /// one-time events on them are ordinary un-missed occurrences.
  late DateTime nearDay;
  late DateTime midDay;
  late DateTime farDay;

  const nearKey = 'event:near';
  const midKey = 'event:mid';
  const farKey = 'event:far';

  // Everything below this line needs a database and a pumped page; the
  // `eviction window` group at the bottom of the file is pure arithmetic and
  // is deliberately left outside so it does not open one per case.
  group('CalendarPage', () {
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'anta_calendar_route_gate',
      );
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

    Future<void> dispatch(CalendarPageEvent event) async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 30));
      bloc.add(event);
      await next;
    }

    setUp(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      testDb = await openTestDatabase();
      SettingsService.forTesting(testDb);

      final service = await CalendarEventService.getInstance();
      await service.deleteAll();
      bloc = CalendarBloc(service: service);
      await dispatch(const LoadCalendarEvents());

      final now = DateTime.now();
      today = DateTime.utc(now.year, now.month, now.day);
      nearDay = DateTime.utc(now.year, now.month + 1, 15);
      midDay = DateTime.utc(now.year, now.month + 3, 15);
      farDay = DateTime.utc(now.year, now.month + 5, 15);

      // One marker event per month under test, so a rendered bar list can be
      // located by the day it belongs to rather than by its position in tree
      // order — the grid also paints outside days from the neighbouring months,
      // which a positional snapshot cannot tell apart.
      for (final (id, day) in [
        ('near', nearDay),
        ('mid', midDay),
        ('far', farDay),
      ]) {
        await dispatch(
          CreateCalendarEvent(
            event: CalendarEvent(
              id: id,
              title: 'Marker $id',
              categoryId: 'gym',
              startDate: day,
              rule: const OneTimeRecurrence(),
            ),
          ),
        );
      }
      // Created last on purpose: `_onCreateEvent` re-focuses the grid on the new
      // event's start date, so this is what leaves the page opening on today.
      // It also guarantees every painted day carries a bar, which is what
      // `pumpCalendar` waits for.
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'daily',
            title: 'Leg day',
            categoryId: 'gym',
            startDate: today,
            rule: const DailyRecurrence(),
          ),
        ),
      );

      final noteRepository = NoteRepository(database: testDb);
      final folderRepository = FolderRepository(database: testDb);
      importExportBloc = ImportExportBloc(
        service: ImportExportService(
          noteStorage: NoteStorageService(repository: noteRepository),
          folderStorage: FolderStorageService(repository: folderRepository),
          noteRepository: noteRepository,
        ),
      );
    });

    tearDown(() async {
      await bloc.close();
      await importExportBloc.close();
      SettingsService.reset();
      await testDb.close();
    });

    /// A phone-width surface tall enough to hold a month grid plus a keyboard,
    /// at device pixel ratio 1 so [FakeViewPadding]'s physical pixels read as
    /// logical ones.
    void sizeSurface(WidgetTester tester) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
    }

    Future<void> setPanelMode(CalendarPanelMode mode) async {
      final settings = await SettingsService.getInstance();
      await settings.setCalendarPanelMode(mode);
    }

    /// The one thing this file does differently from its siblings: the real
    /// `AppNavigator.routeObserver` is registered, so `didPushNext` /
    /// `didPopNext` actually reach the page.
    Future<void> pumpCalendar(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<CalendarBloc>.value(value: bloc),
            BlocProvider<ImportExportBloc>.value(value: importExportBloc),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            navigatorObservers: [AppNavigator.routeObserver],
            home: const CalendarPage(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// `skipOffstage: false` because an opaque `PageRoute` on top pushes the
    /// calendar's overlay entry offstage: it is still built (and therefore can
    /// still be wrongly rebuilt by a keyboard), but the default finders would
    /// stop seeing it — and a test that cannot see the grid cannot prove the
    /// grid was left alone.
    TableCalendar<CalendarEvent> grid(WidgetTester tester) =>
        tester.widget<TableCalendar<CalendarEvent>>(
          find.byType(TableCalendar<CalendarEvent>, skipOffstage: false),
        );

    BuildContext calendarContext(WidgetTester tester) =>
        tester.element(find.byType(CalendarPage, skipOffstage: false));

    /// Covers the calendar with an ordinary opaque page route — what the note
    /// editor, the settings pages and the database page all are.
    Future<void> pushPageAbove(WidgetTester tester) async {
      unawaited(
        Navigator.of(calendarContext(tester)).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Covers the calendar with a `PopupRoute`, which `RouteObserver<PageRoute>`
    /// never reports — the calendar's own editor/detail/filter sheets are all
    /// of this kind, and their keyboards are the reason the collapse exists.
    Future<void> pushSheetAbove(WidgetTester tester) async {
      unawaited(
        showModalBottomSheet<void>(
          context: calendarContext(tester),
          builder: (_) => const SizedBox(height: 200),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> popRouteAbove(WidgetTester tester) async {
      Navigator.of(calendarContext(tester)).pop();
      await tester.pumpAndSettle();
    }

    void setInset(WidgetTester tester, double inset) {
      if (inset <= 0) {
        tester.view.resetViewInsets();
      } else {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
      }
    }

    /// Walks the inset from [from] to [to] one frame at a time, the way an IME
    /// on API 30+ reports its own animation.
    Future<void> rampKeyboard(
      WidgetTester tester,
      double from,
      double to, {
      int frames = 10,
    }) async {
      for (var i = 1; i <= frames; i++) {
        setInset(tester, from + (to - from) * (i / frames));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> showKeyboard(WidgetTester tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
    }

    Future<void> hideKeyboard(WidgetTester tester) async {
      tester.view.resetViewInsets();
      await tester.pump();
    }

    /// Height of the page's own `AnimatedSize` and of the grid animator it
    /// wraps — the same probe pair `calendar_keyboard_collapse_test.dart` uses.
    (double outer, double inner) heights(WidgetTester tester) => (
      tester.getSize(find.byType(AnimatedSize).first).height,
      tester.getSize(find.byType(KeyboardCoupledSize)).height,
    );

    /// One completed open/close cycle, returning the collapsed height. This is
    /// what teaches `KeyboardInsetTracker` how tall this keyboard is: the show
    /// path has no observed peak of its own to divide by.
    Future<double> learnKeyboardHeight(WidgetTester tester) async {
      await showKeyboard(tester);
      await tester.pumpAndSettle();
      final weekHeight = heights(tester).$1;
      await hideKeyboard(tester);
      await tester.pumpAndSettle();
      return weekHeight;
    }

    /// Focuses [day] the way every programmatic navigation does, then lets the
    /// page animation finish so exactly one month page is mounted.
    Future<void> focusDay(WidgetTester tester, DateTime day) async {
      await tester.runAsync(() async {
        final next = bloc.stream.first.timeout(const Duration(seconds: 10));
        bloc.add(
          SelectCalendarDay(
            day: day,
            focusedDay: day,
            source: CalendarSelectionSource.navigation,
          ),
        );
        await next;
      });
      await tester.pumpAndSettle();
    }

    /// The rendered `List<DayBar>` of the one cell carrying [barKey], or null
    /// when that day is not on screen. The instance itself is the assertion
    /// subject: it is whatever `_barsOutputCache[day] ??= resolve(...)` handed
    /// out, so identity across two visits distinguishes a cache hit from a
    /// recompute.
    List<DayBar>? barsCarrying(WidgetTester tester, String barKey) {
      for (final widget in tester.widgetList<CalendarDayBars>(
        find.byType(CalendarDayBars),
      )) {
        if (widget.bars.any((bar) => bar.key == barKey)) return widget.bars;
      }
      return null;
    }

    group('the route-covered keyboard gate', () {
      testWidgets('a page route above the calendar mutes the collapse', (
        tester,
      ) async {
        sizeSurface(tester);
        await setPanelMode(CalendarPanelMode.upcoming);
        await pumpCalendar(tester);
        await tester.pumpAndSettle();
        expect(grid(tester).calendarFormat, CalendarFormat.month);

        await pushPageAbove(tester);
        await rampKeyboard(tester, 0, 320);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          grid(tester).calendarFormat,
          CalendarFormat.month,
          reason:
              'the keyboard belongs to the page on top — collapsing here '
              'rebuilds 42 cells nobody can see',
        );
        expect(
          grid(tester).onFormatChanged,
          isNotNull,
          reason:
              'the format override is not engaged at all, so the swipe gesture '
              'is not locked out either',
        );

        setInset(tester, 0);
        await tester.pump();
      });

      testWidgets('a modal sheet above the calendar still collapses it', (
        tester,
      ) async {
        sizeSurface(tester);
        await setPanelMode(CalendarPanelMode.upcoming);
        await pumpCalendar(tester);
        await tester.pumpAndSettle();

        await pushSheetAbove(tester);
        await rampKeyboard(tester, 0, 320);

        expect(
          grid(tester).calendarFormat,
          CalendarFormat.week,
          reason:
              'a PopupRoute is not a PageRoute, so RouteObserver<PageRoute> '
              'never reports it — and a sheet keyboard is the case the '
              'collapse exists for',
        );
        expect(grid(tester).onFormatChanged, isNull);

        setInset(tester, 0);
        await tester.pump();
        await tester.pumpAndSettle();
      });

      testWidgets('an uncovered calendar still collapses', (tester) async {
        sizeSurface(tester);
        await setPanelMode(CalendarPanelMode.upcoming);
        await pumpCalendar(tester);
        await tester.pumpAndSettle();

        await rampKeyboard(tester, 0, 320);
        expect(
          grid(tester).calendarFormat,
          CalendarFormat.week,
          reason:
              'subscribing to the route observer must not arm the gate by '
              'itself — with nothing on top the page is not covered',
        );

        await rampKeyboard(tester, 320, 0);
        await tester.pumpAndSettle();
        expect(grid(tester).calendarFormat, CalendarFormat.month);
      });

      testWidgets('the grid follows the keyboard again once the route pops', (
        tester,
      ) async {
        sizeSurface(tester);
        await setPanelMode(CalendarPanelMode.upcoming);
        await pumpCalendar(tester);
        await tester.pumpAndSettle();

        await pushPageAbove(tester);
        await rampKeyboard(tester, 0, 320);
        expect(grid(tester).calendarFormat, CalendarFormat.month);

        await popRouteAbove(tester);
        expect(
          grid(tester).calendarFormat,
          CalendarFormat.week,
          reason:
              'didPopNext re-syncs with the inset that is actually on screen — '
              'coming back to a raised keyboard over an expanded month grid is '
              'the stuck-expanded half of the bug',
        );

        await rampKeyboard(tester, 320, 0);
        await tester.pumpAndSettle();
        expect(
          grid(tester).calendarFormat,
          CalendarFormat.month,
          reason: 'and not stuck collapsed either',
        );

        await rampKeyboard(tester, 0, 320);
        expect(
          grid(tester).calendarFormat,
          CalendarFormat.week,
          reason: 'a keyboard after the whole cycle is an ordinary keyboard',
        );
        await rampKeyboard(tester, 320, 0);
        await tester.pumpAndSettle();
        expect(grid(tester).calendarFormat, CalendarFormat.month);
      });

      testWidgets(
        'a cover-and-uncover cycle keeps the learned keyboard height',
        (tester) async {
          sizeSurface(tester);
          await setPanelMode(CalendarPanelMode.upcoming);
          await pumpCalendar(tester);
          await tester.pumpAndSettle();

          final monthHeight = heights(tester).$1;
          final weekHeight = await learnKeyboardHeight(tester);
          expect(weekHeight, lessThan(monthHeight));
          expect(heights(tester).$1, monthHeight);

          await pushPageAbove(tester);
          await popRouteAbove(tester);
          expect(
            heights(tester).$1,
            monthHeight,
            reason: 'the cover/uncover happened with no keyboard on screen',
          );

          final samples = <double>[];
          for (var i = 1; i <= 10; i++) {
            setInset(tester, 32.0 * i);
            await tester.pump(const Duration(milliseconds: 16));
            samples.add(heights(tester).$1);
          }

          for (var i = 1; i < samples.length; i++) {
            expect(samples[i], lessThanOrEqualTo(samples[i - 1]));
          }
          expect(
            samples.last,
            weekHeight,
            reason:
                'the learned peak is the only thing that makes the *opening* '
                'collapse coupled to the IME instead of a 250ms tween, and this '
                'ramp is 160ms: landing exactly on the collapsed height proves '
                'didPopNext re-synced the tracker without resetting it',
          );

          setInset(tester, 0);
          await tester.pump();
          await tester.pumpAndSettle();
        },
      );
    });

    group('the resolver-output cache eviction', () {
      testWidgets('paging far drops the month left behind, keeps the near one', (
        tester,
      ) async {
        sizeSurface(tester);
        await setPanelMode(CalendarPanelMode.upcoming);
        await pumpCalendar(tester);
        await tester.pumpAndSettle();

        await focusDay(tester, nearDay);
        final nearFirst = barsCarrying(tester, nearKey);
        expect(nearFirst, isNotNull);

        await focusDay(tester, midDay);
        final midFirst = barsCarrying(tester, midKey);
        expect(midFirst, isNotNull);
        expect(
          barsCarrying(tester, nearKey),
          isNull,
          reason: 'two months back is off screen, so nothing repaints it',
        );

        // Focus lands four months past `near`: its window is
        // `[near+1, near+8)`, which excludes `near` and includes `mid`.
        await focusDay(tester, farDay);
        expect(
          barsCarrying(tester, farKey),
          isNotNull,
          reason:
              'eviction runs from the listener, before the grid rebuilds — it '
              'must never prune a day the very next frame is about to paint',
        );

        await focusDay(tester, nearDay);
        final nearSecond = barsCarrying(tester, nearKey);
        expect(nearSecond, isNotNull);
        expect(
          identical(nearSecond, nearFirst),
          isFalse,
          reason:
              'the far focus put this month outside the ±3 month window, so it '
              'must have been evicted and re-resolved — without eviction its '
              'entries would still be sitting in the memo, unbounded',
        );

        await focusDay(tester, midDay);
        expect(
          identical(barsCarrying(tester, midKey), midFirst),
          isTrue,
          reason:
              'this month never left the window, so it must still be the exact '
              'instance from its first visit — which also proves the output '
              'generation never moved across this whole journey, and therefore '
              'that the near-month recompute above was the eviction and not a '
              'wholesale cache clear',
        );
      });
    });
  });

  group('the eviction window', () {
    // A pure companion to the widget test above: the property it cannot
    // observe (that the window is wide enough for everything the grid can
    // paint) is arithmetic, and `gridDaysForMonth` already states exactly
    // which 42 days a month page paints.
    final anchors = [
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 2, 28),
      DateTime.utc(2024, 2, 29),
      DateTime.utc(2026, 6, 15),
      DateTime.utc(2026, 11, 30),
      DateTime.utc(2026, 12, 31),
    ];

    for (final focused in anchors) {
      test('$focused keeps every day the grid can page to', () {
        final (start, endExclusive) = CalendarBloc.dayCacheWindowFor(focused);
        // `TableCalendarBase` mounts the focused month and one neighbour for
        // the length of a page slide, and the prewarm warms the same radius.
        for (var monthOffset = -1; monthOffset <= 1; monthOffset++) {
          final month = DateTime.utc(focused.year, focused.month + monthOffset);
          for (final start2 in StartingDayOfWeek.values) {
            for (final day in gridDaysForMonth(month, start2)) {
              expect(
                day.isBefore(start) || !day.isBefore(endExclusive),
                isFalse,
                reason:
                    '$day is painted at focus $month but falls outside '
                    '[$start, $endExclusive)',
              );
            }
          }
        }
      });

      test('$focused evicts three whole months either side', () {
        final (start, endExclusive) = CalendarBloc.dayCacheWindowFor(focused);
        expect(start, DateTime.utc(focused.year, focused.month - 3));
        expect(endExclusive, DateTime.utc(focused.year, focused.month + 4));
        expect(
          DateTime.utc(focused.year, focused.month - 3, 1).isBefore(start),
          isFalse,
        );
      });
    }
  });
}
