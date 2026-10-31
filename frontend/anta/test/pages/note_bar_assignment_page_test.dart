import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/markdown_bar_profile.dart';
import 'package:anta/pages/note_bar_assignment_page.dart';
import 'package:anta/services/markdown_bar_service.dart';

import '../goldens/support/golden_fonts.dart';
import '../widgets/support/layout_errors.dart';

/// The per-note bar page's smoke suite (D14 of
/// `docs/settings-rework-roadmap.md`), pinned before S6 of the settings
/// rework names its row menus (S18): it opens on two notes, measures at
/// de 2.0 on the small phone, and a row's menu opens and dismisses with
/// nothing written and nothing sent to the bloc.
///
/// The page opens `AppDatabase.getInstance()` itself, so the suite runs over
/// the file-backed database in a temporary documents directory, opened in
/// real async, with the bar service over the same database in `GetIt`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  final l10n = AppLocalizationsEn();

  setUpAll(() async {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp('anta_note_bar');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in real async: inside `testWidgets` the database answers
    // on a background isolate that `FakeAsync` never lets run.
    final db = await AppDatabase.getInstance();
    final folder = await db.folderDao.createFolder(name: 'Training');
    await db.noteDao.createNote(folderId: folder.id, title: 'Leg day');
    await db.noteDao.createNote(folderId: folder.id, title: 'Arm day');
    GetIt.I.registerSingleton<MarkdownBarService>(
      await MarkdownBarService.getInstance(),
    );
  });

  setUp(() async {
    barBloc = MarkdownBarBloc(barService: GetIt.I<MarkdownBarService>())
      ..add(const LoadMarkdownBar());
    await barBloc.stream.firstWhere((s) => s is MarkdownBarLoaded);
  });

  tearDown(() async {
    await barBloc.close();
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Hands the real event loop back so the page's reads land, then flushes
  /// their `setState`s into frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const NoteBarAssignmentPage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Every stored setting, where a per-note assignment would land.
  Future<Map<String, String>> storedSettings(WidgetTester tester) async =>
      (await tester.runAsync(
        () async =>
            (await AppDatabase.getInstance()).userSettingsDao.getAllSettings(),
      ))!;

  Finder rowMenu(String title) => find.descendant(
    of: find.widgetWithText(ListTile, title),
    matching: find.byType(PopupMenuButton<String?>),
  );

  testWidgets('it opens on every note, each on the global bar, sorted by '
      'title', (tester) async {
    await pumpPage(tester);

    expect(find.text(l10n.perNoteBarHint), findsOneWidget);
    expect(find.text(l10n.useGlobalBar), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Arm day')).dy,
      lessThan(tester.getTopLeft(find.text('Leg day')).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("a row's menu opens on the global bar and every profile, and "
      'dismisses writing nothing', (tester) async {
    await pumpPage(tester);
    final before = await storedSettings(tester);
    final states = <MarkdownBarState>[];
    final subscription = barBloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    await tester.tap(rowMenu('Leg day'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(PopupMenuItem<String?>, l10n.useGlobalBar),
      findsOneWidget,
    );
    final defaultBar = GetIt.I<MarkdownBarService>().profiles.firstWhere(
      (p) => p.id == MarkdownBarProfile.defaultProfileId,
    );
    expect(
      find.widgetWithText(PopupMenuItem<String?>, defaultBar.name),
      findsOneWidget,
    );

    // Outside the menu: the barrier's dismiss, as a tap beside it does.
    await tester.tapAt(const Offset(8, 8));
    await settle(tester);

    expect(find.byType(PopupMenuItem<String?>), findsNothing);
    expect(find.text(l10n.useGlobalBar), findsNWidgets(2));
    expect(states, isEmpty);
    expect(await storedSettings(tester), before);
    expect(
      await tester.runAsync(
        GetIt.I<MarkdownBarService>().getAllNoteBarAssignments,
      ),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('smoke', () {
    Future<void> pumpSmall(WidgetTester tester) => pumpPage(
      tester,
      size: const Size(360, 780),
      locale: const Locale('de'),
      textScale: 2.0,
    );

    testWidgets('de 2.0 on 360 × 780 fits with no exception', (tester) async {
      final errors = await layoutErrorsDuring(() => pumpSmall(tester));

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.text('Leg day'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // Today's state, pinned so S6 sees it change: the menu's "Use global
    // bar" item is a Row of an icon, a gap and an unbounded Text, and
    // "Globale Leiste verwenden" at 2.0 runs 94 dp past the 256 dp the
    // menu gives it (measured 2026-10-31). When S6 bounds the label, this
    // expectation flips to `isEmpty`.
    testWidgets("de 2.0 on 360 × 780, the row menu's global item overflows "
        'on the right (known, S6)', (tester) async {
      await pumpSmall(tester);
      final errors = await layoutErrorsDuring(() async {
        await tester.tap(rowMenu('Leg day'));
        await tester.pumpAndSettle();
      });

      expect(errors, hasLength(1));
      expect(
        errors.single.exceptionAsString(),
        allOf(contains('RenderFlex overflowed'), contains('on the right')),
      );
      expect(
        errors.single.toString(),
        contains('note_bar_assignment_page.dart'),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
