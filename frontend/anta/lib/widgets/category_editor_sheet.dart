import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/category_name.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/category_service.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import 'color_swatch_picker.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'icon_picker_sheet.dart';
import 'overlay_snackbar.dart';

const int _defaultCategoryColor = 0xFFFB8C00;
const String _defaultCategoryIconKey = 'event';

/// The form for creating or editing a [CalendarCategory]: a sub-sheet of the
/// UI language (Tier 3, D12) in the quick alarm's shape — ✕ · title · Save
/// over one group of the name, an Icon row and the colour strip.
///
/// Persists through [CategoryService] inside the sheet and returns the saved
/// category, or `null` when dismissed. The row is written before the pop
/// because the callers rely on it: the categories page refreshes from the
/// service, the picker ticks the returned id. A built-in keeps its stored
/// name — its localized label is a read row — while its colour and icon stay
/// editable. Unguarded, as every sub-sheet: a draft is three taps to redo.
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
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<CalendarCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: CategoryEditorSheet(initial: initial, initialName: initialName),
      ),
    );
  }

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  late final TextEditingController _nameController;
  final FormHeaderHairline _hairline = FormHeaderHairline();
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

  IconData get _icon =>
      CalendarIcons.forKey(_iconKey) ?? Icons.event_rounded;

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
    _hairline.dispose();
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
  /// Memoized on the folded text and the catalog revision, because the name
  /// row is rebuilt on every keystroke *and* on every colour tap and icon
  /// pick, and the scan folds two strings per category over the whole set.
  /// The revision is what keeps a category created from another sheet from
  /// going unnoticed.
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

  /// The line under the name while another category folds equal to it, or
  /// null while none does (D14).
  String? _duplicateWarning(AppLocalizations l10n) {
    final duplicate = _duplicateOf(l10n);
    if (duplicate == null) return null;
    final label = CalendarCategories.labelOf(duplicate, l10n);
    return duplicate.isHidden
        ? l10n.categoryNameExistsHidden(label)
        : l10n.categoryNameExists(label);
  }

  bool get _canSave {
    if (_saving) return false;
    if (_isBuiltIn) return true; // name fixed/localized, always valid
    return _nameController.text.trim().isNotEmpty;
  }

  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _pickIcon() async {
    // Before the picker opens: the route under it remembers a focused name
    // field as its focused child and hands the focus — and the keyboard —
    // straight back when the picker closes, over a sheet the user had left
    // the field in.
    _blur();
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
      // In the overlay, not the page's `Scaffold`: this sheet is a route
      // above that page, and a bar raised there is drawn under the sheet.
      OverlaySnackbar.show(
        context,
        l10n.categorySaveFailed,
        duration: AppConstants.snackbarErrorDuration,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the rule every calendar sheet
    // follows (`sheet_bottom_clearance_test.dart`): the box is a fixed
    // fraction of the screen, and a tall IME would collapse a padded Column
    // to nothing.
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.categoryEditorClose,
          onLeading: () => Navigator.of(context).pop(),
          title: _isEditing ? l10n.editCategory : l10n.createCategory,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          // The name is typed without a rebuild of the form; Save follows
          // its controller instead.
          trailing: ListenableBuilder(
            listenable: _nameController,
            builder: (context, _) => FormHeaderTextButton(
              label: l10n.save,
              identifier: SemanticsIds.categoryEditorSave,
              onPressed: _canSave ? _onSave : null,
            ),
          ),
        ),
        Flexible(
          child: _hairline.watch(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: FormRowGroup(
                trailingGap: false,
                children: [
                  _buildNameRow(l10n),
                  _buildIconRow(l10n),
                  _buildColorRow(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The live preview of the draft: its icon in its colour, where the event
  /// editor's title row previews the event.
  Widget _buildAvatar() => EventAvatar(icon: _icon, color: Color(_colorValue));

  /// A custom category's name as the title field; a built-in's localized
  /// label as a read row (D14), since its stored name is never the field's
  /// to edit.
  Widget _buildNameRow(AppLocalizations l10n) {
    final initial = widget.initial;
    if (_isBuiltIn && initial != null) {
      return FormPickerRow(
        leading: _buildAvatar(),
        label: CalendarCategories.labelOf(initial, l10n),
        caption: l10n.categoryDefault,
        onTap: null,
        showChevron: false,
      );
    }
    // The warning is a line of the row's own and follows the typed text, so
    // the row is rebuilt off the controller rather than the whole form. The
    // group reads a hairline indent off a `FormDividedRow` alone, and the
    // builder in between would hand it the glyph indent.
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentTitle,
      child: ListenableBuilder(
        listenable: _nameController,
        builder: (context, _) => FormTitleRow(
          leading: _buildAvatar(),
          controller: _nameController,
          hint: l10n.categoryNameHint,
          maxLength: kCategoryNameMaxLength,
          counterFrom: kCategoryNameCounterFrom,
          counterLabel: l10n.eventTitleCount,
          autofocus: !_isEditing,
          textCapitalization: TextCapitalization.sentences,
          warning: _duplicateWarning(l10n),
          identifier: SemanticsIds.categoryEditorName,
        ),
      ),
    );
  }

  Widget _buildIconRow(AppLocalizations l10n) {
    return FormPickerRow(
      glyph: Icons.emoji_symbols_rounded,
      label: l10n.iconLabel,
      value: l10n.pickIcon,
      onTap: _pickIcon,
      identifier: SemanticsIds.categoryEditorIcon,
    );
  }

  /// No default dot: a category *is* the colour everything else falls back
  /// to, so there is nothing behind it to inherit.
  Widget _buildColorRow() {
    return FormSwatchRow(
      identifier: SemanticsIds.swatchRow,
      child: ColorSwatchPicker(
        value: _colorValue,
        onChanged: (value) =>
            setState(() => _colorValue = value ?? _colorValue),
        spacing: FormMetrics.swatchSpacing,
        collapsible: false,
      ),
    );
  }
}
