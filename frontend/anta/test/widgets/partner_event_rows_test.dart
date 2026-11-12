import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_summary_entry.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/widgets/agenda_day_list_rows.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/day_summary_panel.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';

/// A partner's event in the three lists that draw events — the day panel,
/// the agenda and the overview's rows — under each of the three looks
/// (`docs/cloud-share-surfaces-roadmap.md` §6.7): the look lives in the
/// avatar and, under Outlined, the cards' unpainted stripe; nothing else on
/// the row moves, and "From {name}" is read first in every look.
void main() {
  setUpAll(() => initializeDateFormatting('en'));

  const maria = AppUser(uid: 'maria', displayName: 'Maria');
  const green = Color(0xFF00897B);
  const title = 'Night shift';
  const subtitle = '21:00 – 07:00';
  final day = DateTime.utc(2026, 11, 12);
  const scales = [1.0, 1.3, 2.0];

  CalendarEvent event(String id, {bool fromPartner = false}) => CalendarEvent(
    id: id,
    title: title,
    categoryId: 'work',
    startDate: day,
    fromPartner: fromPartner,
  );

  final mine = event('mine');
  final theirs = event('theirs', fromPartner: true);

  DaySummaryEntry summaryOf(CalendarEvent event) => DaySummaryEntry(
    key: 'event:${event.id}',
    icon: Icons.local_hospital,
    color: green,
    title: title,
    subtitle: subtitle,
    priority: 0,
    event: event,
  );

  PartnerLook lookOf(ShareEventLook look) =>
      PartnerLook(look: look, partner: maria, name: 'Maria');

  Future<void> pump(WidgetTester tester, Widget body, {double scale = 1.0}) {
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: body),
      ),
    );
  }

  /// The accent stripe of the card [card]: the one `Container` painted the
  /// entry's flat colour.
  Finder stripeIn(Finder card) => find.descendant(
    of: card,
    matching: find.byWidgetPredicate(
      (widget) => widget is Container && widget.color == green,
    ),
  );

  Finder avatarIn(Finder row) =>
      find.descendant(of: row, matching: find.byType(EventAvatar));

  Finder noteButtonIn(Finder row) => find.descendant(
    of: row,
    matching: find.widgetWithIcon(IconButton, Icons.sticky_note_2_outlined),
  );

  void expectLook(WidgetTester tester, Finder row, ShareEventLook? look) {
    final avatar = tester.widget<EventAvatar>(avatarIn(row));
    expect(avatar.outlined, look == ShareEventLook.outlined);
    expect(
      avatar.badge,
      look == ShareEventLook.avatar
          ? const EventAvatarBadge.partner(maria)
          : null,
    );
    expect(avatar.semanticsLabel, look == null ? null : 'From Maria');
  }

  /// The three guidelines a list with a partner's row meets in every look.
  Future<void> expectGuidelines(WidgetTester tester, Widget body) async {
    final handle = tester.ensureSemantics();
    await pump(tester, body);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }

  group('day panel', () {
    Widget panel(ShareEventLook look) => DaySummaryPanel(
      day: day,
      entries: [summaryOf(mine), summaryOf(theirs)],
      onEventTap: (_) {},
      partnerLook: lookOf(look),
    );

    final mineCard = find.byKey(const ValueKey('event:mine'));
    final theirCard = find.byKey(const ValueKey('event:theirs'));

    for (final look in ShareEventLook.values) {
      testWidgets('${look.name}: meets the target, label and contrast '
          'guidelines', (tester) => expectGuidelines(tester, panel(look)));
    }

    for (final look in ShareEventLook.values) {
      testWidgets('${look.name}: the avatar carries the look; the stripe is '
          'unpainted only under Outlined; mine is unchanged', (tester) async {
        await pump(tester, panel(look));

        expectLook(tester, theirCard, look);
        expectLook(tester, mineCard, null);
        expect(
          stripeIn(theirCard),
          look == ShareEventLook.outlined ? findsNothing : findsOneWidget,
        );
        expect(stripeIn(mineCard), findsOneWidget);
      });

      for (final scale in scales) {
        testWidgets('${look.name} at $scale: the partner\'s card is as tall '
            'as mine', (tester) async {
          await pump(tester, panel(look), scale: scale);

          expect(
            tester.getSize(theirCard).height,
            tester.getSize(mineCard).height,
          );
        });
      }

      testWidgets('${look.name}: the card\'s one node begins "From Maria" and '
          'carries the title', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester, panel(look));

        expect(
          find.bySemanticsLabel(RegExp('^From Maria\\n$title\\n$subtitle')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('From Maria')), findsOneWidget);
        handle.dispose();
      });
    }

    testWidgets('my own card says nothing new and keeps CircleAvatar\'s '
        'filled look', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        DaySummaryPanel(
          day: day,
          entries: [summaryOf(mine)],
          onEventTap: (_) {},
        ),
      );

      expect(find.bySemanticsLabel(RegExp('From')), findsNothing);
      expect(find.byType(CircleAvatar), findsOneWidget);
      handle.dispose();
    });

    // A partner's note is not reachable in this build (slice F).
    testWidgets('a partner\'s card has no note button; mine keeps its own', (
      tester,
    ) async {
      await pump(
        tester,
        DaySummaryPanel(
          day: day,
          entries: [
            summaryOf(mine.copyWith(noteId: 'note-mine')),
            summaryOf(theirs.copyWith(noteId: 'note-theirs')),
          ],
          onEventTap: (_) {},
          onOpenNote: (_) {},
          partnerLook: lookOf(ShareEventLook.outlined),
        ),
      );

      expect(noteButtonIn(mineCard), findsOneWidget);
      expect(noteButtonIn(theirCard), findsNothing);
    });
  });

  group('agenda', () {
    Widget agenda(
      ShareEventLook look, {
      CalendarEvent? myEvent,
      CalendarEvent? theirEvent,
    }) => SizedBox(
      width: 360,
      child: AgendaListView(
        rows: [
          AgendaEntryRow(day: day, entry: summaryOf(myEvent ?? mine)),
          AgendaEntryRow(day: day, entry: summaryOf(theirEvent ?? theirs)),
        ],
        onDaySelected: (_) {},
        onEditEvent: (_, _) {},
        onOpenNote: (_) {},
        emptyTitle: '',
        emptyHint: '',
        partnerLook: lookOf(look),
      ),
    );

    final cards = find.byType(Card);

    for (final look in ShareEventLook.values) {
      testWidgets('${look.name}: meets the target, label and contrast '
          'guidelines', (tester) => expectGuidelines(tester, agenda(look)));
    }

    for (final look in ShareEventLook.values) {
      testWidgets('${look.name}: the avatar carries the look; the stripe is '
          'unpainted only under Outlined; mine is unchanged', (tester) async {
        await pump(tester, agenda(look));

        expectLook(tester, cards.at(1), look);
        expectLook(tester, cards.at(0), null);
        expect(
          stripeIn(cards.at(1)),
          look == ShareEventLook.outlined ? findsNothing : findsOneWidget,
        );
        expect(stripeIn(cards.at(0)), findsOneWidget);
      });

      for (final scale in scales) {
        testWidgets('${look.name} at $scale: the partner\'s card is as tall '
            'as mine', (tester) async {
          await pump(tester, agenda(look), scale: scale);

          expect(
            tester.getSize(cards.at(1)).height,
            tester.getSize(cards.at(0)).height,
          );
        });
      }

      testWidgets('${look.name}: the title\'s node begins "From Maria"', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(tester, agenda(look));

        expect(
          find.bySemanticsLabel(RegExp('^From Maria\\n$title\\n$subtitle')),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    // Decision m: the pencil stays where the hand learned it, disabled.
    testWidgets('a partner\'s card keeps its pencil, disabled; mine is '
        'enabled', (tester) async {
      await pump(tester, agenda(ShareEventLook.outlined));

      IconButton pencilIn(Finder card) => tester.widget<IconButton>(
        find.descendant(
          of: card,
          matching: find.widgetWithIcon(IconButton, Icons.edit_outlined),
        ),
      );
      expect(pencilIn(cards.at(1)).onPressed, isNull);
      expect(pencilIn(cards.at(0)).onPressed, isNotNull);
    });

    testWidgets('a partner\'s card has no note button; mine keeps its own', (
      tester,
    ) async {
      await pump(
        tester,
        agenda(
          ShareEventLook.outlined,
          myEvent: mine.copyWith(noteId: 'note-mine'),
          theirEvent: theirs.copyWith(noteId: 'note-theirs'),
        ),
      );

      expect(noteButtonIn(cards.at(0)), findsOneWidget);
      expect(noteButtonIn(cards.at(1)), findsNothing);
    });
  });

  group('overview rows', () {
    AgendaDayListEntry entryOf(CalendarEvent event) => AgendaDayListEntry(
      day: day,
      icon: Icons.local_hospital,
      color: green,
      title: title,
      subtitle: subtitle,
      eventId: event.id,
      fromPartner: event.fromPartner,
    );

    // The overview's own geometry: one-line titles, a one-line caption.
    Widget list(ShareEventLook look) {
      final builder = AgendaDayListRowBuilder(
        rows: [
          AgendaDayListEntryRow(entry: entryOf(mine)),
          AgendaDayListEntryRow(entry: entryOf(theirs)),
        ],
        today: day,
        onEntryTap: (_) {},
        captionMaxLines: 1,
        singleLineTitles: true,
        partnerLook: lookOf(look),
      );
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: builder.rows.length,
        itemBuilder: builder.build,
      );
    }

    final rows = find.byType(FormPickerRow);

    for (final look in ShareEventLook.values) {
      testWidgets('${look.name}: meets the target, label and contrast '
          'guidelines', (tester) => expectGuidelines(tester, list(look)));
    }

    for (final look in ShareEventLook.values) {
      testWidgets('${look.name}: the avatar carries the look; mine is '
          'unchanged', (tester) async {
        await pump(tester, list(look));

        expectLook(tester, rows.at(1), look);
        expectLook(tester, rows.at(0), null);
      });

      for (final scale in scales) {
        testWidgets('${look.name} at $scale: the partner\'s row is as tall as '
            'mine', (tester) async {
          await pump(tester, list(look), scale: scale);

          expect(
            tester.getSize(rows.at(1)).height,
            tester.getSize(rows.at(0)).height,
          );
        });
      }

      testWidgets('${look.name}: the row\'s one node begins "From Maria"', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(tester, list(look));

        expect(
          find.bySemanticsLabel(RegExp('^From Maria\\n$title\\n$subtitle')),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    testWidgets('a folded event row of a partner\'s takes the look too', (
      tester,
    ) async {
      final builder = AgendaDayListRowBuilder(
        rows: [
          AgendaDayListEventRow(
            entry: entryOf(theirs),
            count: 3,
            missed: 0,
            first: day,
            last: day,
          ),
        ],
        today: day,
        partnerLook: lookOf(ShareEventLook.avatar),
      );
      await pump(
        tester,
        ListView.builder(
          itemCount: builder.rows.length,
          itemBuilder: builder.build,
        ),
      );

      expectLook(tester, rows.at(0), ShareEventLook.avatar);
    });

    // Decision m: the day list's pencil stays, disabled, and dims through
    // its `disabledColor`.
    testWidgets('a partner\'s day-list row keeps its pencil, disabled and '
        'dimmed; mine is enabled', (tester) async {
      AgendaDayListEntry editable(CalendarEvent event) => AgendaDayListEntry(
        day: day,
        icon: Icons.local_hospital,
        color: green,
        title: title,
        subtitle: subtitle,
        eventId: event.id,
        fromPartner: event.fromPartner,
        editable: true,
      );
      final builder = AgendaDayListRowBuilder(
        rows: [
          AgendaDayListEntryRow(entry: editable(mine)),
          AgendaDayListEntryRow(entry: editable(theirs)),
        ],
        today: day,
        onEntryTap: (_) {},
        onEntryEdit: (_) {},
        partnerLook: lookOf(ShareEventLook.outlined),
      );
      await pump(
        tester,
        ListView.builder(
          itemCount: builder.rows.length,
          itemBuilder: builder.build,
        ),
      );

      FormTrailingButton pencilIn(Finder row) =>
          tester.widget<FormTrailingButton>(
            find.descendant(of: row, matching: find.byType(FormTrailingButton)),
          );
      final theirPencil = pencilIn(rows.at(1));
      expect(theirPencil.icon, Icons.edit_outlined);
      expect(theirPencil.onPressed, isNull);
      expect(
        theirPencil.disabledColor,
        AppTheme.light().colorScheme.outline.withValues(
          alpha: FormMetrics.disabledOpacity,
        ),
      );
      final myPencil = pencilIn(rows.at(0));
      expect(myPencil.icon, Icons.edit_outlined);
      expect(myPencil.onPressed, isNotNull);
      expect(myPencil.disabledColor, isNull);
    });
  });
}
