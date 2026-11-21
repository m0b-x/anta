@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';

/// The sync book's ten stages measured as the page draws them
/// (`GuideTopicPage`, its side margins included) in the extreme cell — a
/// 360 × 780 phone, German, text scale 2.0 — for the record's table of
/// heights. Printed, not pinned: one `GUIDE-HEIGHT` line a card with the
/// card's and the stage's heights and whether the flip's top to the stage's
/// bottom fits the screen under the app bar (decision F). What holds for
/// every card is asserted: the flip leaves the stage's rect as it was.
void main() {
  late AppDatabase db;

  setUpAll(loadGoldenFonts);

  // The page reads the money config and the palette once.
  setUp(() async {
    db = await openTestDatabase();
    SettingsService.reset();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  const size = Size(360, 780);
  final visible = size.height - AppBarMetrics.toolbarHeight;

  for (final topic in SyncGuideTopic.values) {
    for (final spec in topic.demoCards) {
      final slug = spec.slug;
      testWidgets('$slug on its page, 360×780 de at 2.0', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: GuideTopicPage(book: GuideBook.sync, topic: topic),
          ),
        );
        // Nothing is in flight yet, so the page may settle.
        await tester.pumpAndSettle();

        final stage = find.bySemanticsIdentifier(
          SemanticsIds.guideBookTryStage('sync', slug),
        );
        await tester.scrollUntilVisible(
          stage,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        final card = find.ancestor(
          of: stage,
          matching: find.byType(CalendarGuideTryCard),
        );
        final flip = find.descendant(
          of: card,
          matching: find.byType(SegmentedButton<GuidePhone>),
        );
        final hasFlip = flip.evaluate().isNotEmpty;
        // A card of one phone has no flip: its span starts at the coach line.
        final top = hasFlip
            ? tester.getTopLeft(flip).dy
            : tester
                  .getTopLeft(
                    find
                        .descendant(
                          of: card,
                          matching: find.byType(FormCaptionSlot),
                        )
                        .first,
                  )
                  .dy;
        final stageRect = tester.getRect(stage);
        final span = stageRect.bottom - top;
        debugPrint(
          'GUIDE-HEIGHT $slug: card ${tester.getSize(card).height.round()}, '
          'stage ${stageRect.height.round()}, '
          '${hasFlip ? 'flip' : 'coach'}-to-stage ${span.round()} '
          '${span <= visible ? 'fits' : 'exceeds'} ${visible.round()}',
        );

        if (hasFlip) {
          Rect inCard() =>
              tester.getRect(stage).shift(-tester.getTopLeft(card));
          final hers = inCard();
          final there = find.bySemanticsIdentifier(
            SemanticsIds.guideBookTryPhone('sync', slug, 'there'),
          );
          await tester.ensureVisible(there);
          await tester.pump();
          await tester.tap(there);
          await tester.pump();
          expect(inCard(), hers, reason: 'the other phone');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
