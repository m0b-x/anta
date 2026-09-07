import 'package:flutter/material.dart';

class InfiniteScrollSliver<T> extends StatefulWidget {
  final List<T> items;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final ScrollController controller;
  final double loadMoreThreshold;

  const InfiniteScrollSliver({
    super.key,
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.itemBuilder,
    required this.controller,
    this.loadMoreThreshold = 200.0,
  });

  @override
  State<InfiniteScrollSliver<T>> createState() =>
      _InfiniteScrollSliverState<T>();
}

class _InfiniteScrollSliverState<T> extends State<InfiniteScrollSliver<T>> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant InfiniteScrollSliver<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  /// The listener has to come off the controller the page owns: this sliver
  /// leaves the tree every time the bar swaps to search or selection, while
  /// the controller outlives it, so a listener left behind keeps asking a
  /// defunct element to load another page.
  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    if (!widget.controller.hasClients) return;

    final maxScroll = widget.controller.position.maxScrollExtent;
    final currentScroll = widget.controller.offset;

    if (maxScroll - currentScroll <= widget.loadMoreThreshold) {
      if (widget.hasMore && !widget.isLoadingMore) {
        widget.onLoadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index >= widget.items.length) {
          if (widget.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const SizedBox.shrink();
        }

        return widget.itemBuilder(context, widget.items[index], index);
      }, childCount: widget.items.length + (widget.hasMore ? 1 : 0)),
    );
  }
}
