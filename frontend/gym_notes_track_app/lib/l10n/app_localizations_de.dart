// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Gym Notizen';

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
  String get calendarEventsSection => 'Ereignisse';

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
  String get eventDate => 'Datum';

  @override
  String get startsOn => 'Beginnt an diesem Datum';

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
  String get eventPriorityDecrease => 'Niedrigere Priorität';

  @override
  String get eventPriorityIncrease => 'Höhere Priorität';

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
  String get welcomeToGymNotes => 'Willkommen bei Gym Notizen';

  @override
  String get onboardingDescription =>
      'Verfolge deine Trainings und Notizen an einem Ort. Starte mit einem neuen Arbeitsbereich oder stelle ein vorheriges Backup wieder her.';

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
  String get paste => 'Paste';

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
  String get controlsSettings => 'Steuerung';

  @override
  String get controlsSettingsDesc => 'Gesten, Haptik und Interaktionen';

  @override
  String get gesturesSection => 'Gesten';

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
  String get feedbackSection => 'Feedback';

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
  String get displaySection => 'Anzeige';

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
  String get autoBreakLongLines => 'Auto-Break Long Lines';

  @override
  String get autoBreakLongLinesDesc =>
      'Automatically break long lines when pasting text. May slightly affect search positioning accuracy in preview mode.';

  @override
  String get previewWhenKeyboardHidden => 'Preview When Keyboard Hidden';

  @override
  String get previewWhenKeyboardHiddenDesc =>
      'Show rendered markdown preview when the keyboard is hidden. The editor appears when you tap to type.';

  @override
  String get scrollCursorOnKeyboard => 'Scroll Cursor on Keyboard';

  @override
  String get scrollCursorOnKeyboardDesc =>
      'Automatically scroll to keep the cursor visible when the keyboard appears.';

  @override
  String linesFormatted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count long lines were formatted',
      one: '1 long line was formatted',
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
  String get previewPerformanceSection => 'Vorschau-Leistung';

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
  String get repeatWrapperText => 'Wrapper text';

  @override
  String get repeatWrapperTextDesc =>
      'Text inserted before/after all repeated items';

  @override
  String get beforeAllRepeats => 'Before all';

  @override
  String get beforeAllRepeatsHint => 'e.g., ## Week 1\\n';

  @override
  String get afterAllRepeats => 'After all';

  @override
  String get afterAllRepeatsHint => 'e.g., \\n---';

  @override
  String get developerOptions => 'Developer Options';

  @override
  String get developerOptionsDesc => 'Debug tools and diagnostics';

  @override
  String get developerOptionsWarning =>
      'These options are for debugging only. Enabling them may affect app performance.';

  @override
  String get developerOptionsReset => 'Developer options reset to defaults';

  @override
  String get developerModeUnlocked => 'Developer mode unlocked!';

  @override
  String get lockDeveloperMode => 'Lock Developer Mode';

  @override
  String get developerModeLocked => 'Developer mode locked';

  @override
  String get visualizationDebug => 'Visualization / Debug';

  @override
  String get colorMarkdownBlocks => 'Color Markdown Blocks';

  @override
  String get colorMarkdownBlocksDesc =>
      'Show different colors for headers, code, lists, etc.';

  @override
  String get showBlockBoundaries => 'Show Block Boundaries';

  @override
  String get showBlockBoundariesDesc =>
      'Draw borders around each parsed element';

  @override
  String get showWhitespace => 'Show Whitespace';

  @override
  String get showWhitespaceDesc => 'Visualize spaces, tabs, and newlines';

  @override
  String get showPreviewLineNumbers => 'Preview Line Numbers';

  @override
  String get showPreviewLineNumbersDesc =>
      'Show source line numbers in preview mode';

  @override
  String get performanceMonitoring => 'Performance Monitoring';

  @override
  String get showRenderTime => 'Show Render Time';

  @override
  String get showRenderTimeDesc => 'Display how long preview takes to render';

  @override
  String get showFpsCounter => 'Show FPS Counter';

  @override
  String get showFpsCounterDesc => 'Monitor scroll and animation performance';

  @override
  String get showChunkIndicators => 'Show Chunk Indicators';

  @override
  String get showChunkIndicatorsDesc =>
      'Highlight which chunks are loaded in preview';

  @override
  String get showRepaintRainbow => 'Show Repaint Rainbow';

  @override
  String get showRepaintRainbowDesc =>
      'Color widgets when they repaint (Flutter debug)';

  @override
  String get editorDebug => 'Editor Debug';

  @override
  String get showCursorInfo => 'Show Cursor Info';

  @override
  String get showCursorInfoDesc => 'Display line, column, and character offset';

  @override
  String get showSelectionDetails => 'Show Selection Details';

  @override
  String get showSelectionDetailsDesc =>
      'Display start, end positions and length';

  @override
  String get logParserEvents => 'Log Parser Events';

  @override
  String get logParserEventsDesc => 'Output parsing info to debug console';

  @override
  String get storageData => 'Storage / Data';

  @override
  String get showNoteSize => 'Show Note Size';

  @override
  String get showNoteSizeDesc => 'Display content size in bytes';

  @override
  String get showDatabaseStats => 'Show Database Stats';

  @override
  String get showDatabaseStatsDesc => 'Query count and cache information';

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
    return 'A folder named \"$name\" already exists here';
  }

  @override
  String noteTitleAlreadyExists(String title) {
    return 'A note titled \"$title\" already exists here';
  }

  @override
  String moveSkippedDueToDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count items were skipped because the destination already has items with the same name',
      one:
          '1 item was skipped because the destination already has an item with the same name',
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
}
