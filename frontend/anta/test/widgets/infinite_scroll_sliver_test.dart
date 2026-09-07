import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/widgets/infinite_scroll_list.dart';

/// The paging sliver listens on a controller it does not own.
///
/// Both note lists swap it out of the tree whenever their bar becomes a
/// search field or a selection bar, while the page keeps the controller — so
/// a listener left behind goes on calling `onLoadMore` for an element that is
/// gone, once per round trip.
void main() {
  Widget host({
    required ScrollController controller,
    required bool withSliver,
    required VoidCallback onLoadMore,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            if (withSliver)
              InfiniteScrollSliver<int>(
                items: List<int>.generate(40, (i) => i),
                hasMore: true,
                isLoadingMore: false,
                controller: controller,
                onLoadMore: onLoadMore,
                itemBuilder: (context, item, index) =>
                    SizedBox(height: 40, child: Text('row $item')),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => SizedBox(height: 40, child: Text('$index')),
                  childCount: 40,
                ),
              ),
          ],
        ),
      ),
    );
  }

  testWidgets('the sliver stops listening when it leaves the tree', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var loadMoreCalls = 0;

    await tester.pumpWidget(
      host(
        controller: controller,
        withSliver: true,
        onLoadMore: () => loadMoreCalls++,
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(
      loadMoreCalls,
      greaterThan(0),
      reason: 'the listener has to work in the first place',
    );

    await tester.pumpWidget(
      host(
        controller: controller,
        withSliver: false,
        onLoadMore: () => loadMoreCalls++,
      ),
    );
    controller.jumpTo(0);
    await tester.pump();
    final afterRemoval = loadMoreCalls;

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(
      loadMoreCalls,
      afterRemoval,
      reason:
          'the sliver is gone; scrolling the controller it borrowed must not '
          'reach its onLoadMore any more',
    );
  });

  testWidgets('it follows the controller it is handed to a new one', (
    tester,
  ) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var loadMoreCalls = 0;

    await tester.pumpWidget(
      host(
        controller: first,
        withSliver: true,
        onLoadMore: () => loadMoreCalls++,
      ),
    );
    await tester.pumpWidget(
      host(
        controller: second,
        withSliver: true,
        onLoadMore: () => loadMoreCalls++,
      ),
    );

    second.jumpTo(second.position.maxScrollExtent);
    await tester.pump();

    expect(
      loadMoreCalls,
      greaterThan(0),
      reason: 'a rebuilt page hands over a new controller; the sliver has to '
          'rebind rather than keep listening to the old one',
    );
  });
}
