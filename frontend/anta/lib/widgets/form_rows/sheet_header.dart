part of '../form_rows.dart';

class FormSheetHandle extends StatelessWidget {
  final bool showHandle;

  const FormSheetHandle({super.key, this.showHandle = true});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: FormMetrics.handleStripHeight,
      child: showHandle
          ? Center(
              child: Container(
                width: FormMetrics.handleWidth,
                height: FormMetrics.handleHeight,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(
                    FormMetrics.handleHeight / 2,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class FormSheetHeader extends StatelessWidget {
  final IconData leadingIcon;
  final String leadingTooltip;

  /// Null disables the ✕ in place, never hides it: a sheet mid-write (the
  /// delete sheet's Delete) refuses to be left until the write answers.
  final VoidCallback? onLeading;
  final String title;
  final Widget trailing;

  final double trailingInset;

  /// Whether the body has scrolled under the header, which draws the
  /// hairline along its bottom edge — a sheet's [FormHeaderHairline.scrolled].
  final ValueListenable<bool>? scrolled;

  final String? leadingIdentifier;

  /// Whether the title takes a line of its own under the ✕ and the action
  /// whenever it would not fit whole beside them, instead of ellipsizing.
  /// Decided by measuring, not by a scale threshold: Android grows the
  /// 17 px title less than the setting says (1.23× at "1.3"), and a German
  /// title was already cut at the common settings. Opt-in: the language's
  /// header is one 48 dp row at every scale, which the sub-sheets'
  /// large-text suites pin; the event editor opts in because its two-word
  /// title was cut to "Ereigni…".
  final bool stackTitleAtLargeText;

  /// Whether the title is the sheet's level-1 heading, for a sheet whose
  /// title is all a screen reader is told of whose it is (the read sheet's
  /// "From {name}"). Opt-in, so every other sheet's tree stays as it was.
  final bool titleIsHeading;

  const FormSheetHeader({
    super.key,
    required this.leadingIcon,
    required this.leadingTooltip,
    required this.onLeading,
    required this.title,
    required this.trailing,
    this.trailingInset = 12,
    this.scrolled,
    this.leadingIdentifier,
    this.stackTitleAtLargeText = false,
    this.titleIsHeading = false,
  });

  /// The one-row title as a heading node of its own when [titleIsHeading]
  /// asks; untouched otherwise.
  Widget _headingOf(Widget title) => titleIsHeading
      ? Semantics(container: true, header: true, headingLevel: 1, child: title)
      : title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Widget leading = IconButton(
      tooltip: leadingTooltip,
      icon: Icon(leadingIcon),
      color: colorScheme.onSurfaceVariant,
      onPressed: onLeading,
    );
    if (leadingIdentifier case final id?) {
      leading = AutomationId(identifier: id, child: leading);
    }
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: FormMetrics.headerTitleSize,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurface,
    );
    final Widget row;
    if (!stackTitleAtLargeText) {
      row = SizedBox(
        height: FormMetrics.headerHeight,
        child: Padding(
          padding: EdgeInsets.only(left: 4, right: trailingInset),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                leading,
                const SizedBox(width: 4),
                Expanded(
                  child: _headingOf(
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth:
                        constraints.maxWidth * FormMetrics.headerActionMaxShare,
                  ),
                  child: trailing,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // The stacked layout puts the action above the title, so the reading
      // order is set rather than left to geometry: ✕, title, action, as in
      // the one-row header. Each piece is one node, its key on that node.
      row = _StackingHeaderLayout(
        trailingInset: trailingInset,
        textDirection: Directionality.of(context),
        leading: MergeSemantics(
          child: Semantics(sortKey: const OrdinalSortKey(0), child: leading),
        ),
        title: Semantics(
          container: true,
          sortKey: const OrdinalSortKey(1),
          header: titleIsHeading ? true : null,
          headingLevel: titleIsHeading ? 1 : null,
          child: Text(
            title,
            maxLines: FormMetrics.headerTitleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        action: MergeSemantics(
          child: Semantics(sortKey: const OrdinalSortKey(2), child: trailing),
        ),
      );
    }
    final listenable = scrolled;
    if (listenable == null) return row;
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: listenable,
            builder: (context, isScrolled, _) => IgnorePointer(
              child: Container(
                height: 1,
                color: isScrolled ? colorScheme.rowDivider : Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _HeaderSlot { leading, title, action }

/// The opted-in header's layout (`FormSheetHeader.stackTitleAtLargeText`):
/// ✕, title and action on one 48 dp row while the title fits whole in the
/// room the ✕ and the action leave it; otherwise the ✕ and the action alone
/// on that row and the title under them at the form's inset, the way
/// Material's large top app bar sets its headline under the actions.
///
/// A render object rather than widgets because the decision needs the
/// action's laid-out width, and making it here costs no second frame.
class _StackingHeaderLayout
    extends SlottedMultiChildRenderObjectWidget<_HeaderSlot, RenderBox> {
  final Widget leading;
  final Widget title;
  final Widget action;
  final double trailingInset;
  final TextDirection textDirection;

  const _StackingHeaderLayout({
    required this.leading,
    required this.title,
    required this.action,
    required this.trailingInset,
    required this.textDirection,
  });

  @override
  Iterable<_HeaderSlot> get slots => _HeaderSlot.values;

  @override
  Widget childForSlot(_HeaderSlot slot) => switch (slot) {
    _HeaderSlot.leading => leading,
    _HeaderSlot.title => title,
    _HeaderSlot.action => action,
  };

  @override
  _RenderStackingHeader createRenderObject(BuildContext context) {
    return _RenderStackingHeader(
      trailingInset: trailingInset,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStackingHeader renderObject,
  ) {
    renderObject
      ..trailingInset = trailingInset
      ..textDirection = textDirection;
  }
}

class _RenderStackingHeader extends RenderBox
    with SlottedContainerRenderObjectMixin<_HeaderSlot, RenderBox> {
  /// The one-row header's insets: 4 before the ✕ and 4 between it and the
  /// title.
  static const double _leadingInset = 4;
  static const double _gap = 4;

  /// Room left so a title measured to fit exactly is not cut by the
  /// engine's own rounding.
  static const double _fitMargin = 0.5;

  double _trailingInset;
  TextDirection _textDirection;

  _RenderStackingHeader({
    required double trailingInset,
    required TextDirection textDirection,
  }) : _trailingInset = trailingInset,
       _textDirection = textDirection;

  set trailingInset(double value) {
    if (value == _trailingInset) return;
    _trailingInset = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _leading => childForSlot(_HeaderSlot.leading)!;
  RenderBox get _title => childForSlot(_HeaderSlot.title)!;
  RenderBox get _action => childForSlot(_HeaderSlot.action)!;

  /// Lays the three pieces out for [width] through [layoutChild] and
  /// returns the header's height with each piece's start-edge offset; the
  /// dry and the real layout share it.
  ({double height, Offset leading, Offset title, Offset action}) _arrange(
    double width,
    Size Function(RenderBox child, BoxConstraints constraints) layoutChild,
  ) {
    const rowHeight = FormMetrics.headerHeight;
    final inner = math.max(0.0, width - _leadingInset - _trailingInset);
    final leading = layoutChild(
      _leading,
      const BoxConstraints(maxHeight: rowHeight),
    );
    final action = layoutChild(
      _action,
      BoxConstraints(
        maxWidth: inner * FormMetrics.headerActionMaxShare,
        maxHeight: rowHeight,
      ),
    );
    final slot = inner - leading.width - _gap - action.width;
    final leadingAt = Offset(_leadingInset, (rowHeight - leading.height) / 2);
    final actionAt = Offset(
      width - _trailingInset - action.width,
      (rowHeight - action.height) / 2,
    );
    if (_title.getMaxIntrinsicWidth(double.infinity) + _fitMargin <= slot) {
      final title = layoutChild(
        _title,
        BoxConstraints(minWidth: slot, maxWidth: slot, maxHeight: rowHeight),
      );
      return (
        height: rowHeight,
        leading: leadingAt,
        title: Offset(
          _leadingInset + leading.width + _gap,
          (rowHeight - title.height) / 2,
        ),
        action: actionAt,
      );
    }
    final titleWidth = math.max(
      0.0,
      width - RowMetrics.groupInset - _trailingInset,
    );
    final title = layoutChild(
      _title,
      BoxConstraints(minWidth: titleWidth, maxWidth: titleWidth),
    );
    return (
      height:
          rowHeight +
          title.height +
          FormMetrics.headerStackedTitleBottomPadding,
      leading: leadingAt,
      title: const Offset(RowMetrics.groupInset, rowHeight),
      action: actionAt,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final arranged = _arrange(
      width,
      (child, childConstraints) => child.getDryLayout(childConstraints),
    );
    return constraints.constrain(Size(width, arranged.height));
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final arranged = _arrange(width, (child, childConstraints) {
      child.layout(childConstraints, parentUsesSize: true);
      return child.size;
    });
    void place(RenderBox child, Offset start) {
      final x = switch (_textDirection) {
        TextDirection.ltr => start.dx,
        TextDirection.rtl => width - start.dx - child.size.width,
      };
      (child.parentData! as BoxParentData).offset = Offset(x, start.dy);
    }

    place(_leading, arranged.leading);
    place(_title, arranged.title);
    place(_action, arranged.action);
    size = constraints.constrain(Size(width, arranged.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      final parentData = child.parentData! as BoxParentData;
      context.paintChild(child, offset + parentData.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final parentData = child.parentData! as BoxParentData;
      final hit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}

/// Whether a sheet's body has scrolled under its header — what draws the
/// hairline of [FormSheetHeader.scrolled].
///
/// The sheet's state owns one, wraps its scroll view in [watch], hands
/// [scrolled] to the header and disposes it. A notifier, never `setState`:
/// a scroll frame rebuilds a 1 px line and not the rows.
///
/// It follows the body's scroll notifications and its metrics, and the
/// metrics are the point. A scroll view whose content gets shorter under it
/// — the keyboard going down over a body that no longer needs to scroll —
/// corrects its offset without telling a scroll controller's listeners, so
/// a hairline fed by a listener alone stayed on over a body at its top.
class FormHeaderHairline {
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);

  /// True while content of the body lies above its top edge.
  ValueListenable<bool> get scrolled => _scrolled;

  /// [child], the sheet's scroll view, reporting its position here.
  Widget watch({required Widget child}) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) =>
          _report(notification.depth, notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) =>
            _report(notification.depth, notification.metrics),
        child: child,
      ),
    );
  }

  /// Depth 0 and vertical is the body itself: a text field inside it reports
  /// one level down, a strip of chips sideways.
  bool _report(int depth, ScrollMetrics metrics) {
    if (depth == 0 && metrics.axis == Axis.vertical) {
      _scrolled.value = metrics.extentBefore > 0;
    }
    return false;
  }

  void dispose() => _scrolled.dispose();
}

/// The header's trailing text action: a sub-sheet's Done, the detail
/// sheet's Edit. One widget rather than three hand-rolled `TextButton`s so
/// the sheets in the detail loop share one size, one weight and one inset;
/// the filled button stays the editor's alone, because it is the commit.
class FormHeaderTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final String? identifier;

  /// The button's accessible name where [label] is too short to stand alone
  /// — the ring screen's "Keep" beside the sentence that says what is kept,
  /// which a screen reader reaches as a button on its own. Replaces [label]
  /// in the node and draws nothing.
  final String? semanticsLabel;

  /// The label's colour role while enabled — `error` for a destructive
  /// commit (the delete sheet's Delete); `primary` when null. Disabled
  /// draws the theme's disabled colour whatever this says.
  final Color? color;

  const FormHeaderTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.identifier,
    this.semanticsLabel,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final name = semanticsLabel;
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? theme.colorScheme.primary,
        minimumSize: const Size(0, FormMetrics.headerHeight),
        padding: FormMetrics.headerActionPadding,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: FormMetrics.headerActionFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: name == null
          ? text
          : Semantics(
              label: name,
              child: ExcludeSemantics(child: text),
            ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: button);
    }
    return button;
  }
}
