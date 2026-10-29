import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/category_name.dart';
import '../constants/event_alerts.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_permission_check.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/category_alert.dart';
import '../models/recurrence_rule.dart';
import '../services/alert_scheduler.dart';
import '../services/category_service.dart';
import '../services/event_alert_service.dart';
import '../services/event_time_formatter.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import 'alert_editor_sheet.dart';
import 'automation_id.dart';
import 'color_swatch_picker.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'icon_picker_sheet.dart';
import 'overlay_snackbar.dart';

const int _defaultCategoryColor = 0xFFFB8C00;
const String _defaultCategoryIconKey = 'event';

/// The form for creating or editing a [CalendarCategory]: a sub-sheet of the
/// UI language (Tier 3, D12) in the quick alarm's shape — ✕ · title · Save
/// over one group of the name, an Icon row and the colour strip, then the
/// category's alerts (**v42**), which every event in it inherits.
///
/// Persists through [CategoryService] — and the alerts through
/// [EventAlertService] — inside the sheet and returns the saved category, or
/// `null` when dismissed before anything was written. The row is written
/// before the pop because the callers rely on it: the categories page
/// refreshes from the service, the picker ticks the returned id. A built-in
/// keeps its stored name — its localized label is a read row — while its
/// colour, icon and alerts stay editable.
///
/// Unguarded, as every sub-sheet: the name, icon and colour are three taps to
/// redo, and each alert it holds is one row to re-add.
class CategoryEditorSheet extends StatefulWidget {
  final CalendarCategory? initial;

  /// Prefills the name field when creating. The category picker passes what
  /// the user typed into its search field, so "no match" flows straight into
  /// creating the thing they were looking for. Ignored when [initial] is set.
  final String? initialName;

  /// The calendar guide's demos open the real form over throwaway state:
  /// Save validates as ever but writes nothing — no service, no scheduler,
  /// no bloc — and pops the category it would have written; the swatch strip
  /// is read-only and an icon pick is not recorded among the recent ones.
  /// The alert drafts stay in the sheet: the result type
  /// carries the category alone.
  final bool sandbox;

  const CategoryEditorSheet({
    super.key,
    this.initial,
    this.initialName,
    this.sandbox = false,
  });

  static Future<CalendarCategory?> show(
    BuildContext context, {
    CalendarCategory? initial,
    String? initialName,
    bool sandbox = false,
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
        child: CategoryEditorSheet(
          initial: initial,
          initialName: initialName,
          sandbox: sandbox,
        ),
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

  /// The category's alerts as the sheet is editing them, seeded from the
  /// synchronous facade so they are on screen in the first frame. Written on
  /// Save only once [_alertsTouched]: an untouched set is what is stored.
  late List<CategoryAlert> _alerts;
  bool _alertsTouched = false;

  /// The ids [_alerts] was seeded with, handed to `replaceForCategory` so the
  /// save tombstones only the rows this sheet was showing: a pull can add an
  /// alert to this category while the sheet is open, and a whole-set write
  /// would otherwise delete one that was never on screen.
  late Set<String> _seededAlertIds;

  /// Held while the alert sheet is up, so a second tap on a row or on Add
  /// alert during its opening animation cannot stack a second sheet.
  bool _alertSheetOpen = false;

  /// The category a create wrote before its alerts failed to, so the next
  /// Save updates that row rather than creating a second one.
  CalendarCategory? _created;

  /// The category row as the last Save wrote it, when its alerts then failed
  /// to: leaving hands it back rather than `null`, so the caller still
  /// refreshes and the picker ticks it.
  CalendarCategory? _written;

  /// Memo behind [_duplicateOf]: the folded term it last scanned for, the
  /// catalog revision and locale it scanned under, and what it found.
  String? _duplicateTerm;
  int _duplicateRevision = -1;
  String? _duplicateLocale;
  CalendarCategory? _duplicate;

  bool get _isEditing => widget.initial != null;
  bool get _isBuiltIn => widget.initial?.isBuiltIn ?? false;

  IconData get _icon => CalendarIcons.forKey(_iconKey) ?? Icons.event_rounded;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(
      text: initial?.name ?? widget.initialName ?? '',
    );
    _colorValue = initial?.colorValue ?? _defaultCategoryColor;
    _iconKey = initial?.iconKey ?? _defaultCategoryIconKey;
    _alerts = initial == null
        ? const []
        : List<CategoryAlert>.of(EventAlerts.categoryAlertsFor(initial.id));
    _seededAlertIds = {for (final alert in _alerts) alert.id};
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
    final selfId = widget.initial?.id ?? _created?.id;
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
      sandbox: widget.sandbox,
    );
    if (picked == null || !mounted) return;
    setState(() => _iconKey = picked);
  }

  /// The id the alerts are drafted under: the category's, or empty for one
  /// still to be created — `replaceForCategory` re-owns every alert it is
  /// handed under the id it writes for.
  String get _alertCategoryId => widget.initial?.id ?? _created?.id ?? '';

  /// A stand-in event of this category carrying the one property
  /// [EventAlert.describe] reads, the derived `allDay`: a category alert
  /// serves both shapes, and each row names both readings. Nothing else on it
  /// is read.
  CalendarEvent _previewEvent({required bool allDay}) => CalendarEvent(
    id: '',
    title: '',
    categoryId: _alertCategoryId,
    startDate: DateTime.utc(2026),
    rule: const OneTimeRecurrence(),
    time: allDay ? null : const EventTime(startMinute: 0),
  );

  /// Opens the alert sheet on a brand-new alert, and keeps it only if the
  /// user saves. Never offers Remove there: closing the sheet already means
  /// "no". Not a settings-default pre-fill (D7): the draft's own defaults.
  Future<void> _addAlert() async {
    if (_alertSheetOpen) return;
    _blur();
    if (_alerts.length >= kMaxAlertsPerCategory) return;
    _alertSheetOpen = true;
    final AlertEditorResult? result;
    try {
      result = await AlertEditorSheet.show(
        context,
        alert: AlertEditorSheet.draft(eventId: '', allDay: false),
        event: _previewEvent(allDay: true),
        canRemove: false,
        forCategory: true,
      );
    } finally {
      _alertSheetOpen = false;
    }
    if (!mounted) return;
    if (result case AlertEditorSaved(:final alert)) {
      setState(() {
        _alertsTouched = true;
        _alerts = [
          ..._alerts,
          CategoryAlert.fromEventAlert(alert, categoryId: _alertCategoryId),
        ];
      });
    }
  }

  Future<void> _editAlert(CategoryAlert alert) async {
    if (_alertSheetOpen) return;
    _blur();
    _alertSheetOpen = true;
    final AlertEditorResult? answer;
    try {
      answer = await AlertEditorSheet.show(
        context,
        alert: alert.toEventAlert(''),
        event: _previewEvent(allDay: true),
        forCategory: true,
      );
    } finally {
      _alertSheetOpen = false;
    }
    final result = answer;
    if (!mounted || result == null) return;
    setState(() {
      _alertsTouched = true;
      _alerts = switch (result) {
        AlertEditorRemoved() => [
          for (final existing in _alerts)
            if (existing.id != alert.id) existing,
        ],
        AlertEditorSaved(alert: final saved) => [
          for (final existing in _alerts)
            existing.id == alert.id
                ? CategoryAlert.fromEventAlert(
                    saved,
                    categoryId: existing.categoryId,
                  )
                : existing,
        ],
      };
    });
  }

  /// The category's own switch for one alert (D5): off pauses it for every
  /// event in the category, and keeps it here to switch back on.
  void _setAlertEnabled(CategoryAlert alert, bool enabled) {
    setState(() {
      _alertsTouched = true;
      _alerts = [
        for (final existing in _alerts)
          existing.id == alert.id
              ? existing.copyWith(enabled: enabled)
              : existing,
      ];
    });
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
  ///
  /// The alerts are written after the category, which a new one needs for
  /// its id, and a failure there reads as the category's: the sheet stays
  /// open on the draft, the next Save updates the row the write left, and ✕
  /// hands that row back ([_written]).
  ///
  /// A successful alert write is announced to the calendar
  /// ([CategoryAlertsChanged]) and, when it left an alert that can fire,
  /// followed by the permission check every saved alert gets — the message
  /// only: a category alert has no one next fire to count down to.
  ///
  /// A category that is no longer there to edit — a pull merged another
  /// device's delete of it while this sheet was open — is not a throw but a
  /// deliberate no-op in the DAO, so it has its own path: the same message
  /// the `catch` raises, and a pop with **nothing**. Handing the draft back
  /// would have the caller refresh against a category that does not exist,
  /// and the picker's inline-create path tick a dead id into its selection.
  Future<void> _onSave() async {
    if (!_canSave) return;
    if (widget.sandbox) {
      Navigator.of(context).pop(_wouldBeSaved());
      return;
    }
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final service = await CategoryService.getInstance();
      CalendarCategory saved;
      final initial = widget.initial ?? _created;
      if (initial == null) {
        saved = await service.create(
          name: _nameController.text.trim(),
          colorValue: _colorValue,
          iconKey: _iconKey,
        );
        _created = saved;
      } else {
        final updated = initial.copyWith(
          name: _isBuiltIn ? initial.name : _nameController.text.trim(),
          colorValue: _colorValue,
          iconKey: _iconKey,
        );
        if (!await service.updateCategory(updated)) {
          if (!mounted) return;
          // Whatever an earlier partial save left here named the same row,
          // and that row is gone: ✕ and back must hand back nothing too.
          _written = null;
          _raiseSaveFailed(l10n);
          Navigator.of(context).pop();
          return;
        }
        saved = updated;
      }
      _written = saved;
      if (_alertsTouched) {
        final alerts = await EventAlertService.getInstance();
        await alerts.replaceForCategory(
          saved.id,
          _alerts,
          knownIds: _seededAlertIds,
        );
        // A category alert touches every event in the category, so the whole
        // plan is redone (D22).
        unawaited(
          AlertScheduler.reconcileAllQuietly(AlertReconcileReason.eventChanged),
        );
        if (!mounted) return;
        // Nullable: a host without the app's bloc has no badges to redraw.
        context.read<CalendarBloc?>()?.add(const CategoryAlertsChanged());
        if (_alerts.any((alert) => alert.enabled)) {
          // The navigator's context, which outlives this sheet: the check
          // may prompt and raise its message after the pop below.
          unawaited(
            AlertPermissionCheck.afterSave(Navigator.of(context).context),
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      debugPrint('[CategoryEditorSheet] Save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _raiseSaveFailed(l10n);
    }
  }

  /// The category a sandboxed Save hands back: what [_onSave] would have
  /// written, with a fresh id and, for a new one, the position after the
  /// last the catalogue holds — `CategoryService.create`'s
  /// `MAX(sort_order) + 1`, which a reordered catalogue with gaps still
  /// answers, where its length would not.
  CalendarCategory _wouldBeSaved() {
    final initial = widget.initial;
    if (initial != null) {
      return initial.copyWith(
        name: _isBuiltIn ? initial.name : _nameController.text.trim(),
        colorValue: _colorValue,
        iconKey: _iconKey,
      );
    }
    return CalendarCategory(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      colorValue: _colorValue,
      iconKey: _iconKey,
      sortOrder: CalendarCategories.all.fold<int>(
        0,
        (next, category) => math.max(next, category.sortOrder + 1),
      ),
      isBuiltIn: false,
    );
  }

  /// In the overlay, not the page's `Scaffold`: this sheet is a route above
  /// that page, and a bar raised there is drawn under the sheet. The entry
  /// goes into the navigator's own overlay, so it still shows over the page
  /// when this sheet pops away under it.
  void _raiseSaveFailed(AppLocalizations l10n) {
    OverlaySnackbar.show(
      context,
      l10n.categorySaveFailed,
      duration: AppConstants.snackbarErrorDuration,
    );
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
    // Back and the barrier leave the way ✕ does: with the row a failed alert
    // write left behind, when there is one.
    return PopScope<CalendarCategory>(
      canPop: _written == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_written);
      },
      child: _buildBody(context, l10n, clearance),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    double clearance,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.categoryEditorClose,
          onLeading: () => Navigator.of(context).pop(_written),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormRowGroup(
                    children: [
                      _buildNameRow(l10n),
                      _buildIconRow(l10n),
                      _buildColorRow(),
                    ],
                  ),
                  FormSectionLabel(text: l10n.eventAlerts),
                  FormRowGroup(
                    trailingGap: false,
                    children: _buildAlertRows(l10n),
                  ),
                  FormCaption(
                    text: l10n.categoryAlertsHint,
                    padding: FormMetrics.groupCaptionPadding,
                  ),
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

  /// One row per alert, named both ways because it serves both shapes: the
  /// all-day reading as the label, the timed one and the tier in the
  /// caption, and the category's switch for it at the end. A tap edits it,
  /// and the sheet it opens is where it is removed. Then Add alert while
  /// there is room under the cap.
  List<Widget> _buildAlertRows(AppLocalizations l10n) {
    final allDay = _previewEvent(allDay: true);
    final timed = _previewEvent(allDay: false);
    String formatMinute(int minute) =>
        EventTimeFormatter.formatMinute(minute, context);
    return [
      for (final (index, alert) in _alerts.indexed)
        FormPickerSwitchRow(
          glyph: alert.isAlarm
              ? Icons.alarm_outlined
              : Icons.notifications_outlined,
          label: alert
              .toEventAlert('')
              .describe(l10n, allDay, formatMinute: formatMinute),
          caption: [
            l10n.categoryAlertTimedCaption(
              alert.toEventAlert('').describe(l10n, timed),
            ),
            alert.isAlarm ? l10n.eventAlertModeRing : l10n.eventAlertModeNotify,
          ].join(' · '),
          identifier: SemanticsIds.categoryAlertRow(index),
          switchIdentifier: SemanticsIds.categoryAlertSwitch(index),
          value: alert.enabled,
          onTap: () => _editAlert(alert),
          onChanged: (value) => _setAlertEnabled(alert, value),
        ),
      if (_alerts.length < kMaxAlertsPerCategory)
        AutomationId(
          identifier: SemanticsIds.categoryAlertAdd,
          child: FormActionRow(
            glyph: Icons.add_rounded,
            label: l10n.eventAlertAdd,
            onTap: _addAlert,
          ),
        ),
    ];
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
        sandbox: widget.sandbox,
      ),
    );
  }
}
