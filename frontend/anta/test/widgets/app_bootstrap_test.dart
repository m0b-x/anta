import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/main.dart';
import 'package:anta/widgets/app_bootstrap.dart';

import '../goldens/support/golden_fonts.dart';
import 'support/layout_errors.dart';

/// Guards what launch draws while the database opens (D13,
/// `docs/scalability-roadmap.md` §5.7 S16): the "Updating your data…" state
/// only while a migration runs, nothing new on a normal launch, and a
/// message with a way out rather than a blank frame when the open fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppDatabase.onUpgradeStarting = null);

  group('openDatabaseForLaunch', () {
    test('shows the updating state once the open starts a migration', () async {
      final shown = <Widget>[];

      await openDatabaseForLaunch(
        open: () async {
          AppDatabase.onUpgradeStarting?.call();
          return Object();
        },
        show: shown.add,
      );

      expect(shown, hasLength(1));
      expect((shown.single as AppBootstrap).error, isNull);
      expect(
        AppDatabase.onUpgradeStarting,
        isNotNull,
        reason: 'launch clears it once the services are up',
      );
    });

    test('a normal open shows nothing', () async {
      final shown = <Widget>[];

      await openDatabaseForLaunch(open: () async => Object(), show: shown.add);

      expect(shown, isEmpty);
    });

    test('the updating state is shown from the launch zone, not from the '
        'zone the open fires the hook in', () async {
      Zone? shownIn;
      final launchZone = Zone.current;

      await openDatabaseForLaunch(
        open: () async {
          // Drift calls the hook from a zone of its own under the opener's;
          // the frame it schedules must not be bound to that zone.
          await runZoned(
            () async => AppDatabase.onUpgradeStarting?.call(),
            zoneValues: {#opener: true},
          );
          return Object();
        },
        show: (_) => shownIn = Zone.current,
      );

      expect(shownIn, isNotNull);
      expect(identical(shownIn, launchZone), isTrue);
      expect(shownIn![#opener], isNull);
    });

    test('a failed open waits on the failed state, and Retry opens '
        'again', () async {
      final shown = <Widget>[];
      final failure = StateError('disk I/O error');
      var opens = 0;

      var done = false;
      final launch = openDatabaseForLaunch(
        open: () async {
          opens++;
          if (opens == 1) throw failure;
          return Object();
        },
        show: shown.add,
      ).then((_) => done = true);
      await pumpEventQueue();

      expect(done, isFalse, reason: 'launch waits on the failed state');
      final failed = shown.single as AppBootstrap;
      expect(failed.error, failure);
      expect(AppDatabase.onUpgradeStarting, isNull);

      failed.onRetry!();
      failed.onRetry!();
      await launch;

      expect(opens, 2, reason: 'a second tap does not open twice');
      expect(done, isTrue);
      expect(shown, hasLength(2));
      final opening = shown.last as AppBootstrap;
      expect(opening.retrying, isTrue, reason: 'Retry shows that it opens');
      expect(opening.error, isNull);
    });

    test('a second failure shows the failed state again, with its own '
        'error', () async {
      final shown = <Widget>[];
      final failures = [StateError('first'), StateError('second')];
      var opens = 0;

      final launch = openDatabaseForLaunch(
        open: () async {
          if (opens < failures.length) throw failures[opens++];
          opens++;
          return Object();
        },
        show: shown.add,
      );
      await pumpEventQueue();
      (shown.last as AppBootstrap).onRetry!();
      await pumpEventQueue();
      final second = shown.last as AppBootstrap;
      second.onRetry!();
      await launch;

      expect(
        [for (final app in shown.cast<AppBootstrap>()) app.error],
        [failures[0], null, failures[1], null],
      );
      expect(second.retrying, isFalse);
      expect(opens, 3);
    });
  });

  // The half-built singleton trap: a memo stored before its awaits complete
  // would hand Retry's open the instance the failed one left behind.
  test('a retry after a real failed open yields a working database', () async {
    final dir = await Directory.systemTemp.createTemp('anta_launch_retry_');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
    AppDatabase.resetSwitchAnnouncementForTesting();
    AppDatabase? opened;
    addTearDown(() async {
      await opened?.close();
      messenger.setMockMethodCallHandler(pathProvider, null);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    // A directory where the database file goes: SQLite cannot open it.
    final blocker = Directory(p.join(dir.path, 'gym_notes', 'launch.db'))
      ..createSync(recursive: true);
    final shown = <Widget>[];

    final launch = openDatabaseForLaunch(
      open: () async =>
          opened = await AppDatabase.getInstance(databaseName: 'launch'),
      show: shown.add,
    );
    while (shown.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final failed = shown.single as AppBootstrap;
    expect(failed.error, isNotNull);
    expect(opened, isNull);

    blocker.deleteSync();
    failed.onRetry!();
    await launch;

    expect(opened, isNotNull);
    expect(
      await opened!.customSelect('SELECT 1 AS one').getSingle(),
      isNotNull,
    );
    expect(
      await opened!.syncDao.getValue(SyncDao.keyLastHlc),
      isNotNull,
      reason: 'handed over only once its clock is seeded',
    );
    expect(
      identical(await AppDatabase.getInstance(databaseName: 'launch'), opened),
      isTrue,
      reason: 'the next caller joins the retry, not the failed open',
    );
  });

  test('the hook fires when an open migrates, never when the schema is '
      'current', () async {
    final dir = await Directory.systemTemp.createTemp('anta_bootstrap_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    var fired = 0;
    AppDatabase.onUpgradeStarting = () => fired++;
    Future<void> openAndClose() async {
      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();
    }

    await openAndClose();
    expect(fired, 0, reason: 'a fresh install creates, it does not migrate');
    await openAndClose();
    expect(fired, 0, reason: 'a normal launch');

    final old = AppDatabase.forTesting(NativeDatabase(file));
    await old.customStatement('PRAGMA user_version = 46');
    await old.close();
    await openAndClose();
    expect(fired, 1);
  });

  test('the hook runs in the zone it was installed from, not in the zone '
      'the open runs the migration in', () async {
    final dir = await Directory.systemTemp.createTemp('anta_bootstrap_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.sqlite');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh.customStatement('PRAGMA user_version = 46');
    await fresh.close();

    Zone? hookZone;
    final installZone = runZoned(() {
      AppDatabase.onUpgradeStarting = () => hookZone = Zone.current;
      return Zone.current;
    }, zoneValues: {#install: true});

    // Opened from this zone, as launch opens from its own: Drift runs the
    // migration, and with it the hook, in a zone forked under this one.
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    await db.close();

    expect(hookZone, isNotNull);
    expect(identical(hookZone, installZone), isTrue);
    expect(hookZone![#install], isTrue);
  });

  group('AppBootstrap', () {
    final en = lookupAppLocalizations(const Locale('en'));

    // Real glyphs, so the geometry below is what a phone lays out.
    setUpAll(loadGoldenFonts);

    Future<void> pump(
      WidgetTester tester,
      Widget app, {
      Locale locale = const Locale('en'),
      double textScale = 1.0,
      Size size = const Size(412, 915),
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = [locale];
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(app);
      await tester.pump();
    }

    AppBootstrap failed({VoidCallback? onRetry, int attempt = 1}) =>
        AppBootstrap.failed(
          StateError('disk I/O error'),
          onRetry: onRetry ?? () {},
          attempt: attempt,
        );

    testWidgets('the updating state speaks once, through the spinner', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, const AppBootstrap.updating());

      expect(find.text(en.launchUpdatingData), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        en.launchUpdatingData,
      );
      expect(find.bySemanticsLabel(en.launchUpdatingData), findsOneWidget);
      expect(find.text(en.launchOpenFailed), findsNothing);
      semantics.dispose();
    });

    testWidgets('the opening state says it opens, not that it updates, and '
        'offers no Retry', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, const AppBootstrap.opening());

      expect(en.launchOpeningData, isNot(en.launchUpdatingData));
      expect(find.text(en.launchOpeningData), findsOneWidget);
      expect(find.bySemanticsLabel(en.launchOpeningData), findsOneWidget);
      expect(find.text(en.launchUpdatingData), findsNothing);
      expect(find.text(en.retry), findsNothing);
      expect(find.text(en.launchOpenFailed), findsNothing);
      semantics.dispose();
    });

    testWidgets('the failed state names the failure, the next step, Retry '
        'and the whole detail last, selectable', (tester) async {
      await pump(tester, failed());

      expect(find.text(en.launchOpenFailed), findsOneWidget);
      expect(find.text(en.launchOpenFailedNext), findsOneWidget);
      final detail = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(detail.data, contains('disk I/O error'));
      expect(detail.maxLines, isNull, reason: 'never cut, never a scroller');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getTopLeft(find.byType(FilledButton)).dy,
        lessThan(tester.getTopLeft(find.byType(SelectableText)).dy),
        reason: 'the action above the diagnostic',
      );
      expect(
        tester.getTopLeft(find.text(en.launchOpenFailedNext)).dy,
        lessThan(tester.getTopLeft(find.byType(FilledButton)).dy),
      );
    });

    testWidgets('the next step reads in onSurface, the detail smaller in '
        'onSurfaceVariant', (tester) async {
      await pump(tester, failed());
      final theme = Theme.of(tester.element(find.byType(Scaffold)));

      final next = tester.widget<Text>(find.text(en.launchOpenFailedNext));
      expect(next.style!.color, theme.colorScheme.onSurface);
      expect(next.style!.fontSize, theme.textTheme.bodyMedium!.fontSize);
      final detail = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(detail.style!.color, theme.colorScheme.onSurfaceVariant);
      expect(detail.style!.fontSize, theme.textTheme.bodySmall!.fontSize);
    });

    testWidgets('the failed title is a live level-1 heading', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, failed());

      final node = tester.getSemantics(find.text(en.launchOpenFailed));
      expect(node.flagsCollection.isHeader, isTrue);
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(node.headingLevel, 1);
      semantics.dispose();
    });

    // A live region whose text did not change announces nothing, so a retry
    // that fails the same way must rebuild the title's node, not reuse it.
    testWidgets('a repeat failure is a new title node', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, failed(attempt: 1));
      final first = tester.getSemantics(find.text(en.launchOpenFailed)).id;

      await pump(tester, failed(attempt: 2));

      final second = tester.getSemantics(find.text(en.launchOpenFailed)).id;
      expect(second, isNot(first));
      semantics.dispose();
    });

    testWidgets('Retry calls back', (tester) async {
      var retried = 0;
      await pump(tester, failed(onRetry: () => retried++));

      await tester.tap(find.text(en.retry));
      await tester.pump();

      expect(retried, 1);
    });

    for (final textScale in const [1.0, 2.0]) {
      for (final size in const [Size(412, 915), Size(360, 780)]) {
        testWidgets('at $textScale on ${size.width.toInt()} x '
            '${size.height.toInt()} no swap moves the slot or the title', (
          tester,
        ) async {
          Future<(Rect, Rect)> slotAndTitle(Widget app, String title) async {
            await pump(tester, app, textScale: textScale, size: size);
            final glyph = find.byWidgetPredicate(
              (w) => w is CircularProgressIndicator || w is Icon,
            );
            final slot = find
                .ancestor(of: glyph, matching: find.byType(SizedBox))
                .first;
            return (tester.getRect(slot), tester.getRect(find.text(title)));
          }

          final updating = await slotAndTitle(
            const AppBootstrap.updating(),
            en.launchUpdatingData,
          );
          final failedState = await slotAndTitle(failed(), en.launchOpenFailed);
          final opening = await slotAndTitle(
            const AppBootstrap.opening(),
            en.launchOpeningData,
          );

          expect(failedState.$1, updating.$1);
          expect(opening.$1, updating.$1);
          expect(failedState.$1.size, const Size.square(48));
          expect(failedState.$2.top, updating.$2.top);
          expect(opening.$2.top, updating.$2.top);
        });
      }
    }

    for (final brightness in Brightness.values) {
      testWidgets('the system bars follow the ${brightness.name} theme', (
        tester,
      ) async {
        await pump(tester, failed(), brightness: brightness);

        final style = tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
            )
            .value;
        expect(style, AppSystemBars.over(brightness));
        final context = tester.element(find.byType(Scaffold));
        expect(Theme.of(context).brightness, brightness);
      });

      testWidgets('every state meets the accessibility guidelines in '
          '${brightness.name}', (tester) async {
        final semantics = tester.ensureSemantics();
        for (final app in [
          const AppBootstrap.updating(),
          const AppBootstrap.opening(),
          failed(),
        ]) {
          await pump(tester, app, brightness: brightness);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        }
        semantics.dispose();
      });
    }

    testWidgets('it follows the device language', (tester) async {
      await pump(
        tester,
        const AppBootstrap.updating(),
        locale: const Locale('ro'),
      );

      expect(
        find.text(
          lookupAppLocalizations(const Locale('ro')).launchUpdatingData,
        ),
        findsOneWidget,
      );
    });

    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      for (final brightness in Brightness.values) {
        testWidgets('${locale.languageCode} at 2.0 on 360 x 780 in '
            '${brightness.name} fits, speaks, meets the guidelines and keeps '
            'Retry in view', (tester) async {
          final l10n = lookupAppLocalizations(locale);
          final semantics = tester.ensureSemantics();
          Future<void> pumpAt(Widget app) => pump(
            tester,
            app,
            locale: locale,
            textScale: 2.0,
            size: const Size(360, 780),
            brightness: brightness,
          );
          Future<void> meetsGuidelines() async {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
          }

          final errors = await layoutErrorsDuring(() async {
            await pumpAt(const AppBootstrap.updating());
            expect(find.bySemanticsLabel(l10n.launchUpdatingData), findsOne);
            await meetsGuidelines();
            await pumpAt(const AppBootstrap.opening());
            expect(find.bySemanticsLabel(l10n.launchOpeningData), findsOne);
            await meetsGuidelines();
            // The longest detail the screen is ever handed.
            await pumpAt(
              AppBootstrap.failed(
                StateError('x ' * AppConstants.errorDetailLimit),
                onRetry: () {},
              ),
            );
            final title = tester.getSemantics(find.text(l10n.launchOpenFailed));
            expect(title.flagsCollection.isHeader, isTrue);
            expect(find.bySemanticsLabel(l10n.retry), findsOneWidget);
            expect(
              tester.getRect(find.byType(FilledButton)).bottom,
              lessThanOrEqualTo(780),
              reason: 'Retry needs no scroll at 2.0',
            );
            await meetsGuidelines();
          });

          expect(errors, isEmpty);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }
  });
}
