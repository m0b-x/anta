import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/chain_item.dart';
import 'package:anta/services/resolver_chain.dart';

/// The dedup-and-order rule behind all three calendar provider chains — the
/// grid's bars, the cell's rail, and the day panel's summary rows.
///
/// It lived as three byte-identical copies until it was extracted, and only
/// one of those copies (`DayBarsResolver`) had a suite asserting the tie-break
/// directly; `DaySummaryResolver.resolve` had none at all. So these are the
/// tests that now stand behind the day panel as well, and the reason a fix
/// here can no longer land in one surface and miss two.
/// Minimal [ChainItem] — the algorithm only ever reads `key` and `priority`,
/// and [tag] is how a test tells two equal-priority items apart.
final class Item implements ChainItem {
  @override
  final String key;
  @override
  final int priority;
  final String tag;

  Item(this.key, this.priority, [String? tag]) : tag = tag ?? key;
}

void main() {
  List<String> tagsOf(List<Item> items) => [for (final i in items) i.tag];

  test('empty chain resolves to nothing', () {
    expect(resolveChain<Item>(const []), isEmpty);
    expect(resolveChain<Item>([const <Item>[], const <Item>[]]), isEmpty);
  });

  test('orders by priority, lowest first', () {
    final result = resolveChain([
      [Item('weekend', 250), Item('holiday', 150), Item('event:a', 0)],
    ]);

    expect(tagsOf(result), ['event:a', 'holiday', 'weekend']);
  });

  test('dedups by key, first provider winning', () {
    // Providers are ordered by specificity, so an event's own contribution
    // beats a contextual one that happens to claim the same key.
    final result = resolveChain([
      [Item('shared', 10, 'first')],
      [Item('shared', 0, 'second')],
    ]);

    expect(tagsOf(result), ['first']);
    // The loser is gone entirely, not merely re-ranked — even though its
    // priority would have sorted it above the winner.
    expect(result.single.priority, 10);
  });

  test('equal priorities keep provider order, never key order', () {
    // The regression this rule exists for: `List.sort` is unstable, so ties
    // used to fall through to a key comparison and `event:<uuid>` keys
    // scrambled a day into id order. Keys here are deliberately reverse to
    // the order the providers emit them in.
    final result = resolveChain([
      [Item('zzz', 5, 'emitted first'), Item('aaa', 5, 'emitted second')],
    ]);

    expect(tagsOf(result), ['emitted first', 'emitted second']);
  });

  test('the tie-break spans providers, not just one', () {
    final result = resolveChain([
      [Item('z', 5, 'provider 0')],
      [Item('a', 5, 'provider 1')],
      [Item('m', 5, 'provider 2')],
    ]);

    expect(tagsOf(result), ['provider 0', 'provider 1', 'provider 2']);
  });

  test('ties are broken within a priority band, not across it', () {
    final result = resolveChain([
      [Item('a', 9, 'low first'), Item('b', 1, 'high second')],
      [Item('c', 9, 'low third'), Item('d', 1, 'high fourth')],
    ]);

    expect(tagsOf(result), [
      'high second',
      'high fourth',
      'low first',
      'low third',
    ]);
  });

  test('does not cap — capping is the widget\'s job', () {
    final result = resolveChain([
      [for (var i = 0; i < 20; i++) Item('k$i', i)],
    ]);

    expect(result, hasLength(20));
  });

  test('iterates a lazy chain exactly once', () {
    // Call sites pass `providers.map(...)`, so a second pass would re-run
    // every provider for the same cell.
    var passes = 0;
    final lazy = [1, 2].map((i) {
      passes++;
      return [Item('k$i', i)];
    });

    final result = resolveChain(lazy);

    expect(passes, 2);
    expect(result, hasLength(2));
  });
}
