import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_search_field.dart';

/// The shortcut list shows a default by its localized name, and the search
/// reads that name: a German reader sees and finds "Fett" and is never shown
/// the English seed the row was stored under, which the search still reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_markdown_settings');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in real async: inside `testWidgets` the database answers
    // on a background isolate that `FakeAsync` never lets run.
    final db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    await SettingsService.getInstance();
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
  });

  tearDownAll(() async {
    await barBloc.close();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Hands the real event loop back so the page's settings reads land,
  /// then flushes their `setState`s into frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    // Phone-wide and tall: the width is the larger phone's (412 dp), so the
    // German captions that once overflowed their rows are laid out as a
    // user sees them (an overflow throws here); the height is tall so the
    // whole page is built and the shortcut list below the other sections
    // exists.
    tester.view.physicalSize = const Size(412, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: MarkdownSettingsPage(
            allShortcuts: DefaultMarkdownShortcuts.shortcuts,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    // The utility section has a search field of its own.
    final hint = lookupAppLocalizations(const Locale('de')).searchShortcuts;
    final field = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is SettingsSearchField && widget.hint == hint,
      ),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, query);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a default shows its localized name, and the search finds it '
      'by that name', (tester) async {
    await pumpPage(tester);
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.bold, 'Fett');
    Finder row(String label) =>
        find.descendant(of: find.byType(Card), matching: find.text(label));

    expect(row(de.bold), findsOneWidget);
    expect(row(de.italic), findsOneWidget);
    expect(row('Bold'), findsNothing, reason: 'never the stored seed');

    await search(tester, 'Fett');

    expect(row(de.bold), findsOneWidget, reason: 'the bold row');
    expect(row(de.italic), findsNothing);

    // The stored seed is searched beside the shown name (the page's own
    // decision), so the English word still finds the row — under its
    // German name.
    await search(tester, 'Bold');

    expect(row(de.bold), findsOneWidget);
    expect(row(de.italic), findsNothing, reason: 'the search still narrows');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
