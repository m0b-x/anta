import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/category_service.dart';
import 'icon_picker_sheet.dart';

/// Curated swatch palette for categories. Stored as 32-bit ARGB ints so they
/// round-trip through SQLite and backup without a `Color` dependency.
const List<int> _categorySwatches = [
  0xFF1E88E5, // blue
  0xFF00ACC1, // cyan
  0xFF00897B, // teal
  0xFF43A047, // green
  0xFF7CB342, // light green
  0xFFC0CA33, // lime
  0xFFFDD835, // yellow
  0xFFFB8C00, // orange
  0xFFF4511E, // deep orange
  0xFFE53935, // red
  0xFFD81B60, // pink
  0xFFEC407A, // rose
  0xFF8E24AA, // purple
  0xFF5E35B1, // deep purple
  0xFF3949AB, // indigo
  0xFF6D4C41, // brown
  0xFF546E7A, // blue grey
  0xFF757575, // grey
];

const int _defaultCategoryColor = 0xFFFB8C00;
const String _defaultCategoryIconKey = 'event';

/// Bottom-sheet form for creating or editing a [CalendarCategory].
///
/// Persists through [CategoryService] and returns the saved category (or
/// `null` if cancelled). Built-in categories keep their localized name (the
/// name field is read-only) but their color and icon remain editable.
class CategoryEditorSheet extends StatefulWidget {
  final CalendarCategory? initial;

  const CategoryEditorSheet({super.key, this.initial});

  static Future<CalendarCategory?> show(
    BuildContext context, {
    CalendarCategory? initial,
  }) {
    return showModalBottomSheet<CalendarCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: CategoryEditorSheet(initial: initial),
      ),
    );
  }

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  late final TextEditingController _nameController;
  late int _colorValue;
  late String _iconKey;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;
  bool get _isBuiltIn => widget.initial?.isBuiltIn ?? false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _colorValue = initial?.colorValue ?? _defaultCategoryColor;
    _iconKey = initial?.iconKey ?? _defaultCategoryIconKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSave {
    if (_saving) return false;
    if (_isBuiltIn) return true; // name fixed/localized, always valid
    return _nameController.text.trim().isNotEmpty;
  }

  Future<void> _pickIcon() async {
    final picked = await IconPickerSheet.show(
      context,
      tint: Color(_colorValue),
      initialKey: _iconKey,
    );
    if (picked == null || !mounted) return;
    setState(() => _iconKey = picked);
  }

  Future<void> _onSave() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final service = await CategoryService.getInstance();
    CalendarCategory saved;
    final initial = widget.initial;
    if (initial == null) {
      saved = await service.create(
        name: _nameController.text.trim(),
        colorValue: _colorValue,
        iconKey: _iconKey,
      );
    } else {
      final updated = initial.copyWith(
        name: _isBuiltIn ? initial.name : _nameController.text.trim(),
        colorValue: _colorValue,
        iconKey: _iconKey,
      );
      await service.updateCategory(updated);
      saved = updated;
    }
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tint = Color(_colorValue);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;
    final builtInLabel = _isBuiltIn && widget.initial != null
        ? CalendarCategories.labelOf(widget.initial!, l10n)
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    _isEditing ? l10n.editCategory : l10n.createCategory,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton(
                    onPressed: _canSave ? _onSave : null,
                    child: Text(l10n.save),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Live preview of the category's avatar.
                  Center(
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: tint.withValues(alpha: 0.18),
                      foregroundColor: tint,
                      child: Icon(
                        CalendarIcons.forKey(_iconKey) ?? Icons.event_rounded,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isBuiltIn)
                    TextFormField(
                      key: const ValueKey('builtin-name'),
                      initialValue: builtInLabel,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: l10n.categoryName,
                        helperText: l10n.categoryDefault,
                        border: const OutlineInputBorder(),
                      ),
                    )
                  else
                    TextField(
                      controller: _nameController,
                      autofocus: !_isEditing,
                      maxLength: 40,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: l10n.categoryName,
                        hintText: l10n.categoryNameHint,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  _SectionLabel(text: l10n.iconLabel),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: tint.withValues(alpha: 0.18),
                        foregroundColor: tint,
                        child: Icon(
                          CalendarIcons.forKey(_iconKey) ?? Icons.event_rounded,
                        ),
                      ),
                      title: Text(l10n.pickIcon),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _pickIcon,
                    ),
                  ),
                  _SectionLabel(text: l10n.categoryColor),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final swatch in _categorySwatches)
                        _ColorSwatch(
                          color: Color(swatch),
                          selected: swatch == _colorValue,
                          onTap: () => setState(() => _colorValue = swatch),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: theme.colorScheme.onSurface, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}
