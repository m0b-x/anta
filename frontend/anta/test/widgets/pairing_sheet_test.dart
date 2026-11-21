import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/pairing_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';

/// The pairing sheet over the real bloc, service and a fake gateway: what
/// the sheet does when the pair is made.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDown(() {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
  });

  testWidgets('closes itself once when the pair is made: "paired" arrives '
      'again when the partner\'s name does, and that second arrival must not '
      'close the page the sheet was opened from', (tester) async {
    final auth = FakeAuthService(user: userA);
    final gateway = FakePairingGateway();
    addTearDown(gateway.dispose);
    late PairingBloc bloc;
    await tester.runAsync(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      PairingService.reset();
      PairingService.forTesting(
        auth: auth,
        gateway: gateway,
        settings: SettingsService.forTesting(await openTestDatabase()),
      );
      bloc = PairingBloc(authService: auth, gateway: gateway)
        ..add(const LoadPairing());
      await pumpEventQueue();
    });
    addTearDown(() => bloc.close());

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Sync & sharing')),
                    body: TextButton(
                      onPressed: () => showPairingSheet(context, bloc),
                      child: const Text('pair'),
                    ),
                  ),
                ),
              ),
              child: const Text('open the page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open the page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pair'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.pairingGenerate),
      findsOneWidget,
    );

    // The partner redeems a code of this account's: the first "paired".
    late PairRecord pair;
    await tester.runAsync(() async {
      bloc.add(const GenerateInviteRequested());
      await pumpEventQueue();
      pair = await gateway.createPair(
        self: PairProfile(uid: userB.uid),
        partner: PairProfile(uid: userA.uid),
        inviteCode: gateway.invites.keys.single,
      );
      await pumpEventQueue();
    });
    final first = bloc.state;
    expect(first, isA<PairingPaired>());
    // The sheet has begun to close and is still on screen, sliding away…
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.bySemanticsIdentifier(SemanticsIds.pairingCodeField),
      findsOneWidget,
    );
    // …when the partner's name arrives: "paired" again.
    await tester.runAsync(() async {
      await gateway.writeProfile(
        pairId: pair.pairId,
        profile: PairProfile(uid: userB.uid, displayName: 'Partner'),
      );
      await pumpEventQueue();
    });
    expect(bloc.state, isNot(first), reason: 'a second paired state');
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.pairingCodeField),
      findsNothing,
      reason: 'the sheet closed',
    );
    expect(
      find.text('Sync & sharing'),
      findsOneWidget,
      reason: 'the page under it did not',
    );
  });

  group('the header and the body\'s parts', () {
    final en = lookupAppLocalizations(const Locale('en'));
    late FakePairingGateway gateway;
    late PairingBloc bloc;

    setUpAll(() async {
      await loadGoldenFonts();
      // The code and its field are drawn in monospace, which the test font
      // would measure twice as wide as a phone does.
      await loadMonospaceStandIn();
    });

    /// The real bloc over a fake gateway, loaded and never paired; the
    /// sheet opened from a page, as Sync & sharing opens it.
    Future<void> open(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      double scale = 1.0,
      Size size = const Size(412, 915),
    }) async {
      final auth = FakeAuthService(user: userA);
      gateway = FakePairingGateway();
      addTearDown(gateway.dispose);
      await tester.runAsync(() async {
        DatabaseLifecycle.notifyDatabaseSwitching();
        SettingsService.reset();
        PairingService.reset();
        PairingService.forTesting(
          auth: auth,
          gateway: gateway,
          settings: SettingsService.forTesting(await openTestDatabase()),
        );
        bloc = PairingBloc(authService: auth, gateway: gateway)
          ..add(const LoadPairing());
        await pumpEventQueue();
      });
      addTearDown(() => bloc.close());
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPairingSheet(context, bloc),
                child: const Text('pair'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pair'));
      await slide(tester);
    }

    Finder byId(String id) => find.bySemanticsIdentifier(id);

    Finder field() => find.descendant(
      of: byId(SemanticsIds.pairingCodeField),
      matching: find.byType(EditableText),
    );

    Future<void> makeCode(WidgetTester tester) async {
      await tester.runAsync(() async {
        bloc.add(const GenerateInviteRequested());
        await pumpEventQueue();
      });
      await tester.pump();
    }

    testWidgets('the app\'s sheet chrome: ✕, the title, and help with its '
        'tooltip and id; the ✕ closes the sheet', (tester) async {
      await open(tester);

      final header = find.byType(FormSheetHeader);
      expect(find.byType(FormSheetHandle), findsOneWidget);
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text(en.pairingTitle)),
        findsOneWidget,
      );
      expect(find.byTooltip(en.close), findsOneWidget);
      expect(find.byTooltip(en.syncGuideHowPairingWorks), findsOneWidget);
      expect(
        find.descendant(
          of: byId(SemanticsIds.pairingHow),
          matching: find.byIcon(Icons.help_outline_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip(en.close));
      await slide(tester);
      expect(byId(SemanticsIds.pairingGenerate), findsNothing);
      expect(find.text('pair'), findsOneWidget);
    });

    testWidgets('in German at 2.0 on a 360 phone the title stacks under the '
        '✕ and help, whole', (tester) async {
      await open(
        tester,
        locale: const Locale('de'),
        scale: 2.0,
        size: const Size(360, 780),
      );
      final de = lookupAppLocalizations(const Locale('de'));
      final title = find.text(de.pairingTitle);
      expect(title, findsOneWidget);
      expect(
        tester.getRect(title).top,
        greaterThanOrEqualTo(tester.getRect(find.byTooltip(de.close)).bottom),
      );
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('help drops focus and opens the guide\'s pair page over the '
        'sheet; back returns to the sheet with its code and the typed text', (
      tester,
    ) async {
      await open(tester);
      await makeCode(tester);
      final code = PairingService.formatCode(gateway.invites.keys.single);
      expect(
        find.descendant(
          of: byId(SemanticsIds.pairingCode),
          matching: find.text(code),
        ),
        findsOneWidget,
      );
      await tester.enterText(field(), 'ABCD');
      await tester.pump();
      final focus = tester.widget<EditableText>(field()).focusNode;
      expect(focus.hasFocus, isTrue);

      await tester.tap(byId(SemanticsIds.pairingHow));
      await slide(tester);
      expect(byId(SemanticsIds.guideBookTopic('sync', 'pair')), findsOneWidget);
      expect(find.byType(GuideTopicPage), findsOneWidget);
      expect(focus.hasFocus, isFalse, reason: 'focus dropped before the push');

      await tester.pageBack();
      await slide(tester);
      expect(find.byType(GuideTopicPage), findsNothing);
      expect(tester.widget<EditableText>(field()).controller.text, 'ABCD');
      expect(
        find.descendant(
          of: byId(SemanticsIds.pairingCode),
          matching: find.text(code),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pair made while the guide is over the sheet takes the '
        'sheet from under it and leaves the guide where it is', (tester) async {
      await open(tester);
      await makeCode(tester);
      await tester.tap(byId(SemanticsIds.pairingHow));
      await slide(tester);

      await tester.runAsync(() async {
        await gateway.createPair(
          self: PairProfile(uid: userB.uid),
          partner: PairProfile(uid: userA.uid),
          inviteCode: gateway.invites.keys.single,
        );
        await pumpEventQueue();
      });
      await slide(tester);
      expect(bloc.state, isA<PairingPaired>());
      expect(find.byType(GuideTopicPage), findsOneWidget);

      await tester.pageBack();
      await slide(tester);
      expect(byId(SemanticsIds.pairingCodeField), findsNothing);
      expect(find.text('pair'), findsOneWidget);
    });

    // On a phone the field's one line cut the refusal to "That code is not
    // valid any…" even at 1.0; German is the longest of the three.
    for (final scale in const [1.0, 1.3]) {
      testWidgets('a refused code says the whole sentence under the field, '
          'in German at $scale on a 360 phone', (tester) async {
        await open(
          tester,
          locale: const Locale('de'),
          scale: scale,
          size: const Size(360, 780),
        );
        await tester.runAsync(() async {
          bloc.add(const RedeemCodeRequested('ABCD2345'));
          await pumpEventQueue();
        });
        await tester.pump();

        final de = lookupAppLocalizations(const Locale('de'));
        final refusal = find.text(de.pairingErrorCodeInvalid);
        expect(refusal, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(refusal);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.size.height,
          moreOrLessEquals(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width),
            epsilon: 0.01,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    // The header the sheet gained stacks at large text, and the body under
    // it did not scroll: at 2.0 in German the field and Connect ended under
    // the keyboard, 308 px past the screen.
    group('with the keyboard up, in German on a 360 phone', () {
      const keyboard = 320.0;
      const keysTop = 780.0 - keyboard;
      final de = lookupAppLocalizations(const Locale('de'));

      Finder connect() => find.descendant(
        of: byId(SemanticsIds.pairingConnect),
        matching: find.byType(FilledButton),
      );
      Finder fieldBox() => find.descendant(
        of: byId(SemanticsIds.pairingCodeField),
        matching: find.byType(TextField),
      );

      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final invite in const [false, true]) {
          final state = invite ? 'the code shown' : 'no code yet';
          testWidgets(
            '$state at $scale: the field rises above the keys with Connect '
            'under it, unscrolled, and nothing is stranded once they go',
            timeout: const Timeout(Duration(seconds: 60)),
            (tester) async {
              await open(
                tester,
                locale: const Locale('de'),
                scale: scale,
                size: const Size(360, 780),
              );
              if (invite) await makeCode(tester);
              await tester.showKeyboard(field());
              tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
              await slide(tester);

              expect(tester.takeException(), isNull);
              expect(
                tester.getRect(fieldBox()).bottom,
                lessThanOrEqualTo(keysTop),
                reason: 'the focused field is brought above the keys',
              );
              expect(
                tester.getRect(fieldBox()).top,
                greaterThanOrEqualTo(
                  tester.getRect(find.byType(FormSheetHeader)).bottom,
                ),
                reason: 'the field is not pushed under the header',
              );
              expect(
                tester.getRect(connect()).bottom,
                lessThanOrEqualTo(keysTop),
                reason: 'Connect, which finishes the field, comes up with it',
              );
              expect(
                find.byType(FormSheetHeader).hitTestable(),
                findsOneWidget,
                reason: 'the header stays put',
              );

              await tester.enterText(field(), 'ABCD-2345');
              await tester.pump();
              expect(
                tester.getRect(connect()).bottom,
                lessThanOrEqualTo(keysTop),
              );
              await tester.tap(connect());
              await tester.runAsync(pumpEventQueue);
              await tester.pump();
              expect(
                find.text(de.pairingErrorCodeInvalid),
                findsOneWidget,
                reason: 'Connect took the tap',
              );

              tester.view.viewInsets = FakeViewPadding.zero;
              await slide(tester);
              expect(tester.takeException(), isNull);
              final position = tester
                  .state<ScrollableState>(
                    find.ancestor(
                      of: fieldBox(),
                      matching: find.byType(Scrollable),
                    ),
                  )
                  .position;
              expect(
                position.pixels,
                lessThanOrEqualTo(position.maxScrollExtent),
              );
              expect(
                tester
                    .getRect(
                      find
                          .ancestor(
                            of: fieldBox(),
                            matching: find.byType(Scrollable),
                          )
                          .first,
                    )
                    .bottom,
                780,
                reason: 'the sheet still reaches the screen\'s edge',
              );
              await tester.ensureVisible(connect());
              await tester.pump();
              expect(tester.getRect(connect()).bottom, lessThanOrEqualTo(780));
            },
          );
        }
      }

      // The keys' Done is the field's own Connect: a whole code is sent as
      // the button sends it, part of one is not.
      testWidgets('the keyboard\'s Done connects a whole code and does nothing '
          'with part of one', (tester) async {
        await open(
          tester,
          locale: const Locale('de'),
          size: const Size(360, 780),
        );
        await tester.showKeyboard(field());
        expect(
          tester.testTextInput.setClientArgs?['inputAction'],
          TextInputAction.done.toString(),
        );

        await tester.enterText(field(), 'ABCD-23');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
        expect(find.text(de.pairingErrorCodeInvalid), findsNothing);

        await tester.showKeyboard(field());
        await tester.enterText(field(), 'ABCD-2345');
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
        expect(
          find.text(de.pairingErrorCodeInvalid),
          findsOneWidget,
          reason: 'the code went to the service, as Connect sends it',
        );
      });

      // At 2.0 with a code shown the sheet grows to the screen's height,
      // and its handle, ✕ and help stood under the status bar.
      testWidgets('a sheet grown to the screen\'s height keeps its handle and '
          'header below the status bar', (tester) async {
        const statusBar = 24.0;
        await open(
          tester,
          locale: const Locale('de'),
          scale: 2.0,
          size: const Size(360, 780),
        );
        tester.view.padding = const FakeViewPadding(top: statusBar);
        tester.view.viewPadding = const FakeViewPadding(top: statusBar);
        await makeCode(tester);
        await tester.showKeyboard(field());
        tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
        await slide(tester);

        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(FormSheetHandle)).top,
          greaterThanOrEqualTo(statusBar),
        );
        expect(
          tester.getRect(find.byType(FormSheetHeader)).top,
          greaterThanOrEqualTo(statusBar),
        );
      });
    });

    // Copy, Share and Cancel in one row cut "Abbrechen" in German at 1.0.
    group('the code\'s actions never overflow on a 360 phone', () {
      final cases = [
        (const Locale('de'), 1.0),
        (const Locale('de'), 1.3),
        (const Locale('de'), 2.0),
        (const Locale('en'), 1.0),
      ];
      for (final (locale, scale) in cases) {
        testWidgets('${locale.languageCode} at $scale', (tester) async {
          await open(
            tester,
            locale: locale,
            scale: scale,
            size: const Size(360, 780),
          );
          await makeCode(tester);
          expect(tester.takeException(), isNull);

          final l10n = lookupAppLocalizations(locale);
          final buttons = [
            for (final word in [l10n.copy, l10n.share, l10n.cancel])
              find.ancestor(
                of: find.text(word),
                matching: find.byWidgetPredicate((w) => w is TextButton),
              ),
          ];
          final rects = [for (final b in buttons) tester.getRect(b)];
          for (final rect in rects) {
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
          }
          final oneRow = rects.every((r) => r.top == rects.first.top);
          if (oneRow) {
            expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
            expect(rects[1].right, lessThanOrEqualTo(rects[2].left));
          } else {
            expect(rects[0].bottom, lessThanOrEqualTo(rects[1].top));
            expect(rects[1].bottom, lessThanOrEqualTo(rects[2].top));
          }
          if (locale.languageCode == 'en') {
            expect(oneRow, isTrue, reason: 'English fits one row, as before');
          }
        });
      }
    });

    testWidgets('the code stays on one line at 2.0 on a narrow phone, scaled '
        'down to fit, and can still be selected', (tester) async {
      await open(tester, scale: 2.0, size: const Size(320, 780));
      await makeCode(tester);
      expect(tester.takeException(), isNull);

      final code = find.descendant(
        of: byId(SemanticsIds.pairingCode),
        matching: find.byType(EditableText),
      );
      final RenderEditable editable = tester
          .state<EditableTextState>(code)
          .renderEditable;
      expect(
        editable.size.height,
        moreOrLessEquals(editable.preferredLineHeight, epsilon: 0.5),
        reason: 'one line',
      );
      final rect = tester.getRect(code);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('the parts carry the sheet\'s ids and words: Create a code, '
        'the code with its life and Copy, and Connect held until a whole '
        'code is typed', (tester) async {
      await open(tester);
      expect(
        find.descendant(
          of: byId(SemanticsIds.pairingGenerate),
          matching: find.text(en.pairingGenerateCode),
        ),
        findsOneWidget,
      );
      await makeCode(tester);
      expect(find.text(en.pairingCodeIntro), findsOneWidget);
      // The service stamps the life on the wall clock, which runs on
      // through the gateway's real-time answer: read its shape, not a
      // second.
      expect(
        find.textContaining(
          RegExp(
            '^${RegExp.escape(en.pairingCodeExpiresIn('@'))}'.replaceFirst(
              '@',
              r'\d+:\d\d',
            ),
          ),
        ),
        findsOneWidget,
      );
      for (final word in [en.copy, en.share, en.cancel]) {
        expect(find.text(word), findsOneWidget, reason: word);
      }

      bool connectEnabled() => tester
          .widget<FilledButton>(
            find.descendant(
              of: byId(SemanticsIds.pairingConnect),
              matching: find.byType(FilledButton),
            ),
          )
          .enabled;
      expect(connectEnabled(), isFalse);
      await tester.enterText(field(), 'ABCD-EFG');
      await tester.pump();
      expect(connectEnabled(), isFalse);
      await tester.enterText(field(), 'ABCD-EFGH');
      await tester.pump();
      expect(connectEnabled(), isTrue);
    });
  });
}

/// A route's slide in or out — a page's fade-forwards takes 800 ms — the
/// countdown's ticker left running: never settled.
Future<void> slide(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
