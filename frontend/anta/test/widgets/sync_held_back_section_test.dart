import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../services/pairing_support.dart';
import 'support/layout_errors.dart';
import 'support/sync_section_robot.dart';

/// Takes any state the suite shows it; the page's side is what is pinned.
class _ScriptedSyncBloc extends SyncBloc {
  _ScriptedSyncBloc({required super.authService});

  void show(SyncState state) => emit(state);

  @override
  bool get engineStatusSeen => true;
}

const _binding = SyncBinding(
  spaceId: 'space-1',
  ownerUid: 'uid-a',
  accountUid: 'uid-a',
);

const _legDay = SyncHeldItem(
  table: 'notes',
  rowKey: 'n1',
  kind: SyncHeldKind.note,
  name: 'Leg day — week 12',
  reason: SyncHeldReason.refused,
);

/// A deleted note, an event labelled by its kind, and a folder.
const _three = [
  SyncHeldItem(
    table: 'notes',
    rowKey: 'n2',
    kind: SyncHeldKind.note,
    name:
        'Groceries and the long list of things to buy before the trip to '
        'the mountains next weekend',
    deleted: true,
    reason: SyncHeldReason.refused,
  ),
  SyncHeldItem(
    table: 'folders',
    rowKey: 'f1',
    kind: SyncHeldKind.folder,
    name: 'Training',
    reason: SyncHeldReason.awaitingText,
  ),
  SyncHeldItem(
    table: 'calendar_events',
    rowKey: 'e1',
    kind: SyncHeldKind.event,
    reason: SyncHeldReason.unreadable,
  ),
];

final _many = [
  for (var i = 0; i < 120; i++)
    SyncHeldItem(
      table: 'notes',
      rowKey: 'n$i',
      kind: SyncHeldKind.note,
      name: 'Note ${i.toString().padLeft(3, '0')}',
      reason: SyncHeldReason.unencodable,
    ),
];

/// The Sharing page's held-back section (scalability record S7, the D14
/// promise): each held-back row by name with its reason, last on the page,
/// capped with one row that counts the rest; nothing above it moves when it
/// comes or goes.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakePairingGateway gateway;
  _ScriptedSyncBloc? syncBloc;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    syncBloc = null;
    db = await openTestDatabase();
    final auth = FakeAuthService(user: userA);
    gateway = FakePairingGateway();
    await PairingService.forTesting(
      auth: auth,
      gateway: gateway,
      settings: SettingsService.forTesting(db),
    );
    GetIt.I.registerFactory<SyncBloc>(
      () => syncBloc = _ScriptedSyncBloc(authService: auth),
    );
    GetIt.I.registerFactory<PairingBloc>(
      () => PairingBloc(authService: auth, gateway: gateway),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    PairingService.reset();
    await gateway.dispose();
    await db.close();
  });

  SyncSignedIn held(List<SyncHeldItem> items, {int? count}) => SyncSignedIn(
    userA,
    status: SyncStatus(
      binding: _binding,
      parkedCount: count ?? items.length,
      heldBack: items,
    ),
  );

  Future<SyncSectionRobot> open(
    WidgetTester tester,
    SyncState state, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
  }) async {
    final robot = SyncSectionRobot(tester);
    await robot.pumpPage(
      size: size,
      locale: locale,
      textScale: textScale,
      dark: dark,
    );
    syncBloc!.show(state);
    await robot.settle();
    return robot;
  }

  Future<void> show(SyncSectionRobot robot, SyncState state) async {
    syncBloc!.show(state);
    await robot.settle();
  }

  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  String rowId(int index) => SemanticsIds.sharingHeldBackRow(index);

  /// The rows the list draws, by their ids.
  Finder listedRows() => find.bySemanticsIdentifier(
    RegExp(r'^sharing-held-back-\d+$'),
    skipOffstage: false,
  );

  testWidgets('nothing held back draws no section', (tester) async {
    final robot = await open(tester, held(const []));

    expect(robot.byId(SemanticsIds.sharingSyncStatus), findsOneWidget);
    expect(
      find.textContaining(RegExp('HELD BACK'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(
        RegExp('^sharing-held-back-'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    await close(tester);
  });

  testWidgets('unbound, nothing is listed even with rows held', (tester) async {
    await open(
      tester,
      SyncSignedIn(
        userA,
        status: const SyncStatus(parkedCount: 1, heldBack: [_legDay]),
      ),
    );

    expect(listedRows(), findsNothing);
    await close(tester);
  });

  testWidgets('sync becoming unavailable forgets the rows seen', (
    tester,
  ) async {
    final robot = await open(tester, held(_three));
    expect(listedRows(), findsNWidgets(3));

    await show(robot, const SyncUnavailable());
    expect(listedRows(), findsNothing);
    await show(robot, held(const [_legDay]));

    expect(listedRows(), findsOneWidget);
    await robot.reveal(rowId(0));
    expect(robot.shows(rowId(0), _legDay.name!), isTrue);
    await close(tester);
  });

  testWidgets('one row: its name, its reason, under a header that counts '
      'it and a line that says what to do, after Pairing', (tester) async {
    final robot = await open(tester, held(const [_legDay]));
    await robot.reveal(rowId(0));

    expect(robot.shows(rowId(0), _legDay.name!), isTrue);
    expect(robot.shows(rowId(0), l10n.syncHeldBackRefused), isTrue);
    expect(find.text(l10n.syncParkedCount(1).toUpperCase()), findsOneWidget);
    expect(find.text(l10n.syncHeldBackIntro), findsOneWidget);
    expect(
      tester.getRect(find.text(l10n.syncHeldBackIntro)).bottom,
      lessThanOrEqualTo(tester.getRect(robot.byId(rowId(0))).top),
    );
    expect(
      tester.getRect(robot.byId(rowId(0))).top,
      greaterThan(tester.getRect(robot.byId(SemanticsIds.sharingPair)).top),
    );
    final tile = robot.tile(rowId(0));
    expect(tile.onTap, isNull);
    expect(tile.leading, isA<Icon>());
    expect((tile.leading! as Icon).icon, Icons.note_outlined);
    await close(tester);
  });

  test('the intro quotes the Sync now row as each language spells it', () {
    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      final local = lookupAppLocalizations(locale);
      expect(local.syncHeldBackIntro, contains(local.syncNow));
    }
  });

  testWidgets('a deleted note says so before its reason, another kind is '
      'labelled by its kind, each with its glyph', (tester) async {
    final robot = await open(tester, held(_three));
    for (var index = 0; index < _three.length; index++) {
      await robot.reveal(rowId(index));
    }

    expect(
      robot.shows(
        rowId(0),
        l10n.syncHeldBackDeleted('note', l10n.syncHeldBackRefused),
      ),
      isTrue,
    );
    expect(
      l10n.syncHeldBackDeleted('note', l10n.syncHeldBackRefused),
      'Deleted · ${l10n.syncHeldBackRefused}',
    );
    expect(robot.shows(rowId(1), 'Training'), isTrue);
    expect(robot.shows(rowId(1), l10n.syncHeldBackAwaitingText), isTrue);
    expect(robot.shows(rowId(2), l10n.syncHeldBackKind('event')), isTrue);
    expect(robot.shows(rowId(2), l10n.syncHeldBackUnreadable), isTrue);
    expect(
      [
        for (var index = 0; index < _three.length; index++)
          (robot.tile(rowId(index)).leading! as Icon).icon,
      ],
      [Icons.note_outlined, Icons.folder_outlined, Icons.event_outlined],
    );
    // A long name stops at two lines.
    final name = tester.renderObject<RenderParagraph>(
      find.text(_three[0].name!),
    );
    expect(name.maxLines, 2);
    expect(name.didExceedMaxLines, isTrue);
    await close(tester);
  });

  testWidgets('120 rows list the first 20 and one row for the other 100', (
    tester,
  ) async {
    final robot = await open(tester, held(_many));
    await robot.reveal(SemanticsIds.sharingHeldBackMore);

    expect(listedRows(), findsNWidgets(20));
    expect(robot.shows(rowId(19), _many[19].name!), isTrue);
    expect(
      find.bySemanticsIdentifier(rowId(20), skipOffstage: false),
      findsNothing,
    );
    const more = 'And 100 more still held back';
    expect(robot.shows(SemanticsIds.sharingHeldBackMore, more), true);
    expect(robot.tile(SemanticsIds.sharingHeldBackMore).onTap, isNull);
    expect(find.text(l10n.syncParkedCount(120).toUpperCase()), findsOneWidget);
    expect(l10n.syncHeldBackMoreHeld(1), 'And 1 more still held back');
    // The count lines up with the names above it.
    expect(
      robot.drawnTextRect(SemanticsIds.sharingHeldBackMore, more).left,
      robot.drawnTextRect(rowId(19), _many[19].name!).left,
    );
    await close(tester);
  });

  testWidgets('the "more" row counts the unlisted rows still held, and says '
      'they were synced once none is', (tester) async {
    final robot = await open(tester, held(_many.take(22).toList()));
    await robot.reveal(SemanticsIds.sharingHeldBackMore);
    bool more(String text) =>
        robot.shows(SemanticsIds.sharingHeldBackMore, text);

    expect(more(l10n.syncHeldBackMoreHeld(2)), isTrue);

    await show(robot, held(_many.take(21).toList()));
    expect(more(l10n.syncHeldBackMoreHeld(1)), isTrue);

    await show(robot, held(_many.take(20).toList()));
    expect(more(l10n.syncHeldBackMoreSynced(2)), isTrue);
    expect(l10n.syncHeldBackMoreSynced(2), 'The other 2 were synced');
    expect(l10n.syncHeldBackMoreSynced(1), 'The other one was synced');
    expect(find.text(l10n.syncParkedCount(20).toUpperCase()), findsOneWidget);
    await close(tester);
  });

  test('Romanian agrees "synced" with the kind', () {
    final ro = lookupAppLocalizations(const Locale('ro'));
    for (final kind in const ['note', 'category', 'view', 'vocabulary']) {
      expect(ro.syncHeldBackSynced(kind), 'Sincronizată', reason: kind);
    }
    for (final kind in const ['folder', 'event', 'counter', 'other']) {
      expect(ro.syncHeldBackSynced(kind), 'Sincronizat', reason: kind);
    }
  });

  testWidgets('every kind has its glyph; a note or folder with no copy here '
      'is labelled by its kind, an empty title reads untitled', (tester) async {
    const kinds = [
      SyncHeldKind.note,
      SyncHeldKind.folder,
      SyncHeldKind.event,
      SyncHeldKind.counter,
      SyncHeldKind.vocabulary,
      SyncHeldKind.other,
    ];
    final robot = await open(
      tester,
      held([
        for (final (index, kind) in kinds.indexed)
          SyncHeldItem(
            table: kind.name,
            rowKey: 'k$index',
            kind: kind,
            reason: SyncHeldReason.unreadable,
          ),
        const SyncHeldItem(
          table: 'notes',
          rowKey: 'untitled',
          kind: SyncHeldKind.note,
          name: '',
          reason: SyncHeldReason.refused,
        ),
      ]),
    );
    for (var index = 0; index <= kinds.length; index++) {
      await robot.reveal(rowId(index));
    }

    expect(
      [
        for (var index = 0; index < kinds.length; index++)
          (robot.tile(rowId(index)).leading! as Icon).icon,
      ],
      [
        Icons.note_outlined,
        Icons.folder_outlined,
        Icons.event_outlined,
        Icons.pin_rounded,
        Icons.format_list_bulleted_rounded,
        Icons.sync_rounded,
      ],
    );
    for (final (index, kind) in kinds.indexed) {
      expect(robot.shows(rowId(index), l10n.syncHeldBackKind(kind.name)), true);
    }
    expect(l10n.syncHeldBackKind('note'), 'A note');
    expect(l10n.syncHeldBackKind('folder'), 'A folder');
    expect(robot.shows(rowId(kinds.length), l10n.untitledNote), isTrue);
    await close(tester);
  });

  test('Romanian agrees "deleted" with the kind', () {
    final ro = lookupAppLocalizations(const Locale('ro'));
    final deleted = {
      for (final kind in const ['note', 'category', 'view', 'vocabulary'])
        kind: 'Ștearsă · x',
      for (final kind in const ['folder', 'event', 'counter', 'other'])
        kind: 'Șters · x',
    };
    for (final MapEntry(key: kind, value: line) in deleted.entries) {
      expect(ro.syncHeldBackDeleted(kind, 'x'), line, reason: kind);
    }
  });

  testWidgets('a row that goes through stays in place as synced under a '
      'check while the page is open; with none held the header and the '
      'intro say so in place; a page opened afresh lists only what is '
      'held', (tester) async {
    final robot = await open(
      tester,
      held(_three),
      size: const Size(360, 780),
      textScale: 2.0,
    );
    // Scrolled to the end of the list, where the user reads it: twice, since
    // the first jump lands on an estimate of the extent the unbuilt rows
    // still refine.
    Future<void> toEnd() async {
      for (var i = 0; i < 3; i++) {
        robot.listPosition.jumpTo(robot.listPosition.maxScrollExtent);
        await tester.pump();
      }
    }

    await toEnd();
    final pairing = find.text(
      l10n.pairingSection.toUpperCase(),
      skipOffstage: false,
    );
    final header = find.text(
      l10n.syncParkedCount(3).toUpperCase(),
      skipOffstage: false,
    );
    // The Pairing header's top in list coordinates — at 2.0 on a small
    // phone it lies past the built extent at the end of the list, so it is
    // walked to from the top as the sibling test does — then, back at the
    // end, the held-back header's screen top and every row's rect.
    Future<List<Object>> geometry(Finder header) async {
      final pairingTop = (await robot.listRect(
        pairing,
        () => tester.getRect(pairing),
      )).top;
      await toEnd();
      return [
        pairingTop,
        tester.getRect(header).top,
        for (var index = 0; index < _three.length; index++)
          tester.getRect(robot.byId(rowId(index))),
      ];
    }

    final before = await geometry(header);

    await show(robot, held([_three[1]]));

    expect(robot.shows(rowId(0), l10n.syncHeldBackSynced('note')), isTrue);
    expect(l10n.syncHeldBackSynced('note'), 'Synced');
    expect(robot.shows(rowId(0), _three[0].name!), isTrue);
    expect(
      robot.shows(
        rowId(0),
        l10n.syncHeldBackDeleted('note', l10n.syncHeldBackRefused),
      ),
      isFalse,
    );
    expect(robot.shows(rowId(1), l10n.syncHeldBackAwaitingText), isTrue);
    expect(robot.shows(rowId(2), l10n.syncHeldBackSynced('event')), isTrue);
    IconData? glyph(int index) =>
        (robot.tile(rowId(index)).leading! as Icon).icon;
    expect(
      [glyph(0), glyph(1), glyph(2)],
      [Icons.check_rounded, Icons.folder_outlined, Icons.check_rounded],
    );
    final live = find.text(l10n.syncParkedCount(1).toUpperCase());
    expect(live, findsOneWidget, reason: 'the header counts what is held');
    expect(await geometry(live), before);
    final title = tester.widget<RichText>(
      find.descendant(
        of: robot.byId(rowId(0)),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == _three[0].name,
        ),
      ),
    );
    final colors = Theme.of(tester.element(robot.byId(rowId(0)))).colorScheme;
    expect(title.text.style?.color, colors.onSurfaceVariant);

    // Back to its reason and its kind's glyph when it is held again.
    await show(robot, held(_three));
    expect(robot.shows(rowId(2), l10n.syncHeldBackUnreadable), isTrue);
    expect(glyph(2), Icons.event_outlined);

    await show(robot, held(const []));
    final done = find.text(l10n.syncHeldBackAllDone.toUpperCase());
    expect(done, findsOneWidget);
    expect(find.text(l10n.syncHeldBackIntroDone), findsOneWidget);
    expect(
      find.text(l10n.syncHeldBackIntro),
      findsOneWidget,
      reason: 'kept unseen, holding the intro as tall as it was',
    );
    expect(await geometry(done), before);
    await close(tester);
    await open(tester, held(const []));
    expect(listedRows(), findsNothing);
    expect(find.text(l10n.syncHeldBackIntro), findsNothing);
    await close(tester);
  });

  testWidgets('each row is one node reading its name then its reason, with '
      'no action; the "more" row one node; the header a level-2 '
      'heading', (tester) async {
    final semantics = tester.ensureSemantics();
    final robot = await open(tester, held(_many.take(21).toList()));
    await robot.reveal(SemanticsIds.sharingHeldBackMore);

    final row = tester.getSemantics(robot.byId(rowId(19)));
    expect(row.childrenCount, 0);
    final data = row.getSemanticsData();
    expect(data.label, 'Note 019\n${l10n.syncHeldBackUnencodable}');
    expect(data.flagsCollection.isButton, isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);

    final more = tester.getSemantics(
      robot.byId(SemanticsIds.sharingHeldBackMore),
    );
    expect(more.childrenCount, 0);
    expect(more.getSemanticsData().label, l10n.syncHeldBackMoreHeld(1));
    expect(more.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

    robot.listPosition.jumpTo(0);
    await tester.pump();
    await robot.reveal(rowId(0));
    final header = tester
        .getSemantics(find.bySemanticsLabel(l10n.syncParkedCount(21)))
        .getSemanticsData();
    expect(header.flagsCollection.isHeader, isTrue);
    expect(header.headingLevel, 2);

    // The intro is a node of its own, read after the heading.
    final intro = tester.getSemantics(find.text(l10n.syncHeldBackIntro));
    expect(intro.label, l10n.syncHeldBackIntro);
    final labels = <String>[];
    void walk(SemanticsNode node) {
      if (node.label.isNotEmpty) labels.add(node.label);
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        walk(child);
      }
    }

    walk(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    final heading = labels.indexOf(l10n.syncParkedCount(21));
    expect(heading, isNonNegative);
    expect(labels.indexOf(l10n.syncHeldBackIntro), heading + 1);
    semantics.dispose();
    await close(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('the section meets the contrast and tap-target guidelines, '
        '${dark ? 'dark' : 'light'}', (tester) async {
      final semantics = tester.ensureSemantics();
      final robot = await open(
        tester,
        held([..._three, ..._many.take(20)]),
        dark: dark,
      );
      await robot.reveal(SemanticsIds.sharingHeldBackMore);

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await close(tester);
    });
  }

  for (final size in const [Size(360, 780), Size(412, 915)]) {
    for (final dark in [false, true]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
          final cell =
              '${locale.languageCode} ${dark ? 'dark' : 'light'} $scale on '
              '${size.width.toInt()} × ${size.height.toInt()}';

          testWidgets('nothing above the list moves when it comes and goes, '
              'and it fits, $cell', (tester) async {
            final local = lookupAppLocalizations(locale);
            final details =
                '${local.syncNeverSynced} · ${local.syncParkedCount(3)}';
            final pairing = find.text(
              local.pairingSection.toUpperCase(),
              skipOffstage: false,
            );
            late SyncSectionRobot robot;
            final geometry = <bool, List<Rect>>{};
            final errors = await layoutErrorsDuring(() async {
              robot = await open(
                tester,
                held(const [], count: 3),
                size: size,
                locale: locale,
                textScale: scale,
                dark: dark,
              );
              for (final listed in [false, true]) {
                if (listed) await show(robot, held(_three));
                geometry[listed] = [
                  await robot.listRect(pairing, () => tester.getRect(pairing)),
                  await robot.listRect(
                    robot.byId(SemanticsIds.sharingSyncStatus),
                    () => robot.drawnTextRect(
                      SemanticsIds.sharingSyncStatus,
                      details,
                    ),
                  ),
                ];
              }
              for (final (index, item) in _three.indexed) {
                await robot.reveal(rowId(index));
                expect(
                  robot.shows(rowId(index), switch (item.kind) {
                    SyncHeldKind.event => local.syncHeldBackKind('event'),
                    _ => item.name!,
                  }),
                  isTrue,
                );
              }
              // The folder and the event went through and stay listed as
              // synced; the note n2 is among the 120 now held, so 18 of those
              // are listed and 102 counted.
              await show(robot, held(_many));
              robot.listPosition.jumpTo(0);
              await tester.pump();
              await robot.reveal(rowId(1));
              expect(
                robot.shows(rowId(1), local.syncHeldBackSynced('folder')),
                isTrue,
              );
              await robot.reveal(SemanticsIds.sharingHeldBackMore);
              expect(
                robot.shows(
                  SemanticsIds.sharingHeldBackMore,
                  local.syncHeldBackMoreHeld(102),
                ),
                isTrue,
              );
            });

            expect(errors.map((e) => e.exceptionAsString()), isEmpty);
            expect(tester.takeException(), isNull);
            expect(geometry[true], geometry[false]);
            await close(tester);
          });
        }
      }
    }
  }
}
