part of '../form_rows.dart';

abstract class FormDividedRow extends StatelessWidget {
  const FormDividedRow({super.key});

  double get dividerIndent;

  /// [dividerIndent] as drawn in [context]: a row whose leading narrows at a
  /// large text scale ([FormMeterRow.compactLeading]) moves its hairline
  /// with its text, which a context-free getter cannot know.
  double dividerIndentIn(BuildContext context) => dividerIndent;
}

class FormRowGroup extends StatelessWidget {
  final List<Widget> children;
  final bool trailingGap;

  const FormRowGroup({
    super.key,
    required this.children,
    this.trailingGap = true,
  });

  /// The hairline indent under [row]; with [context], the one it draws at
  /// that context's text scale ([FormDividedRow.dividerIndentIn]).
  static double indentOf(Widget row, [BuildContext? context]) =>
      row is FormDividedRow
      ? (context == null ? row.dividerIndent : row.dividerIndentIn(context))
      : FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: indentOf(children[i], context),
            endIndent: 0,
            color: colorScheme.rowDivider,
          ),
        );
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: trailingGap ? RowMetrics.groupGap : 0),
      child: Material(
        type: MaterialType.card,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.rowGroup,
        borderRadius: BorderRadius.circular(RowMetrics.groupRadius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// A row that is not one of the primitives — a description cell, a row
/// inside a `ValueChangeHighlight` — carrying the hairline indent the group
/// draws under it.
///
/// [FormRowGroup] reads the indent off a [FormDividedRow] and off nothing
/// else, so a wrapped row falls back to the glyph indent whatever the row
/// inside it says.
class FormIndentedRow extends FormDividedRow {
  final Widget child;

  @override
  final double dividerIndent;

  const FormIndentedRow({
    super.key,
    required this.dividerIndent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => child;
}

/// The colour strip as a row of a group — the Look sheet's row, hoisted in
/// Tier 3 (D13) so the category editor, the fasting style sheet and the
/// palette draw the one strip the same way: `ColorSwatchPicker` at the plain
/// indent inside the row's own air, under a node carrying [identifier].
///
/// That node is a container, never a merge: `AutomationId` would fold
/// eighteen colour buttons into one and leave a screen reader nothing to
/// pick. A driver finds the row by its id and each swatch by its name.
class FormSwatchRow extends FormDividedRow {
  final Widget child;
  final String? identifier;

  const FormSwatchRow({super.key, required this.child, this.identifier});

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset,
        FormMetrics.swatchRowTopPadding,
        RowMetrics.groupInset,
        FormMetrics.swatchRowBottomPadding,
      ),
      child: child,
    );
    if (identifier case final id?) {
      return Semantics(identifier: id, child: row);
    }
    return row;
  }
}

/// One row of a rounded group, drawn on its own — the row-at-a-time twin of
/// [FormRowGroup] for a list a `Column` cannot hold: a reorderable list, a
/// sliver. Same tokens, same hairline rule (under every row but the last, at
/// the child's own indent), the corners on the first and last rows only, so
/// a run of shells reads as one group.
///
/// Only the end rows are a clipped [Material]. A middle row has no corner to
/// round, so it paints flat and hosts its ink on a transparent [Material] —
/// a clip path per row is what a long list would otherwise pay for corners
/// that are never drawn (the browser's row shell reasons the same way).
class FormRowShell extends StatelessWidget {
  final bool first;
  final bool last;

  /// The air below the last row, [FormRowGroup]'s `trailingGap`.
  final bool trailingGap;

  final Widget child;

  const FormRowShell({
    super.key,
    required this.first,
    required this.last,
    required this.child,
    this.trailingGap = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = Radius.circular(RowMetrics.groupRadius);
    final borderRadius = BorderRadius.vertical(
      top: first ? radius : Radius.zero,
      bottom: last ? radius : Radius.zero,
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        if (!last)
          Divider(
            height: 1,
            thickness: 1,
            indent: FormRowGroup.indentOf(child, context),
            endIndent: 0,
            color: colorScheme.rowDivider,
          ),
      ],
    );
    final shell = first || last
        ? Material(
            type: MaterialType.card,
            clipBehavior: Clip.antiAlias,
            color: colorScheme.rowGroup,
            borderRadius: borderRadius,
            child: body,
          )
        : ColoredBox(
            color: colorScheme.rowGroup,
            child: Material(type: MaterialType.transparency, child: body),
          );
    if (!last || !trailingGap) return shell;
    return Padding(
      padding: const EdgeInsets.only(bottom: RowMetrics.groupGap),
      child: shell,
    );
  }
}
