import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';

/// The event editor's share switch (share surfaces §6.6, the slice C spec
/// §5): absent for a person who never paired, one height in every state,
/// following a category pick at once, and riding the draft — dirty, the
/// leave guard and the result — while the form itself writes nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;
  late AppDatabase settingsDb;

  final startDate = DateTime.utc(2026, 9, 20);

  ShareAudience audience([String? name = 'Maria']) =>
      ShareAudience(id: 'pair-1', displayName: name, members: const []);

  CalendarCategory category(String id, String name, int order, bool shared) =>
      CalendarCategory(
        id: id,
        name: name,
        colorValue: 0xFF43A047,
        iconKey: 'event',
        sortOrder: order,
        isBuiltIn: false,
        sharedByMe: shared,
      );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_editor_share');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    SettingsService.reset();
    settingsDb = await openTestDatabase();
    SettingsService.forTesting(settingsDb);
    CalendarCategories.updateCache([
      category('gym', 'Gym', 0, false),
      category('work', 'Work', 1, true),
    ]);
  });

  tearDown(() async {
    await barBloc.close();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    await settingsDb.close();
  });

  CalendarEvent eventOf({String categoryId = 'gym', bool shared = false}) =>
      CalendarEvent(
        id: 'e1',
        title: 'Dinner',
        categoryId: categoryId,
        startDate: startDate,
        markedShared: shared,
      );

  late _RouteRecorder routes;

  Future<List<EventEditorResult?>> open(
    WidgetTester tester, {
    CalendarEvent? initial,
    ShareAvailability availability = const ShareNotPaired(),
    bool sandbox = false,
    Locale locale = const Locale('en'),
    double scale = 1.0,
    Future<({ShareAvailability availability, bool markedShared})> Function()?
    reread,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.reset);
    routes = _RouteRecorder();
    final results = <EventEditorResult?>[];
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        navigatorObservers: [routes],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    Navigator.of(hostContext)
        .push<EventEditorResult>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: BlocProvider<MarkdownBarBloc>.value(
                value: barBloc,
                child: EventEditorSheet(
                  defaultDate: startDate,
                  initialEvent: initial,
                  sandbox: sandbox,
                  shareAvailability: availability,
                  rereadShare: reread,
                ),
              ),
            ),
          ),
        )
        .then(results.add);
    await tester.pumpAndSettle();
    return results;
  }

  /// The row's own widget, found by its id: the semantics finder needs a
  /// live tree, so it is built per use.
  Finder shareRowOf() => find.byWidgetPredicate(
    (w) => w is FormSwitchRow && w.identifier == SemanticsIds.eventShare,
  );

  FormSwitchRow row(WidgetTester tester) =>
      tester.widget<FormSwitchRow>(shareRowOf());

  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<EventEditorSaved> save(
    WidgetTester tester,
    List<EventEditorResult?> results,
  ) async {
    await tapAndSettle(tester, find.byType(FilledButton).first);
    return results.single as EventEditorSaved;
  }

  group('someone not paired', () {
    testWidgets('sees no share row, and the result says nothing of sharing', (
      tester,
    ) async {
      final results = await open(tester, initial: eventOf());

      expect(shareRowOf(), findsNothing);
      expect(find.byIcon(Icons.group_rounded), findsNothing);
      expect(find.textContaining('Share with'), findsNothing);
      // The DETAILS group ends on Linked note, as it always has.
      final details = tester.getRect(
        find.bySemanticsIdentifier(SemanticsIds.eventLinkedNote),
      );
      final template = tester.getRect(
        find.bySemanticsIdentifier(SemanticsIds.eventSaveAsTemplate),
      );
      expect(template.top, greaterThan(details.bottom));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is FormSwitchRow &&
              (w.identifier?.startsWith('event-share') ?? false),
        ),
        findsNothing,
      );

      expect((await save(tester, results)).shared, isNull);
    });

    testWidgets('the guide\'s sandbox never offers it, paired or not', (
      tester,
    ) async {
      await open(
        tester,
        initial: eventOf(),
        availability: ShareReady(audience()),
        sandbox: true,
      );

      expect(shareRowOf(), findsNothing);
    });
  });

  group('the row\'s states', () {
    testWidgets('off: only you see it, the switch toggles on', (tester) async {
      await open(
        tester,
        initial: eventOf(),
        availability: ShareReady(audience()),
      );

      expect(find.text('Share with Maria'), findsOneWidget);
      expect(row(tester).subtitle, 'Only you see this event');
      expect(row(tester).value, isFalse);
      expect(row(tester).onChanged, isNotNull);

      await tapAndSettle(tester, shareRowOf());
      expect(row(tester).value, isTrue);
      expect(row(tester).subtitle, 'Maria sees it, read-only');
    });

    testWidgets('on: the partner sees it, read-only', (tester) async {
      await open(
        tester,
        initial: eventOf(shared: true),
        availability: ShareReady(audience()),
      );

      expect(row(tester).subtitle, 'Maria sees it, read-only');
      expect(row(tester).value, isTrue);
      expect(row(tester).onChanged, isNotNull);
    });

    testWidgets('its category is shared: on and locked, naming it', (
      tester,
    ) async {
      await open(
        tester,
        initial: eventOf(categoryId: 'work'),
        availability: ShareReady(audience()),
      );

      expect(row(tester).subtitle, 'On for everything in Work');
      expect(row(tester).value, isTrue);
      expect(row(tester).onChanged, isNull);
      expect(row(tester).onDisabledTap, isNull);
    });

    testWidgets('not syncing: off and disabled, the row\'s tap opens Sync & '
        'sharing over the form', (tester) async {
      final results = await open(
        tester,
        initial: eventOf(shared: true),
        availability: ShareNotSyncing(audience()),
      );

      expect(row(tester).subtitle, 'Turn on sync to share');
      expect(row(tester).value, isFalse);
      expect(row(tester).onChanged, isNull);
      // Dimmed, yet it acts: it says where its tap goes.
      expect(row(tester).onDisabledTapHint, 'Opens Sync & sharing');

      await tester.ensureVisible(shareRowOf());
      await tester.pumpAndSettle();
      await tester.tap(shareRowOf());
      final pushed = routes.pushed.last;
      expect(pushed.settings.name, NavDestinationKind.syncSettings.name);
      // Taken down before its first frame: the page's blocs are the app's.
      pushed.navigator!.removeRoute(pushed);
      await tester.pumpAndSettle();

      expect(find.byType(EventEditorSheet), findsOneWidget);
      // The mark the event had is not what this row can change.
      expect((await save(tester, results)).shared, isTrue);
    });

    testWidgets('sync turned on over the form: the opener is asked again on '
        'the return, and the row follows', (tester) async {
      var asked = 0;
      final results = await open(
        tester,
        initial: eventOf(),
        availability: ShareNotSyncing(audience()),
        reread: () async {
          asked++;
          return (availability: ShareReady(audience()), markedShared: false);
        },
      );
      expect(row(tester).onChanged, isNull);

      await tester.ensureVisible(shareRowOf());
      await tester.pumpAndSettle();
      await tester.tap(shareRowOf());
      final pushed = routes.pushed.last;
      pushed.navigator!.removeRoute(pushed);
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(row(tester).subtitle, 'Only you see this event');
      expect(row(tester).onChanged, isNotNull);
      await tapAndSettle(tester, shareRowOf());
      expect((await save(tester, results)).shared, isTrue);
    });

    testWidgets('every share stopped over the form: on the return the switch '
        'reads the mark as stored now, and the form stays clean', (
      tester,
    ) async {
      final results = await open(
        tester,
        initial: eventOf(shared: true),
        availability: ShareNotSyncing(audience()),
        reread: () async =>
            (availability: ShareReady(audience()), markedShared: false),
      );

      await tester.ensureVisible(shareRowOf());
      await tester.pumpAndSettle();
      await tester.tap(shareRowOf());
      final pushed = routes.pushed.last;
      pushed.navigator!.removeRoute(pushed);
      await tester.pumpAndSettle();

      expect(row(tester).value, isFalse, reason: 'no longer shared');
      expect(row(tester).subtitle, 'Only you see this event');
      // Clean: ✕ leaves at once, asking nothing.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('without a profile name the partner is "your partner"', (
      tester,
    ) async {
      await open(
        tester,
        initial: eventOf(shared: true),
        availability: ShareReady(audience(null)),
      );

      expect(find.text('Share with your partner'), findsOneWidget);
      expect(row(tester).subtitle, 'Your partner sees it, read-only');
    });
  });

  group('one height in every state', () {
    Future<List<double>> heights(
      WidgetTester tester, {
      required Locale locale,
      required double scale,
      required String name,
    }) async {
      final sizes = <double>[];
      Future<void> measure() async {
        expect(tester.takeException(), isNull);
        sizes.add(tester.getSize(shareRowOf()).height);
      }

      await open(
        tester,
        initial: eventOf(),
        availability: ShareReady(audience(name)),
        locale: locale,
        scale: scale,
      );
      await measure();
      await tapAndSettle(tester, shareRowOf());
      expect(row(tester).value, isTrue);
      await measure();
      await open(
        tester,
        initial: eventOf(categoryId: 'work'),
        availability: ShareReady(audience(name)),
        locale: locale,
        scale: scale,
      );
      await measure();
      await open(
        tester,
        initial: eventOf(),
        availability: ShareNotSyncing(audience(name)),
        locale: locale,
        scale: scale,
      );
      await measure();
      return sizes;
    }

    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('at $scale', (tester) async {
        final sizes = await heights(
          tester,
          locale: const Locale('en'),
          scale: scale,
          name: 'Maria',
        );

        expect(sizes.toSet(), hasLength(1), reason: '$sizes');
        expect(
          sizes.first,
          greaterThanOrEqualTo(FormMetrics.twoLineRowMinHeight),
        );
      });
    }

    testWidgets('in German at 2.0 with a long name, nothing clipped', (
      tester,
    ) async {
      final sizes = await heights(
        tester,
        locale: const Locale('de'),
        scale: 2.0,
        name: 'Maximilian-Alexander',
      );

      expect(sizes.toSet(), hasLength(1), reason: '$sizes');
      expect(find.text('Mit Maximilian-Alexander teilen'), findsOneWidget);
    });
  });

  testWidgets('the subtitle follows a category pick at once, and the '
      'person\'s own choice comes back with an unshared category', (
    tester,
  ) async {
    final results = await open(tester, availability: ShareReady(audience()));
    await tester.enterText(find.byType(TextField).first, 'Dinner');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, shareRowOf());
    expect(row(tester).subtitle, 'Maria sees it, read-only');

    Future<void> pick(String id) async {
      await tapAndSettle(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.eventCategory),
      );
      await tapAndSettle(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.categoryPickRow(id)),
      );
    }

    await pick('work');
    expect(row(tester).subtitle, 'On for everything in Work');
    expect(row(tester).value, isTrue);
    expect(row(tester).onChanged, isNull);

    await pick('gym');
    expect(row(tester).subtitle, 'Maria sees it, read-only');
    expect(row(tester).onChanged, isNotNull);

    final saved = await save(tester, results);
    expect(saved.event.categoryId, 'gym');
    expect(saved.shared, isTrue, reason: 'a new event can be created shared');
    expect(
      saved.event.markedShared,
      isFalse,
      reason: 'the mark is the flow\'s to write, never the save\'s',
    );
  });

  group('the draft', () {
    testWidgets('a flip makes the form dirty, and the leave guard asks', (
      tester,
    ) async {
      await open(
        tester,
        initial: eventOf(),
        availability: ShareReady(audience()),
      );
      await tapAndSettle(tester, shareRowOf());

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EventEditorSheet), findsOneWidget);
    });

    testWidgets('flipped back, the form is clean again and leaves at once', (
      tester,
    ) async {
      final results = await open(
        tester,
        initial: eventOf(),
        availability: ShareReady(audience()),
      );
      await tapAndSettle(tester, shareRowOf());
      await tapAndSettle(tester, shareRowOf());

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(results.single, isNull);
    });

    testWidgets('Save carries the choice, and an untouched one as it was', (
      tester,
    ) async {
      var results = await open(
        tester,
        initial: eventOf(shared: true),
        availability: ShareReady(audience()),
      );
      await tapAndSettle(tester, shareRowOf());
      expect((await save(tester, results)).shared, isFalse);

      results = await open(
        tester,
        initial: eventOf(shared: true),
        availability: ShareReady(audience()),
      );
      expect((await save(tester, results)).shared, isTrue);
    });
  });

  testWidgets('the row meets the tap-target and labelled-target guidelines', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(
      tester,
      initial: eventOf(),
      availability: ShareReady(audience()),
    );
    await tester.ensureVisible(shareRowOf());
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  // Design review C9 and C15: the row measured as a phone draws it. The
  // fixed readings size the subtitle's slot; a shared category with a long
  // name is cut to it, never given a line of its own. Last in the file, so
  // no case above measures in anything but the test font.
  group('with real fonts', () {
    const longName = 'Weekly family dinners at the grandparents\' house';

    setUpAll(loadGoldenFonts);

    setUp(
      () => CalendarCategories.updateCache([
        category('gym', 'Gym', 0, false),
        category('work', 'Work', 1, true),
        category('long', longName, 2, true),
      ]),
    );

    /// The row's height in each of its states, the long category's
    /// included.
    Future<List<double>> heights(WidgetTester tester, double scale) async {
      final sizes = <double>[];
      for (final (initial, availability) in [
        (eventOf(), ShareReady(audience())),
        (eventOf(shared: true), ShareReady(audience())),
        (eventOf(categoryId: 'work'), ShareReady(audience())),
        (eventOf(categoryId: 'long'), ShareReady(audience())),
        (eventOf(), ShareNotSyncing(audience())),
      ]) {
        await open(
          tester,
          initial: initial,
          availability: availability,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        sizes.add(tester.getSize(shareRowOf()).height);
      }
      return sizes;
    }

    testWidgets('at 1.0 the row is 62 dp in every state, a long shared '
        'category cut to the line with an ellipsis', (tester) async {
      final sizes = await heights(tester, 1.0);

      expect(sizes.toSet(), {
        FormMetrics.twoLineRowMinHeight,
      }, reason: '$sizes');
      await open(
        tester,
        initial: eventOf(categoryId: 'long'),
        availability: ShareReady(audience()),
      );
      final line = tester.widget<Text>(
        find
            .descendant(
              of: shareRowOf(),
              matching: find.textContaining('On for everything in'),
            )
            .last,
      );
      expect(line.maxLines, 1);
      expect(line.overflow, TextOverflow.ellipsis);
    });

    for (final scale in const [1.3, 2.0]) {
      testWidgets('at $scale one height in every state', (tester) async {
        final sizes = await heights(tester, scale);

        expect(sizes.toSet(), hasLength(1), reason: '$sizes');
      });
    }

    testWidgets('the row meets the text-contrast guideline', (tester) async {
      final handle = tester.ensureSemantics();
      for (final (initial, availability) in [
        (eventOf(), ShareReady(audience())),
        (eventOf(categoryId: 'long'), ShareReady(audience())),
        (eventOf(), ShareNotSyncing(audience())),
      ]) {
        await open(tester, initial: initial, availability: availability);
        await tester.ensureVisible(shareRowOf());
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(const _ShareRowContrast()));
      }
      handle.dispose();
    });
  });
}

/// Android's text-contrast guideline on the share row's node alone: the
/// review found failures elsewhere in the form that belong to no share
/// slice (design review C14), told to the owner.
class _ShareRowContrast extends MinimumTextContrastGuideline {
  const _ShareRowContrast();

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) || data.identifier != SemanticsIds.eventShare;

  @override
  String get description => '${super.description}, on the share row';
}

class _RouteRecorder extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}
