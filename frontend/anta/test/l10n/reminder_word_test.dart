import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/l10n/app_localizations.dart';

/// A reminder is called one thing in every language.
///
/// The quieter of the two alert tiers has a word of its own: the type the
/// alert sheet offers and the kind its notification prints
/// (`eventAlertModeNotify`). Every string that names that tier says the same
/// word — the Android channel its notifications post on included, which until
/// 2026-10 read "Erinnerungen" / "Mementouri" in German and Romanian over
/// notifications that said "Mitteilung" / "Notificare".
///
/// The channel moved to the tier word, not the other way round. German's
/// "Erinnerung" is already the word for an alert of either tier, and the tier
/// must not share it; and the Romanian "Amânată" that the hub, the snoozed
/// re-post and the alarm page's eyebrow all draw from one key agrees with a
/// feminine noun, which "memento" is not. So the umbrella word is held apart
/// here too. The exact-alarm access keeps Android's own name for it ("Wecker &
/// Erinnerungen", "Alarme și mementouri"), quoted, and is not held.
void main() {
  /// The stem each language's word for the reminder tier starts with.
  const stems = {'en': 'reminder', 'de': 'mitteilung', 'ro': 'notific'};

  /// Every string that names the reminder tier, by its key.
  final reminderStrings = <String, String Function(AppLocalizations)>{
    'eventAlertModeNotify': (s) => s.eventAlertModeNotify,
    'alertsReminderChannel': (s) => s.alertsReminderChannel,
    'alertsReminderChannelDesc': (s) => s.alertsReminderChannelDesc,
    'alertsNotificationsDesc': (s) => s.alertsNotificationsDesc,
    'alertsRowDesc': (s) => s.alertsRowDesc,
    'alertsEmptyDesc': (s) => s.alertsEmptyDesc,
    'alertsNotificationsOffBanner': (s) => s.alertsNotificationsOffBanner,
    'permissionsAttentionTitle': (s) => s.permissionsAttentionTitle,
    'permissionsNoneNeededDesc': (s) => s.permissionsNoneNeededDesc,
    'permissionsPromptBody': (s) => s.permissionsPromptBody,
    'calendarGuideAlertKindsTitle': (s) => s.calendarGuideAlertKindsTitle,
    'calendarGuideAlertKindsBody': (s) => s.calendarGuideAlertKindsBody(
      s.eventAlertModeNotify,
      s.eventAlertModeRing,
      s.eventAllDay,
    ),
    'calendarGuideRingBody': (s) => s.calendarGuideRingBody(
      s.alertsDoneAction,
      s.alarmSnoozeMinutes(SettingsKeys.defaultAlertSnoozeMinutes),
      s.alarmStop,
    ),
    'calendarGuidePageAlertsCaption': (s) => s.calendarGuidePageAlertsCaption,
    'calendarGuideAlertsLead': (s) => s.calendarGuideAlertsLead,
  };

  /// Strings that name an alert of either tier.
  final umbrellaStrings = <String, String Function(AppLocalizations)>{
    'eventAlert': (s) => s.eventAlert,
    'eventAlerts': (s) => s.eventAlerts,
    'alertsTitle': (s) => s.alertsTitle,
    'calendarAlertsSection': (s) => s.calendarAlertsSection,
    'eventAlertAdd': (s) => s.eventAlertAdd,
    'eventAlertRemove': (s) => s.eventAlertRemove,
    'alertsDefaultNone': (s) => s.alertsDefaultNone,
    'alertsEmpty': (s) => s.alertsEmpty,
    'alertsToggleLabel': (s) => s.alertsToggleLabel('Leg day'),
    'calendarGuidePageAlerts': (s) => s.calendarGuidePageAlerts,
    'calendarGuideCatAlertsTitle': (s) => s.calendarGuideCatAlertsTitle,
    'calendarGuideCatAlertsBody': (s) =>
        s.calendarGuideCatAlertsBody(s.eventAlertAdd, s.eventCategoryAlerts),
  };

  /// English strings that say "reminder" without naming the tier, each with
  /// why. A later "reminder" about something else — a backup reminder, say —
  /// goes here, with its reason, rather than into [reminderStrings], whose
  /// translations would then be held to the tier's word.
  const notTheTier = {
    'permissionExactAlarms': "Android's own name for the exact-alarm access",
    'alertsExactAlarmsOffBanner': 'quotes that name',
    'calendarGuideOpenOftenBody': 'alerts of either tier are lined up',
  };

  test('every language the app ships has a stem here', () {
    expect({
      for (final locale in AppLocalizations.supportedLocales)
        locale.languageCode,
    }, stems.keys.toSet());
  });

  test('every English string that says "reminder" is sorted here', () {
    // A string added later that names the tier is held to the word with the
    // rest; one that is not listed here would be translated without it. One
    // that only happens to say "reminder" goes into [notTheTier].
    final english =
        json.decode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final naming = {
      for (final MapEntry(:key, :value) in english.entries)
        if (!key.startsWith('@') &&
            value is String &&
            value.toLowerCase().contains('reminder'))
          key,
    };

    expect(naming, {...reminderStrings.keys, ...notTheTier.keys});
  });

  for (final MapEntry(key: language, value: stem) in stems.entries) {
    final strings = lookupAppLocalizations(Locale(language));

    test('$language says "$stem…" wherever it names a reminder', () {
      for (final MapEntry(key: key, value: read) in reminderStrings.entries) {
        final text = read(strings);
        expect(text.toLowerCase(), contains(stem), reason: '$key: "$text"');
      }
    });

    test('$language keeps "$stem…" out of its word for any alert', () {
      for (final MapEntry(key: key, value: read) in umbrellaStrings.entries) {
        final text = read(strings);
        expect(
          text.toLowerCase(),
          isNot(contains(stem)),
          reason: '$key: "$text"',
        );
      }
    });
  }
}
