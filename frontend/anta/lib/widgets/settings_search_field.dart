import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import 'automation_id.dart';
import 'form_rows.dart';

/// The search field used to filter long lists on settings pages: a 48 dp
/// target that grows with the text, its clear button a labelled 48 dp
/// button with an id of its own. Callers own the [controller] and decide
/// when the field is worth showing at all — see
/// `AppConstants.listSearchThreshold`.
class SettingsSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  /// The `SemanticsIds` value a device script types into. Every page shares
  /// the default today; a page that needs its own passes it.
  final String identifier;

  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.identifier = SemanticsIds.settingsSearch,
  });

  /// The height the field lays out at under [context]'s text scale, for a
  /// host that pins it in a fixed-extent header (Markdown shortcuts): its
  /// text line plus the air that makes 48 dp at 1.0, never under 48.
  static double heightFor(BuildContext context) {
    final line =
        MediaQuery.textScalerOf(context).scale(FormMetrics.labelSize) *
        FormMetrics.labelLineHeight /
        FormMetrics.labelSize;
    return math.max(
      FormMetrics.rowMinHeight,
      line + FormMetrics.searchFieldPadding.vertical,
    );
  }

  @override
  State<SettingsSearchField> createState() => _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends State<SettingsSearchField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.isNotEmpty;
    final textStyle = TextStyle(
      fontSize: FormMetrics.labelSize,
      height: FormMetrics.labelLineHeight / FormMetrics.labelSize,
      color: colors.onSurface,
    );

    // 48 dp at 1.0 and the text's own line plus the same air above it: a
    // fixed box clipped the text at 2.0. The field is padded to the box's
    // height so a tap anywhere in it focuses the field.
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surfaceContainerLow,
        shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
        child: Padding(
          // While empty the hint runs to the end, so it keeps the start's
          // inset there; the clear button brings its own.
          padding: EdgeInsetsDirectional.only(
            start: RowMetrics.groupInset,
            end: hasText ? 0 : RowMetrics.groupInset,
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: FormMetrics.glyphSize,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: AutomationId(
                  identifier: widget.identifier,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    onTapOutside: (_) => _focusNode.unfocus(),
                    style: textStyle,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: FormMetrics.searchFieldPadding,
                      hintText: widget.hint,
                      // `onSurfaceVariant` at full strength: the old 60 %
                      // read 3.05:1 in light, under AA.
                      hintStyle: textStyle.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                      widget.onChanged(value);
                    },
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                  ),
                ),
              ),
              // No slot while empty: the hint takes the whole width, which
              // "Einstellungen suchen" needs at 2.0 on a small phone. The
              // first letter shrinks the field from its end, away from the
              // caret, so nothing typed moves.
              if (hasText)
                FormTrailingButton(
                  icon: Icons.close_rounded,
                  tooltip: AppLocalizations.of(context)!.clearSearch,
                  color: colors.onSurfaceVariant,
                  identifier: SemanticsIds.settingsSearchClear,
                  onPressed: () {
                    widget.controller.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
