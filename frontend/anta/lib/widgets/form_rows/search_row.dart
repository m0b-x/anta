part of '../form_rows.dart';

/// A search field as the first row of a group — a searchable sub-sheet's
/// first row, a filler's pinned one. It stands in for `SettingsSearchField`
/// only inside a form group; the settings pages keep theirs.
///
/// Never autofocused: a sheet that opens with the keyboard up hides the list
/// it exists to show. The clear button is a sibling target that always has a
/// slot, so the field's width never changes as text comes and goes.
class FormSearchRow extends FormDividedRow {
  final TextEditingController controller;
  final String hint;

  /// The clear button's tooltip — passed in like every other label here, so
  /// the primitives stay free of the localizations.
  final String clearTooltip;
  final ValueChanged<String> onChanged;

  /// Lands on the field's own text-field node, which is what a device script
  /// types into by id.
  final String? identifier;

  /// For a caller that reveals the row and focuses it (the overview's search
  /// button); the row itself never autofocuses.
  final FocusNode? focusNode;

  const FormSearchRow({
    super.key,
    required this.controller,
    required this.hint,
    required this.clearTooltip,
    required this.onChanged,
    this.identifier,
    this.focusNode,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TextStyle(
      fontSize: FormMetrics.labelSize,
      height: 20 / FormMetrics.labelSize,
      color: colorScheme.onSurface,
    );
    Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: false,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      style: textStyle,
      // Collapsed, but padded to the row's height: a bare collapsed field is
      // its 20 px line, and a thumb landing in the row's other 28 px focused
      // nothing.
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        contentPadding: FormMetrics.searchFieldPadding,
        hintText: hint,
        // `onSurfaceVariant`, never `outline`: the latter is under AA for
        // text on `surface`.
        hintStyle: textStyle.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      // A tap on the rows below drops the keyboard, so the list being ticked
      // is not left half-covered by it.
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onChanged: onChanged,
    );
    // The visible hint names the field only while it is empty; once a query
    // replaces it the label keeps the name — only then, or TalkBack would say
    // it twice.
    field = ListenableBuilder(
      listenable: controller,
      builder: (context, field) => MergeSemantics(
        child: Semantics(
          label: controller.text.isEmpty ? null : hint,
          child: field,
        ),
      ),
      child: field,
    );
    if (identifier case final id?) {
      field = AutomationId(identifier: id, child: field);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(left: RowMetrics.groupInset),
        child: Row(
          children: [
            const FormGlyph(icon: Icons.search_rounded),
            const SizedBox(width: FormMetrics.gap),
            Expanded(child: field),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => controller.text.isEmpty
                  ? const SizedBox.square(
                      dimension: FormMetrics.trailingButtonSize,
                    )
                  : FormTrailingButton(
                      icon: Icons.close_rounded,
                      tooltip: clearTooltip,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
