import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/form_menu_item.dart';

/// `showFormMenuAbove` on a plain host: an anchor placed anywhere, the
/// menu read off its own surface.
void main() {
  const anchorSize = 48.0;
  const screen = Size(360, 780);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Ten glyphs of the test font plus the item's padding: 174 dp, which the
  // framework's 56 dp step rounds to 224.
  const short = ['Aaaaaaaaaa', 'Bbbbbbbbbb', 'Cccccccccc'];

  Widget host(
    _Outcome outcome, {
    required List<String> labels,
    double? left,
    double? top,
    double? bottom,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    double gap = 0,
    bool requestFocus = false,
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: left ?? (screen.width - anchorSize) / 2,
              top: top,
              bottom: bottom,
              child: Builder(
                builder: (anchor) => SizedBox.square(
                  key: _anchorKey,
                  dimension: anchorSize,
                  child: Material(
                    child: InkWell(
                      onTap: () async {
                        outcome.value = await showFormMenuAbove<int>(
                          anchor,
                          requestFocus: requestFocus,
                          gap: gap,
                          items: [
                            for (var i = 0; i < labels.length; i++)
                              FormMenuChoiceItem<int>(
                                value: i,
                                checked: false,
                                child: FormMenuItemRow(label: labels[i]),
                              ),
                          ],
                        );
                        outcome.closed = true;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect anchorRect(WidgetTester tester) =>
      tester.getRect(find.byKey(_anchorKey));

  Finder menuOf(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(Material))
      .first;

  List<String> headings(Locale locale) {
    final l10n = lookupAppLocalizations(locale);
    return [
      l10n.headingBodyText,
      l10n.header1,
      l10n.header2,
      l10n.header3,
      l10n.header4,
      l10n.header5,
      l10n.header6,
    ];
  }

  group('above the anchor', () {
    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('de'), 2.0),
    ]) {
      testWidgets('${locale.languageCode} at $scale: the bottom edge on the '
          'anchor, centred on it', (tester) async {
        phone(tester);
        final labels = headings(locale);
        final outcome = _Outcome();
        await tester.pumpWidget(
          host(
            outcome,
            labels: labels,
            top: 600,
            locale: locale,
            textScale: scale,
          ),
        );

        await tester.tap(find.byKey(_anchorKey));
        await tester.pumpAndSettle();

        final anchor = anchorRect(tester);
        final menu = tester.getRect(menuOf(labels.first));
        expect(menu.bottom, moreOrLessEquals(anchor.top));
        expect(menu.center.dx, moreOrLessEquals(anchor.center.dx));
        expect(menu.top, greaterThanOrEqualTo(8));
      });
    }

    testWidgets('a gap keeps the edge off the anchor, and the reveal rises '
        'from there', (tester) async {
      phone(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: short, top: 600, gap: 6));
      final anchor = anchorRect(tester);

      await tester.tap(find.byKey(_anchorKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final rising = tester.getRect(menuOf(short.first));
      await tester.pumpAndSettle();
      final menu = tester.getRect(menuOf(short.first));

      expect(rising.bottom, moreOrLessEquals(anchor.top - 6));
      expect(menu.bottom, moreOrLessEquals(anchor.top - 6));
      expect(rising.height, lessThan(menu.height));
    });

    testWidgets('an anchor at the right edge keeps the menu 16 dp inside it', (
      tester,
    ) async {
      phone(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(
        host(outcome, labels: short, left: screen.width - anchorSize, top: 600),
      );

      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(menuOf(short.first)).right,
        moreOrLessEquals(screen.width - RowMetrics.groupInset),
      );
    });

    testWidgets('a side cutout pushes the clamp in by its padding', (
      tester,
    ) async {
      phone(tester);
      tester.view.padding = const FakeViewPadding(left: 40, right: 30);
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: short, left: 0, top: 600));

      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(menuOf(short.first)).left,
        moreOrLessEquals(40 + RowMetrics.groupInset),
      );
      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        host(outcome, labels: short, left: screen.width - anchorSize, top: 600),
      );
      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(menuOf(short.first)).right,
        moreOrLessEquals(screen.width - 30 - RowMetrics.groupInset),
      );
    });

    testWidgets('a short menu steps its width as showMenu does', (
      tester,
    ) async {
      phone(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: short, top: 600));

      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(menuOf(short.first)).width,
        4 * FormMetrics.menuWidthStep,
      );
    });
  });

  group('the side', () {
    testWidgets('an anchor without the room above opens below, its top edge '
        'on the anchor, revealed from there', (tester) async {
      phone(tester);
      tester.view.padding = const FakeViewPadding(top: 24);
      final labels = headings(const Locale('en'));
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: labels, top: 60));
      final anchor = anchorRect(tester);

      await tester.tap(find.byKey(_anchorKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final growing = tester.getRect(menuOf(labels.first));
      await tester.pumpAndSettle();
      final menu = tester.getRect(menuOf(labels.first));

      expect(menu.top, moreOrLessEquals(anchor.bottom));
      expect(growing.top, moreOrLessEquals(anchor.bottom));
      expect(growing.height, lessThan(menu.height));
      expect(find.text(labels.last).hitTestable(), findsOneWidget);
    });

    testWidgets('a keyboard dropping in one step under the open menu carries '
        'it down with its anchor, still above', (tester) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      final labels = headings(const Locale('en'));
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: labels, bottom: 0));

      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();
      final raised = anchorRect(tester);
      expect(
        tester.getRect(menuOf(labels.first)).bottom,
        moreOrLessEquals(raised.top),
      );

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();

      final fallen = anchorRect(tester);
      expect(fallen.top, greaterThan(raised.top));
      expect(
        tester.getRect(menuOf(labels.first)).bottom,
        moreOrLessEquals(fallen.top),
      );
    });
  });

  group('the answer', () {
    testWidgets('a pick returns its value', (tester) async {
      phone(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: short, top: 600));

      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(short[1]));
      await tester.pumpAndSettle();

      expect(outcome.closed, isTrue);
      expect(outcome.value, 1);
    });

    testWidgets('the barrier returns null', (tester) async {
      phone(tester);
      final outcome = _Outcome();
      await tester.pumpWidget(host(outcome, labels: short, top: 600));

      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(find.text(short.first), findsNothing);
      expect(outcome.closed, isTrue);
      expect(outcome.value, isNull);
    });

    testWidgets(
      'with focus taken, Escape returns null',
      (tester) async {
        phone(tester);
        final outcome = _Outcome();
        await tester.pumpWidget(
          host(outcome, labels: short, top: 600, requestFocus: true),
        );

        await tester.tap(find.byKey(_anchorKey));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.text(short.first), findsNothing);
        expect(outcome.closed, isTrue);
        expect(outcome.value, isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    // The framework's directional traversal reaches the items unaided: no
    // item is autofocused.
    testWidgets(
      'with focus taken, arrow down and Enter pick the first item',
      (tester) async {
        phone(tester);
        final outcome = _Outcome();
        await tester.pumpWidget(
          host(outcome, labels: short, top: 600, requestFocus: true),
        );

        await tester.tap(find.byKey(_anchorKey));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(outcome.closed, isTrue);
        expect(outcome.value, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });

  group('semantics', () {
    Finder menuNode() => find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.role == SemanticsRole.menu,
    );

    Future<void> open(WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(host(_Outcome(), labels: short, top: 600));
      await tester.tap(find.byKey(_anchorKey));
      await tester.pumpAndSettle();
    }

    testWidgets('a menu node that names its route, labelled on Android', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester);

      final node = tester.getSemantics(menuNode());
      expect(node.getSemanticsData().role, SemanticsRole.menu);
      expect(
        node,
        isSemantics(
          label: const DefaultMaterialLocalizations().popupMenuLabel,
          namesRoute: true,
          scopesRoute: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets(
      'no label on iOS, as showMenu',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester);

        final node = tester.getSemantics(menuNode());
        expect(node.getSemanticsData().role, SemanticsRole.menu);
        expect(node.label, isEmpty);
        semantics.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });
}

final _anchorKey = GlobalKey();

class _Outcome {
  bool closed = false;
  int? value;
}
