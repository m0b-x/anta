import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/onboarding_page.dart';

/// Drives [OnboardingPage] for its pinned suite: the suite says what the
/// user does and reads what the page shows.
///
/// S3 of the settings rework (`docs/settings-rework-roadmap.md`, D9) makes
/// the page scroll and S9 pluralizes its confirmation; keeping the finders
/// here is what lets the bodies stay unchanged across both.
class OnboardingRobot {
  OnboardingRobot(this.tester);

  final WidgetTester tester;

  /// How many times the page handed control back to the app.
  int completions = 0;

  late AppLocalizations _l10n;

  Finder get _dialog => find.byType(AlertDialog);

  Future<void> pump({
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    _l10n = lookupAppLocalizations(locale);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: OnboardingPage(onComplete: () => completions++),
      ),
    );
    await settle(rounds: 2);
  }

  /// The page's file work and the database answer on real IO, which
  /// `FakeAsync` alone never completes, so real time and pumped frames are
  /// interleaved rather than `pumpAndSettle` used.
  Future<void> settle({int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Settles until [done] holds, failing after [maxRounds].
  Future<void> settleUntil(bool Function() done, {int maxRounds = 300}) async {
    for (var i = 0; i < maxRounds; i++) {
      if (done()) return;
      await settle(rounds: 1);
    }
    if (!done()) fail('the page never reached the expected state');
  }

  /// The two choices are replaced by a spinner while an import runs.
  bool get importing =>
      find.byType(CircularProgressIndicator).evaluate().isNotEmpty;

  bool get showsChoices => find.text(_l10n.startFresh).evaluate().isNotEmpty;

  bool get showsDialog => _dialog.evaluate().isNotEmpty;

  /// Whether [text] is shown anywhere — a snackbar, a dialog, the page.
  bool shows(String text) => find.textContaining(text).evaluate().isNotEmpty;

  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await settle(rounds: 2);
    await tester.tap(target);
    await settle();
  }

  Future<void> startFresh() => _tap(find.text(_l10n.startFresh));

  Future<void> restoreFromBackup() => _tap(find.text(_l10n.restoreFromBackup));

  Future<void> confirmDialog() =>
      _tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));

  Future<void> cancelDialog() =>
      _tap(find.bySemanticsIdentifier(SemanticsIds.sheetCancel));

  /// Taps the single action of an action dialog ("Exit app").
  Future<void> tapDialogAction(String label) => _tap(
    find.descendant(
      of: _dialog,
      matching: find.widgetWithText(FilledButton, label),
    ),
  );
}
