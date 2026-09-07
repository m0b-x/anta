import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/widgets/folder_overflow_menu.dart';
import 'package:anta/widgets/note_overflow_menu.dart';

/// E5, E6/E22, E7 — menu anatomy against the mock: 236 wide, 44 dp rows,
/// a 15/400 label, 20 px glyphs in `onSurfaceVariant`, and a move-history
/// count that is a primary pill on the trailing edge rather than a red
/// notification badge hung off the leading glyph.
Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(appBar: AppBar(actions: [child])),
  );
}

void main() {
  final l10n = AppLocalizationsEn();

  Finder menuItems() =>
      find.byWidgetPredicate((widget) => widget is PopupMenuItem);

  void expectAnatomy(WidgetTester tester, ColorScheme scheme) {
    for (final element in menuItems().evaluate()) {
      final item = element.widget as PopupMenuItem;
      expect(item.height, AppTheme.menuItemHeight);
      final size = tester.getSize(find.byWidget(item));
      expect(size.width, AppTheme.menuWidth);
      expect(size.height, AppTheme.menuItemHeight);
    }

    // The label style comes from the theme, so every row reads the same
    // 15/400 without any of them saying so.
    final label = tester.widget<Text>(find.text(l10n.settings));
    final style = DefaultTextStyle.of(
      tester.element(find.text(l10n.settings)),
    ).style.merge(label.style);
    expect(style.fontSize, AppTheme.menuLabelSize);
    expect(style.fontWeight, FontWeight.w400);
    expect(style.color, scheme.onSurface);

    final glyph = tester.widget<Icon>(find.byIcon(Icons.settings_outlined));
    expect(glyph.size, AppTheme.menuIconSize);
    expect(glyph.color, scheme.onSurfaceVariant);
  }

  for (final brightness in Brightness.values) {
    testWidgets('the note menu anatomy matches the mock (${brightness.name})', (
      tester,
    ) async {
      final scheme = brightness == Brightness.light
          ? AppTheme.lightScheme
          : AppTheme.darkScheme;
      await tester.pumpWidget(
        _host(
          NoteOverflowMenu(
            folderName: 'Training plans',
            onOpenFolder: () {},
            onEditTitle: () {},
            onMove: () {},
            onShare: () {},
            onDelete: () {},
            onSettings: () {},
          ),
          brightness: brightness,
        ),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expectAnatomy(tester, scheme);

      // Trailing secondary text: 13 px, muted, right-aligned.
      final trailing = tester.widget<Text>(find.text(l10n.openFolder));
      expect(trailing.style?.fontSize, AppTheme.menuTrailingSize);
      expect(trailing.style?.color, scheme.onSurfaceVariant);
      expect(trailing.textAlign, TextAlign.end);

      // The destructive row keeps `error`, glyph included.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.delete)).color,
        scheme.error,
      );
      expect(
        tester.widget<Text>(find.text(l10n.deleteNote)).style?.color,
        scheme.error,
      );

      // Separators are a hairline in a 13 dp band, not a 16 dp row.
      for (final element in find.byType(PopupMenuDivider).evaluate().toList()) {
        expect(
          (element.widget as PopupMenuDivider).height,
          AppTheme.menuDividerHeight,
        );
      }
    });
  }

  testWidgets('the folder menu anatomy matches the mock', (tester) async {
    await tester.pumpWidget(
      _host(
        FolderOverflowMenu(
          isRootPage: false,
          sortLabel: 'Name',
          moveHistoryCount: 0,
          onSortBy: () {},
          onSelect: () {},
          onMoveHistory: () {},
          onImport: () {},
          onSettings: () {},
          onRenameFolder: () {},
          onMoveFolder: () {},
          onShareFolder: () {},
          onDeleteFolder: () {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expectAnatomy(tester, AppTheme.lightScheme);
    final trailing = tester.widget<Text>(find.text('Name'));
    expect(trailing.style?.fontSize, AppTheme.menuTrailingSize);
    expect(trailing.style?.color, AppTheme.lightScheme.onSurfaceVariant);
  });

  testWidgets('the move-history count is a primary pill on the trailing edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FolderOverflowMenu(
          isRootPage: true,
          sortLabel: 'Name',
          moveHistoryCount: 3,
          onSortBy: () {},
          onSelect: () {},
          onMoveHistory: () {},
          onImport: () {},
          onSettings: () {},
        ),
      ),
    );

    // The trigger keeps its badge, recoloured off the error palette.
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.backgroundColor, AppTheme.lightScheme.primary);
    expect(badge.textColor, AppTheme.lightScheme.onPrimary);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // No second Badge in the menu: the row count is the pill.
    expect(find.byType(MenuCountPill), findsOneWidget);
    final pill = tester.getRect(find.byType(MenuCountPill));
    expect(pill.height, MenuCountPill.height);
    expect(pill.width, greaterThanOrEqualTo(MenuCountPill.height));

    final row = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.history),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
    );
    final label = tester.getRect(find.text(AppLocalizationsEn().moveHistory));
    expect(pill.left, greaterThan(label.left));
    expect(pill.right, lessThanOrEqualTo(row.right));

    final decoration =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(MenuCountPill),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, AppTheme.lightScheme.primary);

    final text = tester.widget<Text>(
      find.descendant(of: find.byType(MenuCountPill), matching: find.text('3')),
    );
    expect(text.style?.fontSize, 11);
    expect(text.style?.fontWeight, FontWeight.w500);
    expect(text.style?.color, AppTheme.lightScheme.rowGroup);
  });
}
