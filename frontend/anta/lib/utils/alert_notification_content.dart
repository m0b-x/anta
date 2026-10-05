import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';

/// The notifications an alert can put on the phone.
enum AlertNotificationKind {
  /// The alarm tier's own notification, drawn by the `alarm` plugin while it
  /// rings: the heads-up when the phone is in use.
  ring,

  /// The reminder tier's notification.
  reminder,

  /// A reminder posted again by its own Snooze.
  snoozed,

  /// The quiet notice posted ahead of an alarm.
  notice,

  /// The quiet report of an alarm that never rang, or rang unanswered.
  missed,

  /// The ongoing notification that stands while a session is under way.
  sessionChip,

  /// The alarm tier on the notification backend, behind
  /// `kAlarmTierUsesNotifications`.
  fallbackAlarm,
}

/// What a button on a notification does, whatever it is called.
enum AlertNotificationAction { stop, snooze, done, skip, open }

/// One button of a notification: what it does and what it reads.
typedef AlertActionLabel = ({AlertNotificationAction action, String label});

/// The words of one notification.
class AlertNotificationContent {
  const AlertNotificationContent({
    required this.title,
    required this.text,
    this.expandedText,
    this.actions = const <AlertActionLabel>[],
  });

  final String title;

  /// The one line under the title that every presentation draws.
  final String text;

  /// What the notification reads once it is expanded — [text] with a line
  /// more under it — or null when expanding it adds nothing.
  final String? expandedText;

  /// The buttons, in the order they are drawn: the one that settles first.
  final List<AlertActionLabel> actions;

  /// The label of the button that does [action], or null when this
  /// notification has none.
  String? labelOf(AlertNotificationAction action) {
    for (final candidate in actions) {
      if (candidate.action == action) return candidate.label;
    }
    return null;
  }
}

/// The words of the notification of one [kind] for [payload], in [strings]'
/// language — **the one grammar every alert notification is written in**
/// (`docs/alert-surfaces-redesign-roadmap.md` §3.5).
///
/// The title is the event's own, always. The text is what the notification
/// is and the time it is about: the event's own time for an alert that is
/// firing, the alarm's own for one that is ahead or was missed. Expanded,
/// the first line of the description is added under the text and never takes
/// its place. A kind is named in the words the Alerts hub already uses, and
/// the button that settles comes first.
///
/// Pure, and it formats nothing: every time it shows was written when the
/// entry was armed and is only placed here, which is what lets a reminder's
/// Snooze call this from a background isolate that has no date symbols and
/// no database.
///
/// The named arguments are what a payload cannot say. [dayLabel] is the day
/// an upcoming notice names beside its alarm's time, which needs the
/// notice's own instant; [untilLabel] is when the session a chip stands for
/// ends, and [linkedNote] whether its event has a note for the chip to open
/// — both the session's, known once its alarm has been answered.
AlertNotificationContent alertNotificationContent(
  AlertNotificationKind kind,
  AlertPayload payload,
  AppLocalizations strings, {
  String? dayLabel,
  String? untilLabel,
  bool linkedNote = false,
}) {
  final tier = payload.isAlarm
      ? strings.eventAlertModeRing
      : strings.eventAlertModeNotify;
  // A title nobody typed still has to name what this is, and a test ring's
  // title is the label of the button that armed it.
  final title = payload.isTest
      ? strings.alarmTestTitle
      : payload.title.trim().isEmpty
      ? tier
      : payload.title;
  // The alarm's own time, and the event's: the same line wherever the entry
  // left the second out as a repeat of the first, or never knew it.
  final time = payload.timeLabel;
  final when = payload.whenLabel.isEmpty ? time : payload.whenLabel;

  // A payload with no time at all — truncated, or foreign — still names its
  // kind rather than trail a separator.
  String kindAt(String word, String moment) =>
      moment.isEmpty ? word : strings.alertsKindWhen(word, moment);

  String? expanded(String text) =>
      payload.excerpt.isEmpty ? null : '$text\n${payload.excerpt}';

  AlertActionLabel snooze() => (
    action: AlertNotificationAction.snooze,
    label: strings.alarmSnoozeMinutes(payload.snoozeMinutes),
  );
  final stop = (action: AlertNotificationAction.stop, label: strings.alarmStop);
  final done = (
    action: AlertNotificationAction.done,
    label: strings.alertsDoneAction,
  );

  switch (kind) {
    case AlertNotificationKind.ring:
      return AlertNotificationContent(
        title: title,
        text: kindAt(strings.eventAlertModeRing, when),
        actions: [stop, snooze()],
      );
    case AlertNotificationKind.fallbackAlarm:
      final text = kindAt(strings.eventAlertModeRing, when);
      return AlertNotificationContent(
        title: title,
        text: text,
        expandedText: expanded(text),
        actions: [stop],
      );
    case AlertNotificationKind.reminder:
      final text = kindAt(strings.eventAlertModeNotify, when);
      return AlertNotificationContent(
        title: title,
        text: text,
        expandedText: expanded(text),
        actions: [done, snooze()],
      );
    case AlertNotificationKind.snoozed:
      final text = kindAt(strings.alertsOutcomeSnoozed, when);
      return AlertNotificationContent(
        title: title,
        text: text,
        expandedText: expanded(text),
        actions: [done, snooze()],
      );
    case AlertNotificationKind.notice:
      final text = time.isEmpty
          ? strings.eventAlertModeRing
          : strings.alertsUpcomingTitle(
              dayLabel == null ? time : strings.alertsWhenOnDay(time, dayLabel),
            );
      return AlertNotificationContent(
        title: title,
        text: text,
        expandedText: expanded(text),
        actions: [
          (
            action: AlertNotificationAction.skip,
            label: strings.alertsSkipAction,
          ),
          (
            action: AlertNotificationAction.open,
            label: strings.alertsOpenAction,
          ),
        ],
      );
    case AlertNotificationKind.missed:
      final text = kindAt(strings.alertsOutcomeMissed, time);
      return AlertNotificationContent(
        title: title,
        text: text,
        expandedText: expanded(text),
      );
    case AlertNotificationKind.sessionChip:
      return AlertNotificationContent(
        title: title,
        text: untilLabel == null
            ? strings.alertsSessionInProgress
            : strings.alertsSessionUntil(untilLabel),
        actions: [
          done,
          (
            action: AlertNotificationAction.open,
            // The button says where it lands: the note when the event has
            // one, the event itself otherwise.
            label: linkedNote
                ? strings.alertsSessionOpenNote
                : strings.alarmOpenEvent,
          ),
        ],
      );
  }
}
