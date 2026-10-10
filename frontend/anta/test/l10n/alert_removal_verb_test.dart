import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';

/// An event its alarm removes is removed in one verb, in every language.
///
/// Four strings say it, on four surfaces and at four moments: the switch
/// that asks for it (`eventAlertRemoveAfter`), the calendar row that
/// remembers it (`eventRemovedAfterAlert`), the line above the alarm page's
/// Stop that warns of it (`alarmRemoveAfterCaption`) and the bar that
/// reports it (`eventAlertEventRemoved`). Read one after another, a second
/// verb is a second thing: until 2026-10 the Romanian page line said the
/// event was deleted ("șters") where the switch that set it up had said
/// removed ("elimină"). A string reworded later is held here to its
/// language's stem, case aside.
void main() {
  /// The stem each language's four strings share.
  const stems = {'en': 'remov', 'de': 'entfern', 'ro': 'elimin'};

  test('every language the app ships has a stem here', () {
    expect({
      for (final locale in AppLocalizations.supportedLocales)
        locale.languageCode,
    }, stems.keys.toSet());
  });

  for (final MapEntry(key: language, value: stem) in stems.entries) {
    test('$language says "$stem…" in all four', () {
      final strings = lookupAppLocalizations(Locale(language));
      final said = {
        'alarmRemoveAfterCaption': strings.alarmRemoveAfterCaption,
        'eventAlertRemoveAfter': strings.eventAlertRemoveAfter,
        'eventRemovedAfterAlert': strings.eventRemovedAfterAlert,
        'eventAlertEventRemoved': strings.eventAlertEventRemoved,
      };

      for (final MapEntry(key: key, value: text) in said.entries) {
        expect(text.toLowerCase(), contains(stem), reason: '$key: "$text"');
      }
    });
  }
}
