import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/markdown_bar_profile.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';

import '../goldens/support/golden_fonts.dart';

/// The markdown settings page's destructive paths — Reset to default, Remove
/// all custom, a shortcut's Delete and a bar's Delete — pinned against today's behaviour before
/// S6 of the settings rework (`docs/settings-rework-roadmap.md`, §6 "Pinned
/// in S0") touches the page. Each outcome is read back from the store, by a
/// fresh service the way the next launch reads it, not only from the widget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MarkdownBarBloc barBloc;

  final l10n = AppLocalizationsEn();
  const defaultId = MarkdownBarProfile.defaultProfileId;

  // The default bar as a user left it: the first built-in hidden, and one
  // shortcut of their own after the built-ins.
  final hiddenFirst = DefaultMarkdownShortcuts.shortcuts.first.copyWith(
    isVisible: false,
  );
  const custom = CustomMarkdownShortcut(
    id: 'custom_set',
    label: 'Set',
    iconCodePoint: 0xe145,
    iconFontFamily: 'MaterialIcons',
    beforeText: 'Set ',
    afterText: '',
  );
  final seeded = [
    hiddenFirst,
    ...DefaultMarkdownShortcuts.shortcuts.skip(1),
    custom,
  ];

  setUpAll(() async {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and overflow the page menu's rows where no device does.
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp(
      'anta_markdown_destructive',
    );
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
  });

  setUp(() async {
    final service = await MarkdownBarService.getInstance();
    for (final profile in service.profiles.where((p) => !p.isDefault)) {
      await service.deleteProfile(profile.id);
    }
    await service.setActiveProfile(defaultId);
    await service.updateShortcuts(defaultId, seeded);
    barBloc = MarkdownBarBloc(barService: service)
      ..add(const LoadMarkdownBar());
    await barBloc.stream.firstWhere((s) => s is MarkdownBarLoaded);
  });

  tearDown(() async {
    await barBloc.close();
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Hands the real event loop back so the page's reads and the bloc's writes
  /// land, then flushes their `setState`s into frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: MarkdownSettingsPage(
            allShortcuts: DefaultMarkdownShortcuts.shortcuts,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// The profiles as the store holds them: the singleton is dropped and read
  /// again from the database. The bloc under the page keeps the old instance;
  /// the next `setUp` picks up the fresh one.
  Future<List<MarkdownBarProfile>> storedProfiles(WidgetTester tester) async {
    final profiles = await tester.runAsync(() async {
      MarkdownBarService.reset();
      return (await MarkdownBarService.getInstance()).profiles;
    });
    return profiles!;
  }

  Future<List<CustomMarkdownShortcut>> storedDefaultBar(
    WidgetTester tester,
  ) async => (await storedProfiles(
    tester,
  )).firstWhere((p) => p.id == defaultId).shortcuts;

  /// Picks [label] from the app bar's ⋮ — the page-level menu, not a bar's
  /// or a shortcut's.
  Future<void> chooseFromPageMenu(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Picks [label] from the bar selector's ⋮, the menu that sits beside the
  /// selector's add button.
  Future<void> chooseFromBarMenu(WidgetTester tester, String label) async {
    final selector = find
        .ancestor(of: find.byTooltip(l10n.addBar), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: selector, matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> answerDialog(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await settle(tester);
  }

  List<CustomMarkdownShortcut> blocShortcuts() =>
      (barBloc.state as MarkdownBarLoaded).currentShortcuts;

  group('Reset to default', () {
    // Today the reset restores the built-ins and keeps the user's own
    // shortcuts after them — it is not a wipe of the customs.
    testWidgets('confirmed puts the built-ins back as shipped and keeps the '
        'custom after them, in the store', (tester) async {
      await pumpPage(tester);

      await chooseFromPageMenu(tester, l10n.resetToDefault);
      expect(find.text(l10n.resetDialogMessage), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      final expected = [...DefaultMarkdownShortcuts.shortcuts, custom];
      expect(blocShortcuts(), expected);
      expect(await storedDefaultBar(tester), expected);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelled leaves the store as it was', (tester) async {
      await pumpPage(tester);

      await chooseFromPageMenu(tester, l10n.resetToDefault);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(blocShortcuts(), seeded);
      expect(await storedDefaultBar(tester), seeded);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Remove all custom', () {
    testWidgets('confirmed removes the customs only — an edited built-in '
        'stays as edited', (tester) async {
      await pumpPage(tester);

      await chooseFromPageMenu(tester, l10n.removeAllCustom);
      expect(find.text(l10n.removeCustomDialogMessage), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      final expected = [
        hiddenFirst,
        ...DefaultMarkdownShortcuts.shortcuts.skip(1),
      ];
      expect(blocShortcuts(), expected);
      expect(await storedDefaultBar(tester), expected);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelled leaves the store as it was', (tester) async {
      await pumpPage(tester);

      await chooseFromPageMenu(tester, l10n.removeAllCustom);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(blocShortcuts(), seeded);
      expect(await storedDefaultBar(tester), seeded);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Delete shortcut', () {
    /// Picks Delete from the custom shortcut's own ⋮; built-ins offer none.
    Future<void> chooseDeleteOnCustom(WidgetTester tester) async {
      final row = find.ancestor(
        of: find.text(custom.label),
        matching: find.byType(ListTile),
      );
      await tester.scrollUntilVisible(
        find.text(custom.label),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.more_vert)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text(l10n.delete),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('confirmed removes that shortcut alone from the bloc and the '
        'store', (tester) async {
      await pumpPage(tester);

      await chooseDeleteOnCustom(tester);
      expect(find.text(l10n.deleteShortcutConfirm), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      final expected = [
        hiddenFirst,
        ...DefaultMarkdownShortcuts.shortcuts.skip(1),
      ];
      expect(blocShortcuts(), expected);
      expect(await storedDefaultBar(tester), expected);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelled leaves the store as it was', (tester) async {
      await pumpPage(tester);

      await chooseDeleteOnCustom(tester);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(blocShortcuts(), seeded);
      expect(await storedDefaultBar(tester), seeded);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Delete bar', () {
    Future<String> addBar(WidgetTester tester) async {
      final id = await tester.runAsync(() async {
        barBloc.add(const AddBarProfile(name: 'Gym'));
        final loaded = await barBloc.stream.firstWhere(
          (s) => s is MarkdownBarLoaded && s.profiles.length == 2,
        );
        return (loaded as MarkdownBarLoaded).editingProfileId!;
      });
      expect((await storedProfiles(tester)).map((p) => p.id), [defaultId, id]);
      return id!;
    }

    testWidgets('confirmed removes the bar from the bloc and the store and '
        'leaves the default bar alone', (tester) async {
      final gym = await addBar(tester);
      await pumpPage(tester);

      await chooseFromBarMenu(tester, l10n.deleteBar);
      expect(find.text(l10n.deleteBarConfirm), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      final state = barBloc.state as MarkdownBarLoaded;
      expect(state.profiles.map((p) => p.id), [defaultId]);
      expect(state.editingProfileId, defaultId);
      final stored = await storedProfiles(tester);
      expect(stored.map((p) => p.id), [defaultId]);
      expect(stored.any((p) => p.id == gym), isFalse);
      expect(stored.single.shortcuts, seeded);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelled keeps the bar in the bloc and the store', (
      tester,
    ) async {
      final gym = await addBar(tester);
      await pumpPage(tester);

      await chooseFromBarMenu(tester, l10n.deleteBar);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      final state = barBloc.state as MarkdownBarLoaded;
      expect(state.profiles.map((p) => p.id), [defaultId, gym]);
      final stored = await storedProfiles(tester);
      expect(stored.map((p) => p.id), [defaultId, gym]);
      expect(stored.first.shortcuts, seeded);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
