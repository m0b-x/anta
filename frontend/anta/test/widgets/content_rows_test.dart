import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/folder.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/folder_row.dart';
import 'package:anta/widgets/label_dot.dart';
import 'package:anta/widgets/label_swatch_strip.dart';
import 'package:anta/widgets/note_row.dart';
import 'package:anta/widgets/selection_action_bar.dart';

/// The row anatomy the navigation mock fixes, measured rather than eyeballed.
///
/// These rows only need a [Theme] and the localizations to build — the
/// database-backed paths (rename, delete, share) hang off the action sheet,
/// and the browser page suite exercises those where a real drift lives.
void main() {
  final l10n = AppLocalizationsEn();

  Folder folderNamed(String name, {ItemLabel label = ItemLabel.none}) =>
      Folder(
        id: 'f-$name',
        name: name,
        createdAt: DateTime(2026, 1, 1),
        label: label,
      );

  NoteMetadata noteNamed(
    String title, {
    String preview = '',
    ItemLabel label = ItemLabel.none,
  }) => NoteMetadata(
    id: 'n-$title',
    folderId: 'f',
    title: title,
    preview: preview,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime.now(),
    contentLength: preview.length,
    chunkCount: 1,
    isCompressed: false,
    label: label,
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: [child]),
        ),
      ),
    );
    await tester.pump();
  }

  group('the row shell', () {
    testWidgets('a middle row is not a PhysicalShape — only the ends of a '
        'group carry a clip path', (tester) async {
      await pump(
        tester,
        const Column(
          children: [
            ContentRowShell(
              position: RowGroupPosition.first,
              child: SizedBox(height: 48),
            ),
            ContentRowShell(
              position: RowGroupPosition.middle,
              child: SizedBox(height: 48, key: ValueKey('middle')),
            ),
            ContentRowShell(
              position: RowGroupPosition.last,
              child: SizedBox(height: 48),
            ),
          ],
        ),
      );

      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('middle')),
          matching: find.byType(PhysicalShape),
        ),
        findsNothing,
      );
      // The middle row still paints the group's surface and hosts ink.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('middle')),
          matching: find.byType(ColoredBox),
        ),
        findsWidgets,
      );
      expect(find.byType(PhysicalShape), findsWidgets);
    });

    testWidgets('the divider indent comes from the row, not the shell', (
      tester,
    ) async {
      await pump(
        tester,
        const Column(
          children: [
            ContentRowShell(
              position: RowGroupPosition.first,
              dividerIndent: RowMetrics.dividerIndentWithGlyph,
              child: SizedBox(height: 48),
            ),
            ContentRowShell(
              position: RowGroupPosition.last,
              child: SizedBox(height: 48),
            ),
          ],
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, 52);
      expect(divider.thickness, 1);
      expect(divider.height, 1);
    });

    testWidgets('the gap between two groups is 18, carried by the last row '
        'and not doubled by the label below it', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            const ContentRowShell(
              position: RowGroupPosition.single,
              child: SizedBox(height: 48, key: ValueKey('groupA')),
            ),
            ContentSectionHeader(label: l10n.notes),
            const ContentRowShell(
              position: RowGroupPosition.single,
              child: SizedBox(height: 48, key: ValueKey('groupB')),
            ),
          ],
        ),
      );

      final aBottom = tester
          .getBottomLeft(find.byKey(const ValueKey('groupA')))
          .dy;
      final labelTop = tester.getTopLeft(find.byType(ContentSectionHeader)).dy;
      expect(labelTop - aBottom, RowMetrics.groupGap);

      final labelBottom = tester
          .getBottomLeft(find.byType(ContentSectionHeader))
          .dy;
      final bTop = tester.getTopLeft(find.byKey(const ValueKey('groupB'))).dy;
      expect(bTop, labelBottom);
    });

    testWidgets('the section label is 11 / w500 / 0.88, inset 20 from the '
        'page edge', (tester) async {
      await pump(tester, ContentSectionHeader(label: l10n.folders));

      final text = tester.widget<Text>(find.text(l10n.folders.toUpperCase()));
      expect(text.style!.fontSize, 11);
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.style!.letterSpacing, 0.88);
      expect(
        text.style!.color,
        AppTheme.lightScheme.onSurfaceVariant,
      );
      expect(tester.getTopLeft(find.byType(Text)).dx, 20);
    });
  });

  group('a folder row', () {
    Future<void> pumpFolder(
      WidgetTester tester, {
      int? count,
      RowGroupPosition position = RowGroupPosition.single,
    }) {
      return pump(
        tester,
        FolderRow(
          folder: folderNamed('Training'),
          noteCount: count,
          groupPosition: position,
          onReturn: () {},
        ),
      );
    }

    testWidgets('is 48 tall, ends in a bare count and a chevron, and offers '
        'no per-row menu', (tester) async {
      await pumpFolder(tester, count: 23);

      expect(
        tester.getSize(find.byType(InkWell)).height,
        RowMetrics.singleLineMinHeight,
      );
      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.text('23'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      // No subtitle: the count is the trailing slot, not a second line.
      expect(find.text(l10n.noteCountLabel(23)), findsNothing);
    });

    testWidgets('wears the mock glyph, sizes and colour roles', (tester) async {
      await pumpFolder(tester, count: 4);
      final scheme = AppTheme.lightScheme;

      final glyph = tester.widget<Icon>(find.byIcon(Icons.folder_outlined));
      expect(glyph.size, RowMetrics.glyphSize);
      expect(glyph.color, scheme.primary);

      final name = tester.widget<Text>(find.text('Training'));
      expect(name.style!.fontSize, 15);
      expect(name.style!.fontWeight, FontWeight.w400);
      expect(name.style!.color, scheme.onSurface);

      final count = tester.widget<Text>(find.text('4'));
      expect(count.style!.fontSize, 14);
      expect(count.style!.color, scheme.outline);
      expect(count.style!.fontFeatures, const [FontFeature.tabularFigures()]);

      final chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
      expect(chevron.size, RowMetrics.chevronSize);
      expect(chevron.color, scheme.outline);
    });

    testWidgets('does not resize or reflow when the count lands', (
      tester,
    ) async {
      await pumpFolder(tester);
      final withoutCount = tester.getSize(find.byType(InkWell));
      final nameLeft = tester.getTopLeft(find.text('Training')).dx;
      final chevronLeft = tester.getTopLeft(find.byIcon(Icons.chevron_right)).dx;

      await pumpFolder(tester, count: 123);

      expect(tester.getSize(find.byType(InkWell)), withoutCount);
      expect(tester.getTopLeft(find.text('Training')).dx, nameLeft);
      expect(
        tester.getTopLeft(find.byIcon(Icons.chevron_right)).dx,
        chevronLeft,
      );
    });

    testWidgets('its divider starts past the glyph, at 52', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            FolderRow(
              folder: folderNamed('Training'),
              groupPosition: RowGroupPosition.first,
              onReturn: () {},
            ),
            FolderRow(
              folder: folderNamed('Money'),
              groupPosition: RowGroupPosition.last,
              onReturn: () {},
            ),
          ],
        ),
      );

      expect(tester.widget<Divider>(find.byType(Divider)).indent, 52);
    });
  });

  group('a note row', () {
    Future<void> pumpNote(
      WidgetTester tester, {
      bool showPreview = true,
      String preview = 'Progressive overload',
      RowGroupPosition position = RowGroupPosition.single,
    }) {
      return pump(
        tester,
        NoteRow(
          metadata: noteNamed('Training principles', preview: preview),
          folderId: 'f',
          groupPosition: position,
          showPreview: showPreview,
          onReturn: () {},
        ),
      );
    }

    testWidgets('is 62 tall, carries no leading glyph and no per-row menu', (
      tester,
    ) async {
      await pumpNote(tester);

      expect(
        tester.getSize(find.byType(InkWell)).height,
        RowMetrics.twoLineMinHeight,
      );
      expect(find.byIcon(Icons.description_outlined), findsNothing);
      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('its second line is the date in w500 onSurface then the '
        'preview in onSurfaceVariant', (tester) async {
      await pumpNote(tester);
      final scheme = AppTheme.lightScheme;

      final title = tester.widget<Text>(find.text('Training principles'));
      expect(title.style!.fontSize, 15);
      expect(title.style!.fontWeight, FontWeight.w500);

      final second = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan != null,
          description: 'the rich second line',
        ),
      );
      expect(second.style!.fontSize, 13);
      expect(second.style!.color, scheme.onSurfaceVariant);

      final spans = (second.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans, hasLength(2));
      expect(spans.first.text, l10n.today);
      expect(spans.first.style!.fontWeight, FontWeight.w500);
      expect(spans.first.style!.color, scheme.onSurface);
      expect(spans.last.text, ' · Progressive overload');
      expect(spans.last.style, isNull);
    });

    testWidgets('with the preview setting off only the date remains', (
      tester,
    ) async {
      await pumpNote(tester, showPreview: false);

      final second = tester.widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
      );
      final spans = (second.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans, hasLength(1));
      expect(spans.single.text, l10n.today);
    });

    testWidgets('its divider starts at the group edge, at 16', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            NoteRow(
              metadata: noteNamed('One'),
              folderId: 'f',
              groupPosition: RowGroupPosition.first,
              onReturn: () {},
            ),
            NoteRow(
              metadata: noteNamed('Two'),
              folderId: 'f',
              groupPosition: RowGroupPosition.last,
              onReturn: () {},
            ),
          ],
        ),
      );

      expect(tester.widget<Divider>(find.byType(Divider)).indent, 16);
    });
  });

  group('the selection action bar', () {
    testWidgets('sits on the row surface with a hairline and no elevation, '
        'at the create bar\'s own height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: SelectionActionBar(
              count: 2,
              onLabel: () {},
              onMove: () {},
              onShare: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SelectionActionBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
      expect(material.color, AppTheme.lightScheme.rowGroup);

      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(SelectionActionBar),
                matching: find.byType(Container),
              ),
            )
            .height,
        RowMetrics.bottomBarHeight,
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
      expect(icon.size, RowMetrics.bottomBarGlyphSize);
      expect(icon.color, AppTheme.lightScheme.error);
    });

    testWidgets('offers four actions, Label first, and fires onLabel', (
      tester,
    ) async {
      var labelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: SelectionActionBar(
              count: 2,
              onLabel: () => labelled++,
              onMove: () {},
              onShare: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final row = tester.widget<Row>(
        find
            .descendant(
              of: find.byType(SelectionActionBar),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(row.children, hasLength(4));
      expect(row.mainAxisAlignment, MainAxisAlignment.spaceEvenly);

      final labelX = tester.getCenter(find.byIcon(Icons.label_outline)).dx;
      final moveX = tester
          .getCenter(find.byIcon(Icons.drive_file_move_outline))
          .dx;
      expect(labelX, lessThan(moveX), reason: 'Label sits before Move');

      await tester.tap(find.byIcon(Icons.label_outline));
      await tester.pump();
      expect(labelled, 1);
    });

    testWidgets('a disabled bar does not fire onLabel', (tester) async {
      var labelled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: SelectionActionBar(
              count: 0,
              onLabel: () => labelled++,
              onMove: () {},
              onShare: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.label_outline));
      await tester.pump();
      expect(labelled, 0);
    });
  });

  group('the colour label dot', () {
    testWidgets('an unlabelled note row draws no dot at all', (tester) async {
      await pump(
        tester,
        NoteRow(
          metadata: noteNamed('Plain'),
          folderId: 'f',
          groupPosition: RowGroupPosition.single,
          onReturn: () {},
        ),
      );

      expect(find.byType(LabelDot), findsNothing);
    });

    testWidgets('a labelled note row ends in a 10dp dot, past the title', (
      tester,
    ) async {
      await pump(
        tester,
        NoteRow(
          metadata: noteNamed('Labelled', label: ItemLabel.teal),
          folderId: 'f',
          groupPosition: RowGroupPosition.single,
          onReturn: () {},
        ),
      );

      final dot = find.descendant(
        of: find.byType(LabelDot),
        matching: find.byType(Container),
      );
      expect(dot, findsOneWidget);
      expect(
        tester.getSize(dot),
        const Size(RowMetrics.labelDotSize, RowMetrics.labelDotSize),
      );
      expect(
        tester.getTopLeft(dot).dx,
        greaterThan(tester.getBottomRight(find.text('Labelled')).dx),
      );

      final decoration =
          tester.widget<Container>(dot).decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.color,
        AppColors.labelColor(ItemLabel.teal, Brightness.light),
      );
      expect(
        (decoration.border! as Border).top.color,
        AppColors.labelRing(Brightness.light),
      );
    });

    testWidgets('in reorder mode the dot sits left of the drag handle', (
      tester,
    ) async {
      await pump(
        tester,
        NoteRow(
          metadata: noteNamed('Labelled', label: ItemLabel.red),
          folderId: 'f',
          groupPosition: RowGroupPosition.single,
          onReturn: () {},
          isReorderMode: true,
          index: 0,
        ),
      );

      expect(
        tester.getCenter(find.byType(LabelDot)).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.drag_handle)).dx),
      );
    });

    testWidgets('an unlabelled folder row draws no dot, a labelled one puts '
        'it before the count and chevron', (tester) async {
      await pump(
        tester,
        FolderRow(
          folder: folderNamed('Plain'),
          noteCount: 3,
          groupPosition: RowGroupPosition.single,
          onReturn: () {},
        ),
      );
      expect(find.byType(LabelDot), findsNothing);

      await pump(
        tester,
        FolderRow(
          folder: folderNamed('Marked', label: ItemLabel.blue),
          noteCount: 3,
          groupPosition: RowGroupPosition.single,
          onReturn: () {},
        ),
      );

      expect(find.byType(LabelDot), findsOneWidget);
      expect(
        tester.getCenter(find.byType(LabelDot)).dx,
        lessThan(tester.getCenter(find.byType(RowCountChevron)).dx),
      );
      expect(
        tester.getCenter(find.byType(LabelDot)).dx,
        greaterThan(tester.getBottomRight(find.text('Marked')).dx),
      );
      final glyph = tester.widget<Icon>(find.byIcon(Icons.folder_outlined));
      expect(
        glyph.color,
        AppTheme.lightScheme.primary,
        reason: 'a label never tints the folder glyph',
      );
    });

    testWidgets('a labelled folder row in reorder mode puts the dot left of '
        'the drag handle', (tester) async {
      await pump(
        tester,
        FolderRow(
          folder: folderNamed('Marked', label: ItemLabel.green),
          groupPosition: RowGroupPosition.single,
          onReturn: () {},
          isReorderMode: true,
          index: 0,
        ),
      );

      expect(
        tester.getCenter(find.byType(LabelDot)).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.drag_handle)).dx),
      );
    });
  });

  group('the label swatch strip', () {
    final scheme = AppTheme.lightScheme;

    Future<void> pumpStrip(
      WidgetTester tester, {
      required ItemLabel value,
      required ValueChanged<ItemLabel> onChanged,
    }) {
      return pump(
        tester,
        LabelSwatchStrip(value: value, onChanged: onChanged),
      );
    }

    testWidgets('draws a clear swatch plus the seven colours', (tester) async {
      await pumpStrip(tester, value: ItemLabel.none, onChanged: (_) {});

      expect(find.byType(InkWell), findsNWidgets(8));
      expect(find.bySemanticsLabel(l10n.labelNone), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.labelRed), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.labelPink), findsOneWidget);
    });

    testWidgets('fits a 360dp phone without overflowing, every cell at least '
        'as wide as its painted circle', (tester) async {
      await pump(
        tester,
        Center(
          child: SizedBox(
            width: 360,
            child: LabelSwatchStrip(value: ItemLabel.none, onChanged: (_) {}),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final inkWell in find.byType(InkWell).evaluate()) {
        final cell = tester.getSize(
          find.ancestor(
            of: find.byWidget(inkWell.widget),
            matching: find.byType(Expanded),
          ),
        );
        expect(cell.width, greaterThanOrEqualTo(LabelSwatchStrip.swatchSize));
        expect(cell.height, LabelSwatchStrip.tapTarget);
      }
      expect(
        tester.getTopLeft(find.byType(InkWell).first).dx,
        greaterThan(tester.getTopLeft(find.byType(Center).first).dx),
      );
      expect(
        tester.getBottomRight(find.byType(InkWell).last).dx,
        lessThan(tester.getBottomRight(find.byType(Center).first).dx),
      );
    });

    testWidgets('tapping a swatch reports it', (tester) async {
      final picked = <ItemLabel>[];
      await pumpStrip(tester, value: ItemLabel.none, onChanged: picked.add);

      await tester.tap(find.bySemanticsLabel(l10n.labelBlue));
      await tester.pump();

      expect(picked, [ItemLabel.blue]);
    });

    testWidgets('the current value is the ringed swatch', (tester) async {
      await pumpStrip(tester, value: ItemLabel.green, onChanged: (_) {});

      BoxDecoration ringOf(String name) {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.bySemanticsLabel(name),
                matching: find.byType(Container),
              )
              .first,
        );
        return container.decoration! as BoxDecoration;
      }

      final selected = ringOf(l10n.labelGreen);
      expect(selected.border, isNotNull);
      expect((selected.border! as Border).top.color, scheme.primary);
      expect((selected.border! as Border).top.width, 2);

      expect(
        ringOf(l10n.labelRed).border,
        isNull,
        reason: 'only the current value is ringed',
      );
    });
  });

  group('the row action sheet', () {
    Widget sheetHost({
      Widget Function(BuildContext sheetContext)? headerBuilder,
    }) {
      return MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showRowActionSheet(
                  context,
                  title: 'Leg day',
                  headerBuilder: headerBuilder,
                  actions: [
                    RowAction(
                      icon: Icons.edit_rounded,
                      label: l10n.rename,
                      onSelected: () {},
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders its header between the title and the first action, '
        'each behind its own divider', (tester) async {
      await tester.pumpWidget(
        sheetHost(
          headerBuilder: (sheetContext) => LabelSwatchStrip(
            value: ItemLabel.none,
            onChanged: (label) => Navigator.of(sheetContext).pop(),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(LabelSwatchStrip), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
      final stripY = tester.getTopLeft(find.byType(LabelSwatchStrip)).dy;
      expect(stripY, greaterThan(tester.getTopLeft(find.text('Leg day')).dy));
      expect(stripY, lessThan(tester.getTopLeft(find.text(l10n.rename)).dy));

      await tester.tap(find.bySemanticsLabel(l10n.labelOrange));
      await tester.pumpAndSettle();

      expect(
        find.byType(LabelSwatchStrip),
        findsNothing,
        reason: 'picking a swatch closes the sheet',
      );
    });

    testWidgets('without a header the sheet is exactly what it was', (
      tester,
    ) async {
      await tester.pumpWidget(sheetHost());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(LabelSwatchStrip), findsNothing);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });
  });
}
