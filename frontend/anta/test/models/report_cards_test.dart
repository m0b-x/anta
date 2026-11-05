import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/report_cards.dart';

/// The report's card list (W): the defaults are the page's order with every
/// card on, the stored grammar round-trips and reads forward-compatibly,
/// and a move or a switch keeps every card exactly once.
void main() {
  const all = ReportCardKind.values;

  test('the defaults are the page order, every card shown', () {
    expect(ReportCards.defaults.order, all);
    expect(ReportCards.defaults.off, isEmpty);
    expect(ReportCards.defaults.shown, all);
    expect(all.first, ReportCardKind.goals);
    expect(all.last, ReportCardKind.ahead);
  });

  test('encode writes every name in order, an off card with a dash', () {
    final cards = ReportCards.defaults.toggled(ReportCardKind.dueSoon, false);

    expect(
      cards.encode(),
      'goals,insights,-dueSoon,totals,records,months,categories,tags,'
      'overTime,when,balance,missed,ahead',
    );
  });

  test('decode reads encode back', () {
    final cards = ReportCards.defaults
        .moved(12, 0)
        .toggled(ReportCardKind.when, false)
        .toggled(ReportCardKind.goals, false);

    expect(ReportCards.decode(cards.encode()), cards);
    expect(
      ReportCards.decode(ReportCards.defaults.encode()),
      ReportCards.defaults,
    );
  });

  test('a space after the dash still reads the card off', () {
    final cards = ReportCards.decode(' - goals , insights');

    expect(cards.order.first, ReportCardKind.goals);
    expect(cards.off, {ReportCardKind.goals});
    expect(cards.order, all);
  });

  test('null, empty and blank decode as the defaults', () {
    expect(ReportCards.decode(null), ReportCards.defaults);
    expect(ReportCards.decode(''), ReportCards.defaults);
    expect(ReportCards.decode('  '), ReportCards.defaults);
  });

  test('an unknown name is skipped, a missing one joins on in the default '
      'order', () {
    final cards = ReportCards.decode('ahead,-chart,-totals,goals');

    expect(cards.order, [
      ReportCardKind.ahead,
      ReportCardKind.totals,
      ReportCardKind.goals,
      ReportCardKind.insights,
      ReportCardKind.dueSoon,
      ReportCardKind.records,
      ReportCardKind.months,
      ReportCardKind.categories,
      ReportCardKind.tags,
      ReportCardKind.overTime,
      ReportCardKind.when,
      ReportCardKind.balance,
      ReportCardKind.missed,
    ]);
    expect(cards.off, {ReportCardKind.totals});
  });

  test('a repeated name keeps its first place and its first switch', () {
    final cards = ReportCards.decode('missed,goals,-missed,goals');

    expect(cards.order.take(2), [ReportCardKind.missed, ReportCardKind.goals]);
    expect(cards.order, hasLength(all.length));
    expect(cards.order.toSet(), all.toSet());
    expect(cards.off, isEmpty);
  });

  test('shown is the order without the off cards', () {
    final cards = ReportCards.decode('-goals,ahead,-insights,totals');

    expect(cards.shown.take(2), [ReportCardKind.ahead, ReportCardKind.totals]);
    expect(cards.shown, isNot(contains(ReportCardKind.goals)));
    expect(cards.shown, isNot(contains(ReportCardKind.insights)));
    expect(cards.shown, hasLength(all.length - 2));
  });

  test('moved takes indices adjusted for the removal', () {
    final down = ReportCards.defaults.moved(0, 2);
    expect(down.order.take(3), [
      ReportCardKind.insights,
      ReportCardKind.dueSoon,
      ReportCardKind.goals,
    ]);

    final up = ReportCards.defaults.moved(12, 0);
    expect(up.order.first, ReportCardKind.ahead);
    expect(up.order[1], ReportCardKind.goals);
    expect(up.order, hasLength(all.length));
  });

  test('moved onto its own place or out of range is the same cards', () {
    final cards = ReportCards.defaults;

    expect(identical(cards.moved(3, 3), cards), isTrue);
    expect(identical(cards.moved(-1, 2), cards), isTrue);
    expect(identical(cards.moved(0, all.length), cards), isTrue);
  });

  test('moved keeps the off cards off', () {
    final cards = ReportCards.defaults
        .toggled(ReportCardKind.balance, false)
        .moved(10, 0);

    expect(cards.order.first, ReportCardKind.balance);
    expect(cards.off, {ReportCardKind.balance});
    expect(cards.shown.first, ReportCardKind.goals);
  });

  test('toggled switches a card in place, a no-op is the same cards', () {
    final off = ReportCards.defaults.toggled(ReportCardKind.tags, false);
    expect(off.order, all);
    expect(off.off, {ReportCardKind.tags});

    expect(identical(off.toggled(ReportCardKind.tags, false), off), isTrue);
    expect(
      identical(
        ReportCards.defaults.toggled(ReportCardKind.tags, true),
        ReportCards.defaults,
      ),
      isTrue,
    );

    expect(off.toggled(ReportCardKind.tags, true), ReportCards.defaults);
  });
}
