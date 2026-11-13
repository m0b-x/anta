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
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
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

  setUp(() {
    share = FakeShareService(availability: pairedWith('Ana'));
    opens = 0;
    shellChild = null;
    CalendarCategories.updateCache(const [gym, shifts, choir]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

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
        navigatorObservers: [AppNavigator.routeObserver],
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
        const ShareArrived(categoryIds: ['c-shifts'], eventTitles: ['Dinner']),
        en.shareNewFromPartner('Ana', 'Shifts'),
        true,
      ),
      (
        'one event',
        const ShareArrived(eventTitles: ['Dinner']),
        en.shareNewFromPartner('Ana', 'Dinner'),
        true,
      ),
      (
        'several events',
        const ShareArrived(eventTitles: ['Dinner', 'Run', 'Lunch']),
        en.shareNewFromPartner('Ana', en.shareSummaryEvents(3)),
        true,
      ),
      (
        'one event left with my alert',
        const ShareLeftWithAlert(['Dinner']),
        'Ana no longer shares Dinner. Your alert is off.',
        false,
      ),
      (
        'several events left with my alerts',
        const ShareLeftWithAlert(['Dinner', 'Run']),
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

    testWidgets('a partner with no name is the stand-in, starting the '
        'sentence', (tester) async {
      share = FakeShareService(availability: pairedWith(null));
      await pumpApp(tester);
      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      expect(find.text('Your partner shares Shifts with you'), findsOneWidget);
      // Said in full, the bar for the leave reads the same way.
      await waitOutBar(tester);
      await say(tester, const ShareLeftWithAlert(['Dinner']));
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
        await say(tester, const ShareLeftWithAlert(['Abendessen']));
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
          ShareLeftWithAlert([for (var i = 0; i < count; i++) 'E$i']),
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
      await say(tester, const ShareArrived(eventTitles: ['Abendessen']));

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

      await say(tester, const ShareArrived(eventTitles: ['Dinner']));
      await say(tester, const ShareArrived(eventTitles: ['Dinner', 'Run']));
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
      await say(tester, const ShareArrived(eventTitles: ['Run']));
      await say(tester, const ShareLeftWithAlert(['Dinner']));
      await say(tester, const ShareLeftWithAlert(['Dinner']));

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

      await say(tester, const ShareLeftWithAlert(['Dinner']));
      final left = find.text(en.shareGoneWithAlert('Ana', 'Dinner'));
      expect(arrived, findsOneWidget);
      expect(left, findsNothing);

      // The second `say` spent another settle of the arrival's time.
      await tester.pump(barTurn - settled * 2);
      await settleBar(tester);
      expect(left, findsOneWidget);

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
      await say(tester, const ShareArrived(eventTitles: [title]));
      expect(
        find.text(de.shareNewFromPartner('Maximilian-Alexander', title)),
        findsOneWidget,
      );
      expect(find.text(de.shareView), findsOneWidget);
      expect(tester.takeException(), isNull);

      await waitOutBar(tester);
      await say(tester, const ShareLeftWithAlert([title]));
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

    testWidgets('with Sync & sharing in front, it only takes the bar down', (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(
        AppNavigator.toSyncSettings(AppNavigator.navigatorKey.currentContext!),
      );
      await settle(tester);
      expect(find.byType(SyncSettingsPage), findsOneWidget);

      await say(tester, const ShareArrived(categoryIds: ['c-shifts']));
      await tester.tap(view());
      await settle(tester);

      expect(find.byType(SyncSettingsPage, skipOffstage: false), findsOne);
      expect(find.byType(SharingPage), findsNothing);
      expect(bar(), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
