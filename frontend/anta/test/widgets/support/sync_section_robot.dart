import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/sync_settings_page.dart';

/// Drives the Sharing page's Sync section and the bind picker for their
/// suite: the suite says what the user does and reads what the page shows,
/// by the rows' `SemanticsIds`.
class SyncSectionRobot {
  SyncSectionRobot(this.tester);

  final WidgetTester tester;

  /// [pushed] opens the page over a blank route, so leaving it can be
  /// tried; [settled] false returns on the first frame, before the bloc's
  /// first answer.
  Future<void> pumpPage({
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    bool pushed = false,
    bool settled = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        initialRoute: pushed ? '/sync' : '/',
        routes: {
          '/': (_) => pushed ? const Scaffold() : const SyncSettingsPage(),
          '/sync': (_) => const SyncSettingsPage(),
        },
      ),
    );
    if (settled) await settle();
  }

  /// Drift answers on futures `FakeAsync` alone never completes, so real
  /// time and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle({int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  /// The settings row under [id] — every Sync section row is a `ListTile`.
  ListTile tile(String id) => tester.widget<ListTile>(
    find.descendant(of: byId(id), matching: find.byType(ListTile)),
  );

  /// Whether [text] is drawn inside the node [id] — not merely laid out
  /// unseen, as the status row's templates are.
  bool shows(String id, String text) => find
      .descendant(of: byId(id), matching: find.text(text))
      .evaluate()
      .any(drawn);

  /// False for an element under a zero opacity: a slot's template.
  static bool drawn(Element element) {
    var seen = true;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Opacity && widget.opacity == 0) seen = false;
      return seen;
    });
    return seen;
  }

  bool busy(String id) => find
      .descendant(
        of: byId(id),
        matching: find.byType(CircularProgressIndicator),
      )
      .evaluate()
      .isNotEmpty;

  double height(String id) => tester.getSize(byId(id)).height;

  Future<void> tap(String id) async {
    await tester.ensureVisible(byId(id));
    await tester.pump();
    await tester.tap(byId(id));
    await settle();
  }

  /// Walks the settings list to its end and back, so a lazy list builds —
  /// and lays out — every row at least once.
  Future<void> scrollThrough() async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, -300));
      await tester.pump();
    }
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, 300));
      await tester.pump();
    }
  }
}
