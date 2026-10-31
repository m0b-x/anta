import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:intl/intl.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../bloc/permissions/permissions_bloc.dart';
import '../constants/alert_constants.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_alerts.dart';
import '../constants/event_digests.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_permission_check.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_hub_entry.dart';
import '../models/app_permission.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/event_digest.dart';
import '../services/alert_scheduler.dart';
import '../services/app_navigator.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../utils/alert_labels.dart';
import '../utils/custom_snackbar.dart';
import '../utils/digest_labels.dart';
import '../utils/digest_planner.dart';
import '../widgets/agenda_list_view.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/automation_id.dart';
import '../widgets/digest_editor_sheet.dart';
import '../widgets/form_rows.dart';
import '../widgets/permission_tile.dart';
import '../widgets/unified_app_bars.dart';

/// Reads what the hub lists. A seam so a widget test can hand rows over
/// without a database, a scheduler or a gateway.
typedef AlertHubLoader = Future<List<AlertHubEntry>> Function();

/// Reads the hub's *Recent* section (OS-4), the same seam.
typedef AlertHistoryLoader = Future<List<AlertHistoryEntry>> Function();

/// Reads the digests' next fires (**v42**), the same seam.
typedef DigestHubLoader = Future<List<DigestHubEntry>> Function();

/// The Alerts hub (§5.6): every alert the phone is about to act on, by day.
///
/// **A view over events' alerts, never a list of its own** — there is no
/// reminder item to create here, and every row leads back to the event that
/// owns it. Enabled alerts come from the registry, so the page says what is
/// armed rather than what a fresh plan would like to be; disabled ones are
/// planned on the spot so the switch that silenced them stays reachable.
///
/// The one thing created here is a digest (**v42**, D14): its Digests group
/// heads the page, its fires sit among the alerts' days and its deliveries
/// under Recent. A digest belongs to no event, so the hub is its only home —
/// still never an event alert's.
///
/// Writes go through the app-wide `CalendarBloc` (`ToggleEventAlert`,
/// `DeleteCalendarEvent`, the three digest events), which is also what
/// guarantees the facades the rows read are configured: the body is only
/// built under `CalendarPageLoaded`.
/// Re-reads ride two signals — a bloc emit (an alert or an event changed) and
/// `AlertScheduler.registryRevision` (the reconcile that change provoked has
/// landed). The banners ride a page-scoped `PermissionsBloc`, which mirrors
/// the `PermissionService` snapshot — re-read by the service on every resume,
/// because a banner's own action returns before the user has toggled anything.
class AlertsPage extends StatefulWidget {
  final AlertHubLoader? _loadEntries;
  final AlertHistoryLoader? _loadRecent;
  final DigestHubLoader? _loadDigests;
  final PermissionService? _permissions;

  /// The week start a test hands over in place of the settings read.
  final CalendarWeekStart _testWeekStart;

  /// What runs after an enabled digest is saved — the shared permission
  /// check, or a test's recorder.
  final Future<bool> Function(BuildContext context) _afterDigestSaved;

  const AlertsPage({super.key})
    : _loadEntries = null,
      _loadRecent = null,
      _loadDigests = null,
      _permissions = null,
      _testWeekStart = CalendarWeekStart.monday,
      _afterDigestSaved = AlertPermissionCheck.afterSave;

  @visibleForTesting
  const AlertsPage.forTesting({
    super.key,
    required AlertHubLoader loadEntries,
    AlertHistoryLoader? loadRecent,
    DigestHubLoader? loadDigests,
    PermissionService? permissions,
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    Future<bool> Function(BuildContext context) afterDigestSaved =
        AlertPermissionCheck.afterSave,
  }) : _loadEntries = loadEntries,
       _loadRecent = loadRecent,
       _loadDigests = loadDigests,
       _permissions = permissions,
       _testWeekStart = weekStart,
       _afterDigestSaved = afterDigestSaved;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  List<AlertHubEntry> _entries = const [];

  /// The *Recent* section (OS-4): what the phone did in the last week,
  /// newest first, read beside the live rows on every reload.
  List<AlertHistoryEntry> _recent = const [];

  /// Every digest's next fires, soonest first — a disabled digest's as if it
  /// were on, so its row can say when it would fire.
  List<DigestHubEntry> _digestFires = const [];

  /// The app's week start, which decides whether a weekly span is "this
  /// week" and orders the digest sheet's weekdays.
  CalendarWeekStart _weekStart = CalendarWeekStart.monday;
  bool _isLoading = true;
  int _loadGeneration = 0;

  PermissionsBloc? _permissionsBloc;

  /// Switch positions the user has set and the store has not echoed yet,
  /// keyed by [_pendingKey]. Dropped wholesale by the next load, which by
  /// then carries the written value.
  final Map<String, bool> _pendingEnabled = {};

  /// [_pendingEnabled]'s twin for the Digests group, keyed by digest id.
  final Map<String, bool> _pendingDigestEnabled = {};

  /// Held while the digest sheet is up, so a second tap during its opening
  /// animation cannot stack a second sheet.
  bool _digestSheetOpen = false;

  @override
  void initState() {
    super.initState();
    AlertScheduler.registryRevision.addListener(_reload);
    _reload();
    final permissions = _permissionService();
    if (permissions != null) {
      _permissionsBloc = PermissionsBloc(service: permissions)
        ..add(const PermissionsStarted())
        ..add(const PermissionsRefreshRequested());
    }
  }

  PermissionService? _permissionService() {
    final injected = widget._permissions;
    if (injected != null) return injected;
    if (!GetIt.I.isRegistered<PermissionService>()) return null;
    return GetIt.I<PermissionService>();
  }

  @override
  void dispose() {
    AlertScheduler.registryRevision.removeListener(_reload);
    unawaited(_permissionsBloc?.close());
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final loader = widget._loadEntries ?? AlertScheduler.hubEntriesOrEmpty;
    final history = widget._loadRecent ?? _defaultRecent;
    final digests = widget._loadDigests ?? _defaultDigests;
    final results = await Future.wait<Object>([
      loader(),
      history(),
      digests(),
      _readWeekStart(),
    ]);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _entries = results[0] as List<AlertHubEntry>;
      _recent = results[1] as List<AlertHistoryEntry>;
      _digestFires = results[2] as List<DigestHubEntry>;
      _weekStart = results[3] as CalendarWeekStart;
      _isLoading = false;
      _pendingEnabled.clear();
      _pendingDigestEnabled.clear();
    });
  }

  /// A test that hands over live rows without a history loader gets an empty
  /// section rather than a scheduler lookup.
  Future<List<AlertHistoryEntry>> _defaultRecent() =>
      widget._loadEntries == null
          ? AlertScheduler.recentEntriesOrEmpty()
          : Future.value(const []);

  /// [_defaultRecent]'s rule for the digests' fires.
  Future<List<DigestHubEntry>> _defaultDigests() => widget._loadEntries == null
      ? AlertScheduler.digestEntriesOrEmpty()
      : Future.value(const []);

  /// Read on every load, as the calendar settings may have moved it; a test
  /// handing over rows gets the default rather than a settings lookup.
  Future<CalendarWeekStart> _readWeekStart() async {
    if (widget._loadEntries != null) return widget._testWeekStart;
    try {
      return await (await SettingsService.getInstance()).getCalendarWeekStart();
    } catch (e) {
      debugPrint('[AlertsPage] week start read failed: $e');
      return CalendarWeekStart.monday;
    }
  }

  /// The key [_pendingEnabled] holds a row's switch under: the alert for an
  /// own alert, the event for an inherited one — whose switch is the
  /// event's flag, shared by every inherited row of that event, while the
  /// alert's id is shared by every event in the category.
  static String _pendingKey(AlertHubEntry entry) =>
      entry.alert.categoryId == null
      ? entry.alert.id
      : 'category-alerts:${entry.event.id}';

  /// An own alert's switch is the alert's `enabled`; an inherited alert's is
  /// the event's `categoryAlerts` (D5) — the alert belongs to the category,
  /// and switching it off there would silence every other event in it. The
  /// notice's Skip takes the same meaning for an inherited alert.
  void _toggle(AlertHubEntry entry, bool enabled) {
    final bloc = context.read<CalendarBloc>();
    if (entry.alert.categoryId != null) {
      // The whole event is written back, so it is read at the press from the
      // bloc rather than taken from the row, which holds it as the last load
      // did: an edit since then would be overwritten, a deleted event
      // resurrected.
      final state = bloc.state;
      final current = state is CalendarPageLoaded
          ? state.allEvents.where((e) => e.id == entry.event.id).firstOrNull
          : null;
      if (current == null) return;
      setState(() => _pendingEnabled[_pendingKey(entry)] = enabled);
      bloc.add(
        UpdateCalendarEvent(event: current.copyWith(categoryAlerts: enabled)),
      );
      return;
    }
    setState(() => _pendingEnabled[_pendingKey(entry)] = enabled);
    bloc.add(
      ToggleEventAlert(
        eventId: entry.event.id,
        alertId: entry.alert.id,
        enabled: enabled,
      ),
    );
  }

  Future<void> _cancelSnooze(AlertHubEntry entry) async {
    final osId = entry.snoozeOsId;
    if (osId == null) return;
    await AlertScheduler.cancelSnoozeById(osId);
  }

  /// A3: cancelling an alarm whose event exists only to ring deletes the
  /// event. Undo is an ordinary create, which resurrects the tombstone and
  /// carries back the alerts the cascade took with it — captured before the
  /// delete, while the facade still has them.
  Future<void> _cancelRemovable(AlertHubEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final bloc = context.read<CalendarBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.alertsCancelAlarm,
      content: l10n.alertsCancelAlarmConfirm(entry.event.title),
      confirmText: l10n.alertsCancelAlarm,
      icon: Icons.alarm_off_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final alerts = List<EventAlert>.of(EventAlerts.alertsFor(entry.event.id));
    bloc.add(DeleteCalendarEvent(eventId: entry.event.id));
    CustomSnackbar.showWithAction(
      context,
      message: l10n.eventAlertEventRemoved,
      actionLabel: l10n.undo,
      onAction: () =>
          bloc.add(CreateCalendarEvent(event: entry.event, alerts: alerts)),
    );
  }

  void _open(AlertHubEntry entry) {
    unawaited(
      AppNavigator.toCalendarOccurrence(
        day: entry.day,
        eventId: entry.event.id,
      ),
    );
  }

  void _toggleDigest(EventDigest digest, bool enabled) {
    setState(() => _pendingDigestEnabled[digest.id] = enabled);
    context.read<CalendarBloc>().add(
      ToggleEventDigest(digest.id, enabled: enabled),
    );
  }

  /// Opens the digest sheet on [digest], or on a new one, and hands what it
  /// returns to the bloc — the sheet writes nothing and neither does the
  /// hub. The events it counts over are read at the press, as the alert
  /// rows read theirs.
  ///
  /// Never for a digest this build cannot read: its sheet would show the
  /// defaults it fell back to, and a save would overwrite the newer build's.
  Future<void> _openDigest(EventDigest? digest) async {
    if (_digestSheetOpen || (digest != null && !digest.isReadable)) return;
    final bloc = context.read<CalendarBloc>();
    final state = bloc.state;
    _digestSheetOpen = true;
    final DigestEditorResult? result;
    try {
      result = await DigestEditorSheet.show(
        context,
        initial: digest,
        events: state is CalendarPageLoaded
            ? state.allEvents
            : const <CalendarEvent>[],
        weekStart: _weekStart,
      );
    } finally {
      _digestSheetOpen = false;
    }
    if (!mounted) return;
    switch (result) {
      case DigestEditorSaved(:final digest):
        bloc.add(SaveEventDigest(digest));
        // A digest is a notification: the first one ever may need the
        // permission to post, which only a save can ask for in context.
        if (digest.enabled) unawaited(widget._afterDigestSaved(context));
      case DigestEditorDeleted(:final id):
        bloc.add(DeleteEventDigest(id));
      case null:
        break;
    }
  }

  /// The digest a fire or a delivery names, as the facade holds it now — the
  /// row's copy is the last load's.
  void _openDigestById(EventDigest digest) =>
      unawaited(_openDigest(EventDigests.byId(digest.id) ?? digest));

  String _categoryLabel(String id, AppLocalizations l10n) =>
      CalendarCategories.labelOf(CalendarCategories.resolve(id), l10n);

  String _digestTitle(EventDigest digest, AppLocalizations l10n) =>
      digestTitleOf(
        digest,
        l10n,
        categoryLabel: (id) => _categoryLabel(id, l10n),
      );

  String _digestDescribe(EventDigest digest, AppLocalizations l10n) =>
      digestDescribe(
        digest,
        l10n,
        formatMinute: (minute) =>
            EventTimeFormatter.formatMinute(minute, context),
        weekdayName: (weekday) => digestWeekdayName(weekday, l10n.localeName),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The page ground the mock draws, one tone under the Digests group's
    // `rowGroup` in both themes; the bar sits on it so no seam shows.
    final ground = Theme.of(context).colorScheme.pageGround;
    return Scaffold(
      backgroundColor: ground,
      appBar: SettingsAppBar(
        title: l10n.alertsTitle,
        showMenuButton: false,
        backgroundColor: ground,
        identifier: SemanticsIds.settingsBarAlerts,
      ),
      body: SafeArea(
        top: false,
        child: BlocConsumer<CalendarBloc, CalendarPageState>(
          listener: (context, state) => _reload(),
          builder: (context, state) {
            if (state is! CalendarPageLoaded || _isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final permissionsBloc = _permissionsBloc;
            if (permissionsBloc == null) {
              return _buildBody(context, l10n, const []);
            }
            return BlocBuilder<PermissionsBloc, PermissionsState>(
              bloc: permissionsBloc,
              buildWhen: (previous, current) =>
                  previous.snapshotOrNull != current.snapshotOrNull,
              builder: (context, permissions) => _buildBody(
                context,
                l10n,
                _buildBanners(l10n, permissions.snapshotOrNull),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    List<Widget> banners,
  ) {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final theme = Theme.of(context);
    final labels = AlertLabels(
      strings: l10n,
      use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    // Only an enabled digest's fires are coming; a disabled one's are what
    // its group row says it would do. Read through the facade, so a digest
    // switched or deleted since the last load is not listed as it was.
    final digestFires = [
      for (final fire in _digestFires)
        if (EventDigests.byId(fire.digest.id) case final digest?
            when _pendingDigestEnabled[digest.id] ?? digest.enabled)
          (fire: fire, digest: digest),
    ];
    final group = _buildDigestGroup(l10n);
    final empty = _entries.isEmpty && digestFires.isEmpty;
    // Nothing at all to show: the empty state takes the page's middle as it
    // always has, under the group's one Add row.
    if (empty &&
        _recent.isEmpty &&
        banners.isEmpty &&
        EventDigests.all.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          group,
          Expanded(
            child: _EmptyState(
              title: l10n.alertsEmpty,
              body: l10n.alertsEmptyDesc,
            ),
          ),
        ],
      );
    }
    final children = <Widget>[...banners, group];
    if (empty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: RowMetrics.groupGap),
          child: _EmptyState(
            title: l10n.alertsEmpty,
            body: l10n.alertsEmptyDesc,
          ),
        ),
      );
    }
    // The alerts and the digests' fires merged in one order — both lists come
    // soonest first — a digest first at a shared instant: it is the summary
    // the alerts after it belong to.
    DateTime? currentDay;
    var nextAlert = 0;
    var nextDigest = 0;
    while (nextAlert < _entries.length || nextDigest < digestFires.length) {
      final takeDigest =
          nextDigest < digestFires.length &&
          (nextAlert >= _entries.length ||
              !digestFires[nextDigest].fire.fireAt.isAfter(
                _entries[nextAlert].fireAt,
              ));
      final fireAt = takeDigest
          ? digestFires[nextDigest].fire.fireAt
          : _entries[nextAlert].fireAt;
      final fireDay = DateTime.utc(fireAt.year, fireAt.month, fireAt.day);
      if (fireDay != currentDay) {
        currentDay = fireDay;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              AgendaListView.dayHeaderLabel(l10n, fireDay, today),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      if (takeDigest) {
        final (:fire, :digest) = digestFires[nextDigest++];
        children.add(
          _DigestFireRow(
            // Its own key shape: a digest has no event, and two fires of one
            // digest differ by their instant.
            key: ValueKey(
              'digest|${digest.id}|${fire.fireAt.toIso8601String()}',
            ),
            digest: digest,
            fireAt: fire.fireAt,
            title: _digestTitle(digest, l10n),
            subtitle: l10n.digestCountPeriod(
              fire.count,
              digestPeriodOf(
                digest,
                spanStart: fire.spanStart,
                spanEnd: fire.spanEnd,
                strings: l10n,
                labels: labels,
                weekStart: _weekStart,
              ),
            ),
            onTap: () => _openDigestById(digest),
          ),
        );
        continue;
      }
      final entry = _entries[nextAlert++];
      children.add(
        _AlertHubRow(
          // The event as well as the alert: an inherited alert's one id is
          // shared by every event in its category, on the same day too.
          key: ValueKey(
            '${entry.event.id}|${entry.alert.id}|'
            '${entry.day.millisecondsSinceEpoch}|${entry.snoozeOsId ?? ''}',
          ),
          entry: entry,
          enabled:
              _pendingEnabled[_pendingKey(entry)] ??
              (entry.alert.categoryId == null
                  ? entry.alert.enabled
                  : entry.event.categoryAlerts),
          onTap: () => _open(entry),
          onLongPress: entry.event.removeAfterAlert
              ? () => _cancelRemovable(entry)
              : null,
          onToggle: (value) => _toggle(entry, value),
          onCancelSnooze: () => _cancelSnooze(entry),
        ),
      );
    }
    if (_recent.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Text(
            l10n.alertsRecent,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      for (final entry in _recent) {
        // The registry holds no count for a delivery, so a digest's row says
        // how it fires instead of what it said.
        final digest = entry.digest;
        if (digest != null) {
          children.add(
            _AlertHistoryRow(
              key: ValueKey(
                'recent|digest|${digest.id}|'
                '${entry.fireAt.millisecondsSinceEpoch}|'
                '${entry.settledAt.millisecondsSinceEpoch}',
              ),
              entry: entry,
              today: today,
              digestTitle: _digestTitle(digest, l10n),
              digestDescribe: _digestDescribe(digest, l10n),
              onTap: () => _openDigestById(digest),
            ),
          );
          continue;
        }
        children.add(
          _AlertHistoryRow(
            key: ValueKey(
              'recent|${entry.fireAt.millisecondsSinceEpoch}|'
              '${entry.event?.id ?? ''}|${entry.alert?.id ?? ''}|'
              '${entry.settledAt.millisecondsSinceEpoch}',
            ),
            entry: entry,
            today: today,
            onTap: entry.event == null
                ? null
                : () => unawaited(
                    AppNavigator.toCalendarOccurrence(
                      day: entry.day,
                      eventId: entry.event!.id,
                    ),
                  ),
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: children,
    );
  }

  /// The Digests group (§6.4): one row per digest in display order — what it
  /// is called over how it fires and when next, its switch at the end — then
  /// Add digest while there is room under the cap. On the UI language from
  /// its first day; the rows under it keep their look until Tier 4.
  Widget _buildDigestGroup(AppLocalizations l10n) {
    final digests = EventDigests.all;
    // Sync can carry a database past the cap, and the planner then arms the
    // first ten silently: without this a card the user switched on would read
    // exactly like one that fires. Read through the switches the store has
    // not echoed yet, as the rows are: a cap set built from the stored flags
    // alone would still caption the eleventh digest unarmed after the user
    // has just switched the tenth off, and say nothing about an eleventh the
    // user has just switched on.
    final overCap = DigestPlanner.overCapIds(
      digests: [
        for (final digest in digests)
          if (_pendingDigestEnabled[digest.id] case final pending?)
            digest.copyWith(enabled: pending)
          else
            digest,
      ],
      horizon: kDigestHorizon,
    );
    final nextFire = <String, DateTime>{};
    for (final fire in _digestFires) {
      nextFire.putIfAbsent(fire.digest.id, () => fire.fireAt);
    }
    final dayFormat = DateFormat.MMMEd(l10n.localeName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset,
        FormMetrics.bodyTop,
        RowMetrics.groupInset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormSectionLabel(text: l10n.alertsDigestChannel),
          FormRowGroup(
            trailingGap: false,
            children: [
              for (final digest in digests)
                _digestRow(
                  digest,
                  nextFire[digest.id],
                  dayFormat,
                  l10n,
                  overCap: overCap.contains(digest.id),
                ),
              if (digests.length < kDigestHorizon.maxDigests)
                FormActionRow(
                  glyph: Icons.add_rounded,
                  label: l10n.digestsAdd,
                  identifier: SemanticsIds.alertsDigestAdd,
                  onTap: () => unawaited(_openDigest(null)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// One digest's row: what it is called over how it fires and, while it is
  /// on, when next — a switched-off digest promises no fire, and dims as a
  /// switched-off alert's row does. A digest this build cannot read says so,
  /// with its switch disabled and no sheet behind it.
  ///
  /// [overCap] is an enabled digest the pass will not arm, because the
  /// database holds more than [DigestHorizon.maxDigests] of them (sync can
  /// carry it there). Its caption says so in place of the next fire it has
  /// none of: the switch is on and reads as on, and the row is otherwise the
  /// same row — the anatomy is Tier 4's, not this fix's.
  Widget _digestRow(
    EventDigest digest,
    DateTime? next,
    DateFormat dayFormat,
    AppLocalizations l10n, {
    bool overCap = false,
  }) {
    final enabled = _pendingDigestEnabled[digest.id] ?? digest.enabled;
    final describe = _digestDescribe(digest, l10n);
    return FormPickerSwitchRow(
      key: ValueKey('digest-row|${digest.id}'),
      glyph: Icons.summarize_rounded,
      label: _digestTitle(digest, l10n),
      caption: !digest.isReadable
          ? l10n.digestUnreadable
          : overCap && enabled
          ? '$describe · ${l10n.digestOverLimit(kDigestHorizon.maxDigests)}'
          : next == null || !enabled
          ? describe
          : '$describe · ${l10n.digestNextFire(dayFormat.format(next))}',
      captionMaxLines: 2,
      value: enabled,
      dimOff: true,
      identifier: SemanticsIds.alertsDigestRow(digest.id),
      switchIdentifier: SemanticsIds.alertsDigestSwitch(digest.id),
      onTap: () => unawaited(_openDigest(digest)),
      onChanged: digest.isReadable
          ? (value) => _toggleDigest(digest, value)
          : null,
    );
  }

  ({IconData icon, String message})? _bannerFor(
    AppLocalizations l10n,
    AppPermission permission,
  ) => switch (permission) {
    AppPermission.notifications => (
      icon: Icons.notifications_off_rounded,
      message: l10n.alertsNotificationsOffBanner,
    ),
    AppPermission.exactAlarms => (
      icon: Icons.alarm_off_rounded,
      message: l10n.alertsExactAlarmsOffBanner,
    ),
    AppPermission.fullScreenIntent => (
      icon: Icons.fullscreen_exit_rounded,
      message: l10n.alertsFullScreenOffBanner,
    ),
    AppPermission.batteryOptimization => null,
  };

  List<Widget> _buildBanners(
    AppLocalizations l10n,
    PermissionSnapshot? snapshot,
  ) {
    if (snapshot == null) return const [];
    final banners = <Widget>[];
    for (final entry in snapshot.missing) {
      final banner = _bannerFor(l10n, entry.permission);
      if (banner == null) continue;
      banners.add(
        _PermissionBanner(
          icon: banner.icon,
          message: banner.message,
          actionLabel: PermissionPresentation.actionOf(l10n, entry),
          onAction: () =>
              _permissionsBloc?.add(PermissionRequested(entry.permission)),
        ),
      );
    }
    return banners;
  }
}

class _AlertHubRow extends StatelessWidget {
  final AlertHubEntry entry;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCancelSnooze;

  static const double _timeWidth = 64;
  static const double _glyphSize = 14;
  static const double _disabledAlpha = 0.5;

  const _AlertHubRow({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
    required this.onCancelSnooze,
  });

  String _clock(BuildContext context, DateTime instant) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(instant),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAlarm = entry.alert.mode == AlertMode.ring;
    final original = entry.originalFireAt;
    final dim = enabled || entry.isSnoozed ? 1.0 : _disabledAlpha;
    final tint = EventSummaryProvider.colorFor(
      entry.event,
      CalendarCategories.resolve(entry.event.categoryId),
    );
    final describe = entry.alert.describe(
      l10n,
      entry.event,
      formatMinute: (minute) =>
          EventTimeFormatter.formatMinute(minute, context),
    );
    final categoryId = entry.alert.categoryId;
    final timing = original == null
        ? describe
        : l10n.alertsSnoozedRow(describe);
    // An inherited alert says where it comes from, which is also what its
    // switch stands for: the event's opt-out, not the alert.
    final subtitle = switch (categoryId) {
      null => timing,
      final id => [
        timing,
        l10n.eventAlertFromCategory(
          CalendarCategories.labelOf(CalendarCategories.resolve(id), l10n),
        ),
      ].join(' · '),
    };

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Grows with the text scale, and past it with the time itself:
              // a fixed 64 dp broke "09:00" over two lines at 200 %.
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.textScalerOf(context).scale(_timeWidth),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _clock(context, entry.fireAt),
                      softWrap: false,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colorScheme.onSurface.withValues(alpha: dim),
                      ),
                    ),
                    if (original != null)
                      Text(
                        _clock(context, original),
                        softWrap: false,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: colorScheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                CalendarCategories.iconFor(entry.event),
                size: 20,
                color: tint.withValues(alpha: dim),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: dim),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Icon(
                          isAlarm
                              ? Icons.alarm_rounded
                              : Icons.notifications_active_rounded,
                          size: _glyphSize,
                          color:
                              (isAlarm
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant)
                                  .withValues(alpha: dim),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: dim,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (entry.isSnoozed)
                IconButton(
                  tooltip: l10n.alertsCancelSnooze,
                  icon: const Icon(Icons.alarm_off_rounded),
                  onPressed: onCancelSnooze,
                )
              else
                Semantics(
                  label: l10n.alertsToggleLabel(entry.event.title),
                  hint: categoryId == null ? null : l10n.eventCategoryAlerts,
                  child: Switch(value: enabled, onChanged: onToggle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One fire of an enabled digest among the day groups: [_AlertHubRow]'s
/// shape — the time, what it lists, the count line under the digest's glyph
/// — with no switch of its own (M3 · A: the group's switch is the one
/// control), its slot held empty so the column of switches stays put.
class _DigestFireRow extends StatelessWidget {
  final EventDigest digest;
  final DateTime fireAt;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const double _timeWidth = 64;
  static const double _glyphSize = 14;

  const _DigestFireRow({
    super.key,
    required this.digest,
    required this.fireAt,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final look = _digestLook(digest, colorScheme);
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: AutomationId(
        identifier: SemanticsIds.alertsDigestFire(digest.id, fireAt),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                // [_AlertHubRow]'s time slot: scaled, never wrapped.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.textScalerOf(
                      context,
                    ).scale(_timeWidth),
                  ),
                  child: Text(
                    MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(fireAt),
                      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                        context,
                      ),
                    ),
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(look.icon, size: 20, color: look.color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Icon(
                            Icons.summarize_rounded,
                            size: _glyphSize,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // The alert rows' switch, unseen and inert: its exact box.
                const ExcludeSemantics(
                  child: Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Switch(value: false, onChanged: null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The glyph and tint a digest's day and history rows lead with: what it
/// lists — one category's own icon in its colour, else the digest glyph.
({IconData icon, Color color}) _digestLook(
  EventDigest digest,
  ColorScheme colorScheme,
) {
  if (digest.categoryIds.length == 1) {
    final category = CalendarCategories.resolve(digest.categoryIds.single);
    return (
      icon: CalendarIcons.forKey(category.iconKey) ?? Icons.summarize_rounded,
      color: category.color,
    );
  }
  return (icon: Icons.summarize_rounded, color: colorScheme.primary);
}

/// One row of the *Recent* section: the day and time it was armed for, the
/// outcome's glyph, the event's title (or the removed fallback) and what the
/// alert was — or, for a digest's delivery, the digest's title and how it
/// fires.
class _AlertHistoryRow extends StatelessWidget {
  final AlertHistoryEntry entry;
  final DateTime today;
  final VoidCallback? onTap;

  /// Set for a digest's delivery, whose entry carries neither an event nor
  /// an alert to name it by.
  final String? digestTitle;
  final String? digestDescribe;

  static const double _timeWidth = 64;
  static const double _glyphSize = 14;

  const _AlertHistoryRow({
    super.key,
    required this.entry,
    required this.today,
    required this.onTap,
    this.digestTitle,
    this.digestDescribe,
  });

  static IconData iconFor(AlertOutcome outcome) => switch (outcome) {
    AlertOutcome.rang => Icons.alarm_on_rounded,
    AlertOutcome.stopped => Icons.check_circle_outline_rounded,
    AlertOutcome.snoozed => Icons.snooze_rounded,
    AlertOutcome.missed => Icons.alarm_off_rounded,
    AlertOutcome.delivered => Icons.notifications_active_rounded,
  };

  static String labelFor(AppLocalizations l10n, AlertOutcome outcome) =>
      switch (outcome) {
        AlertOutcome.rang => l10n.alertsOutcomeRang,
        AlertOutcome.stopped => l10n.alertsOutcomeStopped,
        AlertOutcome.snoozed => l10n.alertsOutcomeSnoozed,
        AlertOutcome.missed => l10n.alertsOutcomeMissed,
        AlertOutcome.delivered => l10n.alertsOutcomeDelivered,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final event = entry.event;
    final alert = entry.alert;
    final fireDay = DateTime.utc(
      entry.fireAt.year,
      entry.fireAt.month,
      entry.fireAt.day,
    );
    final missed = entry.outcome == AlertOutcome.missed;
    final digest = entry.digest;
    final digestLook = digest == null ? null : _digestLook(digest, colorScheme);
    final tint =
        digestLook?.color ??
        (event == null
            ? colorScheme.onSurfaceVariant
            : EventSummaryProvider.colorFor(
                event,
                CalendarCategories.resolve(event.categoryId),
              ));
    final describe = event == null || alert == null
        ? digestDescribe
        : alert.describe(
            l10n,
            event,
            formatMinute: (minute) =>
                EventTimeFormatter.formatMinute(minute, context),
          );
    final subtitle = describe == null
        ? labelFor(l10n, entry.outcome)
        : '${labelFor(l10n, entry.outcome)} · $describe';

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              // [_AlertHubRow]'s time slot scaled and never wrapped, but a
              // fixed width: the day label under the time is clamped to it,
              // and a slot that grew with its text grew with "Yesterday".
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(_timeWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay.fromDateTime(entry.fireAt),
                        alwaysUse24HourFormat:
                            MediaQuery.alwaysUse24HourFormatOf(context),
                      ),
                      softWrap: false,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      AgendaListView.dayHeaderLabel(l10n, fireDay, today),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                digestLook?.icon ??
                    (event == null
                        ? Icons.event_busy_rounded
                        : CalendarCategories.iconFor(event)),
                size: 20,
                color: tint,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      digestTitle ?? event?.title ?? l10n.alertsHistoryRemoved,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Icon(
                          iconFor(entry.outcome),
                          size: _glyphSize,
                          color: missed
                              ? colorScheme.error
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: missed
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _PermissionBanner({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.onErrorContainer),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onErrorContainer,
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
