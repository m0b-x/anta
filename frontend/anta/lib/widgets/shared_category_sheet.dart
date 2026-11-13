import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/share/share_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_alerts.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_permission_check.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/category_alert.dart';
import '../models/partner_look.dart';
import '../models/recurrence_rule.dart';
import '../models/share_overview.dart';
import '../models/share_settings.dart';
import '../services/alert_scheduler.dart';
import '../services/event_alert_service.dart';
import '../services/event_time_formatter.dart';
import '../utils/share_copy.dart';
import 'alert_editor_sheet.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';

/// A category in the partner's look, as the sharing lists draw it: the
/// Outlined ring, the Avatar badge or the plain fill. Silent — the list's
/// title already says whose they are (decision dk), so no row repeats it.
EventAvatar sharedCategoryAvatar(CalendarCategory category, PartnerLook look) =>
    EventAvatar(
      icon: CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded,
      color: Color(category.colorValue),
      outlined: look.outlined,
      badge: look.avatar ? EventAvatarBadge.partner(look.partner) : null,
    );

/// One of the partner's own categories, from my side (share surfaces §6.4,
/// the slice D spec §3): who it is from, whether it shows on my calendar,
/// and my own alerts for it — rows of mine keyed by the partner's category
/// id, which ring only under "Category alerts too" and while it is shown.
///
/// Live-apply: the switch goes through [bloc], every alert is written as it
/// is made. It follows [bloc] while open, and closes its own route, without
/// a word, once the overview no longer lists the category (un-shared, the
/// pair ended) — the list it was opened from says the rest.
///
/// A shared built-in has no such sheet: my own category editor governs it.
class SharedCategorySheet extends StatefulWidget {
  final ShareBloc bloc;
  final String categoryId;
  final PartnerLook partner;

  const SharedCategorySheet({
    super.key,
    required this.bloc,
    required this.categoryId,
    required this.partner,
  });

  /// The plan pass every alert write here is followed by: a category alert
  /// touches every event in the category, so the whole plan is redone
  /// (D22). A test swaps it to count the passes without an alarm gateway.
  @visibleForTesting
  static Future<void> Function(AlertReconcileReason reason) reconcile =
      AlertScheduler.reconcileAllQuietly;

  /// A sub-sheet: content-tall under the editor's height, the route's own
  /// drag, nothing to guard — every control writes at once.
  static Future<void> show(
    BuildContext context, {
    required ShareBloc bloc,
    required String categoryId,
    required PartnerLook partner,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
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
        // An alert added or removed through the alert sheet resizes it.
        child: FormSheetSemanticsRefresh(
          child: SharedCategorySheet(
            bloc: bloc,
            categoryId: categoryId,
            partner: partner,
          ),
        ),
      ),
    );
  }

  @override
  State<SharedCategorySheet> createState() => _SharedCategorySheetState();
}

class _SharedCategorySheetState extends State<SharedCategorySheet> {
  /// The category as the overview last listed it: what the sheet draws in
  /// the frame its leave is heard in.
  PartnerSharedCategory? _shared;

  /// My alerts for the category, as this sheet last wrote them.
  late List<CategoryAlert> _alerts;

  /// The ids the last write left stored — the only ones the next may
  /// remove; another device's alert added meanwhile stays. Seeded in
  /// [initState], never lazily: read first by a write, it would take that
  /// write's rows.
  late Set<String> _known;

  /// The writes, one after another: two quick taps both hold, in order.
  Future<void> _writes = Future<void>.value();

  /// Bumped by a failed write, so the writes queued behind it — drawn from
  /// rows that were never stored — are dropped rather than fail again.
  int _generation = 0;

  bool _alertSheetOpen = false;

  /// Whether this sheet has asked to pop; a second pop would take the route
  /// underneath.
  bool _popped = false;

  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  static Set<String> _idsOf(List<CategoryAlert> alerts) => {
    for (final alert in alerts) alert.id,
  };

  @override
  void initState() {
    super.initState();
    _alerts = EventAlerts.categoryAlertsFor(widget.categoryId);
    _known = _idsOf(_alerts);
    _bodyScroll.addListener(_onBodyScroll);
    final state = widget.bloc.state;
    _shared = _entryIn(state);
    if (state is ShareLoaded && _shared == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  PartnerSharedCategory? _entryIn(ShareState state) {
    if (state is! ShareLoaded) return null;
    for (final shared in state.overview.partnerCategories) {
      if (shared.category.id == widget.categoryId && !shared.joinsMine) {
        return shared;
      }
    }
    return null;
  }

  void _onState(BuildContext context, ShareState state) {
    if (state is! ShareLoaded) return;
    final shared = _entryIn(state);
    if (shared == null) {
      _close();
    } else {
      _shared = shared;
    }
  }

  /// Pops this sheet's own route. The leave can land under an alert editor
  /// or a permission dialog; those close first — an alert for a category
  /// that is gone has nothing to save — so the pop reaches this route,
  /// never theirs.
  void _close() {
    if (_popped) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (!route.isCurrent) navigator.popUntil((above) => above == route);
    _popped = true;
    navigator.pop();
  }

  /// A stand-in event of this category carrying the one property
  /// `EventAlert.describe` reads, the derived `allDay`, as the category
  /// editor drafts it: a category alert serves both shapes.
  CalendarEvent _previewEvent({required bool allDay}) => CalendarEvent(
    id: '',
    title: '',
    categoryId: widget.categoryId,
    startDate: DateTime.utc(2026),
    rule: const OneTimeRecurrence(),
    time: allDay ? null : const EventTime(startMinute: 0),
  );

  /// Shows [next] at once and queues its write. [canRing] is an add, an
  /// edit or an enable — a write after which the permission check runs, as
  /// it does after every saved alert that can fire.
  ///
  /// What the write's follow-ups need is taken here, while the sheet is
  /// up: a write can end after it has closed, and the calendar's notice
  /// and the permission check are owed all the same.
  void _write(List<CategoryAlert> next, {required bool canRing}) {
    setState(() => _alerts = List.unmodifiable(next));
    final alerts = _alerts;
    final generation = _generation;
    // Nullable: a host without the app's bloc has no badges to redraw.
    final calendar = context.read<CalendarBloc?>();
    // The navigator's context, which outlives this sheet.
    final host = Navigator.of(context).context;
    void checkPermission() => unawaited(AlertPermissionCheck.afterSave(host));
    _writes = _writes.then((_) {
      if (generation != _generation) return null;
      return _store(
        alerts,
        canRing: canRing,
        calendar: calendar,
        checkPermission: checkPermission,
      );
    });
  }

  Future<void> _store(
    List<CategoryAlert> alerts, {
    required bool canRing,
    required CalendarBloc? calendar,
    required VoidCallback checkPermission,
  }) async {
    try {
      final service = await EventAlertService.getInstance();
      await service.replaceForCategory(
        widget.categoryId,
        alerts,
        knownIds: _known,
      );
      _known = _idsOf(alerts);
    } catch (e) {
      debugPrint('[SharedCategorySheet] alerts not written: $e');
      _generation++;
      // What stands is what storage holds; the rows say so.
      final stored = EventAlerts.categoryAlertsFor(widget.categoryId);
      _known = _idsOf(stored);
      if (!mounted) return;
      setState(() => _alerts = stored);
      OverlaySnackbar.show(
        context,
        AppLocalizations.of(context)!.saveStatusError,
        duration: AppConstants.snackbarErrorDuration,
      );
      return;
    }
    unawaited(SharedCategorySheet.reconcile(AlertReconcileReason.eventChanged));
    if (calendar != null && !calendar.isClosed) {
      calendar.add(const CategoryAlertsChanged());
    }
    if (canRing && alerts.any((alert) => alert.enabled)) checkPermission();
  }

  Future<void> _addAlert() async {
    if (_alertSheetOpen || _popped) return;
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
    if (!mounted || _popped) return;
    if (result case AlertEditorSaved(:final alert)) {
      _write([
        ..._alerts,
        CategoryAlert.fromEventAlert(alert, categoryId: widget.categoryId),
      ], canRing: true);
    }
  }

  Future<void> _editAlert(CategoryAlert alert) async {
    if (_alertSheetOpen || _popped) return;
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
    if (!mounted || _popped || result == null) return;
    switch (result) {
      case AlertEditorRemoved():
        _write([
          for (final existing in _alerts)
            if (existing.id != alert.id) existing,
        ], canRing: false);
      case AlertEditorSaved(alert: final saved):
        _write([
          for (final existing in _alerts)
            existing.id == alert.id
                ? CategoryAlert.fromEventAlert(
                    saved,
                    categoryId: widget.categoryId,
                  )
                : existing,
        ], canRing: true);
    }
  }

  void _setAlertEnabled(CategoryAlert alert, bool enabled) {
    _write([
      for (final existing in _alerts)
        existing.id == alert.id
            ? existing.copyWith(enabled: enabled)
            : existing,
    ], canRing: enabled);
  }

  /// The category editor's alert rows, then Add alert under the cap. Inert
  /// keeps them in place, disabled: what the group would do is still read.
  List<Widget> _alertRows(AppLocalizations l10n, {required bool inert}) {
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
          caption: ShareCopy.caption([
            l10n.categoryAlertTimedCaption(
              alert.toEventAlert('').describe(l10n, timed),
            ),
            alert.isAlarm ? l10n.eventAlertModeRing : l10n.eventAlertModeNotify,
          ]),
          identifier: SemanticsIds.sharedCategoryAlert(index),
          switchIdentifier: SemanticsIds.sharedCategoryAlertSwitch(index),
          value: alert.enabled,
          enabled: !inert,
          onTap: () => _editAlert(alert),
          onChanged: (value) => _setAlertEnabled(alert, value),
        ),
      if (_alerts.length < kMaxAlertsPerCategory)
        FormActionRow(
          glyph: Icons.add_rounded,
          label: l10n.eventAlertAdd,
          identifier: SemanticsIds.sharedCategoryAddAlert,
          onTap: inert ? null : _addAlert,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ShareBloc, ShareState>(
      bloc: widget.bloc,
      listener: _onState,
      builder: (context, state) {
        final shared = _entryIn(state) ?? _shared;
        if (shared == null) return const SizedBox.shrink();
        final alerts = state is ShareLoaded ? state.alerts : ShareAlerts.own;
        return _body(context, shared, alerts);
      },
    );
  }

  Widget _body(
    BuildContext context,
    PartnerSharedCategory shared,
    ShareAlerts setting,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final name = ShareCopy.partnerName(l10n, widget.partner.name);
    final category = shared.category;
    final ringing = setting == ShareAlerts.category;
    // Under the other two settings nothing of the partner's rings from a
    // category, and a hidden category has no events here to ring for
    // (decision dl).
    final inert = !ringing || !shared.shown;
    FormCaption caption(String text) =>
        FormCaption(text: text, padding: FormMetrics.groupCaptionPadding);
    final candidates = ringing
        ? [
            caption(l10n.categoryAlertsHint),
            caption(l10n.shareHiddenCategoryAlertsCaption),
          ]
        : [caption(l10n.shareCategoryAlertsOffCaption)];
    final current = !ringing
        ? l10n.shareCategoryAlertsOffCaption
        : shared.shown
        ? l10n.categoryAlertsHint
        : l10n.shareHiddenCategoryAlertsCaption;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Semantics(
      container: true,
      identifier: SemanticsIds.sharedCategorySheet,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          // "Category" whatever the name: the title row under it carries the
          // name and whose it is (decision dh).
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.close,
            onLeading: _close,
            title: l10n.eventCategory,
            scrolled: _headerScrolled,
            trailing: const SizedBox.shrink(),
            titleIsHeading: true,
          ),
          Flexible(
            child: SingleChildScrollView(
              controller: _bodyScroll,
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FormRowGroup(
                    children: [
                      FormReadTitleRow(
                        leading: sharedCategoryAvatar(category, widget.partner),
                        title: CalendarCategories.labelOf(category, l10n),
                        caption: l10n.shareFromPartner(name),
                      ),
                      FormSwitchRow(
                        glyph: Icons.visibility_outlined,
                        label: l10n.shareShowOnCalendar,
                        value: shared.shown,
                        onChanged: (shown) => widget.bloc.add(
                          ShareCategoryShownSet(category.id, shown: shown),
                        ),
                        identifier: SemanticsIds.sharedCategorySheetShow,
                      ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.eventAlerts),
                  FormRowGroup(
                    trailingGap: false,
                    children: _alertRows(l10n, inert: inert),
                  ),
                  // The words change with the show switch, never the height.
                  FormCaptionSlot(
                    candidates: candidates,
                    child: caption(current),
                  ),
                  // A section label has no top padding of its own and the
                  // caption no bottom one: the gap a group would leave.
                  const SizedBox(height: RowMetrics.groupGap),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
