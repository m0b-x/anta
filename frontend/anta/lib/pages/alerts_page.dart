import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_alerts.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_hub_entry.dart';
import '../models/event_alert.dart';
import '../services/alert_gateway.dart';
import '../services/alert_scheduler.dart';
import '../services/app_navigator.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/agenda_list_view.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/unified_app_bars.dart';

/// Reads what the hub lists. A seam so a widget test can hand rows over
/// without a database, a scheduler or a gateway.
typedef AlertHubLoader = Future<List<AlertHubEntry>> Function();

/// The Alerts hub (§5.6): every alert the phone is about to act on, by day.
///
/// **A view over events' alerts, never a list of its own** — there is no
/// reminder item to create here, and every row leads back to the event that
/// owns it. Enabled alerts come from the registry, so the page says what is
/// armed rather than what a fresh plan would like to be; disabled ones are
/// planned on the spot so the switch that silenced them stays reachable.
///
/// Writes go through the app-wide `CalendarBloc` (`ToggleEventAlert`,
/// `DeleteCalendarEvent`), which is also what guarantees the facades the rows
/// read are configured: the body is only built under `CalendarPageLoaded`.
/// Re-reads ride two signals — a bloc emit (an alert or an event changed) and
/// `AlertScheduler.registryRevision` (the reconcile that change provoked has
/// landed) — and permission state is asked again on every resume, because the
/// banners' own actions return before the user has toggled anything.
class AlertsPage extends StatefulWidget {
  final AlertHubLoader? _loadEntries;
  final AlertGateway? _gateway;

  const AlertsPage({super.key}) : _loadEntries = null, _gateway = null;

  @visibleForTesting
  const AlertsPage.forTesting({
    super.key,
    required AlertHubLoader loadEntries,
    AlertGateway? gateway,
  }) : _loadEntries = loadEntries,
       _gateway = gateway;

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> with WidgetsBindingObserver {
  List<AlertHubEntry> _entries = const [];
  bool _isLoading = true;
  int _loadGeneration = 0;

  AlertGateway? _gateway;
  AlertPermissions? _permissions;

  /// Switch positions the user has set and the store has not echoed yet,
  /// keyed by alert id. Dropped wholesale by the next load, which by then
  /// carries the written value.
  final Map<String, bool> _pendingEnabled = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlertScheduler.registryRevision.addListener(_reload);
    _reload();
    unawaited(_refreshPermissions());
  }

  @override
  void dispose() {
    AlertScheduler.registryRevision.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshPermissions());
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final loader = widget._loadEntries ?? AlertScheduler.hubEntriesOrEmpty;
    final entries = await loader();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
      _pendingEnabled.clear();
    });
  }

  Future<void> _refreshPermissions() async {
    var gateway = widget._gateway;
    if (gateway == null && GetIt.I.isRegistered<AlertGateway>()) {
      gateway = GetIt.I<AlertGateway>();
    }
    final permissions = await gateway?.permissions();
    if (!mounted) return;
    setState(() {
      _gateway = gateway;
      _permissions = permissions;
    });
  }

  void _toggle(AlertHubEntry entry, bool enabled) {
    setState(() => _pendingEnabled[entry.alert.id] = enabled);
    context.read<CalendarBloc>().add(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SettingsAppBar(title: l10n.alertsTitle, showMenuButton: false),
      body: SafeArea(
        top: false,
        child: BlocConsumer<CalendarBloc, CalendarPageState>(
          listener: (context, state) => _reload(),
          builder: (context, state) {
            if (state is! CalendarPageLoaded || _isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildBody(context, l10n);
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final banners = _buildBanners(l10n);
    if (_entries.isEmpty) {
      return Column(
        children: [
          ...banners,
          Expanded(
            child: _EmptyState(
              title: l10n.alertsEmpty,
              body: l10n.alertsEmptyDesc,
            ),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final theme = Theme.of(context);
    final children = <Widget>[...banners];
    DateTime? currentDay;
    for (final entry in _entries) {
      final fireDay = DateTime.utc(
        entry.fireAt.year,
        entry.fireAt.month,
        entry.fireAt.day,
      );
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
      children.add(
        _AlertHubRow(
          key: ValueKey(
            '${entry.alert.id}|${entry.day.millisecondsSinceEpoch}|'
            '${entry.snoozeOsId ?? ''}',
          ),
          entry: entry,
          enabled: _pendingEnabled[entry.alert.id] ?? entry.alert.enabled,
          onTap: () => _open(entry),
          onLongPress: entry.event.removeAfterAlert
              ? () => _cancelRemovable(entry)
              : null,
          onToggle: (value) => _toggle(entry, value),
          onCancelSnooze: () => _cancelSnooze(entry),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: children,
    );
  }

  List<Widget> _buildBanners(AppLocalizations l10n) {
    final permissions = _permissions;
    if (permissions == null) return const [];
    return [
      if (permissions.notifications == AlertPermissionState.denied)
        _PermissionBanner(
          icon: Icons.notifications_off_rounded,
          message: l10n.alertsNotificationsOffBanner,
          actionLabel: l10n.alertsTurnOn,
          onAction: () async {
            await _gateway?.requestNotifications();
            await _refreshPermissions();
          },
        ),
      if (permissions.fullScreenIntent == AlertPermissionState.denied)
        _PermissionBanner(
          icon: Icons.fullscreen_exit_rounded,
          message: l10n.alertsFullScreenOffBanner,
          actionLabel: l10n.alertsTurnOn,
          onAction: () async {
            await _gateway?.openFullScreenIntentSettings();
            await _refreshPermissions();
          },
        ),
    ];
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
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(instant));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isAlarm = entry.alert.mode == AlertMode.ring;
    final original = entry.originalFireAt;
    final dim = enabled || entry.isSnoozed ? 1.0 : _disabledAlpha;
    final tint = CalendarCategories.resolve(entry.event.categoryId).color;
    final describe = entry.alert.describe(l10n, entry.event);

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
              SizedBox(
                width: _timeWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _clock(context, entry.fireAt),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colorScheme.onSurface.withValues(alpha: dim),
                      ),
                    ),
                    if (original != null)
                      Text(
                        _clock(context, original),
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
                            original == null
                                ? describe
                                : l10n.alertsSnoozedRow(describe),
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
                  child: Switch(value: enabled, onChanged: onToggle),
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
