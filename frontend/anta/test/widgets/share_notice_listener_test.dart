import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/models/share_notice.dart';
import 'package:anta/pages/sharing_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/kept_share_notices.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/utils/custom_snackbar.dart';
import 'package:anta/utils/share_copy.dart';
import 'package:anta/widgets/share_notice_listener.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';

/// The app's one voice for share notices (share surfaces §6.14, D23): the
/// words for each notice in each language, when they are said — at once in
/// front, held and merged while not, the leave before the arrival — and the
/// View action's way to the Sharing page.
///
/// The listener sits in the app's builder as it does in `main.dart`, over a
/// navigator keyed and observed as the app's is, under a page with a
/// Scaffold to carry the bar.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final en = AppLocalizationsEn();
  final de = AppLocalizationsDe();
  final ro = AppLocalizationsRo();

  ShareReady pairedWith(String? name) => ShareReady(
    ShareAudience(id: 'pair-1', displayName: name, members: const []),
  );

  late FakeShareService share;
  var opens = 0;

  /// Whether an alert is in front, as `main.dart` answers the listener.
  var alerting = false;

  /// How often the catalogue was asked for, and what it puts in the cache.
  var catalogueLoads = 0;
  var catalogue = const <CalendarCategory>[];

  /// What a check kept with the database while the app was closed, read as
  /// the store hands it — reading clears nothing — and how often it was
  /// asked.
  var kept = <ShareNotice>[];
  var keptAsked = 0;

  /// What the listener told the store it had dealt with, in order; the
  /// store forgets exactly that, once [forgetting] lets it — null is at
  /// once.
  var forgotten = <KeptNoticesSaid>[];
  Completer<void>? forgetting;

  /// The partner's events the calendar no longer holds — gone again
  /// before their arrival was said.
  var goneEvents = <String>{};

  /// A calendar, or a store, that answers when the test lets it: each null
  /// answers at once from [goneEvents] and [kept].
  Future<Set<String>> Function(Iterable<String> ids)? heldOverride;
  Future<List<ShareNotice>> Function()? keptOverride;

  /// What the app's builder handed the listener, to show it draws nothing
  /// of its own.
  Widget? shellChild;

  const gym = CalendarCategory(
    id: 'gym',
    name: 'stored gym name',
    colorValue: 0xFF1E88E5,
    iconKey: 'fitness_center',
    sortOrder: 0,
    isBuiltIn: true,
  );
  const shifts = CalendarCategory(
    id: 'c-shifts',
    name: 'Shifts',
    colorValue: 0xFF43A047,
    iconKey: 'event',
    sortOrder: 1,
    isBuiltIn: false,
    fromPartner: true,
  );
  const choir = CalendarCategory(
    id: 'c-choir',
    name: 'Choir',
    colorValue: 0xFF8E24AA,
    iconKey: 'event',
    sortOrder: 2,
    isBuiltIn: false,
    fromPartner: true,
  );

  const dinner = (id: 'e-dinner', title: 'Dinner');
  const run = (id: 'e-run', title: 'Run');
  const lunch = (id: 'e-lunch', title: 'Lunch');

  setUp(() {
    share = FakeShareService(availability: pairedWith('Ana'));
    opens = 0;
    alerting = false;
    catalogueLoads = 0;
    catalogue = const [gym, shifts, choir];
    shellChild = null;
    kept = [];
    keptAsked = 0;
    forgotten = [];
    forgetting = null;
    goneEvents = {};
    heldOverride = null;
    keptOverride = null;
    CalendarCategories.updateCache(catalogue);
    // A hide's notice is said while the category stands hidden.
    CalendarCategories.updatePartnerHidden({'c-shifts', 'gym'});
    CustomSnackbar.forgetActionBar();
  });

  tearDown(() {
    CalendarCategories.updateCache(const []);
    CalendarCategories.updatePartnerHidden(const {});
  });

  /// [notices] as the store holds them once [said] is forgotten: each id
  /// out of the list of its own kind, a notice with nothing left gone.
  List<ShareNotice> withoutSaid(
    List<ShareNotice> notices,
    KeptNoticesSaid said,
  ) => [
    for (final notice in notices)
      ...switch (notice) {
        ShareLeftWithAlert(:final events, :final partnerName) => [
          if (events.any((e) => !said.left.contains(e.id)))
            ShareLeftWithAlert([
              for (final e in events)
                if (!said.left.contains(e.id)) e,
            ], partnerName: partnerName),
        ],
        ShareArrived(:final categoryIds, :final events) => [
          if (categoryIds.any((id) => !said.categories.contains(id)) ||
              events.any((e) => !said.events.contains(e.id)))
            ShareArrived(
              categoryIds: [
                for (final id in categoryIds)
                  if (!said.categories.contains(id)) id,
              ],
              events: [
                for (final e in events)
                  if (!said.events.contains(e.id)) e,
              ],
            ),
        ],
        ShareHiddenWithAlerts() => [notice],
      },
  ];

  Future<void> pumpApp(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    Size size = const Size(412, 915),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppNavigator.navigatorKey,
        navigatorObservers: [
          AppNavigator.routeObserver,
          ShareNoticeListener.routes,
        ],
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: ShareNoticeListener(
            shareService: () async {
              opens++;
              return share;
            },
            loadCategories: () async {
              catalogueLoads++;
              CalendarCategories.updateCache(catalogue);
              return null;
            },
            alertInFront: () => alerting,
            partnerEventsHeld: (ids) =>
                heldOverride?.call(ids) ??
                Future.value(ids.toSet().difference(goneEvents)),
            keptNotices: () {
              keptAsked++;
              return keptOverride?.call() ?? Future.value(kept);
            },
            forgetKept: (said) async {
              forgotten.add(said);
              await forgetting?.future;
              kept = withoutSaid(kept, said);
            },
            child: shellChild = child!,
          ),
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pump();
  }

  /// What [settleBar] spends of a bar's time.
  const settled = Duration(milliseconds: 750);

  /// A bar's whole turn, from being said to the listener's next bar: its
  /// time on screen and the transitions around it.
  final barTurn =
      AppConstants.shareNoticeDuration + AppConstants.snackbarTransitions;

  /// A moment before a bar's own time has passed, counted from being said.
  const justShort = Duration(milliseconds: 100);

  /// Lets a notice reach the listener and its bar finish coming in.
  Future<void> settleBar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(settled);
  }

  /// From a settled bar to the end of its turn.
  Future<void> waitOutBar(WidgetTester tester) =>
      tester.pump(barTurn - settled);

  /// From a settled bar to a moment before its time has passed.
  Future<void> nearlyThrough(WidgetTester tester) =>
      tester.pump(AppConstants.shareNoticeDuration - settled - justShort);

  Future<void> say(WidgetTester tester, ShareNotice notice) async {
    ShareService.notify(notice);
    await settleBar(tester);
  }

  Finder bar() => find.byType(SnackBar);
  Finder view() => find.bySemanticsIdentifier(SemanticsIds.shareNoticeView);

  group('the words, in English', () {
    final cases = <(String, ShareNotice, String, bool)>[
      (
        'one category',
        const ShareArrived(categoryIds: ['c-shifts']),
        'Ana shares Shifts with you',
        true,
      ),
      (
        'several categories',
        const ShareArrived(categoryIds: ['c-shifts', 'c-choir']),
        en.shareNewManyFromPartner('Ana', 2),
        true,
      ),
      (
        'a category wins over events beside it',
        const ShareArrived(categoryIds: ['c-shifts'], events: [dinner]),
        en.shareNewFromPartner('Ana', 'Shifts'),
        true,
      ),
      (
        'one event',
        const ShareArrived(events: [dinner]),
        en.shareNewFromPartner('Ana', 'Dinner'),
        true,
      ),
      (
        'several events',
        const ShareArrived(events: [dinner, run, lunch]),
        en.shareNewFromPartner('Ana', en.shareSummaryEvents(3)),
        true,
      ),
      (
        'two events of one title, counted as two',
        const ShareArrived(events: [run, (id: 'e-run-2', title: 'Run')]),
        en.shareNewFromPartner('Ana', en.shareSummaryEvents(2)),
        true,
      ),
      (
        'one event left with my alert',
        const ShareLeftWithAlert([dinner]),
        'Ana no longer shares Dinner. Your alert is off.',
        false,
      ),
      (
        'several events left with my alerts',
        const ShareLeftWithAlert([dinner, run]),
        en.shareGoneWithAlerts(2, 'Ana'),
        false,
      ),
      (
        'two events of one title left with my alerts, counted as two',
        const ShareLeftWithAlert([
          (id: 'e-gym-1', title: 'Gym'),
          (id: 'e-gym-2', title: 'Gym'),
        ]),
        en.shareGoneWithAlerts(2, 'Ana'),
        false,
      ),
    ];
    for (final (what, notice, words, viewed) in cases) {
      testWidgets('$what: "$words"${viewed ? ', with View' : ''}', (
        tester,
      ) async {
        await pumpApp(tester);
        await say(tester, notice);

        expect(bar(), findsOneWidget);
        expect(find.text(words), findsOneWidget);
        expect(find.text(en.shareView), viewed ? findsOneWidget : findsNothing);
        expect(view(), viewed ? findsOneWidget : findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('a built-in category is named by my own label for it', (
      tester,
    ) async {
      share.sharedBuiltIns = {'gym'};
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['gym']));

      final label = CalendarCategories.builtInLabel(
        CalendarEventCategory.gym,
        en,
      );
      expect(find.text(en.shareNewFromPartner('Ana', label)), findsOneWidget);
      expect(find.textContaining(gym.name), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a leave names the partner as the pair did, though the pair '
        'is gone (D35)', (tester) async {
      share = FakeShareService(availability: const ShareNotPaired());
      await pumpApp(tester);
      await say(tester, const ShareLeftWithAlert([dinner], partnerName: 'Ana'));

      expect(
        find.text('Ana no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a partner with no name is the stand-in, starting the '
        'sentence', (tester) async {
      share = FakeShareService(availability: pairedWith(null));
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      expect(find.text('Your partner shares Shifts with you'), findsOneWidget);
      // Said in full, the bar for the leave reads the same way.
      await waitOutBar(tester);
      await say(tester, const ShareLeftWithAlert([dinner]));
      expect(
        find.text('Your partner no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the words, in German and Romanian', () {
    for (final (locale, l10n) in <(Locale, AppLocalizations)>[
      (const Locale('de'), de),
      (const Locale('ro'), ro),
    ]) {
      testWidgets('${locale.languageCode}: an arrival with View, then a '
          'leave', (tester) async {
        await pumpApp(tester, locale: locale);
        await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
        expect(
          find.text(l10n.shareNewFromPartner('Ana', 'Shifts')),
          findsOneWidget,
        );
        expect(find.text(l10n.shareView), findsOneWidget);

        await waitOutBar(tester);
        await say(
          tester,
          const ShareLeftWithAlert([(id: 'e-dinner', title: 'Abendessen')]),
        );
        expect(
          find.text(l10n.shareGoneWithAlert('Ana', 'Abendessen')),
          findsOneWidget,
        );
        expect(find.text(l10n.shareView), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    // Romanian's `few` runs from 2 to 19; `other` from 20 takes "de".
    for (final count in [2, 5, 20]) {
      testWidgets('ro: $count events left with my alerts', (tester) async {
        await pumpApp(tester, locale: const Locale('ro'));
        await say(
          tester,
          ShareLeftWithAlert([
            for (var i = 0; i < count; i++) (id: 'e$i', title: 'E$i'),
          ]),
        );

        final words = ro.shareGoneWithAlerts(count, 'Ana');
        expect(find.text(words), findsOneWidget);
        expect(
          words,
          count == 20
              ? contains('20 de evenimente')
              : contains('$count evenimente'),
        );

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('de: the stand-in is the German word', (tester) async {
      share = FakeShareService(availability: pairedWith('  '));
      await pumpApp(tester, locale: const Locale('de'));
      await say(
        tester,
        const ShareArrived(events: [(id: 'e-dinner', title: 'Abendessen')]),
      );

      expect(
        find.text(
          ShareCopy.sentence(
            de.shareNewFromPartner(de.sharePartnerFallback, 'Abendessen'),
          ),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('when it is said', () {
    testWidgets('an empty notice says nothing and opens no service', (
      tester,
    ) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived());
      await say(tester, const ShareLeftWithAlert([]));

      expect(bar(), findsNothing);
      expect(opens, 0);
      expect(catalogueLoads, 0);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('never paired: the listener draws nothing of its own and '
        'opens no share service', (tester) async {
      share = FakeShareService();
      await pumpApp(tester);
      await tester.pump(const Duration(seconds: 1));

      Widget? built;
      tester
          .element(find.byType(ShareNoticeListener))
          .visitChildElements((child) => built = child.widget);
      expect(built, same(shellChild));
      expect(opens, 0);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('held while the app is away, merged without a repeat, and '
        'said on resume', (tester) async {
      await pumpApp(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      await say(tester, const ShareArrived(events: [dinner]));
      await say(tester, const ShareArrived(events: [dinner, run]));
      expect(bar(), findsNothing);
      expect(opens, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settleBar(tester);
      expect(bar(), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBar(tester);
      expect(
        find.text(en.shareNewFromPartner('Ana', en.shareSummaryEvents(2))),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('held events merge by id: a later notice for one renames it, '
        'and two of one title stay two', (tester) async {
      await pumpApp(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await say(tester, const ShareArrived(events: [dinner]));
      await say(
        tester,
        const ShareArrived(events: [(id: 'e-dinner', title: 'Supper')]),
      );
      await say(
        tester,
        const ShareLeftWithAlert([(id: 'e-gym-1', title: 'Gym')]),
      );
      await say(
        tester,
        const ShareLeftWithAlert([(id: 'e-gym-2', title: 'Gym')]),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBar(tester);
      expect(find.text(en.shareGoneWithAlerts(2, 'Ana')), findsOneWidget);

      await waitOutBar(tester);
      await settleBar(tester);
      expect(
        find.text(en.shareNewFromPartner('Ana', 'Supper')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('held categories merge without a repeat', (tester) async {
      await pumpApp(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBar(tester);

      expect(find.text(en.shareNewFromPartner('Ana', 'Shifts')), findsOne);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with both held, the leave is said first and the arrival '
        'after it, each for its own time', (tester) async {
      await pumpApp(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await say(tester, const ShareArrived(events: [run]));
      await say(tester, const ShareLeftWithAlert([dinner]));
      await say(tester, const ShareLeftWithAlert([dinner]));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBar(tester);
      final left = find.text(en.shareGoneWithAlert('Ana', 'Dinner'));
      final arrived = find.text(en.shareNewFromPartner('Ana', 'Run'));
      expect(left, findsOneWidget);
      expect(arrived, findsNothing);

      // A moment before the leave's time has passed: still the leave.
      await nearlyThrough(tester);
      expect(left, findsOneWidget);
      expect(arrived, findsNothing);

      await tester.pump(barTurn - AppConstants.shareNoticeDuration + justShort);
      await settleBar(tester);
      expect(left, findsNothing);
      expect(arrived, findsOneWidget);

      // The arrival keeps its own time, then leaves.
      await nearlyThrough(tester);
      expect(arrived, findsOneWidget);
      await tester.pump(barTurn);
      await settleBar(tester);
      expect(arrived, findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a notice while a bar of its own is up waits for it rather '
        'than taking it down', (tester) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      final arrived = find.text(en.shareNewFromPartner('Ana', 'Shifts'));
      expect(arrived, findsOneWidget);

      await say(tester, const ShareLeftWithAlert([dinner]));
      final left = find.text(en.shareGoneWithAlert('Ana', 'Dinner'));
      expect(arrived, findsOneWidget);
      expect(left, findsNothing);

      // The second `say` spent another settle of the arrival's time.
      await tester.pump(barTurn - settled * 2);
      await settleBar(tester);
      expect(left, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a bar with an action that is up is waited out, never taken '
        'down', (tester) async {
      await pumpApp(tester);
      CustomSnackbar.showWithAction(
        tester.element(find.byType(Scaffold)),
        message: 'Event deleted',
        actionLabel: 'Undo',
        onAction: () {},
      );
      await settleBar(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      final undo = find.text('Event deleted');
      final arrived = find.text(en.shareNewFromPartner('Ana', 'Shifts'));
      expect(undo, findsOneWidget);
      expect(arrived, findsNothing);

      await tester.pump(
        AppConstants.snackbarActionDefaultDuration +
            AppConstants.snackbarTransitions,
      );
      await settleBar(tester);
      expect(undo, findsNothing);
      expect(arrived, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('while an alert is in front it waits, and is said once the '
        'alert has gone', (tester) async {
      await pumpApp(tester);
      alerting = true;
      unawaited(
        AppNavigator.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('ringing')),
          ),
        ),
      );
      await settleBar(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      final arrived = find.text(en.shareNewFromPartner('Ana', 'Shifts'));
      expect(arrived, findsNothing);
      await tester.pump(barTurn);
      expect(arrived, findsNothing);

      alerting = false;
      AppNavigator.navigatorKey.currentState!.pop();
      await settleBar(tester);
      expect(find.text('ringing'), findsNothing);
      expect(arrived, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('held under one database, it is dropped unsaid under '
        'another', (tester) async {
      await pumpApp(tester);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await say(tester, const ShareArrived(events: [dinner]));
      await say(tester, const ShareLeftWithAlert([run]));
      DatabaseLifecycle.notifyDatabaseSwitching();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBar(tester);
      expect(bar(), findsNothing);

      // What arrives under the database now open is said as ever.
      await say(tester, const ShareArrived(events: [lunch]));
      expect(find.text(en.shareNewFromPartner('Ana', 'Lunch')), findsOne);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a built-in category is worded from the loaded catalogue, '
        'never as "Other"', (tester) async {
      share.sharedBuiltIns = {'gym'};
      CalendarCategories.updateCache(const []);
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['gym']));

      final label = CalendarCategories.builtInLabel(
        CalendarEventCategory.gym,
        en,
      );
      expect(find.text(en.shareNewFromPartner('Ana', label)), findsOneWidget);
      expect(catalogueLoads, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('over a sheet, under a dialog', () {
    final arrived = find.text(en.shareNewFromPartner('Ana', 'Shifts'));

    Future<void> openSheet(WidgetTester tester, {bool guarded = false}) async {
      unawaited(
        showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          isScrollControlled: true,
          builder: (_) => PopScope(
            canPop: !guarded,
            child: const SizedBox(height: 600, child: Text('sheet')),
          ),
        ),
      );
      await settleBar(tester);
    }

    testWidgets('over a sheet the bar is seen, and its View can be tapped', (
      tester,
    ) async {
      await pumpApp(tester);
      await openSheet(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));

      expect(find.text('sheet'), findsOneWidget);
      expect(arrived.hitTestable(), findsOneWidget);
      expect(view().hitTestable(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('over a sheet that may hold a draft it waits, and is said '
        'when the sheet has gone', (tester) async {
      await pumpApp(tester);
      await openSheet(tester, guarded: true);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      expect(arrived, findsNothing);
      await tester.pump(barTurn);
      expect(arrived, findsNothing);

      AppNavigator.navigatorKey.currentState!.pop();
      await settleBar(tester);
      expect(find.text('sheet'), findsNothing);
      expect(arrived.hitTestable(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('under a dialog it waits, and is said when the dialog has '
        'gone', (tester) async {
      await pumpApp(tester);
      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await settleBar(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      expect(arrived, findsNothing);

      AppNavigator.navigatorKey.currentState!.pop();
      await settleBar(tester);
      expect(find.text('dialog'), findsNothing);
      expect(arrived.hitTestable(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // The answer to the person's own tap (D30, A13): at once, over whatever
  // is in front, never held behind a resume or another bar.
  group('a category I hid while my alerts were armed on it', () {
    const hid = ShareHiddenWithAlerts(categoryId: 'c-shifts', name: 'Shifts');
    final said = find.text(en.shareHiddenAlertsOff('Shifts'));

    testWidgets('is said at once over a sheet, a form sheet and a dialog', (
      tester,
    ) async {
      await pumpApp(tester);
      for (final open in <Future<void> Function()>[
        () => showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const SizedBox(height: 300, child: Text('sheet')),
        ),
        () => showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const PopScope(
            canPop: false,
            child: SizedBox(height: 300, child: Text('sheet')),
          ),
        ),
        () => showDialog<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      ]) {
        unawaited(open());
        await settleBar(tester);
        await say(tester, hid);

        expect(said.hitTestable(), findsOneWidget);
        await waitOutBar(tester);
        AppNavigator.navigatorKey.currentState!.pop();
        await settleBar(tester);
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('is said once, and a built-in by my own label', (tester) async {
      await pumpApp(tester);
      await say(tester, hid);
      expect(said, findsOneWidget);
      await waitOutBar(tester);
      await settleBar(tester);
      expect(said, findsNothing);

      await say(
        tester,
        const ShareHiddenWithAlerts(categoryId: 'gym', name: 'stored'),
      );
      final label = CalendarCategories.builtInLabel(
        CalendarEventCategory.gym,
        en,
      );
      expect(find.text(en.shareHiddenAlertsOff(label)), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('is not queued behind an arrival\'s bar', (tester) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-choir']));
      expect(view(), findsOneWidget);

      await say(tester, hid);

      expect(said, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('waits while an alert is in front, and is said once it has '
        'gone', (tester) async {
      await pumpApp(tester);
      alerting = true;
      await say(tester, hid);
      expect(said, findsNothing);

      alerting = false;
      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await settleBar(tester);

      expect(said, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    /// Holds [hid] behind an alert in front, runs [meanwhile], then lets
    /// what is in front change.
    Future<void> heldThen(
      WidgetTester tester,
      void Function() meanwhile,
    ) async {
      await pumpApp(tester);
      alerting = true;
      await say(tester, hid);
      meanwhile();
      alerting = false;
      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await settleBar(tester);
    }

    testWidgets('held, it is dropped when the database switched under it', (
      tester,
    ) async {
      await heldThen(tester, DatabaseLifecycle.notifyDatabaseSwitching);

      expect(said, findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('held, it is dropped when the category shows again before '
        'it could be said', (tester) async {
      await heldThen(
        tester,
        () => CalendarCategories.updatePartnerHidden({'gym'}),
      );

      expect(said, findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // What is no longer here when an arrival is said is dropped first: never
  // "Ana shares Other with you" for a category un-shared again.
  group('an arrival undone before it could be said', () {
    /// Holds [notice] under a dialog, runs [meanwhile], closes the dialog.
    Future<void> heldThen(
      WidgetTester tester,
      ShareNotice notice,
      void Function() meanwhile,
    ) async {
      await pumpApp(tester);
      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await settleBar(tester);
      await say(tester, notice);
      meanwhile();
      AppNavigator.navigatorKey.currentState!.pop();
      await settleBar(tester);
    }

    testWidgets('a category the catalogue no longer holds is not said', (
      tester,
    ) async {
      await heldThen(
        tester,
        const ShareArrived(categoryIds: ['c-shifts']),
        () => catalogue = const [gym, choir],
      );

      expect(bar(), findsNothing);
      expect(find.textContaining('Other'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an event the calendar no longer holds is not said', (
      tester,
    ) async {
      await heldThen(
        tester,
        const ShareArrived(events: [run]),
        () => goneEvents = {run.id},
      );

      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('what is still here is said without what left', (tester) async {
      await heldThen(
        tester,
        const ShareArrived(events: [run, lunch]),
        () => goneEvents = {lunch.id},
      );

      expect(find.text(en.shareNewFromPartner('Ana', 'Run')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    /// A built-in is my own row in the catalogue whether or not they share
    /// it, so the catalogue alone cannot say it left: the service is asked.
    testWidgets('a built-in of mine they no longer share is not said; one '
        'they still share is', (tester) async {
      await heldThen(
        tester,
        const ShareArrived(categoryIds: ['gym']),
        () => share.sharedBuiltIns = {},
      );

      expect(bar(), findsNothing);

      share.sharedBuiltIns = {'gym'};
      await say(tester, const ShareArrived(categoryIds: ['gym']));

      expect(bar(), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the bar on the app\'s grounds', () {
    setUpAll(loadGoldenFonts);

    for (final dark in [false, true]) {
      testWidgets('meets the text-contrast guideline in the '
          '${dark ? 'dark' : 'light'} theme', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, dark: dark);
        await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
        expect(bar(), findsOneWidget);

        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.pumpWidget(const SizedBox.shrink());
        handle.dispose();
      });
    }

    testWidgets('German at 2.0 on a small phone, a long name and a long '
        'title: nothing overflows', (tester) async {
      share = FakeShareService(
        availability: pairedWith('Maximilian-Alexander'),
      );
      await pumpApp(
        tester,
        locale: const Locale('de'),
        textScale: 2.0,
        size: const Size(360, 780),
      );
      const title = 'Jahreshauptversammlung des Sportvereins Musterstadt';
      await say(
        tester,
        const ShareArrived(events: [(id: 'e-meeting', title: title)]),
      );
      expect(
        find.text(de.shareNewFromPartner('Maximilian-Alexander', title)),
        findsOneWidget,
      );
      expect(find.text(de.shareView), findsOneWidget);
      expect(tester.takeException(), isNull);

      await waitOutBar(tester);
      await say(
        tester,
        const ShareLeftWithAlert([(id: 'e-meeting', title: title)]),
      );
      expect(
        find.text(de.shareGoneWithAlert('Maximilian-Alexander', title)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // View opens the real Sync & sharing page, which builds its blocs through
  // `getIt` over the pairing fakes, as `sync_settings_page_test.dart` does.
  group('View', () {
    late AppDatabase db;
    late FakePairingGateway gateway;

    setUp(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      PairingService.reset();
      db = await openTestDatabase();
      share = FakeShareService(availability: pairedWith(userB.displayName));
      GetIt.I.registerFactory<ShareBloc>(
        () => ShareBloc(
          service: () async => share,
          calendarChanges: const Stream.empty(),
        ),
      );
      final auth = FakeAuthService(user: userA);
      gateway = FakePairingGateway()
        ..seedPair(
          [userA.uid, userB.uid],
          {userB.uid: PairProfile.fromUser(userB)},
        );
      await PairingService.forTesting(
        auth: auth,
        gateway: gateway,
        settings: SettingsService.forTesting(db),
      );
      GetIt.I.registerFactory<SyncBloc>(() => SyncBloc(authService: auth));
      GetIt.I.registerFactory<PairingBloc>(
        () => PairingBloc(authService: auth, gateway: gateway),
      );
    });

    tearDown(() async {
      await GetIt.I.reset();
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      PairingService.reset();
      await gateway.dispose();
      await db.close();
    });

    /// Drift answers on futures `FakeAsync` alone never completes.
    Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('opens Sync & sharing asking for the Sharing page, which '
        'opens once: back lands on Sync & sharing', (tester) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));

      await tester.tap(view());
      await settle(tester);

      final page = tester.widget<SyncSettingsPage>(
        find.byType(SyncSettingsPage, skipOffstage: false),
      );
      expect(page.openSharing, isTrue);
      expect(find.byType(SharingPage), findsOneWidget);
      expect(bar(), findsNothing);

      Navigator.of(tester.element(find.byType(SharingPage))).pop();
      await settle(tester);
      expect(find.byType(SharingPage), findsNothing);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    /// How many [type] pages the navigator holds, those under the top one
    /// counted.
    int pagesOf(Type type) =>
        find.byType(type, skipOffstage: false).evaluate().length;

    testWidgets('with Sync & sharing in front, it opens its Sharing page '
        'over it', (tester) async {
      await pumpApp(tester);
      unawaited(
        AppNavigator.toSyncSettings(AppNavigator.navigatorKey.currentContext!),
      );
      await settle(tester);
      expect(find.byType(SyncSettingsPage), findsOneWidget);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(pagesOf(SyncSettingsPage), 1);
      expect(find.byType(SharingPage), findsOneWidget);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with the Sharing page in front, it only takes the bar '
        'down', (tester) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);
      expect(find.byType(SharingPage), findsOneWidget);

      // The first bar's turn runs out before the next is said.
      await tester.pump(barTurn);
      await say(tester, const ShareArrived(categoryIds: ['c-choir']));
      await tester.tap(view());
      await settle(tester);

      expect(pagesOf(SyncSettingsPage), 1);
      expect(pagesOf(SharingPage), 1);
      expect(find.byType(SharingPage), findsOneWidget);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with Sync & sharing under another page, it goes back to it '
        'and opens its Sharing page', (tester) async {
      await pumpApp(tester);
      unawaited(
        AppNavigator.toSyncSettings(AppNavigator.navigatorKey.currentContext!),
      );
      await settle(tester);
      unawaited(
        AppNavigator.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('other page')),
          ),
        ),
      );
      await settle(tester);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(pagesOf(SyncSettingsPage), 1);
      expect(find.byType(SharingPage), findsOneWidget);
      expect(find.text('other page', skipOffstage: false), findsNothing);

      Navigator.of(tester.element(find.byType(SharingPage))).pop();
      await settle(tester);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharingPaired),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a sheet that may hold a draft under Sync & sharing in front '
        'stays: the Sharing page opens over them', (tester) async {
      await pumpApp(tester);
      unawaited(
        showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const PopScope(canPop: false, child: Text('draft')),
        ),
      );
      await settle(tester);
      unawaited(
        AppNavigator.toSyncSettings(AppNavigator.navigatorKey.currentContext!),
      );
      await settle(tester);
      expect(find.byType(SyncSettingsPage), findsOneWidget);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(find.byType(SharingPage), findsOneWidget);
      expect(pagesOf(SyncSettingsPage), 1);
      expect(find.text('draft', skipOffstage: false), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with no Sync & sharing page to go back to, a draft under '
        'the page in front stays and Sync & sharing opens over it', (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(
        showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const PopScope(canPop: false, child: Text('draft')),
        ),
      );
      await settle(tester);
      unawaited(
        AppNavigator.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('other page')),
          ),
        ),
      );
      await settle(tester);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(find.byType(SharingPage), findsOneWidget);
      expect(pagesOf(SyncSettingsPage), 1);
      expect(find.text('draft', skipOffstage: false), findsOneWidget);
      expect(find.text('other page', skipOffstage: false), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a sheet that may hold a draft, above the Sync & sharing page '
        'View would go back to, is never closed on its way: it only takes '
        'the bar down', (tester) async {
      await pumpApp(tester);
      unawaited(
        AppNavigator.toSyncSettings(AppNavigator.navigatorKey.currentContext!),
      );
      await settle(tester);
      unawaited(
        showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const PopScope(canPop: false, child: Text('draft')),
        ),
      );
      await settle(tester);
      unawaited(
        AppNavigator.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('other page')),
          ),
        ),
      );
      await settle(tester);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(find.text('draft', skipOffstage: false), findsOneWidget);
      expect(find.text('other page'), findsOneWidget);
      expect(find.byType(SharingPage, skipOffstage: false), findsNothing);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('over a sheet, it closes the sheet on its way', (tester) async {
      await pumpApp(tester);
      unawaited(
        showModalBottomSheet<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          isScrollControlled: true,
          builder: (_) => const SizedBox(height: 600, child: Text('sheet')),
        ),
      );
      await settle(tester);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(find.text('sheet', skipOffstage: false), findsNothing);
      expect(pagesOf(SyncSettingsPage), 1);
      expect(find.byType(SharingPage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('what a check kept while the app was closed (freshness, decision '
      'f)', () {
    testWidgets('is said at the next open, the leave before the arrival, '
        'with the name it was kept with — once', (tester) async {
      // The name the run kept is the leave's; the service's is the
      // arrival's.
      kept = const [
        ShareLeftWithAlert([dinner], partnerName: 'Mara'),
        ShareArrived(events: [run]),
      ];

      await pumpApp(tester);
      await settleBar(tester);

      expect(keptAsked, 1);
      expect(
        find.text('Mara no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );

      await waitOutBar(tester);
      await settleBar(tester);
      expect(find.text(en.shareNewFromPartner('Ana', 'Run')), findsOneWidget);
      expect(keptAsked, 1, reason: 'read once, at the start');
      // Each forgotten as its own bar was said, by its id and kind — and
      // nothing before it was.
      expect(forgotten.map((said) => [said.left, said.events]), [
        [
          {dinner.id},
          <String>{},
        ],
        [
          <String>{},
          {run.id},
        ],
      ]);
      expect(kept, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    /// A return to the app, as the lifecycle tells it.
    void leaveAndReturn(WidgetTester tester) {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    testWidgets('is cleared only once it was said: while its bar waits '
        'under a dialog the store holds it still, so an app closed there '
        'loses nothing; read again on each return it is held once, said '
        'once, and only then forgotten (review item 13)', (tester) async {
      await pumpApp(tester);
      unawaited(
        showDialog<void>(
          context: AppNavigator.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await settleBar(tester);
      kept = const [
        ShareLeftWithAlert([dinner], partnerName: 'Mara'),
      ];

      // A return under the dialog reads it, and it waits.
      leaveAndReturn(tester);
      await settleBar(tester);
      expect(bar(), findsNothing);
      expect(forgotten, isEmpty);
      expect(kept, hasLength(1), reason: 'unsaid, it is still kept');

      // Two more: read again each time, held by id.
      leaveAndReturn(tester);
      await settleBar(tester);
      leaveAndReturn(tester);
      await settleBar(tester);
      expect(keptAsked, 4);
      expect(bar(), findsNothing);
      expect(forgotten, isEmpty);

      AppNavigator.navigatorKey.currentState!.pop();
      await settleBar(tester);

      // One event, said as one: the three reads did not make it three.
      expect(
        find.text('Mara no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );
      expect(forgotten.single.left, {dinner.id});
      expect(kept, isEmpty);

      // Its turn over, nothing is worded a second time.
      await waitOutBar(tester);
      await settleBar(tester);
      expect(opens, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('said, with the forgetting still on its way: a return reads '
        'it again and it is not said twice', (tester) async {
      kept = const [
        ShareArrived(events: [run]),
      ];
      forgetting = Completer<void>();
      await pumpApp(tester);
      await settleBar(tester);
      expect(find.text(en.shareNewFromPartner('Ana', 'Run')), findsOneWidget);
      expect(kept, hasLength(1), reason: 'the store has not forgotten yet');
      expect(opens, 1);

      await waitOutBar(tester);
      leaveAndReturn(tester);
      await settleBar(tester);
      await waitOutBar(tester);
      await settleBar(tester);

      // Read again, and worded no second time.
      expect(keptAsked, 2);
      expect(opens, 1);
      expect(forgotten, hasLength(1));

      forgetting!.complete();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dropped as undone at the moment it would be said, it will '
        'never be said: the store forgets it too, and what is still here '
        'is said and forgotten with its bar', (tester) async {
      goneEvents = {run.id};
      kept = const [
        ShareArrived(categoryIds: ['c-gone'], events: [run, lunch]),
      ];

      await pumpApp(tester);
      await settleBar(tester);

      expect(find.text(en.shareNewFromPartner('Ana', 'Lunch')), findsOneWidget);
      expect(forgotten.map((said) => [said.categories, said.events]), [
        [
          {'c-gone'},
          <String>{},
        ],
        [
          <String>{},
          {run.id},
        ],
        [
          <String>{},
          {lunch.id},
        ],
      ]);
      expect(kept, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('only what was said is forgotten: what a run kept meanwhile '
        'stays in the store for its own turn', (tester) async {
      kept = const [
        ShareLeftWithAlert([dinner], partnerName: 'Mara'),
      ];
      await pumpApp(tester);
      await settleBar(tester);
      expect(forgotten.single.left, {dinner.id});

      // A run, in between: the same event arrived again, and another left.
      kept = [
        ...kept,
        const ShareLeftWithAlert([lunch], partnerName: 'Mara'),
        const ShareArrived(events: [dinner]),
      ];
      await waitOutBar(tester);
      leaveAndReturn(tester);
      await settleBar(tester);

      expect(
        find.text('Mara no longer shares Lunch. Your alert is off.'),
        findsOneWidget,
      );
      await waitOutBar(tester);
      await settleBar(tester);
      expect(
        find.text(en.shareNewFromPartner('Ana', 'Dinner')),
        findsOneWidget,
      );
      expect(kept, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a notice that only ever arrived live tells the store '
        'nothing: saying it costs no statement', (tester) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived(events: [run]));
      expect(find.text(en.shareNewFromPartner('Ana', 'Run')), findsOneWidget);
      await waitOutBar(tester);
      await say(tester, const ShareLeftWithAlert([dinner]));

      expect(bar(), findsOneWidget);
      expect(forgotten, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('is asked for again on each return, and what a run kept '
        'meanwhile is said then', (tester) async {
      await pumpApp(tester);
      await settleBar(tester);
      expect(bar(), findsNothing);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      kept = const [
        ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      ];

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleBar(tester);

      expect(keptAsked, 2);
      expect(
        find.text('Ana no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('nothing kept: nothing is said and no service is opened', (
      tester,
    ) async {
      await pumpApp(tester);
      await settleBar(tester);

      expect(keptAsked, 1);
      expect(opens, 0);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('reads that answer late (the notices review, N1–N5)', () {
    void leave(WidgetTester tester) {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    void comeBack(WidgetTester tester) {
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    final dinnerAlone = en.shareNewFromPartner('Ana', 'Dinner');
    final runAlone = en.shareNewFromPartner('Ana', 'Run');
    final twoEvents = en.shareNewFromPartner('Ana', en.shareSummaryEvents(2));

    testWidgets('only what was checked is said (N1): an arrival that lands '
        'while the first is asked about — and is gone again already — is '
        'not in that bar, and is dropped at its own turn', (tester) async {
      final first = Completer<Set<String>>();
      var asks = 0;
      heldOverride = (ids) {
        asks++;
        return asks == 1
            ? first.future
            : Future.value(ids.toSet().difference(goneEvents));
      };
      await pumpApp(tester);
      ShareService.notify(const ShareArrived(events: [dinner]));
      await tester.pump();
      await tester.pump();
      goneEvents = {run.id};
      ShareService.notify(const ShareArrived(events: [run]));
      await tester.pump();
      first.complete({dinner.id});
      await settleBar(tester);

      expect(find.text(dinnerAlone), findsOneWidget);
      expect(find.text(twoEvents), findsNothing);

      await waitOutBar(tester);
      await settleBar(tester);
      expect(asks, 2, reason: 'the second was asked about at its own turn');
      expect(find.text(runAlone), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('at a return (N1): a kept arrival that merges in while a '
        'live one is asked about is not said with it — and is forgotten as '
        'dropped at its own turn, never as said', (tester) async {
      await pumpApp(tester);
      await settleBar(tester);
      leave(tester);
      ShareService.notify(const ShareArrived(events: [dinner]));
      await tester.pump();
      goneEvents = {run.id};
      kept = const [
        ShareArrived(events: [run]),
      ];
      comeBack(tester);
      await settleBar(tester);

      expect(find.text(dinnerAlone), findsOneWidget);
      expect(find.text(twoEvents), findsNothing);

      await waitOutBar(tester);
      await settleBar(tester);
      expect(find.text(runAlone), findsNothing);
      expect(forgotten.map((said) => said.events), [
        {run.id},
      ]);
      expect(kept, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a check that never answers costs no leave (N3): the leave '
        'is said without it, and the arrival is said as held once the '
        'check\'s own bound has passed', (tester) async {
      heldOverride = (ids) => Completer<Set<String>>().future;
      await pumpApp(tester);
      ShareService.notify(const ShareArrived(events: [dinner]));
      await settleBar(tester);
      expect(bar(), findsNothing);

      ShareService.notify(const ShareLeftWithAlert([run]));
      await tester.pump(AppConstants.shareNoticeCheckLimit);
      await settleBar(tester);
      expect(
        find.text('Ana no longer shares Run. Your alert is off.'),
        findsOneWidget,
      );

      await waitOutBar(tester);
      await tester.pump(AppConstants.shareNoticeCheckLimit);
      await settleBar(tester);
      expect(find.text(dinnerAlone), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a service that never comes up releases the turn (N3): the '
        'next notice tries again', (tester) async {
      var hangs = true;
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppNavigator.navigatorKey,
          navigatorObservers: [
            AppNavigator.routeObserver,
            ShareNoticeListener.routes,
          ],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => ShareNoticeListener(
            shareService: () =>
                hangs ? Completer<ShareService>().future : Future.value(share),
            loadCategories: () async => null,
            partnerEventsHeld: (ids) async => ids.toSet(),
            keptNotices: () async => const [],
            forgetKept: (_) async {},
            child: child!,
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump();
      ShareService.notify(const ShareLeftWithAlert([dinner]));
      await tester.pump(AppConstants.shareNoticeCheckLimit);
      await settleBar(tester);
      expect(bar(), findsNothing);

      hangs = false;
      ShareService.notify(const ShareLeftWithAlert([run]));
      await settleBar(tester);
      expect(find.text(en.shareGoneWithAlerts(2, 'Ana')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dealt with lasts as long as the store\'s forget (N4): a '
        'kept arrival said and forgotten, then kept again by a later run, '
        'is said again', (tester) async {
      kept = const [
        ShareArrived(events: [run]),
      ];
      await pumpApp(tester);
      await settleBar(tester);
      expect(find.text(runAlone), findsOneWidget);
      await waitOutBar(tester);
      await settleBar(tester);
      expect(kept, isEmpty);
      expect(opens, 1);

      // It left, was shared again, and a later run kept its arrival anew.
      leave(tester);
      kept = const [
        ShareArrived(events: [run]),
      ];
      comeBack(tester);
      await settleBar(tester);

      expect(find.text(runAlone), findsOneWidget);
      expect(opens, 2, reason: 'a second bar was worded');
      expect(forgotten, hasLength(2));
      expect(kept, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a notice said live is dealt with too (N4): the kept copy '
        'of it that a read in flight brings afterwards is not said a second '
        'time, and is forgotten in the store', (tester) async {
      final read = Completer<List<ShareNotice>>();
      var reads = 0;
      keptOverride = () => ++reads == 1 ? read.future : Future.value(kept);
      await pumpApp(tester);
      await say(tester, const ShareArrived(events: [run]));
      expect(find.text(runAlone), findsOneWidget);
      await waitOutBar(tester);
      await settleBar(tester);
      expect(opens, 1);
      expect(forgotten, isEmpty, reason: 'said live: the store told nothing');

      read.complete(const [
        ShareArrived(events: [run]),
      ]);
      await settleBar(tester);

      expect(opens, 1, reason: 'no second bar was worded');
      expect(forgotten.map((said) => said.events), [
        {run.id},
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('and only while a copy can exist (N4): said live with none '
        'kept, an arrival a later run keeps under the same id is news', (
      tester,
    ) async {
      await pumpApp(tester);
      await say(tester, const ShareArrived(events: [run]));
      await waitOutBar(tester);
      await settleBar(tester);
      // A return whose read holds no copy: there was none.
      leave(tester);
      comeBack(tester);
      await settleBar(tester);
      expect(opens, 1);

      leave(tester);
      kept = const [
        ShareArrived(events: [run]),
      ];
      comeBack(tester);
      await settleBar(tester);

      expect(opens, 2, reason: 'a second bar was worded');
      expect(find.text(runAlone), findsOneWidget);
      expect(forgotten.map((said) => said.events), [
        {run.id},
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('kept notices read under one database are not said under '
        'the next (N5): a switch while the read is on its way drops the '
        'answer, and forgets nothing in the other database\'s store — it '
        'is said when its own database reads it', (tester) async {
      final read = Completer<List<ShareNotice>>();
      var reads = 0;
      keptOverride = () => ++reads == 1 ? read.future : Future.value(kept);
      await pumpApp(tester);
      DatabaseLifecycle.notifyDatabaseSwitching();
      read.complete(const [
        ShareLeftWithAlert([dinner], partnerName: 'Mara'),
      ]);
      await settleBar(tester);

      const said = 'Mara no longer shares Dinner. Your alert is off.';
      expect(find.text(said), findsNothing);
      expect(forgotten, isEmpty);

      // Back under the database that kept it.
      leave(tester);
      kept = const [
        ShareLeftWithAlert([dinner], partnerName: 'Mara'),
      ];
      comeBack(tester);
      await settleBar(tester);
      expect(find.text(said), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the calendar\'s answer for one database is not applied to '
        'the next (N5): a switch while it is asked drops nothing and tells '
        'the other database\'s store nothing', (tester) async {
      final asked = Completer<Set<String>>();
      heldOverride = (ids) => asked.future;
      kept = const [
        ShareArrived(events: [dinner]),
      ];
      await pumpApp(tester);
      await tester.pump();
      await tester.pump();
      kept = const [];

      DatabaseLifecycle.notifyDatabaseSwitching();
      // The old database's answer: gone.
      asked.complete(const {});
      await settleBar(tester);

      expect(forgotten, isEmpty);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a hide tells of the database it was made in (N5): one '
        'stamped under another opening is not said, one stamped under this '
        'one is', (tester) async {
      await pumpApp(tester);
      await say(
        tester,
        ShareHiddenWithAlerts(
          categoryId: 'c-shifts',
          name: 'Shifts',
          generation: ShareService.databaseGeneration - 1,
        ),
      );
      final hidden = find.text(en.shareHiddenAlertsOff('Shifts'));
      expect(hidden, findsNothing);

      await say(
        tester,
        ShareHiddenWithAlerts(
          categoryId: 'c-shifts',
          name: 'Shifts',
          generation: ShareService.databaseGeneration,
        ),
      );
      expect(hidden, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('one bar per name (N8): leaves told with different names — '
        'an unsaid one of Mara\'s, then one of Ion\'s — are never one bar '
        'under the later name; each name\'s leaves get a turn of their own, '
        'the earlier first', (tester) async {
      await pumpApp(tester);
      await settleBar(tester);
      leave(tester);
      ShareService.notify(
        const ShareLeftWithAlert([dinner], partnerName: 'Mara'),
      );
      ShareService.notify(const ShareLeftWithAlert([run], partnerName: 'Ion'));
      ShareService.notify(
        const ShareLeftWithAlert([lunch], partnerName: 'Ion'),
      );
      await tester.pump();
      comeBack(tester);
      await settleBar(tester);

      expect(
        find.text('Mara no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );
      expect(find.text(en.shareGoneWithAlerts(3, 'Ion')), findsNothing);

      await waitOutBar(tester);
      await settleBar(tester);
      expect(find.text(en.shareGoneWithAlerts(2, 'Ion')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a run that wrote behind the live app (N2): the prompt '
        'after the catch-up has the store read again, with no return in '
        'between', (tester) async {
      await pumpApp(tester);
      await settleBar(tester);
      expect(keptAsked, 1);
      kept = const [
        ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      ];

      KeptShareNotices.prompt();
      await settleBar(tester);

      expect(keptAsked, 2);
      expect(
        find.text('Ana no longer shares Dinner. Your alert is off.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
