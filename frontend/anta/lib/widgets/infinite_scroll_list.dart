import 'package:flutter/material.dart';

class InfiniteScrollList<T> extends StatefulWidget {
  final List<T> items;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget? emptyWidget;
  final Widget? loadingWidget;
  final double loadMoreThreshold;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final bool shrinkWrap;

  const InfiniteScrollList({
    super.key,
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.itemBuilder,
    this.emptyWidget,
    this.loadingWidget,
    this.loadMoreThreshold = 200.0,
    this.padding,
    this.controller,
    this.shrinkWrap = false,
  });

  @override
  State<InfiniteScrollList<T>> createState() => _InfiniteScrollListState<T>();
}

class _InfiniteScrollListState<T> extends State<InfiniteScrollList<T>> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;

    if (maxScroll - currentScroll <= widget.loadMoreThreshold) {
      if (widget.hasMore && !widget.isLoadingMore) {
        widget.onLoadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty && !widget.isLoadingMore) {
      return widget.emptyWidget ?? const SizedBox.shrink();
    }

    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= widget.items.length) {
          return _buildLoadingIndicator();
        }

        return widget.itemBuilder(context, widget.items[index], index);
      },
    );
  }

  Widget _buildLoadingIndicator() {
    if (!widget.isLoadingMore && !widget.hasMore) {
      return const SizedBox.shrink();
    }

    return widget.loadingWidget ??
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        );
  }
}

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

  void _onScroll() {
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

class PaginationInfo extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int displayedCount;

  const PaginationInfo({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.displayedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$displayedCount / $totalCount',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (totalPages > 1)
            Text(
              'Page $currentPage of $totalPages',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
