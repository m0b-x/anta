import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import 'category_editor_sheet.dart';

/// Bottom-sheet selector for an event category. Returns the selected
/// category **id** (`String`), or `null` if dismissed. Lists the live,
/// data-driven category set and offers an inline "create category" entry so
/// users can add a category without leaving the event editor.
class CategoryPickerSheet extends StatelessWidget {
  final String selectedId;

  const CategoryPickerSheet({super.key, required this.selectedId});

  static Future<String?> show(
    BuildContext context, {
    required String selectedId,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child: CategoryPickerSheet(selectedId: selectedId),
      ),
    );
  }

  Future<void> _createCategory(BuildContext context) async {
    final created = await CategoryEditorSheet.show(context);
    if (created == null || !context.mounted) return;
    Navigator.of(context).pop(created.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final categories = CalendarCategories.all;
    // `useSafeArea: true` on the modal route avoids the status bar but has
    // proven unreliable against the bottom gesture/nav bar on real devices
    // (the "Create category" row rendered under it) — same fix as
    // `EventEditorSheet` / `CategoryEditorSheet`: pad the list's bottom by
    // the larger of the keyboard inset and the system's bottom inset so the
    // last row always lands above both.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            l10n.eventType,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + bottomClearance),
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              if (index == categories.length) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.add_rounded),
                  ),
                  title: Text(l10n.createCategory),
                  onTap: () => _createCategory(context),
                );
              }
              final category = categories[index];
              final isSelected = category.id == selectedId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: category.color.withValues(alpha: 0.18),
                  foregroundColor: category.color,
                  child: Icon(
                    CalendarIcons.forKey(category.iconKey) ??
                        Icons.event_rounded,
                  ),
                ),
                title: Text(CalendarCategories.labelOf(category, l10n)),
                trailing: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                selected: isSelected,
                onTap: () => Navigator.of(context).pop(category.id),
              );
            },
          ),
        ),
      ],
    );
  }
}
