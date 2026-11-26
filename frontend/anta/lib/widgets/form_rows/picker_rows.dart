part of '../form_rows.dart';

class FormPickerRow extends FormDividedRow {
  /// A 40 dp widget — an `EventAvatar` — standing where the glyph would,
  /// which gives the row the title row's 56 dp shape and, unless
  /// [dividerIndent] says otherwise, its divider indent. Wins over [glyph].
  final Widget? leading;
  final IconData? glyph;
  final Color? glyphColor;
  final String label;
  final String? value;
  final Widget? valueLeading;
  final Color? labelColor;
  final Color? valueColor;
  final VoidCallback? onTap;
  final FormTrailingButton? trailingButton;
  final bool showChevron;
  final String? semanticsLabel;
  final String? identifier;
  final bool subRow;

  /// A line of the row's own data under the pair — the dates after the
  /// next occurrence, never help text. It lives inside the row's ink well
  /// and semantics node, so the row stays one target and one announcement.
  final String? caption;

  /// Clamps a glyph row's [caption] like a value, ellipsizing past the limit
  /// — the fasting style's description read back at two lines, where a
  /// 500-character text would otherwise run the row to a paragraph. Null
  /// wraps freely. The stacked shape under a [leading] widget clamps at its
  /// own two lines when nothing is passed — its caption is the second line
  /// of a 62 dp row, not a line under a pair — and at one when a list that
  /// sizes its rows by kind asks for it.
  final int? captionMaxLines;

  /// Lets the stacked shape's caption under a [leading] widget wrap as far
  /// as it needs rather than clamp at [captionMaxLines] or its own two
  /// lines: a caption every word of which counts — the Single events
  /// sheet's time and the category it stays shared through — loses the
  /// time or the name to an ellipsis at German 2.0.
  final bool captionWraps;

  /// Gives a glyph row with a [caption] and no value [FormCheckRow]'s
  /// two-line shape — the label and the caption in one column on the check
  /// row's air, clamped at two lines while enabled and whole while disabled —
  /// so an action row in a sheet that otherwise lists check rows (the sync
  /// picker's spaces) keeps their height at every scale. The glyph centres
  /// against both lines.
  final bool checkRowShape;

  /// Keeps the label and the value on one line ([FormLabelValue.wrap]
  /// false), for a list that sizes its rows by kind — the overview's exact
  /// extents — where a row's height must never depend on its text.
  final bool singleLine;

  /// False draws the row at the disabled opacity — all but its [caption],
  /// which says why and stays readable — with no ink and no tap, and marks
  /// its one node disabled: a control the form has switched off, the
  /// shape `FormMenuRow` takes without a handler. A read row (the next
  /// occurrences) passes `onTap: null` instead and stays fully drawn, so a
  /// value the user cannot act on never looks like one they may not.
  final bool enabled;

  /// A [FormDragHandle] in a [FormMetrics.dragHandleSlot] target flush with
  /// the row's start — the shape [FormCheckRow.handle] gives a reorderable
  /// list's rows, for a list of picker rows (the palette's colours): a third
  /// node beside the row's own and its [trailingButton]. The row's content
  /// starts 4 dp past the slot, at [FormMetrics.dividerIndentGlyph]. With
  /// nothing before the label, the text starts there and the hairline indents
  /// to it, as on the saved filters' check rows. With a [leading] the text
  /// starts past the slot and the leading column, and the hairline takes the
  /// title indent ([FormMetrics.dividerIndentTitle]) as under any [leading]
  /// — the palette's rows.
  final Widget? handle;

  final double? _dividerIndent;

  const FormPickerRow({
    super.key,
    this.leading,
    this.glyph,
    this.glyphColor,
    required this.label,
    this.value,
    this.valueLeading,
    this.labelColor,
    this.valueColor,
    required this.onTap,
    this.trailingButton,
    this.showChevron = true,
    this.semanticsLabel,
    this.identifier,
    this.subRow = false,
    this.caption,
    this.captionMaxLines,
    this.captionWraps = false,
    this.checkRowShape = false,
    this.singleLine = false,
    this.enabled = true,
    this.handle,
    double? dividerIndent,
  }) : assert(
         !checkRowShape || (leading == null && value == null),
         'the check row shape is for a glyph row without a value',
       ),
       assert(
         !captionWraps || leading != null,
         'only the stacked shape under a leading widget clamps by default',
       ),
       _dividerIndent = dividerIndent;

  /// The glyph indent unless a caller sets one; the title indent under a
  /// [leading] widget, which is wider than a glyph.
  @override
  double get dividerIndent =>
      _dividerIndent ??
      (leading != null
          ? FormMetrics.dividerIndentTitle
          : FormMetrics.dividerIndentGlyph);

  @override
  Widget build(BuildContext context) {
    final button = trailingButton;
    final avatar = leading;
    final captionText = caption;
    final tap = enabled ? onTap : null;
    // A disabled row dims what it offers — the glyph, the label, the value,
    // the chevron — and keeps its caption whole: the caption is what says
    // why the row is off, and at 38 % it read at under 2:1.
    Widget dim(Widget child) => enabled
        ? child
        : Opacity(opacity: FormMetrics.disabledOpacity, child: child);
    final pair = FormLabelValue(
      label: label,
      value: value,
      valueLeading: valueLeading,
      labelColor: labelColor,
      valueColor: valueColor,
      wrap: !singleLine,
    );
    // Under a leading widget the caption joins the label in one column — the
    // check row's two-line shape — so the avatar centres against both lines
    // instead of sitting on the first with the caption hanging under it.
    // Under a glyph the caption stays a line below the pair: the glyph names
    // the field and belongs on the label line.
    final checkShaped = checkRowShape && captionText != null;
    final stacked = (avatar != null || checkShaped) && captionText != null;
    final text = checkShaped
        ? _CheckRowLines(
            label: dim(
              Text(
                label,
                style: FormLabelValue.labelStyle(
                  labelColor ?? Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            caption: captionText,
            enabled: enabled,
            captionMaxLines: captionMaxLines ?? 2,
          )
        : stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              dim(pair),
              FormCaption(
                text: captionText,
                maxLines: captionWraps ? null : captionMaxLines ?? 2,
                padding: const EdgeInsets.only(
                  bottom: FormMetrics.pairVerticalPadding,
                ),
              ),
            ],
          )
        : dim(pair);
    final content = Row(
      children: [
        if (avatar != null) ...[
          dim(
            SizedBox.square(
              dimension: FormMetrics.rowLeadingSize,
              child: Center(child: avatar),
            ),
          ),
          const SizedBox(width: FormMetrics.gap),
        ] else if (glyph case final icon?) ...[
          dim(FormGlyph(icon: icon, color: glyphColor)),
          const SizedBox(width: FormMetrics.gap),
        ],
        Expanded(child: text),
        if (button == null && showChevron) ...[
          const SizedBox(width: FormMetrics.gap),
          dim(const FormChevron()),
        ],
      ],
    );
    final dragHandle = handle;
    // Past a handle the content starts at the glyph column, 4 dp after the
    // 48 dp slot — the check row's rule; otherwise at the group inset, or the
    // sub-row inset for a row another row reveals.
    final leftInset = dragHandle != null
        ? FormMetrics.dividerIndentGlyph - FormMetrics.dragHandleSlot
        : avatar == null && glyph == null && subRow
        ? FormMetrics.subRowInset
        : RowMetrics.groupInset;
    final rightInset = button == null ? FormMetrics.rowEndPadding : 0.0;
    // The width of whatever stands before the label, so the caption below
    // can start where the label starts.
    final double leadingColumn = avatar != null
        ? FormMetrics.rowLeadingSize + FormMetrics.gap
        : glyph != null
        ? FormMetrics.glyphSize + FormMetrics.gap
        : 0;
    final line = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: stacked
            ? FormMetrics.twoLineRowMinHeight
            : avatar != null
            ? FormMetrics.titleRowMinHeight
            : FormMetrics.rowMinHeight,
      ),
      child: Padding(
        padding: EdgeInsets.only(left: leftInset, right: rightInset),
        child: content,
      ),
    );
    // The caption starts where the label starts, past the glyph column, so
    // it reads as the value's continuation and not as a second row.
    final body = captionText == null || stacked
        ? line
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              line,
              FormCaption(
                text: captionText,
                maxLines: captionMaxLines,
                padding: EdgeInsets.only(
                  left: leftInset + leadingColumn,
                  right: rightInset,
                  bottom: FormMetrics.rowCaptionBottomPadding,
                ),
              ),
            ],
          );
    Widget well = InkWell(onTap: tap, child: body);
    if (semanticsLabel != null) {
      well = Semantics(
        label: semanticsLabel,
        button: true,
        enabled: tap != null,
        onTap: tap,
        child: ExcludeSemantics(child: well),
      );
    } else if (!enabled) {
      // Inside the merge below, so the flag lands on the row's one node
      // beside its id and its label.
      well = Semantics(enabled: false, child: well);
    }
    if (identifier case final id?) {
      well = AutomationId(identifier: id, child: well);
    } else {
      // A row is one announcement — label, value, caption — whether or not
      // a driver needs an id on it (`AutomationId` merges for the ones that
      // do). The trailing button below stays a sibling, so a two-target row
      // keeps its second node.
      well = MergeSemantics(child: well);
    }
    if (button == null && dragHandle == null) return well;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ?dragHandle,
        Expanded(child: well),
        ?button,
      ],
    );
  }
}

/// `[glyph] label / caption ⟷` — a two-line picker row with a switch of its
/// own at the end: the tap edits the thing (opens its sheet), the switch
/// turns it on or off in place. A category's alerts and the Alerts hub's
/// digests are lists of such things, and one shape keeps them reading alike.
///
/// Two nodes, never one: the row's (label and caption, a button) and the
/// switch's, named [label] so a screen reader says what it switches. The
/// switch keeps its padded 48 dp target, a sibling of the row's ink well.
/// While [value] is off and [dimOff] is set, the text and glyph dim to
/// [FormMetrics.switchedOffOpacity] — off, not disabled, so the switch stays
/// full; a null [onChanged] disables the switch alone, in place.
///
/// With a null [onTap] there is nothing to open: the row's tap flips the
/// switch and the row is one node, read as a [FormSwitchRow] is (a shared
/// built-in category in the received list). [enabled] false dims the whole
/// text part, caption included — the reason a row is off is its group's
/// caption, never the row's.
class FormPickerSwitchRow extends FormDividedRow {
  /// The field's glyph, or [leading] in its place; exactly one of the two.
  final IconData? glyph;

  /// A 40 dp widget — an `EventAvatar` — standing where the glyph would,
  /// which gives the row the stacked two-line shape and the title row's
  /// divider indent.
  final Widget? leading;
  final String label;
  final String caption;
  final int? captionMaxLines;
  final bool value;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onChanged;
  final bool dimOff;

  /// The row's id; with a null [onTap] the one node takes [switchIdentifier]
  /// and this only when that is null.
  final String? identifier;
  final String? switchIdentifier;

  /// The switch node's name in the two-node shape, where [label] alone
  /// would not say what it switches ("Show Night shift on my calendar").
  /// Null names it [label].
  final String? switchSemanticsLabel;

  /// False makes the row and its switch inert in place, drawn at
  /// [FormMetrics.disabledOpacity] — the text part only, the switch in
  /// Material's own disabled colours.
  final bool enabled;

  const FormPickerSwitchRow({
    super.key,
    this.glyph,
    this.leading,
    required this.label,
    required this.caption,
    this.captionMaxLines,
    required this.value,
    required this.onTap,
    required this.onChanged,
    this.dimOff = false,
    this.identifier,
    this.switchIdentifier,
    this.switchSemanticsLabel,
    this.enabled = true,
  }) : assert(
         (glyph == null) != (leading == null),
         'a picker switch row leads with a glyph or a widget, never both',
       );

  @override
  double get dividerIndent => leading != null
      ? FormMetrics.dividerIndentTitle
      : FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final changed = enabled ? onChanged : null;
    final oneNode = onTap == null;
    final VoidCallback? tap = !enabled
        ? null
        : oneNode
        ? (changed == null ? null : () => changed(!value))
        : onTap;
    Widget row = FormPickerRow(
      glyph: glyph,
      leading: leading,
      label: label,
      caption: caption,
      captionMaxLines: captionMaxLines,
      identifier: oneNode ? null : identifier,
      showChevron: false,
      onTap: tap,
    );
    if (!enabled) {
      // Outside the row's own merge, so the flag lands on its node; the
      // opacity covers the caption, which the row's own `enabled` keeps whole.
      row = MergeSemantics(
        child: Semantics(
          enabled: false,
          child: Opacity(opacity: FormMetrics.disabledOpacity, child: row),
        ),
      );
    } else if (dimOff && !value) {
      row = Opacity(opacity: FormMetrics.switchedOffOpacity, child: row);
    }
    final Widget toggle = Switch(
      value: value,
      onChanged: changed,
      // A target of its own beside the row's, so the full 48 dp.
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    if (oneNode) {
      final content = Row(
        children: [
          Expanded(child: row),
          toggle,
          const SizedBox(width: FormMetrics.rowEndPadding),
        ],
      );
      if (switchIdentifier ?? identifier case final id?) {
        return AutomationId(identifier: id, child: content);
      }
      return MergeSemantics(child: content);
    }
    Widget named = Semantics(
      label: switchSemanticsLabel ?? label,
      child: toggle,
    );
    if (switchIdentifier case final id?) {
      named = AutomationId(identifier: id, child: named);
    }
    return Row(
      children: [
        Expanded(child: row),
        named,
        const SizedBox(width: FormMetrics.rowEndPadding),
      ],
    );
  }
}

/// `label … value ›` opening a menu of [items] — the editor's Priority and
/// Day rail, the filter sheet's Repeat and Time of day.
///
/// A popup route in the header menus' anatomy ([FormMenuChoiceItem]), never a
/// `MenuAnchor`, whose items expose no semantics nodes on iOS. The menu is
/// right-aligned with the group and opens under the row, or above it when
/// there is no room below; focus is dropped before it opens, or the route's
/// return would hand focus back to a field and raise the keyboard.
class FormMenuRow<T> extends FormDividedRow {
  final IconData glyph;
  final String label;
  final String value;
  final T selected;
  final List<FormMenuItem<T>> items;

  /// Null draws the row disabled — 38 %, no ink, no tap, its node marked so
  /// — and the menu never opens: the agenda's Fasting rows while the fasting
  /// calendar is off, kept in place with its stored value rather than
  /// dropped, so nothing under it moves between two openings.
  final ValueChanged<T>? onSelected;
  final double menuWidth;
  final String? identifier;

  /// The [FormPickerRow.caption] of the row it builds — what Auto resolves
  /// to, a disabled row's reason — kept at full strength while the rest of
  /// a disabled row dims, since it is the line that explains the state.
  final String? caption;
  final int? captionMaxLines;

  const FormMenuRow({
    super.key,
    required this.glyph,
    required this.label,
    required this.value,
    required this.selected,
    required this.items,
    required this.onSelected,
    required this.menuWidth,
    this.identifier,
    this.caption,
    this.captionMaxLines,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    // A `Builder` so the tap has the row's own render box to anchor to.
    return Builder(
      builder: (rowContext) => FormPickerRow(
        glyph: glyph,
        label: label,
        value: value,
        identifier: identifier,
        caption: caption,
        captionMaxLines: captionMaxLines,
        enabled: onSelected != null,
        onTap: () => _open(rowContext),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final select = onSelected;
    if (select == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showFormMenu<T>(
      context,
      items: items,
      selected: selected,
      menuWidth: menuWidth,
    );
    if (picked == null) return;
    select(picked);
  }
}
