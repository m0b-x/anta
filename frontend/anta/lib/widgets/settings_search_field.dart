import 'package:flutter/material.dart';

/// Compact search field used to filter long lists on settings pages.
///
/// Styled to match the note editor's search bar so search looks the same
/// everywhere in the app. Callers own the [controller] and decide when the
/// field is worth showing at all — see `AppConstants.listSearchThreshold`.
class SettingsSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const SettingsSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

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

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onTapOutside: (_) => _focusNode.unfocus(),
        style: TextStyle(fontSize: 14, color: colors.onSurface),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(
            color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            fontSize: 14,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(
              Icons.search_rounded,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          suffixIcon: hasText
              ? GestureDetector(
                  onTap: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }
}
