import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_ring_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';
import '../services/app_navigator.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/automation_id.dart';

/// The full-screen surface an alarm rings on (**§5.5**).
///
/// **It renders from the payload alone.** No service, no facade, no database
/// read stands between the ring and the screen: an alarm belonging to a
/// database the user is not currently in still has to show a title, a colour
/// and a time (**A9**), and an alarm recovered after a reboot arrives in a
/// process where nothing is loaded yet. The only thing resolved afterwards is
/// which database is open, and that only decides whether a chip appears.
///
/// Pushed with `AppNavigator.rootPushInstant` and **never stamped as a
/// `NavDestination`**: a restored last location must not reopen a ring that is
/// long over.
///
/// `PopScope(canPop: false)` because back is not Stop. An alarm is stopped
/// deliberately or not at all, and a back gesture that silenced it would be
/// the easiest thing in the world to do in one's sleep.
///
/// It resumes the app, so it inherits the stale-inset hazard the UX section
/// describes — but it has no text field and raises no keyboard, so there is
/// nothing for a stuck `viewInsets` frame to eat. Its widget test says so.
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.payload, this.controller});

  final AlertPayload payload;

  /// A controller the page renders instead of building its own.
  ///
  /// Test-only, and the caller owns it: the page disposes only a controller it
  /// created. The alternative would be a widget test that cannot reach the
  /// database chip at all, since which database is open is the one thing the
  /// payload cannot say.
  @visibleForTesting
  final AlertRingController? controller;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  late final AlertRingController _controller =
      widget.controller ?? AlertRingController(payload: widget.payload);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.endedElsewhere) {
      _close();
      return;
    }
    setState(() {});
  }

  bool _closed = false;

  void _close() {
    if (_closed) return;
    _closed = true;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _stop() async {
    await _controller.stop();
    if (mounted) _close();
  }

  Future<void> _snooze() async {
    await _controller.snooze();
    if (mounted) _close();
  }

  /// Stops first, then opens the day the occurrence belongs to. Stopping is
  /// unconditional: leaving the ring going behind the calendar would be the
  /// one way out of this screen that does not silence the phone.
  Future<void> _openEvent() async {
    // Read before Stop, which is what carries out the removal (**A3**): an
    // event that Stop deletes is opened on its day alone, where the Undo
    // snackbar is, rather than as a detail sheet over a tombstone.
    final removed = _controller.willRemoveEvent;
    await _controller.stop();
    if (!mounted) return;
    _close();
    await AppNavigator.toCalendarOccurrence(
      day: widget.payload.dayUtc,
      eventId: removed ? null : widget.payload.eventId,
    );
  }

  Future<void> _openDatabase() async {
    final l10n = AppLocalizations.of(context)!;
    final switched = await _controller.activateDatabase();
    if (!mounted || !switched) return;
    // The app's existing restart flow, verbatim: a database cannot be swapped
    // under a running process, so the user is told and the app exits.
    await AppDialogs.action(
      context,
      title: l10n.restartRequired,
      content: l10n.restartRequired,
      actionText: l10n.exitApp,
      icon: Icons.restart_alt_rounded,
      onAction: () => SystemNavigator.pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final payload = widget.payload;
    final title = payload.isTest ? l10n.alertsTestAlarm : payload.title;
    final tint = payload.colorValue != null
        ? Color(payload.colorValue!)
        : Color(CalendarCategories.resolve(payload.categoryId).colorValue);
    final icon =
        CalendarIcons.forKey(payload.iconKey) ??
        CalendarIcons.forKey(
          CalendarCategories.resolve(payload.categoryId).iconKey,
        ) ??
        Icons.alarm_rounded;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.alarmPageTitle.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  payload.timeLabel,
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w300,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  _dayLabel(context, payload.dayUtc),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: tint.withValues(alpha: 0.18),
                      child: Icon(icon, color: tint),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_controller.fromOtherDatabase) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.storage_rounded, size: 18),
                      label: Text(l10n.alarmFromDatabase(payload.database)),
                      onPressed: _openDatabase,
                    ),
                  ),
                ],
                if (_controller.willRemoveEvent) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.alarmRemoveAfterCaption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_controller.keepEvent) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.alarmKeptEvent,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                AutomationId(
                  identifier: SemanticsIds.alarmStop,
                  child: FilledButton.icon(
                    onPressed: _controller.busy ? null : _stop,
                    icon: const Icon(Icons.alarm_off_rounded),
                    label: Text(l10n.alarmStop),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AutomationId(
                  identifier: SemanticsIds.alarmSnooze,
                  child: OutlinedButton.icon(
                    onPressed: _controller.busy ? null : _snooze,
                    icon: const Icon(Icons.snooze_rounded),
                    label: Text(
                      l10n.alarmSnoozeMinutes(payload.snoozeMinutes),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AutomationId(
                  identifier: SemanticsIds.alarmOpenEvent,
                  child: TextButton(
                    // Another database's event is not in the calendar this
                    // would open; the chip above is the way to it.
                    onPressed:
                        _controller.busy ||
                            payload.isTest ||
                            _controller.fromOtherDatabase
                        ? null
                        : _openEvent,
                    child: Text(l10n.alarmOpenEvent),
                  ),
                ),
                if (_controller.willRemoveEvent)
                  AutomationId(
                    identifier: SemanticsIds.alarmKeepEvent,
                    child: TextButton(
                      onPressed: _controller.busy ? null : _controller.keep,
                      child: Text(l10n.alarmKeepEvent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The occurrence day, spelled in the app's locale.
  ///
  /// Built per open rather than cached per locale like the agenda's
  /// formatters: this page is shown once per ring, so the cache would only
  /// ever hold one entry.
  static String _dayLabel(BuildContext context, DateTime dayUtc) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.MMMMEEEEd(
      locale,
    ).format(DateTime(dayUtc.year, dayUtc.month, dayUtc.day));
  }
}
