import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_name_index.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/widgets/folder_picker_dialog.dart';
import 'package:anta/widgets/form_rows.dart' show FormCaptionSlot;

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';

/// The move picker opened from a note whose folder is a tombstone, with that
/// folder among the recent destinations: a tombstone a pull brought without
/// its data is stored under its id as its name, and neither the breadcrumb
/// nor the recents row may show it.
void main() {
  late AppDatabase db;
  late RecentDestinationsService recents;
  late String liveName;
  late String liveId;
  late String ghostId;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    db = await openTestDatabase();
    final folders = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folders.initialize();
    GetIt.I.registerSingleton<FolderStorageService>(folders);
    GetIt.I.registerSingleton<FolderNameIndex>(
      FolderNameIndex(folderService: folders),
    );
    recents = RecentDestinationsService();
    GetIt.I.registerSingleton<RecentDestinationsService>(recents);

    final live = await db.folderDao.createFolder(name: 'Training');
    liveName = live.name;
    liveId = live.id;
    ghostId = (await db.folderDao.createFolder(name: 'Legs')).id;
    await db.customStatement(
      'UPDATE folders SET name = id, is_deleted = 1 WHERE id = ?',
      [ghostId],
    );
    recents.record(ghostId);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<void> openPicker(
    WidgetTester tester,
    String currentFolderId, {
    String? waitFor,
    FolderPickPurpose purpose = FolderPickPurpose.move,
    String? partnerName,
    Locale? locale,
    double scale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFolderPickerDialog(
              context,
              currentFolderId: currentFolderId,
              purpose: purpose,
              partnerName: partnerName,
              allowRoot: purpose == FolderPickPurpose.move,
            ),
            child: const Text('move'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('move'));
    final shown = find.text(waitFor ?? liveName);
    for (var i = 0; i < 100 && shown.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
    // The folder list loads after the crumbs.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  testWidgets('a tombstoned current or recent folder is never named', (
    tester,
  ) async {
    await openPicker(tester, ghostId);

    expect(find.text(liveName), findsOneWidget);
    expect(find.textContaining(ghostId), findsNothing);
  });

  testWidgets('opened inside a tombstoned chain, it opens at the nearest live '
      'folder and offers only that', (tester) async {
    // Training (live) > Block (a data-less tombstone, named by its id) > Legs
    // (tombstone), with a live Sibling still under Block while the folder
    // repair waits.
    final blockId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Block', parentId: liveId),
    ))!.id;
    final legsId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Legs', parentId: blockId),
    ))!.id;
    await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Sibling', parentId: blockId),
    );
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE folders SET name = id, is_deleted = 1 WHERE id = ?',
        [blockId],
      ),
    );
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE folders SET is_deleted = 1 WHERE id = ?',
        [legsId],
      ),
    );
    recents.clear();

    await openPicker(tester, legsId);

    expect(find.textContaining(blockId), findsNothing);
    expect(find.textContaining(blockId.toUpperCase()), findsNothing);
    expect(find.text('Sibling'), findsNothing);
    expect(find.text('Legs'), findsNothing);
    expect(
      find.text(l10n.subfoldersOf(liveName).toUpperCase()),
      findsOneWidget,
    );
    expect(find.text(l10n.moveToDestination(liveName)), findsOneWidget);
  });

  testWidgets('a chain of locally deleted folders is never named either', (
    tester,
  ) async {
    final winterId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Winter', parentId: liveId),
    ))!.id;
    final weekId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Week 1', parentId: winterId),
    ))!.id;
    await tester.runAsync(
      () => db.folderDao.softDeleteFolderWithDescendants(winterId),
    );
    recents.clear();

    await openPicker(tester, weekId);

    expect(find.textContaining('Winter'), findsNothing);
    expect(find.textContaining('Week 1'), findsNothing);
    expect(find.text(l10n.moveToDestination(liveName)), findsOneWidget);
  });

  testWidgets('the crumbs above a live folder stop at the first tombstone', (
    tester,
  ) async {
    // Training > Old (deleted here) > Current (live, the folder repair has
    // not re-filed it yet) > Gone (deleted).
    final oldId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Old', parentId: liveId),
    ))!.id;
    final currentId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Current', parentId: oldId),
    ))!.id;
    final goneId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Gone', parentId: currentId),
    ))!.id;
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE folders SET is_deleted = 1 WHERE id IN (?, ?)',
        [oldId, goneId],
      ),
    );
    recents.clear();

    await openPicker(tester, goneId, waitFor: 'Current');

    expect(find.text('Current'), findsOneWidget);
    expect(find.textContaining('Old'), findsNothing);
    expect(find.text(liveName), findsNothing);
    expect(find.textContaining('Gone'), findsNothing);
    expect(find.text(l10n.moveToDestination('Current')), findsOneWidget);
  });

  // Share surfaces §6.11, slice F spec F5: one picker, three purposes.
  group('what the pick is for', () {
    late String tripsId;

    setUp(() async {
      tripsId = (await db.folderDao.createFolder(name: 'Trips')).id;
      await db.folderDao.setSharedPair(tripsId, 'pair-1');
      final theirs = await db.folderDao.createFolder(name: 'Theirs');
      await db.customStatement(
        "UPDATE folders SET owner_id = 'maria' WHERE id = ?",
        [theirs.id],
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'maria');
      recents.record(theirs.id);
      GetIt.I<FolderStorageService>().invalidateCache();
    });

    FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
      find.byWidgetPredicate((w) => w is FilledButton),
    );

    testWidgets('move: today\'s words; the partner\'s folders nowhere — '
        'browse, recents, search', (tester) async {
      await openPicker(tester, '');

      expect(find.text(l10n.moveToTitle), findsOneWidget);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Theirs'), findsNothing);

      await tester.enterText(find.byType(TextField), 'The');
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Theirs'), findsNothing);
    });

    testWidgets('share: its title and button; a shared folder wears the sign '
        'and says so, and cannot be confirmed', (tester) async {
      await openPicker(
        tester,
        '',
        purpose: FolderPickPurpose.share,
        partnerName: 'Maria',
      );

      expect(find.text(l10n.shareAddFolder), findsOneWidget);
      expect(find.text(l10n.pickShareConfirm), findsOneWidget);
      expect(find.byIcon(Icons.group_rounded), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('Shared with Maria')),
        findsOneWidget,
      );

      await tester.tap(find.text('Trips'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(confirm(tester).onPressed, isNull);
      expect(find.text(l10n.pickShareAlready('Trips')), findsOneWidget);

      await tester.tap(find.text(l10n.rootFolder).first);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 5));
      }
      await tester.tap(find.text(liveName));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(confirm(tester).onPressed, isNotNull);
    });

    // Review 6 (B4): the search reads an index built once. A share act
    // writes the mark and drops the folder cache (`foldersChanged`, the
    // service's hook in `injection.dart`), which emits no folder change —
    // the search must still learn of it, both ways.
    testWidgets('share: a folder shared, then stopped, after the search index '
        'was built — the search refuses it, then offers it again', (
      tester,
    ) async {
      Future<void> search(String query) async {
        await tester.enterText(find.byType(TextField), '');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.enterText(find.byType(TextField), query);
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      Future<void> share(bool on) => tester.runAsync(() async {
        await db.folderDao.setSharedPair(liveId, on ? 'pair-1' : null);
        GetIt.I<FolderStorageService>().invalidateCache();
      });

      ListTile row() =>
          tester.widget<ListTile>(find.widgetWithText(ListTile, liveName));

      await openPicker(
        tester,
        '',
        purpose: FolderPickPurpose.share,
        partnerName: 'Maria',
      );
      await search('Train');
      expect(row().enabled, isTrue, reason: 'the index is built, unshared');

      await share(true);
      await search('Train');
      expect(row().enabled, isFalse);
      expect(find.text(l10n.shareFolderAlready(liveName)), findsOneWidget);

      await share(false);
      await search('Train');
      expect(row().enabled, isTrue);
      expect(find.text(l10n.shareFolderAlready(liveName)), findsNothing);
    });

    // Leg 10: the ids the device flows tap the picker by — no node added:
    // the search id lands on the text field's own node.
    testWidgets('its controls and rows carry their ids, once each', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openPicker(tester, '', partnerName: 'Maria');

      Finder id(String identifier) => find.bySemanticsIdentifier(identifier);
      for (final identifier in [
        SemanticsIds.folderPickerSearch,
        SemanticsIds.folderPickerConfirm,
        SemanticsIds.folderPickerCancel,
        SemanticsIds.folderPickerUp,
        SemanticsIds.folderPickerRow(tripsId),
        SemanticsIds.folderPickerRow(liveId),
      ]) {
        expect(id(identifier), findsOneWidget, reason: identifier);
      }
      bool isField() => tester
          .getSemantics(id(SemanticsIds.folderPickerSearch))
          .flagsCollection
          .isTextField;
      expect(
        isField(),
        isTrue,
        reason: 'the field\'s own node, not a node of its own',
      );
      // The row's one node: its label and its tap, with the id.
      final row = tester
          .getSemantics(id(SemanticsIds.folderPickerRow(liveId)))
          .getSemanticsData();
      expect(row.label, liveName);
      expect(row.hasAction(SemanticsAction.tap), isTrue);
      // A shared row's sign label stays on that same node.
      final shared = tester
          .getSemantics(id(SemanticsIds.folderPickerRow(tripsId)))
          .getSemanticsData();
      expect(shared.label, allOf(contains('Maria'), contains('Trips')));

      await tester.enterText(find.byType(TextField), 'Tri');
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(id(SemanticsIds.folderPickerRow(tripsId)), findsOneWidget);
      expect(isField(), isTrue, reason: 'with the clear button beside it');
      semantics.dispose();
    });

    testWidgets('copy: "Copy to my notes" as title and button', (tester) async {
      await openPicker(tester, '', purpose: FolderPickPurpose.copy);

      expect(find.text(l10n.sharedNoteCopy), findsOneWidget);
      expect(find.text(l10n.pickCopyConfirm), findsOneWidget);
      expect(find.text('Theirs'), findsNothing);
    });

    // Fix pass item 2: a recent destination is a move's history. Moves and
    // copies keep the chips — they are destinations, a shared one with the
    // sign — and the partner's are never among them; a share offers none,
    // since no road may confirm a folder already shared.
    Finder chip(String name) => find.widgetWithText(ActionChip, name);

    testWidgets('the recent chips: move and copy keep them, the shared one '
        'wearing the sign, never the partner\'s; share offers none', (
      tester,
    ) async {
      recents.record(tripsId);

      Future<void> close() async {
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
      }

      await openPicker(tester, '');
      expect(chip('Trips'), findsOneWidget);
      expect(chip('Theirs'), findsNothing);
      await close();

      await openPicker(
        tester,
        '',
        purpose: FolderPickPurpose.copy,
        partnerName: 'Maria',
      );
      expect(chip('Trips'), findsOneWidget);
      expect(
        find.descendant(
          of: chip('Trips'),
          matching: find.byIcon(Icons.group_rounded),
        ),
        findsOneWidget,
      );
      await close();

      await openPicker(
        tester,
        '',
        purpose: FolderPickPurpose.share,
        partnerName: 'Maria',
      );
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text(l10n.recentDestinations), findsNothing);
    });

    // Review 11, 12, 15: German at 2.0 on a 360 × 780 phone, with a long
    // folder name — every purpose keeps its button within two lines and a
    // whole folder row in view; the share pick's reason is said in full and
    // its slot never moves the list's end.
    for (final purpose in FolderPickPurpose.values) {
      testWidgets('${purpose.name} at German 2.0: the button within two '
          'lines, a whole row in view', (tester) async {
        // Real glyphs: the test font's square boxes are wider than Roboto,
        // and what is measured here is what a phone draws.
        await tester.runAsync(loadGoldenFonts);
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        const long = 'Reisen nach Portugal und Spanien im Sommer';
        await db.folderDao.createFolder(name: long);
        GetIt.I<FolderStorageService>().invalidateCache();

        await openPicker(
          tester,
          '',
          waitFor: long,
          purpose: purpose,
          partnerName: 'maximilian.mustermann@example.com',
          locale: const Locale('de'),
          scale: 2.0,
        );

        expect(tester.takeException(), isNull);
        final button = tester.getSize(
          find.byWidgetPredicate((w) => w is FilledButton),
        );
        // Two lines of the button's 14 sp label at 2.0, with its padding.
        expect(button.height, lessThanOrEqualTo(2 * 14 * 2.0 * 1.43 + 24));
        final list = tester.getRect(find.byType(ListView).last);
        final whole = [
          for (final tile in find.byType(ListTile).evaluate())
            tester.getRect(find.byWidget(tile.widget)),
        ].where((row) => row.top >= list.top && row.bottom <= list.bottom);
        expect(whole, isNotEmpty, reason: 'a whole folder row in view');

        if (purpose != FolderPickPurpose.share) return;
        // Into the shared Trips and back: the reason in full, the list's
        // end where it was.
        await tester.enterText(find.byType(TextField), 'x');
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byTooltip('Suche löschen'), findsOneWidget);
        await tester.tap(find.byTooltip('Suche löschen'));
        await tester.pump(const Duration(milliseconds: 200));
        // The reason's slot: where the browse area ends.
        Finder slot() => find.byType(FormCaptionSlot);
        final before = tester.getRect(slot()).top;
        await tester.tap(find.text('Trips'));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 5));
        }
        final reason = find.text('Schon geteilt: Trips');
        expect(reason, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(reason).didExceedMaxLines,
          isFalse,
          reason: 'a short name: said whole within the slot\'s lines',
        );
        expect(
          tester.getRect(slot()).top,
          moreOrLessEquals(before, epsilon: 0.5),
        );
      });
    }

    // Review 7 (B5): the share pick's reason changes the text, never the
    // geometry — one height for the slot whatever the folder's name wraps
    // to, at the root, and while a search is typed.
    testWidgets('share at German 2.0: the reason\'s slot is one height — a '
        'short name, a long one, the root, a search; the why leads, and a '
        'search empties the slot', (tester) async {
      await tester.runAsync(loadGoldenFonts);
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final de = AppLocalizationsDe();
      const long = 'Reisen nach Portugal und Spanien im Sommer';
      final longId = (await tester.runAsync(() async {
        final created = await db.folderDao.createFolder(name: long);
        await db.folderDao.setSharedPair(created.id, 'pair-1');
        // A child in each, so every state draws a list whose end is
        // where the reason's slot begins.
        await db.folderDao.createFolder(name: 'Lissabon', parentId: created.id);
        await db.folderDao.createFolder(name: 'Porto', parentId: tripsId);
        GetIt.I<FolderStorageService>().invalidateCache();
        return created.id;
      }))!;
      recents.clear();

      double listEnd() => tester.getRect(find.byType(ListView).last).bottom;

      /// The picker opened inside [id] — where a pick from a row of that
      /// folder starts.
      Future<double> openedIn(String id, String waitFor) async {
        await openPicker(
          tester,
          id,
          waitFor: waitFor,
          purpose: FolderPickPurpose.share,
          partnerName: 'Maria',
          locale: const Locale('de'),
          scale: 2.0,
        );
        return listEnd();
      }

      Future<void> close() async {
        await tester.tap(find.text(de.cancel));
        await tester.pumpAndSettle();
      }

      final atRoot = await openedIn('', long);
      await close();

      expect(await openedIn(tripsId, 'Porto'), moreOrLessEquals(atRoot));
      expect(find.text(de.pickShareAlready('Trips')), findsOneWidget);
      await close();

      expect(await openedIn(longId, 'Lissabon'), moreOrLessEquals(atRoot));
      // Review 2, finding 3: the slot's two lines cut a long name's end,
      // so the why leads and the name comes after it.
      final reason = find.text(de.pickShareAlready(long));
      expect(reason, findsOneWidget);
      final why = de.pickShareAlready(long).replaceAll(long, '').trim();
      final paragraph = tester.renderObject<RenderParagraph>(reason);
      expect(
        paragraph.text.toPlainText(),
        startsWith(why),
        reason: 'the why is the part the cut keeps',
      );
      final slotHeight = tester.getSize(find.byType(FormCaptionSlot)).height;

      await tester.enterText(find.byType(TextField), 'Lis');
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Lissabon'), findsOneWidget, reason: 'searching');
      expect(listEnd(), moreOrLessEquals(atRoot, epsilon: 0.5));
      // Finding 8: the crumbs the reason speaks of are hidden while
      // searching, and each result says its own — the slot keeps its
      // height and says nothing.
      expect(
        tester.getSize(find.byType(FormCaptionSlot)).height,
        moreOrLessEquals(slotHeight),
      );
      expect(
        find.descendant(
          of: find.byType(FormCaptionSlot),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && (widget.data ?? '').trim().isNotEmpty,
          ),
        ),
        findsNothing,
      );
      expect(reason, findsNothing);
      expect(tester.takeException(), isNull);
    });

    // Review 2, finding 4: at German 2.0 the title took three headline lines
    // and left the share pick's list 107 dp — a row and a half. Its scale
    // stops where every kit dialog's title stops, so the list keeps rows.
    for (final purpose in FolderPickPurpose.values) {
      testWidgets('${purpose.name} at German 2.0: the title leaves the list '
          'three whole rows', (tester) async {
        await tester.runAsync(loadGoldenFonts);
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.runAsync(() async {
          for (final name in ['Porto', 'Madrid', 'Sevilla']) {
            await db.folderDao.createFolder(name: name);
          }
        });
        GetIt.I<FolderStorageService>().invalidateCache();
        recents.clear();

        await openPicker(
          tester,
          '',
          waitFor: 'Sevilla',
          purpose: purpose,
          partnerName: 'Maria',
          locale: const Locale('de'),
          scale: 2.0,
        );

        expect(tester.takeException(), isNull);
        final list = tester.getRect(find.byType(ListView).last);
        final whole = [
          for (final tile in find.byType(ListTile).evaluate())
            tester.getRect(find.byWidget(tile.widget)),
        ].where((row) => row.top >= list.top && row.bottom <= list.bottom);
        expect(
          whole.length,
          greaterThanOrEqualTo(3),
          reason: 'the list is ${list.height} dp',
        );
      });
    }

    // Leg 2's F: the address bar four levels deep, every name long, at the
    // same German 2.0 on the same phone — the crumbs must not push the
    // button or the bar out of their room.
    for (final purpose in FolderPickPurpose.values) {
      testWidgets('${purpose.name} at German 2.0, four long crumbs deep: no '
          'overflow, the button within two lines', (tester) async {
        await tester.runAsync(loadGoldenFonts);
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        const names = [
          'Krafttraining und Ausdauerprogramme',
          'Wochenpläne für die Wintervorbereitung',
          'Oberkörperübungen mit Langhantel',
          'Aufzeichnungen der Trainingseinheiten',
        ];
        String? parentId;
        for (final name in names) {
          final created = await tester.runAsync(
            () => db.folderDao.createFolder(name: name, parentId: parentId),
          );
          parentId = created!.id;
        }
        GetIt.I<FolderStorageService>().invalidateCache();
        recents.clear();

        await openPicker(
          tester,
          parentId!,
          waitFor: names.last,
          purpose: purpose,
          partnerName: 'maximilian.mustermann@example.com',
          locale: const Locale('de'),
          scale: 2.0,
        );

        expect(tester.takeException(), isNull);
        expect(find.text(names.last), findsWidgets);
        final button = tester.getSize(
          find.byWidgetPredicate((w) => w is FilledButton),
        );
        // Two lines of the button's 14 sp label at 2.0, with its padding.
        expect(button.height, lessThanOrEqualTo(2 * 14 * 2.0 * 1.43 + 24));
      });
    }
  });
}
