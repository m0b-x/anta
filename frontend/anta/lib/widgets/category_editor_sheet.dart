import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/category_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/custom_snackbar.dart';
import 'color_swatch_picker.dart';
import 'icon_picker_sheet.dart';

const int _defaultCategoryColor = 0xFFFB8C00;
const String _defaultCategoryIconKey = 'event';

/// Bottom-sheet form for creating or editing a [CalendarCategory].
///
/// Persists through [CategoryService] and returns the saved category (or
/// `null` if cancelled). Built-in categories keep their localized name (the
/// name field is read-only) but their color and icon remain editable.
class CategoryEditorSheet extends StatefulWidget {
  final CalendarCategory? initial;

  /// Prefills the name field when creating. The category picker passes what
  /// the user typed into its search field, so "no match" flows straight into
  /// creating the thing they were looking for. Ignored when [initial] is set.
  final String? initialName;

  const CategoryEditorSheet({super.key, this.initial, this.initialName});

  static Future<CalendarCategory?> show(
    BuildContext context, {
    CalendarCategory? initial,
    String? initialName,
  }) {
    return showModalBottomSheet<CalendarCategory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: CategoryEditorSheet(initial: initial, initialName: initialName),
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

  /// Memo behind [_duplicateOf]: the folded term it last scanned for, the
  /// catalog revision and locale it scanned under, and what it found.
  String? _duplicateTerm;
  int _duplicateRevision = -1;
  String? _duplicateLocale;
  CalendarCategory? _duplicate;

  bool get _isEditing => widget.initial != null;
  bool get _isBuiltIn => widget.initial?.isBuiltIn ?? false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(
      text: initial?.name ?? widget.initialName ?? '',
    );
    _colorValue = initial?.colorValue ?? _defaultCategoryColor;
    _iconKey = initial?.iconKey ?? _defaultCategoryIconKey;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The existing category whose name folds equal to what has been typed, if
  /// there is one.
  ///
  /// A **soft** guard: near-duplicates are how a category set rots on the way
  /// to forty entries, and a hidden duplicate is usually where a user first
  /// learns hiding exists. It never blocks Save — a custom *Cardio* beside the
  /// built-in one may be exactly what someone wants.
  ///
  /// Memoized on the folded text and the catalog revision, because `build`
  /// runs on every keystroke *and* on every colour tap and icon pick, and the
  /// scan folds two strings per category over the whole set. The revision is
  /// what keeps a category created from another sheet from going unnoticed.
  CalendarCategory? _duplicateOf(AppLocalizations l10n) {
    if (_isBuiltIn) return null;
    final typed = normalizeForSearch(_nameController.text.trim());
    final revision = CalendarCategories.revision;
    if (typed == _duplicateTerm &&
        revision == _duplicateRevision &&
        l10n.localeName == _duplicateLocale) {
      return _duplicate;
    }
    _duplicateTerm = typed;
    _duplicateRevision = revision;
    _duplicateLocale = l10n.localeName;
    _duplicate = typed.isEmpty ? null : _scanForDuplicate(typed, l10n);
    return _duplicate;
  }

  CalendarCategory? _scanForDuplicate(String typed, AppLocalizations l10n) {
    final selfId = widget.initial?.id;
    for (final category in CalendarCategories.all) {
      if (category.id == selfId) continue;
      final label = normalizeForSearch(
        CalendarCategories.labelOf(category, l10n),
      );
      if (label == typed || normalizeForSearch(category.name) == typed) {
        return category;
      }
    }
    return null;
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

  /// Persists and pops with the saved category.
  ///
  /// The failure path is the point of the `try`: `_saving` gates Save, so a
  /// throw that escaped here would leave the button disabled for the life of
  /// the sheet with nothing said and the edit unsaved — and the error would
  /// surface as an unhandled async error rather than as anything the user can
  /// act on. Everything else in this subsystem that fires a write from a
  /// callback goes through the categories page's `_guarded`; this is that
  /// wrapper's counterpart for the one write the sheet owns.
  Future<void> _onSave() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
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
    } catch (e) {
      debugPrint('[CategoryEditorSheet] Save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      CustomSnackbar.showError(context, l10n.categorySaveFailed);
    }
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
    final duplicate = _duplicateOf(l10n);
    final duplicateWarning = duplicate == null
        ? null
        : (duplicate.isHidden
              ? l10n.categoryNameExistsHidden(
                  CalendarCategories.labelOf(duplicate, l10n),
                )
              : l10n.categoryNameExists(
                  CalendarCategories.labelOf(duplicate, l10n),
                ));

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
                        helperText: duplicateWarning,
                        helperMaxLines: 2,
                        helperStyle: TextStyle(
                          color: theme.colorScheme.tertiary,
                        ),
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
                  // No "default" dot: a category *is* the colour everything
                  // else falls back to, so there is nothing behind it to
                  // inherit.
                  ColorSwatchPicker(
                    value: _colorValue,
                    onChanged: (value) =>
                        setState(() => _colorValue = value ?? _colorValue),
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
