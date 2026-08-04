// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get appTitle => 'Gym Notes';

  @override
  String get calendar => 'Calendar';

  @override
  String get calendarDesc => 'Planifică antrenamente și evenimente';

  @override
  String get calendarNoEventsForDay => 'Niciun eveniment pentru această zi';

  @override
  String get addEvent => 'Adaugă eveniment';

  @override
  String get eventTitle => 'Titlu';

  @override
  String get eventAllDay => 'Toată ziua';

  @override
  String get eventAllDayHint => 'Evenimentul durează toată ziua';

  @override
  String get eventTimeSection => 'Ora';

  @override
  String get eventStartTime => 'Ora de început';

  @override
  String get eventEndTime => 'Ora de sfârșit';

  @override
  String get eventEndTimeNone => 'Fără oră de sfârșit';

  @override
  String get eventEndTimeHint => 'Atinge pentru a adăuga o oră de sfârșit';

  @override
  String get eventCrossesMidnight => 'Se termină a doua zi';

  @override
  String get calendarFormatMonth => 'Lună';

  @override
  String get calendarFormatTwoWeeks => '2 săptămâni';

  @override
  String get calendarFormatWeek => 'Săptămână';

  @override
  String get calendarFiltersTitle => 'Filtre';

  @override
  String get calendarViewRange => 'Interval de vizualizare';

  @override
  String get calendarEventCategories => 'Categorii de evenimente';

  @override
  String get calendarSelectAll => 'Selectează tot';

  @override
  String get calendarClearAll => 'Șterge';

  @override
  String get filterCalendar => 'Filtrează calendarul';

  @override
  String get goToToday => 'Mergi la azi';

  @override
  String get apply => 'Aplică';

  @override
  String get dayBarWeekend => 'Weekend';

  @override
  String get dayBarPublicHoliday => 'Sărbătoare legală';

  @override
  String get publicHolidayNewYear => 'Anul Nou';

  @override
  String get publicHolidayLabourDay => 'Ziua Muncii';

  @override
  String get publicHolidayChristmasDay => 'Crăciun';

  @override
  String get publicHolidaySecondChristmasDay => 'A doua zi de Crăciun';

  @override
  String get publicHolidayEpiphany => 'Bobotează';

  @override
  String get publicHolidayGoodFriday => 'Vinerea Mare';

  @override
  String get publicHolidayEasterSunday => 'Paștele';

  @override
  String get publicHolidayEasterMonday => 'A doua zi de Paște';

  @override
  String get publicHolidayAscension => 'Înălțarea Domnului';

  @override
  String get publicHolidayPentecost => 'Rusaliile';

  @override
  String get publicHolidayWhitMonday => 'A doua zi de Rusalii';

  @override
  String get publicHolidayAssumption => 'Adormirea Maicii Domnului';

  @override
  String get publicHolidayAllSaints => 'Ziua Tuturor Sfinților';

  @override
  String get publicHolidayChristmasEve => 'Ajunul Crăciunului';

  @override
  String get publicHolidayNewYearsEve => 'Revelionul';

  @override
  String get publicHolidayUnificationDay => 'Ziua Unirii Principatelor Române';

  @override
  String get publicHolidayChildrensDay => 'Ziua Copilului';

  @override
  String get publicHolidayStAndrewDay => 'Sfântul Andrei';

  @override
  String get publicHolidayNationalDayRomania => 'Ziua Națională a României';

  @override
  String get publicHolidayMartinLutherKingDay => 'Ziua Martin Luther King Jr.';

  @override
  String get publicHolidayPresidentsDay => 'Ziua Președinților';

  @override
  String get publicHolidayMemorialDay => 'Memorial Day';

  @override
  String get publicHolidayJuneteenth => 'Juneteenth';

  @override
  String get publicHolidayIndependenceDay => 'Ziua Independenței';

  @override
  String get publicHolidayLaborDayUnitedStates => 'Labor Day';

  @override
  String get publicHolidayColumbusDay => 'Ziua lui Columb';

  @override
  String get publicHolidayVeteransDay => 'Ziua Veteranilor';

  @override
  String get publicHolidayThanksgiving => 'Ziua Recunoștinței';

  @override
  String get publicHolidayEarlyMayBankHoliday =>
      'Sărbătoare bancară de la începutul lunii mai';

  @override
  String get publicHolidaySpringBankHoliday =>
      'Sărbătoare bancară de primăvară';

  @override
  String get publicHolidaySummerBankHoliday => 'Sărbătoare bancară de vară';

  @override
  String get publicHolidayGermanUnityDay => 'Ziua Unității Germane';

  @override
  String get publicHolidayEuropeDay => 'Ziua Europei';

  @override
  String get holidayProfileTitle => 'Set sărbători';

  @override
  String get holidayProfileGeneric => 'Creștin (occidental)';

  @override
  String get holidayProfileRomania => 'România';

  @override
  String get holidayProfileUnitedStates => 'Statele Unite';

  @override
  String get holidayProfileUnitedKingdom => 'Regatul Unit';

  @override
  String get holidayProfileGermany => 'Germania';

  @override
  String get holidayProfileEurope => 'Europa';

  @override
  String get holidayProfileNone => 'Niciunul';

  @override
  String get removeHoliday => 'Elimină sărbătoarea';

  @override
  String removeHolidayConfirm(String holiday) {
    return 'Elimini \"$holiday\" pentru această dată? O poți restaura oricând din Setări calendar.';
  }

  @override
  String get holidayRemoved => 'Sărbătoare eliminată';

  @override
  String get removedHolidays => 'Sărbători eliminate';

  @override
  String get removedHolidaysEmpty => 'Nicio sărbătoare eliminată';

  @override
  String get holidayRestore => 'Restaurează';

  @override
  String get holidayRestored => 'Sărbătoare restaurată';

  @override
  String get eventCategoryGym => 'Sală';

  @override
  String get eventCategoryCardio => 'Cardio';

  @override
  String get eventCategoryRest => 'Odihnă';

  @override
  String get eventCategoryHoliday => 'Concediu';

  @override
  String get eventCategoryCompetition => 'Competiție';

  @override
  String get eventCategoryMeasurement => 'Măsurare';

  @override
  String get eventCategoryMobility => 'Mobilitate';

  @override
  String get eventCategoryBirthday => 'Zi de naștere';

  @override
  String get eventCategoryOther => 'Altele';

  @override
  String get calendarCategories => 'Categorii';

  @override
  String get calendarCategoriesDesc =>
      'Creează și personalizează categoriile de evenimente';

  @override
  String get createCategory => 'Creează categorie';

  @override
  String get editCategory => 'Editează categoria';

  @override
  String get categoryName => 'Nume';

  @override
  String get categoryNameHint => 'ex. Stretching';

  @override
  String get categoryColor => 'Culoare';

  @override
  String get categoryDefault => 'Categorie integrată';

  @override
  String get deleteCategory => 'Șterge categoria';

  @override
  String deleteCategoryConfirm(String name) {
    return 'Ștergi „$name”? Evenimentele care o folosesc vor trece la „Altele”.';
  }

  @override
  String get categoryDeleted => 'Categorie ștearsă';

  @override
  String get calendarEventsSection => 'Evenimente';

  @override
  String get deleteAllEvents => 'Șterge toate evenimentele';

  @override
  String get deleteAllEventsDesc =>
      'Elimină definitiv toate evenimentele create. Sărbătorile rămân.';

  @override
  String get deleteAllEventsConfirm =>
      'Ștergi toate evenimentele? Sărbătorile legale nu sunt afectate. Această acțiune nu poate fi anulată.';

  @override
  String get noEventsToDelete => 'Niciun eveniment de șters';

  @override
  String get allEventsDeleted => 'Toate evenimentele au fost șterse';

  @override
  String get eventType => 'Tip';

  @override
  String get recurrence => 'Repetare';

  @override
  String get recurrenceNone => 'O singură dată';

  @override
  String get recurrenceDaily => 'Zilnic';

  @override
  String get recurrenceWeekly => 'Săptămânal';

  @override
  String get recurrenceMonthly => 'Lunar';

  @override
  String get recurrenceYearly => 'Anual';

  @override
  String get editEvent => 'Editează eveniment';

  @override
  String get deleteEvent => 'Șterge eveniment';

  @override
  String deleteEventConfirm(String title) {
    return 'Ștergi \"$title\"? Această acțiune nu poate fi anulată.';
  }

  @override
  String get iconLabel => 'Pictogramă';

  @override
  String get iconDefault => 'Implicit pentru categorie';

  @override
  String get iconCustom => 'Pictogramă personalizată';

  @override
  String get pickIcon => 'Alege pictogramă';

  @override
  String get pickCategory => 'Schimbă categoria';

  @override
  String get resetToDefault => 'Resetează la Implicit';

  @override
  String get eventDate => 'Dată';

  @override
  String get startsOn => 'Începe la această dată';

  @override
  String get repeatMode => 'Repetare';

  @override
  String get repeatOnce => 'O singură dată';

  @override
  String get repeatRecurring => 'Recurent';

  @override
  String get frequency => 'Frecvență';

  @override
  String get recurrenceWorkdays => 'Zile lucrătoare';

  @override
  String get recurrenceWeekends => 'Weekend';

  @override
  String get recurrenceHolidaysOnly => 'Doar sărbători legale';

  @override
  String recurrenceEveryDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La fiecare $count de zile',
      few: 'La fiecare $count zile',
      one: 'Zilnic',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La fiecare $count de săptămâni',
      few: 'La fiecare $count săptămâni',
      one: 'Săptămânal',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeksOn(int count, String days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La fiecare $count de săptămâni · $days',
      few: 'La fiecare $count săptămâni · $days',
      one: 'Săptămânal · $days',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La fiecare $count de luni',
      few: 'La fiecare $count luni',
      one: 'Lunar',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La fiecare $count de ani',
      few: 'La fiecare $count ani',
      one: 'Anual',
    );
    return '$_temp0';
  }

  @override
  String get recurrenceIntervalLabel => 'Repetă la fiecare';

  @override
  String get recurrenceIntervalDecrement => 'Mai rar';

  @override
  String get recurrenceIntervalIncrement => 'Mai des';

  @override
  String recurrenceUnitDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'de zile',
      few: 'zile',
      one: 'zi',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'de săptămâni',
      few: 'săptămâni',
      one: 'săptămână',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'de luni',
      few: 'luni',
      one: 'lună',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'de ani',
      few: 'ani',
      one: 'an',
    );
    return '$_temp0';
  }

  @override
  String get weekdays => 'Zilele săptămânii';

  @override
  String get weeklyDaysHint => 'Selectează cel puțin o zi';

  @override
  String get eventUntilLabel => 'Se termină pe';

  @override
  String get eventUntilNone => 'Nu se termină niciodată';

  @override
  String get eventUntilHint => 'Atinge pentru a seta o dată de final';

  @override
  String get eventColor => 'Culoare';

  @override
  String get eventColorCustomTitle => 'Culoare personalizată';

  @override
  String get select => 'Selectează';

  @override
  String get eventTintIcon => 'Colorează pictograma';

  @override
  String get eventTintIconHint =>
      'Folosește culoarea evenimentului și pentru pictogramă';

  @override
  String get eventPriority => 'Prioritate';

  @override
  String get eventPriorityHint =>
      'Prioritatea mai mare apare prima și își păstrează bara când ziua e plină';

  @override
  String get eventPriorityLowest => 'Minimă';

  @override
  String get eventPriorityLow => 'Scăzută';

  @override
  String get eventPriorityNormal => 'Normală';

  @override
  String get eventPriorityHigh => 'Ridicată';

  @override
  String get eventPriorityHighest => 'Maximă';

  @override
  String get eventDatesLabel => 'Date';

  @override
  String get eventDatesHint =>
      'Adaugă alte date individuale pentru a repeta acest eveniment fără recurență';

  @override
  String get eventAddDate => 'Adaugă dată';

  @override
  String get eventRemoveDate => 'Elimină data';

  @override
  String recurrenceSpecificDates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de date',
      few: '$count date',
      one: 'O dată',
    );
    return '$_temp0';
  }

  @override
  String get eventDescription => 'Descriere';

  @override
  String get eventDescriptionHint =>
      'Adaugă note (focus, tehnică, intensitate…)';

  @override
  String get eventLinkedNote => 'Notă asociată';

  @override
  String get eventLinkNoteHint => 'Asociază o notă de antrenament';

  @override
  String get eventLinkedNoteMissing => 'Nota asociată nu mai există';

  @override
  String get eventOpenLinkedNote => 'Deschide nota asociată';

  @override
  String get eventRemoveNoteLink => 'Elimină asocierea';

  @override
  String get iconGroupStrength => 'Forță';

  @override
  String get iconGroupCardio => 'Cardio';

  @override
  String get iconGroupSports => 'Sporturi';

  @override
  String get iconGroupRecovery => 'Recuperare';

  @override
  String get iconGroupBody => 'Corp & nutriție';

  @override
  String get iconGroupMeasurement => 'Măsurători';

  @override
  String get iconGroupAchievements => 'Realizări';

  @override
  String get iconGroupTravel => 'Călătorie';

  @override
  String get iconGroupTime => 'Timp';

  @override
  String get iconGroupGeneric => 'Altele';

  @override
  String get welcomeToGymNotes => 'Bine ai venit la Gym Notes';

  @override
  String get onboardingDescription =>
      'Urmărește-ți antrenamentele și notițele într-un singur loc. Începe cu un spațiu de lucru nou sau restaurează dintr-un backup anterior.';

  @override
  String get startFresh => 'Începe de la zero';

  @override
  String get restoreFromBackup => 'Restaurează din Backup';

  @override
  String get confirmImport => 'Confirmă Importul';

  @override
  String get backupContains => 'Acest backup conține:';

  @override
  String exportedOn(String date) {
    return 'Exportat la: $date';
  }

  @override
  String get import => 'Importă';

  @override
  String importSuccess(int folders, int notes) {
    return '$folders foldere și $notes notițe importate cu succes';
  }

  @override
  String get importFailed => 'Import eșuat';

  @override
  String get invalidBackupFile => 'Fișier backup invalid';

  @override
  String get exportBackup => 'Exportă Backup';

  @override
  String get folders => 'Foldere';

  @override
  String get notes => 'Notițe';

  @override
  String get createFolder => 'Crează Folder';

  @override
  String get createNote => 'Crează Notiță';

  @override
  String get folderName => 'Nume Folder';

  @override
  String get noteName => 'Nume Notiță';

  @override
  String get cancel => 'Anulează';

  @override
  String get create => 'Crează';

  @override
  String get edit => 'Editează';

  @override
  String get delete => 'Șterge';

  @override
  String get save => 'Salvează';

  @override
  String get search => 'Caută';

  @override
  String error(String message) {
    return 'Eroare: $message';
  }

  @override
  String created(String date) {
    return 'Creat: $date';
  }

  @override
  String updated(String date) {
    return 'Actualizat: $date';
  }

  @override
  String get deleteFolder => 'Șterge Folder';

  @override
  String deleteFolderConfirm(String name) {
    return 'Ești sigur că vrei să ștergi \"$name\"?';
  }

  @override
  String deleteFolderWithNotesConfirm(String name, int count) {
    return 'Ești sigur că vrei să ștergi \"$name\"? Aceasta va șterge și $count notiță(e).';
  }

  @override
  String get rename => 'Redenumește';

  @override
  String get renameFolder => 'Redenumește Folder';

  @override
  String get untitledNote => 'Notiță fără titlu';

  @override
  String get emptyNote => 'Notiță goală';

  @override
  String get deleteNote => 'Șterge Notiță';

  @override
  String deleteNoteConfirm(String title) {
    return 'Ești sigur că vrei să ștergi \"$title\"?';
  }

  @override
  String get deleteThisNote => 'această notiță';

  @override
  String get enterFolderName => 'Introdu numele folderului';

  @override
  String get newNote => 'Notiță Nouă';

  @override
  String get switchToEditMode => 'Comută la modul Editare';

  @override
  String get previewMarkdown => 'Previzualizare markdown';

  @override
  String get preview => 'Previzualizare';

  @override
  String get autoSaveOn =>
      'Auto-salvare ACTIVATĂ (salvează la fiecare 5s după modificări)';

  @override
  String get enableAutoSave => 'Activează auto-salvarea';

  @override
  String get autoSaveOff => 'Auto-salvare DEZACTIVATĂ';

  @override
  String get saveNote => 'Salvează notița';

  @override
  String get noContentYet => '*Fără conținut încă*';

  @override
  String get startWriting => 'Începe să scrii prima ta notiță...';

  @override
  String get noteCannotBeEmpty => 'Notița nu poate fi goală';

  @override
  String get noteSaved => 'Notiță salvată!';

  @override
  String get editTitle => 'Editează Titlu';

  @override
  String get enterNoteTitle => 'Introdu titlul notiței';

  @override
  String get autoSaveEnabled => 'Auto-salvare activată';

  @override
  String get autoSaveDisabled => 'Auto-salvare dezactivată';

  @override
  String get markdownShortcuts => 'Comenzi Rapide Markdown';

  @override
  String get markdownShortcutsDesc =>
      'Personalizează butoanele și acțiunile din bara de instrumente';

  @override
  String get removeAllCustom => 'Elimină Toate Personalizate';

  @override
  String get noCustomShortcutsYet => 'Nicio comandă rapidă personalizată încă';

  @override
  String get tapToAddShortcut => 'Apasă butonul + pentru a adăuga una';

  @override
  String get deleteShortcut => 'Șterge Comanda Rapidă';

  @override
  String get deleteShortcutConfirm =>
      'Ești sigur că vrei să ștergi această comandă rapidă?';

  @override
  String get resetDialogTitle => 'Resetează la Implicit';

  @override
  String get resetDialogMessage =>
      'Aceasta va restabili toate comenzile rapide implicite la ordinea și setările originale. Comenzile rapide personalizate vor fi păstrate dar mutate la sfârșit.';

  @override
  String get reset => 'Resetează';

  @override
  String get removeCustomDialogTitle => 'Elimină Toate Personalizate';

  @override
  String get removeCustomDialogMessage =>
      'Aceasta va șterge permanent toate comenzile rapide personalizate pe care le-ai creat. Comenzile rapide implicite vor rămâne.';

  @override
  String get remove => 'Elimină';

  @override
  String get defaultLabel => 'IMPLICIT';

  @override
  String get insertsCurrentDate => 'Inserează data curentă';

  @override
  String get opensHeaderMenu => 'Deschide meniul de anteturi (H1-H6)';

  @override
  String beforeAfterText(String before, String after) {
    return 'Înainte: \"$before\" | După: \"$after\"';
  }

  @override
  String get hide => 'Ascunde';

  @override
  String get show => 'Arată';

  @override
  String get newShortcut => 'Comandă Rapidă Nouă';

  @override
  String get editShortcut => 'Editează Comanda Rapidă';

  @override
  String get icon => 'Pictogramă';

  @override
  String get tapToChangeIcon => 'Apasă pentru a schimba pictograma';

  @override
  String get selectIcon => 'Selectează Pictograma';

  @override
  String get searchIcons => 'Caută pictograme...';

  @override
  String get noIconsFound => 'Nicio pictogramă găsită';

  @override
  String get label => 'Etichetă';

  @override
  String get labelHint => 'ex., Evidențiere';

  @override
  String get insertType => 'Tip Inserare';

  @override
  String get wrapSelectedText => 'Înconjoară Textul Selectat';

  @override
  String get insertCurrentDate => 'Inserează Data Curentă';

  @override
  String get beforeDate => 'Înainte de Dată (opțional)';

  @override
  String get markdownStart => 'Început Markdown';

  @override
  String get markdownStartHint => 'ex., ==';

  @override
  String get optionalTextBeforeDate => 'Text opțional înainte de dată';

  @override
  String get afterDate => 'După Dată (opțional)';

  @override
  String get markdownEnd => 'Sfârșit Markdown';

  @override
  String get optionalTextAfterDate => 'Text opțional după dată';

  @override
  String get labelCannotBeEmpty => 'Eticheta nu poate fi goală';

  @override
  String get formHasErrors => 'Te rugăm să corectezi erorile din formular';

  @override
  String get bold => 'Îngroșat';

  @override
  String get italic => 'Italic';

  @override
  String get headers => 'Anteturi';

  @override
  String get pointList => 'Listă cu Puncte';

  @override
  String get strikethrough => 'Tăiat';

  @override
  String get bulletList => 'Listă cu Buline';

  @override
  String get numberedList => 'Listă Numerotată';

  @override
  String get checkbox => 'Casetă de Bifat';

  @override
  String get quote => 'Citat';

  @override
  String get inlineCode => 'Cod în Linie';

  @override
  String get codeBlock => 'Bloc de Cod';

  @override
  String get link => 'Link';

  @override
  String get currentDate => 'Data Curentă';

  @override
  String get header1 => 'Antet 1';

  @override
  String get header2 => 'Antet 2';

  @override
  String get header3 => 'Antet 3';

  @override
  String get header4 => 'Antet 4';

  @override
  String get header5 => 'Antet 5';

  @override
  String get header6 => 'Antet 6';

  @override
  String get undo => 'Anulează';

  @override
  String get redo => 'Refă';

  @override
  String get paste => 'Paste';

  @override
  String get decreaseFontSize => 'Micșorează Fontul';

  @override
  String get increaseFontSize => 'Mărește Fontul';

  @override
  String get settings => 'Setări';

  @override
  String get dropPosition => 'Poziție de plasare';

  @override
  String get longPressToReorder => 'Apasă lung pentru a reordona';

  @override
  String shortcutButton(String label) {
    return 'Buton $label';
  }

  @override
  String get markdownSpaceWarning =>
      'Sfat: Adaugă un spațiu după sintaxa markdown (ex., \'# \' sau \'- \') pentru formatare corectă.';

  @override
  String get reorderShortcuts => 'Reordonează comenzile rapide';

  @override
  String get doneReordering => 'Gata';

  @override
  String get noSearchResults => 'Niciun rezultat găsit';

  @override
  String get searchHint => 'Tastează pentru a căuta notițe';

  @override
  String get loadingMore => 'Se încarcă mai multe...';

  @override
  String get noMoreNotes => 'Nu mai sunt notițe';

  @override
  String get sortBy => 'Sortează după';

  @override
  String get sortByUpdated => 'Ultima actualizare';

  @override
  String get sortByCreated => 'Data creării';

  @override
  String get sortByTitle => 'Titlu';

  @override
  String get ascending => 'Crescător';

  @override
  String get descending => 'Descrescător';

  @override
  String get loadingContent => 'Se încarcă conținutul...';

  @override
  String get largeNoteWarning =>
      'Această notiță este foarte mare și poate dura un moment să se încarce';

  @override
  String noteStats(int count, int chunks) {
    return '$count caractere distincte, $chunks fragmente';
  }

  @override
  String get compressedNote => 'Comprimat';

  @override
  String get searchInFolder => 'Caută în acest folder';

  @override
  String get searchAll => 'Caută în toate notițele';

  @override
  String get recentSearches => 'Căutări recente';

  @override
  String get clearSearchHistory => 'Șterge istoricul căutărilor';

  @override
  String get filterByDate => 'Filtrează după dată';

  @override
  String get fromDate => 'De la';

  @override
  String get toDate => 'Până la';

  @override
  String get applyFilter => 'Aplică filtru';

  @override
  String get clearFilter => 'Șterge filtru';

  @override
  String matchesFound(int count) {
    return '$count potriviri găsite';
  }

  @override
  String get autoSaving => 'Se salvează automat...';

  @override
  String get changesSaved => 'Modificări salvate';

  @override
  String get unsavedChanges => 'Modificări nesalvate';

  @override
  String get discardChanges => 'Renunță la modificări';

  @override
  String get keepEditing => 'Continuă editarea';

  @override
  String get virtualScrollEnabled =>
      'Derulare virtuală activată pentru conținut mare';

  @override
  String lineCount(int count) {
    return '$count linii';
  }

  @override
  String get emptyFoldersHint => 'Se pare că ai putea dori să creezi un folder';

  @override
  String get emptyNotesHint => 'Scrie prima ta notiță';

  @override
  String get tapPlusToCreate => 'Apasă + pentru a începe';

  @override
  String charactersCount(int current, int max) {
    return '$current/$max caractere';
  }

  @override
  String get databaseSettings => 'Bază de Date';

  @override
  String get databaseSettingsDesc =>
      'Gestionează locația și stocarea bazei de date';

  @override
  String get about => 'Despre';

  @override
  String get databaseLocation => 'Locația Bazei de Date';

  @override
  String get copyPath => 'Copiază Calea';

  @override
  String get openInFinder => 'Deschide Folderul';

  @override
  String get databaseStats => 'Statistici';

  @override
  String get size => 'Dimensiune';

  @override
  String get lastModified => 'Ultima Modificare';

  @override
  String get maintenance => 'Întreținere';

  @override
  String get maintenanceDesc =>
      'Rulează SQLite VACUUM pentru a recupera spațiul nefolosit din notițele și folderele șterse. Aceasta reconstruiește fișierul bazei de date, defragmentează datele și poate reduce semnificativ dimensiunea fișierului după ștergerea unor cantități mari de conținut.';

  @override
  String get optimizeDatabase => 'Optimizează Baza de Date';

  @override
  String get dangerZone => 'Zonă Periculoasă';

  @override
  String get dangerZoneDesc =>
      'Aceste acțiuni sunt ireversibile. Toate notițele și folderele tale vor fi șterse permanent.';

  @override
  String get deleteAllData => 'Șterge Toate Datele';

  @override
  String get pathCopied => 'Calea a fost copiată în clipboard';

  @override
  String get notSupportedOnPlatform => 'Nu este suportat pe această platformă';

  @override
  String get errorOpeningFolder => 'Eroare la deschiderea folderului';

  @override
  String get optimizing => 'Se optimizează baza de date...';

  @override
  String get optimizationComplete => 'Baza de date a fost optimizată cu succes';

  @override
  String get saved => 'salvat';

  @override
  String get alreadyOptimized => 'Baza de date este deja optimizată';

  @override
  String get deleteConfirmation =>
      'Această acțiune nu poate fi anulată. Toate notițele, folderele și datele tale vor fi șterse permanent. Ești absolut sigur?';

  @override
  String get deleteNotImplemented =>
      'Funcția de ștergere nu este implementată încă din motive de siguranță';

  @override
  String get deletingData => 'Se șterg toate datele...';

  @override
  String get dataDeleted => 'Date Șterse';

  @override
  String get restartRequired =>
      'Repornirea poate fi necesară pentru efect complet';

  @override
  String get exitApp => 'Închide Aplicația';

  @override
  String get errorDeletingData => 'Eroare la ștergerea datelor';

  @override
  String get shareDatabase => 'Partajează Baza de Date';

  @override
  String get shareDatabaseDesc =>
      'Exportă și partajează fișierul bazei de date prin email, aplicații de mesagerie sau stocare cloud pentru backup.';

  @override
  String get preparingShare => 'Se pregătește partajarea...';

  @override
  String get shareError => 'Eroare la partajarea bazei de date';

  @override
  String get databaseNotFound => 'Fișierul bazei de date nu a fost găsit';

  @override
  String get renameNote => 'Redenumește Notița';

  @override
  String get enterNewName => 'Introdu noul nume';

  @override
  String get reorderMode => 'Mod Reordonare';

  @override
  String get dragToReorder => 'Trage elementele pentru a le reordona';

  @override
  String get sortByCustom => 'Ordine Personalizată';

  @override
  String get quickSort => 'Sortare Rapidă';

  @override
  String get sortItems => 'Sortează Elementele';

  @override
  String get sortFolders => 'Sortează Folderele';

  @override
  String get sortNotes => 'Sortează Notițele';

  @override
  String get sortByName => 'După Nume';

  @override
  String get moveUp => 'Mută Sus';

  @override
  String get moveDown => 'Mută Jos';

  @override
  String get controlsSettings => 'Controale';

  @override
  String get controlsSettingsDesc => 'Gesturi, feedback haptic și interacțiuni';

  @override
  String get gesturesSection => 'Gesturi';

  @override
  String get folderSwipeGesture =>
      'Glisare pentru a deschide meniul în foldere';

  @override
  String get folderSwipeGestureDesc =>
      'Glisează de la marginea stângă pentru a deschide meniul de navigare când navighezi în foldere';

  @override
  String get noteSwipeGesture => 'Glisare pentru a deschide meniul în notițe';

  @override
  String get noteSwipeGestureDesc =>
      'Glisează de la marginea stângă pentru a deschide meniul de navigare când editezi notițe';

  @override
  String get feedbackSection => 'Feedback';

  @override
  String get hapticFeedback => 'Feedback haptic';

  @override
  String get hapticFeedbackDesc =>
      'Vibrează la interacțiuni precum comutarea comutatoarelor';

  @override
  String get confirmDelete => 'Confirmă înainte de ștergere';

  @override
  String get confirmDeleteDesc =>
      'Afișează dialogul de confirmare înainte de ștergerea notițelor sau folderelor';

  @override
  String get autoSaveSection => 'Auto-salvare';

  @override
  String get autoSave => 'Auto-salvare notițe';

  @override
  String get autoSaveDesc => 'Salvează automat notițele în timpul editării';

  @override
  String get autoSaveInterval => 'Interval auto-salvare';

  @override
  String autoSaveIntervalDesc(int seconds) {
    return 'Salvează la fiecare $seconds secunde';
  }

  @override
  String get displaySection => 'Afișare';

  @override
  String get showNotePreview => 'Arată previzualizarea notiței';

  @override
  String get showNotePreviewDesc =>
      'Afișează o previzualizare a conținutului notiței în listă';

  @override
  String get showStatsBar => 'Arată bara de statistici';

  @override
  String get showStatsBarDesc =>
      'Afișează numărul de caractere și linii în editor';

  @override
  String get resetToDefaults => 'Resetează la valorile implicite';

  @override
  String get resetToDefaultsConfirm =>
      'Ești sigur că vrei să resetezi toate setările la valorile implicite?';

  @override
  String get settingsReset => 'Setările au fost resetate la valorile implicite';

  @override
  String get shareNote => 'Partajează Notița';

  @override
  String get shareFolder => 'Partajează Folderul';

  @override
  String get exportingFolder => 'Se exportă folderul...';

  @override
  String get folderExportError => 'Eroare la exportul folderului';

  @override
  String get importingFile => 'Se importă...';

  @override
  String get importFileError => 'Eroare la import';

  @override
  String get importNoteOrFolder => 'Importă';

  @override
  String importedSummary(int folders, int notes) {
    return 'Importat: $folders foldere, $notes notițe';
  }

  @override
  String get shareSelected => 'Distribuie';

  @override
  String get exportingSelection => 'Se exportă selecția...';

  @override
  String get selectionExportError => 'Eroare la exportul selecției';

  @override
  String get noteOptions => 'Opțiuni Notiță';

  @override
  String get exportingNote => 'Se exportă notița...';

  @override
  String get noteExportError => 'Eroare la exportul notiței';

  @override
  String get chooseExportFormat => 'Alege Formatul de Export';

  @override
  String get exportAsMarkdown => 'Markdown (.md)';

  @override
  String get exportAsJson => 'JSON (.json)';

  @override
  String get exportAsText => 'Text Simplu (.txt)';

  @override
  String get activeDatabaseSection => 'Baza de Date Activă';

  @override
  String get activeDatabaseDesc =>
      'Selectează ce bază de date să folosești. Crearea sau schimbarea bazelor de date va reporni aplicația.';

  @override
  String get selectDatabase => 'Selectează Baza de Date';

  @override
  String currentDatabase(String name) {
    return 'Curentă: $name';
  }

  @override
  String get createNewDatabase => 'Crează Bază de Date Nouă';

  @override
  String get newDatabaseName => 'Nume Bază de Date';

  @override
  String get enterDatabaseName => 'Introdu numele bazei de date';

  @override
  String get invalidDatabaseName =>
      'Nume invalid. Folosește doar litere, cifre, underscores și cratime (maxim 50 caractere).';

  @override
  String get databaseExists => 'O bază de date cu acest nume există deja.';

  @override
  String get creatingDatabase => 'Se crează baza de date...';

  @override
  String get databaseCreated => 'Baza de date a fost creată cu succes';

  @override
  String get renameDatabase => 'Redenumește Baza de Date';

  @override
  String get renamingDatabase => 'Se redenumește baza de date...';

  @override
  String get databaseRenamed => 'Baza de date a fost redenumită cu succes';

  @override
  String get switchingDatabase => 'Se schimbă baza de date...';

  @override
  String get availableDatabases => 'Baze de Date Disponibile';

  @override
  String get noDatabases => 'Nicio bază de date găsită';

  @override
  String get databaseOptions => 'Opțiuni Bază de Date';

  @override
  String get switchTo => 'Comută la această bază de date';

  @override
  String deleteDatabaseConfirm(String name) {
    return 'Ești sigur că vrei să ștergi baza de date \"$name\"? Această acțiune nu poate fi anulată.';
  }

  @override
  String get cannotDeleteActive =>
      'Nu poți șterge baza de date activă curent. Te rugăm să comuți la altă bază de date mai întâi.';

  @override
  String get databaseDeleted => 'Baza de date a fost ștearsă';

  @override
  String get findInNote => 'Găsește în notiță';

  @override
  String get replaceWith => 'Înlocuiește cu';

  @override
  String get replaceOne => 'Înlocuiește';

  @override
  String get replaceAll => 'Toate';

  @override
  String replacedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count potriviri înlocuite',
      one: '1 potrivire înlocuită',
    );
    return '$_temp0';
  }

  @override
  String get matchCase => 'Potrivire majuscule';

  @override
  String get wholeWord => 'Cuvânt întreg';

  @override
  String get useRegex => 'Folosește regex';

  @override
  String get findAndReplace => 'Găsește și Înlocuiește';

  @override
  String get options => 'Opțiuni';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Următor';

  @override
  String get close => 'Închide';

  @override
  String get dateFormatSettings => 'Format Dată';

  @override
  String get selectDateFormat => 'Alege cum vor fi afișate datele:';

  @override
  String get longPressToChangeFormat => 'Apasă lung pentru a schimba formatul';

  @override
  String get languageSettings => 'Limbă';

  @override
  String get languageSettingsDesc => 'Schimbă limba de afișare a aplicației';

  @override
  String get selectLanguage => 'Selectează Limba';

  @override
  String get english => 'Engleză';

  @override
  String get german => 'Germană';

  @override
  String get romanian => 'Română';

  @override
  String get systemDefault => 'Implicit Sistem';

  @override
  String get themeSettings => 'Aspect';

  @override
  String get themeSettingsDesc => 'Mod întunecat, culori și afișare';

  @override
  String get selectTheme => 'Selectează Tema';

  @override
  String get lightTheme => 'Luminos';

  @override
  String get darkTheme => 'Întunecat';

  @override
  String get systemTheme => 'Sistem';

  @override
  String get searchSection => 'Căutare';

  @override
  String get searchCursorBehavior => 'Navigare căutare';

  @override
  String get searchCursorBehaviorDesc =>
      'Unde să poziționeze cursorul când navighezi la o potrivire';

  @override
  String get cursorAtStart => 'Înainte';

  @override
  String get cursorAtEnd => 'După';

  @override
  String get selectMatch => 'Selectează';

  @override
  String get searching => 'Se caută...';

  @override
  String get editorSection => 'Editor';

  @override
  String get liveMarkdownRendering => 'Redare Markdown Live';

  @override
  String get liveMarkdownRenderingDesc =>
      'Afișează titlurile, listele, casetele de bifat și stilurile de text direct în timpul editării';

  @override
  String get showLineNumbers => 'Numere de Linie';

  @override
  String get showLineNumbersDesc =>
      'Afișează numerele liniilor în partea stângă a editorului';

  @override
  String get wordWrap => 'Împachetare Text';

  @override
  String get wordWrapDesc =>
      'Împachetează liniile lungi pentru a încăpea în lățimea editorului';

  @override
  String get showCursorLine => 'Evidențiază Linia Curentă';

  @override
  String get showCursorLineDesc =>
      'Evidențiază linia unde este poziționat cursorul';

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
  String get previewSection => 'Previzualizare';

  @override
  String get showPreviewScrollbar => 'Bară de Derulare Previzualizare';

  @override
  String get showPreviewScrollbarDesc =>
      'Afișează o bară de derulare interactivă în modul previzualizare (experimental)';

  @override
  String get previewPerformanceSection => 'Performanță Previzualizare';

  @override
  String get previewLinesPerChunk => 'Linii per Bucată';

  @override
  String previewLinesPerChunkDesc(int count) {
    return '$count linii per bucată (mai mare = performanță mai bună, mai mic = derulare căutare mai precisă)';
  }

  @override
  String get calendarSection => 'Calendar';

  @override
  String get calendarSettings => 'Calendar';

  @override
  String get calendarMaxDayBars => 'Numărul maxim de bare pe zi';

  @override
  String calendarMaxDayBarsDesc(int count) {
    return 'Afișează până la $count bare pe zi. Restul categoriilor sunt grupate într-un indicator +N.';
  }

  @override
  String get calendarAppearanceSection => 'Aspect';

  @override
  String get calendarTodayStyleTitle => 'Evidențierea zilei de azi';

  @override
  String get todayStyleTonal => 'Estompat';

  @override
  String get todayStyleRing => 'Inel';

  @override
  String get todayStyleFilled => 'Plin';

  @override
  String get calendarAccentColor => 'Culoarea de evidențiere';

  @override
  String get calendarAccentColorDesc =>
      'Colorează ziua de azi și ziua selectată';

  @override
  String get calendarAccentThemeDefault => 'Culoarea temei';

  @override
  String get calendarMarkerStyleTitle => 'Marcaje evenimente';

  @override
  String get markerStyleBars => 'Bare';

  @override
  String get markerStyleDots => 'Puncte';

  @override
  String get calendarHighlightWeekends => 'Colorează weekendurile';

  @override
  String get calendarHighlightWeekendsDesc =>
      'Afișează sâmbăta și duminica într-o culoare distinctă';

  @override
  String get calendarShowWeekNumbers => 'Numerele săptămânilor';

  @override
  String get calendarShowWeekNumbersDesc =>
      'Afișează numărul săptămânii în marginea stângă';

  @override
  String get calendarWeekStartTitle => 'Săptămâna începe';

  @override
  String daySummaryEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de intrări',
      few: '$count intrări',
      one: '1 intrare',
    );
    return '$_temp0';
  }

  @override
  String get dateOffset => 'Offset Dată';

  @override
  String get dateOffsetDescription =>
      'Deplasează data înainte sau înapoi față de azi';

  @override
  String get days => 'Zile';

  @override
  String get monthsLabel => 'Luni';

  @override
  String get yearsLabel => 'Ani';

  @override
  String get repeatSettings => 'Repetare';

  @override
  String get repeatDescription =>
      'Inserează această scurtătură de mai multe ori';

  @override
  String get repeatCount => 'Număr repetări';

  @override
  String get separator => 'Separator';

  @override
  String get newLine => 'Linie nouă';

  @override
  String get noSeparator => 'Niciunul';

  @override
  String get space => 'Spațiu';

  @override
  String get nbspSpace => 'Neîntrerupt';

  @override
  String get blankLine => 'Linie goală';

  @override
  String get comma => 'Virgulă';

  @override
  String get pipe => 'Bară';

  @override
  String get incrementDateOnRepeat => 'Incrementează data la repetare';

  @override
  String get incrementByEachRepeat => 'Incrementare pentru fiecare repetare:';

  @override
  String get advancedOptions => 'Opțiuni Avansate';

  @override
  String get advancedOptionsDescription => 'Offset dată, repetare și altele';

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
  String get saveStatusSaved => 'Saved';

  @override
  String get saveStatusUnsaved => 'Unsaved';

  @override
  String get saveStatusSaving => 'Saving…';

  @override
  String get saveStatusError => 'Save failed';

  @override
  String get toolbarLayout => 'Aspect bară de instrumente';

  @override
  String get shortcuts => 'Scurtături';

  @override
  String get utilities => 'Utilități';

  @override
  String get splitToolbar => 'Împarte bara de instrumente';

  @override
  String get utilityButtons => 'Butoane utilitare';

  @override
  String get utilityButtonsHint =>
      'Comutați vizibilitatea și trageți pentru a reordona';

  @override
  String get markdownBars => 'Bare Markdown';

  @override
  String get activeBar => 'Bara Activă';

  @override
  String get editingBar => 'Editare Bară';

  @override
  String get addBar => 'Adaugă Bară';

  @override
  String get deleteBar => 'Șterge Bara';

  @override
  String get deleteBarConfirm =>
      'Sigur doriți să ștergeți această bară? Notele care o folosesc vor folosi bara activă globală.';

  @override
  String get renameBar => 'Redenumire Bară';

  @override
  String get duplicateBar => 'Duplicare Bară';

  @override
  String get barName => 'Nume Bară';

  @override
  String get defaultBar => 'Implicit';

  @override
  String get switchBar => 'Schimbă Bara';

  @override
  String get searchBars => 'Caută bare...';

  @override
  String get noMatchingBars => 'Nicio bară potrivită';

  @override
  String get perNoteBarAssignment => 'Alocare Bară per Notiță';

  @override
  String get perNoteBarHint =>
      'Alocați o bară specifică pentru note individuale. Notele fără o alocare folosesc bara activă globală.';

  @override
  String get useGlobalBar => 'Folosește Bara Globală';

  @override
  String get cannotDeleteDefault => 'Nu se poate șterge bara implicită';

  @override
  String get cannotRenameDefault => 'Nu se poate redenumi bara implicită';

  @override
  String get barSwitcherTitle => 'Selectare Bară Markdown';

  @override
  String get noteBarOverride => 'Suprascriere Notiță';

  @override
  String get clearOverride => 'Șterge Suprascrierea';

  @override
  String get manageBarProfiles => 'Gestionare Profile Bară';

  @override
  String get alwaysVisible => 'Întotdeauna vizibil';

  @override
  String get visible => 'Vizibil';

  @override
  String get goToTop => 'Mergi sus';

  @override
  String get goToBottom => 'Mergi jos';

  @override
  String get hidden => 'Ascuns';

  @override
  String get insertCounter => 'Inserează Valoare Contor';

  @override
  String get counterBindingsTitle => 'Legături cu contoare';

  @override
  String get counterBindingsDescription =>
      'Leagă până la două contoare la această scurtătură și folosește tokenele c1 și c2 (în acolade) în textul înainte/după pentru a insera valorile lor. Fiecare apariție a unui token modifică contorul o dată pe fiecare repetare.';

  @override
  String get addCounterBinding => 'Adaugă legătură contor';

  @override
  String get addSecondCounterBinding => 'Adaugă a doua legătură contor';

  @override
  String get removeCounterBinding => 'Elimină legătura contor';

  @override
  String get counterTokensHint =>
      'Apasă un token pentru a-l insera la poziția cursorului.';

  @override
  String get counterOperation => 'Operație';

  @override
  String get counterOpIncrement => 'Incrementează';

  @override
  String get counterOpKeep => 'Păstrează';

  @override
  String get counterOpDecrement => 'Decrementează';

  @override
  String get selectCounter => 'Selectează Contorul';

  @override
  String get noCountersYet => 'Niciun contor creat încă';

  @override
  String get noCountersYetHint =>
      'Niciun contor creat încă. Folosește butonul \"Adaugă Contor\" de mai jos pentru a crea unul.';

  @override
  String get addCounter => 'Adaugă Contor';

  @override
  String get counterName => 'Nume Contor';

  @override
  String get startValue => 'Valoare Inițială';

  @override
  String get step => 'Pas';

  @override
  String get counterScope => 'Domeniu Contor';

  @override
  String get global => 'Global';

  @override
  String get perNote => 'Per Notiță';

  @override
  String get editCounter => 'Editează Contor';

  @override
  String get deleteCounter => 'Șterge Contor';

  @override
  String get deleteCounterConfirm =>
      'Sigur doriți să ștergeți acest contor? Această acțiune nu poate fi anulată.';

  @override
  String get resetCounter => 'Resetează Contor';

  @override
  String get resetCounterConfirm =>
      'Resetați acest contor la valoarea inițială?';

  @override
  String get counters => 'Contoare';

  @override
  String get counterSettings => 'Contoare';

  @override
  String get counterSettingsDesc =>
      'Creează și gestionează contoare cu auto-incrementare';

  @override
  String counterCurrentValue(int value) {
    return 'Curent: $value';
  }

  @override
  String counterStepLabel(int step) {
    return 'Pas: $step';
  }

  @override
  String get counterEmptyState =>
      'Niciun contor încă. Apasă + pentru a crea unul.';

  @override
  String get counterResetSuccess => 'Contor resetat la valoarea inițială';

  @override
  String get counterDeleteSuccess => 'Contor șters';

  @override
  String get counterSetValue => 'Setează Valoare';

  @override
  String get counterValuePerNote => 'Valoare variabilă per notiță';

  @override
  String get counterScopeGlobalDesc => 'Partajat între toate notițele';

  @override
  String get counterScopePerNoteDesc => 'Valoare independentă per notiță';

  @override
  String get pickCounter => 'Alege Contor';

  @override
  String get searchCounters => 'Caută contoare…';

  @override
  String get noCountersMatchSearch => 'Niciun contor nu corespunde căutării';

  @override
  String get counterInsertTooltip => 'Inserează valoare contor';

  @override
  String get createCounterInline => 'Creează contor nou';

  @override
  String get manageCounters => 'Gestionează contoare';

  @override
  String counterPickerPage(int current, int total) {
    return '$current / $total';
  }

  @override
  String get selectNote => 'Selectează o notiță';

  @override
  String get searchNotes => 'Caută notițe…';

  @override
  String get noNotesAvailable => 'Nicio notiță încă';

  @override
  String get noNotesMatchSearch => 'Nicio notiță nu corespunde căutării';

  @override
  String get counterSelectNoteToView =>
      'Apasă pentru a gestiona valorile per notițe';

  @override
  String get counterLoadError => 'Nu s-au putut încărca contoarele';

  @override
  String get counterRetry => 'Încercă din nou';

  @override
  String get counterPerNoteValues => 'Valori per notiță';

  @override
  String get counterPerNoteEmpty =>
      'Nicio notiță nu are încă valori pentru acest contor';

  @override
  String get counterResetAllNotes => 'Resetează toate notițele';

  @override
  String get counterResetAllConfirm =>
      'Resetezi acest contor la valoarea inițială pentru toate notițele?';

  @override
  String get counterResetAllSuccess =>
      'Toate valorile per notiță au fost resetate';

  @override
  String get counterManageNoteValues => 'Gestionează valori per notiță';

  @override
  String get pinCounter => 'Fixează';

  @override
  String get unpinCounter => 'Eliberează';

  @override
  String get addNote => 'Adaugă notiță';

  @override
  String get removeNote => 'Elimină notița';

  @override
  String get removeNoteConfirm =>
      'Elimini această notiță din contor? Valoarea va fi pierdută.';

  @override
  String get noteAlreadyAdded => 'Această notiță este deja adăugată';

  @override
  String get moveToFolder => 'Mută în dosar';

  @override
  String get selectDestinationFolder => 'Selectează destinația';

  @override
  String get moveToTitle => 'Mută în…';

  @override
  String get currentlyIn => 'Te afli în';

  @override
  String subfoldersOf(String name) {
    return 'Subdosare din $name';
  }

  @override
  String moveToDestination(String name) {
    return 'Mută în $name';
  }

  @override
  String get rootFolder => 'Rădăcină';

  @override
  String get noteMoved => 'Notița a fost mutată cu succes';

  @override
  String get noteMoveFailed => 'Mutarea notiței a eșuat';

  @override
  String get alreadyInThisFolder => 'Notița se află deja în acest dosar';

  @override
  String get noFoldersAvailable => 'Nu sunt dosare disponibile';

  @override
  String get noSubfolders => 'Niciun subdosar aici';

  @override
  String get back => 'Înapoi';

  @override
  String get openFolder => 'Deschide dosarul';

  @override
  String get selectAsDestination => 'Selectează ca destinație';

  @override
  String get moveHere => 'Mută aici';

  @override
  String get folderMoved => 'Dosarul a fost mutat cu succes';

  @override
  String get folderMoveFailed => 'Mutarea dosarului a eșuat';

  @override
  String get cannotMoveIntoSelf =>
      'Nu se poate muta un dosar în el însuși sau într-un subdosar';

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
  String get moveHistory => 'Istoric mutări';

  @override
  String get noMoveHistory => 'Nicio mutare recentă';

  @override
  String get clearHistory => 'Șterge istoricul';

  @override
  String movedToTarget(String target) {
    return 'Mutat în $target';
  }

  @override
  String get undone => 'Anulat';

  @override
  String get moveUndone => 'Mutarea a fost anulată';

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
  String get originalLocationGone => 'Locația inițială nu mai există';

  @override
  String get moveUndoCanceled => 'Restaurare anulată';

  @override
  String get clearMoveHistoryConfirm =>
      'Ștergi tot istoricul de mutări? Această acțiune nu poate fi anulată.';

  @override
  String get searchFolders => 'Caută foldere';

  @override
  String get noFoldersFound => 'Niciun folder găsit';

  @override
  String get recentDestinations => 'Recente';

  @override
  String itemsMoved(int count) {
    return '$count elemente mutate';
  }

  @override
  String get moveSelected => 'Mută';

  @override
  String get deleteSelected => 'Șterge';

  @override
  String deleteSelectedConfirm(int count) {
    return 'Ștergi $count elemente selectate? Această acțiune nu poate fi anulată.';
  }

  @override
  String get selectAll => 'Selectează tot';

  @override
  String get linkOpenFailed => 'Linkul nu a putut fi deschis';

  @override
  String get linkSchemeNotAllowed => 'Tip de link nesuportat';

  @override
  String linkOpenPrompt(String target) {
    return 'Deschizi $target?';
  }

  @override
  String get linkOpenAction => 'Deschide';

  @override
  String get moneySection => 'Registru de bani';

  @override
  String get moneyLedgerEnabledLabel => 'Activează registrul de bani';

  @override
  String get moneyLedgerEnabledDesc =>
      'Afișează liniile \$ de bani în notițe și în calendar';

  @override
  String get moneyStartBalance => 'Sold inițial';

  @override
  String get moneyStartBalanceDesc =>
      'Registrul fiecărei notițe pornește de la această sumă';

  @override
  String get moneyCurrencySymbolLabel => 'Simbol monedă';

  @override
  String get moneyCurrencySymbolDesc =>
      'Afișat la sumele calculate (ex. lei, €, \$)';

  @override
  String get moneyCurrencySuffixLabel => 'Simbol după sumă';

  @override
  String get moneyCurrencySuffixDesc => '12.50 lei în loc de lei12.50';

  @override
  String get moneyPerNoteCurrency => 'Monedă per notiță';

  @override
  String get useGlobalCurrency => 'Folosește moneda globală';

  @override
  String get moneyCustomSymbol => 'Personalizat…';

  @override
  String get moneyDetailTitle => 'Registru';

  @override
  String get moneyErrorMissingAmount => 'lipsește suma după \":\"';

  @override
  String get moneyErrorUnknownColour => 'nume de culoare necunoscut';

  @override
  String get moneyErrorInvalidAmount => 'sumă invalidă';

  @override
  String get moneyErrorInvalidCount => 'număr invalid';

  @override
  String get moneyErrorDivideByZero => 'împărțire la zero';

  @override
  String get moneyErrorAmountTooLarge =>
      'sumă prea mare (max. 99.999.999.999,99)';

  @override
  String get moneyErrorTooManyDecimals => 'prea multe zecimale';

  @override
  String moneyDaySummaryTitle(String amount) {
    return 'Bani: $amount';
  }

  @override
  String get markdownColorsTitle => 'Culori text';

  @override
  String get markdownColorsSubtitle => 'Culori pentru text și evidențieri';

  @override
  String get markdownColorsHowTo =>
      'Scrie numele culorii înaintea textului. Numele necunoscute rămân simple.';

  @override
  String get markdownColorsSampleText => 'text exemplu';

  @override
  String get markdownColorsFallbackNote =>
      'Culorile personalizate sunt ajustate automat când ar fi ilizibile pe tema curentă.';

  @override
  String get markdownColorsPresets => 'Presetări';

  @override
  String get markdownColorsCustom => 'Culori personalizate';

  @override
  String get markdownColorsEmpty =>
      'Nicio culoare personalizată. Apasă + pentru a adăuga.';

  @override
  String get markdownColorsNameTitle => 'Nume culoare';

  @override
  String get markdownColorsNameHint => 'litere mici, cifre, - și _';

  @override
  String get markdownColorsNameInvalid =>
      'Introdu un nume cu litere, cifre, - sau _';

  @override
  String get markdownColorsRecolor => 'Schimbă culoarea';

  @override
  String get markdownColorsRename => 'Redenumește';

  @override
  String get markdownColorsDelete => 'Șterge';

  @override
  String get markdownColorsDeleteTitle => 'Șterge culoarea';

  @override
  String get markdownColorsOverridden => 'Înlocuită de o culoare personalizată';

  @override
  String markdownColorsNameTaken(String name) {
    return '„$name” este deja folosit';
  }

  @override
  String markdownColorsLimitReached(int count) {
    return 'Limită de culori atinsă ($count)';
  }

  @override
  String markdownColorsDeleteMessage(String name) {
    return 'Ștergi „$name”? Notițele care o folosesc vor afișa text simplu.';
  }

  @override
  String get upcomingEvents => 'Urmează';

  @override
  String get upcomingSearchHint => 'Caută evenimente';

  @override
  String get upcomingClearSearch => 'Șterge căutarea';

  @override
  String upcomingPeriodDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de zile',
      few: '$count zile',
      one: '1 zi',
    );
    return '$_temp0';
  }

  @override
  String get upcomingPeriodCustom => 'Personalizat';

  @override
  String get upcomingPriority => 'Prioritate';

  @override
  String get upcomingPriorityAny => 'Oricare';

  @override
  String get upcomingNoEvents => 'Nimic în perioada aleasă';

  @override
  String get upcomingNoEventsHint =>
      'Încearcă o perioadă mai lungă sau o prioritate mai mică';

  @override
  String get upcomingToday => 'Azi';

  @override
  String get upcomingTomorrow => 'Mâine';

  @override
  String get upcomingEditEvent => 'Editează evenimentul';

  @override
  String get upcomingShowHolidays => 'Sărbători';

  @override
  String get upcomingFilters => 'Filtre';

  @override
  String get panelExpand => 'Extinde panoul';

  @override
  String get panelShowCalendar => 'Arată calendarul';

  @override
  String get panelModeDay => 'Zi';

  @override
  String get panelModeTimeline => 'Program';

  @override
  String get timelineEmptyHint =>
      'Evenimentele cu oră de început apar în program';

  @override
  String get exportEventsIcs => 'Exportă evenimentele (.ics)';

  @override
  String get exportingEvents => 'Se exportă evenimentele...';

  @override
  String get eventsExportError => 'Evenimentele nu au putut fi exportate';

  @override
  String eventsExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de evenimente exportate',
      few: '$count evenimente exportate',
      one: '1 eveniment exportat',
      zero: 'Niciun eveniment exportat',
    );
    return '$_temp0';
  }
}
