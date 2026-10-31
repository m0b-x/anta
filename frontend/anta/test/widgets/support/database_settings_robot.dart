import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/database_settings_page.dart';

import 'layout_errors.dart';

/// Drives [DatabaseSettingsPage] for its pinned suite: the suite says what the
/// user does and reads what the page shows.
///
/// S6 of the settings rework (`docs/settings-rework-roadmap.md`, D8) edits
/// this page under that suite; keeping the finders here is what lets the
/// bodies stay unchanged when the page's widgets move.
class DatabaseSettingsRobot {
  DatabaseSettingsRobot(this.tester);

  final WidgetTester tester;

  Finder get _dialog => find.byType(AlertDialog);

  /// What the route beneath the page shows when [pump] is asked for one.
  static const baseText = 'the route beneath';

  /// [overBase] pushes the page over a plain route instead of making it the
  /// app's home, for a path whose stray pop would take the page itself away.
  Future<void> pump({
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool overBase = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: overBase
            ? const Scaffold(body: Text(baseText))
            : const DatabaseSettingsPage(),
      ),
    );
    if (overBase) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const DatabaseSettingsPage()),
      );
    }
    await settleUntil(() => !_loadingPage && showsPage);
  }

  /// The page's file work and the database answer on real IO, which
  /// `FakeAsync` alone never completes, so real time and pumped frames are
  /// interleaved rather than `pumpAndSettle` used — a loading dialog's
  /// spinner would keep that from ever settling anyway.
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

  bool get _loadingPage =>
      find.byType(CircularProgressIndicator).evaluate().isNotEmpty;

  /// A loading dialog is up.
  bool get showsLoading => find
      .descendant(of: _dialog, matching: find.byType(CircularProgressIndicator))
      .evaluate()
      .isNotEmpty;

  bool get showsDialog => _dialog.evaluate().isNotEmpty;

  /// The page's own route is still on screen — no stray pop took it away.
  bool get showsPage => find.byType(DatabaseSettingsPage).evaluate().isNotEmpty;

  /// Whether [text] is shown anywhere — a snackbar, a dialog, a row.
  bool shows(String text) => find.textContaining(text).evaluate().isNotEmpty;

  Finder _row(String name) =>
      find.ancestor(of: find.text(name), matching: find.byType(ListTile));

  /// The value the info card shows beside [label] — the size, the path.
  String statValue(String label) {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    return tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .last
        .data!;
  }

  /// The database list has a row titled [name].
  bool listsDatabase(String name) => _row(name).evaluate().isNotEmpty;

  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await settle(rounds: 2);
    await tester.tap(target);
    await settle();
  }

  /// Taps a page button by its label (create, import, optimize, share,
  /// delete all).
  Future<void> tapButton(String label) async {
    await scrollTo(label);
    await _tap(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
    );
  }

  /// Scrolls the page until [text] is built and on screen; the list builds
  /// lazily, so the maintenance and danger cards do not exist until then.
  Future<void> scrollTo(String text) =>
      _scrollUntilBuilt(find.text(text), find.byType(Scrollable).first);

  /// Moves [scrollable] a step at a time until [target] is built, then
  /// brings it on screen. The position is driven directly: a drag at the
  /// page's centre lands on the nested database list at a large text scale,
  /// which takes the gesture instead of the page.
  Future<void> _scrollUntilBuilt(Finder target, Finder scrollable) async {
    final position = tester.state<ScrollableState>(scrollable).position;
    while (target.evaluate().isEmpty &&
        position.pixels < position.maxScrollExtent) {
      position.jumpTo(
        (position.pixels + 200).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pump();
    }
    if (target.evaluate().isEmpty) fail('$target was never built');
    await tester.ensureVisible(target.first);
    await settle(rounds: 2);
  }

  /// Whether a row menu's overflows are kept in [menuOverflows] instead of
  /// failing the test.
  ///
  /// The menu's entries are bare `Row`s inside the popup's 256 dp of content
  /// width, so "Zu dieser Datenbank wechseln" overflows at de 2.0. That is
  /// S6's to fix, and only the case that pins it turns this on: every other
  /// test still fails on an overflow.
  bool captureMenuOverflows = false;

  /// The text of each row a menu overflowed on while it was open or closing,
  /// kept only while [captureMenuOverflows] is on.
  final List<String> menuOverflows = [];

  Future<void> _inMenu(Future<void> Function() body) async {
    if (!captureMenuOverflows) return body();
    final errors = await layoutErrorsDuring(body);
    for (final error in errors) {
      // The report names the overflowing flex itself ("The specific
      // RenderFlex in question is"); its text says which entry it is.
      final flex = error.informationCollector
          ?.call()
          .whereType<DiagnosticableTreeNode>()
          .map((node) => node.value)
          .whereType<RenderFlex>()
          .firstOrNull;
      if (flex != null &&
          error.exceptionAsString().contains('RenderFlex overflowed')) {
        menuOverflows.add(_textUnder(flex));
      } else {
        FlutterError.reportError(error);
      }
    }
  }

  static String _textUnder(RenderObject root) {
    final text = StringBuffer();
    void visit(RenderObject node) {
      if (node is RenderParagraph) text.write(node.text.toPlainText());
      node.visitChildren(visit);
    }

    visit(root);
    return text.toString();
  }

  Future<void> openMenu(String database) async {
    // The database list is its own scroll of at most 240 dp inside the page;
    // at a large text scale only its first row is built.
    if (!listsDatabase(database)) {
      await _scrollUntilBuilt(
        find.text(database),
        find.byType(Scrollable).at(1),
      );
    }
    // Through the button's own state: at de 2.0 a row is taller than the
    // list's 240 dp, and its ⋮ can sit clipped below the list's edge.
    await _inMenu(() async {
      tester
          .state<PopupMenuButtonState<String>>(
            find.descendant(
              of: _row(database),
              matching: find.byType(PopupMenuButton<String>),
            ),
          )
          .showButtonMenu();
      await settle();
    });
  }

  /// The open menu's entry labelled [label].
  PopupMenuItem<String> menuItem(String label) => tester.widget(
    find.ancestor(
      of: find.text(label).last,
      matching: find.byType(PopupMenuItem<String>),
    ),
  );

  Future<void> chooseFromMenu(String label) =>
      _inMenu(() => _tap(find.text(label).last));

  /// Closes an open menu by tapping outside it.
  Future<void> dismissMenu() => _inMenu(tapOutsideDialog);

  Future<void> enterName(String name) async {
    await tester.enterText(
      find.descendant(of: _dialog, matching: find.byType(TextField)),
      name,
    );
    await settle(rounds: 2);
  }

  /// The name field of the open text dialog.
  String get dialogFieldText => tester
      .widget<TextField>(
        find.descendant(of: _dialog, matching: find.byType(TextField)),
      )
      .controller!
      .text;

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

  /// Taps outside the open dialog, where a dismissible one would close.
  Future<void> tapOutsideDialog() async {
    await tester.tapAt(const Offset(4, 4));
    await settle();
  }
}
