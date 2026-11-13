import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/share/share_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/share_folders_sheets.dart';
import 'package:anta/widgets/share_list_frame.dart';

import '../goldens/support/golden_fonts.dart';
import '../support/fake_share_service.dart';
import 'support/semantics_geometry.dart';

/// The two Folders lists of the Sharing page (the slice F spec F8, D37):
/// mine, whose ✕ un-shares at once with Undo and whose "Share a folder"
/// shares one more through the picker, and the partner's, read-only, whose
/// tap leaves for the folder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trips = MySharedFolder(
    id: 'trips',
    name: 'Trips',
    parentName: null,
    noteCount: 3,
  );
  const lisbon = MySharedFolder(
    id: 'lisbon',
    name: 'Lisbon',
    parentName: 'Travel',
    noteCount: 1,
  );
  const recipes = PartnerSharedFolder(
    id: 'recipes',
    name: 'Recipes',
    noteCount: 40,
  );

  late FakeShareService service;
  late ShareBloc bloc;
  late List<String> pickerLabels;
  late String? picked;
  late List<PartnerSharedFolder> opened;
  final en = lookupAppLocalizations(const Locale('en'));

  ShareAudience audienceOf(String? name) =>
      ShareAudience(id: 'pair-1', displayName: name, members: const []);

  // The real faces, as the spec measured them.
  setUpAll(loadGoldenFonts);

  setUp(() {
    service = FakeShareService(availability: ShareReady(audienceOf('Maria')))
      ..shareOverview = const ShareOverview(
        folders: [lisbon, trips],
        folderCount: 2,
        partnerFolders: [recipes],
      );
    pickerLabels = [];
    picked = 'pick';
    opened = [];
  });

  /// Loads the bloc as the Sharing page would, then opens [show] from a
  /// button on a 360 × 780 phone.
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) show, {
    Locale locale = const Locale('en'),
    double scale = 1.0,
    ThemeData? theme,
    bool settled = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.reset);
    bloc = ShareBloc(
      service: () async => service,
      calendarChanges: const Stream.empty(),
    );
    addTearDown(bloc.close);
    bloc.add(const ShareOpened());
    await tester.runAsync(
      () => bloc.stream.firstWhere((state) => state is ShareLoaded),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (!settled) return;
    await tester.pumpAndSettle();
  }

  /// My list in the frame `show` opens, its picker and its name lookup the
  /// test's own: the picker records its confirm label and answers [picked].
  Future<void> openMine(
    WidgetTester tester, {
    Locale? locale,
    double? scale,
    ThemeData? theme,
    bool settled = true,
    ShareFolderPicker? pickFolder,
  }) => open(
    tester,
    (context) => showShareListSheet(
      context,
      MySharedFoldersSheet(
        bloc: bloc,
        shareService: () async => service,
        pickFolder:
            pickFolder ??
            (_, partnerName) async {
              pickerLabels.add(partnerName);
              return picked;
            },
        folderName: (id) async => id == 'lisbon' ? 'Lisbon' : null,
      ),
    ),
    locale: locale ?? const Locale('en'),
    scale: scale ?? 1.0,
    theme: theme,
    settled: settled,
  );

  Future<void> openTheirs(
    WidgetTester tester, {
    Locale? locale,
    double? scale,
    ThemeData? theme,
    String? partner = 'Maria',
  }) => open(
    tester,
    (context) => showShareListSheet(
      context,
      PartnerSharedFoldersSheet(
        bloc: bloc,
        partnerName: partner,
        onOpen: (_, folder) async => opened.add(folder),
      ),
    ),
    locale: locale ?? const Locale('en'),
    scale: scale ?? 1.0,
    theme: theme,
  );

  /// Lets the bloc's write and its reload land.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  FormPickerRow rowOf(WidgetTester tester, String label) =>
      tester.widget<FormPickerRow>(
        find.byWidgetPredicate((w) => w is FormPickerRow && w.label == label),
      );

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Finder unshare(String id) => byId(SemanticsIds.shareFolderUnshare(id));

  Finder add() => byId(SemanticsIds.shareFoldersAdd);

  /// The sheet's own ✕ — the snackbar over it carries a Close of its own.
  Finder sheetClose() => find.descendant(
    of: find.byType(FormSheetHeader),
    matching: find.byTooltip('Close'),
  );

  group('my shared folders', () {
    testWidgets('lists each with where it lies and its notes, a ✕, and '
        '"Share a folder" last, under "Folders"', (tester) async {
      await openMine(tester);

      expect(byId(SemanticsIds.shareFoldersSheet), findsOneWidget);
      expect(find.text('Folders'), findsOneWidget);
      expect(
        tester
            .widget<FormSheetHeader>(find.byType(FormSheetHeader))
            .titleIsHeading,
        isTrue,
      );
      expect(rowOf(tester, 'Lisbon').caption, 'Travel · 1 note');
      expect(rowOf(tester, 'Trips').caption, '3 notes');
      final row = rowOf(tester, 'Trips');
      expect(row.glyph, Icons.folder_outlined);
      expect(row.checkRowShape, isTrue);
      expect(row.showChevron, isFalse);
      expect(row.onTap, isNull);
      expect(row.trailingButton!.tooltip, 'Stop sharing');
      expect(
        tester.getSize(find.byTooltip('Stop sharing').first),
        const Size.square(FormMetrics.trailingButtonSize),
      );
      expect(find.text('Share a folder'), findsOneWidget);
      expect(
        tester.getRect(add()).top,
        greaterThan(tester.getRect(unshare('trips')).top),
      );
    });

    testWidgets('the ✕ un-shares at once: the row leaves, the snackbar says '
        'so, and Undo writes it back', (tester) async {
      await openMine(tester);

      await tester.tap(unshare('lisbon'));
      await settle(tester);

      expect(service.folderShares, [('lisbon', false)]);
      expect(find.text('Lisbon'), findsNothing);
      expect(find.text('No longer shared: Lisbon'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(service.undone.single.unsharedFolders, [
        const ShareFolderRef(id: 'lisbon', name: 'Lisbon'),
      ]);
      expect(find.text('Lisbon'), findsOneWidget);
    });

    testWidgets('a ✕ whose write fails brings the row back and says '
        'shareChangeFailed over the sheet', (tester) async {
      await openMine(tester);
      final hold = service.hold = Completer<void>();

      await tester.tap(unshare('lisbon'));
      await settle(tester);
      expect(find.text('Lisbon'), findsNothing);
      hold.completeError(StateError('disk'));
      await settle(tester);

      expect(find.text('Lisbon'), findsOneWidget);
      expect(find.text(en.shareChangeFailed).hitTestable(), findsOneWidget);
    });

    testWidgets('a ✕ whose write fails after the sheet was dismissed says '
        'shareChangeFailed on the app\'s messenger, once', (tester) async {
      await openMine(tester);
      final hold = service.hold = Completer<void>();
      await tester.tap(unshare('lisbon'));
      await settle(tester);
      await tester.tap(sheetClose());
      await tester.pumpAndSettle();

      hold.completeError(StateError('disk'));
      await settle(tester);

      expect(find.byType(MySharedFoldersSheet), findsNothing);
      expect(
        find.widgetWithText(SnackBar, en.shareChangeFailed),
        findsOneWidget,
      );
    });

    testWidgets('a ✕ refused after the sheet was dismissed says why on the '
        'app\'s messenger', (tester) async {
      await openMine(tester);
      final hold = service.hold = Completer<void>();
      await tester.tap(unshare('lisbon'));
      await settle(tester);
      await tester.tap(unshare('trips'));
      await settle(tester);
      await tester.tap(sheetClose());
      await tester.pumpAndSettle();

      service.emit(ShareNotSyncing(audienceOf('Maria')));
      hold.complete();
      await settle(tester);

      expect(service.folderShares, [('lisbon', false)]);
      expect(find.widgetWithText(SnackBar, en.shareNeedsSync), findsOneWidget);
    });

    testWidgets('a row comes back on Undo only once the undo was written', (
      tester,
    ) async {
      await openMine(tester);
      await tester.tap(unshare('lisbon'));
      await settle(tester);
      final hold = service.hold = Completer<void>();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(service.undone, hasLength(1));
      expect(find.text('Lisbon'), findsNothing);

      hold.complete();
      await settle(tester);
      expect(find.text('Lisbon'), findsOneWidget);
    });

    testWidgets('an Undo that fails leaves the row out and says '
        'shareChangeFailed over the sheet', (tester) async {
      await openMine(tester);
      await tester.tap(unshare('lisbon'));
      await settle(tester);
      final hold = service.hold = Completer<void>();

      await tester.tap(find.text('Undo'));
      await settle(tester);
      hold.completeError(StateError('disk'));
      await settle(tester);

      expect(find.text('Lisbon'), findsNothing);
      expect(find.text(en.shareChangeFailed).hitTestable(), findsOneWidget);
    });

    testWidgets('an Undo tapped after the sheet and the page\'s bloc have '
        'closed writes through the service', (tester) async {
      await openMine(tester);
      await tester.tap(unshare('lisbon'));
      await settle(tester);
      await tester.tap(sheetClose());
      await tester.pumpAndSettle();
      await tester.runAsync(bloc.close);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(service.undone.single.unsharedFolders.single.id, 'lisbon');
    });

    testWidgets('an Undo tapped after a database switch writes nothing', (
      tester,
    ) async {
      await openMine(tester);
      await tester.tap(unshare('lisbon'));
      await settle(tester);
      DatabaseLifecycle.notifyDatabaseSwitching();

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(service.undone, isEmpty);
      expect(find.text(en.shareChangeFailed), findsNothing);
    });

    testWidgets('"Share a folder" opens the picker saying who it goes to; '
        'the pick shares, the new row appears, and the bar offers Undo', (
      tester,
    ) async {
      await openMine(tester);
      const work = ShareFolderRef(id: 'pick', name: 'Work');
      service.nextChange = const ShareChange(sharedFolders: [work]);
      service.shareOverview = const ShareOverview(
        folders: [
          lisbon,
          trips,
          MySharedFolder(
            id: 'pick',
            name: 'Work',
            parentName: null,
            noteCount: 0,
          ),
        ],
      );

      await tester.tap(add());
      await settle(tester);

      expect(pickerLabels, ['Maria'], reason: 'the picker names who');
      expect(service.folderShares, [('pick', true)]);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Sharing Work with Maria'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(service.undone.single.sharedFolders, [work]);
    });

    testWidgets('a pick over a folder shared on its own says the inner one is '
        'now shared through it', (tester) async {
      await openMine(tester);
      service.nextChange = const ShareChange(
        sharedFolders: [ShareFolderRef(id: 'pick', name: 'Travel')],
        coveredFolders: [ShareFolderRef(id: 'lisbon', name: 'Lisbon')],
      );

      await tester.tap(add());
      await settle(tester);

      expect(find.text('Lisbon is now shared through Travel'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('a pick already shared writes nothing and says so, with no '
        'Undo', (tester) async {
      picked = 'lisbon';
      await openMine(tester);

      await tester.tap(add());
      await settle(tester);

      expect(service.folderShares, [('lisbon', true)]);
      expect(find.text('Lisbon is already shared'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a cancelled pick writes nothing; a refused one says why', (
      tester,
    ) async {
      picked = null;
      await openMine(tester);
      await tester.tap(add());
      await settle(tester);
      expect(service.folderShares, isEmpty);

      picked = 'pick';
      service.emit(ShareNotSyncing(audienceOf('Maria')));
      await settle(tester);
      await tester.tap(add());
      await settle(tester);

      expect(service.folderShares, isEmpty);
      expect(find.text('Turn on sync to share'), findsOneWidget);
    });

    testWidgets('empty, it says one line, "Share a folder" under it', (
      tester,
    ) async {
      service.shareOverview = const ShareOverview();
      await openMine(tester);

      expect(find.text('No folder is shared yet.'), findsOneWidget);
      expect(find.byType(FormPickerRow), findsNothing);
      expect(
        tester.getRect(add()).top,
        greaterThan(tester.getRect(find.text('No folder is shared yet.')).top),
      );
    });

    /// The picker opened while the list is still sliding in: the list
    /// reaches its place under the picker, whose barrier blocks its
    /// semantics, and a ✕ that only moved would keep its old transform.
    testWidgets('a ✕ is reported where it is painted after "Share a folder" '
        'opened the picker while the list was still sliding in', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openMine(
        tester,
        settled: false,
        pickFolder: (context, _) => showDialog<String>(
          context: context,
          builder: (_) => const Dialog(child: Text('picker')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final stop = unshare('lisbon');
      final sliding = tester.getRect(stop);
      await tester.tapAt(tester.getCenter(find.text('Share a folder')));
      await tester.pumpAndSettle();
      expect(find.text('picker'), findsOneWidget);

      Navigator.of(tester.element(find.text('picker'))).pop();
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      final painted = tester.getRect(stop);
      expect(painted.top, lessThan(sliding.top));
      expect(
        semanticsGlobalRect(tester.getSemantics(stop), tester.view),
        painted,
      );
      expect(service.folderShares, isEmpty);
      handle.dispose();
    });
  });

  group('the partner\'s folders', () {
    testWidgets('read-only rows with their notes and a chevron, the name in '
        'the caption', (tester) async {
      await openTheirs(tester);

      expect(byId(SemanticsIds.sharedFoldersSheet), findsOneWidget);
      expect(find.text('Folders'), findsOneWidget);
      expect(find.text('From Maria'), findsOneWidget);
      final row = rowOf(tester, 'Recipes');
      expect(row.caption, '40 notes');
      expect(row.showChevron, isTrue);
      expect(row.trailingButton, isNull);
      expect(row.identifier, SemanticsIds.sharedFolderOpen('recipes'));
    });

    testWidgets('a tap leaves the sheet first, then opens the folder', (
      tester,
    ) async {
      await openTheirs(tester);

      await tester.tap(byId(SemanticsIds.sharedFolderOpen('recipes')));
      await tester.pumpAndSettle();

      expect(opened, [recipes]);
      expect(find.byType(PartnerSharedFoldersSheet), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('empty, it says None', (tester) async {
      service.shareOverview = const ShareOverview();
      await openTheirs(tester);

      expect(find.text('None'), findsOneWidget);
      expect(find.byType(FormPickerRow), findsNothing);
    });
  });

  for (final mine in const [true, false]) {
    final which = mine ? 'my' : 'the partner\'s';

    testWidgets('$which list meets the tap-target and labelled-target '
        'guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      if (mine) {
        await openMine(tester);
      } else {
        await openTheirs(tester);
      }

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final partner in const [
      'Maximilian-Alexander Mustermann',
      'maximilian.mustermann@example.com',
    ]) {
      testWidgets('$which list in German at 2.0 cuts nothing, with '
          '"$partner"', (tester) async {
        service.emit(ShareReady(audienceOf(partner)));
        if (mine) {
          await openMine(tester, locale: const Locale('de'), scale: 2.0);
        } else {
          await openTheirs(
            tester,
            locale: const Locale('de'),
            scale: 2.0,
            partner: partner,
          );
        }

        expect(tester.takeException(), isNull);
        expect(find.text('Ordner'), findsOneWidget);
        final paragraphs = [
          for (final row in tester.widgetList<FormPickerRow>(
            find.byType(FormPickerRow),
          )) ...[row.label, row.caption!],
          if (!mine) 'Von $partner',
          if (mine) 'Einen Ordner teilen',
        ];
        expect(paragraphs, isNotEmpty);
        for (final text in paragraphs) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(text),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: text);
        }
        if (mine) {
          await tester.tap(add());
          await settle(tester);
          expect(pickerLabels, [partner]);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
