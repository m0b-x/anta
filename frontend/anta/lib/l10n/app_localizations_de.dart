// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'ANTA';

  @override
  String get calendar => 'Kalender';

  @override
  String get calendarDesc => 'Trainings und Ereignisse planen';

  @override
  String get calendarNoEventsForDay => 'Keine Ereignisse an diesem Tag';

  @override
  String get addEvent => 'Ereignis hinzufügen';

  @override
  String get eventTitle => 'Titel';

  @override
  String get eventAllDay => 'Ganztägig';

  @override
  String get eventAllDayHint => 'Ereignis dauert den ganzen Tag';

  @override
  String get eventTimeSection => 'Uhrzeit';

  @override
  String get eventStartTime => 'Startzeit';

  @override
  String get eventEndTime => 'Endzeit';

  @override
  String get eventEndTimeNone => 'Keine Endzeit';

  @override
  String get eventEndTimeHint => 'Tippe, um eine Endzeit hinzuzufügen';

  @override
  String get eventCrossesMidnight => 'Endet am nächsten Tag';

  @override
  String get calendarFormatMonth => 'Monat';

  @override
  String get calendarFormatTwoWeeks => '2 Wochen';

  @override
  String get calendarFormatWeek => 'Woche';

  @override
  String get calendarFiltersTitle => 'Filter';

  @override
  String get calendarViewRange => 'Ansichtsbereich';

  @override
  String get calendarEventCategories => 'Ereigniskategorien';

  @override
  String get calendarSelectAll => 'Alle auswählen';

  @override
  String get calendarClearAll => 'Leeren';

  @override
  String get calendarFilterRepeat => 'Wiederholung';

  @override
  String get calendarFilterTiming => 'Tageszeit';

  @override
  String get calendarFilterTimed => 'Mit Uhrzeit';

  @override
  String get calendarFilterOnlyShow => 'Nur anzeigen';

  @override
  String get calendarFilterTracked => 'Mit Anwesenheit';

  @override
  String get calendarFilterHideEnded => 'Beendete ausblenden';

  @override
  String get calendarFilterWithDescription => 'Mit Beschreibung';

  @override
  String get calendarFilterWithMoney => 'Mit Geld';

  @override
  String get calendarFilterCounted => 'Gezählt';

  @override
  String get calendarFilterMoneyLayer => 'Geld';

  @override
  String calendarFilterLayerHidden(String layer) {
    return 'Ohne $layer';
  }

  @override
  String get calendarFilterPanelShowsAll => 'Tagesbereich ungefiltert lassen';

  @override
  String get calendarFilterPanelShowsAllDesc =>
      'Der Monat bleibt gefiltert; ein Tag zeigt weiterhin alles';

  @override
  String get calendarFilterShowAll => 'Alles anzeigen';

  @override
  String get calendarFilterShowsEverything => 'Zeigt alles';

  @override
  String get calendarFilterNoCategories => 'Keine Kategorien';

  @override
  String get filterPresetsTitle => 'Gespeicherte Filter';

  @override
  String get filterPresetSearchHint => 'Gespeicherte Filter suchen';

  @override
  String get filterPresetEmpty =>
      'Noch keine gespeicherten Filter. Stelle einen Filter ein und tippe im Filterfenster auf das Lesezeichen, um ihn zu speichern.';

  @override
  String get filterPresetNoMatches =>
      'Kein gespeicherter Filter passt zur Suche';

  @override
  String get filterPresetSave => 'Filter speichern';

  @override
  String filterPresetSaved(String name) {
    return 'Als \"$name\" gespeichert';
  }

  @override
  String get filterPresetSaveCurrent => 'Aktuellen Filter speichern';

  @override
  String get filterPresetName => 'Name';

  @override
  String get filterPresetRename => 'Umbenennen';

  @override
  String get filterPresetUpdate => 'Auf aktuellen Filter aktualisieren';

  @override
  String get filterPresetDelete => 'Gespeicherten Filter löschen';

  @override
  String filterPresetDeleteConfirm(String name) {
    return '\"$name\" löschen? Die ausgeblendeten Ereignisse bleiben unberührt.';
  }

  @override
  String get filterPresetActions => 'Optionen für gespeicherte Filter';

  @override
  String filterPresetLimitReached(int count) {
    return 'Du kannst bis zu $count Filter speichern';
  }

  @override
  String get filterCalendar => 'Kalender filtern';

  @override
  String get goToToday => 'Zu heute springen';

  @override
  String get apply => 'Übernehmen';

  @override
  String get dayBarWeekend => 'Wochenende';

  @override
  String get dayBarPublicHoliday => 'Feiertag';

  @override
  String calendarRailMarkMissedLabel(String title) {
    return '$title, verpasst';
  }

  @override
  String get publicHolidayNewYear => 'Neujahr';

  @override
  String get publicHolidayLabourDay => 'Tag der Arbeit';

  @override
  String get publicHolidayChristmasDay => 'Weihnachten';

  @override
  String get publicHolidaySecondChristmasDay => 'Zweiter Weihnachtsfeiertag';

  @override
  String get publicHolidayEpiphany => 'Heilige Drei Könige';

  @override
  String get publicHolidayGoodFriday => 'Karfreitag';

  @override
  String get publicHolidayEasterSunday => 'Ostersonntag';

  @override
  String get publicHolidayEasterMonday => 'Ostermontag';

  @override
  String get publicHolidayAscension => 'Christi Himmelfahrt';

  @override
  String get publicHolidayPentecost => 'Pfingstsonntag';

  @override
  String get publicHolidayWhitMonday => 'Pfingstmontag';

  @override
  String get publicHolidayAssumption => 'Mariä Himmelfahrt';

  @override
  String get publicHolidayAllSaints => 'Allerheiligen';

  @override
  String get publicHolidayChristmasEve => 'Heiligabend';

  @override
  String get publicHolidayNewYearsEve => 'Silvester';

  @override
  String get publicHolidayUnificationDay =>
      'Tag der Vereinigung der Rumänischen Fürstentümer';

  @override
  String get publicHolidayChildrensDay => 'Kindertag';

  @override
  String get publicHolidayStAndrewDay => 'Andreastag';

  @override
  String get publicHolidayNationalDayRomania => 'Rumänischer Nationalfeiertag';

  @override
  String get publicHolidayMartinLutherKingDay => 'Martin-Luther-King-Tag';

  @override
  String get publicHolidayPresidentsDay => 'Presidents’ Day';

  @override
  String get publicHolidayMemorialDay => 'Memorial Day';

  @override
  String get publicHolidayJuneteenth => 'Juneteenth';

  @override
  String get publicHolidayIndependenceDay => 'Unabhängigkeitstag';

  @override
  String get publicHolidayLaborDayUnitedStates => 'Labor Day';

  @override
  String get publicHolidayColumbusDay => 'Kolumbus-Tag';

  @override
  String get publicHolidayVeteransDay => 'Veterans Day';

  @override
  String get publicHolidayThanksgiving => 'Thanksgiving';

  @override
  String get publicHolidayEarlyMayBankHoliday => 'Early May Bank Holiday';

  @override
  String get publicHolidaySpringBankHoliday => 'Spring Bank Holiday';

  @override
  String get publicHolidaySummerBankHoliday => 'Summer Bank Holiday';

  @override
  String get publicHolidayGermanUnityDay => 'Tag der Deutschen Einheit';

  @override
  String get publicHolidayEuropeDay => 'Europatag';

  @override
  String get holidayProfileTitle => 'Feiertage';

  @override
  String get holidayProfileGeneric => 'Christlich (West)';

  @override
  String get holidayProfileRomania => 'Rumänien';

  @override
  String get holidayProfileUnitedStates => 'Vereinigte Staaten';

  @override
  String get holidayProfileUnitedKingdom => 'Vereinigtes Königreich';

  @override
  String get holidayProfileGermany => 'Deutschland';

  @override
  String get holidayProfileEurope => 'Europa';

  @override
  String get holidayProfileNone => 'Keine';

  @override
  String get removeHoliday => 'Feiertag entfernen';

  @override
  String removeHolidayConfirm(String holiday) {
    return '\"$holiday\" für dieses Datum entfernen? Du kannst ihn jederzeit in den Kalendereinstellungen wiederherstellen.';
  }

  @override
  String get holidayRemoved => 'Feiertag entfernt';

  @override
  String get removedHolidays => 'Entfernte Feiertage';

  @override
  String get removedHolidaysEmpty => 'Keine Feiertage entfernt';

  @override
  String get holidayRestore => 'Wiederherstellen';

  @override
  String get holidayRestored => 'Feiertag wiederhergestellt';

  @override
  String get eventCategoryGym => 'Training';

  @override
  String get eventCategoryCardio => 'Cardio';

  @override
  String get eventCategoryRest => 'Ruhetag';

  @override
  String get eventCategoryHoliday => 'Urlaub';

  @override
  String get eventCategoryCompetition => 'Wettkampf';

  @override
  String get eventCategoryMeasurement => 'Messung';

  @override
  String get eventCategoryMobility => 'Mobilität';

  @override
  String get eventCategoryBirthday => 'Geburtstag';

  @override
  String get eventCategoryOther => 'Sonstiges';

  @override
  String get calendarCategories => 'Kategorien';

  @override
  String get calendarCategoriesDesc =>
      'Ereigniskategorien erstellen und anpassen';

  @override
  String get createCategory => 'Kategorie erstellen';

  @override
  String get editCategory => 'Kategorie bearbeiten';

  @override
  String get categoryName => 'Name';

  @override
  String get categoryNameHint => 'z. B. Dehnen';

  @override
  String get categoryColor => 'Farbe';

  @override
  String get categoryDefault => 'Integrierte Kategorie';

  @override
  String get deleteCategory => 'Kategorie löschen';

  @override
  String deleteCategoryConfirm(String name) {
    return '„$name“ löschen? Ereignisse damit werden zu „Sonstiges“ verschoben.';
  }

  @override
  String get categoryDeleted => 'Kategorie gelöscht';

  @override
  String get categorySaveFailed => 'Kategorie konnte nicht gespeichert werden';

  @override
  String deleteCategoryConfirmWithEvents(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Ereignisse zu „Sonstiges“ verschieben und „$name“ löschen?',
      one: '1 Ereignis zu „Sonstiges“ verschieben und „$name“ löschen?',
    );
    return '$_temp0';
  }

  @override
  String get deleteCategoryHideHint =>
      'Verbergen behält diese Ereignisse in ihrer eigenen Farbe.';

  @override
  String categoryEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ereignisse',
      one: '1 Ereignis',
      zero: 'Keine Ereignisse',
    );
    return '$_temp0';
  }

  @override
  String get searchCategories => 'Kategorien suchen';

  @override
  String get noCategoriesMatch => 'Keine passenden Kategorien';

  @override
  String createCategoryNamed(String name) {
    return '„$name“ erstellen';
  }

  @override
  String get categoryHidden => 'Verborgen';

  @override
  String categoryNameExists(String name) {
    return '„$name“ existiert bereits';
  }

  @override
  String categoryNameExistsHidden(String name) {
    return '„$name“ existiert bereits, ist aber verborgen';
  }

  @override
  String get categoriesAllSelected => 'Alle Kategorien';

  @override
  String categoriesNSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kategorien',
      one: '1 Kategorie',
      zero: 'Keine Kategorien',
    );
    return '$_temp0';
  }

  @override
  String categoriesMore(int count) {
    return '+$count weitere';
  }

  @override
  String get categoriesSelectAll => 'Alle auswählen';

  @override
  String get categoriesSelectNone => 'Keine auswählen';

  @override
  String get sortCategoriesAlphabetically => 'A–Z sortieren';

  @override
  String get moveToTop => 'Nach oben';

  @override
  String get vocabularySection => 'Autovervollständigung';

  @override
  String get vocabularySuggestionsLabel => 'Begriffe beim Tippen vorschlagen';

  @override
  String get vocabularySuggestionsDesc =>
      'Begriffe aus deinen Listen nach dem Auslösezeichen anbieten oder wenn du einen Platzhalter antippst.';

  @override
  String get vocabularySuggestionsDismiss => 'Vorschläge ausblenden';

  @override
  String get vocabularyTriggerLabel => 'Auslösezeichen';

  @override
  String get vocabularyTriggerDesc =>
      'Nach einem Leerzeichen eingeben, um deine Listen zu durchsuchen.';

  @override
  String get manageVocabularies => 'Listen bearbeiten';

  @override
  String get vocabularies => 'Wortlisten';

  @override
  String get vocabulariesEmpty =>
      'Noch keine Listen. Lege eine an, um Vorschläge für häufig Geschriebenes zu bekommen — Übungen, Mahlzeiten, Kunden.';

  @override
  String get createVocabulary => 'Neue Liste';

  @override
  String get editVocabulary => 'Liste bearbeiten';

  @override
  String get vocabularyName => 'Listenname';

  @override
  String get vocabularyNameHint => 'Übungen';

  @override
  String get vocabularyNameHelper =>
      'Ein Platzhalter mit diesem Namen schlägt nur diese Liste vor.';

  @override
  String get vocabularyEnabled => 'Für Vorschläge verwenden';

  @override
  String get vocabularyEnabledDesc =>
      'Ausschalten, um die Liste zu behalten, ohne sie vorzuschlagen.';

  @override
  String get vocabularyTerms => 'Begriffe';

  @override
  String get vocabularyTermsHint =>
      'Einer pro Zeile:\nBankdrücken\nKreuzheben\n\n;; Beine\nKniebeuge';

  @override
  String get vocabularyDetails => 'Listenname und Einstellungen';

  @override
  String vocabularyTermCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Begriffe',
      one: '1 Begriff',
      zero: 'Keine Begriffe',
    );
    return '$_temp0';
  }

  @override
  String get deleteVocabulary => 'Liste löschen';

  @override
  String deleteVocabularyConfirm(String name) {
    return '„$name“ löschen? Bereits geschriebene Notizen behalten ihren Text.';
  }

  @override
  String get vocabularyDeleted => 'Liste gelöscht';

  @override
  String get calendarEventsSection => 'Ereignisse';

  @override
  String get eventDescriptionLimit => 'Beschreibungslänge';

  @override
  String eventDescriptionLimitDesc(int count) {
    return 'Bis zu $count Zeichen in einer Ereignisbeschreibung zulassen.';
  }

  @override
  String eventDescriptionCount(int count, int limit) {
    return '$count / $limit';
  }

  @override
  String eventDescriptionTooLong(int limit) {
    return 'Die Beschreibung überschreitet das Limit von $limit Zeichen. Kürze sie oder erhöhe das Limit in den Kalendereinstellungen.';
  }

  @override
  String get eventPerOccurrenceDescriptions => 'Eigene Beschreibung pro Tag';

  @override
  String get eventPerOccurrenceDescriptionsDesc =>
      'Dieses Ereignis behält für jeden Tag eine eigene Beschreibung. Die Beschreibung des Ereignisses wird zur Vorlage, mit der jeder Tag beginnt.';

  @override
  String get eventDescriptionScopeAllDays => 'Alle Tage';

  @override
  String get eventDescriptionScopeThisDay => 'Dieser Tag';

  @override
  String get eventDescriptionScopeAllDaysHint =>
      'Du bearbeitest die Beschreibung, mit der jeder Tag beginnt.';

  @override
  String get eventDescriptionScopeThisDayHint =>
      'Du bearbeitest nur diesen Tag. Andere Tage behalten die gemeinsame Beschreibung.';

  @override
  String get eventDescriptionResetDay =>
      'Diesen Tag auf die gemeinsame Beschreibung zurücksetzen';

  @override
  String get deleteAllEvents => 'Alle Ereignisse löschen';

  @override
  String get deleteAllEventsDesc =>
      'Alle selbst erstellten Ereignisse dauerhaft entfernen. Feiertage bleiben erhalten.';

  @override
  String get deleteAllEventsConfirm =>
      'Alle Ereignisse löschen? Feiertage sind nicht betroffen. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get noEventsToDelete => 'Keine Ereignisse zum Löschen';

  @override
  String get allEventsDeleted => 'Alle Ereignisse gelöscht';

  @override
  String get eventType => 'Typ';

  @override
  String get recurrence => 'Wiederholung';

  @override
  String get recurrenceNone => 'Einmalig';

  @override
  String get recurrenceDaily => 'Täglich';

  @override
  String get recurrenceWeekly => 'Wöchentlich';

  @override
  String get recurrenceMonthly => 'Monatlich';

  @override
  String get recurrenceYearly => 'Jährlich';

  @override
  String get editEvent => 'Ereignis bearbeiten';

  @override
  String get deleteEvent => 'Ereignis löschen';

  @override
  String deleteEventConfirm(String title) {
    return '\"$title\" löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get iconLabel => 'Symbol';

  @override
  String get iconDefault => 'Standard für Kategorie';

  @override
  String get iconCustom => 'Eigenes Symbol';

  @override
  String get pickIcon => 'Symbol wählen';

  @override
  String get pickCategory => 'Kategorie ändern';

  @override
  String get resetToDefault => 'Auf Standard zurücksetzen';

  @override
  String get eventDate => 'Startdatum';

  @override
  String get repeatMode => 'Wiederholung';

  @override
  String get repeatOnce => 'Einmalig';

  @override
  String get repeatRecurring => 'Wiederkehrend';

  @override
  String get frequency => 'Häufigkeit';

  @override
  String get recurrenceWorkdays => 'Werktage';

  @override
  String get recurrenceWeekends => 'Wochenende';

  @override
  String get recurrenceHolidaysOnly => 'Nur an Feiertagen';

  @override
  String recurrenceEveryDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Tage',
      one: 'Täglich',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Wochen',
      one: 'Wöchentlich',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeksOn(int count, String days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Wochen · $days',
      one: 'Wöchentlich · $days',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Monate',
      one: 'Monatlich',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Jahre',
      one: 'Jährlich',
    );
    return '$_temp0';
  }

  @override
  String get recurrenceIntervalLabel => 'Wiederholen alle';

  @override
  String get recurrenceIntervalDecrement => 'Seltener';

  @override
  String get recurrenceIntervalIncrement => 'Häufiger';

  @override
  String recurrenceUnitDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tage',
      one: 'Tag',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wochen',
      one: 'Woche',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Monate',
      one: 'Monat',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Jahre',
      one: 'Jahr',
    );
    return '$_temp0';
  }

  @override
  String get weekdays => 'Wochentage';

  @override
  String get weeklyDaysHint => 'Wähle mindestens einen Wochentag';

  @override
  String get eventUntilLabel => 'Endet am';

  @override
  String get eventUntilNone => 'Endet nie';

  @override
  String get eventUntilHint => 'Tippe, um ein Enddatum festzulegen';

  @override
  String get recurrenceScopeLabel => 'Vorkommen';

  @override
  String get recurrenceScopeFromStart => 'Ab diesem Datum';

  @override
  String get recurrenceScopeAlways => 'Immer';

  @override
  String get recurrenceScopeEveryYear => 'Jedes Jahr';

  @override
  String get recurrenceScopeHint =>
      'Erscheint auch an passenden Tagen vor dem Startdatum';

  @override
  String recurrenceScopeAlwaysSuffix(String rule) {
    return '$rule · auch davor';
  }

  @override
  String get eventTrackPresence => 'Anwesenheit erfassen';

  @override
  String get eventTrackPresenceDesc => 'Markiere ausgelassene Tage.';

  @override
  String get eventShowInDayRail => 'Tagesleiste';

  @override
  String get eventShowInDayRailAuto => 'Auto';

  @override
  String get eventShowInDayRailAlways => 'Immer';

  @override
  String get eventShowInDayRailNever => 'Nie';

  @override
  String get eventShowInDayRailHint => 'Auto folgt der Anwesenheitserfassung.';

  @override
  String get eventPresencePresent => 'Anwesend';

  @override
  String get eventPresenceMissed => 'Verpasst';

  @override
  String get eventMarkMissed => 'Als verpasst markieren';

  @override
  String get eventMarkPresent => 'Als anwesend markieren';

  @override
  String get eventCountOccurrences => 'Wiederholungen zählen';

  @override
  String get eventCountOccurrencesHint =>
      'Jede Wiederholung erhält eine Beschriftung, die ab dem Startdatum zählt. Für Alter und Jahrestage ab 0 zählen.';

  @override
  String get eventCountStyleNumbered => 'Ab 1 zählen';

  @override
  String get eventCountStyleElapsed => 'Ab 0 zählen';

  @override
  String eventNumberedDays(int count) {
    return 'Tag $count';
  }

  @override
  String eventNumberedWeeks(int count) {
    return 'Woche $count';
  }

  @override
  String eventNumberedMonths(int count) {
    return 'Monat $count';
  }

  @override
  String eventNumberedYears(int count) {
    return 'Jahr $count';
  }

  @override
  String eventElapsedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String eventElapsedWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wochen',
      one: '1 Woche',
    );
    return '$_temp0';
  }

  @override
  String eventElapsedMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Monate',
      one: '1 Monat',
    );
    return '$_temp0';
  }

  @override
  String eventElapsedYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Jahre',
      one: '1 Jahr',
    );
    return '$_temp0';
  }

  @override
  String get datePickerSingleTitle => 'Datum wählen';

  @override
  String get datePickerMultiTitle => 'Daten wählen';

  @override
  String get monthYearPickerTitle => 'Datum wählen';

  @override
  String get monthYearPickerManualEntry => 'Stattdessen eingeben';

  @override
  String get monthYearPickerWheelEntry => 'Über die Räder wählen';

  @override
  String get monthYearPickerFieldLabel => 'Datum';

  @override
  String get monthYearPickerFieldHint => '15.08.2026';

  @override
  String get monthYearPickerInvalid => 'Datum eingeben, z. B. 15.08.2026';

  @override
  String monthYearPickerRange(String first, String last) {
    return 'Jahr zwischen $first und $last wählen';
  }

  @override
  String get fastingSectionTitle => 'Religiöses Fasten';

  @override
  String get fastingSectionDesc =>
      'Berechnete Fastenzeiten mit der Regel jedes Tages, im Raster und im Tagespanel';

  @override
  String get fastingTraditionOrthodox => 'Orthodox';

  @override
  String get fastingTraditionCatholic => 'Katholisch';

  @override
  String get fastingTraditionMuslim => 'Muslimisch';

  @override
  String get fastingTraditionJewish => 'Jüdisch';

  @override
  String get fastingTraditionOrthodoxKeywords =>
      'orthodox, ortodox, fasten, kirche, ostkirche';

  @override
  String get fastingTraditionCatholicKeywords =>
      'katholisch, catholic, catolic, kirche, papst';

  @override
  String get fastingTraditionMuslimKeywords =>
      'muslimisch, muslim, musulman, islamisch, moschee';

  @override
  String get fastingTraditionJewishKeywords =>
      'jüdisch, jewish, evreiesc, synagoge, hebräisch';

  @override
  String get fastingGreatLent => 'Große Fastenzeit';

  @override
  String get fastingApostlesFast => 'Apostelfasten';

  @override
  String get fastingDormitionFast => 'Entschlafungsfasten';

  @override
  String get fastingNativityFast => 'Weihnachtsfasten';

  @override
  String get fastingWeekdayFast => 'Mittwochs- und Freitagsfasten';

  @override
  String get fastingCheesefareWeek => 'Butterwoche';

  @override
  String get fastingEveOfTheophany => 'Vorabend der Theophanie';

  @override
  String get fastingBeheadingOfStJohn => 'Enthauptung Johannes des Täufers';

  @override
  String get fastingExaltationOfCross => 'Kreuzerhöhung';

  @override
  String get fastingLent => 'Fastenzeit';

  @override
  String get fastingAshWednesday => 'Aschermittwoch';

  @override
  String get fastingGoodFriday => 'Karfreitag';

  @override
  String get fastingFridayAbstinence => 'Freitagsabstinenz';

  @override
  String get fastingAdvent => 'Advent';

  @override
  String get fastingRamadan => 'Ramadan';

  @override
  String get fastingDayOfArafah => 'Tag von Arafat';

  @override
  String get fastingAshura => 'Aschura';

  @override
  String get fastingYomKippur => 'Jom Kippur';

  @override
  String get fastingTishaBAv => 'Tischa beAw';

  @override
  String get fastingGedaliah => 'Zom Gedalja';

  @override
  String get fastingTenthOfTevet => '10. Tevet';

  @override
  String get fastingSeventeenthOfTammuz => '17. Tammus';

  @override
  String get fastingEstherFast => 'Esterfasten';

  @override
  String get fastingGreatLentKeywords =>
      'lent, great lent, postul mare, osterfasten, fasten';

  @override
  String get fastingLentKeywords => 'lent, postul mare, fasten, buße';

  @override
  String get fastingAdventKeywords =>
      'advent, christmas fast, adventszeit, vorweihnachtszeit';

  @override
  String get fastingRamadanKeywords =>
      'ramadan, ramazan, muslimischer fastenmonat, fastenmonat';

  @override
  String get fastingNativityFastKeywords =>
      'weihnachtsfasten, nativity fast, christmas fast, postul craciunului, advent';

  @override
  String get fastingDormitionFastKeywords =>
      'entschlafungsfasten, dormition fast, assumption fast, postul adormirii, mariä himmelfahrt';

  @override
  String get fastingApostlesFastKeywords =>
      'apostelfasten, apostles fast, peter and paul fast, postul sfintilor apostoli';

  @override
  String get fastingWeekdayFastKeywords =>
      'mittwoch, freitag, wochenfasten, wednesday, friday, miercuri, vineri';

  @override
  String get fastingRegimeStrict => 'Strenges Fasten';

  @override
  String get fastingRegimeOil => 'Wein und Öl erlaubt';

  @override
  String get fastingRegimeFish => 'Fisch erlaubt';

  @override
  String get fastingRegimeDairy => 'Milchprodukte und Eier erlaubt';

  @override
  String get fastingRegimePenitential => 'Bußtag';

  @override
  String get fastingRegimeDaylight => 'Fasten bis Sonnenuntergang';

  @override
  String get fastingRegimeFull => 'Vollständiges Fasten';

  @override
  String get fastingStyleTitle => 'Anzeige im Raster';

  @override
  String get fastingStyleTint => 'Dezente Tönung';

  @override
  String get fastingStyleBar => 'Tagesbalken';

  @override
  String get fastingStyleStrong => 'Fette Tageszahl';

  @override
  String get fastingStyleNone => 'Nur im Tagespanel';

  @override
  String get fastingOrthodoxGreatFasts => 'Mehrtägige Fastenzeiten';

  @override
  String get fastingOrthodoxGreatFastsDesc =>
      'Große Fastenzeit, Weihnachts-, Apostel-, Entschlafungsfasten, strenge Einzeltage';

  @override
  String get fastingWeekdayDaysTitle => 'Wöchentliche Fastentage';

  @override
  String get fastingWeekdayDaysDesc =>
      'Wähle deine Tage — viele fasten nur mittwochs und freitags';

  @override
  String get fastingAppearanceTitle => 'Darstellung';

  @override
  String get fastingPlacementTitle => 'Reihenfolge im Tagespanel';

  @override
  String get fastingPlacementFirst => 'Zuerst';

  @override
  String get fastingPlacementBeforeHolidays => 'Nach Terminen';

  @override
  String get fastingPlacementAfterHolidays => 'Nach Feiertagen';

  @override
  String get fastingPlacementLast => 'Zuletzt';

  @override
  String get fastingColorDefault => 'Standardfarbe';

  @override
  String get fastingIconDefault => 'Standardsymbol';

  @override
  String get fastingPreviewLabel => 'Vorschau';

  @override
  String get fastingPlacementHint =>
      'Legt fest, wo die Zeile zwischen Terminen, Feiertagen und Wochenende steht';

  @override
  String get fastingTitleOverrideLabel => 'Eigener Titel';

  @override
  String get fastingDescriptionLabel => 'Beschreibung';

  @override
  String get fastingDescriptionHint =>
      'Wird unter der Regel angezeigt — Markdown möglich';

  @override
  String get fastingScheduleTitle => 'Meine Praxis';

  @override
  String get fastingScheduleAllYear => 'Ganzes Jahr';

  @override
  String get fastingScheduleNoDays => 'Keine wöchentlichen Tage';

  @override
  String get fastingScheduleNoMonths => 'Keine Monate';

  @override
  String get fastingMonthsTitle => 'Monate, die du hältst';

  @override
  String fastingMonthsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Monate',
      one: '1 Monat',
    );
    return '$_temp0';
  }

  @override
  String get fastingWeekdayScopeTitle => 'Wochentage gelten für';

  @override
  String get fastingWeekdayScopeHintWeekly =>
      'Mehrtägige Fastenzeiten markieren weiterhin jeden ihrer Tage';

  @override
  String get fastingWeekdayScopeHintAll =>
      'Ein abgewählter Tag wird nie markiert';

  @override
  String get fastingMonthScopeTitle => 'Monate gelten für';

  @override
  String get fastingMonthScopeWeekly => 'Nur wöchentliches Fasten';

  @override
  String get fastingMonthScopeAll => 'Alle Fastenzeiten';

  @override
  String get fastingMonthScopeHintWeekly =>
      'Mehrtägige Fastenzeiten erscheinen auch in einem ausgeschalteten Monat';

  @override
  String get fastingMonthScopeHintAll =>
      'Ein ausgeschalteter Monat wird nie markiert';

  @override
  String get fastingExceptionsSkipTitle => 'Freie Tage';

  @override
  String get fastingExceptionsSkipHint =>
      'Nie markiert, egal was der Kalender sagt';

  @override
  String get fastingExceptionsForceTitle => 'Zusätzliche Fastentage';

  @override
  String get fastingExceptionsForceHint =>
      'Immer markiert, auch außerhalb deiner Praxis';

  @override
  String fastingExceptionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ausnahmen',
      one: '1 Ausnahme',
    );
    return '$_temp0';
  }

  @override
  String get fastingExceptionsFull => 'Grenze erreicht';

  @override
  String get fastingAddDates => 'Daten hinzufügen';

  @override
  String get fastingPersonalFast => 'Persönliches Fasten';

  @override
  String get selectNone => 'Keine';

  @override
  String get eventSectionWhat => 'Was';

  @override
  String get eventSectionWhen => 'Wann';

  @override
  String get eventSectionDetails => 'Details';

  @override
  String datePickerSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Daten gewählt',
      one: '1 Datum gewählt',
      zero: 'Keine Daten gewählt',
    );
    return '$_temp0';
  }

  @override
  String get datePickerClear => 'Leeren';

  @override
  String get datePickerToday => 'Heute';

  @override
  String get datePickerBusyDay => 'Hat bereits Termine';

  @override
  String get eventDescriptionPreviewOn => 'Beschreibung gerendert anzeigen';

  @override
  String get eventDescriptionPreviewOff => 'Beschreibung bearbeiten';

  @override
  String get eventDescriptionEmpty => 'Noch nichts zum Anzeigen';

  @override
  String get eventHasDescription => 'Hat Notizen';

  @override
  String get eventDetailsTitle => 'Termin';

  @override
  String get eventDetailsNextOccurrences => 'Nächste Vorkommen';

  @override
  String get eventDetailsNoOccurrences => 'Keine weiteren Vorkommen';

  @override
  String get eventDetailsNoDescription => 'Keine Notizen für diesen Termin';

  @override
  String eventDetailsSeriesStart(String date) {
    return 'Wiederholt sich seit $date';
  }

  @override
  String get eventAppearance => 'Symbol & Farbe';

  @override
  String get eventColor => 'Farbe';

  @override
  String get eventColorCustomTitle => 'Eigene Farbe';

  @override
  String get select => 'Auswählen';

  @override
  String get eventTintIcon => 'Symbol einfärben';

  @override
  String get eventTintIconHint =>
      'Die Ereignisfarbe auch für das Symbol verwenden';

  @override
  String get eventPriority => 'Priorität';

  @override
  String get eventPriorityHint =>
      'Höhere Priorität wird zuerst angezeigt und behält ihren Balken, wenn ein Tag voll ist';

  @override
  String get eventPriorityLowest => 'Niedrigste';

  @override
  String get eventPriorityLow => 'Niedrig';

  @override
  String get eventPriorityNormal => 'Normal';

  @override
  String get eventPriorityHigh => 'Hoch';

  @override
  String get eventPriorityHighest => 'Höchste';

  @override
  String get eventDatesLabel => 'Termine';

  @override
  String get eventDatesHint =>
      'Füge weitere einzelne Termine hinzu, um dieses Ereignis ohne Wiederholung zu wiederholen';

  @override
  String get eventAddDate => 'Datum hinzufügen';

  @override
  String get eventRemoveDate => 'Datum entfernen';

  @override
  String recurrenceSpecificDates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Termine',
      one: 'Ein Termin',
    );
    return '$_temp0';
  }

  @override
  String get eventDescription => 'Beschreibung';

  @override
  String get eventDescriptionHint =>
      'Notizen hinzufügen (Fokus, Technik, Intensität…)';

  @override
  String get eventDescriptionEdit => 'Beschreibung bearbeiten';

  @override
  String get eventDescriptionAdd => 'Beschreibung hinzufügen';

  @override
  String get eventDescriptionExpand => 'Vollständigen Editor öffnen';

  @override
  String get eventDescriptionDone => 'Fertig';

  @override
  String get eventDescriptionAppliesAllOccurrences =>
      'Gilt für jedes Vorkommen';

  @override
  String get eventDescriptionTickAllOccurrences =>
      'Ein Häkchen hier gilt für jedes Vorkommen. Aktiviere „Eigene Beschreibung pro Tag“, um nur diesen Tag abzuhaken.';

  @override
  String get eventLinkedNote => 'Verknüpfte Notiz';

  @override
  String get eventLinkNoteHint => 'Trainingsnotiz verknüpfen';

  @override
  String get eventLinkedNoteMissing => 'Verknüpfte Notiz existiert nicht mehr';

  @override
  String get eventOpenLinkedNote => 'Verknüpfte Notiz öffnen';

  @override
  String get eventRemoveNoteLink => 'Verknüpfung entfernen';

  @override
  String get iconGroupStrength => 'Kraft';

  @override
  String get iconGroupCardio => 'Ausdauer';

  @override
  String get iconGroupSports => 'Sportarten';

  @override
  String get iconGroupRecovery => 'Erholung';

  @override
  String get iconGroupBody => 'Körper & Ernährung';

  @override
  String get iconGroupMeasurement => 'Messung';

  @override
  String get iconGroupAchievements => 'Erfolge';

  @override
  String get iconGroupTravel => 'Reise';

  @override
  String get iconGroupTime => 'Zeit';

  @override
  String get iconGroupGeneric => 'Sonstiges';

  @override
  String get iconGroupWork => 'Arbeit';

  @override
  String get iconGroupEducation => 'Bildung';

  @override
  String get iconGroupHealth => 'Gesundheit';

  @override
  String get iconGroupHome => 'Zuhause';

  @override
  String get iconGroupFinance => 'Finanzen';

  @override
  String get iconGroupFoodDrink => 'Essen & Trinken';

  @override
  String get iconGroupTransport => 'Verkehr';

  @override
  String get iconGroupEntertainment => 'Unterhaltung';

  @override
  String get iconGroupPeople => 'Menschen';

  @override
  String get iconGroupNature => 'Natur';

  @override
  String get iconGroupTech => 'Technik';

  @override
  String get iconGroupSymbols => 'Symbole';

  @override
  String get iconGroupLetters => 'Buchstaben';

  @override
  String get iconGroupDigits => 'Zahlen';

  @override
  String get iconGroupRecent => 'Zuletzt verwendet';

  @override
  String get welcomeToApp => 'Willkommen bei ANTA';

  @override
  String get onboardingDescription =>
      'Verfolge deine Notizen, Ausgaben und Termine an einem Ort. Starte mit einem neuen Arbeitsbereich oder stelle ein vorheriges Backup wieder her.';

  @override
  String get startFresh => 'Neu starten';

  @override
  String get restoreFromBackup => 'Aus Backup wiederherstellen';

  @override
  String get confirmImport => 'Import bestätigen';

  @override
  String get backupContains => 'Dieses Backup enthält:';

  @override
  String exportedOn(String date) {
    return 'Exportiert am: $date';
  }

  @override
  String get import => 'Importieren';

  @override
  String importSuccess(int folders, int notes) {
    return '$folders Ordner und $notes Notizen erfolgreich importiert';
  }

  @override
  String get importFailed => 'Import fehlgeschlagen';

  @override
  String get invalidBackupFile => 'Ungültige Backup-Datei';

  @override
  String get exportBackup => 'Backup exportieren';

  @override
  String get folders => 'Ordner';

  @override
  String get notes => 'Notizen';

  @override
  String get createFolder => 'Ordner erstellen';

  @override
  String get createNote => 'Notiz erstellen';

  @override
  String get folderName => 'Ordnername';

  @override
  String get noteName => 'Notizname';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get create => 'Erstellen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get delete => 'Löschen';

  @override
  String get save => 'Speichern';

  @override
  String get search => 'Suchen';

  @override
  String error(String message) {
    return 'Fehler: $message';
  }

  @override
  String created(String date) {
    return 'Erstellt: $date';
  }

  @override
  String updated(String date) {
    return 'Aktualisiert: $date';
  }

  @override
  String get deleteFolder => 'Ordner löschen';

  @override
  String deleteFolderConfirm(String name) {
    return 'Möchten Sie \"$name\" wirklich löschen?';
  }

  @override
  String deleteFolderWithNotesConfirm(String name, int count) {
    return 'Möchten Sie \"$name\" wirklich löschen? Dies löscht auch $count Notiz(en).';
  }

  @override
  String get rename => 'Umbenennen';

  @override
  String get renameFolder => 'Ordner umbenennen';

  @override
  String get untitledNote => 'Unbenannte Notiz';

  @override
  String get emptyNote => 'Leere Notiz';

  @override
  String get deleteNote => 'Notiz löschen';

  @override
  String deleteNoteConfirm(String title) {
    return 'Möchten Sie \"$title\" wirklich löschen?';
  }

  @override
  String get deleteThisNote => 'diese Notiz';

  @override
  String get enterFolderName => 'Ordnernamen eingeben';

  @override
  String get newNote => 'Neue Notiz';

  @override
  String get switchToEditMode => 'Zum Bearbeitungsmodus wechseln';

  @override
  String get previewMarkdown => 'Markdown-Vorschau';

  @override
  String get preview => 'Vorschau';

  @override
  String get autoSaveOn =>
      'Auto-Speichern ist EIN (speichert alle 5s nach Änderungen)';

  @override
  String get enableAutoSave => 'Auto-Speichern aktivieren';

  @override
  String get autoSaveOff => 'Auto-Speichern AUS';

  @override
  String get saveNote => 'Notiz speichern';

  @override
  String get noContentYet => '*Noch kein Inhalt*';

  @override
  String get startWriting => 'Beginnen Sie zu schreiben...';

  @override
  String get noteCannotBeEmpty => 'Notiz darf nicht leer sein';

  @override
  String get noteSaved => 'Notiz gespeichert!';

  @override
  String get editTitle => 'Titel bearbeiten';

  @override
  String get enterNoteTitle => 'Notiztitel eingeben';

  @override
  String get autoSaveEnabled => 'Auto-Speichern aktiviert';

  @override
  String get autoSaveDisabled => 'Auto-Speichern deaktiviert';

  @override
  String get markdownShortcuts => 'Markdown-Verknüpfungen';

  @override
  String get markdownShortcutsDesc =>
      'Symbolleisten-Schaltflächen und Aktionen anpassen';

  @override
  String get removeAllCustom => 'Alle benutzerdefinierten entfernen';

  @override
  String get noCustomShortcutsYet =>
      'Noch keine benutzerdefinierten Verknüpfungen';

  @override
  String get tapToAddShortcut =>
      'Tippen Sie auf die Schaltfläche +, um eine hinzuzufügen';

  @override
  String get deleteShortcut => 'Verknüpfung löschen';

  @override
  String get deleteShortcutConfirm =>
      'Möchten Sie diese Verknüpfung wirklich löschen?';

  @override
  String get resetDialogTitle => 'Auf Standard zurücksetzen';

  @override
  String get resetDialogMessage =>
      'Dies stellt alle Standardverknüpfungen in ihrer ursprünglichen Reihenfolge und Einstellungen wieder her. Benutzerdefinierte Verknüpfungen werden behalten, aber ans Ende verschoben.';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get removeCustomDialogTitle => 'Alle benutzerdefinierten entfernen';

  @override
  String get removeCustomDialogMessage =>
      'Dies löscht dauerhaft alle von Ihnen erstellten benutzerdefinierten Verknüpfungen. Standardverknüpfungen bleiben erhalten.';

  @override
  String get remove => 'Entfernen';

  @override
  String get defaultLabel => 'STANDARD';

  @override
  String get insertsCurrentDate => 'Fügt aktuelles Datum ein';

  @override
  String get opensHeaderMenu => 'Öffnet Überschriftenmenü (H1-H6)';

  @override
  String beforeAfterText(String before, String after) {
    return 'Vorher: \"$before\" | Nachher: \"$after\"';
  }

  @override
  String get hide => 'Verbergen';

  @override
  String get show => 'Anzeigen';

  @override
  String get newShortcut => 'Neue Verknüpfung';

  @override
  String get editShortcut => 'Verknüpfung bearbeiten';

  @override
  String get icon => 'Symbol';

  @override
  String get tapToChangeIcon => 'Tippen Sie, um das Symbol zu ändern';

  @override
  String get selectIcon => 'Symbol auswählen';

  @override
  String get searchIcons => 'Symbole suchen...';

  @override
  String get noIconsFound => 'Keine Symbole gefunden';

  @override
  String get label => 'Beschriftung';

  @override
  String get labelHint => 'z.B. Hervorheben';

  @override
  String get insertType => 'Einfügungstyp';

  @override
  String get wrapSelectedText => 'Ausgewählten Text umschließen';

  @override
  String get insertCurrentDate => 'Aktuelles Datum einfügen';

  @override
  String get beforeDate => 'Vor Datum (optional)';

  @override
  String get markdownStart => 'Markdown-Start';

  @override
  String get markdownStartHint => 'z.B. ==';

  @override
  String get optionalTextBeforeDate => 'Optionaler Text vor Datum';

  @override
  String get afterDate => 'Nach Datum (optional)';

  @override
  String get markdownEnd => 'Markdown-Ende';

  @override
  String get optionalTextAfterDate => 'Optionaler Text nach Datum';

  @override
  String get labelCannotBeEmpty => 'Beschriftung darf nicht leer sein';

  @override
  String get formHasErrors => 'Bitte beheben Sie die Fehler im Formular';

  @override
  String get bold => 'Fett';

  @override
  String get italic => 'Kursiv';

  @override
  String get headers => 'Überschriften';

  @override
  String get pointList => 'Punktliste';

  @override
  String get strikethrough => 'Durchgestrichen';

  @override
  String get bulletList => 'Aufzählungsliste';

  @override
  String get numberedList => 'Nummerierte Liste';

  @override
  String get checkbox => 'Kontrollkästchen';

  @override
  String get quote => 'Zitat';

  @override
  String get inlineCode => 'Inline-Code';

  @override
  String get codeBlock => 'Codeblock';

  @override
  String get link => 'Link';

  @override
  String get currentDate => 'Aktuelles Datum';

  @override
  String get header1 => 'Überschrift 1';

  @override
  String get header2 => 'Überschrift 2';

  @override
  String get header3 => 'Überschrift 3';

  @override
  String get header4 => 'Überschrift 4';

  @override
  String get header5 => 'Überschrift 5';

  @override
  String get header6 => 'Überschrift 6';

  @override
  String get undo => 'Rückgängig';

  @override
  String get redo => 'Wiederholen';

  @override
  String get paste => 'Einfügen';

  @override
  String get decreaseFontSize => 'Schriftgröße verkleinern';

  @override
  String get increaseFontSize => 'Schriftgröße vergrößern';

  @override
  String get settings => 'Einstellungen';

  @override
  String get dropPosition => 'Ablageposition';

  @override
  String get longPressToReorder => 'Lange drücken zum Neuordnen';

  @override
  String shortcutButton(String label) {
    return '$label Schaltfläche';
  }

  @override
  String get markdownSpaceWarning =>
      'Tipp: Fügen Sie ein Leerzeichen nach der Markdown-Syntax hinzu (z.B. \'# \' oder \'- \') für die richtige Formatierung.';

  @override
  String get reorderShortcuts => 'Verknüpfungen neu anordnen';

  @override
  String get doneReordering => 'Fertig';

  @override
  String get noSearchResults => 'Keine Ergebnisse gefunden';

  @override
  String get searchHint => 'Tippen um Notizen zu suchen';

  @override
  String get loadingMore => 'Lade mehr...';

  @override
  String get noMoreNotes => 'Keine weiteren Notizen';

  @override
  String get sortBy => 'Sortieren nach';

  @override
  String get sortByUpdated => 'Zuletzt aktualisiert';

  @override
  String get sortByCreated => 'Erstellungsdatum';

  @override
  String get sortByTitle => 'Titel';

  @override
  String get ascending => 'Aufsteigend';

  @override
  String get descending => 'Absteigend';

  @override
  String get loadingContent => 'Lade Inhalt...';

  @override
  String get largeNoteWarning =>
      'Diese Notiz ist sehr groß und kann einen Moment zum Laden benötigen';

  @override
  String noteStats(int count, int chunks) {
    return '$count Zeichen, $chunks Teile';
  }

  @override
  String get compressedNote => 'Komprimiert';

  @override
  String get searchInFolder => 'In diesem Ordner suchen';

  @override
  String get searchAll => 'Alle Notizen durchsuchen';

  @override
  String get recentSearches => 'Letzte Suchen';

  @override
  String get clearSearchHistory => 'Suchverlauf löschen';

  @override
  String get filterByDate => 'Nach Datum filtern';

  @override
  String get fromDate => 'Von';

  @override
  String get toDate => 'Bis';

  @override
  String get applyFilter => 'Filter anwenden';

  @override
  String get clearFilter => 'Filter löschen';

  @override
  String matchesFound(int count) {
    return '$count Treffer gefunden';
  }

  @override
  String get autoSaving => 'Automatisches Speichern...';

  @override
  String get changesSaved => 'Änderungen gespeichert';

  @override
  String get unsavedChanges => 'Ungespeicherte Änderungen';

  @override
  String get discardChanges => 'Änderungen verwerfen';

  @override
  String get keepEditing => 'Weiter bearbeiten';

  @override
  String get virtualScrollEnabled =>
      'Virtuelles Scrollen für große Inhalte aktiviert';

  @override
  String lineCount(int count) {
    return '$count Zeilen';
  }

  @override
  String get emptyFoldersHint =>
      'Sieht so aus, als möchtest du einen Ordner erstellen';

  @override
  String get emptyNotesHint => 'Schreibe deine erste Notiz';

  @override
  String get tapPlusToCreate => 'Tippe auf + um zu beginnen';

  @override
  String charactersCount(int current, int max) {
    return '$current/$max Zeichen';
  }

  @override
  String get databaseSettings => 'Datenbank';

  @override
  String get databaseSettingsDesc => 'Datenbankspeicherort und -verwaltung';

  @override
  String get about => 'Über';

  @override
  String get databaseLocation => 'Datenbankspeicherort';

  @override
  String get copyPath => 'Pfad kopieren';

  @override
  String get openInFinder => 'Ordner öffnen';

  @override
  String get databaseStats => 'Statistiken';

  @override
  String get size => 'Größe';

  @override
  String get lastModified => 'Zuletzt geändert';

  @override
  String get maintenance => 'Wartung';

  @override
  String get maintenanceDesc =>
      'SQLite VACUUM ausführen, um ungenutzten Speicherplatz von gelöschten Notizen und Ordnern zurückzugewinnen. Dies erstellt die Datenbankdatei neu, defragmentiert die Daten und kann die Dateigröße nach dem Löschen großer Inhaltsmengen erheblich reduzieren.';

  @override
  String get optimizeDatabase => 'Datenbank optimieren';

  @override
  String get dangerZone => 'Gefahrenzone';

  @override
  String get dangerZoneDesc =>
      'Diese Aktionen sind unwiderruflich. Alle Notizen und Ordner werden dauerhaft gelöscht.';

  @override
  String get deleteAllData => 'Alle Daten löschen';

  @override
  String get pathCopied => 'Pfad in Zwischenablage kopiert';

  @override
  String get notSupportedOnPlatform => 'Auf dieser Plattform nicht unterstützt';

  @override
  String get errorOpeningFolder => 'Fehler beim Öffnen des Ordners';

  @override
  String get optimizing => 'Datenbank wird optimiert...';

  @override
  String get optimizationComplete => 'Datenbank erfolgreich optimiert';

  @override
  String get saved => 'gespart';

  @override
  String get alreadyOptimized => 'Datenbank bereits optimiert';

  @override
  String get deleteConfirmation =>
      'Diese Aktion kann nicht rückgängig gemacht werden. Alle Notizen, Ordner und Daten werden dauerhaft gelöscht. Sind Sie absolut sicher?';

  @override
  String get deleteNotImplemented =>
      'Löschfunktion aus Sicherheitsgründen noch nicht implementiert';

  @override
  String get deletingData => 'Alle Daten werden gelöscht...';

  @override
  String get dataDeleted => 'Daten gelöscht';

  @override
  String get restartRequired =>
      'Neustart kann für volle Wirkung erforderlich sein';

  @override
  String get exitApp => 'App beenden';

  @override
  String get errorDeletingData => 'Fehler beim Löschen der Daten';

  @override
  String get shareDatabase => 'Datenbank teilen';

  @override
  String get shareDatabaseDesc =>
      'Exportieren und teilen Sie Ihre Datenbankdatei per E-Mail, Messenger-Apps oder Cloud-Speicher für Backup-Zwecke.';

  @override
  String get preparingShare => 'Teilen wird vorbereitet...';

  @override
  String get shareError => 'Fehler beim Teilen der Datenbank';

  @override
  String get databaseNotFound => 'Datenbankdatei nicht gefunden';

  @override
  String get renameNote => 'Notiz umbenennen';

  @override
  String get enterNewName => 'Neuen Namen eingeben';

  @override
  String get reorderMode => 'Sortierungsmodus';

  @override
  String get dragToReorder => 'Elemente ziehen um neu zu ordnen';

  @override
  String get sortByCustom => 'Benutzerdefinierte Reihenfolge';

  @override
  String get quickSort => 'Schnellsortierung';

  @override
  String get sortItems => 'Elemente sortieren';

  @override
  String get sortFolders => 'Ordner sortieren';

  @override
  String get sortNotes => 'Notizen sortieren';

  @override
  String get sortByName => 'Nach Name';

  @override
  String get moveUp => 'Nach oben';

  @override
  String get moveDown => 'Nach unten';

  @override
  String get appSettings => 'Einstellungen';

  @override
  String get appSettingsDesc => 'Start, Navigation, Editor und Vorschau';

  @override
  String get folderSwipeGesture => 'Wischen zum Öffnen des Menüs in Ordnern';

  @override
  String get folderSwipeGestureDesc =>
      'Vom linken Rand wischen, um das Navigationsmenü beim Durchsuchen von Ordnern zu öffnen';

  @override
  String get noteSwipeGesture => 'Wischen zum Öffnen des Menüs in Notizen';

  @override
  String get noteSwipeGestureDesc =>
      'Vom linken Rand wischen, um das Navigationsmenü beim Bearbeiten von Notizen zu öffnen';

  @override
  String get feedbackSection => 'Feedback & Bestätigung';

  @override
  String get hapticFeedback => 'Haptisches Feedback';

  @override
  String get hapticFeedbackDesc =>
      'Vibration bei Interaktionen wie dem Umschalten von Schaltern';

  @override
  String get confirmDelete => 'Vor dem Löschen bestätigen';

  @override
  String get confirmDeleteDesc =>
      'Bestätigungsdialog vor dem Löschen von Notizen oder Ordnern anzeigen';

  @override
  String get autoSaveSection => 'Automatisches Speichern';

  @override
  String get autoSave => 'Notizen automatisch speichern';

  @override
  String get autoSaveDesc => 'Notizen beim Bearbeiten automatisch speichern';

  @override
  String get autoSaveInterval => 'Speicherintervall';

  @override
  String autoSaveIntervalDesc(int seconds) {
    return 'Alle $seconds Sekunden speichern';
  }

  @override
  String get startupSection => 'Start';

  @override
  String get restoreLocation => 'Letzten Bildschirm wieder öffnen';

  @override
  String get restoreLocationDesc => 'Was ANTA beim Starten öffnet';

  @override
  String get restoreLocationOff => 'Aus';

  @override
  String get restoreLocationNotes => 'Ordner und Notizen';

  @override
  String get restoreLocationEverything => 'Alles';

  @override
  String get restoreLocationKeywords =>
      'start, fortsetzen, merken, letzter, bildschirm';

  @override
  String get displaySection => 'Ordner & Notizen';

  @override
  String get showNotePreview => 'Notizvorschau anzeigen';

  @override
  String get showNotePreviewDesc =>
      'Eine Vorschau des Notizinhalts in der Liste anzeigen';

  @override
  String get showStatsBar => 'Statistikleiste anzeigen';

  @override
  String get showStatsBarDesc =>
      'Zeichenanzahl und Zeilenanzahl im Editor anzeigen';

  @override
  String get resetToDefaults => 'Auf Standard zurücksetzen';

  @override
  String get resetToDefaultsConfirm =>
      'Möchten Sie wirklich alle Einstellungen auf ihre Standardwerte zurücksetzen?';

  @override
  String get settingsReset => 'Einstellungen wurden auf Standard zurückgesetzt';

  @override
  String get shareNote => 'Notiz teilen';

  @override
  String get shareFolder => 'Ordner teilen';

  @override
  String get exportingFolder => 'Ordner wird exportiert...';

  @override
  String get folderExportError => 'Fehler beim Exportieren des Ordners';

  @override
  String get importingFile => 'Wird importiert...';

  @override
  String get importFileError => 'Fehler beim Importieren';

  @override
  String get importNoteOrFolder => 'Importieren';

  @override
  String importedSummary(int folders, int notes) {
    return '$folders Ordner und $notes Notizen importiert';
  }

  @override
  String get shareSelected => 'Teilen';

  @override
  String get exportingSelection => 'Auswahl wird exportiert...';

  @override
  String get selectionExportError => 'Fehler beim Exportieren der Auswahl';

  @override
  String get noteOptions => 'Notiz-Optionen';

  @override
  String get exportingNote => 'Notiz wird exportiert...';

  @override
  String get noteExportError => 'Fehler beim Exportieren der Notiz';

  @override
  String get chooseExportFormat => 'Exportformat wählen';

  @override
  String get exportAsMarkdown => 'Markdown (.md)';

  @override
  String get exportAsJson => 'JSON (.json)';

  @override
  String get exportAsText => 'Nur Text (.txt)';

  @override
  String get activeDatabaseSection => 'Aktive Datenbank';

  @override
  String get activeDatabaseDesc =>
      'Wählen Sie aus, welche Datenbank verwendet werden soll. Das Erstellen oder Wechseln der Datenbank startet die App neu.';

  @override
  String get selectDatabase => 'Datenbank auswählen';

  @override
  String currentDatabase(String name) {
    return 'Aktuell: $name';
  }

  @override
  String get createNewDatabase => 'Neue Datenbank erstellen';

  @override
  String get newDatabaseName => 'Datenbankname';

  @override
  String get enterDatabaseName => 'Datenbanknamen eingeben';

  @override
  String get invalidDatabaseName =>
      'Ungültiger Name. Verwenden Sie nur Buchstaben, Zahlen, Unterstriche und Bindestriche (max. 50 Zeichen).';

  @override
  String get databaseExists =>
      'Eine Datenbank mit diesem Namen existiert bereits.';

  @override
  String get creatingDatabase => 'Datenbank wird erstellt...';

  @override
  String get databaseCreated => 'Datenbank erfolgreich erstellt';

  @override
  String get importDatabase => 'Datenbank importieren';

  @override
  String get importingDatabase => 'Datenbank wird importiert...';

  @override
  String get databaseImported => 'Datenbank erfolgreich importiert';

  @override
  String get invalidDatabaseFile => 'Diese Datei ist keine gültige Datenbank.';

  @override
  String get renameDatabase => 'Datenbank umbenennen';

  @override
  String get renamingDatabase => 'Datenbank wird umbenannt...';

  @override
  String get databaseRenamed => 'Datenbank erfolgreich umbenannt';

  @override
  String get switchingDatabase => 'Datenbank wird gewechselt...';

  @override
  String get availableDatabases => 'Verfügbare Datenbanken';

  @override
  String get noDatabases => 'Keine Datenbanken gefunden';

  @override
  String get databaseOptions => 'Datenbankoptionen';

  @override
  String get switchTo => 'Zu dieser Datenbank wechseln';

  @override
  String deleteDatabaseConfirm(String name) {
    return 'Möchten Sie die Datenbank \"$name\" wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get cannotDeleteActive =>
      'Die aktuell aktive Datenbank kann nicht gelöscht werden. Bitte wechseln Sie zuerst zu einer anderen Datenbank.';

  @override
  String get databaseDeleted => 'Datenbank gelöscht';

  @override
  String get findInNote => 'In Notiz suchen';

  @override
  String get clearSearch => 'Suche löschen';

  @override
  String get jumpToMatch => 'Zu Treffer springen';

  @override
  String get goToMatchNumber => 'Zu Treffer gehen';

  @override
  String get matchNumberHint => 'Treffer-Nr.';

  @override
  String matchNumberRange(int min, int max) {
    return '$min–$max';
  }

  @override
  String enterMatchNumber(int min, int max) {
    return 'Gib eine Zahl zwischen $min und $max ein';
  }

  @override
  String get typeMatchNumber => 'Treffernummer eingeben';

  @override
  String matchesForQuery(String query) {
    return 'Treffer für „$query“';
  }

  @override
  String matchPosition(int current, int total) {
    return 'Treffer $current von $total';
  }

  @override
  String matchCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer',
      one: '1 Treffer',
    );
    return '$_temp0';
  }

  @override
  String matchAtLine(int line) {
    return 'Zeile $line';
  }

  @override
  String get wrappedToFirstMatch => 'Zum ersten Treffer gesprungen';

  @override
  String get wrappedToLastMatch => 'Zum letzten Treffer gesprungen';

  @override
  String get replaceWith => 'Ersetzen durch';

  @override
  String get replaceOne => 'Ersetzen';

  @override
  String get replaceAll => 'Alle';

  @override
  String replacedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer ersetzt',
      one: '1 Treffer ersetzt',
    );
    return '$_temp0';
  }

  @override
  String get matchCase => 'Groß-/Kleinschreibung';

  @override
  String get wholeWord => 'Ganzes Wort';

  @override
  String get useRegex => 'Regex verwenden';

  @override
  String get findAndReplace => 'Suchen & Ersetzen';

  @override
  String get options => 'Optionen';

  @override
  String get previous => 'Zurück';

  @override
  String get next => 'Weiter';

  @override
  String get close => 'Schließen';

  @override
  String get dateFormatSettings => 'Datumsformat';

  @override
  String get selectDateFormat => 'Wählen Sie, wie Daten angezeigt werden:';

  @override
  String get longPressToChangeFormat => 'Lange drücken zum Ändern des Formats';

  @override
  String get languageSettings => 'Sprache';

  @override
  String get languageSettingsDesc => 'App-Anzeigesprache ändern';

  @override
  String get selectLanguage => 'Sprache auswählen';

  @override
  String get english => 'Englisch';

  @override
  String get german => 'Deutsch';

  @override
  String get romanian => 'Rumänisch';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get themeSettings => 'Erscheinungsbild';

  @override
  String get themeSettingsDesc => 'Dunkelmodus, Farben und Anzeige';

  @override
  String get selectTheme => 'Design auswählen';

  @override
  String get lightTheme => 'Hell';

  @override
  String get darkTheme => 'Dunkel';

  @override
  String get systemTheme => 'System';

  @override
  String get searchSection => 'Suche';

  @override
  String get searchCursorBehavior => 'Suchnavigation';

  @override
  String get searchCursorBehaviorDesc =>
      'Wo der Cursor beim Springen zu einem Suchergebnis platziert werden soll';

  @override
  String get cursorAtStart => 'Davor';

  @override
  String get cursorAtEnd => 'Danach';

  @override
  String get selectMatch => 'Auswählen';

  @override
  String get searching => 'Suche...';

  @override
  String get editorSection => 'Editor';

  @override
  String get liveMarkdownRendering => 'Live-Markdown-Darstellung';

  @override
  String get liveMarkdownRenderingDesc =>
      'Überschriften, Listen, Kontrollkästchen und Textstile direkt beim Bearbeiten darstellen';

  @override
  String get showLineNumbers => 'Zeilennummern';

  @override
  String get showLineNumbersDesc =>
      'Zeilennummern auf der linken Seite des Editors anzeigen';

  @override
  String get wordWrap => 'Zeilenumbruch';

  @override
  String get wordWrapDesc =>
      'Lange Zeilen umbrechen, um in die Editorbreite zu passen';

  @override
  String get showCursorLine => 'Aktuelle Zeile hervorheben';

  @override
  String get showCursorLineDesc =>
      'Die Zeile hervorheben, in der sich der Cursor befindet';

  @override
  String get autoBreakLongLines => 'Lange Zeilen autom. umbrechen';

  @override
  String get autoBreakLongLinesDesc =>
      'Bricht lange Zeilen beim Einfügen von Text automatisch um. Kann die Genauigkeit der Suchpositionierung in der Vorschau leicht beeinträchtigen.';

  @override
  String get previewWhenKeyboardHidden =>
      'Vorschau bei ausgeblendeter Tastatur';

  @override
  String get previewWhenKeyboardHiddenDesc =>
      'Zeigt die gerenderte Markdown-Vorschau, wenn die Tastatur ausgeblendet ist. Der Editor erscheint, wenn du zum Tippen tippst.';

  @override
  String get scrollCursorOnKeyboard => 'Cursor bei Tastatur scrollen';

  @override
  String get scrollCursorOnKeyboardDesc =>
      'Scrollt automatisch, damit der Cursor sichtbar bleibt, wenn die Tastatur erscheint.';

  @override
  String linesFormatted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lange Zeilen wurden formatiert',
      one: '1 lange Zeile wurde formatiert',
    );
    return '$_temp0';
  }

  @override
  String get previewSection => 'Vorschau';

  @override
  String get showPreviewScrollbar => 'Vorschau-Bildlaufleiste';

  @override
  String get showPreviewScrollbarDesc =>
      'Eine interaktive Bildlaufleiste im Vorschaumodus anzeigen (experimentell)';

  @override
  String get previewLinesPerChunk => 'Zeilen pro Block';

  @override
  String previewLinesPerChunkDesc(int count) {
    return '$count Zeilen pro Block (höher = bessere Leistung, niedriger = präziseres Scroll-Suchen)';
  }

  @override
  String get calendarSection => 'Kalender';

  @override
  String get calendarSettings => 'Kalender';

  @override
  String get calendarMaxDayBars => 'Maximale Balken pro Tag';

  @override
  String calendarMaxDayBarsDesc(int count) {
    return 'Zeige bis zu $count Balken pro Tag. Weitere Kategorien werden als +N angezeigt.';
  }

  @override
  String get calendarAppearanceSection => 'Darstellung';

  @override
  String get calendarTodayStyleTitle => 'Heute-Markierung';

  @override
  String get todayStyleTonal => 'Dezent';

  @override
  String get todayStyleRing => 'Ring';

  @override
  String get todayStyleFilled => 'Gefüllt';

  @override
  String get calendarAccentColor => 'Markierungsfarbe';

  @override
  String get calendarAccentColorDesc => 'Färbt heute und den ausgewählten Tag';

  @override
  String get calendarAccentThemeDefault => 'Themenfarbe';

  @override
  String get calendarMarkerStyleTitle => 'Ereignis-Markierungen';

  @override
  String get markerStyleBars => 'Balken';

  @override
  String get markerStyleDots => 'Punkte';

  @override
  String get calendarDayRailStyleTitle => 'Tagesleiste';

  @override
  String get calendarDayRailStyleDesc =>
      'Eine senkrechte Leiste links an jedem Tag, eine Marke je erfasstem Termin — damit ein Tag mit dreien nicht wie einer aussieht. Leisten-Termine verlassen die unteren Markierungen.';

  @override
  String get dayRailStyleNone => 'Aus';

  @override
  String get dayRailStyleLine => 'Striche';

  @override
  String get dayRailStyleDot => 'Punkte';

  @override
  String get calendarMaxDayRailMarks => 'Maximale Leistenmarken pro Tag';

  @override
  String calendarMaxDayRailMarksDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Zeige bis zu $count Leistenmarken pro Tag. Der Rest wird zu einer neutralen Marke.',
      one:
          'Zeige eine Leistenmarke pro Tag. Der Rest wird zu einer neutralen Marke.',
    );
    return '$_temp0';
  }

  @override
  String get calendarDayRailBasePositionTitle => 'Fasten-Hälfte der Leiste';

  @override
  String get calendarDayRailBasePositionDesc =>
      'An einem Tag mit beidem teilt sich die Leiste in zwei gleiche Hälften — deine Marken und das Fasten. Hier wählst du, welches Ende das Fasten bekommt.';

  @override
  String get dayRailBasePositionTop => 'Oben';

  @override
  String get dayRailBasePositionBottom => 'Unten';

  @override
  String get calendarHighlightWeekends => 'Wochenenden einfärben';

  @override
  String get calendarHighlightWeekendsDesc =>
      'Samstag und Sonntag in eigener Farbe anzeigen';

  @override
  String get calendarShowWeekNumbers => 'Kalenderwochen';

  @override
  String get calendarShowWeekNumbersDesc =>
      'Wochennummern am linken Rand anzeigen';

  @override
  String get calendarFilteringSection => 'Filterung';

  @override
  String get calendarShowFilterChips => 'Filter-Chips';

  @override
  String get calendarShowFilterChipsDesc =>
      'Aktive Filter als Zeile über dem Raster anzeigen';

  @override
  String publicHolidayObserved(String name) {
    return '$name (Ersatztag)';
  }

  @override
  String get calendarShowRecurrenceLabels => 'Wiederholung in Zeilen';

  @override
  String get calendarShowRecurrenceLabelsDesc =>
      'Wiederholungsmuster (Täglich, Wöchentlich…) in Ereigniszeilen anzeigen';

  @override
  String get calendarMissedDisplayTitle => 'Verpasste Tage';

  @override
  String get calendarMissedDisplayDesc =>
      'Wie verpasste Tage eines erfassten Termins im Kalender erscheinen';

  @override
  String get calendarMissedDisplayFaded => 'Abgeblendet';

  @override
  String get calendarMissedDisplayHidden => 'Ausgeblendet';

  @override
  String get eventSkipOccurrence => 'Diesen Tag auslassen';

  @override
  String get eventOccurrenceSkipped => 'Termin ausgelassen';

  @override
  String get eventSkippedDays => 'Ausgelassene Tage';

  @override
  String eventSkippedDaysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage ausgelassen',
      one: '1 Tag ausgelassen',
    );
    return '$_temp0';
  }

  @override
  String get eventNoSkippedDays => 'Keine';

  @override
  String get eventTemplates => 'Terminvorlagen';

  @override
  String get eventTemplatesDesc =>
      'Wiederverwendbare Vorlagen — Kategorie, Zeitplan, Farbe und Details vorausgefüllt';

  @override
  String get createTemplate => 'Neue Vorlage';

  @override
  String get editTemplate => 'Vorlage bearbeiten';

  @override
  String get templateName => 'Vorlagenname';

  @override
  String get templateNameHint => 'Push-Tag';

  @override
  String get saveAsTemplate => 'Als Vorlage speichern';

  @override
  String get templateSaved => 'Vorlage gespeichert';

  @override
  String get deleteTemplate => 'Vorlage löschen';

  @override
  String deleteTemplateConfirm(String name) {
    return '„$name\" löschen? Bereits erstellte Termine bleiben erhalten.';
  }

  @override
  String get templateDeleted => 'Vorlage gelöscht';

  @override
  String get addFromTemplate => 'Aus Vorlage hinzufügen';

  @override
  String get templateBlankEvent => 'Leerer Termin';

  @override
  String eventCreatedFromTemplate(String title) {
    return 'Hinzugefügt: $title';
  }

  @override
  String eventCreatedFromTemplateOn(String title, String date) {
    return 'Hinzugefügt: $title — zuerst am $date';
  }

  @override
  String get noEventTemplates => 'Noch keine Vorlagen';

  @override
  String get noEventTemplatesDesc =>
      'Speichere einen Termin als Vorlage, um seine Angaben später wiederzuverwenden.';

  @override
  String eventAdherenceSummary(int attended, int total, int days) {
    return '$attended/$total wahrgenommen · letzte $days Tage';
  }

  @override
  String eventAdherenceStreak(int count, int best) {
    return 'Serie $count · Bestwert $best';
  }

  @override
  String get calendarEventTintTitle => 'Tage nach Terminfarbe einfärben';

  @override
  String get calendarEventTintDesc =>
      'Färbt jeden Tag in der Farbe seines wichtigsten Termins. Kräftiger heißt höhere Priorität.';

  @override
  String get calendarTintConflictTitle => 'An Fastentagen';

  @override
  String get calendarTintConflictDesc =>
      'Welche Farbe gewinnt, wenn ein Tag Termin und Fastentag ist';

  @override
  String get calendarTintConflictEvent => 'Termin';

  @override
  String get calendarTintConflictFasting => 'Fasten';

  @override
  String get calendarTintConflictBoth => 'Beide';

  @override
  String get calendarWeekStartTitle => 'Woche beginnt am';

  @override
  String daySummaryEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String get dateOffset => 'Datumsversatz';

  @override
  String get dateOffsetDescription =>
      'Das Datum von heute vor- oder zurückverschieben';

  @override
  String get days => 'Tage';

  @override
  String get monthsLabel => 'Monate';

  @override
  String get yearsLabel => 'Jahre';

  @override
  String get repeatSettings => 'Wiederholen';

  @override
  String get repeatDescription => 'Diese Verknüpfung mehrmals einfügen';

  @override
  String get repeatCount => 'Wiederholungsanzahl';

  @override
  String get separator => 'Trennzeichen';

  @override
  String get newLine => 'Neue Zeile';

  @override
  String get noSeparator => 'Keines';

  @override
  String get space => 'Leerzeichen';

  @override
  String get nbspSpace => 'Geschütztes';

  @override
  String get blankLine => 'Leerzeile';

  @override
  String get comma => 'Komma';

  @override
  String get pipe => 'Senkrechter Strich';

  @override
  String get incrementDateOnRepeat => 'Datum bei Wiederholung erhöhen';

  @override
  String get incrementByEachRepeat => 'Erhöhung pro Wiederholung:';

  @override
  String get advancedOptions => 'Erweiterte Optionen';

  @override
  String get advancedOptionsDescription =>
      'Datumsversatz, Wiederholung und mehr';

  @override
  String get repeatWrapperText => 'Umschließender Text';

  @override
  String get repeatWrapperTextDesc =>
      'Text, der vor/nach allen wiederholten Elementen eingefügt wird';

  @override
  String get beforeAllRepeats => 'Vor allen';

  @override
  String get beforeAllRepeatsHint => 'z.B. ## Woche 1\\n';

  @override
  String get afterAllRepeats => 'Nach allen';

  @override
  String get afterAllRepeatsHint => 'z.B. \\n---';

  @override
  String get developerOptions => 'Entwickleroptionen';

  @override
  String get developerOptionsDesc => 'Debug-Tools und Diagnose';

  @override
  String get developerOptionsWarning =>
      'Diese Optionen dienen nur zum Debuggen. Ihre Aktivierung kann die App-Leistung beeinträchtigen.';

  @override
  String get developerOptionsReset =>
      'Entwickleroptionen auf Standard zurückgesetzt';

  @override
  String get developerModeUnlocked => 'Entwicklermodus freigeschaltet!';

  @override
  String get lockDeveloperMode => 'Entwicklermodus sperren';

  @override
  String get developerModeLocked => 'Entwicklermodus gesperrt';

  @override
  String get visualizationDebug => 'Visualisierung / Debug';

  @override
  String get colorMarkdownBlocks => 'Markdown-Blöcke einfärben';

  @override
  String get colorMarkdownBlocksDesc =>
      'Verschiedene Farben für Überschriften, Code, Listen usw. anzeigen';

  @override
  String get showBlockBoundaries => 'Blockgrenzen anzeigen';

  @override
  String get showBlockBoundariesDesc =>
      'Rahmen um jedes analysierte Element zeichnen';

  @override
  String get showWhitespace => 'Leerzeichen anzeigen';

  @override
  String get showWhitespaceDesc =>
      'Leerzeichen, Tabs und Zeilenumbrüche visualisieren';

  @override
  String get showPreviewLineNumbers => 'Zeilennummern in Vorschau';

  @override
  String get showPreviewLineNumbersDesc =>
      'Quell-Zeilennummern im Vorschaumodus anzeigen';

  @override
  String get performanceMonitoring => 'Leistungsüberwachung';

  @override
  String get showRenderTime => 'Renderzeit anzeigen';

  @override
  String get showRenderTimeDesc =>
      'Anzeigen, wie lange die Vorschau zum Rendern braucht';

  @override
  String get showFpsCounter => 'FPS-Zähler anzeigen';

  @override
  String get showFpsCounterDesc => 'Scroll- und Animationsleistung überwachen';

  @override
  String get showChunkIndicators => 'Chunk-Indikatoren anzeigen';

  @override
  String get showChunkIndicatorsDesc =>
      'Hervorheben, welche Chunks in der Vorschau geladen sind';

  @override
  String get showRepaintRainbow => 'Repaint-Rainbow anzeigen';

  @override
  String get showRepaintRainbowDesc =>
      'Widgets einfärben, wenn sie neu gezeichnet werden (Flutter-Debug)';

  @override
  String get editorDebug => 'Editor-Debug';

  @override
  String get showCursorInfo => 'Cursor-Info anzeigen';

  @override
  String get showCursorInfoDesc => 'Zeile, Spalte und Zeichenoffset anzeigen';

  @override
  String get showSelectionDetails => 'Auswahldetails anzeigen';

  @override
  String get showSelectionDetailsDesc =>
      'Start- und Endpositionen sowie Länge anzeigen';

  @override
  String get logParserEvents => 'Parser-Ereignisse protokollieren';

  @override
  String get logParserEventsDesc =>
      'Parsing-Informationen an die Debug-Konsole ausgeben';

  @override
  String get storageData => 'Speicher / Daten';

  @override
  String get showNoteSize => 'Notizgröße anzeigen';

  @override
  String get showNoteSizeDesc => 'Inhaltsgröße in Bytes anzeigen';

  @override
  String get showDatabaseStats => 'Datenbankstatistik anzeigen';

  @override
  String get showDatabaseStatsDesc => 'Abfrageanzahl und Cache-Informationen';

  @override
  String get saveStatusSaved => 'Gespeichert';

  @override
  String get saveStatusUnsaved => 'Ungespeichert';

  @override
  String get saveStatusSaving => 'Speichern…';

  @override
  String get saveStatusError => 'Speichern fehlgeschlagen';

  @override
  String get toolbarLayout => 'Toolbar-Layout';

  @override
  String get shortcuts => 'Kurzbefehle';

  @override
  String get utilities => 'Werkzeuge';

  @override
  String get splitToolbar => 'Toolbar teilen';

  @override
  String get utilityButtons => 'Hilfsschaltflächen';

  @override
  String get utilityButtonsHint =>
      'Sichtbarkeit umschalten und zum Neuordnen ziehen';

  @override
  String get markdownBars => 'Markdown-Leisten';

  @override
  String get activeBar => 'Aktive Leiste';

  @override
  String get editingBar => 'Leiste bearbeiten';

  @override
  String get addBar => 'Leiste hinzufügen';

  @override
  String get deleteBar => 'Leiste löschen';

  @override
  String get deleteBarConfirm =>
      'Möchten Sie diese Leiste wirklich löschen? Notizen, die sie verwenden, fallen auf die globale aktive Leiste zurück.';

  @override
  String get renameBar => 'Leiste umbenennen';

  @override
  String get duplicateBar => 'Leiste duplizieren';

  @override
  String get barName => 'Leistenname';

  @override
  String get defaultBar => 'Standard';

  @override
  String get switchBar => 'Leiste wechseln';

  @override
  String get searchBars => 'Leisten suchen...';

  @override
  String get noMatchingBars => 'Keine passenden Leisten';

  @override
  String get perNoteBarAssignment => 'Notiz-Leisten-Zuweisung';

  @override
  String get perNoteBarHint =>
      'Weisen Sie einzelnen Notizen eine bestimmte Leiste zu. Notizen ohne Zuweisung verwenden die globale aktive Leiste.';

  @override
  String get useGlobalBar => 'Globale Leiste verwenden';

  @override
  String get cannotDeleteDefault =>
      'Die Standardleiste kann nicht gelöscht werden';

  @override
  String get cannotRenameDefault =>
      'Die Standardleiste kann nicht umbenannt werden';

  @override
  String get barSwitcherTitle => 'Markdown-Leiste auswählen';

  @override
  String get noteBarOverride => 'Notiz-Überschreibung';

  @override
  String get clearOverride => 'Überschreibung entfernen';

  @override
  String get manageBarProfiles => 'Leistenprofile verwalten';

  @override
  String get alwaysVisible => 'Immer sichtbar';

  @override
  String get visible => 'Sichtbar';

  @override
  String get goToTop => 'Zum Anfang';

  @override
  String get goToBottom => 'Zum Ende';

  @override
  String get hidden => 'Ausgeblendet';

  @override
  String get insertCounter => 'Zählerwert einfügen';

  @override
  String get counterBindingsTitle => 'Zähler-Bindungen';

  @override
  String get counterBindingsDescription =>
      'Binde bis zu zwei Zähler an dieses Kürzel und verwende die Tokens c1 und c2 (in geschweiften Klammern) im Davor/Danach-Text, um ihre Werte einzufügen. Jede Token-Auflösung verändert den Zähler einmal pro Wiederholung.';

  @override
  String get addCounterBinding => 'Zähler-Bindung hinzufügen';

  @override
  String get addSecondCounterBinding => 'Zweite Zähler-Bindung hinzufügen';

  @override
  String get removeCounterBinding => 'Zähler-Bindung entfernen';

  @override
  String get counterTokensHint =>
      'Tippe ein Token, um es an der Cursor-Position einzufügen.';

  @override
  String get counterOperation => 'Operation';

  @override
  String get counterOpIncrement => 'Erhöhen';

  @override
  String get counterOpKeep => 'Beibehalten';

  @override
  String get counterOpDecrement => 'Verringern';

  @override
  String get selectCounter => 'Zähler auswählen';

  @override
  String get noCountersYet => 'Noch keine Zähler erstellt';

  @override
  String get noCountersYetHint =>
      'Noch keine Zähler erstellt. Verwende die Schaltfläche \"Zähler hinzufügen\" unten, um einen zu erstellen.';

  @override
  String get addCounter => 'Zähler hinzufügen';

  @override
  String get counterName => 'Zählername';

  @override
  String get startValue => 'Startwert';

  @override
  String get step => 'Schritt';

  @override
  String get counterScope => 'Zählerbereich';

  @override
  String get global => 'Global';

  @override
  String get perNote => 'Pro Notiz';

  @override
  String get editCounter => 'Zähler bearbeiten';

  @override
  String get deleteCounter => 'Zähler löschen';

  @override
  String get deleteCounterConfirm =>
      'Möchten Sie diesen Zähler wirklich löschen? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get resetCounter => 'Zähler zurücksetzen';

  @override
  String get resetCounterConfirm =>
      'Diesen Zähler auf den Startwert zurücksetzen?';

  @override
  String get counters => 'Zähler';

  @override
  String get counterSettings => 'Zähler';

  @override
  String get counterSettingsDesc =>
      'Auto-Inkrement-Zähler erstellen und verwalten';

  @override
  String counterCurrentValue(int value) {
    return 'Aktuell: $value';
  }

  @override
  String counterStepLabel(int step) {
    return 'Schritt: $step';
  }

  @override
  String get counterEmptyState =>
      'Noch keine Zähler. Tippe +, um einen zu erstellen.';

  @override
  String get counterResetSuccess => 'Zähler auf Startwert zurückgesetzt';

  @override
  String get counterDeleteSuccess => 'Zähler gelöscht';

  @override
  String get counterSetValue => 'Wert setzen';

  @override
  String get counterValuePerNote => 'Wert variiert pro Notiz';

  @override
  String get counterScopeGlobalDesc => 'Geteilt über alle Notizen';

  @override
  String get counterScopePerNoteDesc => 'Unabhängiger Wert pro Notiz';

  @override
  String get pickCounter => 'Zähler auswählen';

  @override
  String get searchCounters => 'Zähler suchen…';

  @override
  String get noCountersMatchSearch => 'Keine Zähler gefunden';

  @override
  String get counterInsertTooltip => 'Zählerwert einfügen';

  @override
  String get createCounterInline => 'Neuen Zähler erstellen';

  @override
  String get manageCounters => 'Zähler verwalten';

  @override
  String counterPickerPage(int current, int total) {
    return '$current / $total';
  }

  @override
  String get selectNote => 'Notiz auswählen';

  @override
  String get searchNotes => 'Notizen suchen…';

  @override
  String get noNotesAvailable => 'Noch keine Notizen';

  @override
  String get noNotesMatchSearch => 'Keine Notizen gefunden';

  @override
  String get counterSelectNoteToView => 'Tippen, um Notizwerte zu verwalten';

  @override
  String get counterLoadError => 'Zähler konnten nicht geladen werden';

  @override
  String get counterRetry => 'Erneut versuchen';

  @override
  String get counterPerNoteValues => 'Werte pro Notiz';

  @override
  String get counterPerNoteEmpty =>
      'Noch keine Notizen haben Werte für diesen Zähler';

  @override
  String get counterResetAllNotes => 'Alle Notizen zurücksetzen';

  @override
  String get counterResetAllConfirm =>
      'Diesen Zähler für alle Notizen auf den Startwert zurücksetzen?';

  @override
  String get counterResetAllSuccess => 'Alle Notizwerte zurückgesetzt';

  @override
  String get counterManageNoteValues => 'Notizwerte verwalten';

  @override
  String get pinCounter => 'Anheften';

  @override
  String get unpinCounter => 'Lösen';

  @override
  String get addNote => 'Notiz hinzufügen';

  @override
  String get removeNote => 'Notiz entfernen';

  @override
  String get removeNoteConfirm =>
      'Diese Notiz vom Zähler entfernen? Der Wert geht verloren.';

  @override
  String get noteAlreadyAdded => 'Diese Notiz ist bereits hinzugefügt';

  @override
  String get moveToFolder => 'In Ordner verschieben';

  @override
  String get selectDestinationFolder => 'Ziel auswählen';

  @override
  String get moveToTitle => 'Verschieben nach…';

  @override
  String get currentlyIn => 'Aktuell in';

  @override
  String subfoldersOf(String name) {
    return 'Unterordner von $name';
  }

  @override
  String moveToDestination(String name) {
    return 'Nach $name verschieben';
  }

  @override
  String get rootFolder => 'Stammordner';

  @override
  String get noteMoved => 'Notiz erfolgreich verschoben';

  @override
  String get noteMoveFailed => 'Notiz konnte nicht verschoben werden';

  @override
  String get alreadyInThisFolder =>
      'Notiz befindet sich bereits in diesem Ordner';

  @override
  String get noFoldersAvailable => 'Keine Ordner verfügbar';

  @override
  String get noSubfolders => 'Keine Unterordner hier';

  @override
  String get back => 'Zurück';

  @override
  String get openFolder => 'Ordner öffnen';

  @override
  String get selectAsDestination => 'Als Ziel auswählen';

  @override
  String get moveHere => 'Hierher verschieben';

  @override
  String get folderMoved => 'Ordner erfolgreich verschoben';

  @override
  String get folderMoveFailed => 'Ordner konnte nicht verschoben werden';

  @override
  String get cannotMoveIntoSelf =>
      'Ein Ordner kann nicht in sich selbst oder einen Unterordner verschoben werden';

  @override
  String folderNameAlreadyExists(String name) {
    return 'Ein Ordner mit dem Namen \"$name\" existiert hier bereits';
  }

  @override
  String noteTitleAlreadyExists(String title) {
    return 'Eine Notiz mit dem Titel \"$title\" existiert hier bereits';
  }

  @override
  String moveSkippedDueToDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Elemente wurden übersprungen, da das Ziel bereits Elemente mit demselben Namen enthält',
      one:
          '1 Element wurde übersprungen, da das Ziel bereits ein Element mit demselben Namen enthält',
    );
    return '$_temp0';
  }

  @override
  String get moveHistory => 'Verschiebeverlauf';

  @override
  String get noMoveHistory => 'Keine letzten Verschiebungen';

  @override
  String get clearHistory => 'Verlauf löschen';

  @override
  String movedToTarget(String target) {
    return 'Verschoben nach $target';
  }

  @override
  String get undone => 'Rückgängig gemacht';

  @override
  String get moveUndone => 'Verschiebung rückgängig gemacht';

  @override
  String get timeLessThanMinute => '<1m';

  @override
  String timeMinutes(int count) {
    return '${count}m';
  }

  @override
  String timeHours(int count) {
    return '${count}h';
  }

  @override
  String timeDays(int count) {
    return '${count}d';
  }

  @override
  String get originalLocationGone =>
      'Ursprünglicher Speicherort existiert nicht mehr';

  @override
  String get moveUndoCanceled => 'Wiederherstellung abgebrochen';

  @override
  String get clearMoveHistoryConfirm =>
      'Gesamten Verschiebeverlauf löschen? Dies kann nicht rückgängig gemacht werden.';

  @override
  String get searchFolders => 'Ordner suchen';

  @override
  String get noFoldersFound => 'Keine Ordner gefunden';

  @override
  String get recentDestinations => 'Zuletzt verwendet';

  @override
  String itemsMoved(int count) {
    return '$count Elemente verschoben';
  }

  @override
  String get moveSelected => 'Verschieben';

  @override
  String get deleteSelected => 'Löschen';

  @override
  String deleteSelectedConfirm(int count) {
    return '$count ausgewählte Elemente löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get selectAll => 'Alle auswählen';

  @override
  String get linkOpenFailed => 'Link konnte nicht geöffnet werden';

  @override
  String get linkSchemeNotAllowed => 'Linktyp nicht unterstützt';

  @override
  String linkOpenPrompt(String target) {
    return '$target öffnen?';
  }

  @override
  String get linkOpenAction => 'Öffnen';

  @override
  String get moneySection => 'Kassenbuch';

  @override
  String get moneyLedgerEnabledLabel => 'Kassenbuch aktivieren';

  @override
  String get moneyLedgerEnabledDesc =>
      '\$-Geldzeilen in Notizen und im Kalender anzeigen';

  @override
  String get moneyStartBalance => 'Startguthaben';

  @override
  String get moneyStartBalanceDesc => 'Jede Notiz startet mit diesem Betrag';

  @override
  String get moneyCurrencySymbolLabel => 'Währungssymbol';

  @override
  String get moneyCurrencySymbolDesc =>
      'Bei berechneten Beträgen angezeigt (z. B. lei, €, \$)';

  @override
  String get moneyCurrencySuffixLabel => 'Symbol nach dem Betrag';

  @override
  String get moneyCurrencySuffixDesc => '12.50 lei statt lei12.50';

  @override
  String get moneyPerNoteCurrency => 'Währung pro Notiz';

  @override
  String get useGlobalCurrency => 'Globale Währung verwenden';

  @override
  String get moneyCustomSymbol => 'Eigenes…';

  @override
  String get moneyDetailTitle => 'Kassenbuch';

  @override
  String get moneyErrorMissingAmount => 'Betrag nach \":\" fehlt';

  @override
  String get moneyErrorUnknownColour => 'unbekannter Farbname';

  @override
  String get moneyErrorInvalidAmount => 'ungültiger Betrag';

  @override
  String get moneyErrorInvalidCount => 'ungültige Anzahl';

  @override
  String get moneyErrorDivideByZero => 'Division durch Null';

  @override
  String get moneyErrorAmountTooLarge =>
      'Betrag zu groß (max. 99.999.999.999,99)';

  @override
  String get moneyErrorTooManyDecimals => 'zu viele Nachkommastellen';

  @override
  String moneyDaySummaryTitle(String amount) {
    return 'Geld: $amount';
  }

  @override
  String get markdownColorsTitle => 'Textfarben';

  @override
  String get markdownColorsSubtitle => 'Farben für Text und Hervorhebungen';

  @override
  String get editColors => 'Farben bearbeiten';

  @override
  String get markdownColorsHowTo =>
      'Farbnamen vor den Text schreiben. Unbekannte Namen bleiben unverändert.';

  @override
  String get markdownColorsSampleText => 'Beispieltext';

  @override
  String get markdownColorsFallbackNote =>
      'Eigene Farben werden automatisch angepasst, wenn sie im aktuellen Design unlesbar wären.';

  @override
  String get markdownColorsPresets => 'Vorgaben';

  @override
  String get markdownColorsCustom => 'Eigene Farben';

  @override
  String get markdownColorsEmpty =>
      'Noch keine eigenen Farben. Zum Hinzufügen auf + tippen.';

  @override
  String get markdownColorsNameTitle => 'Farbname';

  @override
  String get markdownColorsNameHint => 'Kleinbuchstaben, Ziffern, - und _';

  @override
  String get markdownColorsNameInvalid =>
      'Name mit Buchstaben, Ziffern, - oder _ eingeben';

  @override
  String get markdownColorsRecolor => 'Farbe ändern';

  @override
  String get markdownColorsRename => 'Umbenennen';

  @override
  String get markdownColorsDelete => 'Löschen';

  @override
  String get markdownColorsDeleteTitle => 'Farbe löschen';

  @override
  String get markdownColorsOverridden => 'Durch eigene Farbe ersetzt';

  @override
  String markdownColorsNameTaken(String name) {
    return '„$name“ wird bereits verwendet';
  }

  @override
  String markdownColorsLimitReached(int count) {
    return 'Farbgrenze erreicht ($count)';
  }

  @override
  String markdownColorsDeleteMessage(String name) {
    return '„$name“ löschen? Notizen, die sie verwenden, zeigen einfachen Text.';
  }

  @override
  String get upcomingEvents => 'Demnächst';

  @override
  String get upcomingSearchHint => 'Ereignisse suchen';

  @override
  String get upcomingClearSearch => 'Suche leeren';

  @override
  String get upcomingClearRange => 'Eigenen Zeitraum löschen';

  @override
  String get upcomingClearCategories => 'Alle Kategorien anzeigen';

  @override
  String get upcomingEventDisplayTitle => 'Termin-Zeilen';

  @override
  String get upcomingEventDisplayEveryOccurrence => 'Jedes';

  @override
  String get upcomingEventDisplayPerEvent => 'Pro Termin';

  @override
  String get upcomingEventDisplaySummary => 'Eine Karte';

  @override
  String upcomingEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Termine',
      one: '1 Termin',
    );
    return '$_temp0';
  }

  @override
  String get upcomingFastingDisplayTitle => 'Fasten-Zeilen';

  @override
  String get upcomingFastingDisplayEveryDay => 'Jeder Tag';

  @override
  String get upcomingFastingDisplayPeriods => 'Zeiträume';

  @override
  String get upcomingFastingDisplaySummary => 'Eine Karte';

  @override
  String get upcomingHolidayDisplayTitle => 'Feiertags-Zeilen';

  @override
  String get upcomingHolidayDisplayEveryDay => 'Jeder Tag';

  @override
  String get upcomingHolidayDisplaySummary => 'Eine Karte';

  @override
  String upcomingHolidayCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Feiertage',
      one: '1 Feiertag',
    );
    return '$_temp0';
  }

  @override
  String get upcomingShowAllDays => 'Alle Tage anzeigen';

  @override
  String get upcomingFollowSelectedDay => 'Ab ausgewähltem Tag';

  @override
  String upcomingCollapsedTimes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count× im Zeitraum',
      one: '1× im Zeitraum',
    );
    return '$_temp0';
  }

  @override
  String upcomingFastingSpanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String upcomingAnchorFrom(String date) {
    return 'ab $date';
  }

  @override
  String get upcomingRemoveFilter => 'Filter entfernen';

  @override
  String get upcomingResetAnchor => 'Zurück zu heute';

  @override
  String get upcomingFiltersReset => 'Zurücksetzen';

  @override
  String get upcomingSectionPeriod => 'Zeitraum';

  @override
  String get upcomingSectionShow => 'Anzeigen';

  @override
  String get upcomingSectionDisplay => 'Darstellung';

  @override
  String get upcomingShowEvents => 'Ereignisse';

  @override
  String get upcomingEventsHidden => 'Keine Ereignisse';

  @override
  String upcomingPeriodDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get upcomingPeriodRestOfYear => 'Rest des Jahres';

  @override
  String get upcomingPeriodWholeYear => 'Dieses Jahr';

  @override
  String get upcomingPeriodCustom => 'Eigener';

  @override
  String get upcomingPriority => 'Priorität';

  @override
  String get upcomingPriorityAny => 'Alle';

  @override
  String get upcomingNoEvents => 'Nichts geplant';

  @override
  String get upcomingDidYouMean => 'Meintest du';

  @override
  String get upcomingNoEventsHint =>
      'Längeren Zeitraum oder niedrigere Priorität wählen';

  @override
  String get upcomingToday => 'Heute';

  @override
  String get upcomingTomorrow => 'Morgen';

  @override
  String get upcomingEditEvent => 'Ereignis bearbeiten';

  @override
  String get upcomingShowHolidays => 'Feiertage';

  @override
  String get upcomingShowFasting => 'Fasten';

  @override
  String get upcomingEventType => 'Ereignisse';

  @override
  String get upcomingEventTypeAll => 'Alle';

  @override
  String get upcomingEventTypeRecurring => 'Wiederkehrend';

  @override
  String get upcomingEventTypeOneTime => 'Einmalig';

  @override
  String get upcomingFilters => 'Filter';

  @override
  String get panelExpand => 'Bereich vergrößern';

  @override
  String get panelShowCalendar => 'Kalender anzeigen';

  @override
  String get panelModeDay => 'Tag';

  @override
  String get panelModeTimeline => 'Zeitplan';

  @override
  String get timelineEmptyHint =>
      'Ereignisse mit Startzeit erscheinen im Zeitplan';

  @override
  String get exportEventsIcs => 'Ereignisse exportieren (.ics)';

  @override
  String get exportingEvents => 'Ereignisse werden exportiert...';

  @override
  String get eventsExportError => 'Ereignisse konnten nicht exportiert werden';

  @override
  String eventsExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ereignisse exportiert',
      one: '1 Ereignis exportiert',
      zero: 'Keine Ereignisse exportiert',
    );
    return '$_temp0';
  }

  @override
  String get searchShortcuts => 'Kürzel suchen';

  @override
  String get shortcutCategory => 'Kategorie';

  @override
  String get setCategory => 'Kategorie festlegen';

  @override
  String get uncategorized => 'Ohne Kategorie';

  @override
  String get categoryHint => 'z. B. Push-Tag';

  @override
  String get noCategory => 'Keine Kategorie';

  @override
  String get existingCategories => 'Vorhandene Kategorien';

  @override
  String get clearFilters => 'Zurücksetzen';

  @override
  String get clearSearchToReorder =>
      'Suche und Filter löschen, um zu sortieren';

  @override
  String get noShortcutsMatchFilter => 'Keine passenden Kürzel';

  @override
  String shortcutCountFiltered(int shown, int total) {
    return '$shown / $total';
  }

  @override
  String get collapseAll => 'Alle einklappen';

  @override
  String get expandAll => 'Alle ausklappen';

  @override
  String get searchUtilityButtons => 'Schaltflächen suchen';

  @override
  String get noMatchesFound => 'Keine Treffer';

  @override
  String get searchSettings => 'Einstellungen suchen';

  @override
  String settingsSectionCollapsedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Optionen',
      one: '1 Option',
    );
    return '$_temp0';
  }

  @override
  String get hapticFeedbackKeywords => 'Vibration, Summen, Rütteln';

  @override
  String get autoSaveKeywords => 'Sicherung, Speichern, Backup';

  @override
  String get wordWrapKeywords => 'Zeile, Überlauf, Umbruch';

  @override
  String get swipeKeywords => 'Geste, Wischen, Ziehen';

  @override
  String get liveMarkdownKeywords => 'Vorschau, Darstellung, Formatierung';

  @override
  String get lineNumbersKeywords => 'Zeilennummern, Nummerierung';

  @override
  String get confirmDeleteKeywords => 'Papierkorb, Entfernen, Nachfrage';

  @override
  String get performanceKeywords =>
      'Geschwindigkeit, Verzögerung, Abschnitt, schnell';

  @override
  String get cursorKeywords => 'Einfügemarke, aktuelle Zeile';

  @override
  String get keyboardKeywords => 'Tippen, Eingabe';

  @override
  String get sharingSettings => 'Teilen';

  @override
  String get sharingSettingsDesc => 'Anmelden, um mit jemandem zu teilen';

  @override
  String get accountSection => 'Konto';

  @override
  String get signInWithGoogle => 'Mit Google anmelden';

  @override
  String get signOut => 'Abmelden';

  @override
  String get notSignedIn => 'Nicht angemeldet';

  @override
  String get signingIn => 'Anmeldung läuft…';

  @override
  String get syncUnavailablePlatform => 'Auf dieser Plattform nicht verfügbar';

  @override
  String get syncUnavailablePlatformDesc =>
      'Teilen funktioniert auf Android und iOS. Deine Daten bleiben auf diesem Gerät.';

  @override
  String get signInFailed => 'Anmeldung fehlgeschlagen';

  @override
  String get authErrorOffline =>
      'Keine Verbindung. Prüf dein Netzwerk und versuch es erneut.';

  @override
  String get authErrorUnavailable => 'Anmeldung ist hier nicht verfügbar';

  @override
  String get authErrorNotSupported =>
      'Google-Anmeldung ist auf diesem Gerät nicht verfügbar';

  @override
  String get authErrorUnknown => 'Anmeldung fehlgeschlagen. Versuch es erneut.';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get sharingKeywords =>
      'Cloud, Synchronisierung, Konto, Google, Anmeldung, Teilen, Partner, Kopplung, Code, Einladung, Trennen';

  @override
  String get aboutDescription =>
      'Ein Offline-First-Tracker für den Alltag: Ordner, Markdown-Notizen, ein Geldbuch, Zähler und ein Kalender.';

  @override
  String get pairingSection => 'Kopplung';

  @override
  String get pairingNotPaired => 'Nicht gekoppelt';

  @override
  String get pairingNotPairedDesc => 'Mit jemandem teilen';

  @override
  String get pairingSignInFirst => 'Zum Teilen anmelden';

  @override
  String get pairingWaiting => 'Warten auf deinen Partner';

  @override
  String pairingPairedWith(String name) {
    return 'Gekoppelt mit $name';
  }

  @override
  String get pairingPairedDesc => 'Verbunden. Es wird noch nichts geteilt.';

  @override
  String get pairingPartnerUnknown => 'Gekoppelt';

  @override
  String get pairingTitle => 'Mit jemandem koppeln';

  @override
  String get pairingGenerateCode => 'Code erstellen';

  @override
  String get pairingCodeIntro =>
      'Lies der anderen Person diesen Code vor. Er funktioniert einmal.';

  @override
  String pairingCodeExpiresIn(String time) {
    return 'Läuft ab in $time';
  }

  @override
  String get pairingCodeExpired => 'Dieser Code ist abgelaufen';

  @override
  String get copy => 'Kopieren';

  @override
  String get share => 'Teilen';

  @override
  String get pairingCodeCopied => 'Code kopiert';

  @override
  String pairingShareMessage(String code) {
    return 'Kopple dich mit mir in ANTA – Code: $code';
  }

  @override
  String get pairingEnterCode => 'Code eingeben';

  @override
  String get pairingCodeHint => 'XXXX-XXXX';

  @override
  String get pairingConnect => 'Verbinden';

  @override
  String get pairingOr => 'oder';

  @override
  String get unpair => 'Trennen';

  @override
  String pairingUnpairConfirm(String name) {
    return 'Teilen mit $name beenden? Deine Notizen und Termine bleiben auf diesem Gerät. Es wird nichts Neues mehr geteilt.';
  }

  @override
  String get pairingEndedTitle => 'Teilen beendet';

  @override
  String pairingEndedBy(String name) {
    return '$name hat das Teilen beendet. Deine Notizen und Termine bleiben auf diesem Gerät.';
  }

  @override
  String get pairingEndedByPartner =>
      'Dein Partner hat das Teilen beendet. Deine Notizen und Termine bleiben auf diesem Gerät.';

  @override
  String pairingSignOutConfirm(String name) {
    return 'Abmelden? Das Teilen mit $name pausiert, bis du dich wieder anmeldest.';
  }

  @override
  String get pairingErrorOffline =>
      'Keine Verbindung. Die Kopplung braucht Internet.';

  @override
  String get pairingErrorNotSignedIn => 'Zuerst anmelden';

  @override
  String get pairingErrorUnavailable => 'Kopplung ist hier nicht verfügbar';

  @override
  String get pairingErrorCodeInvalid =>
      'Dieser Code gilt nicht mehr. Frag nach einem neuen.';

  @override
  String get pairingErrorOwnCode => 'Das ist dein eigener Code';

  @override
  String get pairingErrorAlreadyPaired => 'Du bist bereits gekoppelt';

  @override
  String get pairingErrorPermissionDenied => 'Nicht erlaubt';

  @override
  String get pairingErrorUnknown => 'Kopplung fehlgeschlagen';

  @override
  String get colorPaletteTitle => 'Farben';

  @override
  String get colorPaletteDesc =>
      'Alle Farben, die die Kalender-Auswahlen anbieten. Hinzugefügte Farben erscheinen überall.';

  @override
  String get colorPaletteDefaultsLabel => 'Vorgegebene Farben';

  @override
  String get colorPaletteCustomLabel => 'Deine Farben';

  @override
  String get colorPaletteBuiltIn => 'Vorgegebene Farbe';

  @override
  String get colorPaletteEmpty =>
      'Noch keine eigenen Farben. Füge eine hinzu und sie erscheint in jeder Auswahl.';

  @override
  String get colorPaletteEditHint =>
      'Tippe auf eine Farbe, um sie zu ändern. Alles, was sie bereits nutzt, behält seine Farbe.';

  @override
  String get colorPaletteReset => 'Farben zurücksetzen';

  @override
  String get colorPaletteResetConfirm =>
      'Alle hinzugefügten Farben löschen und nur die vorgegebenen behalten?';

  @override
  String get colorPaletteFull =>
      'Deine Palette ist voll. Lösche eine Farbe, um eine weitere hinzuzufügen.';

  @override
  String get colorAlreadyInPalette => 'Diese Farbe ist bereits in der Palette';

  @override
  String colorPaletteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eigene Farben',
      one: '1 eigene Farbe',
      zero: 'Keine eigenen Farben',
    );
    return '$_temp0';
  }

  @override
  String get addColor => 'Farbe hinzufügen';

  @override
  String get editColor => 'Farbe bearbeiten';

  @override
  String get deleteColor => 'Farbe löschen';

  @override
  String get deleteColorConfirm =>
      'Diese Farbe aus der Palette entfernen? Alles, was sie bereits nutzt, behält seine Farbe.';

  @override
  String get manageColors => 'Farben verwalten';

  @override
  String get colorHexLabel => 'Hex';

  @override
  String get colorHexInvalid => 'Gib eine Farbe wie #3A7BDE ein';

  @override
  String get colorCopyHex => 'Hex-Code kopieren';

  @override
  String get colorHexCopied => 'Kopiert';

  @override
  String get colorPickerCurrent => 'Aktuelle Farbe, tippen zum Zurücksetzen';

  @override
  String get colorPickerNew => 'Neue Farbe';

  @override
  String get colorHue => 'Farbton';

  @override
  String get colorSaturationBrightness => 'Sättigung und Helligkeit';

  @override
  String colorSaturationBrightnessValue(int saturation, int brightness) {
    return 'Sättigung $saturation %, Helligkeit $brightness %';
  }

  @override
  String get colorReorder => 'Zum Umsortieren ziehen';

  @override
  String colorPaletteCapCount(int count, int max) {
    return '$count von $max';
  }

  @override
  String get colorModeSquare => 'Quadrat';

  @override
  String get colorModeWheel => 'Farbkreis';

  @override
  String get colorBrightness => 'Helligkeit';

  @override
  String get colorHueSaturation => 'Farbton und Sättigung';

  @override
  String colorHueSaturationValue(int hue, int saturation) {
    return 'Farbton $hue°, Sättigung $saturation %';
  }

  @override
  String colorShowAll(int count) {
    return '$count weitere Farben anzeigen';
  }

  @override
  String get eventColorCategoryDefault => 'Kategoriefarbe';

  @override
  String get dayListModeList => 'Liste';

  @override
  String get dayListModeMonth => 'Monat';

  @override
  String get dayListModeYear => 'Jahr';

  @override
  String get dayListBackToYear => 'Zurück zu den Monaten';

  @override
  String get dayListWholeMonth => 'Ganzer Monat';

  @override
  String get dayListEmptyMonth => 'Nichts in diesem Monat';

  @override
  String get dayListPreviousMonth => 'Voriger Monat';

  @override
  String get dayListNextMonth => 'Nächster Monat';

  @override
  String get dayListScopeUpcoming => 'Demnächst';

  @override
  String get dayListScopeThisYear => 'Dieses Jahr';

  @override
  String get dayListJumpToToday => 'Dieser Monat';

  @override
  String dayListMissedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verpasst',
      one: '1 verpasst',
    );
    return '$_temp0';
  }
}
