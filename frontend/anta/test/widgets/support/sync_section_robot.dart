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

  Future<void> pumpPage({
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
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
        home: const SyncSettingsPage(),
      ),
    );
    await settle();
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

  /// Whether [text] is drawn inside the node [id].
  bool shows(String id, String text) => find
      .descendant(of: byId(id), matching: find.text(text))
      .evaluate()
      .isNotEmpty;

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
