import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/user_avatar.dart';

/// `EventAvatar`'s three cuts (`docs/cloud-share-surfaces-roadmap.md` §6.7):
/// the filled one every row drew before sharing, the outlined one a
/// partner's event takes under the Outlined look, and the share badge on the
/// rim — none of which may change the 40 dp box a row is laid out around.
void main() {
  const yellow = Color(0xFFFDD835);
  const maria = AppUser(uid: 'maria', displayName: 'Maria');

  Future<void> pump(
    WidgetTester tester,
    Widget avatar, {
    TextDirection direction = TextDirection.ltr,
    ThemeData? theme,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Align(
              alignment: AlignmentDirectional.topStart,
              child: Padding(padding: const EdgeInsets.all(40), child: avatar),
            ),
          ),
        ),
      ),
    );
  }

  Rect boxOf(WidgetTester tester) => tester.getRect(find.byType(EventAvatar));

  group('filled', () {
    testWidgets('is today\'s CircleAvatar in the 40 dp box', (tester) async {
      await pump(tester, const EventAvatar(icon: Icons.event, color: yellow));

      expect(boxOf(tester).size, const Size.square(EventAvatar.radius * 2));
      final circle = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(circle.radius, EventAvatar.radius);
      expect(
        circle.backgroundColor,
        yellow.withValues(alpha: EventAvatar.backgroundAlpha),
      );
      expect(circle.foregroundColor, yellow);
      expect(tester.widget<Icon>(find.byType(Icon)).size, EventAvatar.iconSize);
    });
  });

  group('outlined', () {
    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('$name: a ring and an icon in the colour lifted to 3:1 on '
          'rowGroup, no fill, the same box', (tester) async {
        await pump(
          tester,
          const EventAvatar(icon: Icons.event, color: yellow, outlined: true),
          theme: theme,
        );

        expect(boxOf(tester).size, const Size.square(EventAvatar.radius * 2));
        expect(find.byType(CircleAvatar), findsNothing);
        final ink = MarkerContrast.atLeast(yellow, theme.colorScheme.rowGroup);
        final ring = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(EventAvatar),
            matching: find.byType(DecoratedBox),
          ),
        );
        final decoration = ring.decoration as BoxDecoration;
        expect(decoration.color, isNull);
        expect(decoration.shape, BoxShape.circle);
        final side = (decoration.border! as Border).top;
        expect(side.width, FormMetrics.shareOutlineWidth);
        expect(side.color, ink);
        expect(side.strokeAlign, BorderSide.strokeAlignInside);
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.color, ink);
        expect(icon.size, EventAvatar.iconSize);
      });
    }
  });

  group('badge', () {
    // 20 + 20·√½, the rim at 45°.
    const centre = 34.14;

    for (final direction in TextDirection.values) {
      testWidgets('${direction.name}: the partner\'s face sits on the rim at '
          'the bottom-end corner and the box stays 40 dp', (tester) async {
        await pump(
          tester,
          const EventAvatar(
            icon: Icons.event,
            color: yellow,
            badge: EventAvatarBadge.partner(maria),
          ),
          direction: direction,
        );

        final box = boxOf(tester);
        expect(box.size, const Size.square(EventAvatar.radius * 2));
        final face = tester.getRect(find.byType(UserAvatar));
        expect(face.width, RowMetrics.partnerAvatarRadius * 2);
        expect(face.center.dy - box.top, closeTo(centre, 1));
        final fromStart = direction == TextDirection.ltr
            ? face.center.dx - box.left
            : box.right - face.center.dx;
        expect(fromStart, closeTo(centre, 1));
      });
    }

    testWidgets('the halo is rowGroup and 24 dp across', (tester) async {
      await pump(
        tester,
        const EventAvatar(
          icon: Icons.event,
          color: yellow,
          badge: EventAvatarBadge.partner(maria),
        ),
      );

      final scheme = AppTheme.light().colorScheme;
      final halo = find.descendant(
        of: find.byType(EventAvatar),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).color == scheme.rowGroup,
        ),
      );
      expect(halo, findsOneWidget);
      expect(
        tester.getSize(halo),
        const Size.square(
          2 * (RowMetrics.partnerAvatarRadius + RowMetrics.shareBadgeHalo),
        ),
      );
    });

    testWidgets('a partner never read draws the person glyph', (tester) async {
      await pump(
        tester,
        const EventAvatar(
          icon: Icons.event,
          color: yellow,
          badge: EventAvatarBadge.partner(null),
        ),
      );

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('mine is the share sign at its own size', (tester) async {
      await pump(
        tester,
        const EventAvatar(
          icon: Icons.event,
          color: yellow,
          badge: EventAvatarBadge.mine,
        ),
      );

      final sign = tester.widget<Icon>(find.byIcon(Icons.group_rounded));
      expect(sign.size, RowMetrics.shareMarkSize);
      expect(find.byType(UserAvatar), findsNothing);
      expect(boxOf(tester).size, const Size.square(EventAvatar.radius * 2));
    });
  });

  group('semantics', () {
    testWidgets('silent without a label, as before sharing', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const EventAvatar(icon: Icons.event, color: yellow));

      expect(tester.getSemantics(find.byType(EventAvatar)).label, isEmpty);
      handle.dispose();
    });

    testWidgets('says its label, the badge excluded', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const EventAvatar(
          icon: Icons.event,
          color: yellow,
          badge: EventAvatarBadge.partner(maria),
          semanticsLabel: 'From Maria',
        ),
      );

      expect(find.bySemanticsLabel('From Maria'), findsOneWidget);
      handle.dispose();
    });
  });

  group('ofRow', () {
    Future<EventAvatar> built(WidgetTester tester, PartnerLook? look) async {
      late EventAvatar avatar;
      await pump(
        tester,
        Builder(
          builder: (context) => avatar = EventAvatar.ofRow(
            icon: Icons.event,
            color: yellow,
            partner: look,
            l10n: AppLocalizations.of(context)!,
          ),
        ),
      );
      return avatar;
    }

    testWidgets('my own event is today\'s avatar', (tester) async {
      final avatar = await built(tester, null);
      expect(avatar.outlined, isFalse);
      expect(avatar.badge, isNull);
      expect(avatar.semanticsLabel, isNull);
    });

    testWidgets('a partner\'s event follows the look and says whose it is in '
        'every one', (tester) async {
      for (final look in ShareEventLook.values) {
        final avatar = await built(
          tester,
          PartnerLook(look: look, partner: maria, name: 'Maria'),
        );
        expect(avatar.outlined, look == ShareEventLook.outlined);
        expect(
          avatar.badge,
          look == ShareEventLook.avatar
              ? const EventAvatarBadge.partner(maria)
              : null,
        );
        expect(avatar.semanticsLabel, 'From Maria');
      }
    });

    testWidgets('a partner with no name is the localized stand-in', (
      tester,
    ) async {
      final avatar = await built(tester, const PartnerLook());
      expect(avatar.semanticsLabel, 'From your partner');
    });
  });
}
