import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/category_kinds.dart';
import '../constants/category_name.dart';
import '../constants/category_profiles.dart';
import '../constants/event_alerts.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_permission_check.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart' show ReportShape, shapeOf;
import '../models/category_alert.dart';
import '../models/category_profile.dart';
import '../models/recurrence_rule.dart';
import '../services/alert_scheduler.dart';
import '../services/app_navigator.dart';
import '../services/category_profile_service.dart';
import '../services/category_service.dart';
import '../services/event_alert_service.dart';
import '../services/event_time_formatter.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../services/share_service.dart';
import '../utils/category_profile_labels.dart';
import '../utils/mark_verb_labels.dart' show markVerbLabel;
import '../utils/share_copy.dart';
import 'alert_editor_sheet.dart';
import 'app_dialogs.dart';
import 'automation_id.dart';
import 'category_goal_sheet.dart';
import 'category_kind_sheet.dart';
import 'color_swatch_picker.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'icon_picker_sheet.dart';
import 'overlay_snackbar.dart';
import 'value_change_highlight.dart';

const int _defaultCategoryColor = 0xFFFB8C00;
const String _defaultCategoryIconKey = 'event';

/// The Mark menu's three items: the kind's own verb, the owner's word, off.
enum _MarkChoice { kind, own, off }

/// A menu value that may be "none" — Auto, Off. `showFormMenu` answers null
/// for a dismissed menu, so a null choice rides inside this box instead.
final class _Choice<T> {
  final T? value;

  const _Choice(this.value);

  @override
  bool operator ==(Object other) => other is _Choice<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// What the category editor answers through [CategoryEditorSheet.open]: the
/// category it stored, and the share its draft asks for.
///
/// The share is written by the opener after the pop, never by the sheet
/// (`docs/cloud-share-surfaces-roadmap.md` §6.1): it needs the category's id,
/// which a new one has only once stored, and its Undo belongs to the page
/// the sheet returns to.
@immutable
class CategoryEditorResult {
  final CalendarCategory category;

  /// Whether the category is to be shared, or null when the draft leaves
  /// the share as it was stored.
  final bool? share;

  const CategoryEditorResult(this.category, {this.share});
}

/// The form for creating or editing a [CalendarCategory]: a sub-sheet of the
/// UI language (Tier 3, D12) in the quick alarm's shape — ✕ · title · Save
/// over one group of the name, an Icon row and the colour strip, then the
/// category's alerts (**v42**), which every event in it inherits, then its
/// analytics profile (S3 of `docs/calendar-analytics-roadmap.md`): Report's
/// Kind, Mark and Area and Measure & goal's Measure, Counts as and Goal.
/// The profile sections come last, so nothing they do moves a row above.
///
/// Persists through [CategoryService] — the profile through
/// [CategoryProfileService] and the alerts through [EventAlertService] —
/// inside the sheet and returns the saved category, or
/// `null` when dismissed before anything was written. The row is written
/// before the pop because the callers rely on it: the categories page
/// refreshes from the service, the picker ticks the returned id. A built-in
/// keeps its stored name — its localized label is a read row — while its
/// colour, icon and alerts stay editable. The share switch is the one part
/// of the draft the sheet does not write: [open] hands it back for the
/// opener to write once the category is stored.
///
/// Guarded (K11 of the categories record): a typed name and drafted alerts
/// are more than a tap to redo, so ✕, back, the system back gesture and the
/// barrier and a dismissing drag ask before discarding a draft that differs
/// from what the sheet opened with. The drag is `FormSheetFrame`'s, as every
/// guarded sheet's is — the route's own pops without consulting the guard —
/// on the frame's content-tall option, so the sub-sheet keeps its box.
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

  /// Whether this phone can share the category, handed over by the opener
  /// as the event editor is handed its day load: not paired leaves the
  /// SHARING section out, so the sheet is the one it was before sharing.
  final ShareAvailability share;

  /// The category's own live events, for the share switch's "All 42 events,
  /// and new ones" — the opener's `countByCategory`, never a read here.
  final int shareEventCount;

  /// Opens Sync & sharing from the share switch while the database does not
  /// sync. A seam for tests; the app's page otherwise.
  final Future<void> Function(BuildContext context) openSyncSettings;

  /// Asks the opener for [share] again once Sync & sharing returns: sync
  /// turned on there enables the switch the person went there for. Null
  /// keeps the first answer.
  final Future<ShareAvailability> Function()? rereadShare;

  const CategoryEditorSheet({
    super.key,
    this.initial,
    this.initialName,
    this.sandbox = false,
    this.share = const ShareNotPaired(),
    this.shareEventCount = 0,
    this.openSyncSettings = AppNavigator.toSyncSettings,
    this.rereadShare,
  });

  /// The editor for a caller that does not share: it answers the stored
  /// category alone.
  static Future<CalendarCategory?> show(
    BuildContext context, {
    CalendarCategory? initial,
    String? initialName,
    bool sandbox = false,
  }) async {
    final result = await open(
      context,
      initial: initial,
      initialName: initialName,
      sandbox: sandbox,
    );
    return result?.category;
  }

  /// The editor with its share switch while [share] says the phone is
  /// paired; the answer carries the share for the caller to write.
  static Future<CategoryEditorResult?> open(
    BuildContext context, {
    CalendarCategory? initial,
    String? initialName,
    bool sandbox = false,
    ShareAvailability share = const ShareNotPaired(),
    int shareEventCount = 0,
    Future<void> Function(BuildContext context) openSyncSettings =
        AppNavigator.toSyncSettings,
    Future<ShareAvailability> Function()? rereadShare,
  }) {
    return showModalBottomSheet<CategoryEditorResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      // The frame owns the drag (the route's own would pop past the guard)
      // and paints the ground and the radius itself, so a dragged sheet
      // uncovers nothing of the route's.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Content-tall: a sub-sheet's answer resizes the sheet while that
      // route is still leaving.
      builder: (context) => FormSheetSemanticsRefresh(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                FormMetrics.sheetHeightFactor,
          ),
          child: CategoryEditorSheet(
            initial: initial,
            initialName: initialName,
            sandbox: sandbox,
            share: share,
            shareEventCount: shareEventCount,
            openSyncSettings: openSyncSettings,
            rereadShare: rereadShare,
          ),
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

  /// Held while Save writes. Nothing opens under it — no sub-sheet, menu or
  /// dialog: Save ends in a pop of the top route, which would close that
  /// one with the editor's result instead of the sheet.
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

  /// The category's analytics profile as the sheet is editing it, seeded
  /// from the facade as the alerts are; null is no profile — Custom with
  /// nothing overridden. Every row of the two profile sections reads its
  /// resolution, [_effective].
  CategoryProfile? _profile;
  late final CategoryProfile? _openedProfile;

  /// The profile as this sheet last knew it stored: [_openedProfile] until
  /// a Save writes one, then what that write stored. A Save whose alerts
  /// then failed has moved the store, so a draft turned back to the opened
  /// profile is a change to write, not an untouched one.
  late CategoryProfile? _profileBaseline;

  /// Whether every live event of the category is a plain repeat, which the
  /// report never gives counted hours: Counts as is then disabled with its
  /// reason. Read once at open, from the calendar's events where the app
  /// has them in scope.
  late final bool _repeatsOnly;

  /// Held while the kind picker or the goal sheet is up, [_alertSheetOpen]'s
  /// twin.
  bool _profileSheetOpen = false;

  /// The category a create wrote before its alerts failed to, so the next
  /// Save updates that row rather than creating a second one.
  CalendarCategory? _created;

  /// The category row as the last Save wrote it, when its alerts then failed
  /// to: leaving hands it back rather than `null`, so the caller still
  /// refreshes and the picker ticks it.
  CalendarCategory? _written;

  /// The draft as the sheet opened — the picker's typed text included, so a
  /// create it opened is clean until something changes — which [_isDirty]
  /// compares against.
  late final String _openedName;
  late final int _openedColor;
  late final String _openedIconKey;
  late final List<CategoryAlert> _openedAlerts;

  /// The share switch as the draft holds it, and as stored — at the open,
  /// then again on each return from Sync & sharing. Off unless the phone
  /// can share now: the switch reads off while the database does not sync
  /// (decision pb of the share surfaces), and a draft that cannot change is
  /// never dirty.
  late bool _shared;
  late bool _openedShared;

  /// [CategoryEditorSheet.share], then the opener's answer again after each
  /// trip to Sync & sharing from the share switch.
  late ShareAvailability _share = widget.share;

  /// Held while the discard question is up, so a second back or barrier tap
  /// cannot stack a second dialog.
  bool _leaving = false;

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
    // The field's limit governs typing only, never its initial text, so a
    // long query handed over by the picker is cut here (in characters, as
    // the counter counts) or Save would store it whole.
    _nameController = TextEditingController(
      text:
          initial?.name ??
          widget.initialName?.characters
              .take(kCategoryNameMaxLength)
              .toString() ??
          '',
    );
    _colorValue = initial?.colorValue ?? _defaultCategoryColor;
    _iconKey = initial?.iconKey ?? _defaultCategoryIconKey;
    _alerts = initial == null
        ? const []
        : List<CategoryAlert>.of(EventAlerts.categoryAlertsFor(initial.id));
    _seededAlertIds = {for (final alert in _alerts) alert.id};
    _profile = initial == null ? null : CategoryProfiles.profileFor(initial.id);
    _openedProfile = _profile;
    _profileBaseline = _profile;
    _repeatsOnly = _readRepeatsOnly();
    _openedName = _nameController.text.trim();
    _openedColor = _colorValue;
    _openedIconKey = _iconKey;
    _openedAlerts = _alerts;
    _openedShared = _sharedAsOpened(initial?.sharedByMe ?? false);
    _shared = _openedShared;
  }

  bool _sharedAsOpened(bool stored) => _share is ShareReady && stored;

  /// A category with no events is not repeat-only: its next event may be
  /// anything. Nothing in scope reads as nothing known. A partner's events in
  /// a shared built-in are theirs and shape none of my profile (D15).
  bool _readRepeatsOnly() {
    final initial = widget.initial;
    if (initial == null) return false;
    final state = context.read<CalendarBloc?>()?.state;
    if (state is! CalendarPageLoaded) return false;
    var any = false;
    for (final event in state.allEvents) {
      if (event.fromPartner ||
          CalendarCategories.resolve(event.categoryId).id != initial.id) {
        continue;
      }
      if (shapeOf(event) != ReportShape.repeat) return false;
      any = true;
    }
    return any;
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
      // A partner's category never stands in a picker beside this one.
      if (category.id == selfId || category.fromPartner) continue;
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

  /// Whether leaving would lose anything. The alerts compare by value, not by
  /// [_alertsTouched]: one switched off and on again is the set it opened
  /// with.
  bool get _isDirty =>
      _nameController.text.trim() != _openedName ||
      _colorValue != _openedColor ||
      _iconKey != _openedIconKey ||
      !listEquals(_alerts, _openedAlerts) ||
      !_sameProfile(_profile, _openedProfile) ||
      _shared != _openedShared;

  /// What a profile says, its identity and stamps left out; a Custom
  /// profile with nothing overridden says what no profile does, so picking
  /// Custom on an unprofiled category changes nothing.
  static List<Object?> _meaningOf(CategoryProfile? profile) {
    if (profile == null ||
        (profile.kind == CategoryKind.custom && !profile.hasOverrides)) {
      return const [];
    }
    return [
      profile.kind,
      profile.area,
      profile.measure,
      profile.nominalMinutes,
      profile.markVerb,
      profile.marksNew,
      profile.assumeAbsentNew,
      profile.countsHours,
      profile.target,
    ];
  }

  static bool _sameProfile(CategoryProfile? a, CategoryProfile? b) =>
      listEquals(_meaningOf(a), _meaningOf(b));

  /// Serves ✕, back, the system back gesture, the barrier and a dismissing
  /// drag. Nothing leaves while Save is writing: its own pop is on the way,
  /// and a question opened under it would take that pop instead of the
  /// sheet. After a save whose alerts then failed it hands back the row that
  /// save wrote, as ✕ always has — asking first while the draft holds
  /// anything that save did not store; otherwise a dirty draft asks first.
  Future<void> _leave() async {
    if (_leaving || _saving) return;
    final written = _written;
    _leaving = true;
    try {
      final dirty = written == null ? _isDirty : _differsFrom(written);
      final leave = !dirty || await AppDialogs.confirmDiscard(context);
      if (!leave || !mounted) return;
      Navigator.of(context).pop(_answerOf(written));
    } finally {
      _leaving = false;
    }
  }

  /// Whether the draft differs from what the partial save at [written]
  /// stored: the row against the row, the alerts and the profile against
  /// what the facades hold for it, which a failed write left as it was. The
  /// share is the opener's to write after a Save that completes, so a
  /// partial save never stored it.
  bool _differsFrom(CalendarCategory written) =>
      (!_isBuiltIn && _nameController.text.trim() != written.name) ||
      _colorValue != written.colorValue ||
      _iconKey != written.iconKey ||
      !listEquals(_alerts, EventAlerts.categoryAlertsFor(written.id)) ||
      !_sameProfile(_profile, CategoryProfiles.profileFor(written.id)) ||
      _shared != _openedShared;

  /// What leaving without a completed Save answers: the row a partial save
  /// wrote, if any, and never a share.
  static CategoryEditorResult? _answerOf(CalendarCategory? written) =>
      written == null ? null : CategoryEditorResult(written);

  Future<void> _pickIcon() async {
    if (_saving) return;
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
    if (_alertSheetOpen || _saving) return;
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
    if (_alertSheetOpen || _saving) return;
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
    if (_saving) return;
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

  EffectiveProfile get _effective => CategoryProfile.effectiveOf(_profile);

  /// The kind's own row, the one the overrides are laid over.
  CategoryKindRow get _kindRow => CategoryKinds.of(_effective.kind);

  /// The draft to change: the profile, or a fresh Custom one. Its id is the
  /// service's to mint, and its category is set on Save.
  CategoryProfile get _draft =>
      _profile ?? CategoryProfile(id: '', categoryId: _alertCategoryId);

  /// [next] with its goal kept only while the goal still means the same
  /// thing under its primary (the S3 spec's F): the same unit and a type the
  /// primary takes. A gap counts days under any primary.
  CategoryProfile _keepingValidTarget(CategoryProfile next) {
    final target = _profile?.target;
    if (target == null) return next;
    final from = _effective.primary;
    final to = next.effective.primary;
    final keeps =
        CategoryGoalLimits.allows(to, target.kind) &&
        (target.kind == TargetKind.maxGap ||
            CategoryGoalLimits.unitOf(from) == CategoryGoalLimits.unitOf(to));
    return keeps
        ? next.copyWith(target: target)
        : next.copyWith(clearTarget: true);
  }

  /// A new kind starts from its own defaults (F) — area, measure, verb and
  /// the three new-event and hours flags no row shows yet, so Custom with
  /// nothing on screen overridden is no profile; the confirmed counts-as
  /// stays, and so does a goal that still fits.
  Future<void> _pickKind() async {
    if (_profileSheetOpen || _saving) return;
    _blur();
    _profileSheetOpen = true;
    final CategoryKind? picked;
    try {
      picked = await CategoryKindSheet.show(context, selected: _effective.kind);
    } finally {
      _profileSheetOpen = false;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _profile = _keepingValidTarget(
        _draft.copyWith(
          kind: picked,
          clearArea: true,
          clearMeasure: true,
          clearMarkVerb: true,
          clearMarksNew: true,
          clearAssumeAbsentNew: true,
          clearCountsHours: true,
        ),
      );
    });
  }

  _MarkChoice get _markInEffect {
    final effective = _effective;
    if (effective.customVerb != null) return _MarkChoice.own;
    return effective.marks ? _MarkChoice.kind : _MarkChoice.off;
  }

  /// The kind's verb in the owner's language, or null for a kind that does
  /// not mark.
  String? _kindVerbWord(AppLocalizations l10n) {
    final kind = _effective.kind;
    if (CategoryKinds.of(kind).verb == null) return null;
    return markVerbLabel(
      l10n,
      CategoryProfile(id: '', categoryId: '', kind: kind).effective,
    );
  }

  Future<void> _pickMark(_MarkChoice choice) async {
    switch (choice) {
      case _MarkChoice.kind:
        setState(() => _profile = _draft.copyWith(clearMarkVerb: true));
      case _MarkChoice.off:
        // `''` turns a marking kind off; a kind that never marks is off
        // with no override at all.
        setState(() {
          _profile = _kindRow.verb != null
              ? _draft.copyWith(markVerb: '')
              : _draft.copyWith(clearMarkVerb: true);
        });
      case _MarkChoice.own:
        await _askMarkWord();
    }
  }

  /// The owner's own word, which outranks the kind's verb. The kind's own
  /// word typed back is no override.
  Future<void> _askMarkWord() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final kindWord = _kindVerbWord(l10n);
    final word = await AppDialogs.textInput(
      context,
      title: l10n.categoryMarkOwnTitle,
      hintText: l10n.categoryMarkOwnHint,
      initialValue: _effective.customVerb ?? kindWord ?? '',
      maxLength: kCategoryMarkWordMaxLength,
      selectAll: true,
      allowEmpty: false,
      fieldIdentifier: SemanticsIds.categoryMarkWordField,
      confirmIdentifier: SemanticsIds.categoryMarkWordSave,
    );
    final trimmed = word?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    setState(() {
      _profile = trimmed == kindWord
          ? _draft.copyWith(clearMarkVerb: true)
          : _draft.copyWith(markVerb: trimmed);
    });
  }

  void _pickArea(LifeArea area) {
    setState(() {
      _profile = area == _kindRow.area
          ? _draft.copyWith(clearArea: true)
          : _draft.copyWith(area: area);
    });
  }

  void _pickMeasure(_Choice<ReportMeasure> choice) {
    final measure = choice.value;
    setState(() {
      _profile = _keepingValidTarget(
        measure == null || measure == _kindRow.primary
            ? _draft.copyWith(clearMeasure: true)
            : _draft.copyWith(measure: measure),
      );
    });
  }

  /// The pick is the confirmation (record §5 I): a suggestion never counts
  /// until it is picked here.
  void _pickCountsAs(_Choice<int> choice) {
    final minutes = choice.value;
    setState(() {
      _profile = minutes == null
          ? _draft.copyWith(clearNominalMinutes: true)
          : _draft.copyWith(nominalMinutes: minutes);
    });
  }

  Future<void> _pickGoal() async {
    if (_profileSheetOpen || _saving) return;
    _blur();
    final effective = _effective;
    _profileSheetOpen = true;
    final CategoryGoalResult? answer;
    try {
      answer = await CategoryGoalSheet.show(
        context,
        initial: effective.target,
        primary: effective.primary,
        presets: effective.targetPresets,
      );
    } finally {
      _profileSheetOpen = false;
    }
    final result = answer;
    if (result == null || !mounted) return;
    setState(() {
      _profile = switch (result) {
        CategoryGoalSaved(:final target) => _draft.copyWith(target: target),
        CategoryGoalRemoved() => _draft.copyWith(clearTarget: true),
      };
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
  /// The profile and then the alerts are written after the category, which
  /// a new one needs for its id, and a failure there reads as the
  /// category's: the sheet stays
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
      Navigator.of(context).pop(CategoryEditorResult(_wouldBeSaved()));
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
      await _saveProfile(saved.id);
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
      Navigator.of(context).pop(
        CategoryEditorResult(
          saved,
          share: _shared == _openedShared ? null : _shared,
        ),
      );
    } catch (e) {
      debugPrint('[CategoryEditorSheet] Save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _raiseSaveFailed(l10n);
    }
  }

  /// Writes the profile between the category, whose id a new one needs, and
  /// the alerts — only when the owner changed it here since it was last
  /// stored ([_profileBaseline]) and it still differs from what is stored,
  /// so a pull that landed under an untouched draft is never overwritten,
  /// and a retry after a failed alert write does not write it twice. Back
  /// to Custom with nothing overridden is a [CategoryProfileService.clear]:
  /// the category is unprofiled again.
  Future<void> _saveProfile(String categoryId) async {
    final draft = _profile;
    if (_sameProfile(draft, _profileBaseline) ||
        _sameProfile(draft, CategoryProfiles.profileFor(categoryId))) {
      return;
    }
    final service = await CategoryProfileService.getInstance();
    if (draft == null || _meaningOf(draft).isEmpty) {
      await service.clear(categoryId);
    } else {
      await service.save(draft.copyWith(categoryId: categoryId));
    }
    _profileBaseline = draft;
  }

  /// The category a sandboxed Save hands back: what [_onSave] would have
  /// written, with a fresh id and, for a new one, the position after the
  /// last the catalogue holds — `CategoryService.create`'s
  /// `MAX(sort_order) + 1`, which a reordered catalogue with gaps still
  /// answers, where its length would not — over the person's own, as that
  /// one counts.
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
      sortOrder: CalendarCategories.all
          .where((category) => !category.fromPartner)
          .fold<int>(
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
    // follows (`sheet_bottom_clearance_test.dart`): the box is clamped to a
    // fraction of the screen, and under a tall IME a padded Column would
    // collapse the rows to nothing while a padded scroll view just scrolls.
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    // Back, the barrier and a dismissing drag reach `_leave` through the
    // frame and leave the way ✕ does; a drag on a clean sheet pops at once.
    return FormSheetFrame(
      mainAxisSize: MainAxisSize.min,
      onLeave: _leave,
      isClean: () => !_saving && !_isDirty && _written == null,
      onDismiss: () => Navigator.of(context).pop(_answerOf(_written)),
      chrome: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.categoryEditorClose,
            onLeading: _saving ? null : _leave,
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
        ],
      ),
      body: [
        Flexible(
          child: _hairline.watch(
            child: Semantics(
              identifier: SemanticsIds.categoryEditorForm,
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
                    if (_buildShareRow(l10n) case final shareRow?) ...[
                      FormSectionLabel(text: l10n.shareSectionLabel),
                      FormRowGroup(children: [shareRow]),
                    ],
                    FormSectionLabel(text: l10n.eventAlerts),
                    FormRowGroup(
                      trailingGap: false,
                      children: _buildAlertRows(l10n),
                    ),
                    FormCaption(
                      text: l10n.categoryAlertsHint,
                      padding: FormMetrics.groupCaptionPadding,
                    ),
                    // A section label has no top padding of its own and the
                    // caption no bottom one: the gap a group would leave.
                    const SizedBox(height: RowMetrics.groupGap),
                    FormSectionLabel(text: l10n.categoryReportSection),
                    FormRowGroup(
                      children: [
                        _buildKindRow(l10n),
                        _buildMarkRow(l10n),
                        _buildAreaRow(l10n),
                      ],
                    ),
                    FormSectionLabel(text: l10n.categoryMeasureGoalSection),
                    FormRowGroup(
                      trailingGap: false,
                      children: [
                        _buildMeasureRow(l10n),
                        _buildCountsAsRow(l10n),
                        _buildGoalRow(l10n),
                      ],
                    ),
                  ],
                ),
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

  /// The SHARING section's one switch, or null while the phone is not
  /// paired (D7). Its subtitle slot is sized for every state's words, so
  /// the row keeps one height whether it is off, on or waiting for sync.
  /// While the database does not sync the switch is off and dimmed with the
  /// reason whole, and a tap opens Sync & sharing over the sheet (D8).
  Widget? _buildShareRow(AppLocalizations l10n) {
    final share = _share;
    final audience = share.audience;
    if (audience == null) return null;
    final ready = share is ShareReady;
    final count = widget.shareEventCount;
    final on = count == 0
        ? l10n.shareCategoryNewOnly
        : l10n.shareCategoryOn(count);
    return FormSwitchRow(
      glyph: Icons.group_rounded,
      label: l10n.shareWithPartner(
        ShareCopy.partnerName(l10n, audience.displayName),
      ),
      subtitle: !ready
          ? l10n.shareNeedsSync
          : _shared
          ? on
          : l10n.shareCategoryOff,
      subtitleTemplates: [
        l10n.shareCategoryOff,
        on,
        l10n.shareCategoryNewOnly,
        l10n.shareNeedsSync,
      ],
      value: _shared,
      onChanged: ready ? (value) => setState(() => _shared = value) : null,
      onDisabledTap: ready ? null : _openSyncSettings,
      onDisabledTapHint: l10n.shareOpensSyncHint,
      identifier: SemanticsIds.categoryEditorShare,
    );
  }

  /// Pushes Sync & sharing over the sheet, and on its return takes the
  /// opener's answer again. The draft is re-seeded from the catalogue as it
  /// stands now — sharing may have stopped on that page — and stays clean;
  /// a switch the person had moved keeps their choice. A new category has
  /// nothing stored.
  Future<void> _openSyncSettings() async {
    _blur();
    await widget.openSyncSettings(context);
    final reread = widget.rereadShare;
    if (reread == null || !mounted) return;
    final next = await reread();
    if (!mounted || next == _share) return;
    final initial = widget.initial;
    final touched = _shared != _openedShared;
    setState(() {
      _share = next;
      _openedShared = _sharedAsOpened(
        initial != null &&
            (CalendarCategories.byId(initial.id)?.sharedByMe ?? false),
      );
      if (!touched) _shared = _openedShared;
    });
  }

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

  /// A profile row a sub-sheet or a menu writes to: it flashes when the pick
  /// lands, and the wrapper keeps its hairline at the glyph indent. While
  /// Save writes it takes no tap but is drawn as it was — a row dimmed for
  /// the save window alone would flicker on every Save.
  Widget _highlighted(Object? value, Widget row) => FormIndentedRow(
    dividerIndent: FormMetrics.dividerIndentGlyph,
    child: IgnorePointer(
      ignoring: _saving,
      child: ValueChangeHighlight(value: value, child: row),
    ),
  );

  Widget _buildKindRow(AppLocalizations l10n) {
    final kind = _effective.kind;
    return _highlighted(
      kind,
      FormPickerRow(
        glyph: Icons.category_outlined,
        label: l10n.categoryKindLabel,
        value: categoryKindName(l10n, kind),
        caption: categoryKindExample(l10n, kind),
        identifier: SemanticsIds.categoryEditorKind,
        onTap: _pickKind,
      ),
    );
  }

  Widget _buildMarkRow(AppLocalizations l10n) {
    final effective = _effective;
    final kindWord = _kindVerbWord(l10n);
    final customWord = effective.customVerb;
    return _highlighted(
      effective.marks ? markVerbLabel(l10n, effective) : null,
      FormMenuRow<_MarkChoice>(
        glyph: Icons.task_alt_rounded,
        label: l10n.categoryMarkLabel,
        value: effective.marks
            ? markVerbLabel(l10n, effective)
            : l10n.categoryMarkOff,
        selected: _markInEffect,
        menuWidth: FormMetrics.menuWidth,
        identifier: SemanticsIds.categoryEditorMark,
        items: [
          if (kindWord != null)
            FormMenuItem(
              value: _MarkChoice.kind,
              label: kindWord,
              identifier: SemanticsIds.categoryMarkKind,
            ),
          FormMenuItem(
            value: _MarkChoice.own,
            label: customWord ?? l10n.categoryMarkOwn,
            identifier: SemanticsIds.categoryMarkOwn,
          ),
          FormMenuItem(
            value: _MarkChoice.off,
            label: l10n.categoryMarkOff,
            identifier: SemanticsIds.categoryMarkOff,
          ),
        ],
        onSelected: _pickMark,
      ),
    );
  }

  Widget _buildAreaRow(AppLocalizations l10n) {
    final area = _effective.area;
    return _highlighted(
      area,
      FormMenuRow<LifeArea>(
        glyph: Icons.donut_large_rounded,
        label: l10n.categoryAreaLabel,
        value: lifeAreaName(l10n, area),
        selected: area,
        menuWidth: FormMetrics.menuWidth,
        identifier: SemanticsIds.categoryEditorArea,
        items: [
          for (final choice in LifeArea.values)
            FormMenuItem(
              value: choice,
              label: lifeAreaName(l10n, choice),
              identifier: SemanticsIds.categoryArea(choice.name),
            ),
        ],
        onSelected: _pickArea,
      ),
    );
  }

  /// Auto is the kind's own measure and is named as such; a Custom
  /// category's Auto is resolved by the report per period (the S3 spec's O),
  /// so the editor does not guess it.
  Widget _buildMeasureRow(AppLocalizations l10n) {
    final measure = _profile?.measure;
    final auto = _kindRow.primary;
    return _highlighted(
      measure,
      FormMenuRow<_Choice<ReportMeasure>>(
        glyph: Icons.insights_rounded,
        label: l10n.categoryMeasureLabel,
        value: measure == null
            ? l10n.categoryMeasureAuto
            : reportMeasureName(l10n, measure),
        caption: auto == null
            ? l10n.categoryMeasureAutoPerPeriod
            : l10n.categoryMeasureAutoIs(reportMeasureName(l10n, auto)),
        selected: _Choice(measure),
        menuWidth: FormMetrics.menuWidth,
        identifier: SemanticsIds.categoryEditorMeasure,
        items: [
          FormMenuItem(
            value: const _Choice<ReportMeasure>(null),
            label: auto == null
                ? l10n.categoryMeasureAuto
                : l10n.categoryMeasureAutoWith(reportMeasureName(l10n, auto)),
            identifier: SemanticsIds.categoryMeasureAuto,
          ),
          for (final choice in CategoryKinds.headlineMeasures)
            if (choice != auto)
              FormMenuItem(
                value: _Choice(choice),
                label: reportMeasureName(l10n, choice),
                identifier: SemanticsIds.categoryMeasure(choice.name),
              ),
          // A stored measure the editor never offers (sync, a later build)
          // is listed, checked, so the menu says what is in effect.
          if (measure != null &&
              !CategoryKinds.headlineMeasures.contains(measure))
            FormMenuItem(
              value: _Choice(measure),
              label: reportMeasureName(l10n, measure),
              identifier: SemanticsIds.categoryMeasure(measure.name),
            ),
        ],
        onSelected: _pickMeasure,
      ),
    );
  }

  /// Disabled where no counts-as could ever reach a total — Sleep keeps its
  /// own hours, a plain repeat earns none — with the stored value still on
  /// show and the reason as its caption.
  Widget _buildCountsAsRow(AppLocalizations l10n) {
    final effective = _effective;
    final nominal = effective.nominalMinutes;
    final suggested = effective.suggestedMinutes;
    final sleep = effective.kind == CategoryKind.sleep;
    final disabled = sleep || _repeatsOnly;
    String duration(int minutes) =>
        EventTimeFormatter.formatDuration(minutes, l10n);
    final caption = sleep
        ? l10n.categoryCountsAsSleep
        : _repeatsOnly
        ? l10n.categoryCountsAsRepeats
        : suggested != null
        ? l10n.categoryCountsAsSuggested(duration(suggested))
        : l10n.categoryCountsAsScope;
    return _highlighted(
      nominal,
      FormMenuRow<_Choice<int>>(
        glyph: Icons.timelapse_rounded,
        label: l10n.categoryCountsAsLabel,
        value: nominal == null ? l10n.categoryCountsAsOff : duration(nominal),
        caption: caption,
        selected: _Choice(nominal),
        menuWidth: FormMetrics.menuWidth,
        identifier: SemanticsIds.categoryEditorCountsAs,
        items: [
          FormMenuItem(
            value: const _Choice<int>(null),
            label: l10n.categoryCountsAsOff,
            identifier: SemanticsIds.categoryCountsAsOff,
          ),
          for (final minutes in CategoryKinds.countsAsChoices)
            FormMenuItem(
              value: _Choice(minutes),
              label: minutes == suggested
                  ? l10n.categoryCountsAsSuggestedItem(duration(minutes))
                  : duration(minutes),
              identifier: SemanticsIds.categoryCountsAs(minutes),
            ),
        ],
        onSelected: disabled ? null : _pickCountsAs,
      ),
    );
  }

  /// The goal read back as the row's caption, which wraps freely where a
  /// value is clamped at two lines. A primary that takes no goal disables
  /// the row with the reason — unless a goal is stored, which stays
  /// reachable so it can be removed.
  Widget _buildGoalRow(AppLocalizations l10n) {
    final effective = _effective;
    final target = effective.target;
    final primary = effective.primary;
    final blocked = !CategoryGoalLimits.takesGoal(primary);
    final caption = target != null
        ? categoryGoalReadBack(l10n, target, primary)
        : !blocked
        ? l10n.categoryGoalNone
        : primary == null
        ? l10n.categoryGoalNeedsMeasure
        : l10n.categoryGoalNotFor(reportMeasureName(l10n, primary));
    return _highlighted(
      target,
      FormPickerRow(
        glyph: Icons.flag_outlined,
        label: l10n.categoryGoalLabel,
        caption: caption,
        identifier: SemanticsIds.categoryEditorGoal,
        enabled: !blocked || target != null,
        onTap: _pickGoal,
      ),
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
        sandbox: widget.sandbox,
      ),
    );
  }
}
