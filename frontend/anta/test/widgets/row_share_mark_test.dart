import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/folder.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/folder_row.dart';
import 'package:anta/widgets/note_row.dart';
import 'package:anta/widgets/search_surface.dart';
import 'package:anta/widgets/user_avatar.dart';

/// Whose a browser row is (`docs/cloud-share-surfaces-roadmap.md` §6.7,
/// §16.8): the sign before the count on a folder I share, the partner's face
/// before the count on their folder and at the start of the second line on
/// their note and search result, the words read first in every look — and,
/// for an account with no look, the tree every row has always built.
void main() {
  const maria = AppUser(uid: 'maria', displayName: 'Maria');
  const avatar = PartnerLook(partner: maria, name: 'Maria');
  const plain = PartnerLook(
    partner: maria,
    name: 'Maria',
    noteLook: ShareNoteLook.plain,
  );

  final created = DateTime(2026, 11, 1);

  Folder folder({
    String id = 'f1',
    bool fromPartner = false,
    FolderShare share = FolderShare.none,
  }) => Folder(
    id: id,
    name: 'Recipes',
    createdAt: created,
    fromPartner: fromPartner,
    share: share,
  );

  NoteMetadata note({bool fromPartner = false}) => NoteMetadata(
    id: 'n1',
    folderId: 'f1',
    title: 'Soup',
    preview: 'Leek, potato',
    contentLength: 12,
    chunkCount: 1,
    isCompressed: false,
    createdAt: created,
    updatedAt: created,
    fromPartner: fromPartner,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget row, {
    double scale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 360, child: row),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Widget folderRow(Folder folder, PartnerLook? look) => FolderRow(
    folder: folder,
    noteCount: 40,
    groupPosition: RowGroupPosition.single,
    onReturn: () {},
    partnerLook: look,
  );

  Widget noteRow(NoteMetadata note, PartnerLook? look) => NoteRow(
    metadata: note,
    folderId: note.folderId,
    groupPosition: RowGroupPosition.single,
    onReturn: () {},
    partnerLook: look,
  );

  Widget resultRow(NoteMetadata note, PartnerLook? look) => SearchResultRow(
    metadata: note,
    groupPosition: RowGroupPosition.single,
    path: const ['Kitchen', 'Recipes'],
    showDate: true,
    partnerLook: look,
  );

  String label(WidgetTester tester, String id) => tester
      .getSemantics(find.bySemanticsIdentifier(SemanticsIds.browserRow(id)))
      .label;

  final sign = find.byIcon(Icons.group_rounded);
  final face = find.byType(UserAvatar);

  /// The row's element tree as text: what "builds the tree it always
  /// built" compares.
  String tree(WidgetTester tester, Type type) =>
      tester.element(find.byType(type)).toStringDeep();

  group('no look — an account that shares nothing', () {
    testWidgets('a folder row builds the same tree, whatever its flags say', (
      tester,
    ) async {
      await pump(tester, folderRow(folder(), null));
      final today = tree(tester, FolderRow);
      final height = tester.getSize(find.byType(FolderRow)).height;

      await pump(tester, folderRow(folder(share: FolderShare.byMark), null));
      expect(tree(tester, FolderRow), today);
      await pump(tester, folderRow(folder(fromPartner: true), null));
      expect(tree(tester, FolderRow), today);
      expect(tester.getSize(find.byType(FolderRow)).height, height);
      expect(sign, findsNothing);
      expect(face, findsNothing);
    });

    testWidgets('a note row and a search result too', (tester) async {
      await pump(tester, noteRow(note(), null));
      final noteToday = tree(tester, NoteRow);
      await pump(tester, noteRow(note(fromPartner: true), null));
      expect(tree(tester, NoteRow), noteToday);

      await pump(tester, resultRow(note(), null));
      final resultToday = tree(tester, SearchResultRow);
      await pump(tester, resultRow(note(fromPartner: true), null));
      expect(tree(tester, SearchResultRow), resultToday);
      expect(face, findsNothing);
    });

    testWidgets('a look on a row that is nobody\'s changes nothing either', (
      tester,
    ) async {
      await pump(tester, folderRow(folder(), null));
      final today = tree(tester, FolderRow);
      await pump(tester, folderRow(folder(), avatar));
      expect(tree(tester, FolderRow), today);

      await pump(tester, noteRow(note(), null));
      final noteToday = tree(tester, NoteRow);
      await pump(tester, noteRow(note(), avatar));
      expect(tree(tester, NoteRow), noteToday);
    });
  });

  group('my folder, shared', () {
    testWidgets('wears the sign before its count and says "Shared with '
        'Maria" first', (tester) async {
      await pump(tester, folderRow(folder(share: FolderShare.byMark), avatar));

      expect(sign, findsOneWidget);
      expect(
        tester.getTopLeft(sign).dx,
        lessThan(tester.getTopLeft(find.text('40')).dx),
      );
      expect(label(tester, 'f1'), startsWith('Shared with Maria'));
    });

    testWidgets('a subfolder shared through the folder above wears it too', (
      tester,
    ) async {
      await pump(
        tester,
        folderRow(folder(share: const FolderShare.through('outer')), avatar),
      );
      expect(sign, findsOneWidget);
    });

    testWidgets('with the mark switched off: no sign, the words stay', (
      tester,
    ) async {
      const off = PartnerLook(partner: maria, name: 'Maria', markMine: false);
      await pump(tester, folderRow(folder(share: FolderShare.byMark), off));

      expect(sign, findsNothing);
      expect(label(tester, 'f1'), startsWith('Shared with Maria'));
    });

    testWidgets('with nobody to share with — a pair that ended — nothing', (
      tester,
    ) async {
      await pump(tester, folderRow(folder(), null));
      final today = tree(tester, FolderRow);
      await pump(
        tester,
        folderRow(
          folder(share: FolderShare.byMark),
          const PartnerLook(unpaired: true),
        ),
      );
      expect(tree(tester, FolderRow), today);
    });
  });

  group('the partner\'s rows', () {
    testWidgets('a folder wears the face before its count and says "From '
        'Maria" first', (tester) async {
      await pump(tester, folderRow(folder(fromPartner: true), avatar));

      expect(face, findsOneWidget);
      expect(sign, findsNothing, reason: 'one slot, never both');
      expect(
        tester.getTopLeft(face).dx,
        lessThan(tester.getTopLeft(find.text('40')).dx),
      );
      expect(label(tester, 'f1'), startsWith('From Maria'));
    });

    testWidgets('a note and a search result lead their second line with the '
        'face, and say "From Maria" first', (tester) async {
      await pump(tester, noteRow(note(fromPartner: true), avatar));
      expect(face, findsOneWidget);
      expect(
        tester.getTopLeft(face).dy,
        greaterThan(tester.getTopLeft(find.text('Soup')).dy),
        reason: 'on the second line, not beside the title',
      );
      expect(label(tester, 'n1'), startsWith('From Maria'));

      await pump(tester, resultRow(note(fromPartner: true), avatar));
      expect(face, findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^From Maria\nSoup')),
        findsOneWidget,
      );
    });

    testWidgets('Like mine: no face anywhere, the words in every row', (
      tester,
    ) async {
      await pump(tester, folderRow(folder(fromPartner: true), plain));
      expect(face, findsNothing);
      expect(label(tester, 'f1'), startsWith('From Maria'));

      await pump(tester, noteRow(note(fromPartner: true), plain));
      expect(face, findsNothing);
      expect(label(tester, 'n1'), startsWith('From Maria'));
    });

    testWidgets('an unread partner is "your partner" with the person glyph', (
      tester,
    ) async {
      await pump(
        tester,
        folderRow(folder(fromPartner: true), const PartnerLook()),
      );
      expect(face, findsOneWidget);
      expect(label(tester, 'f1'), startsWith('From your partner'));
    });
  });

  // Review 14: on a search result the face may cost the path, never the
  // date — the path gives way first.
  testWidgets('a partner\'s result at 2.0 keeps its whole date; the path '
      'gives way', (tester) async {
    await pump(
      tester,
      SearchResultRow(
        metadata: note(fromPartner: true),
        groupPosition: RowGroupPosition.single,
        path: const ['Kitchen', 'Recipes', 'Soups and stews of the winter'],
        showDate: true,
        partnerLook: avatar,
      ),
      scale: 2.0,
    );

    expect(tester.takeException(), isNull);
    final dated = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().endsWith('Nov 1'),
    );
    expect(dated, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(dated).didExceedMaxLines,
      isFalse,
    );
    final path = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Kitchen'),
    );
    expect(
      tester.renderObject<RenderParagraph>(path).didExceedMaxLines,
      isTrue,
    );
  });

  group('heights equal an unmarked row', () {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('at text scale $scale', (tester) async {
        Future<double> height(Widget row, Type type) async {
          await pump(tester, row, scale: scale);
          return tester.getSize(find.byType(type)).height;
        }

        final folderToday = await height(folderRow(folder(), null), FolderRow);
        expect(
          await height(
            folderRow(folder(share: FolderShare.byMark), avatar),
            FolderRow,
          ),
          folderToday,
        );
        expect(
          await height(folderRow(folder(fromPartner: true), avatar), FolderRow),
          folderToday,
        );

        final noteToday = await height(noteRow(note(), null), NoteRow);
        expect(
          await height(noteRow(note(fromPartner: true), avatar), NoteRow),
          noteToday,
        );

        final resultToday = await height(
          resultRow(note(), null),
          SearchResultRow,
        );
        expect(
          await height(
            resultRow(note(fromPartner: true), avatar),
            SearchResultRow,
          ),
          resultToday,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
