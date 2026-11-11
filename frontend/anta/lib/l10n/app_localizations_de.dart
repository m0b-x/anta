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
  String get holidayProfileTitle => 'Feiertags-Kalender';

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
  String get categoryDeleted => 'Kategorie gelöscht';

  @override
  String get categorySaveFailed => 'Kategorie konnte nicht gespeichert werden';

  @override
  String get categoryChangeFailed =>
      'Die Änderung konnte nicht gespeichert werden';

  @override
  String categoryEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ereignisse',
      one: '1 Ereignis',
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
  String get categorySortConfirmTitle => 'Kategorien A–Z sortieren?';

  @override
  String get categorySortConfirmBody =>
      'Deine eigene Reihenfolge wird ersetzt.';

  @override
  String get sort => 'Sortieren';

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
      'Große Fastenzeit, Weihnachts-, Apostel-, Entschlafungs-Fasten, strenge Einzeltage';

  @override
  String get fastingWeekdayDaysTitle => 'Wöchentliche Fastentage';

  @override
  String get fastingWeekdayDaysDesc =>
      'Wähle deine Tage — viele fasten nur mittwochs und freitags';

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
  String get fastingExceptionsSkipTitle => 'Tage, an denen ich nicht faste';

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
  String onboardingBackupFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ordner',
      one: '1 Ordner',
    );
    return '$_temp0';
  }

  @override
  String onboardingBackupNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizen',
      one: '1 Notiz',
    );
    return '$_temp0';
  }

  @override
  String get onboardingHowToHint =>
      '„So nutzt du ANTA“ findest du jederzeit im Menü';

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
  String get searchStillIndexing =>
      'Notizen werden noch indexiert – einige fehlen eventuell';

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
  String optimizeFreed(String size) {
    return '$size freigegeben';
  }

  @override
  String get optimizeAlreadyCompact => 'Bereits kompakt';

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
      'Vor dem Löschen von Notizen oder Ordnern nachfragen';

  @override
  String get autoSaveSection => 'Automatisches Speichern';

  @override
  String get autoSave => 'Notizen automatisch speichern';

  @override
  String get autoSaveDesc =>
      'Beim Tippen speichern. Ausgeschaltet wird eine Notiz gespeichert, wenn du sie verlässt oder die App in den Hintergrund geht.';

  @override
  String get autoSaveInterval => 'Speicherintervall';

  @override
  String autoSaveIntervalDesc(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Speichert $seconds Sekunden nach der letzten Änderung',
      one: 'Speichert eine Sekunde nach der letzten Änderung',
    );
    return '$_temp0';
  }

  @override
  String autoSaveSeconds(int count) {
    return '$count s';
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
  String get settingsResetFailed =>
      'Die Einstellungen konnten nicht zurückgesetzt werden';

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
  String get checkingDatabaseFile => 'Datei wird geprüft...';

  @override
  String get databaseImportCorrupt =>
      'Diese Datenbankdatei ist beschädigt und kann nicht importiert werden.';

  @override
  String get databaseImportNotAnta => 'Diese Datei ist keine ANTA-Datenbank.';

  @override
  String get databaseImportTooNew =>
      'Diese Datenbank stammt aus einer neueren ANTA-Version. Aktualisiere die App, um sie zu importieren.';

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
  String databaseSwitchConfirm(String name) {
    return 'Zu $name wechseln? ANTA startet damit neu.';
  }

  @override
  String databaseSizeBytes(String size) {
    return '$size B';
  }

  @override
  String databaseSizeKilobytes(String size) {
    return '$size KB';
  }

  @override
  String databaseSizeMegabytes(String size) {
    return '$size MB';
  }

  @override
  String get unknownValue => 'Unbekannt';

  @override
  String get databasePathError =>
      'Der Speicherpfad konnte nicht gelesen werden';

  @override
  String get databaseCreateFailed =>
      'Die Datenbank konnte nicht erstellt werden';

  @override
  String get databaseRenameFailed =>
      'Die Datenbank konnte nicht umbenannt werden';

  @override
  String get databaseDeleteFailed =>
      'Die Datenbank konnte nicht gelöscht werden';

  @override
  String get databaseSwitchFailed =>
      'Die Datenbank konnte nicht gewechselt werden';

  @override
  String get databaseOptimizeFailed =>
      'Die Datenbank konnte nicht optimiert werden';

  @override
  String databaseReclaimable(String size) {
    return 'Freigebbar: $size';
  }

  @override
  String get databaseReclaimableUnknown => 'Freigebbarer Speicher unbekannt';

  @override
  String get launchUpdatingData => 'Deine Daten werden aktualisiert…';

  @override
  String get launchOpeningData => 'Deine Daten werden geöffnet…';

  @override
  String get launchOpenFailed => 'Deine Daten konnten nicht geöffnet werden';

  @override
  String get launchOpenFailedNext =>
      'Versuche es erneut oder starte die App neu. Wenn das wieder passiert, gib etwas Speicherplatz frei.';

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
      'Starte die App neu, um die neue Datenbank zu verwenden.';

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
  String get systemDefault => 'System-Standard';

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
  String get previewModeEnabled => 'Vorschau-Modus';

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
  String get calendarSection => 'Feiertage';

  @override
  String get calendarSettings => 'Kalender-Einstellungen';

  @override
  String get holidayProfileDesc =>
      'Gesetzliche Feiertage im Kalender; auch für Werktags-Wiederholungen';

  @override
  String get calendarSettingsPagesSection => 'Weitere Einstellungen';

  @override
  String get deleteAllEventsFailed =>
      'Die Ereignisse konnten nicht gelöscht werden';

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
  String get calendarHighlightWeekends => 'Wochenende färben';

  @override
  String get calendarHighlightWeekendsDesc =>
      'Samstag und Sonntag in eigener Farbe anzeigen';

  @override
  String get calendarShowWeekNumbers => 'Kalender-Wochen';

  @override
  String get calendarShowWeekNumbersDesc =>
      'Wochen-Nummern am linken Rand anzeigen';

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
  String get calendarShowRecurrenceLabels => 'Rhythmus in Zeilen';

  @override
  String get calendarShowRecurrenceLabelsDesc =>
      'Rhythmus (Täglich, Wöchentlich…) in Ereigniszeilen anzeigen';

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
      'Gespeicherte Vorlagen — Kategorie, Zeitplan, Farbe und Details vorausgefüllt';

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
  String get developerOptionsResetConfirm =>
      'Alle Entwickleroptionen zurücksetzen? Das sperrt auch den Entwicklermodus.';

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
  String get showFpsCounterDesc => 'Scroll- und Animations-Leistung überwachen';

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
  String get showDatabaseStats => 'Datenbank-Statistik anzeigen';

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
  String get searchSettings => 'Suchen';

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
  String get sharingSettings => 'Sync & Teilen';

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
  String get authSignOutFailed => 'Nicht abgemeldet';

  @override
  String get authSignOutFailedRetry =>
      'Abmeldung fehlgeschlagen – versuch es erneut';

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
  String get syncSection => 'Synchronisierung';

  @override
  String get syncKeywords =>
      'Cloud, Sync, synchronisieren, Geräte, Handy, Tablet, Bereich, zusammenführen, herunterladen, hochladen, Status, offline, beenden, automatisch, manuell, löschen';

  @override
  String get syncThisDatabase => 'Diese Datenbank synchronisieren';

  @override
  String get syncThisDatabaseDesc =>
      'Deine anderen Geräte mit diesem Konto bekommen jede Änderung und senden ihre';

  @override
  String get syncSignInFirst =>
      'Melde dich an, um diese Datenbank zu synchronisieren';

  @override
  String get syncThisDatabaseUnavailable =>
      'Synchronisierung ist in dieser Version von ANTA nicht verfügbar';

  @override
  String get syncUpToDate => 'Auf dem neuesten Stand';

  @override
  String get syncWaitingFirst => 'Wartet auf die erste Synchronisierung';

  @override
  String syncSending(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Änderungen werden gesendet',
      one: '1 Änderung wird gesendet',
      zero: 'Änderungen werden gesendet',
    );
    return '$_temp0';
  }

  @override
  String get syncReceiving => 'Änderungen werden empfangen';

  @override
  String syncDownloading(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wird geladen – bisher $countString Einträge',
      one: 'Wird geladen – bisher 1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String syncUpdatingNotes(int done, int total) {
    final intl.NumberFormat doneNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String doneString = doneNumberFormat.format(done);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Update läuft – Notizen $doneString von $totalString';
  }

  @override
  String get syncUpdating => 'Update läuft';

  @override
  String syncUpdatingSending(int done, int total) {
    final intl.NumberFormat doneNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String doneString = doneNumberFormat.format(done);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Update läuft – gesendet $doneString von $totalString';
  }

  @override
  String get syncOffline => 'Offline – neuer Versuch folgt';

  @override
  String get syncRetrying => 'Nicht synchronisiert – neuer Versuch folgt';

  @override
  String get syncOfflineManual => 'Offline – nicht synchronisiert';

  @override
  String get syncFailedManual => 'Nicht synchronisiert';

  @override
  String get syncManualIdle =>
      'Synchronisierung nur über „Jetzt synchronisieren“';

  @override
  String get syncPausedQuota => 'Pausiert – Tageslimit erreicht';

  @override
  String syncPausedQuotaUntil(String time) {
    return 'Pausiert bis $time – Tageslimit erreicht';
  }

  @override
  String get syncPausedSignedOut => 'Pausiert – abgemeldet';

  @override
  String get syncPausedOtherAccount =>
      'Pausiert – gehört zu einem anderen Konto';

  @override
  String get syncPausedAppOutdated =>
      'Pausiert – aktualisiere ANTA auf diesem Gerät';

  @override
  String get syncPausedNoAccess =>
      'Pausiert – die Cloud-Kopie ist nicht erreichbar';

  @override
  String get syncPausedSpaceDeleted =>
      'Pausiert – die Cloud-Kopie wurde gelöscht';

  @override
  String get drawerAccountNotSyncing => 'Wird nicht synchronisiert';

  @override
  String get drawerSyncPausedQuota => 'Pausiert – Tageslimit';

  @override
  String drawerSyncPausedQuotaUntil(String time) {
    return 'Pausiert bis $time';
  }

  @override
  String get drawerSyncPausedOtherAccount => 'Pausiert – anderes Konto';

  @override
  String get drawerSyncPausedAppOutdated => 'Pausiert – ANTA aktualisieren';

  @override
  String get drawerSyncPausedNoAccess => 'Pausiert – kein Zugriff';

  @override
  String get drawerSyncPausedSpaceDeleted => 'Pausiert – Cloud-Kopie gelöscht';

  @override
  String get drawerSyncRetrying => 'Fehler – neuer Versuch';

  @override
  String drawerSyncUpdating(int done, int total) {
    final intl.NumberFormat doneNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String doneString = doneNumberFormat.format(done);
    final intl.NumberFormat totalNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String totalString = totalNumberFormat.format(total);

    return 'Update läuft ($doneString von $totalString)';
  }

  @override
  String get drawerSyncUpdatingNoTotal => 'Update läuft';

  @override
  String syncLastSynced(String time) {
    return 'Zuletzt synchronisiert $time';
  }

  @override
  String get syncNeverSynced => 'Noch nicht synchronisiert';

  @override
  String syncPendingCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Änderungen warten',
      one: '1 Änderung wartet',
    );
    return '$_temp0';
  }

  @override
  String syncDetailsWaiting(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString warten',
      one: '1 wartet',
    );
    return '$_temp0';
  }

  @override
  String syncParkedCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString zurückgestellt',
      one: '1 zurückgestellt',
    );
    return '$_temp0';
  }

  @override
  String get syncHeldBackRefused => 'Von der Cloud-Kopie abgelehnt';

  @override
  String get syncHeldBackUnencodable =>
      'Konnte nicht zum Senden vorbereitet werden';

  @override
  String get syncHeldBackAwaitingText => 'Wartet auf den Text';

  @override
  String get syncHeldBackUnreadable => 'Aus der Cloud-Kopie nicht lesbar';

  @override
  String syncHeldBackDeleted(String kind, String reason) {
    String _temp0 = intl.Intl.selectLogic(kind, {'other': 'Gelöscht'});
    return '$_temp0 · $reason';
  }

  @override
  String syncHeldBackKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'note': 'Eine Notiz',
      'folder': 'Ein Ordner',
      'event': 'Ein Termin',
      'category': 'Eine Kalenderkategorie',
      'counter': 'Ein Zähler',
      'template': 'Eine Terminvorlage',
      'view': 'Eine gespeicherte Ansicht',
      'filter': 'Ein gespeicherter Filter',
      'digest': 'Eine Zusammenfassung',
      'vocabulary': 'Eine Begriffsliste',
      'other': 'Ein Eintrag',
    });
    return '$_temp0';
  }

  @override
  String syncHeldBackMoreHeld(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Und $countString weitere noch zurückgestellt',
      one: 'Und 1 weiterer noch zurückgestellt',
    );
    return '$_temp0';
  }

  @override
  String syncHeldBackMoreSynced(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Die $countString weiteren wurden synchronisiert',
      one: 'Der eine weitere wurde synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String syncHeldBackSynced(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {'other': 'Synchronisiert'});
    return '$_temp0';
  }

  @override
  String get syncHeldBackAllDone => 'Alles synchronisiert';

  @override
  String get syncHeldBackIntro => '„Jetzt synchronisieren“ versucht es erneut.';

  @override
  String get syncHeldBackIntroDone => 'Nichts wird mehr zurückgestellt.';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get syncAutomatic => 'Automatisch synchronisieren';

  @override
  String get syncAutomaticOnDesc =>
      'Änderungen werden synchronisiert, solange die App offen ist, und wenn du sie verlässt';

  @override
  String get syncAutomaticOffDesc =>
      'Nur wenn du auf „Jetzt synchronisieren“ tippst';

  @override
  String get syncStop => 'Synchronisierung beenden';

  @override
  String get syncStopConfirmTitle =>
      'Synchronisierung dieser Datenbank beenden?';

  @override
  String get syncStopConfirmBody =>
      'Dieses Gerät sendet und empfängt für diese Datenbank keine Änderungen mehr. Die Kopie in der Cloud bleibt, und deine anderen Geräte behalten sie.';

  @override
  String get syncStopConfirmAction => 'Synchronisierung beenden';

  @override
  String get syncStopFailed =>
      'Synchronisierung konnte nicht beendet werden – versuch es erneut';

  @override
  String get syncStopConfirmBodyDeleted =>
      'Die Cloud-Kopie dieser Datenbank wurde gelöscht. Dieses Gerät behält alles und versucht nicht mehr zu synchronisieren.';

  @override
  String get syncDeleteCloud => 'Cloud-Kopie löschen';

  @override
  String get syncDeleteCloudDesc =>
      'Entfernt sie aus deinem Konto. Dieses Gerät behält alles.';

  @override
  String syncDeleteCloudProgress(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Einträge entfernt',
      one: '1 Eintrag entfernt',
      zero: 'Wird gestartet…',
    );
    return '$_temp0';
  }

  @override
  String get syncDeleteCloudConfirmTitle =>
      'Cloud-Kopie dieser Datenbank löschen?';

  @override
  String get syncDeleteCloudConfirmBody =>
      'Die Kopie wird endgültig aus deinem Konto entfernt, und diese Datenbank synchronisiert nicht mehr. Auf diesem Gerät wird nichts gelöscht. Deine anderen Geräte behalten, was sie haben, und synchronisieren ebenfalls nicht mehr.';

  @override
  String get syncDeleteCloudConfirmAction => 'Cloud-Kopie löschen';

  @override
  String get syncDeleteCloudDone => 'Cloud-Kopie gelöscht';

  @override
  String get syncDeletionSection => 'Löschen der Cloud-Kopie';

  @override
  String get syncDeleteCloudRunning => 'Cloud-Kopie wird gelöscht';

  @override
  String get syncDeleteCloudFinish => 'Löschen abschließen';

  @override
  String get syncDeleteCloudFinishUpdate =>
      'Aktualisiere ANTA, um abzuschließen';

  @override
  String syncDeleteCloudFinishDesc(String space) {
    return 'Cloud-Kopie erst teilweise gelöscht: „$space“';
  }

  @override
  String syncDeleteCloudFinishMany(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString Cloud-Kopien erst teilweise gelöscht',
      one: '1 Cloud-Kopie erst teilweise gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get syncPickerSpaces => 'Cloud-Bereiche';

  @override
  String get syncPickerTitle => 'Bereich wählen';

  @override
  String syncPickerLastUsed(String time) {
    return 'Zuletzt verwendet $time';
  }

  @override
  String get syncPickerNotUsed => 'Noch nicht verwendet';

  @override
  String syncPickerHeldBy(String database) {
    return 'Wird von „$database“ auf diesem Gerät synchronisiert';
  }

  @override
  String syncPickerMerge(String space) {
    return 'Diese Datenbank mit „$space“ zusammenführen';
  }

  @override
  String get syncPickerMergeSelected =>
      'Diese Datenbank mit dem gewählten Bereich zusammenführen';

  @override
  String syncPickerDownload(String space) {
    return '„$space“ in eine neue Datenbank laden';
  }

  @override
  String get syncPickerDownloadSelected =>
      'Den gewählten Bereich in eine neue Datenbank laden';

  @override
  String syncPickerJoin(String space) {
    return 'Mit „$space“ synchronisieren';
  }

  @override
  String get syncPickerUpload => 'Diese Datenbank als neuen Bereich hochladen';

  @override
  String get syncFailedOffline =>
      'Du bist offline – versuch es erneut, sobald du verbunden bist';

  @override
  String get syncFailedQuota =>
      'Das heutige Sync-Limit ist erreicht – versuch es morgen erneut';

  @override
  String get syncFailedPermission =>
      'Die Cloud hat das abgelehnt – prüf, ob du mit dem richtigen Konto angemeldet bist oder ob die Synchronisierung in der Cloud schon eingerichtet ist';

  @override
  String get syncFailedSpaceGone =>
      'Diesen Cloud-Bereich gibt es nicht mehr – wähl einen anderen oder lade diese Datenbank als neuen Bereich hoch';

  @override
  String get syncFailedAppOutdated =>
      'Eine neuere ANTA-Version hat in diese Cloud-Kopie geschrieben – aktualisiere zuerst die App';

  @override
  String get syncFailedSuspended =>
      'Eine Wiederherstellung läuft – versuch es danach erneut';

  @override
  String get syncFailedAlreadyBound =>
      'Diese Datenbank wird bereits synchronisiert – beende das zuerst';

  @override
  String syncFailedHeld(String database) {
    return 'Die Datenbank „$database“ auf diesem Gerät synchronisiert bereits mit diesem Bereich';
  }

  @override
  String get syncFailedHeldUnnamed =>
      'Eine andere Datenbank auf diesem Gerät synchronisiert bereits mit diesem Bereich';

  @override
  String get syncFailedInvalidName =>
      'Ein Bereichsname braucht 1 bis 100 Zeichen';

  @override
  String get syncFailedNewDatabase =>
      'Die neue Datenbank konnte nicht erstellt werden – nichts wurde geändert';

  @override
  String get syncFailedUnknown =>
      'Synchronisierung konnte nicht gestartet werden – versuch es erneut';

  @override
  String syncMergeConfirmTitle(String space) {
    return 'Mit „$space“ zusammenführen?';
  }

  @override
  String get syncMergeConfirmBody =>
      'Einträge, die diese Datenbank und die Cloud beide haben, übernehmen die Version der Cloud. Einträge, die nur hier sind, werden hochgeladen.';

  @override
  String get syncMergeConfirmAction => 'Zusammenführen';

  @override
  String syncUnboundAsCopyOf(String database) {
    return 'Synchronisierung beendet – eine Kopie von „$database“ ist schon verbunden';
  }

  @override
  String get syncBusyLabel => 'Wird ausgeführt…';

  @override
  String syncAnnounceBound(String space) {
    return 'Synchronisiert mit „$space“';
  }

  @override
  String get syncAnnounceBoundUnnamed => 'Diese Datenbank wird synchronisiert';

  @override
  String get syncAnnounceStopped => 'Synchronisierung beendet';

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
  String get signOutConfirm => 'Von diesem Konto abmelden?';

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
  String get alertsNotifications => 'Mitteilungen';

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
  String alertsNoticeLeadHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Ein leiser Hinweis $count Stunden vor einem Alarm, mit Überspringen und Öffnen',
      one:
          'Ein leiser Hinweis 1 Stunde vor einem Alarm, mit Überspringen und Öffnen',
    );
    return '$_temp0';
  }

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
  String get alertsTestAlarm => 'Testalarm in 10 s';

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
  String get reportDigestGoalsLead => 'Ziele';

  @override
  String get reportDigestDueLead => 'Fällig';

  @override
  String reportDigestGoalMet(String name, String value, String target) {
    return '$name $value von $target ✓';
  }

  @override
  String reportDigestGoalOver(String name, String value, String target) {
    return '$name $value (über $target)';
  }

  @override
  String reportDigestGoalPace(String name, String value, String target) {
    return '$name $value von $target';
  }

  @override
  String reportDigestGoalGap(String name, String since, String limit) {
    return '$name $since ($limit)';
  }

  @override
  String reportDigestGoalPeriods(String name, String periods) {
    return '$name $periods';
  }

  @override
  String reportDigestDueItem(String title, String phrase) {
    return '$title $phrase';
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
  String get categorySectionInUse => 'In Verwendung';

  @override
  String get categorySectionArchived => 'Archiviert';

  @override
  String get categoryRowArchived => 'Archiviert';

  @override
  String get categoryCaptionBuiltIn => 'Integriert';

  @override
  String get categoryCaptionAlertsOn => 'Erinnerungen an';

  @override
  String get categoryActions => 'Kategorieoptionen';

  @override
  String categoryReorderLabel(String name) {
    return '$name verschieben';
  }

  @override
  String get categoryMoveUp => 'Nach oben';

  @override
  String get categoryMoveDown => 'Nach unten';

  @override
  String get categoryReorderLockedHint => 'Suche leeren, um neu zu ordnen';

  @override
  String get categoryArchive => 'Archivieren';

  @override
  String get categoryRestore => 'Wiederherstellen';

  @override
  String get categoryDeleteEllipsis => 'Löschen…';

  @override
  String get categoryDeleteMoveTo => 'Ereignisse verschieben nach';

  @override
  String categoryDeleteImpactAlerts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Erinnerungen',
      one: '1 Erinnerung',
    );
    return '$_temp0';
  }

  @override
  String categoryDeleteImpactTemplates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Vorlagen',
      one: '1 Vorlage',
    );
    return '$_temp0';
  }

  @override
  String categoryDeleteConsequences(String name) {
    return 'Gespeicherte Ansichten, Zusammenfassungen und Berichte, die nur $name auswählen, zeigen nichts, bis du neu auswählst.';
  }

  @override
  String get categoryDeleteAlertsRemoved =>
      'Die Erinnerungen der Kategorie werden entfernt.';

  @override
  String get categoryDeleteTemplatesMove =>
      'Die Vorlagen der Kategorie werden mit den Ereignissen verschoben.';

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
  String get alertsDefaultRemove => 'Keine Standard-Erinnerung';

  @override
  String get alertSettingsTitle => 'Einstellungen für Erinnerungen';

  @override
  String get alertSettingsSectionDefaults => 'Standardwerte';

  @override
  String get alertSettingsSectionTiming => 'Ton und Zeiten';

  @override
  String get alertSettingsCategoriesRow => 'Erinnerungen pro Kategorie';

  @override
  String get alertSettingsCategoriesDesc => 'Für jede Kategorie festgelegt';

  @override
  String get fastingSettingsTitle => 'Fasten';

  @override
  String get fastingSectionTraditions => 'Traditionen';

  @override
  String get fastingLookRow => 'Darstellung im Kalender';

  @override
  String get fastingGreatFastsOffDesc =>
      'Aus: nur deine wöchentlichen Fastentage, das ganze Jahr';

  @override
  String get fastingPracticeRow => 'Deine Praxis';

  @override
  String get fastingTraditionsOff => 'Aus';

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
  String get settingsHubSearchHint => 'Suchen';

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
  String get settingsRowAlertsDesc =>
      'Standardwerte, Ton, Zeiten, Berechtigungen';

  @override
  String get settingsRowFastingDesc => 'Traditionen, deine Praxis';

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
  String get settingsRowSharingDesc =>
      'Konto, Synchronisierung und gekoppelte Geräte';

  @override
  String get permissionsCalendarRowDesc =>
      'Mitteilungen, genaue Zeit, Vollbild-Alarme, Akku';

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
  String get permissionsSystemSettings => 'System-Einstellungen';

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
  String get calendarGuideCategoriesWhereTitle => 'Wo sie verwaltet werden';

  @override
  String calendarGuideCategoriesWhereBody(String categories) {
    return 'Öffne das Menü (☰) und tippe auf „$categories“, oder tippe auf ⋮ im Kalender, dann „$categories“.';
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
  String calendarGuideSettingsBody(
    String settings,
    String calendarSettings,
    String save,
  ) {
    return 'Öffne das Menü (☰), tippe auf „$settings“, dann auf „$calendarSettings“ – oder tippe auf ⋮ im Kalender, dann auf „$calendarSettings“. Alles dort gilt sofort – es gibt keine Taste „$save“.';
  }

  @override
  String calendarGuideSetupFastingBody(
    String settings,
    String fasting,
    String calendarSettings,
  ) {
    return 'Unter „$settings“ → „$fasting“ oder aus „$calendarSettings“: die Traditionen, wie jede aussieht, deine eigene Praxis.';
  }

  @override
  String calendarGuideSetupAlertsBody(
    String settings,
    String alerts,
    String alertsPage,
  ) {
    return 'Unter „$settings“ → „$alerts“ oder über ⚙ auf der Seite $alertsPage: die Standard-Erinnerungen, der Weckton, das Schlummern und der Hinweis.';
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
  String get calendarGuideStepBack => 'Vorheriger Schritt';

  @override
  String get calendarGuideStepForward => 'Nächster Schritt';

  @override
  String get calendarGuideStepDone => 'Erledigt';

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
  String calendarGuideCoachScreenOverview(String overview) {
    return 'Tippe oben auf den Titel und wähle „$overview“: Der Titel ist ein Menü der Ansichten.';
  }

  @override
  String calendarGuideCoachScreenReport(String report) {
    return 'Tippe oben auf den Titel und wähle „$report“: Er zählt, was war.';
  }

  @override
  String calendarGuideCoachOverviewMode(
    String overview,
    String year,
    String month,
    String list,
  ) {
    return 'In „$overview“ tippe auf „$year“, „$month“ oder „$list“: drei Arten, dieselben Ereignisse zu sehen.';
  }

  @override
  String calendarGuideCoachOverviewPeriod(String overview) {
    return 'In „$overview“ blättern die Pfeile vor und zurück; die Taste dazwischen führt zu heute zurück.';
  }

  @override
  String calendarGuideCoachEventsAdd(String save) {
    return 'Tippe auf +, um ein Ereignis hinzuzufügen. Gib ihm einen Namen und tippe auf „$save“.';
  }

  @override
  String calendarGuideCoachEventsChange(String edit, String save) {
    return 'Tippe unten auf das Ereignis, dann oben rechts „$edit“, ändere den Namen, dann „$save“.';
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
  String calendarGuideCoachKindsSkip(String skip) {
    return 'Tippe auf einen Tag mit Punkt, dann „$skip“.';
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
  String calendarGuideCoachCategoriesHide(String archive) {
    return 'Tippe auf die drei Punkte einer Kategorie, dann „$archive“: sie verschwindet aus den Auswahllisten; ihre Ereignisse und Erinnerungen bleiben.';
  }

  @override
  String calendarGuideCoachCategoriesDelete(String delete, String other) {
    return 'Tippe auf die drei Punkte deiner Kategorie, dann „$delete“: ihre Ereignisse gehen zu „$other“ – oder wähle, wohin sie gehen.';
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
  String calendarGuideTourEdit(String edit, String save) {
    return 'Tippe unten auf das Ereignis, „$edit“, ändere es, „$save“.';
  }

  @override
  String get calendarGuideTourAdd =>
      'Tippe auf +, um am gewählten Tag ein Ereignis hinzuzufügen.';

  @override
  String calendarGuideTourFilter(String apply) {
    return 'Der Trichter versteckt Kategorien. Probier es, dann „$apply“.';
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
  String calendarGuideTourFilterCategory(String categories, String apply) {
    return 'Tippe auf den Trichter, „$categories“, wähle eine ab, dann „$apply“.';
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
  String get reportGroupLess => 'Weniger';

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

  @override
  String get markVerbDone => 'Erledigt';

  @override
  String get markVerbAttended => 'Besucht';

  @override
  String get markVerbTaken => 'Genommen';

  @override
  String get markVerbPaid => 'Bezahlt';

  @override
  String get markVerbReceived => 'Erhalten';

  @override
  String get markVerbMet => 'Stattgefunden';

  @override
  String get markVerbRenewed => 'Erneuert';

  @override
  String get eventMarkDone => 'Als erledigt markieren';

  @override
  String get eventMarkAttended => 'Als besucht markieren';

  @override
  String get eventMarkTaken => 'Als genommen markieren';

  @override
  String get eventMarkPaid => 'Als bezahlt markieren';

  @override
  String get eventMarkReceived => 'Als erhalten markieren';

  @override
  String get eventMarkMet => 'Als stattgefunden markieren';

  @override
  String get eventMarkRenewed => 'Als erneuert markieren';

  @override
  String eventMarkAsVerb(String verb) {
    return 'Als $verb markieren';
  }

  @override
  String get eventCancelEvent => 'Diesen Termin absagen';

  @override
  String get eventCancelledState => 'Abgesagt';

  @override
  String get eventRestoreEvent => 'Wiederherstellen';

  @override
  String get eventCancelled => 'Termin abgesagt';

  @override
  String get categoryReportSection => 'Bericht';

  @override
  String get categoryMeasureGoalSection => 'Messgröße & Ziel';

  @override
  String get categoryKindLabel => 'Art';

  @override
  String get categoryKindRoutine => 'Routine';

  @override
  String get categoryKindWorkout => 'Training';

  @override
  String get categoryKindMedication => 'Medikamente';

  @override
  String get categoryKindSleep => 'Schlaf';

  @override
  String get categoryKindEpisode => 'Episode';

  @override
  String get categoryKindAppointment => 'Termin';

  @override
  String get categoryKindWork => 'Arbeit';

  @override
  String get categoryKindMeeting => 'Besprechung';

  @override
  String get categoryKindTask => 'Aufgabe';

  @override
  String get categoryKindDeadline => 'Frist';

  @override
  String get categoryKindStudy => 'Lernen';

  @override
  String get categoryKindBill => 'Rechnung';

  @override
  String get categoryKindIncome => 'Einnahme';

  @override
  String get categoryKindSocial => 'Soziales';

  @override
  String get categoryKindAnniversary => 'Jahrestag';

  @override
  String get categoryKindChore => 'Haushalt';

  @override
  String get categoryKindMaintenance => 'Wartung';

  @override
  String get categoryKindExpiry => 'Ablaufdatum';

  @override
  String get categoryKindTrip => 'Reise';

  @override
  String get categoryKindLeave => 'Urlaub';

  @override
  String get categoryKindCustom => 'Eigene Art';

  @override
  String get categoryKindExampleRoutine => 'Dehnen, Tagebuch';

  @override
  String get categoryKindExampleWorkout => 'Studio, Laufen, Kurs';

  @override
  String get categoryKindExampleMedication => 'Tabletten, Vitamine';

  @override
  String get categoryKindExampleSleep => 'Die Nacht und ihre Dauer';

  @override
  String get categoryKindExampleEpisode => 'Krankheit, Migräne, Zyklus';

  @override
  String get categoryKindExampleAppointment => 'Arzt, Zahnarzt, Tierarzt';

  @override
  String get categoryKindExampleWork => 'Schichten, Arbeitstage';

  @override
  String get categoryKindExampleMeeting => 'Anrufe, Stand-ups, Reviews';

  @override
  String get categoryKindExampleTask => 'To-dos, Besorgungen';

  @override
  String get categoryKindExampleDeadline => 'Abgaben, Einreichungen';

  @override
  String get categoryKindExampleStudy => 'Kurse, Üben, Lesen';

  @override
  String get categoryKindExampleBill => 'Miete, Rechnungen, Abos';

  @override
  String get categoryKindExampleIncome => 'Gehalt, Honorare';

  @override
  String get categoryKindExampleSocial => 'Essen, Besuche, Dates';

  @override
  String get categoryKindExampleAnniversary => 'Geburtstage, Namenstage';

  @override
  String get categoryKindExampleChore => 'Putzen, Wäsche, Einkauf';

  @override
  String get categoryKindExampleMaintenance => 'Autoservice, Heizung';

  @override
  String get categoryKindExampleExpiry => 'Pass, Ausweis, Garantie';

  @override
  String get categoryKindExampleTrip => 'Reisen, Wochenendausflüge';

  @override
  String get categoryKindExampleLeave => 'Ferien, freie Tage';

  @override
  String get categoryKindExampleCustom => 'Alles andere';

  @override
  String get lifeAreaHealth => 'Gesundheit';

  @override
  String get lifeAreaWork => 'Arbeit';

  @override
  String get lifeAreaMoney => 'Geld';

  @override
  String get lifeAreaPeople => 'Menschen';

  @override
  String get lifeAreaHome => 'Zuhause';

  @override
  String get lifeAreaLeisure => 'Freizeit';

  @override
  String get lifeAreaOther => 'Sonstiges';

  @override
  String get categoryMarkLabel => 'Markierung';

  @override
  String get categoryMarkOff => 'Aus';

  @override
  String get categoryMarkOwn => 'Eigenes Wort…';

  @override
  String get categoryMarkOwnTitle => 'Eigenes Wort';

  @override
  String get categoryMarkOwnHint => 'z. B. Spaziert';

  @override
  String get categoryAreaLabel => 'Bereich';

  @override
  String get categoryMeasureLabel => 'Messgröße';

  @override
  String get categoryMeasureAuto => 'Auto';

  @override
  String categoryMeasureAutoIs(String measure) {
    return 'Auto ist $measure';
  }

  @override
  String get categoryMeasureAutoPerPeriod => 'Auto wählt je Zeitraum';

  @override
  String categoryMeasureAutoWith(String measure) {
    return 'Auto · $measure';
  }

  @override
  String get categoryMeasureCount => 'Anzahl';

  @override
  String get categoryMeasureEvents => 'Termine';

  @override
  String get categoryMeasureHours => 'Stunden';

  @override
  String get categoryMeasureAttendance => 'Anwesenheit';

  @override
  String get categoryMeasureTasks => 'Aufgaben';

  @override
  String get categoryMeasureMoney => 'Geld';

  @override
  String get categoryMeasureLastSeen => 'Zuletzt am';

  @override
  String get categoryMeasureDaysUntil => 'Tage bis';

  @override
  String get categoryMeasureCancelled => 'Abgesagt';

  @override
  String get categoryMeasureLeadTime => 'Vorlauf';

  @override
  String get categoryMeasureTiming => 'Uhrzeit';

  @override
  String get categoryCountsAsLabel => 'Zählt als';

  @override
  String get categoryCountsAsOff => 'Aus';

  @override
  String categoryCountsAsSuggested(String duration) {
    return 'Vorschlag: $duration';
  }

  @override
  String categoryCountsAsSuggestedItem(String duration) {
    return '$duration · Vorschlag';
  }

  @override
  String get categoryCountsAsScope => 'Für Termine ohne Uhrzeit';

  @override
  String get categoryCountsAsSleep => 'Schlaf zählt eigene Stunden';

  @override
  String get categoryCountsAsRepeats => 'Wiederholungen zählen keine Stunden';

  @override
  String get categoryGoalLabel => 'Ziel';

  @override
  String get categoryGoalNone => 'Kein Ziel';

  @override
  String get categoryGoalNeedsMeasure => 'Erst eine Messgröße wählen';

  @override
  String categoryGoalNotFor(String measure) {
    return 'Kein Ziel für $measure';
  }

  @override
  String get categoryGoalTitle => 'Ziel';

  @override
  String get categoryGoalTypeSection => 'Typ';

  @override
  String get categoryGoalTargetSection => 'Zielwert';

  @override
  String get categoryGoalTypeAtLeast => 'Mindestens';

  @override
  String get categoryGoalTypeAtMost => 'Höchstens';

  @override
  String get categoryGoalTypeBudget => 'Budget';

  @override
  String get categoryGoalTypeMaxGap => 'Tage dazwischen';

  @override
  String get categoryGoalTypeNotForMeasure => 'Nicht für diese Messgröße';

  @override
  String get categoryGoalUnitCount => 'Anzahl';

  @override
  String get categoryGoalUnitHours => 'Stunden';

  @override
  String get categoryGoalUnitTasks => 'Aufgaben';

  @override
  String get categoryGoalUnitAmount => 'Betrag';

  @override
  String get categoryGoalUnitDays => 'Tage';

  @override
  String categoryGoalHours(String hours) {
    return '$hours h';
  }

  @override
  String categoryGoalTasks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Aufgaben',
      one: '1 Aufgabe',
    );
    return '$_temp0';
  }

  @override
  String get categoryGoalLess => 'Weniger';

  @override
  String get categoryGoalMore => 'Mehr';

  @override
  String get categoryGoalPeriodDay => 'Tag';

  @override
  String get categoryGoalPeriodWeek => 'Woche';

  @override
  String get categoryGoalPeriodMonth => 'Monat';

  @override
  String get categoryGoalPeriodYear => 'Jahr';

  @override
  String categoryGoalAtLeast(String amount, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'pro Tag',
      'week': 'pro Woche',
      'month': 'pro Monat',
      'year': 'pro Jahr',
      'other': '',
    });
    return 'Mindestens $amount $_temp0';
  }

  @override
  String categoryGoalAtMost(String amount, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'pro Tag',
      'week': 'pro Woche',
      'month': 'pro Monat',
      'year': 'pro Jahr',
      'other': '',
    });
    return 'Höchstens $amount $_temp0';
  }

  @override
  String categoryGoalBudget(String amount, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'pro Tag',
      'week': 'pro Woche',
      'month': 'pro Monat',
      'year': 'pro Jahr',
      'other': '',
    });
    return 'Budget $amount $_temp0';
  }

  @override
  String categoryGoalGap(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Höchstens $days Tage dazwischen',
      one: 'Höchstens 1 Tag dazwischen',
    );
    return '$_temp0';
  }

  @override
  String get categoryGoalRemove => 'Ziel entfernen';

  @override
  String get reportSectionGoals => 'Ziele';

  @override
  String get reportSectionInsights => 'Hinweise';

  @override
  String get reportSectionDueSoon => 'Bald fällig';

  @override
  String reportGoalMoreBy(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'noch $count bis $day',
      one: 'noch 1 bis $day',
    );
    return '$_temp0';
  }

  @override
  String reportGoalMoreToday(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'heute noch $count',
      one: 'heute noch 1',
    );
    return '$_temp0';
  }

  @override
  String reportGoalAmountMoreBy(String amount, String day) {
    return 'noch $amount bis $day';
  }

  @override
  String reportGoalAmountMoreToday(String amount) {
    return 'heute noch $amount';
  }

  @override
  String reportGoalDone(String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'für heute erledigt',
      'week': 'für die Woche erledigt',
      'month': 'für den Monat erledigt',
      'year': 'für das Jahr erledigt',
      'other': 'erledigt',
    });
    return '$_temp0';
  }

  @override
  String reportGoalLeft(String amount) {
    return '$amount übrig';
  }

  @override
  String reportGoalLeftIn(String amount, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'heute',
      'week': 'diese Woche',
      'month': 'diesen Monat',
      'year': 'dieses Jahr',
      'other': '',
    });
    return '$amount übrig $_temp0';
  }

  @override
  String reportGoalOver(String amount) {
    return '$amount darüber';
  }

  @override
  String get reportGoalMet => 'Erreicht';

  @override
  String get reportGoalMissed => 'Verfehlt';

  @override
  String get reportGoalWithin => 'Im Rahmen';

  @override
  String get reportGoalOverWord => 'Überschritten';

  @override
  String reportGoalPeriodsMet(int met, int total, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'Tagen',
      'week': 'Wochen',
      'month': 'Monaten',
      'year': 'Jahren',
      'other': 'Zeiträumen',
    });
    String _temp1 = intl.Intl.selectLogic(period, {
      'day': 'Tag',
      'week': 'Woche',
      'month': 'Monat',
      'year': 'Jahr',
      'other': 'Zeitraum',
    });
    String _temp2 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$met von $total $_temp0 erreicht',
      one: '$met von 1 $_temp1 erreicht',
    );
    return '$_temp2';
  }

  @override
  String reportGoalPlanned(String value, String target) {
    return '$value von $target geplant';
  }

  @override
  String reportGoalGapDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get reportGoalGapNone => 'Noch nie';

  @override
  String get reportGoalGapLong => 'Über 1 Jahr';

  @override
  String reportGoalLimit(int limit) {
    return 'max. $limit';
  }

  @override
  String reportGoalStreak(int count) {
    return '$count in Folge';
  }

  @override
  String reportGoalStreakSpoken(int count, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'Tage',
      'week': 'Wochen',
      'month': 'Monate',
      'year': 'Jahre',
      'other': 'Zeiträume',
    });
    String _temp1 = intl.Intl.selectLogic(period, {
      'day': 'Tag',
      'week': 'Woche',
      'month': 'Monat',
      'year': 'Jahr',
      'other': 'Zeitraum',
    });
    String _temp2 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $_temp0 in Folge',
      one: '1 $_temp1 in Folge',
    );
    return '$_temp2';
  }

  @override
  String get reportGoalStateMet => 'erreicht';

  @override
  String get reportGoalStateOnPace => 'im Plan';

  @override
  String get reportGoalStateBehind => 'im Rückstand';

  @override
  String get reportGoalStateOver => 'darüber';

  @override
  String get reportGoalStateMissed => 'verfehlt';

  @override
  String get reportGoalStateNotStarted => 'nicht begonnen';

  @override
  String get reportGoalStatePlanned => 'geplant';

  @override
  String get reportGoalStateWithin => 'innerhalb des Limits';

  @override
  String get reportGoalStateDueSoon => 'bald fällig';

  @override
  String get reportGoalStatePastLimit => 'über dem Limit';

  @override
  String reportGoalsOnPace(int onPace, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$onPace/$total Ziele im Plan',
      one: '$onPace/1 Ziel im Plan',
    );
    return '$_temp0';
  }

  @override
  String reportGoalsMet(int met, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$met/$total Ziele erreicht',
      one: '$met/1 Ziel erreicht',
    );
    return '$_temp0';
  }

  @override
  String get reportInsightAttention => 'Braucht Aufmerksamkeit';

  @override
  String get reportInsightNotable => 'Einen Blick wert';

  @override
  String get reportInsightObservation => 'Gut zu wissen';

  @override
  String get reportInsightInfo => 'Zur Information';

  @override
  String get reportInsightBills => 'Rechnungen';

  @override
  String get reportInsightNextTrip => 'Nächste Reise';

  @override
  String reportInsightBehind(String progress, String more) {
    return '$progress, $more';
  }

  @override
  String reportInsightOver(String progress, String period, String over) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'heute',
      'week': 'diese Woche',
      'month': 'diesen Monat',
      'year': 'dieses Jahr',
      'other': '',
    });
    return '$progress $_temp0, $over';
  }

  @override
  String reportInsightDone(String progress, String done) {
    return '$progress, $done';
  }

  @override
  String reportInsightStreakEnded(int count, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'day': 'Tagen',
      'week': 'Wochen',
      'month': 'Monaten',
      'year': 'Jahren',
      'other': 'Zeiträumen',
    });
    String _temp1 = intl.Intl.selectLogic(period, {
      'day': 'Tag',
      'week': 'Woche',
      'month': 'Monat',
      'year': 'Jahr',
      'other': 'Zeitraum',
    });
    String _temp2 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'die Serie von $count $_temp0 ist gerissen',
      one: 'die Serie von 1 $_temp1 ist gerissen',
    );
    return '$_temp2';
  }

  @override
  String reportInsightAllowance(String left, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$left von $total Tagen übrig',
      one: '$left von 1 Tag übrig',
    );
    return '$_temp0';
  }

  @override
  String reportInsightMonthsToGo(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: 'noch $months Monate',
      one: 'noch 1 Monat',
    );
    return '$_temp0';
  }

  @override
  String reportInsightAllowanceUnused(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage ungenutzt',
      one: '1 Tag ungenutzt',
    );
    return '$_temp0';
  }

  @override
  String reportInsightDaysLeftInYear(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'noch $days Tage im Jahr',
      one: 'noch 1 Tag im Jahr',
    );
    return '$_temp0';
  }

  @override
  String reportInsightGapOverdue(int days, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage seit dem letzten Mal',
      one: '1 Tag seit dem letzten Mal',
    );
    return '$_temp0, das Limit ist $limit';
  }

  @override
  String reportInsightGapOverdueLong(int limit) {
    return 'über ein Jahr seit dem letzten Mal, das Limit ist $limit';
  }

  @override
  String reportInsightGapDue(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'fällig in $days Tagen',
      one: 'fällig in 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String reportInsightExpires(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'läuft in $days Tagen ab',
      one: 'läuft in 1 Tag ab',
      zero: 'läuft heute ab',
    );
    return '$_temp0';
  }

  @override
  String reportInsightExpired(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'vor $days Tagen abgelaufen',
      one: 'vor 1 Tag abgelaufen',
      zero: 'heute abgelaufen',
    );
    return '$_temp0';
  }

  @override
  String reportInsightUnmarked(String day, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage nicht markiert, zuletzt $day',
      one: 'am $day nicht markiert',
    );
    return '$_temp0';
  }

  @override
  String reportInsightEpisodeNext(String day) {
    return 'nach dem üblichen Abstand das nächste Mal gegen $day';
  }

  @override
  String reportInsightWeekdays(
    String best,
    String bestPercent,
    String worst,
    String worstPercent,
  ) {
    return '$best $bestPercent %, $worst $worstPercent %';
  }

  @override
  String reportInsightLateEvenings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count späte Abende',
      one: '1 später Abend',
    );
    return '$_temp0 in einer Woche';
  }

  @override
  String reportInsightWeekend(String hours) {
    return '$hours am Wochenende';
  }

  @override
  String reportInsightShortNights(int count, String hours) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nächte',
      one: '1 Nacht',
    );
    return '$_temp0 unter $hours in einer Woche';
  }

  @override
  String reportInsightBedtimeSpread(String spread) {
    return 'Schlafenszeiten schwanken um $spread';
  }

  @override
  String reportInsightMeetingShare(String hours, String percent) {
    return '$hours, $percent % deiner Arbeitsstunden';
  }

  @override
  String reportInsightCancelled(int cancelled, int planned) {
    String _temp0 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$cancelled von $planned abgesagt',
      one: '$cancelled von 1 abgesagt',
    );
    return '$_temp0';
  }

  @override
  String reportInsightRestGap(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'eine Pause von $days Tagen',
      one: 'eine Pause von 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String reportInsightBillsAhead(String amount, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$amount fällig in den nächsten $days Tagen',
      one: '$amount fällig am nächsten Tag',
    );
    return '$_temp0';
  }

  @override
  String reportInsightBillsYear(String amount, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$amount im Jahr für $count Rechnungen',
      one: '$amount im Jahr für 1 Rechnung',
    );
    return '$_temp0';
  }

  @override
  String reportInsightTagGapLong(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage seit dem letzten Mal, länger als üblich',
      one: '1 Tag seit dem letzten Mal, länger als üblich',
    );
    return '$_temp0';
  }

  @override
  String reportInsightTagTop(String category, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'am häufigsten in $category, an $days Tagen',
      one: 'am häufigsten in $category, an 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String reportInsightLeadTime(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'meist $days Tage vorher gebucht',
      one: 'meist einen Tag vorher gebucht',
      zero: 'meist am selben Tag gebucht',
    );
    return '$_temp0';
  }

  @override
  String reportInsightOpenPast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nach Fälligkeit offen',
      one: '1 nach Fälligkeit offen',
    );
    return '$_temp0';
  }

  @override
  String reportInsightAhead(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anstehend bis $day',
      one: '1 anstehend bis $day',
    );
    return '$_temp0';
  }

  @override
  String reportInsightTrip(String title, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$title in $days Tagen',
      one: '$title morgen',
      zero: '$title heute',
    );
    return '$_temp0';
  }

  @override
  String reportInsightUpOn(String value, String percent, String period) {
    return '$value, $percent % mehr gegenüber $period';
  }

  @override
  String reportInsightDownOn(String value, String percent, String period) {
    return '$value, $percent % weniger gegenüber $period';
  }

  @override
  String reportDueOverdue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage überfällig',
      one: '1 Tag überfällig',
      zero: 'Heute überfällig',
    );
    return '$_temp0';
  }

  @override
  String reportDueIn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count Tagen fällig',
      one: 'In 1 Tag fällig',
      zero: 'Heute fällig',
    );
    return '$_temp0';
  }

  @override
  String reportDueExpires(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Läuft in $count Tagen ab',
      one: 'Läuft in 1 Tag ab',
      zero: 'Läuft heute ab',
    );
    return '$_temp0';
  }

  @override
  String reportDueExpired(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage abgelaufen',
      one: '1 Tag abgelaufen',
      zero: 'Heute abgelaufen',
    );
    return '$_temp0';
  }

  @override
  String get reportDueNotMarked => 'offen';

  @override
  String get reportDueLong => 'Vor über 1 Jahr';

  @override
  String reportLastSeenAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Tagen',
      one: 'gestern',
      zero: 'heute',
    );
    return '$_temp0';
  }

  @override
  String reportCancelledCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abgesagt',
      one: '1 abgesagt',
    );
    return '$_temp0';
  }

  @override
  String reportLeadTime(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage vorher gebucht',
      one: '1 Tag vorher gebucht',
      zero: 'am selben Tag gebucht',
    );
    return '$_temp0';
  }

  @override
  String reportDaysUntil(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in $count Tagen',
      one: 'morgen',
      zero: 'heute',
    );
    return '$_temp0';
  }

  @override
  String reportWorkingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Arbeitstage',
      one: '1 Arbeitstag',
    );
    return '$_temp0';
  }

  @override
  String reportPublicHolidays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Feiertage',
      one: '1 Feiertag',
    );
    return '$_temp0';
  }

  @override
  String reportCaptionCountedAs(String hours) {
    return 'Stunden inkl. $hours pauschal gezählt';
  }

  @override
  String reportCountedAsSpoken(String hours) {
    return 'einschließlich $hours pauschal gezählt';
  }

  @override
  String get reportSectionTags => 'Nach Schlagwort';

  @override
  String get reportSectionWhen => 'Wann';

  @override
  String get reportSectionBalance => 'Balance';

  @override
  String reportTagCount(String kind, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abende',
      one: '1 Abend',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Reisen',
      one: '1 Reise',
    );
    String _temp2 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wartungen',
      one: '1 Wartung',
    );
    String _temp3 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einheiten',
      one: '1 Einheit',
    );
    String _temp4 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-mal',
      one: 'einmal',
    );
    String _temp5 = intl.Intl.selectLogic(kind, {
      'social': '$_temp0',
      'trip': '$_temp1',
      'maintenance': '$_temp2',
      'workout': '$_temp3',
      'other': '$_temp4',
    });
    return '$_temp5';
  }

  @override
  String reportTagDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String reportTagLastSeen(String when, String day) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'today': 'heute',
      'yesterday': 'gestern',
      'other': 'zuletzt $day',
    });
    return '$_temp0';
  }

  @override
  String reportTagSpoken(String name, String facts) {
    return 'Schlagwort $name, $facts';
  }

  @override
  String reportTagName(String name) {
    return 'Schlagwort $name';
  }

  @override
  String reportTagsMoreSpoken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Schlagwörter',
      one: '1 weiteres Schlagwort',
    );
    return '$_temp0';
  }

  @override
  String get reportTagsLessSpoken => 'Weniger Schlagwörter anzeigen';

  @override
  String reportWhenBusiest(String weekday, String hours) {
    return 'Meist: $weekday · $hours';
  }

  @override
  String reportWhenSpoken(String weekday, String from, String to, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tagen mit Uhrzeit',
      one: '1 Tag mit Uhrzeit',
    );
    return 'Wann. Häufigster Tag $weekday, häufigste Stunde $from bis $to, aus $_temp0.';
  }

  @override
  String reportBalanceSpoken(String area, String hours, String percent) {
    return '$area, $hours, $percent der Stunden';
  }

  @override
  String get reportCompareWith => 'Vergleichen mit';

  @override
  String get reportComparePrevious => 'Vorheriger Zeitraum';

  @override
  String get reportCompareLastYear => 'Gleicher Zeitraum im Vorjahr';

  @override
  String get reportCompareNoViews => 'Keine gespeicherten Ansichten';

  @override
  String reportCaptionBeside(String view) {
    return 'neben $view';
  }

  @override
  String get reportLegendLastYear => 'Vorjahr';

  @override
  String reportTrendLastYearSpoken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Termine',
      one: '1 Termin',
    );
    return 'gleicher Zeitraum im Vorjahr, $_temp0';
  }

  @override
  String get reportPeriodLastYear => 'Letztes Jahr';

  @override
  String get reportSectionRecords => 'Rekorde';

  @override
  String get reportSectionMonths => 'Monate';

  @override
  String get calendarSettingsReportTitle => 'Berichtskarten';

  @override
  String get calendarSettingsReportDescription =>
      'Welche Karten der Bericht zeigt und in welcher Reihenfolge';

  @override
  String get reportCardsSectionTitle => 'Karten';

  @override
  String get reportCardsReset => 'Auf Standard zurücksetzen';

  @override
  String get reportCardsResetDone => 'Reihenfolge und Karten zurückgesetzt';

  @override
  String get reportRecordBusiestMonth => 'Stärkster Monat';

  @override
  String get reportRecordBusiestWeek => 'Stärkste Woche';

  @override
  String get reportRecordSocialMonth => 'Geselligster Monat';

  @override
  String get reportRecordMoneyMonth => 'Höchste Ausgaben';

  @override
  String get reportRecordLongestTrip => 'Längste Reise';

  @override
  String get reportRecordLongestStreak => 'Längste Serie';

  @override
  String get reportRecordLongestGap => 'Längste Lücke';

  @override
  String reportRecordCaption(String subject, String value) {
    return '$subject · $value';
  }

  @override
  String reportRecordSpoken(String record, String subject, String value) {
    return '$record: $subject, $value';
  }

  @override
  String reportYearSpan(String first, String last) {
    return '$first – $last';
  }

  @override
  String reportDayRangeSameMonth(String month, String first, String last) {
    return '$first.–$last. $month';
  }

  @override
  String reportYearSpanSpoken(String first, String last) {
    return 'vom $first bis $last';
  }

  @override
  String reportYearDaySpoken(String day) {
    return 'am $day';
  }

  @override
  String reportYearMonthsSpoken(String category, String span, String months) {
    return '$category, $span. Nach Monat: $months.';
  }

  @override
  String reportYearMonthValue(String month, String value) {
    return '$month $value';
  }

  @override
  String reportGoalLongestStreak(int count) {
    return 'längste Serie $count';
  }

  @override
  String reportGoalLongestStreakSpoken(String period, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wochen',
      one: '1 Woche',
    );
    String _temp2 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Monate',
      one: '1 Monat',
    );
    String _temp3 = intl.Intl.selectLogic(period, {
      'day': 'längste Serie $_temp0',
      'week': 'längste Serie $_temp1',
      'month': 'längste Serie $_temp2',
      'other': 'längste Serie $count',
    });
    return '$_temp3';
  }

  @override
  String reportBalanceLastYear(String hours) {
    return 'Vorjahr $hours';
  }

  @override
  String reportBalanceLastYearSpoken(
    String area,
    String hours,
    String lastHours,
  ) {
    return '$area, $hours, Vorjahr $lastHours';
  }

  @override
  String get howToUseAntaDesc => 'Kalender, Notizen, Backup und Einstellungen';

  @override
  String get guideHubIntro =>
      'Drei kurze Leitfäden. Die Suche hier durchsucht alle drei auf einmal.';

  @override
  String get guideHubSectionGuides => 'Leitfäden';

  @override
  String get guideBookCalendarCaption =>
      'Der Bildschirm, Ereignisse, Erinnerungen, Anwesenheit, die Übersicht, ein Übungskalender';

  @override
  String get guideBookNotesTitle => 'Notizen und der Editor';

  @override
  String get guideBookNotesCaption =>
      'Ordner, Schreiben, Markdown, Listen, eigene Kurzbefehle, das Kassenbuch, Autovervollständigung, Zähler';

  @override
  String get guideBookAppTitle => 'Backup, Sync und Einstellungen';

  @override
  String get guideBookAppCaption =>
      'Das Hauptmenü, eine Kopie deiner Notizen, Sync zwischen Telefonen, die Einstellungen';

  @override
  String get notesGuideIntro =>
      'Tippe auf eine Seite. Jedes Beispiel zeigt, was du tippst und was daraus wird.';

  @override
  String get appGuideIntro =>
      'Tippe auf eine Seite. Nichts hier ändert eine Einstellung.';

  @override
  String get guideExampleTyped => 'Du tippst';

  @override
  String get guideExampleShown => 'Du bekommst';

  @override
  String get notesGuidePageBasics => 'Ordner und Notizen';

  @override
  String get notesGuidePageBasicsCaption =>
      'Eine Notiz anlegen, wiederfinden, verschieben, etikettieren, löschen';

  @override
  String get notesGuideBasicsLead =>
      'ANTA bewahrt Notizen in Ordnern auf, wie Blätter in Mappen. Auf dem ersten Bildschirm liegen deine Ordner: Lege dort einen an, und deine Notizen kommen hinein.';

  @override
  String get notesGuideBasicsCreateTitle => 'Eine Notiz anlegen';

  @override
  String notesGuideBasicsCreateBody(String newNote) {
    return 'Öffne einen Ordner und tippe unten auf „$newNote“. Die Notiz öffnet sich sofort und wird vom ersten Buchstaben an gespeichert. Ein Titel kann später kommen: Tippe oben auf den Titel, um ihn festzulegen.';
  }

  @override
  String get notesGuideBasicsFoldersTitle => 'Ordner in Ordnern';

  @override
  String notesGuideBasicsFoldersBody(String newFolder) {
    return '„$newFolder“ legt einen Ordner dort an, wo du bist. Ordner können Ordner enthalten, so kann eine Mappe Abschnitte haben. Tippe auf einen Ordner, um hineinzugehen; der Pfeil oben bringt dich wieder hinaus.';
  }

  @override
  String get notesGuideBasicsSavedTitle =>
      'Es gibt keine Speichern-Schaltfläche';

  @override
  String notesGuideBasicsSavedBody(String saveStatusSaved) {
    return 'Eine Notiz speichert sich ein paar Sekunden nach dem letzten Tippen von selbst, und noch einmal, wenn du sie verlässt. Das Wort oben in der Notiz sagt „$saveStatusSaved“, wenn es erledigt ist.';
  }

  @override
  String get notesGuideBasicsReopenTitle => 'ANTA öffnet, wo du aufgehört hast';

  @override
  String get notesGuideBasicsReopenBody =>
      'Schließe die App mitten in einer Notiz, und sie kommt zu dieser Notiz zurück, in derselben Zeile. Auch Ordner merken sich ihre Stelle.';

  @override
  String get notesGuideBasicsMenuTitle => 'Das ⋮-Menü eines Ordners';

  @override
  String notesGuideBasicsMenuBody(
    String renameFolder,
    String moveToFolder,
    String sortBy,
    String shareFolder,
    String importNoteOrFolder,
    String select,
  ) {
    return '„$renameFolder“, „$moveToFolder“, „$sortBy“, „$shareFolder“ und „$importNoteOrFolder“ stehen im ⋮ oben in einem Ordner; das ⋮ des ersten Bildschirms hat nur „$sortBy“, „$select“ und „$importNoteOrFolder“. Mit „$select“ wählst du mehrere Notizen auf einmal aus.';
  }

  @override
  String get notesGuideBasicsHoldTitle =>
      'Gedrückt halten, um mehrere auszuwählen';

  @override
  String notesGuideBasicsHoldBody(
    String moveSelected,
    String labelSelected,
    String shareSelected,
    String deleteSelected,
  ) {
    return 'Halte eine Notiz oder einen Ordner gedrückt, um sie auszuwählen, und tippe dann auf weitere. Eine Leiste erscheint mit „$moveSelected“, „$labelSelected“, „$shareSelected“ und „$deleteSelected“ für die ganze Auswahl.';
  }

  @override
  String get notesGuideBasicsSortTitle => 'Sortieren und anordnen';

  @override
  String notesGuideBasicsSortBody(String sortNotes, String sortByCustom) {
    return '„$sortNotes“ ordnet einen Ordner nach Titel, nach Datum oder nach Farbetikett. Wähle „$sortByCustom“, um Notizen und Ordner selbst anzuordnen – durch Ziehen.';
  }

  @override
  String get notesGuideBasicsLabelsTitle => 'Farbetiketten';

  @override
  String notesGuideBasicsLabelsBody(String labelAction, String sortByLabel) {
    return '„$labelAction“ gibt einer Notiz oder einem Ordner eine Farbe, gezeichnet als Streifen an der Kante. Sortieren nach „$sortByLabel“ gruppiert sie nach Farbe.';
  }

  @override
  String get notesGuideBasicsDeleteTitle => 'Löschen';

  @override
  String notesGuideBasicsDeleteBody(String guideBookAppTitle) {
    return 'Löschen fragt zuerst, und dann ist es endgültig: Es gibt keinen Papierkorb, aus dem eine Notiz zurückkäme. Ein gelöschter Ordner nimmt seine Notizen mit. Der Weg zurück ist ein Backup – der Leitfaden „$guideBookAppTitle“ zeigt, wie du eines anlegst.';
  }

  @override
  String get notesGuideBasicsSearchTitle => 'Eine Notiz finden';

  @override
  String get notesGuideBasicsSearchBody =>
      'Die Lupe oben durchsucht jeden Ordner: Titel und den Text in den Notizen. Tippe auf einen Treffer, um die Notiz zu öffnen.';

  @override
  String get notesGuideBasicsAllTitle => 'Alle Notizen, zuletzt verwendete';

  @override
  String notesGuideBasicsAllBody(String allNotes, String recent) {
    return 'Der erste Ordner hat zwei Zeilen, die keine Ordner sind: „$allNotes“ zeigt jede Notiz an einem Ort, „$recent“ die, die du zuletzt angefasst hast.';
  }

  @override
  String get notesGuidePageEditor => 'Eine Notiz schreiben';

  @override
  String get notesGuidePageEditorCaption =>
      'Der Bildschirm, die Leiste über der Tastatur, das ⋮-Menü, Rückgängig, Suchen';

  @override
  String get notesGuideEditorLead =>
      'Eine Notiz ist eine Seite Text. Ein paar Zeichen geben ihr Form, und die Leiste über der Tastatur tippt sie für dich.';

  @override
  String get notesGuideEditorLiveTitle => 'Du siehst das Ergebnis beim Tippen';

  @override
  String get notesGuideEditorLiveBody =>
      'Tippe **fett**, und die Sterne verschwinden – übrig bleibt fetter Text. Die Zeichen erscheinen nur in der Zeile wieder, in der du gerade bist, damit du sie ändern kannst; gehst du weiter, verstecken sie sich.';

  @override
  String get notesGuideEditorBarTitle => 'Die Leiste über der Tastatur';

  @override
  String notesGuideEditorBarBody(
    String headers,
    String bulletList,
    String checkbox,
  ) {
    return 'Jede Schaltfläche schreibt eine Form für dich – „$headers“, „$bulletList“, „$checkbox“ –, sodass du dir kein Zeichen merken musst. Markiere zuerst Text, und die Form legt sich darum. Die Leiste lässt sich seitwärts schieben; rechts kommt mehr.';
  }

  @override
  String get notesGuideEditorUndoTitle => 'Rückgängig und Wiederholen';

  @override
  String get notesGuideEditorUndoBody =>
      'Die beiden Pfeile auf der Leiste nehmen deine letzten Änderungen zurück oder stellen sie wieder her, so viele Schritte du brauchst.';

  @override
  String get notesGuideEditorTitleTitle => 'Der Titel';

  @override
  String get notesGuideEditorTitleBody =>
      'Tippe oben auf den Titel, um ihn zu ändern. Zwei Notizen in einem Ordner können nicht denselben Titel tragen; ANTA sagt es dir, wenn das passieren würde.';

  @override
  String get notesGuideEditorMenuTitle => 'Das ⋮-Menü';

  @override
  String notesGuideEditorMenuBody(
    String shareNote,
    String moveToFolder,
    String labelAction,
    String openFolder,
    String deleteNote,
  ) {
    return '„$shareNote“ gibt den Text an eine andere App, „$moveToFolder“ legt die Notiz woanders ab, „$labelAction“ färbt sie, „$openFolder“ zeigt, wo sie liegt, und „$deleteNote“ entfernt sie – nach einer Rückfrage.';
  }

  @override
  String get notesGuideEditorFindTitle => 'In dieser Notiz suchen';

  @override
  String get notesGuideEditorFindBody =>
      'Die Lupe oben durchsucht nur diese Notiz. Die Pfeile springen von Treffer zu Treffer, ein Tipp auf die Trefferzahl listet alle, und das Optionsmenü der Leiste blendet ein Feld zum Ersetzen ein.';

  @override
  String get notesGuideEditorFontTitle => 'Größere oder kleinere Schrift';

  @override
  String notesGuideEditorFontBody(
    String decreaseFontSize,
    String increaseFontSize,
  ) {
    return '„$decreaseFontSize“ und „$increaseFontSize“ auf der Leiste ändern die Schriftgröße aller Notizen. Die Schriftgröße deines Telefons kommt noch obendrauf.';
  }

  @override
  String get notesGuideEditorTapTitle => 'Was du antippen kannst';

  @override
  String get notesGuideEditorTapBody =>
      'Tippe auf ein Kontrollkästchen, um es abzuhaken, auf ein #Schlagwort, um jede Notiz damit zu finden, auf einen [[Notiz-Link]], um diese Notiz zu öffnen, auf eine \$\$-Summe, um zu sehen, was hineinfloss, auf einen Web-Link, um ihn zu öffnen.';

  @override
  String get notesGuidePageMarkdown => 'Markdown-Grundlagen';

  @override
  String get notesGuidePageMarkdownCaption =>
      'Überschriften, fett, Listen, Kontrollkästchen, Zitate, Links, Tabellen';

  @override
  String get notesGuideMarkdownLead =>
      'Markdown ist eine Handvoll Zeichen, die reinem Text Form geben. Tippe sie selbst, oder lass die Leiste das tun.';

  @override
  String get notesGuideExHeadingSource =>
      '# Beintag\n## Aufwärmen\nFünf Minuten auf dem Rad';

  @override
  String get notesGuideExHeadingCaption =>
      'Ein # und ein Leerzeichen beginnen eine Überschrift. Zwei machen eine kleinere.';

  @override
  String get notesGuideExEmphasisSource =>
      '**Schwerer** Tag, *lief gut*, ~~Rudern~~ ausgelassen, ==neuer Rekord==';

  @override
  String get notesGuideExEmphasisCaption =>
      'Zwei Sterne machen fett, ein Stern kursiv, zwei Tilden streichen durch, zwei Gleichheitszeichen heben hervor.';

  @override
  String get notesGuideExListSource => '- Kniebeuge\n- Bankdrücken\n- Rudern';

  @override
  String get notesGuideExListCaption =>
      'Ein Strich und ein Leerzeichen machen einen Aufzählungspunkt. Enter am Ende eines Punkts beginnt den nächsten; Enter auf einem leeren Punkt beendet die Liste.';

  @override
  String get notesGuideExNumberedSource =>
      '1. Aufwärmen\n2. Arbeitssätze\n3. Dehnen';

  @override
  String get notesGuideExNumberedCaption =>
      'Eine Zahl und ein Punkt machen eine nummerierte Liste. Enter zählt für dich weiter.';

  @override
  String get notesGuideExTaskSource => '- [ ] Wasser\n- [x] Protein';

  @override
  String notesGuideExTaskCaption(String checkbox) {
    return 'Strich, Leerzeichen und [ ] machen ein Kontrollkästchen. Tippe darauf, um es abzuhaken; die Schaltfläche „$checkbox“ der Leiste beginnt eines.';
  }

  @override
  String get notesGuideExQuoteSource => '> Technik vor Gewicht';

  @override
  String get notesGuideExQuoteCaption =>
      'Ein > hebt eine Zeile als Zitat ab, mit einem Balken links davon.';

  @override
  String get notesGuideExLinkSource => '[Programm](https://example.com)';

  @override
  String get notesGuideExLinkCaption =>
      'Der Text in eckigen Klammern, die Adresse in runden. Tippe auf den Text, um die Adresse zu öffnen.';

  @override
  String get notesGuideMarkdownTableTitle => 'Tabellen, ganz einfach';

  @override
  String notesGuideMarkdownTableBody(String shortcutTable) {
    return 'Zellen zwischen senkrechten Strichen bilden eine Tabellenzeile. ANTA setzt eine solche Zeile in einer Schrift mit fester Breite, damit die Spalten untereinanderstehen; die Schaltfläche „$shortcutTable“ der Leiste schreibt eine leere.';
  }

  @override
  String get notesGuidePageLists => 'Listen und Verschachteln';

  @override
  String get notesGuidePageListsCaption =>
      'Eine Liste fortsetzen, Punkte einrücken, wieder ausrücken, Kontrollkästchen';

  @override
  String get notesGuideListsLead =>
      'Die meisten Notizen sind Listen: Übungen, Sätze, Einkäufe. ANTA hält sie beim Tippen in Ordnung.';

  @override
  String get notesGuideExNestedSource =>
      '- Beine\n  - Kniebeuge 5×5\n  - Ausfallschritte\n- Rücken\n  - Kreuzheben';

  @override
  String get notesGuideExNestedCaption =>
      'Ein Punkt, der unter einem anderen eingerückt ist, ist verschachtelt. Er bekommt einen hohlen Kreis; eine dritte Ebene ein Quadrat.';

  @override
  String get notesGuideListsEnterTitle => 'Enter setzt die Liste fort';

  @override
  String get notesGuideListsEnterBody =>
      'Enter am Ende eines Punkts beginnt den nächsten auf derselben Ebene – bei einem Kontrollkästchen ein neues leeres Kästchen, bei einer Nummer die nächste Zahl. Enter auf einem leeren Punkt rückt ihn eine Ebene heraus; auf einem äußersten Punkt beendet es die Liste und macht daraus eine normale Zeile.';

  @override
  String get notesGuideListsNestTitle => 'Drei Wege zum Einrücken';

  @override
  String get notesGuideListsNestBody =>
      'Drücke auf einem leeren Punkt einmal die Leertaste, um ihn unter den Punkt darüber zu schieben. Oder wische die Zeile, in der du bist, nach rechts. Oder tippe auf den Einrück-Pfeil der Leiste. Nach links wischen, der Ausrück-Pfeil oder Enter auf einem leeren Punkt holt ihn wieder heraus.';

  @override
  String get notesGuideListsCapTitle => 'Immer nur eine Stufe';

  @override
  String get notesGuideListsCapBody =>
      'Ein Punkt kann eine Ebene tiefer stehen als der Punkt über ihm, nie mehr – so wandert keine Liste aus dem Bildschirm.';

  @override
  String get notesGuideListsTaskTitle => 'Abhaken';

  @override
  String get notesGuideListsTaskBody =>
      'Tippe auf ein Kontrollkästchen, um es abzuhaken, und noch einmal, um den Haken zu entfernen. Die Tastatur bleibt, wo sie ist – so lässt sich eine Satzliste mitten im Training abhaken.';

  @override
  String get notesGuidePageOwn => 'ANTAs eigenes Markdown';

  @override
  String get notesGuidePageOwnCaption =>
      'Schlagwörter, Hinweisblöcke, Farben, Platzhalter, Links zwischen Notizen, das heutige Datum';

  @override
  String get notesGuideOwnLead =>
      'Ein paar Formen sind ANTAs eigene. Jede hat auch eine Schaltfläche auf der Leiste.';

  @override
  String get notesGuideExTagSource => 'Kreuzheben 140 kg #pr #beintag';

  @override
  String get notesGuideExTagCaption =>
      'Ein Wort nach # ist ein Schlagwort. Tippe darauf, um jede Notiz zu finden, die es trägt.';

  @override
  String get notesGuideExCalloutSource =>
      '> [!TIP]\n> Vor den schweren Sätzen aufwärmen';

  @override
  String get notesGuideExCalloutCaption =>
      'Ein Zitat, das mit [!TIP] beginnt, wird ein farbiger Kasten mit Symbol. NOTE, WARNING, IMPORTANT, SUCCESS und QUESTION gehen an Stelle von TIP genauso.';

  @override
  String notesGuideExColourSource(String open, String close) {
    return '${open}red:Maximalkraft$close und ==green:erledigt==';
  }

  @override
  String notesGuideExColourCaption(String markdownColorsTitle) {
    return 'Ein Farbname vor dem Text färbt ihn; zwischen zwei Gleichheitszeichen färbt er die Hervorhebung. Die Namen sind red, orange, yellow, green, teal, blue, purple, pink und gray – oder deine eigenen aus „$markdownColorsTitle“.';
  }

  @override
  String notesGuideExGhostSource(String open, String close) {
    return 'Kniebeuge $open${open}Gewicht$close$close kg × $open${open}Wdh$close$close';
  }

  @override
  String notesGuideExGhostCaption(String shortcutGhostText) {
    return 'Text in doppelten geschweiften Klammern ist ein Platzhalter und wird blass angezeigt. Tippe ihn an und schreibe, um ihn auszufüllen – eine Vorlage für ein Training, das du wiederholst. Die Schaltfläche „$shortcutGhostText“ der Leiste legt einen an.';
  }

  @override
  String get notesGuideExWikiSource => 'Gleiches Aufwärmen wie [[Beintag]]';

  @override
  String get notesGuideExWikiCaption =>
      'Der Titel einer Notiz in doppelten eckigen Klammern verlinkt sie. Tippe darauf, um die Notiz zu öffnen; hat keine Notiz diesen Titel, sagt ANTA es.';

  @override
  String get notesGuideOwnDateTitle => 'Das heutige Datum';

  @override
  String notesGuideOwnDateBody(String currentDate) {
    return 'Die Schaltfläche „$currentDate“ der Leiste tippt das heutige Datum, so beginnt eine Tagebuchzeile von selbst.';
  }

  @override
  String get notesGuidePageMoney => 'Das Kassenbuch';

  @override
  String get notesGuidePageMoneyCaption =>
      'Zeilen, die mit \$ beginnen, werden zusammengerechnet';

  @override
  String notesGuideMoneyLead(
    String moneyLedgerEnabledLabel,
    String settingsRowEditor,
    String moneySection,
  ) {
    return 'Jede Notiz kann eine laufende Summe führen. Schalte zuerst „$moneyLedgerEnabledLabel“ in „$settingsRowEditor“ › „$moneySection“ ein; dann sind Zeilen, die mit \$ beginnen, das Kassenbuch, und alles andere bleibt gewöhnlicher Text.';
  }

  @override
  String get notesGuideExMoneyBasicSource =>
      '\$= 500 Budget\n\$- 40 Studio\n\$+ 25 Rückzahlung\n\$\$ übrig';

  @override
  String get notesGuideExMoneyBasicCaption =>
      '\$= setzt den Anfangsbetrag, \$- gibt aus, \$+ fügt hinzu – jede dieser Zeilen zeigt dahinter den Stand in Grau. \$\$ zeigt die Summe bis hier als farbigen Chip.';

  @override
  String get notesGuideExMoneyMonthsSource =>
      '## März\n\$= 500\n\$- 120 Schuhe\n\$? März';

  @override
  String get notesGuideExMoneyMonthsCaption =>
      '\$? zeigt, wie viel sich seit dem letzten \$= geändert hat. Ein \$= unter jeder Monatsüberschrift macht daraus ein monatliches Kassenbuch.';

  @override
  String get notesGuideExMoneyTargetSource =>
      '\$= 500\n\$! 300 Einkäufe\n\$- 120 Einkäufe\n\$!';

  @override
  String get notesGuideExMoneyTargetCaption =>
      '\$! mit einem Betrag setzt ein Ziel. Ein \$! allein zeigt, was davon nach den Ausgaben seit dem Ziel übrig ist – grün, solange darunter, rot darüber. Keines von beiden ändert den Stand.';

  @override
  String get notesGuideMoneyTapTitle => 'Auf eine Summe tippen';

  @override
  String get notesGuideMoneyTapBody =>
      'Tippe auf einen \$\$- oder \$?-Wert, um jede Zeile zu sehen, die hineingeflossen ist.';

  @override
  String get notesGuideMoneyMoreTitle => 'Malnehmen und Teilen';

  @override
  String get notesGuideMoneyMoreBody =>
      '\$* 1.19 multipliziert den Stand, etwa für eine Steuer; \$/ 2 teilt ihn, etwa für eine halbierte Rechnung.';

  @override
  String get notesGuideMoneySettingsTitle => 'Währung und Startguthaben';

  @override
  String notesGuideMoneySettingsBody(
    String settingsRowEditor,
    String moneySection,
    String moneyLedgerEnabledLabel,
  ) {
    return '„$settingsRowEditor“ › „$moneySection“ legt auch das Symbol, seine Stellung und ein Startguthaben fest, mit dem jede Notiz beginnt; eine einzelne Notiz kann ihre eigene Währung haben. Erscheinen \$-Zeilen als normaler Text, ist dort „$moneyLedgerEnabledLabel“ noch aus.';
  }

  @override
  String get notesGuideMoneyCalendarTitle => 'Im Kalender';

  @override
  String get notesGuideMoneyCalendarBody =>
      'Die verknüpfte Notiz eines Ereignisses zeigt ihr Geld im Kalender: ein Balken unter dem Tag und die Monatssumme in der Kopfzeile.';

  @override
  String get notesGuideMoneyButtonsTitle => 'Auf der Leiste';

  @override
  String notesGuideMoneyButtonsBody(
    String shortcutMoneyAdd,
    String shortcutMoneySubtract,
    String shortcutMoneyStart,
    String shortcutMoneyTotal,
    String shortcutMoneyChange,
    String shortcutMoneyTarget,
  ) {
    return 'Jede Kassenbuchzeile hat eine Schaltfläche: „$shortcutMoneyAdd“, „$shortcutMoneySubtract“, „$shortcutMoneyStart“, „$shortcutMoneyTotal“, „$shortcutMoneyChange“, „$shortcutMoneyTarget“.';
  }

  @override
  String get notesGuidePageBar => 'Die Leiste';

  @override
  String get notesGuidePageBarCaption =>
      'Schaltflächen umordnen, eigene Kurzbefehle, mehrere Leisten';

  @override
  String notesGuideBarLead(String settingsRowEditor) {
    return 'Die Leiste über der Tastatur gehört dir. Alles an ihr findest du in „$settingsRowEditor“.';
  }

  @override
  String get notesGuideBarShortcutsTitle => 'Kurzbefehle';

  @override
  String notesGuideBarShortcutsBody(String shortcuts) {
    return 'Jede Schaltfläche ist ein Kurzbefehl: Text, den sie schreibt oder um deine Markierung legt. Unter „$shortcuts“ ziehst du sie in eine neue Reihenfolge und versteckst die, die du nie brauchst.';
  }

  @override
  String get notesGuideBarOwnTitle => 'Dein eigener Kurzbefehl';

  @override
  String notesGuideBarOwnBody(String shortcuts, String page) {
    return 'Tippe auf der Seite „$shortcuts“ auf +, um einen anzulegen: Eine Zeile, die du oft schreibst – ein Satzformat, die Überschrift, mit der jeder Tag beginnt – wird zur Schaltfläche. „$page“ in dieser Anleitung zeigt, wie.';
  }

  @override
  String get notesGuideBarUtilityTitle => 'Hilfsschaltflächen';

  @override
  String notesGuideBarUtilityBody(String utilityButtons) {
    return 'Rückgängig, Wiederholen, Einrücken, Einfügen, Schriftgröße, Teilen, Zähler, Sprung nach oben oder unten: „$utilityButtons“ bestimmt, welche davon erscheinen und in welcher Reihenfolge.';
  }

  @override
  String get notesGuideBarReorderTitle => 'Aus der Notiz heraus umordnen';

  @override
  String notesGuideBarReorderBody(String reorderShortcuts) {
    return 'Die Schaltfläche „$reorderShortcuts“ der Leiste macht aus den Schaltflächen Chips, die du ziehen kannst – direkt in der Notiz.';
  }

  @override
  String get notesGuideBarProfilesTitle => 'Mehrere Leisten';

  @override
  String notesGuideBarProfilesBody(
    String manageBarProfiles,
    String switchBar,
    String perNoteBarAssignment,
  ) {
    return '„$manageBarProfiles“ hält mehr als eine Leiste bereit – eine fürs Training, eine fürs Geld. Ab zwei wechselt die Schaltfläche „$switchBar“ der Leiste die Leiste für die Notiz, in der du bist, und „$perNoteBarAssignment“ listet diese Zuordnungen.';
  }

  @override
  String get notesGuideBarLayoutTitle => 'Zwei Streifen oder einer';

  @override
  String notesGuideBarLayoutBody(String splitToolbar, String pinUndoRedo) {
    return '„$splitToolbar“ hält die Hilfsschaltflächen in einem eigenen Streifen rechts, der getrennt von deinen Kurzbefehlen scrollt; „$pinUndoRedo“ lässt Rückgängig und Wiederholen sichtbar, während der Rest der Leiste scrollt.';
  }

  @override
  String get notesGuidePageAutocomplete => 'Autovervollständigung';

  @override
  String get notesGuidePageAutocompleteCaption =>
      'Deine eigenen Wortlisten, angeboten beim Tippen';

  @override
  String get notesGuideAutocompleteLead =>
      'Gib ANTA deine Listen – Übungen, Mahlzeiten, Kunden –, und es bietet sie beim Tippen an; ein langer Name ist dann ein Tipp.';

  @override
  String get notesGuideAutoListsTitle => 'Eine Liste anlegen';

  @override
  String notesGuideAutoListsBody(
    String settingsRowEditor,
    String vocabularySection,
    String manageVocabularies,
  ) {
    return '„$settingsRowEditor“ › „$vocabularySection“ › „$manageVocabularies“: ein Eintrag pro Zeile. Eine Zeile, die mit ;; beginnt, ist eine Überschrift in der Liste und wird nie angeboten.';
  }

  @override
  String get notesGuideAutoTriggerTitle => '@ und ein paar Buchstaben tippen';

  @override
  String notesGuideAutoTriggerBody(String vocabularyTriggerLabel) {
    return 'Tippe nach einem Leerzeichen das Auslösezeichen („$vocabularyTriggerLabel“, @ solange du es nicht änderst) und den Anfang eines Worts: @ban bietet Bankdrücken an. Tippe auf den Vorschlag, und er wird für dich geschrieben, als normaler Text.';
  }

  @override
  String get notesGuideAutoScopeTitle => 'Nur eine Liste';

  @override
  String get notesGuideAutoScopeBody =>
      'Nenne die Liste vor einem Doppelpunkt – @übungen:ban – und nur diese Liste wird durchsucht. Zwei Namen mit Komma dazwischen durchsuchen beide.';

  @override
  String get notesGuideAutoGhostTitle => 'Platzhalter kennen deine Listen';

  @override
  String notesGuideAutoGhostBody(String open, String close) {
    return 'Tippe auf einen Platzhalter, dessen Name zu einer deiner Listen passt – $open$openübungen$close$close für eine Liste namens Übungen –, und diese Liste wird angeboten. Eine Vorlage füllt sich mit zwei Tipps.';
  }

  @override
  String get notesGuideAutoIgnoreTitle => 'Ignorieren kostet nichts';

  @override
  String notesGuideAutoIgnoreBody(String vocabularySuggestionsLabel) {
    return 'Tippe einfach weiter, und die Vorschläge schließen sich; was du getippt hast, bleibt genau so. „$vocabularySuggestionsLabel“ schaltet die Funktion ganz ab.';
  }

  @override
  String get notesGuidePageCounters => 'Zähler';

  @override
  String get notesGuidePageCountersCaption =>
      'Zahlen, die du hochtippst: Sätze, Gläser Wasser, Tage in Folge';

  @override
  String get notesGuideCountersLead =>
      'Ein Zähler ist eine Zahl mit eigenem +. Führe einen für die ganze App oder einen pro Notiz.';

  @override
  String get notesGuideCountersMakeTitle => 'Einen anlegen';

  @override
  String notesGuideCountersMakeBody(String counterSettings, String addCounter) {
    return '„$counterSettings“ im Hauptmenü listet deine Zähler. „$addCounter“ legt einen neuen an: Gib ihm einen Namen, einen Startwert und eine Schrittweite.';
  }

  @override
  String get notesGuideCountersNoteTitle => 'Aus einer Notiz heraus';

  @override
  String notesGuideCountersNoteBody(String counterInsertTooltip) {
    return 'Die Schaltfläche „$counterInsertTooltip“ der Leiste listet deine Zähler. Wähle einen: Er geht um einen Schritt hoch, und die neue Zahl wird dort getippt, wo du bist.';
  }

  @override
  String get notesGuideCountersScopeTitle => 'Für die ganze App oder pro Notiz';

  @override
  String notesGuideCountersScopeBody(
    String counterScope,
    String counterScopeGlobalDesc,
    String counterScopePerNoteDesc,
  ) {
    return '„$counterScope“ entscheidet: „$counterScopeGlobalDesc“ oder „$counterScopePerNoteDesc“ – ein Zählstand, der nur dieser Notiz gehört.';
  }

  @override
  String get notesGuideCountersPinTitle => 'Anheften';

  @override
  String notesGuideCountersPinBody(String pinCounter) {
    return '„$pinCounter“ hält einen Zähler oben in der Liste, sodass die, die du täglich brauchst, zuerst kommen.';
  }

  @override
  String get notesGuideCountersShortcutTitle => 'Eine Schaltfläche, die zählt';

  @override
  String notesGuideCountersShortcutBody(
    String shortcuts,
    String counterBindingsTitle,
  ) {
    return 'Unter „$shortcuts“ lässt sich ein Kurzbefehl an einen Zähler binden („$counterBindingsTitle“): Jeder Tipp kann ihn hochzählen und seine Zahl tippen – eine Schaltfläche pro Satz.';
  }

  @override
  String get notesGuidePageSettings => 'Wo die Einstellungen sind';

  @override
  String get notesGuidePageSettingsCaption => 'Welche Seite was enthält';

  @override
  String notesGuideSettingsLead(String settingsHubTitle) {
    return '„$settingsHubTitle“ im Hauptmenü listet jede Einstellungsseite mit einer Zeile dazu, was sie enthält; die Suche dort findet die Seite, die einen Abschnitt enthält, über dessen Namen.';
  }

  @override
  String notesGuideSettingsGeneralTitle(String settingsRowGeneral) {
    return '„$settingsRowGeneral“';
  }

  @override
  String notesGuideSettingsGeneralBody(String settingsRowGeneralDesc) {
    return '$settingsRowGeneralDesc: was sich beim Start öffnet, wie ein Ordner seine Notizen zeigt, Zeilenumbruch und Zeilennummern im Editor.';
  }

  @override
  String notesGuideSettingsEditorTitle(String settingsRowEditor) {
    return '„$settingsRowEditor“';
  }

  @override
  String get notesGuideSettingsEditorBody =>
      'Kurzbefehle und Leisten, Hilfsschaltflächen, Textfarben, das Kassenbuch, die Autovervollständigung – jeder Abschnitt lässt sich zusammenklappen.';

  @override
  String notesGuideSettingsCountersTitle(String counterSettings) {
    return '„$counterSettings“';
  }

  @override
  String get notesGuideSettingsCountersBody =>
      'Deine Zähler, ihre Anheftungen und welche von ihnen pro Notiz zählen.';

  @override
  String notesGuideSettingsLookTitle(
    String settingsRowTheme,
    String languageSettings,
  ) {
    return '„$settingsRowTheme“ und „$languageSettings“';
  }

  @override
  String notesGuideSettingsLookBody(String themeSettingsDesc) {
    return '$themeSettingsDesc; Englisch, Deutsch oder Rumänisch. Die Schriftgröße folgt der Einstellung deines Telefons.';
  }

  @override
  String get notesGuideSettingsPerNoteTitle =>
      'Was eine einzelne Notiz haben kann';

  @override
  String get notesGuideSettingsPerNoteBody =>
      'Ihre eigene Leiste, ihre eigene Währung und ihre eigenen Zählerstände. Alles andere teilen sich alle Notizen.';

  @override
  String get notesGuidePageSafe => 'Nichts geht verloren';

  @override
  String get notesGuidePageSafeCaption =>
      'Automatisches Speichern, das Wort oben, der Weg zurück';

  @override
  String get notesGuideSafeLead =>
      'ANTA ist so gebaut, dass eine Notiz alles überlebt, außer dem Verlust des Telefons.';

  @override
  String get notesGuideSafeAutosaveTitle => 'Gespeichert, während du schreibst';

  @override
  String get notesGuideSafeAutosaveBody =>
      'Text wird ein paar Sekunden nach dem letzten Tippen gespeichert und jede halbe Minute, solange du weiterschreibst; ein fehlgeschlagenes Speichern wird wiederholt. Höchstens der letzte Moment könnte fehlen.';

  @override
  String get notesGuideSafeStatusTitle => 'Das Wort oben';

  @override
  String notesGuideSafeStatusBody(
    String saveStatusSaved,
    String saveStatusSaving,
    String saveStatusUnsaved,
    String saveStatusError,
  ) {
    return '„$saveStatusSaved“, „$saveStatusSaving“ oder „$saveStatusUnsaved“ – ein Blick sagt, wie es steht. „$saveStatusError“ heißt, das Telefon hat das Schreiben verweigert; schreib weiter, ANTA versucht es erneut.';
  }

  @override
  String get notesGuideSafeEventTitle => 'Eine Notiz zu einem Ereignis';

  @override
  String notesGuideSafeEventBody(String eventLinkedNote) {
    return 'Ein Kalenderereignis kann auf eine Notiz zeigen („$eventLinkedNote“): der Plan für eine Einheit, was sie gekostet hat. Öffne die Notiz vom Ereignis aus.';
  }

  @override
  String get notesGuideSafeBackupTitle => 'Der Weg zurück';

  @override
  String notesGuideSafeBackupBody(String guideBookAppTitle) {
    return 'Löschen ist endgültig, und dieses Telefon hält die einzige Kopie, bis du eine weitere anlegst. Der Leitfaden „$guideBookAppTitle“ zeigt, wie du sicherst und wie du synchronisierst.';
  }

  @override
  String get notesGuideSafeShareTitle => 'Text herausbekommen';

  @override
  String notesGuideSafeShareBody(String shareNote) {
    return '„$shareNote“ gibt eine Notiz an jede andere App – eine Nachricht, E-Mail, einen Cloud-Speicher – als Datei im Format, das du wählst.';
  }

  @override
  String get appGuidePageMenu => 'Das Hauptmenü';

  @override
  String get appGuidePageMenuCaption => 'Was das ☰ oben links enthält';

  @override
  String get appGuideMenuLead =>
      'Das ☰ oben links öffnet das Hauptmenü. Es listet Orte, keine Einstellungen: Jede Zeile ist ein Ort, zu dem du gehst.';

  @override
  String get appGuideMenuAccountTitle => 'Die oberste Zeile';

  @override
  String appGuideMenuAccountBody(
    String drawerAccountNotSyncing,
    String sharingSettings,
  ) {
    return 'Sobald du angemeldet bist, zeigt die oberste Zeile, wer das ist und wann die Notizen zuletzt synchronisiert wurden – oder „$drawerAccountNotSyncing“, solange Sync aus ist. Tippe darauf, um „$sharingSettings“ zu öffnen.';
  }

  @override
  String appGuideMenuCalendarTitle(String calendar) {
    return '„$calendar“';
  }

  @override
  String appGuideMenuCalendarBody(
    String calendar,
    String calendarOverview,
    String reportTitle,
    String calendarCategories,
    String alertsTitle,
    String calendarGuideTitle,
    String howToUseAnta,
  ) {
    return '„$calendar“ ist der Monat; „$calendarOverview“ listet, was kommt; „$reportTitle“ zählt, was du getan hast; „$calendarCategories“ und „$alertsTitle“ verwalten Farben und Erinnerungen. Der Leitfaden „$calendarGuideTitle“ unter „$howToUseAnta“ erklärt sie alle.';
  }

  @override
  String appGuideMenuNotesTitle(String notes) {
    return '„$notes“';
  }

  @override
  String appGuideMenuNotesBody(String counterSettings) {
    return '„$counterSettings“: deine Zähler und ihre Anheftungen. Die Notizen selbst stehen nicht im Menü: Sie sind die Ordner, mit denen ANTA startet.';
  }

  @override
  String appGuideMenuAppTitle(String appGroupLabel) {
    return '„$appGroupLabel“';
  }

  @override
  String appGuideMenuAppBody(
    String settingsHubTitle,
    String howToUseAnta,
    String about,
  ) {
    return '„$settingsHubTitle“ enthält jede Einstellung; „$howToUseAnta“ ist dieser Leitfaden; „$about“ zeigt die Version.';
  }

  @override
  String get appGuideMenuBackTitle => 'Zurückgehen';

  @override
  String get appGuideMenuBackBody =>
      'Der Pfeil oben links oder die Zurück-Geste deines Telefons bringt dich dorthin zurück, wo du hergekommen bist – am Ende zu deinen Ordnern.';

  @override
  String get appGuidePageSettings => 'Einstellungen, die man kennen sollte';

  @override
  String get appGuidePageSettingsCaption =>
      'Dunkelmodus, Sprache, Berechtigungen, wo ANTA öffnet';

  @override
  String appGuideSettingsLead(String settingsHubTitle) {
    return 'Alles steht in „$settingsHubTitle“. Diese Einstellungen begegnen dir zuerst.';
  }

  @override
  String appGuideSettingsThemeTitle(String settingsRowTheme) {
    return '„$settingsRowTheme“';
  }

  @override
  String appGuideSettingsThemeBody(String themeSettingsDesc) {
    return '$themeSettingsDesc. Die Schriftgröße folgt der Einstellung deines Telefons.';
  }

  @override
  String appGuideSettingsLanguageTitle(String languageSettings) {
    return '„$languageSettings“';
  }

  @override
  String get appGuideSettingsLanguageBody =>
      'Englisch, Deutsch oder Rumänisch, für die ganze App.';

  @override
  String appGuideSettingsPermissionsTitle(String permissionsTitle) {
    return '„$permissionsTitle“';
  }

  @override
  String appGuideSettingsPermissionsBody(String settingsHubTitle) {
    return 'Was das Telefon ANTA erlaubt: einen Alarm klingeln lassen, eine Mitteilung zeigen und so weiter. Fehlt etwas Nötiges, sagt es die Zeile „$settingsHubTitle“ im Hauptmenü in Rot.';
  }

  @override
  String get appGuideSettingsStartupTitle => 'Wo ANTA öffnet';

  @override
  String appGuideSettingsStartupBody(
    String settingsRowGeneral,
    String startupSection,
    String restoreLocation,
  ) {
    return '„$settingsRowGeneral“ › „$startupSection“: „$restoreLocation“ wählt, was ANTA nach einem Neustart wieder öffnet – alles, nur deine Ordner und Notizen oder nichts, sodass es immer bei deinen Ordnern startet.';
  }

  @override
  String get appGuideSettingsSearchTitle => 'Eine Einstellung finden';

  @override
  String appGuideSettingsSearchBody(
    String settingsHubTitle,
    String autoSaveSection,
    String languageSettings,
  ) {
    return 'Die Suche oben in „$settingsHubTitle“ durchsucht die Abschnitte jeder Seite: Tippe „$autoSaveSection“ oder „$languageSettings“, und die Seite, die es enthält, erscheint.';
  }

  @override
  String get appGuidePageBackup => 'Backup und Wiederherstellen';

  @override
  String get appGuidePageBackupCaption =>
      'Eine Kopie deiner Notizen anlegen und zurückholen';

  @override
  String get appGuideBackupLead =>
      'Deine Notizen liegen auf diesem Telefon. Eine Kopie woanders macht aus einem verlorenen Telefon ein Ärgernis statt eines Verlusts.';

  @override
  String get appGuideBackupFolderTitle => 'Einen Ordner teilen';

  @override
  String appGuideBackupFolderBody(String shareFolder) {
    return '„$shareFolder“ im ⋮-Menü eines Ordners packt ihn – Notizen und Unterordner – in eine Datei und gibt sie an eine andere App: Maile sie dir selbst oder lege sie in einem Cloud-Speicher ab.';
  }

  @override
  String get appGuideBackupSelectionTitle => 'Eine Auswahl teilen';

  @override
  String appGuideBackupSelectionBody(String shareSelected) {
    return 'Halte gedrückt, um Notizen und Ordner auszuwählen, dann packt „$shareSelected“ genau diese.';
  }

  @override
  String get appGuideBackupImportTitle => 'Eine Kopie zurückholen';

  @override
  String appGuideBackupImportBody(String importNoteOrFolder) {
    return '„$importNoteOrFolder“ im ⋮-Menü eines Ordners nimmt eine solche Datei – oder eine einzelne Markdown-Datei – und legt ihre Notizen in diesem Ordner ab.';
  }

  @override
  String get appGuideBackupDatabaseTitle => 'Die ganze Datenbank';

  @override
  String appGuideBackupDatabaseBody(
    String settingsRowDatabases,
    String settingsHubTitle,
    String shareDatabase,
    String importDatabase,
  ) {
    return '„$settingsRowDatabases“ in „$settingsHubTitle“ arbeitet mit allem auf einmal: „$shareDatabase“ verschickt eine Datei mit jedem Ordner, jeder Notiz, jedem Zähler und jedem Ereignis; „$importDatabase“ lädt eine solche Datei als neue Datenbank.';
  }

  @override
  String get appGuideBackupSwitchTitle => 'Mehr als eine Datenbank';

  @override
  String get appGuideBackupSwitchBody =>
      'Du kannst mehrere Datenbanken führen – Arbeit und Zuhause – und auf derselben Seite zwischen ihnen wechseln. ANTA startet dann mit der gewählten neu.';

  @override
  String get appGuideBackupFirstRunTitle => 'Auf einem neuen Telefon';

  @override
  String appGuideBackupFirstRunBody(String restoreFromBackup) {
    return 'Der erste Bildschirm bietet „$restoreFromBackup“: Wähle eine Backup-Datei, und alles ist zurück, bevor du eine einzige Notiz angelegt hast.';
  }

  @override
  String get appGuidePageSync => 'Sync zwischen Telefonen';

  @override
  String get appGuidePageSyncCaption =>
      'Einmal anmelden, dieselben Notizen auf jedem Gerät';

  @override
  String get appGuideSyncLead =>
      'Sync hält eine Kopie einer Datenbank in deinem Konto und schickt jede Änderung an deine anderen Geräte. Es ist aus, bis du es einschaltest.';

  @override
  String get appGuideSyncSignInTitle => 'Anmelden';

  @override
  String appGuideSyncSignInBody(
    String sharingSettings,
    String settingsHubTitle,
    String signInWithGoogle,
  ) {
    return '„$sharingSettings“ in „$settingsHubTitle“: „$signInWithGoogle“. Deine Notizen bleiben auf dem Telefon; das Anmelden allein schickt nichts.';
  }

  @override
  String get appGuideSyncOnTitle => 'Einschalten';

  @override
  String appGuideSyncOnBody(
    String syncThisDatabase,
    String syncThisDatabaseDesc,
  ) {
    return '„$syncThisDatabase“ auf derselben Seite beginnt, die Datenbank zu synchronisieren, die du gerade nutzt. $syncThisDatabaseDesc.';
  }

  @override
  String get appGuideSyncStatusTitle => 'Wie es steht';

  @override
  String appGuideSyncStatusBody(
    String syncUpToDate,
    String syncOffline,
    String syncNow,
  ) {
    return 'Die Seite sagt „$syncUpToDate“, „$syncOffline“ oder wie viele Änderungen warten; die oberste Zeile des Hauptmenüs zeigt, wann zuletzt synchronisiert wurde. Offline geht nichts verloren: Änderungen gehen raus, sobald die Verbindung zurück ist, und „$syncNow“ wartet nicht.';
  }

  @override
  String get appGuideSyncCadenceTitle => 'Wann synchronisiert wird';

  @override
  String appGuideSyncCadenceBody(String syncAutomatic, String syncNow) {
    return '„$syncAutomatic“ auf derselben Seite ist zu Beginn an: Änderungen werden synchronisiert, solange die App offen ist, und wenn du sie verlässt. Schalte es aus, und nichts bewegt sich, bis du auf „$syncNow“ tippst – für eine getaktete Verbindung, oder wenn du selbst bestimmen willst, wann.';
  }

  @override
  String get appGuideSyncOtherTitle => 'Auf dem anderen Telefon';

  @override
  String appGuideSyncOtherBody(String syncThisDatabase) {
    return 'Melde dich mit demselben Konto an und schalte auch dort „$syncThisDatabase“ ein. ANTA listet die Bereiche in deinem Konto; wähle deinen, und er wird als neue Datenbank auf dieses Telefon geladen. Danach werden nur noch Änderungen übertragen.';
  }

  @override
  String get appGuideSyncConflictTitle => 'Zwei Telefone, eine Notiz';

  @override
  String get appGuideSyncConflictBody =>
      'Ändert sich dieselbe Notiz an zwei Orten, behält ANTA beide Fassungen: Die andere wird als Kopie neben deine gelegt, sodass nichts überschrieben wird.';

  @override
  String get moneyNoTarget => 'kein Ziel';

  @override
  String get notesGuideSeedMarkdown =>
      'Beintag\nKniebeuge 5×5\nBankdrücken 3×8\nHeute stark gefühlt';

  @override
  String get notesGuideSeedLists =>
      '- Beine\n- Kniebeuge\n- Ausfallschritte\n- Rücken';

  @override
  String get notesGuideSeedOwn =>
      'Kreuzheben 140 kg\nNächste Woche: Kniebeuge\nGleiches Aufwärmen wie letztes Mal';

  @override
  String get notesGuideSeedMoney => '\$= 500 Budget\n\$- 40 Fitnessstudio\n';

  @override
  String notesGuideCoachMarkdownHeading(String headers) {
    return 'Tippe auf „Beintag“, dann in der Leiste auf „$headers“ und wähle eine Stufe: ein # davor macht daraus eine Überschrift.';
  }

  @override
  String notesGuideCoachMarkdownBold(String bold) {
    return 'Tippe auf „$bold“ und schreibe ein Wort: zwei Sternchen auf jeder Seite machen es fett.';
  }

  @override
  String notesGuideCoachMarkdownList(String bulletList) {
    return 'Tippe auf eine andere Zeile, dann auf „$bulletList“: ein Strich und ein Leerzeichen davor machen sie zum Aufzählungspunkt.';
  }

  @override
  String notesGuideCoachMarkdownTask(String checkbox) {
    return 'Tippe auf noch eine Zeile, dann auf „$checkbox“ – und tippe auf das Kästchen, um es abzuhaken.';
  }

  @override
  String get notesGuideCoachListsEnter =>
      'Tippe hinter „Rücken“ und drücke Enter: der nächste Punkt steht bereit.';

  @override
  String notesGuideCoachListsNest(String indentLine) {
    return 'Tippe auf „Kniebeuge“, dann wische nach rechts oder tippe in der Leiste auf „$indentLine“: der Punkt rückt unter Beine.';
  }

  @override
  String notesGuideCoachListsOutdent(String outdentLine) {
    return 'Wische nach links oder tippe auf „$outdentLine“: er rückt wieder heraus.';
  }

  @override
  String get notesGuideCoachListsEnd =>
      'Drücke Enter auf einem leeren Punkt: die Liste endet in einer normalen Zeile.';

  @override
  String get notesGuideCoachOwnTag =>
      'Hänge #pr an die erste Zeile: ein Wort nach # ist ein Schlagwort.';

  @override
  String notesGuideCoachOwnGhost(String shortcutGhostText) {
    return 'Tippe hinter „Kniebeuge“, dann in der Leiste auf „$shortcutGhostText“: eine Lücke zum späteren Ausfüllen.';
  }

  @override
  String notesGuideCoachOwnColour(String shortcutColorText) {
    return 'Tippe auf eine andere Zeile, dann auf „$shortcutColorText“, und schreibe „schwer“: das Wort wird rot.';
  }

  @override
  String get notesGuideCoachOwnWiki =>
      'Schreibe in eine eigene Zeile [[Beintag]]: doppelte eckige Klammern verlinken die Notiz mit diesem Namen.';

  @override
  String notesGuideCoachMoneySpend(String shortcutMoneySubtract) {
    return 'Tippe auf die leere Zeile, dann auf „$shortcutMoneySubtract“, und schreibe 25 Schuhe: eine weitere Ausgabe.';
  }

  @override
  String notesGuideCoachMoneyAdd(String shortcutMoneyAdd) {
    return 'Drücke Enter, dann „$shortcutMoneyAdd“, und schreibe 25 Rückzahlung: Geld, das hereinkommt.';
  }

  @override
  String notesGuideCoachMoneyTotal(String shortcutMoneyTotal) {
    return 'Drücke Enter und tippe auf „$shortcutMoneyTotal“: was übrig ist, als Chip.';
  }

  @override
  String get notesGuideReportTag =>
      'In einer Notiz zeigt ein Tipp auf ein Schlagwort jede Notiz, die es trägt.';

  @override
  String get notesGuideReportWiki =>
      'In einer Notiz öffnet ein Tipp auf den Link diese Notiz.';

  @override
  String get notesGuideReportLink =>
      'In einer Notiz öffnet ein Tipp auf einen Weblink ihn im Browser.';

  @override
  String get notesGuideReportMoney =>
      'In einer Notiz zeigt ein Tipp auf eine Summe jede Zeile, die hineingeflossen ist.';

  @override
  String notesGuideReportEmptyButton(String markdownStart) {
    return 'Deine Schaltfläche hat noch nichts zu schreiben: fülle zuerst „$markdownStart“ aus.';
  }

  @override
  String get notesGuidePageShortcuts => 'Eigene Kurzbefehle';

  @override
  String get notesGuidePageShortcutsCaption =>
      'Schaltflächen, die deine Zeilen schreiben: ein Satz, ein Datum, ein Zähler';

  @override
  String get notesGuideShortcutsLead =>
      'Ein Kurzbefehl ist eine Schaltfläche der Leiste, die für dich schreibt. ANTA bringt einige mit; deine eigenen machen aus den Zeilen, die du immer wieder schreibst, einen einzigen Tipp.';

  @override
  String get notesGuideSeedShortcuts => 'Beintag\n';

  @override
  String get notesGuideShortcutSetLabel => 'Satz';

  @override
  String notesGuideShortcutSetText(String count, String open, String close) {
    return '- [ ] Satz $count: $open${open}Gewicht$close$close kg × $open${open}Wdh.$close$close';
  }

  @override
  String get notesGuideShortcutTodayLabel => 'Heute';

  @override
  String get notesGuideShortcutMineLabel => 'Deine Schaltfläche';

  @override
  String notesGuideCoachShortcutsLine(String set) {
    return 'Tippe auf die leere Zeile, dann in der Leiste auf „$set“: ein Tipp schreibt eine ganze Zeile, samt Lücken.';
  }

  @override
  String notesGuideCoachShortcutsCount(String set) {
    return 'Tippe noch einmal auf „$set“: die Nummer zählt von selbst weiter.';
  }

  @override
  String notesGuideCoachShortcutsDate(String today) {
    return 'Tippe auf „$today“: das heutige Datum, als Überschrift geschrieben.';
  }

  @override
  String notesGuideCoachShortcutsWrite(String markdownStart) {
    return 'Jetzt deiner: schreibe in „$markdownStart“, über der Notiz, eine Zeile, die du oft schreibst.';
  }

  @override
  String notesGuideCoachShortcutsPress(String mine) {
    return 'Tippe in der Leiste auf den Stern, „$mine“: er schreibt deine Zeile, jedes Mal.';
  }

  @override
  String get notesGuideShortcutsMakeTitle => 'Einen anlegen';

  @override
  String notesGuideShortcutsMakeBody(
    String settingsRowEditor,
    String newShortcut,
    String save,
  ) {
    return 'Öffne in den Einstellungen „$settingsRowEditor“ und tippe unten auf der Seite auf +: „$newShortcut“ öffnet sich. Wähle ein Symbol, gib der Schaltfläche einen Namen, lege fest, was sie schreibt, und tippe auf „$save“. Sie kommt ans Ende der Leiste.';
  }

  @override
  String get notesGuideShortcutsTextTitle => 'Was er schreibt';

  @override
  String notesGuideShortcutsTextBody(String markdownStart, String markdownEnd) {
    return '„$markdownStart“ wird vor den Cursor geschrieben oder vor den Text, den du markiert hast; „$markdownEnd“ dahinter. Für eine ganze Zeile – einen Satz, eine Mahlzeit, eine Überschrift – kommt alles in „$markdownStart“, und „$markdownEnd“ bleibt leer.';
  }

  @override
  String get notesGuideShortcutsKindsTitle => 'Drei Arten';

  @override
  String notesGuideShortcutsKindsBody(
    String insertType,
    String wrapSelectedText,
    String insertCurrentDate,
    String insertCounter,
    String beforeDate,
    String afterDate,
  ) {
    return '„$insertType“ bestimmt, was zwischen beiden steht: „$wrapSelectedText“ lässt deine Markierung dort, „$insertCurrentDate“ schreibt das Datum im Format deiner Wahl – die beiden Felder heißen dann „$beforeDate“ und „$afterDate“ – und „$insertCounter“ den nächsten Wert eines Zählers.';
  }

  @override
  String get notesGuideShortcutsPreviewTitle => 'Vor dem Speichern ansehen';

  @override
  String notesGuideShortcutsPreviewBody(String preview) {
    return '„$preview“, unten auf dieser Seite, zeigt, was die Schaltfläche schreiben wird – so dargestellt, wie eine Notiz es darstellt.';
  }

  @override
  String get notesGuideShortcutsBlanksTitle => 'Lücken lassen';

  @override
  String notesGuideShortcutsBlanksBody(String open, String close) {
    return 'Doppelte geschweifte Klammern lassen eine Lücke in der Zeile: Kniebeuge $open${open}Gewicht$close$close kg schreibt ein blasses „Gewicht“ zum Antippen und Überschreiben. Eine Schaltfläche, jedes Mal eine neue Zahl.';
  }

  @override
  String get notesGuideShortcutsRepeatTitle => 'Mehrere auf einmal';

  @override
  String notesGuideShortcutsRepeatBody(
    String advancedOptions,
    String repeatSettings,
    String incrementDateOnRepeat,
  ) {
    return 'Schalte „$advancedOptions“ ein: „$repeatSettings“ schreibt den Text mit einem Tipp mehrmals – drei Sätze, sieben Tage. Mit „$incrementDateOnRepeat“ rückt ein Datum mit jeder Kopie weiter, sodass ein Tipp die ganze Woche schreibt.';
  }

  @override
  String get notesGuideShortcutsDateTitle => 'Morgen, nächste Woche';

  @override
  String notesGuideShortcutsDateBody(
    String dateOffset,
    String advancedOptions,
  ) {
    return '„$dateOffset“, unter „$advancedOptions“, verschiebt das Datum, das eine Schaltfläche schreibt: ein Tag für den Plan von morgen, sieben für den der nächsten Woche.';
  }

  @override
  String get notesGuideShortcutsCountersTitle => 'Beim Schreiben zählen';

  @override
  String notesGuideShortcutsCountersBody(
    String counterBindingsTitle,
    String advancedOptions,
    String open,
    String close,
  ) {
    return '„$counterBindingsTitle“, ebenfalls unter „$advancedOptions“, bindet bis zu zwei Zähler an die Schaltfläche. Wo im Text ${open}c1$close oder ${open}c2$close steht, wird der nächste Wert des Zählers geschrieben – Satz 1, Satz 2, Satz 3 –, ein Schritt mit jedem Tipp.';
  }

  @override
  String get notesGuideShortcutsTidyTitle => 'Die Leiste kurz halten';

  @override
  String notesGuideShortcutsTidyBody(String setCategory) {
    return 'In der Liste der Kurzbefehle versteckt das Auge eine Schaltfläche, ohne sie zu löschen, und langes Drücken zieht sie an einen neuen Platz. ⋮ › „$setCategory“ fasst Schaltflächen zu Gruppen zusammen, und die Chips über der Liste filtern sie dann nach Gruppe. Über ⋮ bearbeitest oder löschst du auch eine eigene Schaltfläche; die mitgelieferten lassen sich nur verstecken.';
  }

  @override
  String get notesGuideShortcutsBarsTitle => 'Jede Leiste hat ihre eigenen';

  @override
  String notesGuideShortcutsBarsBody(String manageBarProfiles) {
    return 'Ein Kurzbefehl gehört zu der Leiste, in der du ihn angelegt hast. Hast du unter „$manageBarProfiles“ mehrere Leisten, wähle zuerst die Leiste und lege dann die Schaltfläche an.';
  }

  @override
  String get notesGuideRecipeShown => 'Ein Tipp schreibt';

  @override
  String notesGuideExRecipeSetSource(String open, String close) {
    return '- [ ] $open${open}Gewicht$close$close kg × $open${open}Wdh.$close$close';
  }

  @override
  String get notesGuideExRecipeSetCaption =>
      'Ein Satz zum Abhaken, mit zwei Lücken zum Ausfüllen.';

  @override
  String notesGuideExRecipeLabelSource(String open, String close) {
    return '**Aufwärmen:** $open${open}Minuten$close$close min auf dem Rad';
  }

  @override
  String get notesGuideExRecipeLabelCaption =>
      'Eine Zeile, die immer gleich beginnt: der Anfang fett, die Zahl bleibt offen.';

  @override
  String get notesGuideMarkdownCodeTitle => 'Code und Trennlinien';

  @override
  String notesGuideMarkdownCodeBody(
    String inlineCode,
    String codeBlock,
    String shortcutHorizontalRule,
  ) {
    return 'Ein Backtick (`) auf jeder Seite lässt ein Wort genau so stehen, wie es getippt ist, in einer Schrift mit fester Breite; drei Backticks in einer eigenen Zeile beginnen einen Block, der unverändert bleibt, bis drei weitere ihn beenden. Drei Striche in einer eigenen Zeile ziehen eine Linie quer durch die Notiz. Die Leiste hat dafür „$inlineCode“, „$codeBlock“ und „$shortcutHorizontalRule“.';
  }

  @override
  String get notesGuideMoneyBackTitle => 'Zurückblicken';

  @override
  String notesGuideMoneyBackBody(
    String shortcutMoneyDiff,
    String shortcutMoneySpan,
  ) {
    return '\$^ 3 zeigt, wie stark die letzten drei Einträge den Stand verändert haben; \$~ 2 die Veränderung über die letzten zwei \$=-Zeilen. Beide zeigen nur eine Zahl – der Stand bleibt, wie er ist. In der Leiste heißen sie „$shortcutMoneyDiff“ und „$shortcutMoneySpan“.';
  }

  @override
  String get appGuideSyncStopTitle => 'Beenden';

  @override
  String appGuideSyncStopBody(String syncStop, String signOut) {
    return '„$syncStop“ lässt deine Notizen auf diesem Telefon und hört auf zu senden und zu empfangen; die Kopie in deinem Konto bleibt. „$signOut“ pausiert Sync für jede Datenbank, bis du dich wieder anmeldest.';
  }

  @override
  String get appGuideSyncDeleteTitle => 'Die Cloud-Kopie löschen';

  @override
  String appGuideSyncDeleteBody(String delete) {
    return '„$delete“ entfernt die Datenbank endgültig aus deinem Konto. Sie bleibt auf diesem Telefon, das sie nicht mehr synchronisiert; deine anderen Geräte behalten ihre Kopie und hören ebenfalls auf.';
  }
}
