import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/category_service.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/category_editor_sheet.dart';
import '../widgets/unified_app_bars.dart';

/// Management page for event categories. Lists the built-in and user-created
/// categories, and lets the user create, edit (color/icon, plus name for
/// customs) and delete custom categories. Built-ins cannot be deleted.
///
/// Mutations go directly through [CategoryService] (the same service-direct
/// pattern the holiday settings use); the in-memory [CalendarCategories] cache
/// is updated by the service, so the calendar reflects changes once the user
/// returns to it.
class CalendarCategoriesPage extends StatefulWidget {
  const CalendarCategoriesPage({super.key});

  @override
  State<CalendarCategoriesPage> createState() => _CalendarCategoriesPageState();
}

class _CalendarCategoriesPageState extends State<CalendarCategoriesPage> {
  CategoryService? _service;
  List<CalendarCategory> _categories = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await CategoryService.getInstance();
    if (!mounted) return;
    setState(() {
      _service = service;
      _categories = service.categories;
      _isLoading = false;
    });
  }

  void _refresh() {
    final service = _service;
    if (service == null) return;
    setState(() => _categories = service.categories);
  }

  Future<void> _create() async {
    final created = await CategoryEditorSheet.show(context);
    if (created == null || !mounted) return;
    _refresh();
  }

  Future<void> _edit(CalendarCategory category) async {
    final updated = await CategoryEditorSheet.show(context, initial: category);
    if (updated == null || !mounted) return;
    _refresh();
  }

  Future<void> _delete(CalendarCategory category) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteCategory,
      content: l10n.deleteCategoryConfirm(category.name),
      confirmText: l10n.delete,
      icon: Icons.delete_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _service?.deleteCategory(category.id);
    if (!mounted) return;
    _refresh();
    CustomSnackbar.showSuccess(context, l10n.categoryDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SettingsAppBar(
        title: l10n.calendarCategories,
        showMenuButton: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.createCategory),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final category = _categories[index];
                return Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainer,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: category.color.withValues(alpha: 0.18),
                      foregroundColor: category.color,
                      child: Icon(
                        CalendarIcons.forKey(category.iconKey) ??
                            Icons.event_rounded,
                      ),
                    ),
                    title: Text(CalendarCategories.labelOf(category, l10n)),
                    subtitle: category.isBuiltIn
                        ? Text(l10n.categoryDefault)
                        : null,
                    trailing: category.isBuiltIn
                        ? const Icon(Icons.chevron_right_rounded)
                        : IconButton(
                            tooltip: l10n.deleteCategory,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: theme.colorScheme.error,
                            ),
                            onPressed: () => _delete(category),
                          ),
                    onTap: () => _edit(category),
                  ),
                );
              },
            ),
    );
  }
}
