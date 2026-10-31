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
  String get eventStartTime => 'Startzeit';

  @override
  String get eventEndTime => 'Endzeit';

  @override
  String get eventEndTimeNone => 'Keine Endzeit';

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
  String get calendarFilterSavedFilter => 'Gespeicherter Filter';

  @override
  String get calendarFilterSavedNone => 'Keiner';

  @override
  String get calendarFilterSectionEvents => 'Ereignisse';

  @override
  String get calendarFilterCategoriesAll => 'Alle';

  @override
  String get calendarFilterOnlyShowAny => 'Alles';

  @override
  String get calendarFilterSectionAlsoShow => 'Außerdem anzeigen';

  @override
  String get calendarFilterReset => 'Filter zurücksetzen';

  @override
  String get filterPresetNone => 'Kein Filter';

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
  String get calendarFilterHideEnded => 'Nicht beendet';

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
  String get calendarFilterPanelShowsAll => 'Alle Ereignisse im Tagesbereich';

  @override
  String get calendarFilterShowsEverything => 'Zeigt alles';

  @override
  String get calendarFilterNoCategories => 'Keine Kategorien';

  @override
  String get filterPresetsTitle => 'Gespeicherte Filter';

  @override
  String get filterPresetSearchHint => 'Gespeicherte Filter suchen';

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
  String get filterPresetReorder => 'Zum Neuordnen ziehen';

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
  String get holidayRestoreFailed =>
      'Der Feiertag konnte nicht wiederhergestellt werden';

  @override
  String get holidayProfileSwitchFailed =>
      'Die Feiertage konnten nicht gewechselt werden';

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
  String get categoryChangeFailed =>
      'Die Änderung konnte nicht gespeichert werden';

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
  String get iconCustom => 'Eigenes Symbol';

  @override
  String get pickIcon => 'Symbol wählen';

  @override
  String get resetToDefault => 'Auf Standard zurücksetzen';

  @override
  String get eventDate => 'Startdatum';

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
  String get recurrenceIntervalDecrement => 'Häufiger';

  @override
  String get recurrenceIntervalIncrement => 'Seltener';

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
  String get weeklyDaysHint => 'Wähle mindestens einen Wochentag';

  @override
  String get recurrenceScopeLabel => 'Vorkommen';

  @override
  String get recurrenceScopeAlways => 'Immer';

  @override
  String get recurrenceScopeEveryYear => 'Jedes Jahr';

  @override
  String recurrenceScopeAlwaysSuffix(String rule) {
    return '$rule · auch davor';
  }

  @override
  String get eventTrackPresence => 'Anwesenheit erfassen';

  @override
  String get eventAssumePresent => 'Als besucht';

  @override
  String get eventAssumeAbsent => 'Als verpasst';

  @override
  String get eventAssumeAbsentFrom => 'Verpasst ab';

  @override
  String get eventAssumeAbsentFromStart => 'Beginn des Termins';

  @override
  String get eventShowInDayRail => 'Tagesleiste';

  @override
  String get eventShowInDayRailAuto => 'Auto';

  @override
  String get eventShowInDayRailAlways => 'Immer';

  @override
  String get eventShowInDayRailNever => 'Nie';

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
  String get monthYearPickerTypedEntry => 'Datum eintippen';

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
  String get fastingMonthsDesc => 'Ein ausgeschalteter Monat wird nie markiert';

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
  String get fastingWeekdayScopeWeekly => 'Nur wöchentliches Fasten';

  @override
  String get fastingWeekdayScopeAll => 'Alle Fastenzeiten';

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
  String get eventHasDescription => 'Hat Notizen';

  @override
  String get eventDetailsTitle => 'Termin';

  @override
  String get eventTime => 'Uhrzeit';

  @override
  String get eventDetailsNext => 'Nächstes Vorkommen';

  @override
  String eventDetailsThen(String dates) {
    return 'dann $dates';
  }

  @override
  String get eventPresence => 'Anwesenheit';

  @override
  String get eventDetailsNoOccurrences => 'Keine weiteren Vorkommen';

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
  String get eventPriority => 'Priorität';

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
  String get eventLinkedNoteMissing => 'Verknüpfte Notiz existiert nicht mehr';

  @override
  String get eventNoLongerExists => 'Ereignis existiert nicht mehr';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dies löscht auch $count Notizen.',
      one: 'Dies löscht auch 1 Notiz.',
    );
    return 'Möchten Sie \"$name\" wirklich löschen? $_temp0';
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
  String get noteNotFound => 'Notiz nicht gefunden';

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
  String get opensHeaderMenu =>
      'Öffnet das Überschriftenmenü (Fließtext, H1-H6)';

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
  String get headers => 'Überschrift';

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
  String get headingBodyText => 'Fließtext';

  @override
  String get indentLine => 'Einzug vergrößern';

  @override
  String get outdentLine => 'Einzug verringern';

  @override
  String get shortcutHighlight => 'Hervorheben';

  @override
  String get shortcutCallout => 'Hinweisblock';

  @override
  String get shortcutCheckedCheckbox => 'Abgehakt';

  @override
  String get shortcutTable => 'Tabelle';

  @override
  String get shortcutHorizontalRule => 'Trennlinie';

  @override
  String get shortcutImage => 'Bild';

  @override
  String get shortcutGhostText => 'Platzhalter';

  @override
  String get shortcutColorText => 'Farbiger Text';

  @override
  String get shortcutColorHighlight => 'Farbige Markierung';

  @override
  String get shortcutMoneyAdd => 'Geld +';

  @override
  String get shortcutMoneySubtract => 'Geld -';

  @override
  String get shortcutMoneyMultiply => 'Geld ×';

  @override
  String get shortcutMoneyDivide => 'Geld ÷';

  @override
  String get shortcutMoneyStart => 'Geld Start';

  @override
  String get shortcutMoneyTotal => 'Geld Summe';

  @override
  String get shortcutMoneyChange => 'Geld Änderung';

  @override
  String get shortcutMoneyTarget => 'Geld Ziel';

  @override
  String get shortcutMoneyDiff => 'Geld Differenz';

  @override
  String get shortcutMoneySpan => 'Geld Zeitraum';

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
  String get dropPosition => 'Ablageposition';

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
  String get sortByLabel => 'Etikett';

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
  String noteStats(int count, int lines) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat linesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String linesString = linesNumberFormat.format(lines);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Zeichen',
      one: '1 Zeichen',
    );
    String _temp1 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$linesString Zeilen',
      one: '1 Zeile',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String noteChunkCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Teile',
      one: '1 Teil',
    );
    return '$_temp0';
  }

  @override
  String get editorHint => 'Tippe los…';

  @override
  String get closeSearch => 'Suche schließen';

  @override
  String get saveStateSaved => 'Gespeichert';

  @override
  String get saveStateUnsaved => 'Ungespeicherte Änderungen';

  @override
  String get saveStateSaving => 'Wird gespeichert';

  @override
  String get saveStateError => 'Nicht gespeichert';

  @override
  String get compressedNote => 'Komprimiert';

  @override
  String get searchInFolder => 'In diesem Ordner suchen';

  @override
  String get searchAll => 'Alle Notizen durchsuchen';

  @override
  String get recentSearches => 'Letzte Suchen';

  @override
  String get everywhere => 'Überall';

  @override
  String get thisFolder => 'Dieser Ordner';

  @override
  String get recent => 'Zuletzt';

  @override
  String get allNotes => 'Alle Notizen';

  @override
  String get today => 'Heute';

  @override
  String get yesterday => 'Gestern';

  @override
  String get titlesSection => 'Titel';

  @override
  String get inTextSection => 'Im Text';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeilen',
      one: '1 Zeile',
    );
    return '$_temp0';
  }

  @override
  String get emptyFoldersHint =>
      'Sieht so aus, als möchtest du einen Ordner erstellen';

  @override
  String get emptyNotesHint => 'Schreibe deine erste Notiz';

  @override
  String get createFromBarBelow => 'Nutze die Leiste unten zum Anlegen';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String folderCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ordner',
      one: '1 Ordner',
      zero: 'Keine Ordner',
    );
    return '$_temp0';
  }

  @override
  String noteCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizen',
      one: '1 Notiz',
      zero: 'Keine Notizen',
    );
    return '$_temp0';
  }

  @override
  String folderAndNoteCount(String folders, String notes) {
    return '$folders, $notes';
  }

  @override
  String charactersCount(int current, int max) {
    return '$current/$max Zeichen';
  }

  @override
  String get settings => 'Einstellungen';

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
  String get restartRequiredAfterDeletion =>
      'Alle Daten wurden gelöscht. Bitte starten Sie die App neu, um fortzufahren.';

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
  String get appSettingsDesc =>
      'Start, Navigation, Editor und automatisches Speichern';

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
    String _temp0 = intl.Intl.pluralLogic(
      folders,
      locale: localeName,
      other: '$folders Ordner',
      one: '1 Ordner',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes Notizen',
      one: '1 Notiz',
    );
    return '$_temp0 und $_temp1 importiert';
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
  String get restartRequiredNewDatabase =>
      'Bitte starten Sie die App neu, um die neue Datenbank zu verwenden.';

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
  String get themeSettingsDesc => 'Hell, dunkel oder wie das Telefon';

  @override
  String get selectTheme => 'Design auswählen';

  @override
  String get lightTheme => 'Hell';

  @override
  String get darkTheme => 'Dunkel';

  @override
  String get systemTheme => 'System';

  @override
  String get restartRequiredTitle => 'Neustart erforderlich';

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
      'Bricht lange Zeilen beim Einfügen von Text automatisch um.';

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
  String get deprecatedSection => 'Veraltete Funktionen';

  @override
  String get deprecatedSectionIntro =>
      'Bleiben für alle erhalten, die sie bereits nutzen. Standardmäßig aus und in einer künftigen Version möglicherweise entfernt.';

  @override
  String get previewModeEnabled => 'Vorschaumodus';

  @override
  String get previewModeEnabledDesc =>
      'Holt die separate gerenderte Vorschau und ihre Augen-Schaltfläche zurück. Der Editor stellt Markdown bereits beim Tippen dar.';

  @override
  String get previewModeKeywords => 'vorschau, rendern, auge, veraltet';

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
  String get calendarSettingsRow => 'Kalender-Einstellungen';

  @override
  String get appGroupLabel => 'App';

  @override
  String get calendarMaxDayBars => 'Maximale Balken pro Tag';

  @override
  String calendarMaxDayBarsDesc(int count) {
    return 'Zeige bis zu $count Balken pro Tag. Weitere Kategorien werden als +N angezeigt.';
  }

  @override
  String get calendarAppearanceSection => 'Darstellung';

  @override
  String get calendarAppearanceDesc =>
      'Vorschau und Feinabstimmung des Rasters';

  @override
  String get calendarAppearanceDayCellSection => 'Tageszelle';

  @override
  String get calendarAppearanceMarkersSection => 'Markierungen';

  @override
  String get calendarAppearanceRailSection => 'Tagesleiste';

  @override
  String get calendarAppearanceWeekSection => 'Woche';

  @override
  String get calendarAppearanceColorSection => 'Farbe';

  @override
  String get calendarAppearanceLabelsSection => 'Zeilenbeschriftungen';

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
  String get eventAlertAtStart => 'Zum Start';

  @override
  String eventAlertMinutesBefore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Min. vorher',
      one: '1 Min. vorher',
    );
    return '$_temp0';
  }

  @override
  String eventAlertHoursBefore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Std. vorher',
      one: '1 Std. vorher',
    );
    return '$_temp0';
  }

  @override
  String eventAlertDaysBefore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage vorher',
      one: '1 Tag vorher',
    );
    return '$_temp0';
  }

  @override
  String eventAlertAllDayOnDay(String time) {
    return 'Am Tag selbst, $time';
  }

  @override
  String eventAlertAllDayDayBefore(String time) {
    return 'Am Vortag, $time';
  }

  @override
  String eventAlertAllDayDaysBefore(int count, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage vorher, $time',
      one: '1 Tag vorher, $time',
    );
    return '$_temp0';
  }

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
  String get quickAlarmRow => 'Alarm…';

  @override
  String get quickAlarmTitle => 'Schnellalarm';

  @override
  String get quickAlarmName => 'Alarm';

  @override
  String get quickAlarmPickTime => 'Uhrzeit ändern';

  @override
  String get quickAlarmIn20Min => 'In 20 Min.';

  @override
  String get quickAlarmIn1Hour => 'In 1 Stunde';

  @override
  String quickAlarmTonight(String time) {
    return 'Heute Abend $time';
  }

  @override
  String quickAlarmSet(String title, String time) {
    return '$title gestellt für $time';
  }

  @override
  String quickAlarmSetOn(String title, String time, String day) {
    return '$title gestellt für $time, $day';
  }

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
  String get calendarCellStyleTitle => 'Stil der Tageszellen';

  @override
  String get calendarCellStyleDesc =>
      'Wie die Farbe eines Termins die Tageszelle füllt. Jedes Design behält seine eigene Wahl.';

  @override
  String get calendarCellStyleLight => 'Hell';

  @override
  String get calendarCellStyleDark => 'Dunkel';

  @override
  String get calendarCellStyleSolid => 'Flächig';

  @override
  String get calendarCellStyleFade => 'Verlauf';

  @override
  String get calendarCellStyleOutline => 'Umriss';

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
  String get developerOptions => 'Entwickler-Optionen';

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
  String get showAddButtonTrace => 'Kalender-Hinzufügen-Button verfolgen';

  @override
  String get showAddButtonTraceDesc =>
      'Das letzte Scroll-Ereignis anzeigen, auf das der Hinzufügen-Button reagiert hat, und ob er sich aus- oder eingeklappt hat';

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
  String get pinUndoRedo => 'Rückgängig und Wiederholen anheften';

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
  String get counterNotFound => 'Diesen Zähler gibt es nicht mehr';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count ausgewählte Elemente löschen? Dies kann nicht rückgängig gemacht werden.',
      one:
          '1 ausgewähltes Element löschen? Dies kann nicht rückgängig gemacht werden.',
    );
    return '$_temp0';
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
  String wikiLinkNoteNotFound(String title) {
    return 'Keine Notiz mit dem Titel \"$title\"';
  }

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
  String get upcomingSectionDisplay => 'Darstellung';

  @override
  String get upcomingShowEvents => 'Ereignisse';

  @override
  String get upcomingEventsHidden => 'Keine Ereignisse';

  @override
  String get upcomingPeriod => 'Zeitraum';

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
  String get upcomingPeriodCustom => 'Eigener Zeitraum…';

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
  String syncConflictCopyTitle(String title, DateTime dateTime) {
    final intl.DateFormat dateTimeDateFormat = intl.DateFormat.yMMMd(
      localeName,
    ).add_Hm();
    final String dateTimeString = dateTimeDateFormat.format(dateTime);

    return '$title (Konfliktkopie, $dateTimeString)';
  }

  @override
  String get syncNoteUpdatedElsewhere => 'Von einem anderen Gerät aktualisiert';

  @override
  String get syncNoteConflictCopyFiled =>
      'Die Version des anderen Geräts wurde als Kopie gespeichert';

  @override
  String get syncNoteDeletedElsewhere => 'Auf einem anderen Gerät gelöscht';

  @override
  String get syncNoteKeptAsNew =>
      'Auf einem anderen Gerät gelöscht – dein Text wurde als neue Notiz behalten';

  @override
  String get syncNoteConflictCopyFailed =>
      'Kopie konnte nicht gespeichert werden – dein Text bleibt, das nächste Speichern versucht es erneut';

  @override
  String get syncNoteKeptAsNewFailed =>
      'Auf einem anderen Gerät gelöscht – dein Text konnte noch nicht als neue Notiz behalten werden; das nächste Speichern versucht es erneut';

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
  String get colorPaletteEmpty =>
      'Noch keine eigenen Farben. Füge eine hinzu und sie erscheint in jeder Auswahl.';

  @override
  String get colorPaletteReset => 'Farben zurücksetzen';

  @override
  String get colorPaletteResetConfirm =>
      'Alle hinzugefügten Farben löschen und nur die vorgegebenen behalten?';

  @override
  String get colorPaletteResetDone => 'Palette zurückgesetzt';

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
  String get dayListEmptyRange => 'Nichts in diesem Zeitraum';

  @override
  String get renderErrorTitle =>
      'Dieser Teil des Bildschirms konnte nicht dargestellt werden';

  @override
  String renderErrorDetail(String error) {
    return 'Nach unten ziehen oder zurückgehen zum Schließen. Details: $error';
  }

  @override
  String get dayListPreviousMonth => 'Voriger Monat';

  @override
  String get dayListNextMonth => 'Nächster Monat';

  @override
  String get dayListScopeUpcoming => 'Demnächst';

  @override
  String get dayListScopeThisYear => 'Dieses Jahr';

  @override
  String get dayListScopeCalendarYear => 'Kalenderjahr';

  @override
  String get calendarOverview => 'Übersicht';

  @override
  String get calendarOverviewDesc => 'Ereignisse nach Kategorie, Jahr für Jahr';

  @override
  String get calendarViewMenuTooltip => 'Ansicht wechseln';

  @override
  String get overviewCategories => 'Kategorien';

  @override
  String get overviewPeriod => 'Zeitraum';

  @override
  String get overviewPeriodThisWeek => 'Diese Woche';

  @override
  String get overviewPeriodThisMonth => 'Dieser Monat';

  @override
  String get overviewPeriodLast12Months => 'Letzte 12 Monate';

  @override
  String get overviewPeriodLast90Days => 'Letzte 90 Tage';

  @override
  String get overviewPeriodAllTime => 'Gesamter Zeitraum';

  @override
  String get overviewPeriodPrevious => 'Voriger Zeitraum';

  @override
  String get overviewPeriodNext => 'Nächster Zeitraum';

  @override
  String overviewPeriodHome(String period) {
    return 'Zurück zu $period';
  }

  @override
  String overviewCategoryTotal(String label, int count) {
    return '$label $count';
  }

  @override
  String get overviewListOptions => 'Listenoptionen';

  @override
  String get overviewOrder => 'Reihenfolge';

  @override
  String get overviewOrderOldestFirst => 'Älteste zuerst';

  @override
  String get overviewOrderNewestFirst => 'Neueste zuerst';

  @override
  String get overviewRows => 'Zeilen';

  @override
  String get overviewRowsEveryOccurrence => 'Jedes Vorkommen';

  @override
  String get overviewRowsPerEvent => 'Eine pro Termin';

  @override
  String get overviewMissedOnly => 'Nur verpasste';

  @override
  String get overviewViewsTitle => 'Gespeicherte Ansichten';

  @override
  String get overviewViewSaveCurrent => 'Aktuelle Liste speichern';

  @override
  String overviewViewSaved(String name) {
    return 'Als \"$name\" gespeichert';
  }

  @override
  String get overviewViewUpdate => 'Auf aktuelle Liste aktualisieren';

  @override
  String get overviewViewDelete => 'Gespeicherte Ansicht löschen';

  @override
  String overviewViewDeleteConfirm(String name) {
    return '\"$name\" löschen? Die aufgelisteten Ereignisse bleiben unberührt.';
  }

  @override
  String get overviewViewActions => 'Optionen für gespeicherte Ansicht';

  @override
  String overviewViewLimitReached(int count) {
    return 'Du kannst bis zu $count Ansichten speichern';
  }

  @override
  String get overviewViewSearchHint => 'Gespeicherte Ansichten suchen';

  @override
  String get overviewViewNoMatches =>
      'Keine gespeicherte Ansicht passt zur Suche';

  @override
  String get overviewEmptyPeriod => 'Nichts in diesem Zeitraum';

  @override
  String get overviewLoading => 'Weitere werden geladen…';

  @override
  String overviewCapReached(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Die ersten $countString Einträge werden angezeigt. Grenze den Zeitraum ein, um den Rest zu sehen.';
  }

  @override
  String overviewEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Termine',
      one: '1 Termin',
    );
    return '$_temp0';
  }

  @override
  String overviewEventSpan(String first, String last) {
    return '$first – $last';
  }

  @override
  String get overviewScrubberLabel => 'Nach Monat scrollen';

  @override
  String get overviewYearScrubberLabel => 'Nach Jahr scrollen';

  @override
  String get datePickerApply => 'Übernehmen';

  @override
  String get datePickerRangeNone => 'Starttag wählen';

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

  @override
  String get editorZoneToggleTask => 'Aufgabe umschalten';

  @override
  String get editorZoneOpenLink => 'Link öffnen';

  @override
  String get editorZoneOpenMoney => 'Kassenbuchdetails öffnen';

  @override
  String get editorZoneSearchTag => 'Schlagwort suchen';

  @override
  String get editorZoneOpenWikiLink => 'Verknüpfte Notiz öffnen';

  @override
  String editorZoneToggleTaskNamed(String task) {
    return 'Aufgabe umschalten: $task';
  }

  @override
  String editorZoneOpenLinkNamed(String link) {
    return 'Link öffnen: $link';
  }

  @override
  String editorZoneOpenWikiLinkNamed(String note) {
    return 'Verknüpfte Notiz öffnen: $note';
  }

  @override
  String editorZoneSearchTagNamed(String tag) {
    return 'Schlagwort suchen: $tag';
  }

  @override
  String get showAncestors => 'Übergeordnete Ordner anzeigen';

  @override
  String get labelAction => 'Etikett';

  @override
  String get labelSelected => 'Etikett';

  @override
  String get labelNone => 'Kein Etikett';

  @override
  String get labelRed => 'Rot';

  @override
  String get labelOrange => 'Orange';

  @override
  String get labelYellow => 'Gelb';

  @override
  String get labelGreen => 'Grün';

  @override
  String get labelTeal => 'Blaugrün';

  @override
  String get labelBlue => 'Blau';

  @override
  String get labelPink => 'Rosa';

  @override
  String labelSemantics(String color) {
    return 'Etikett $color';
  }

  @override
  String get labelStyle => 'Etikettenstil';

  @override
  String get labelStyleDesc =>
      'Wie eine Notiz oder ein Ordner mit Etikett seine Farbe in der Liste zeigt';

  @override
  String get labelStyleDot => 'Punkt';

  @override
  String get labelStyleStripe => 'Randstreifen';

  @override
  String get labelStyleKeywords =>
      'Farbe, Etikett, Punkt, Streifen, Rand, Markierung';

  @override
  String labelledNotesHeader(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$names · $count Notizen',
      one: '$names · 1 Notiz',
    );
    return '$_temp0';
  }

  @override
  String get alarmPageTitle => 'Alarm';

  @override
  String get alarmTestTitle => 'Testalarm';

  @override
  String get alarmStop => 'Stopp';

  @override
  String alarmSnoozeMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Min. schlummern',
      one: '1 Min. schlummern',
    );
    return '$_temp0';
  }

  @override
  String get alarmOpenEvent => 'Termin öffnen';

  @override
  String get alarmKeep => 'Behalten';

  @override
  String get alarmKeepEvent => 'Termin behalten';

  @override
  String get alarmKeptEvent => 'Der Termin bleibt erhalten';

  @override
  String get alarmRemoveAfterCaption => 'Stopp entfernt auch diesen Termin';

  @override
  String alarmSwitchDatabase(String name) {
    return 'Zu $name wechseln';
  }

  @override
  String alarmDatabaseSwitchedTitle(String name) {
    return 'Zu $name gewechselt';
  }

  @override
  String get alarmDatabaseSwitchedBody =>
      'Beende ANTA und öffne es erneut, um diesen Termin zu sehen. Der Alarm klingelt weiter, bis du ihn stoppst.';

  @override
  String get calendarAlertsSection => 'Erinnerungen';

  @override
  String get alertsNotifications => 'Benachrichtigungen';

  @override
  String get alertsNotificationsDesc =>
      'Nötig, damit Mitteilungen und Alarme erscheinen';

  @override
  String get alertsFullScreenAlarms => 'Vollbild-Alarme';

  @override
  String get alertsFullScreenAlarmsDesc =>
      'Lässt einen Alarm den gesperrten Bildschirm übernehmen';

  @override
  String get alertsBattery => 'Uneingeschränkter Akku';

  @override
  String get alertsBatteryDesc =>
      'Akku-Beschränkungen können einen Alarm verzögern oder verwerfen';

  @override
  String get alertsPermissionOn => 'An';

  @override
  String get alertsPermissionOff => 'Aus';

  @override
  String get alertsTurnOn => 'Aktivieren';

  @override
  String get alertsOpenSettings => 'Einstellungen öffnen';

  @override
  String get alertsSnoozeLength => 'Schlummerdauer';

  @override
  String alertsSnoozeLengthDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Schlummern verschiebt eine Erinnerung um $count Minuten',
      one: 'Schlummern verschiebt eine Erinnerung um 1 Minute',
    );
    return '$_temp0';
  }

  @override
  String get alertsSilenceAfter => 'Stummschalten nach';

  @override
  String alertsSilenceAfterDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ein unbeantworteter Alarm endet nach $count Minuten',
      one: 'Ein unbeantworteter Alarm endet nach 1 Minute',
    );
    return '$_temp0';
  }

  @override
  String get alertsNoticeLead => 'Hinweis vor dem Alarm';

  @override
  String alertsNoticeLeadDesc(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Ein leiser Hinweis $count Minuten vor einem Alarm, mit Überspringen und Öffnen',
      one:
          'Ein leiser Hinweis 1 Minute vor einem Alarm, mit Überspringen und Öffnen',
    );
    return '$_temp0';
  }

  @override
  String get alertsNoticeLeadOff => 'Aus – kein Hinweis vor einem Alarm';

  @override
  String alertsUpcomingTitle(String time) {
    return 'Alarm um $time';
  }

  @override
  String alertsKindWhen(String kind, String when) {
    return '$kind · $when';
  }

  @override
  String alertsWhenOnDay(String when, String day) {
    return '$when, $day';
  }

  @override
  String alertsDayThenWhen(String day, String when) {
    return '$day · $when';
  }

  @override
  String get alertsSkipAction => 'Überspringen';

  @override
  String get alertsOpenAction => 'Öffnen';

  @override
  String get alertsSessionInProgress => 'Einheit läuft';

  @override
  String alertsSessionUntil(String time) {
    return 'Bis $time';
  }

  @override
  String get alertsSessionOpenNote => 'Notiz öffnen';

  @override
  String alertsSkippedSnack(String title) {
    return '$title übersprungen';
  }

  @override
  String get alertsRecent => 'Zuletzt';

  @override
  String get alertsHistoryRemoved => 'Entfernter Termin';

  @override
  String get alertsOutcomeRang => 'Hat geklingelt';

  @override
  String get alertsOutcomeStopped => 'Gestoppt';

  @override
  String get alertsOutcomeSnoozed => 'Geschlummert';

  @override
  String get alertsOutcomeMissed => 'Verpasst';

  @override
  String get alertsOutcomeDelivered => 'Zugestellt';

  @override
  String get alertsForceStopNote =>
      'Ein erzwungenes Beenden von ANTA deaktiviert alle Alarme, bis du die App wieder öffnest.';

  @override
  String get alertsTestAlarm => 'Testalarm in 10 s';

  @override
  String get alertsTestAlarmScheduled => 'Testalarm in 10 Sekunden gesetzt';

  @override
  String get alertsTestAlarmFailed => 'Der Alarm konnte nicht geplant werden';

  @override
  String get alertsReminderChannel => 'Mitteilungen';

  @override
  String get alertsReminderChannelDesc =>
      'Termin-Mitteilungen zum Schlummern oder Schließen';

  @override
  String get alertsAlarmChannel => 'Alarme';

  @override
  String get alertsAlarmChannelDesc =>
      'Termin-Alarme, die bis zum Stoppen klingeln';

  @override
  String get alertsQuietChannel => 'Leise Hinweise';

  @override
  String get alertsQuietChannelDesc =>
      'Hinweise auf anstehende und verpasste Alarme und die laufende Einheit, immer lautlos';

  @override
  String get alertsDigestChannel => 'Zusammenfassungen';

  @override
  String get alertsDigestChannelDesc =>
      'Gebündelte Übersichten anstehender Termine';

  @override
  String get digestAllCategories => 'Termine';

  @override
  String digestCategoriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kategorien',
      one: '1 Kategorie',
    );
    return '$_temp0';
  }

  @override
  String digestCountPeriod(int count, String period) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Termine $period',
      one: '1 Termin $period',
      zero: 'Keine Termine $period',
    );
    return '$_temp0';
  }

  @override
  String get digestPeriodToday => 'heute';

  @override
  String get digestPeriodTomorrow => 'morgen';

  @override
  String get digestPeriodThisWeek => 'in dieser Woche';

  @override
  String get digestPeriodNextWeek => 'in der nächsten Woche';

  @override
  String get digestPeriodThisMonth => 'in diesem Monat';

  @override
  String get digestPeriodNextMonth => 'im nächsten Monat';

  @override
  String digestPeriodSpan(String start, String end) {
    return 'vom $start bis $end';
  }

  @override
  String digestMoreCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count weitere',
      one: '+1 weiterer',
    );
    return '$_temp0';
  }

  @override
  String get digestsAdd => 'Zusammenfassung hinzufügen';

  @override
  String get digestNew => 'Neue Zusammenfassung';

  @override
  String get digestEdit => 'Zusammenfassung bearbeiten';

  @override
  String get digestShows => 'Zeigt';

  @override
  String get digestShowsUpcoming => 'Bevorstehendes';

  @override
  String get digestShowsWeekReport => 'Die abgelaufene Woche';

  @override
  String get digestShowsMonthReport => 'Der abgelaufene Monat';

  @override
  String get digestEvery => 'Rhythmus';

  @override
  String get digestOn => 'Am';

  @override
  String digestOnDayOfMonth(String day) {
    String _temp0 = intl.Intl.selectLogic(day, {'other': '$day.'});
    return '$_temp0';
  }

  @override
  String get digestAt => 'Um';

  @override
  String get digestCovers => 'Umfasst';

  @override
  String get digestCoversSameDay => 'Ab diesem Tag';

  @override
  String get digestCoversNextDay => 'Ab dem nächsten Tag';

  @override
  String get digestIncludeEmpty => 'Auch wenn leer';

  @override
  String get digestIncludeEmptyDesc => 'Auch senden, wenn nichts ansteht';

  @override
  String digestNext(String when, String count) {
    return 'Nächste: $when · $count';
  }

  @override
  String get digestNextNone => 'Noch nichts zu senden';

  @override
  String get digestUnreadable =>
      'Mit einer neueren Version der App gespeichert';

  @override
  String digestNextFire(String when) {
    return 'nächste $when';
  }

  @override
  String digestOverLimit(int count) {
    return 'nicht aktiv, höchstens $count Zusammenfassungen';
  }

  @override
  String get digestDelete => 'Zusammenfassung löschen';

  @override
  String get digestDeleteConfirm => 'Diese Zusammenfassung löschen?';

  @override
  String digestLimitReached(int count) {
    return 'Du kannst bis zu $count Zusammenfassungen behalten';
  }

  @override
  String digestDescribeDaily(String time) {
    return 'Täglich um $time';
  }

  @override
  String digestDescribeWeekly(String weekday, String time) {
    return 'Wöchentlich am $weekday, $time';
  }

  @override
  String digestDescribeMonthly(String day, String time) {
    return 'Monatlich am $day, $time';
  }

  @override
  String digestDescribeWeeklyReport(String weekday, String time) {
    return 'Wochenbericht am $weekday, $time';
  }

  @override
  String digestDescribeMonthlyReport(String day, String time) {
    return 'Monatsbericht am $day, $time';
  }

  @override
  String get digestReportWeeklyTitle => 'Wochenbericht';

  @override
  String get digestReportMonthlyTitle => 'Monatsbericht';

  @override
  String get digestPeriodLastWeek => 'in der letzten Woche';

  @override
  String get digestPeriodLastMonth => 'im letzten Monat';

  @override
  String get digestReportReadyWeek =>
      'Der Bericht der letzten Woche ist fertig';

  @override
  String get digestReportReadyMonth =>
      'Der Bericht des letzten Monats ist fertig';

  @override
  String digestReportSummary(String categories, String facts) {
    return '$categories — $facts';
  }

  @override
  String get alertsDoneAction => 'Erledigt';

  @override
  String get eventAlerts => 'Erinnerungen';

  @override
  String get eventAlertAdd => 'Erinnerung hinzufügen';

  @override
  String get eventAlertRemove => 'Erinnerung entfernen';

  @override
  String get eventAlertRemoveAfter => 'Nach dem Klingeln entfernen';

  @override
  String get eventAlertRemoveAfterHint =>
      'Der Termin wird gelöscht, sobald du den Alarm stoppst. Rückgängig geht direkt danach.';

  @override
  String get eventAlert => 'Erinnerung';

  @override
  String get eventAlertTypeSection => 'Art';

  @override
  String get eventAlertModeNotify => 'Mitteilung';

  @override
  String get eventAlertModeRing => 'Alarm';

  @override
  String get eventAlertNotifyHint =>
      'Liegt in der Leiste, mit Schlummern und Erledigt. Lautlos und Fokus gelten.';

  @override
  String get eventAlertRingHint =>
      'Spielt über den Weckton, bis du stoppst oder schlummerst.';

  @override
  String get eventAlertFullScreenOff =>
      'Vollbild-Alarme sind aus, daher klingelt dies als Banner statt bildschirmfüllend.';

  @override
  String get eventAlertWhenSection => 'Wann';

  @override
  String get eventAlertCustom => 'Eigene';

  @override
  String get eventAlertCustomItem => 'Eigene…';

  @override
  String get eventAlertUnitMinutes => 'Minuten';

  @override
  String get eventAlertUnitHours => 'Stunden';

  @override
  String get eventAlertUnitDays => 'Tage';

  @override
  String get eventAlertOffsetDecrement => 'Weniger Vorlauf';

  @override
  String get eventAlertOffsetIncrement => 'Mehr Vorlauf';

  @override
  String get eventAlertOnTheDay => 'Am Tag selbst';

  @override
  String get eventAlertTheDayBefore => 'Am Vortag';

  @override
  String get eventAlertAWeekBefore => 'Eine Woche vorher';

  @override
  String get eventAlertTimeOfDay => 'Uhrzeit';

  @override
  String eventAlertNext(String time) {
    return 'Nächste $time';
  }

  @override
  String eventAlertFromCategory(String category) {
    return 'Aus $category';
  }

  @override
  String get eventCategoryAlerts => 'Kategorie-Erinnerungen';

  @override
  String eventCategoryAlertsDesc(String category) {
    return 'Die Erinnerungen von $category verwenden';
  }

  @override
  String get categoryAlertsHint =>
      'Jeder Termin in dieser Kategorie erhält diese Erinnerungen.';

  @override
  String categoryAlertTimedCaption(String when) {
    return 'Termine mit Uhrzeit: $when';
  }

  @override
  String get categoryHasAlerts => 'Hat Erinnerungen';

  @override
  String eventAlertCountdown(String kind, String duration) {
    return '$kind in $duration';
  }

  @override
  String eventAlertCountdownDays(int count, String kind) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$kind in $count Tagen',
      one: '$kind in 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String eventAlertCountdownDaysHours(int days, String kind, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$kind in $days Tagen $hours Std.',
      one: '$kind in 1 Tag $hours Std.',
    );
    return '$_temp0';
  }

  @override
  String get eventRemovedAfterAlert => 'wird nach dem Klingeln entfernt';

  @override
  String get eventAlertEventRemoved => 'Termin entfernt';

  @override
  String get alertsDefaultTimed => 'Termine mit Uhrzeit';

  @override
  String get alertsDefaultTimedDesc =>
      'Die Erinnerung, mit der ein neuer Termin mit Uhrzeit startet';

  @override
  String get alertsDefaultAllDay => 'Ganztägige Termine';

  @override
  String get alertsDefaultAllDayDesc =>
      'Die Erinnerung, mit der ein neuer ganztägiger Termin startet';

  @override
  String get alertsDefaultNone => 'Keine Erinnerung';

  @override
  String get alertsSound => 'Weckton';

  @override
  String get alertsSoundDesc =>
      'Was ein Alarm spielt, wenn die Erinnerung keinen Ton nennt';

  @override
  String get alertSoundUseAppSetting => 'App-Einstellung verwenden';

  @override
  String get alertSoundPhoneDefault => 'Standard-Weckton des Telefons';

  @override
  String get alertSoundChooseFromPhone => 'Vom Telefon wählen';

  @override
  String get alertSoundFromPhone => 'Ton vom Telefon';

  @override
  String get alertSoundUnavailable =>
      'Nicht auf diesem Telefon – es spielt der Standard-Weckton';

  @override
  String get alertSoundPickerUnavailable =>
      'Dieses Telefon hat keine Tonauswahl';

  @override
  String get alertsTitle => 'Erinnerungen';

  @override
  String get alertsRowDesc => 'Anstehende Mitteilungen und Alarme';

  @override
  String get alertsEmpty => 'Keine anstehenden Erinnerungen';

  @override
  String get alertsEmptyDesc =>
      'Füge einem Termin eine Mitteilung oder einen Alarm hinzu, dann erscheint er hier.';

  @override
  String get alertsNotificationsOffBanner =>
      'Benachrichtigungen sind aus. Mitteilungen erscheinen nicht, und ein Alarm klingelt, ohne den Bildschirm zu wecken.';

  @override
  String get alertsFullScreenOffBanner =>
      'Vollbild-Alarme sind aus. Auf dem gesperrten Telefon erscheinen Alarme als Banner.';

  @override
  String alertsSnoozedRow(String alert) {
    return 'Schlummert · $alert';
  }

  @override
  String get alertsCancelSnooze => 'Schlummern abbrechen';

  @override
  String alertsToggleLabel(String title) {
    return 'Erinnerung für $title';
  }

  @override
  String get alertsCancelAlarm => 'Alarm abbrechen';

  @override
  String alertsCancelAlarmConfirm(String title) {
    return '„$title“ wird nach dem Klingeln entfernt, daher entfernt das Abbrechen des Alarms den Termin.';
  }

  @override
  String get permissionsTitle => 'Berechtigungen';

  @override
  String get permissionsRowDesc => 'Was ANTA auf diesem Gerät darf';

  @override
  String permissionsRowAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Berechtigungen sind aus',
      one: '1 Berechtigung ist aus',
    );
    return '$_temp0';
  }

  @override
  String get settingsHubTitle => 'Einstellungen';

  @override
  String get settingsHubRowDesc => 'Alles, was du ändern kannst';

  @override
  String get howToUseAnta => 'So nutzt du ANTA';

  @override
  String get calendarReportRowDesc => 'Wie eine Woche oder ein Monat lief';

  @override
  String get settingsHubSearchHint => 'Einstellungen suchen';

  @override
  String get settingsSectionCalendar => 'Kalender';

  @override
  String get settingsSectionNotes => 'Notizen';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionHowTo => 'Anleitungen';

  @override
  String get settingsRowCalendarDesc => 'Feiertage, Filterung, Ereignisse';

  @override
  String get settingsRowAppearanceDesc =>
      'Wochenbeginn, Zellen, Markierungen, Farben';

  @override
  String get calendarCategoriesRowDesc => 'Erstellen, ordnen, archivieren';

  @override
  String get settingsRowEditor => 'Editor und Markdown';

  @override
  String get settingsRowEditorDesc =>
      'Kurzbefehle, Symbolleiste, Farben, Wortlisten, Geld';

  @override
  String get settingsRowCountersDesc =>
      'Angeheftete Zähler und Zähler pro Notiz';

  @override
  String get settingsRowGeneral => 'Allgemein';

  @override
  String get settingsRowGeneralDesc =>
      'Start, Navigation, Editor, automatisches Speichern';

  @override
  String get settingsRowTheme => 'Design';

  @override
  String get settingsRowDatabases => 'Datenbanken und Sicherung';

  @override
  String get settingsRowDatabasesDesc =>
      'Wechseln, exportieren, importieren, löschen';

  @override
  String get settingsRowSharingDesc => 'Konto und gekoppelte Geräte';

  @override
  String get permissionsCalendarRowDesc =>
      'Benachrichtigungen, genaue Zeit, Vollbild-Alarme, Akku';

  @override
  String get permissionsAllSet => 'Alles bereit';

  @override
  String get permissionsAllSetBody =>
      'ANTA hat auf diesem Gerät alles, was es braucht.';

  @override
  String get permissionsAttentionTitle =>
      'Alarme und Mitteilungen funktionieren noch nicht';

  @override
  String get permissionsEssentialsOk => 'Alles Notwendige ist erlaubt';

  @override
  String get permissionsRecommendedBody =>
      'Die empfohlenen machen Alarme zuverlässiger.';

  @override
  String get permissionsEssentialSection => 'Notwendig';

  @override
  String get permissionsRecommendedSection => 'Empfohlen';

  @override
  String get permissionsOptionsSection => 'Optionen';

  @override
  String get permissionExactAlarms => 'Wecker & Erinnerungen';

  @override
  String get permissionExactAlarmsDesc =>
      'Lässt Erinnerungen genau zur eingestellten Zeit auslösen';

  @override
  String get permissionsLaunchCheck => 'Beim Start prüfen';

  @override
  String get permissionsLaunchCheckDesc =>
      'Einmal nachfragen, wenn etwas Notwendiges aus ist';

  @override
  String get permissionsSystemSettings => 'Systemeinstellungen';

  @override
  String get permissionsSystemSettingsDesc =>
      'ANTA in den Systemeinstellungen öffnen';

  @override
  String get permissionsNoneNeeded => 'Nichts zu erlauben';

  @override
  String get permissionsNoneNeededDesc =>
      'ANTA braucht auf diesem Gerät keine Systemberechtigungen. Alarme und Mitteilungen klingeln vorerst nur auf Android.';

  @override
  String get permissionsPromptTitle => 'ANTA braucht deine Erlaubnis';

  @override
  String get permissionsPromptBody =>
      'Ohne sie bleiben Alarme und Mitteilungen stumm.';

  @override
  String get permissionsPromptContinue => 'Weiter';

  @override
  String get permissionsPromptNotNow => 'Nicht jetzt';

  @override
  String get permissionsSettingsUnavailable =>
      'Die Systemeinstellungen ließen sich nicht öffnen';

  @override
  String get permissionsAlertBlocked =>
      'Das kann erst klingeln, wenn eine Berechtigung an ist';

  @override
  String get permissionsReview => 'Prüfen';

  @override
  String get alertsExactAlarmsOffBanner =>
      'Der Zugriff auf Wecker & Erinnerungen ist aus. Erinnerungen lassen sich nicht auf die genaue Zeit stellen.';

  @override
  String get permissionsUnknownTitle =>
      'Berechtigungen ließen sich nicht prüfen';

  @override
  String get permissionsUnknownBody =>
      'Öffne die Systemeinstellungen, um sie zu sehen.';

  @override
  String permissionsPromptRecommended(String description) {
    return 'Empfohlen · $description';
  }

  @override
  String get timePadDone => 'Fertig';

  @override
  String get timePadOnTheHour => 'Zur vollen Stunde';

  @override
  String get timePadHalfPast => 'Zur halben Stunde';

  @override
  String timePadChoosePeriod(String am, String pm) {
    return '$am oder $pm?';
  }

  @override
  String timePadEndsAt(String time) {
    return 'Endet um $time';
  }

  @override
  String timePadEndsNextDayAt(String time) {
    return 'Endet am nächsten Tag um $time';
  }

  @override
  String timePadAfterStart(String duration, String time) {
    return '$duration nach $time';
  }

  @override
  String eventDurationMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String eventDurationHours(int hours) {
    return '$hours Std.';
  }

  @override
  String eventDurationHoursMinutes(int hours, int minutes) {
    return '$hours Std. $minutes Min.';
  }

  @override
  String get quickAlarmTime => 'Weckzeit';

  @override
  String get eventCategory => 'Kategorie';

  @override
  String get eventDateLabel => 'Datum';

  @override
  String get eventStarts => 'Beginn';

  @override
  String get eventEnds => 'Ende';

  @override
  String get eventEndTimeRemove => 'Endzeit entfernen';

  @override
  String get eventRepeat => 'Wiederholung';

  @override
  String get recurrenceDoesNotRepeat => 'Wiederholt sich nicht';

  @override
  String get recurrenceEnds => 'Endet';

  @override
  String get never => 'Nie';

  @override
  String get recurrenceEndDateRemove => 'Enddatum entfernen';

  @override
  String get recurrenceBeforeStart => 'Auch vor dem Startdatum';

  @override
  String recurrenceBeforeStartHint(String date) {
    return 'Erscheint an passenden Tagen vor dem $date';
  }

  @override
  String get recurrenceBeforeStartYearlyHint => 'Auch in früheren Jahren';

  @override
  String get recurrenceBeforeStartTemplateHint =>
      'Auch an passenden Tagen vor dem Tag des Hinzufügens';

  @override
  String recurrenceUntilSuffix(String rule, String date) {
    return '$rule · bis $date';
  }

  @override
  String get eventLookDefault => 'Standard';

  @override
  String get eventLookCustom => 'Angepasst';

  @override
  String get eventLinkedNoteNone => 'Keine';

  @override
  String get eventLinkedNoteNotFound => 'Nicht gefunden';

  @override
  String get eventDescriptionResetDayShort => 'Tag zurücksetzen';

  @override
  String eventTitleCount(int count, int limit) {
    return '$count/$limit';
  }

  @override
  String get eventDatesLabel => 'Termine';

  @override
  String eventDatesSummary(String count, String range) {
    return '$count · $range';
  }

  @override
  String get datePickerListEmpty =>
      'Noch keine Daten. Wähle sie in Monat oder Jahr.';

  @override
  String datePickerListIndex(int index, int count) {
    return '$index von $count';
  }

  @override
  String get datePickerPreviousYear => 'Vorheriges Jahr';

  @override
  String get datePickerNextYear => 'Nächstes Jahr';

  @override
  String get datePickerRepeatPicked => 'Gewählte Daten wiederholen…';

  @override
  String get datePickerRepeatTimes => 'Wie oft';

  @override
  String get datePickerRepeatWeek => 'Woche';

  @override
  String get datePickerRepeatMonth => 'Monat';

  @override
  String get datePickerRepeatYear => 'Jahr';

  @override
  String datePickerRepeatTimesValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Male',
      one: '1 weiteres Mal',
    );
    return '$_temp0';
  }

  @override
  String get datePickerRepeatFewer => 'Weniger';

  @override
  String get datePickerRepeatMore => 'Mehr';

  @override
  String datePickerRepeatAdds(int count, String last) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fügt $count Daten hinzu',
      one: 'Fügt 1 Datum hinzu',
    );
    return '$_temp0 · bis $last';
  }

  @override
  String datePickerRepeatSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count übersprungen, Tag existiert nicht',
      one: '1 übersprungen, Tag existiert nicht',
    );
    return '$_temp0';
  }

  @override
  String get datePickerRepeatNothing => 'Nichts hinzuzufügen';

  @override
  String datePickerRepeatApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Daten hinzufügen',
      one: '1 Datum hinzufügen',
      zero: 'Daten hinzufügen',
    );
    return '$_temp0';
  }

  @override
  String eventDatesNext(String date) {
    return 'Nächstes $date';
  }

  @override
  String eventDatesAhead(int ahead, int total) {
    return '$ahead von $total bevorstehend';
  }

  @override
  String get eventDatesAllPast => 'Alle vergangen';

  @override
  String get calendarGuideTitle => 'So funktioniert der Kalender';

  @override
  String get calendarGuideSearchHint => 'Im Leitfaden suchen';

  @override
  String get calendarGuideIntro =>
      'Tippe auf eine Seite. Nichts dort ist echt.';

  @override
  String get calendarGuideSectionCalendar => 'Der Kalender';

  @override
  String get calendarGuideMarksTitle => 'Die farbigen Balken unter einem Tag';

  @override
  String get calendarGuideMarksBody =>
      'Ein Balken unter einem Tag bedeutet, dass dort etwas geplant ist – in der Farbe seiner Kategorie. Feiertage und Wochenenden haben eigene Balken.';

  @override
  String get calendarGuideViewsTitle => 'Monat, zwei Wochen oder eine Woche';

  @override
  String calendarGuideViewsBody(String month) {
    return 'Wenn die Tage auf ein oder zwei Reihen schrumpfen, wurde im Titelmenü umgeschaltet: Wähle dort wieder „$month“.';
  }

  @override
  String get calendarGuideCategoryTitle => 'Kategorien';

  @override
  String calendarGuideCategoryBody(String category) {
    return 'Jedes Ereignis hat eine Kategorie – die Zeile „$category“ unter seinem Namen –, die ihm Farbe und Symbol gibt. Eigene legst du ganz unten in dieser Liste an.';
  }

  @override
  String get calendarGuideDescriptionTitle => 'Notizen zu einem Ereignis';

  @override
  String get calendarGuideDescriptionBody =>
      'Unter dem Namen ist Platz für eine Adresse, eine Telefonnummer, was mitzubringen ist. Das alles siehst du, wenn du das Ereignis öffnest.';

  @override
  String calendarGuideUnsavedTitle(String save) {
    return 'Gespeichert wird erst mit „$save“';
  }

  @override
  String get calendarGuideUnsavedBody =>
      'Wenn du ein Ereignis schließt, das du gerade änderst, fragt die App, ob du weiter bearbeiten oder verwerfen willst. Ein gespeichertes Ereignis bleibt auf dem Telefon – ganz ohne Internet.';

  @override
  String get calendarGuideTemplatesTitle => 'Vorlagen';

  @override
  String calendarGuideTemplatesBody(String saveAsTemplate) {
    return 'Ein Ereignis, das du oft anlegst, kannst du ganz unten im Editor mit „$saveAsTemplate“ speichern. Halte + gedrückt, um es zu verwenden.';
  }

  @override
  String get calendarGuideAlertKindsTitle => 'Mitteilung oder Alarm';

  @override
  String calendarGuideAlertKindsBody(
    String reminder,
    String alarm,
    String allDay,
  ) {
    return '„$reminder“: eine Benachrichtigung, die du wegwischen oder schlummern lassen kannst. „$alarm“: klingelt, bis du ihn stoppst, auch bei gesperrtem Telefon; damit er Minuten vorher losgeht, braucht das Ereignis eine Startzeit – schalte „$allDay“ aus.';
  }

  @override
  String get calendarGuidePermissionsTitle =>
      'Dem Telefon das Klingeln erlauben';

  @override
  String calendarGuidePermissionsBody(
    String battery,
    String settings,
    String permissions,
  ) {
    return 'Beim ersten Mal bittet ANTA darum, Benachrichtigungen zu zeigen und Alarme zu stellen: Erlaube beides, sonst klingelt nichts. Auf einem Samsung-Telefon schalte auch „$battery“ ein; bleibt später etwas stumm, zeigt „$settings“ im Hauptmenü, dann „$permissions“, was fehlt.';
  }

  @override
  String get calendarGuideRingTitle => 'Wenn es klingelt';

  @override
  String calendarGuideRingBody(String done, String snooze, String stop) {
    return 'Eine Mitteilung erscheint als Benachrichtigung mit „$done“ und „$snooze“. Ein Alarm füllt den Bildschirm mit „$stop“ und „$snooze“ und verstummt von selbst, wenn niemand antwortet.';
  }

  @override
  String get calendarGuideOpenOftenTitle => 'ANTA ab und zu öffnen';

  @override
  String get calendarGuideOpenOftenBody =>
      'ANTA bereitet die nächsten Erinnerungen jedes Mal vor, wenn du es öffnest – etwa zehn von jeder. Öffne die App etwa einmal pro Woche, und sie gehen nie aus.';

  @override
  String get calendarGuideOverviewTitle => 'Die Übersicht';

  @override
  String calendarGuideOverviewBody(String overview, String year, String list) {
    return '„$overview“ im Titelmenü zeigt die Monate als Kacheln („$year“) oder alles aus einem Zeitraum als eine Liste („$list“). Der Pfeil oben links bringt dich zurück.';
  }

  @override
  String get calendarGuideFiltersTitle =>
      'Filter verstecken, sie löschen nichts';

  @override
  String calendarGuideFiltersBody(String reset, String apply) {
    return 'Ein Filter versteckt, er löscht nie. Scheinen Ereignisse zu fehlen, öffne den Trichter und tippe auf „$reset“ und dann auf „$apply“.';
  }

  @override
  String get calendarGuideSettingsTitle => 'Wo die Einstellungen sind';

  @override
  String calendarGuideSettingsBody(String settingsRow, String save) {
    return 'Tippe oben rechts auf die drei Punkte und dann auf „$settingsRow“. Alles dort gilt sofort – es gibt keine Taste „$save“.';
  }

  @override
  String get calendarGuideLanguageTitle =>
      'Sprache, dunkles Design und Schriftgröße';

  @override
  String calendarGuideLanguageBody(
    String settings,
    String language,
    String theme,
  ) {
    return 'Im Hauptmenü (drei Striche, oben links) „$settings“ öffnen: „$language“ wechselt die Sprache und „$theme“ wählt hell oder dunkel. Die Schriftgröße folgt der deines Telefons.';
  }

  @override
  String get calendarGuideSectionGood => 'Gut zu wissen';

  @override
  String get calendarGuideOpeningTitle => 'Den Kalender öffnen';

  @override
  String calendarGuideOpeningBody(String calendar, String title) {
    return 'Tippe auf dem Startbildschirm der App oben links auf die Menütaste und dann auf „$calendar“. Zurück hierher: die drei Punkte im Kalender, dann „$title“.';
  }

  @override
  String get calendarGuideBackTitle => 'Zurück';

  @override
  String get calendarGuideBackBody =>
      'Der Pfeil oben links oder die Zurück-Geste deines Telefons bringt dich zum vorigen Bildschirm. Ein Blatt, das von unten hochkam, schließt sich mit seinem X oder durch Herunterwischen.';

  @override
  String get calendarGuideNotesTitle => 'Der Rest von ANTA';

  @override
  String calendarGuideNotesBody(String linkedNote) {
    return 'ANTA ist auch ein Notizbuch: die Ordner und Notizen hinter dem Hauptmenü. Ein Ereignis kann über „$linkedNote“ auf eine Notiz verweisen.';
  }

  @override
  String get calendarGuideAssumeTitle =>
      'Anwesend, solange du nichts anderes sagst';

  @override
  String calendarGuideAssumeBody(
    String trackPresence,
    String present,
    String missed,
    String assumeAbsent,
  ) {
    return 'Mit „$trackPresence“ gilt jeder Tag als „$present“, bis du ihn als „$missed“ markierst. „$assumeAbsent“ dreht das um – für Dinge, die du selten schaffst.';
  }

  @override
  String calendarGuideRailTitle(String dayRail) {
    return 'Was „$dayRail“ ist';
  }

  @override
  String calendarGuideRailBody(
    String dayRail,
    String settingsRow,
    String appearance,
    String railAuto,
    String railAlways,
    String railNever,
  ) {
    return '„$dayRail“ ist ein schmaler Streifen am linken Rand eines Tages mit einer Marke je erfasstem Ereignis. Schalte sie in „$settingsRow“ unter „$appearance“ ein; danach kann jedes Ereignis „$railAuto“, „$railAlways“ oder „$railNever“ wählen.';
  }

  @override
  String get calendarGuidePerDayTitle => 'Eine Notiz nur für einen Tag';

  @override
  String calendarGuidePerDayBody(String perDay, String thisDay) {
    return 'Ein wiederholtes Ereignis teilt eine Beschreibung über alle seine Tage. Schalte „$perDay“ ein, und über der Beschreibung schreibt „$thisDay“ nur für diesen Tag.';
  }

  @override
  String calendarGuidePriorityTitle(String priority) {
    return '„$priority“ und Aussehen';
  }

  @override
  String calendarGuidePriorityBody(String priority, String iconColor) {
    return '„$priority“ ordnet einen vollen Tag und entscheidet, welche Ereignisse einen Balken bekommen, wenn es mehr als drei sind. „$iconColor“ gibt einem Ereignis ein eigenes Symbol oder eine eigene Farbe.';
  }

  @override
  String get calendarGuideTryIt => 'Probier es aus';

  @override
  String get calendarGuideHowDoI => 'Wie mache ich …';

  @override
  String get calendarGuidePagePractice => 'Übungskalender: Ereignisse';

  @override
  String get calendarGuidePagePracticeCaption =>
      'Ein Kalender, der nichts speichert. Füge hinzu, ändere und lösche nach Belieben.';

  @override
  String get calendarGuidePagePracticeFiltering => 'Übungskalender: Filter';

  @override
  String get calendarGuidePagePracticeFilteringCaption =>
      'Derselbe Kalender, voller. Verstecke Dinge mit dem Trichter und hol sie zurück.';

  @override
  String get calendarGuidePageScreenCaption =>
      'Der Monat, die Balken, der Bereich darunter, die Menüs';

  @override
  String get calendarGuidePageEvents =>
      'Ein Ereignis hinzufügen, ändern oder löschen';

  @override
  String get calendarGuidePageEventsCaption =>
      'Der Editor, Speichern, Löschen, Vorlagen';

  @override
  String get calendarGuidePageKinds => 'Einmalige und wiederholte Ereignisse';

  @override
  String get calendarGuidePageKindsCaption =>
      'Wie sich die beiden Arten unterscheiden, und ihre Eigenheiten';

  @override
  String get calendarGuidePageAlerts => 'Erinnert werden';

  @override
  String get calendarGuidePageAlertsCaption =>
      'Mitteilungen, Alarme, Berechtigungen, der schnelle Alarm';

  @override
  String get calendarGuidePageAttendance => 'Anwesenheit festhalten';

  @override
  String calendarGuidePageAttendanceCaption(
    String present,
    String missed,
    String dayRail,
  ) {
    return '„$present“ oder „$missed“, Zählen, „$dayRail“, eine Notiz pro Tag';
  }

  @override
  String get calendarGuidePageCategories => 'Kategorien nutzen';

  @override
  String get calendarGuidePageCategoriesCaption =>
      'Was sie sind; anlegen, ändern, verstecken, löschen';

  @override
  String get calendarGuidePageFinding => 'Ein Ereignis finden';

  @override
  String calendarGuidePageFindingCaption(String overview) {
    return 'Suche, Filter, „$overview“';
  }

  @override
  String get calendarGuidePageSetup => 'Den Kalender einrichten';

  @override
  String get calendarGuidePageSetupCaption =>
      'Feiertage, der erste Wochentag, Sprache und dunkles Design';

  @override
  String get calendarGuidePageGoodCaption =>
      'Den Kalender öffnen, zurück, der Rest von ANTA';

  @override
  String get calendarGuideStartHere => 'Zum Einstieg';

  @override
  String get calendarGuideHowItWorks => 'So geht’s';

  @override
  String get calendarGuideScreenLead =>
      'Was du siehst, wenn der Kalender öffnet, und wofür jeder Teil da ist.';

  @override
  String get calendarGuideEventsLead =>
      'Ein Ereignis ist alles, was einen Tag hat: ein Termin, eine Rechnung, ein Kurs.';

  @override
  String get calendarGuideKindsLead =>
      'Die meisten Ereignisse passieren einmal; manche kommen jede Woche oder jeden Monat wieder.';

  @override
  String get calendarGuideAlertsLead =>
      'Nichts klingelt von allein: Du fügst eine Mitteilung oder einen Alarm hinzu, wo du sie brauchst.';

  @override
  String get calendarGuideAttendanceLead =>
      'Bei einem Kurs oder einer Gewohnheit kann der Kalender die Tage zählen, an denen du es geschafft hast.';

  @override
  String get calendarGuideCategoriesLead =>
      'Eine Kategorie gibt einem Ereignis Farbe und Symbol.';

  @override
  String get calendarGuideFindingLead =>
      'Nach dem Namen suchen, ausblenden, was du nicht brauchst, oder ein ganzes Jahr betrachten.';

  @override
  String get calendarGuideSetupLead =>
      'Wessen Feiertage, welcher Tag die Woche beginnt, Sprache und Aussehen.';

  @override
  String get calendarGuideKindsOnlyRepeatTitle =>
      'Was nur ein wiederholtes Ereignis kann';

  @override
  String calendarGuideKindsOnlyRepeatBody(
    String trackPresence,
    String countOccurrences,
    String skippedDays,
  ) {
    return '„$trackPresence“, „$countOccurrences“ und eine Notiz pro Tag erscheinen, sobald ein Ereignis mehr als einen Tag hat. „$skippedDays“ im Editor listet die ausgelassenen Tage; nimm bei einem den Haken weg, um ihn zurückzuholen.';
  }

  @override
  String get calendarGuideKindsOneChangeTitle => 'Eine Änderung, alle Tage';

  @override
  String get calendarGuideKindsOneChangeBody =>
      'Wer ein wiederholtes Ereignis bearbeitet, ändert alle seine Tage: Eine neue Uhrzeit verschiebt jede Sitzung. Um einen Tag zu ändern, lass ihn aus und lege dort ein einmaliges Ereignis an.';

  @override
  String get calendarGuideKindsTrickyTitle => 'Wo Wiederholung tückisch wird';

  @override
  String calendarGuideKindsTrickyBody(String ends, String repeat) {
    return 'Ein monatliches Ereignis am 31. überspringt die Monate ohne 31.; ein jährliches am 29. Februar erscheint nur in Schaltjahren. „$ends“ in „$repeat“ beendet eine Regel nach einem Datum.';
  }

  @override
  String get calendarGuideKindsBirthdayTitle => 'Geburtstage';

  @override
  String calendarGuideKindsBirthdayBody(String birthday) {
    return 'Die Kategorie „$birthday“ macht ein neues Ereignis jährlich und zählt ab 0: Setze das echte Geburtsdatum, und das Ereignis zeigt das Alter der Person.';
  }

  @override
  String get calendarGuideCatChangeTitle => 'Eine ändern';

  @override
  String get calendarGuideCatChangeBody =>
      'Tippe in der Liste auf eine Kategorie, um Symbol oder Farbe zu ändern. Die mitgelieferten behalten ihren Namen; deine eigenen kannst du umbenennen.';

  @override
  String get calendarGuideCatAlertsTitle =>
      'Eine Erinnerung für eine ganze Kategorie';

  @override
  String calendarGuideCatAlertsBody(String addAlert, String categoryAlerts) {
    return 'In einer Kategorie legt „$addAlert“ eine Erinnerung fest, die jedes Ereignis darin automatisch bekommt. Ein Ereignis kann das für sich mit „$categoryAlerts“ abschalten.';
  }

  @override
  String calendarGuideWouldOpen(String what) {
    return 'Im echten Kalender würde das „$what“ öffnen.';
  }

  @override
  String get calendarGuideWouldShare =>
      'Im echten Kalender würde das eine Datei mit allen Ereignissen teilen.';

  @override
  String get calendarGuideYouAreHere =>
      'Das ist dieser Leitfaden – du bist schon drin.';

  @override
  String calendarGuideDemoSkipped(String date, String title) {
    return '$date für „$title“ ausgelassen; die anderen Tage bleiben.';
  }

  @override
  String get calendarGuideDemoReset => 'Von vorn';

  @override
  String get calendarGuideShowAlarm => 'Zeig mir den Alarmbildschirm';

  @override
  String calendarGuideDemoHereOnly(String message) {
    return '$message – nur hier.';
  }

  @override
  String calendarGuideDemoHolidays(int count, String year) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Feiertage im Jahr $year',
      one: 'Ein Feiertag im Jahr $year',
    );
    return '$_temp0';
  }

  @override
  String calendarGuideOpenPermissions(String permissions) {
    return '„$permissions“ öffnen';
  }

  @override
  String calendarGuideOpenSettings(String settingsRow) {
    return '„$settingsRow“ öffnen';
  }

  @override
  String get calendarGuidePracticeBanner => 'Hier wird nichts gespeichert.';

  @override
  String get calendarGuideCoachDone =>
      'Fertig. Nichts hier war echt. Probiere, was du willst, oder geh weiter.';

  @override
  String get calendarGuideSkipStep => 'Diesen Schritt überspringen';

  @override
  String calendarGuideCoachScreenTitle(String calendar) {
    return 'Tippe oben auf „$calendar“: dieser Titel ist ein Menü mit Ansichten.';
  }

  @override
  String get calendarGuideCoachScreenMore =>
      'Tippe jetzt oben rechts auf die drei Punkte: das Menü des Kalenders.';

  @override
  String calendarGuideCoachScreenPanel(
    String day,
    String timeline,
    String upcoming,
  ) {
    return 'Wechsle den Bereich unten: „$day“, „$timeline“, „$upcoming“.';
  }

  @override
  String get calendarGuideCardGrid => 'Das Monatsraster';

  @override
  String get calendarGuideCardPanel => 'Der Bereich darunter';

  @override
  String get calendarGuideCardOverview => 'Die Übersicht';

  @override
  String calendarGuideCoachOverviewMode(
    String year,
    String month,
    String list,
  ) {
    return 'Tippe auf „$year“, „$month“ oder „$list“: drei Arten, dieselben Ereignisse zu sehen.';
  }

  @override
  String get calendarGuideCoachOverviewPeriod =>
      'Die Pfeile blättern vor und zurück; die Taste dazwischen führt zu heute zurück.';

  @override
  String calendarGuideCoachEventsAdd(String save) {
    return 'Tippe auf +, um ein Ereignis hinzuzufügen. Gib ihm einen Namen und tippe auf „$save“.';
  }

  @override
  String get calendarGuideCoachEventsOpen =>
      'Ein Ereignis öffnest du, indem du es in der Liste unten antippst.';

  @override
  String calendarGuideCoachEventsChange(String edit, String save) {
    return 'Öffne es, tippe oben rechts auf „$edit“, ändere den Namen, dann „$save“.';
  }

  @override
  String calendarGuideCoachEventsDelete(String edit, String deleteEvent) {
    return 'Zum Löschen: öffne es, „$edit“, dann unten „$deleteEvent“.';
  }

  @override
  String calendarGuideCoachKindsRepeat(
    String repeat,
    String weekly,
    String done,
  ) {
    return 'Tippe auf „$repeat“, wähle „$weekly“, dann „$done“.';
  }

  @override
  String calendarGuideCoachKindsSkip(String date, String skip) {
    return 'Tippe auf „$date“, wähle einen Tag mit Punkt, dann „$skip“.';
  }

  @override
  String calendarGuideCoachKindsOnce(String repeat, String doesNotRepeat) {
    return 'Tippe noch einmal auf „$repeat“ und wähle „$doesNotRepeat“.';
  }

  @override
  String calendarGuideCoachKindsAddDate(String addDate) {
    return '„$addDate“ gibt einem einmaligen Ereignis einen zweiten Tag. Probier es aus.';
  }

  @override
  String calendarGuideCoachAlertsAdd(String addAlert, String done) {
    return 'Tippe auf „$addAlert“, wähle, wann sie losgehen soll, dann „$done“.';
  }

  @override
  String calendarGuideCoachAlertsShow(String showAlarm) {
    return 'Tippe jetzt auf „$showAlarm“, um zu sehen, wie ein Alarm aussieht.';
  }

  @override
  String get calendarGuideCoachAttendanceMark =>
      'Tippe auf einen Tag unten: er gilt als verpasst. Noch einmal: anwesend.';

  @override
  String calendarGuideCoachAttendanceCount(String countOccurrences) {
    return 'Schalte „$countOccurrences“ ein und wähle, wie gezählt wird.';
  }

  @override
  String calendarGuideCoachCategoriesCreate(
    String createCategory,
    String save,
  ) {
    return 'Tippe auf „$createCategory“: Name, Symbol, Farbe, dann „$save“.';
  }

  @override
  String get calendarGuideCoachCategoriesHide =>
      'Tippe auf das Auge einer Kategorie, um sie zu verstecken; noch einmal zeigt sie wieder.';

  @override
  String calendarGuideCoachCategoriesDelete(String delete, String other) {
    return 'Tippe auf die drei Punkte deiner Kategorie, dann „$delete“: ihre Ereignisse gehen zu „$other“.';
  }

  @override
  String get calendarGuideCoachFindingSearch =>
      'Gib ein Wort, eine Kategorie oder ein Datum ein: die Liste behält nur die Treffer.';

  @override
  String calendarGuideCoachFindingFilter(String apply) {
    return 'Tippe auf den Trichter, verstecke eine Kategorie, dann „$apply“.';
  }

  @override
  String calendarGuideCoachSetupHolidays(String holidaySet) {
    return 'Tippe auf „$holidaySet“ und wähle dein Land.';
  }

  @override
  String calendarGuideCoachSetupWeek(String weekStart) {
    return 'Wähle einen Tag unter „$weekStart“.';
  }

  @override
  String get calendarGuideTourPick =>
      'Tippe auf einen Tag mit einem Balken darunter.';

  @override
  String get calendarGuideTourOpen =>
      'Tippe jetzt im Bereich unten auf das Ereignis, um es zu öffnen.';

  @override
  String calendarGuideTourEdit(String edit, String save) {
    return 'Mit „$edit“ oben rechts kannst du es ändern, dann „$save“.';
  }

  @override
  String get calendarGuideTourAdd =>
      'Tippe auf +, um am gewählten Tag ein Ereignis hinzuzufügen.';

  @override
  String calendarGuideTourFilter(String apply) {
    return 'Der Trichter oben versteckt Kategorien. Probier es, dann „$apply“.';
  }

  @override
  String get calendarGuideTourDone =>
      'Das ist der ganze Kalender. Nichts, was du hier getan hast, wurde gespeichert.';

  @override
  String get calendarGuideDemoEventDentist => 'Zahnarzt';

  @override
  String get calendarGuideDemoEventYoga => 'Yoga';

  @override
  String get calendarGuideDemoEventRent => 'Miete';

  @override
  String get calendarGuideDemoEventBirthday => 'Mamas Geburtstag';

  @override
  String get calendarGuideDemoEventBookClub => 'Lesekreis';

  @override
  String get calendarGuideDemoEventFlight => 'Flug';

  @override
  String get calendarGuideDemoEventFlightNote =>
      'Das Gate öffnet zwei Stunden vorher.';

  @override
  String get calendarGuideTourFilterOpen =>
      'Tippe auf den Trichter oben rechts: Er versteckt, was du nicht brauchst.';

  @override
  String calendarGuideTourFilterCategory(String categories, String apply) {
    return 'Tippe auf „$categories“, wähle eine ab, dann „$apply“.';
  }

  @override
  String calendarGuideTourFilterTrait(String onlyShow, String apply) {
    return 'Öffne den Trichter erneut: Probier „$onlyShow“, dann „$apply“.';
  }

  @override
  String calendarGuideTourFilterReset(String reset, String apply) {
    return 'Tippe im Trichter auf „$reset“, dann „$apply“.';
  }

  @override
  String get calendarGuideTourFilterDone =>
      'Alles ist wieder da. Ein Filter versteckt nur, er löscht nie.';

  @override
  String get calendarGuideDemoEventPilates => 'Pilates';

  @override
  String get calendarGuideDemoEventPiano => 'Klavierstunde';

  @override
  String get calendarGuideDemoEventInsurance => 'Kfz-Versicherung';

  @override
  String get calendarGuideDemoEventTax => 'Steuererklärung';

  @override
  String get calendarGuideDemoEventTaxNote =>
      'Die Unterlagen sind im blauen Ordner.';

  @override
  String get calendarGuideDemoEventLunch => 'Mittagessen mit dem Team';

  @override
  String get calendarGuideDemoEventPlants => 'Blumen gießen';

  @override
  String get calendarGuidePageFasting => 'Fastentage';

  @override
  String get calendarGuidePageFastingCaption =>
      'Orthodoxe, katholische, muslimische oder jüdische Fastentage im Raster und im Tagesbereich';

  @override
  String get calendarGuideFastingLead =>
      'Der Kalender kann die Fastentage deiner Tradition markieren, mit der Regel jedes Tages.';

  @override
  String get calendarGuideCoachFastingTradition =>
      'Wähle unter dem Raster eine Tradition: Ihre Fastentage werden getönt.';

  @override
  String calendarGuideCoachFastingStyle(String appearance) {
    return 'Tippe auf „$appearance“, um sie als Tönung, Balken oder fette Tageszahl zu zeigen.';
  }

  @override
  String calendarGuideCoachFastingPractice(String myPractice) {
    return 'Tippe auf „$myPractice“, um nur die Wochentage zu behalten, an denen du fastest.';
  }

  @override
  String get calendarGuideFastingWhereTitle => 'Wo es eingeschaltet wird';

  @override
  String calendarGuideFastingWhereBody(
    String calendarSettings,
    String fastingSection,
  ) {
    return '„$calendarSettings“ → „$fastingSection“, ein Schalter je Tradition. Mehrere können zugleich an sein, jede mit eigener Darstellung.';
  }

  @override
  String get calendarGuideFastingRulesTitle => 'Was die Zeile sagt';

  @override
  String get calendarGuideFastingRulesBody =>
      'Die Zeile nennt das Fasten und die Regel des Tages: streng, Wein und Öl, Fisch, Milchprodukte oder von der Morgendämmerung bis zum Sonnenuntergang. Die Daten folgen den üblichen gedruckten Kalendern; muslimische Daten können um einen Tag von der Mondsichtung abweichen.';

  @override
  String get calendarGuideFastingPracticeTitle => 'Deine eigene Praxis';

  @override
  String calendarGuideFastingPracticeBody(
    String myPractice,
    String applyTo,
    String allFasts,
  ) {
    return '„$myPractice“ behält nur die Wochentage, an denen du fastest, schaltet ganze Monate aus und überspringt oder ergänzt einzelne Tage. Die langen Fastenzeiten markieren weiter jeden ihrer Tage, außer „$applyTo“ steht auf „$allFasts“.';
  }

  @override
  String get calendarGuideFastingHideTitle => 'Eine Weile ausblenden';

  @override
  String calendarGuideFastingHideBody(String fasting, String apply) {
    return 'Schalte im Trichter „$fasting“ aus und tippe auf „$apply“: Die Fastentage verschwinden aus Raster und Bereich, bis du es wieder einschaltest.';
  }

  @override
  String get reportTitle => 'Bericht';

  @override
  String get reportSectionTotals => 'Summen';

  @override
  String get reportSectionCategories => 'Kategorien';

  @override
  String get reportSectionOverTime => 'Im Zeitverlauf';

  @override
  String get reportSectionMissed => 'Verpasst';

  @override
  String get reportSectionAhead => 'Anstehend';

  @override
  String get reportTileEvents => 'Termine';

  @override
  String get reportTileAttended => 'Anwesend';

  @override
  String get reportTileMissed => 'Verpasst';

  @override
  String get reportTileHours => 'Stunden';

  @override
  String get reportTileTasks => 'Aufgaben';

  @override
  String get reportTilePlanned => 'Geplant';

  @override
  String reportOfTotal(String value, String total) {
    return '$value von $total';
  }

  @override
  String reportTasksOpen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offen',
      one: '1 offen',
    );
    return '$_temp0';
  }

  @override
  String reportPercent(String percent) {
    return '$percent %';
  }

  @override
  String reportPercentSpoken(String percent) {
    return '$percent Prozent';
  }

  @override
  String reportHours(String hours) {
    return '$hours Std.';
  }

  @override
  String reportCaptionTo(String date) {
    return 'Bis $date';
  }

  @override
  String reportCaptionAgainst(String period) {
    return 'gegenüber $period';
  }

  @override
  String reportSkippedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count übersprungen',
      one: '1 übersprungen',
    );
    return '$_temp0';
  }

  @override
  String reportAheadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anstehend',
      one: '1 anstehend',
    );
    return '$_temp0';
  }

  @override
  String reportEventCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Termine',
      one: '1 Termin',
    );
    return '$_temp0';
  }

  @override
  String reportPlannedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geplant',
      one: '1 geplant',
    );
    return '$_temp0';
  }

  @override
  String get reportCaptionNothing => 'Nichts passiert';

  @override
  String reportDeltaMore(String delta, String period) {
    return '$delta mehr als $period';
  }

  @override
  String reportDeltaLess(String delta, String period) {
    return '$delta weniger als $period';
  }

  @override
  String reportDeltaMoreCount(int delta, String period) {
    final intl.NumberFormat deltaNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String deltaString = deltaNumberFormat.format(delta);

    String _temp0 = intl.Intl.pluralLogic(
      delta,
      locale: localeName,
      other: '$deltaString mehr als $period',
      one: '$deltaString mehr als $period',
    );
    return '$_temp0';
  }

  @override
  String reportDeltaFewerCount(int delta, String period) {
    final intl.NumberFormat deltaNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String deltaString = deltaNumberFormat.format(delta);

    String _temp0 = intl.Intl.pluralLogic(
      delta,
      locale: localeName,
      other: '$deltaString weniger als $period',
      one: '$deltaString weniger als $period',
    );
    return '$_temp0';
  }

  @override
  String reportDeltaSame(String period) {
    return 'gleich wie $period';
  }

  @override
  String get reportTileNone => 'keine';

  @override
  String get reportPeriodLastWeek => 'Letzte Woche';

  @override
  String get reportPeriodNextWeek => 'Nächste Woche';

  @override
  String get reportPeriodLastMonth => 'Letzter Monat';

  @override
  String get reportPeriodNextMonth => 'Nächster Monat';

  @override
  String get reportShowAsList => 'Als Liste anzeigen';

  @override
  String get reportShare => 'Bericht teilen';

  @override
  String get exportingReport => 'Bericht wird exportiert...';

  @override
  String get reportExported => 'Bericht exportiert';

  @override
  String get reportExportError => 'Bericht konnte nicht exportiert werden';

  @override
  String get reportSendWeekly => 'Wöchentlich zusenden';

  @override
  String get reportSendMonthly => 'Monatlich zusenden';

  @override
  String get reportLegendHappened => 'Stattgefunden';

  @override
  String reportTrendBusiest(String weekday) {
    return 'Meist am $weekday';
  }

  @override
  String reportTrendUsual(String from, String to) {
    return 'üblicherweise $from – $to';
  }

  @override
  String reportTrendUsualAt(String time) {
    return 'üblicherweise um $time';
  }

  @override
  String reportTrendPeak(String peak, String date) {
    return 'Höchstwert $peak am $date';
  }

  @override
  String reportTrendSpoken(String summary) {
    return 'Im Zeitverlauf. $summary';
  }

  @override
  String reportTrendPeakWeek(String peak, String date) {
    return 'Höchstwert $peak in der Woche vom $date';
  }

  @override
  String reportTrendPeakMonth(String peak, String month) {
    return 'Höchstwert $peak im $month';
  }

  @override
  String reportOfTotalOnly(String total) {
    return 'von $total';
  }

  @override
  String reportGroupMore(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString weitere',
      one: '1 weiterer',
    );
    return '$_temp0';
  }

  @override
  String reportMoreCategories(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString weitere Kategorien',
      one: '1 weitere Kategorie',
    );
    return '$_temp0';
  }

  @override
  String get reportMoreCategoriesTitle => 'Weitere Kategorien';

  @override
  String reportGroupMoreSpoken(int count, String category) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere in $category',
      one: '1 weiterer in $category',
    );
    return '$_temp0';
  }

  @override
  String get reportGroupLess => 'Weniger anzeigen';

  @override
  String reportGroupLessSpoken(String category) {
    return 'Weniger von $category anzeigen';
  }

  @override
  String reportAttendedOf(int total, int attended) {
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);
    final intl.NumberFormat attendedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String attendedString = attendedNumberFormat.format(attended);

    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$attendedString von $totalString anwesend',
      one: '$attendedString von 1 anwesend',
    );
    return '$_temp0';
  }

  @override
  String reportTasksOf(int total, int ticked) {
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);
    final intl.NumberFormat tickedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String tickedString = tickedNumberFormat.format(ticked);

    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$tickedString von $totalString Aufgaben',
      one: '$tickedString von 1 Aufgabe',
    );
    return '$_temp0';
  }

  @override
  String reportHoursSpoken(String hours) {
    return '$hours Stunden';
  }

  @override
  String reportWholeHoursSpoken(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Stunden',
      one: '1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String reportMinutesSpoken(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String reportRowDay(String weekday, String day) {
    return '$weekday, $day.';
  }

  @override
  String reportRowDayMonth(String weekday, String day, String month) {
    return '$weekday, $day. $month';
  }

  @override
  String reportGroupListSpoken(String category) {
    return '$category als Liste zeigen';
  }

  @override
  String get calendarGuidePageReport => 'Sehen, was war';

  @override
  String get calendarGuidePageReportCaption =>
      'Summen, verpasste Tage und was noch kommt';

  @override
  String calendarGuideReportLead(String report) {
    return '„$report“ zählt eine Woche, einen Monat oder ein Jahr, Kategorie für Kategorie.';
  }

  @override
  String get calendarGuideReportOpenTitle => 'Öffnen';

  @override
  String calendarGuideReportOpenBody(
    String calendar,
    String overview,
    String report,
    String thisWeek,
    String lastMonth,
    String custom,
  ) {
    return 'Öffne die Seite über den Titel: „$calendar“ · „$overview“ · „$report“. Der Titel zwischen den Pfeilen wählt den Zeitraum – „$thisWeek“, „$lastMonth“, „$custom“; die Pfeile gehen um die Länge des Zeitraums weiter.';
  }

  @override
  String get calendarGuideReportCategoriesTitle => 'Welche Kategorien';

  @override
  String calendarGuideReportCategoriesBody(
    String categories,
    int max,
    String moreCategories,
    int rows,
    String more,
  ) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);
    final intl.NumberFormat rowsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String rowsString = rowsNumberFormat.format(rows);

    return 'Die Taste „$categories“ beschränkt die Seite auf die, die du wählst; darunter steht eine Gruppe je Kategorie, mit einem Balken im Vergleich zur größten – bei mehr als $maxString Kategorien stehen die übrigen hinter „$moreCategories“, das ein Blatt öffnet. Eine Gruppe öffnet mit $rowsString Zeilen; „$more“ zeigt den Rest an Ort und Stelle, ein Tippen auf ihre Überschrift klappt sie zu.';
  }

  @override
  String get calendarGuideReportMissedTitle => 'Was du verpasst hast';

  @override
  String calendarGuideReportMissedBody(String missed, String markPresent) {
    return '„$missed“ listet die Termine, die du als abwesend markiert hast oder die als abwesend gelten; tippe neben einer Zeile auf „$markPresent“, und die Zahlen rechnen sich neu.';
  }

  @override
  String get calendarGuideReportDigestTitle =>
      'Jede Woche oder jeden Monat von selbst';

  @override
  String calendarGuideReportDigestBody(
    String weekly,
    String monthly,
    String shows,
    String weekReport,
    String monthReport,
    String share,
  ) {
    return 'Bei einer Woche öffnet „$weekly“, bei einem Monat „$monthly“ eine Zusammenfassung des gerade abgelaufenen Zeitraums – speichere sie, und sie kommt am ersten Tag der nächsten Woche oder des nächsten Monats: eine Zusammenfassung, bei der „$shows“ auf „$weekReport“ oder „$monthReport“ steht. „$share“ schreibt die Seite als Markdown.';
  }
}
