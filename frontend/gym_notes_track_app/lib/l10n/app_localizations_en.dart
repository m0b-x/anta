// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Gym Notes';

  @override
  String get calendar => 'Calendar';

  @override
  String get calendarDesc => 'Plan gym sessions and events';

  @override
  String get calendarNoEventsForDay => 'No events for this day';

  @override
  String get addEvent => 'Add event';

  @override
  String get eventTitle => 'Title';

  @override
  String get eventAllDay => 'All day';

  @override
  String get eventAllDayHint => 'Event spans the entire day';

  @override
  String get eventTimeSection => 'Time';

  @override
  String get eventStartTime => 'Start time';

  @override
  String get eventEndTime => 'End time';

  @override
  String get eventEndTimeNone => 'No end time';

  @override
  String get eventEndTimeHint => 'Tap to add an end time';

  @override
  String get eventCrossesMidnight => 'Ends next day';

  @override
  String get calendarFormatMonth => 'Month';

  @override
  String get calendarFormatTwoWeeks => '2 weeks';

  @override
  String get calendarFormatWeek => 'Week';

  @override
  String get calendarFiltersTitle => 'Filters';

  @override
  String get calendarViewRange => 'View range';

  @override
  String get calendarEventCategories => 'Event categories';

  @override
  String get calendarSelectAll => 'Select all';

  @override
  String get calendarClearAll => 'Clear';

  @override
  String get filterCalendar => 'Filter calendar';

  @override
  String get goToToday => 'Go to today';

  @override
  String get apply => 'Apply';

  @override
  String get dayBarWeekend => 'Weekend';

  @override
  String get dayBarPublicHoliday => 'Public holiday';

  @override
  String get publicHolidayNewYear => 'New Year\'s Day';

  @override
  String get publicHolidayLabourDay => 'Labour Day';

  @override
  String get publicHolidayChristmasDay => 'Christmas Day';

  @override
  String get publicHolidaySecondChristmasDay => 'Second Day of Christmas';

  @override
  String get publicHolidayEpiphany => 'Epiphany';

  @override
  String get publicHolidayGoodFriday => 'Good Friday';

  @override
  String get publicHolidayEasterSunday => 'Easter Sunday';

  @override
  String get publicHolidayEasterMonday => 'Easter Monday';

  @override
  String get publicHolidayAscension => 'Ascension Day';

  @override
  String get publicHolidayPentecost => 'Pentecost';

  @override
  String get publicHolidayWhitMonday => 'Whit Monday';

  @override
  String get publicHolidayAssumption => 'Assumption of Mary';

  @override
  String get publicHolidayAllSaints => 'All Saints\' Day';

  @override
  String get publicHolidayChristmasEve => 'Christmas Eve';

  @override
  String get publicHolidayNewYearsEve => 'New Year\'s Eve';

  @override
  String get publicHolidayUnificationDay =>
      'Union of the Romanian Principalities Day';

  @override
  String get publicHolidayChildrensDay => 'Children\'s Day';

  @override
  String get publicHolidayStAndrewDay => 'Saint Andrew\'s Day';

  @override
  String get publicHolidayNationalDayRomania => 'Romanian National Day';

  @override
  String get publicHolidayMartinLutherKingDay => 'Martin Luther King Jr. Day';

  @override
  String get publicHolidayPresidentsDay => 'Presidents\' Day';

  @override
  String get publicHolidayMemorialDay => 'Memorial Day';

  @override
  String get publicHolidayJuneteenth => 'Juneteenth';

  @override
  String get publicHolidayIndependenceDay => 'Independence Day';

  @override
  String get publicHolidayLaborDayUnitedStates => 'Labor Day';

  @override
  String get publicHolidayColumbusDay => 'Columbus Day';

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
  String get publicHolidayGermanUnityDay => 'German Unity Day';

  @override
  String get publicHolidayEuropeDay => 'Europe Day';

  @override
  String get holidayProfileTitle => 'Holiday set';

  @override
  String get holidayProfileGeneric => 'Christian (Western)';

  @override
  String get holidayProfileRomania => 'Romania';

  @override
  String get holidayProfileUnitedStates => 'United States';

  @override
  String get holidayProfileUnitedKingdom => 'United Kingdom';

  @override
  String get holidayProfileGermany => 'Germany';

  @override
  String get holidayProfileEurope => 'Europe';

  @override
  String get holidayProfileNone => 'None';

  @override
  String get removeHoliday => 'Remove holiday';

  @override
  String removeHolidayConfirm(String holiday) {
    return 'Remove \"$holiday\" for this date? You can restore it anytime from Calendar Settings.';
  }

  @override
  String get holidayRemoved => 'Holiday removed';

  @override
  String get removedHolidays => 'Removed holidays';

  @override
  String get removedHolidaysEmpty => 'No holidays removed';

  @override
  String get holidayRestore => 'Restore';

  @override
  String get holidayRestored => 'Holiday restored';

  @override
  String get eventCategoryGym => 'Gym';

  @override
  String get eventCategoryCardio => 'Cardio';

  @override
  String get eventCategoryRest => 'Rest';

  @override
  String get eventCategoryHoliday => 'Holiday';

  @override
  String get eventCategoryCompetition => 'Competition';

  @override
  String get eventCategoryMeasurement => 'Measurement';

  @override
  String get eventCategoryMobility => 'Mobility';

  @override
  String get eventCategoryBirthday => 'Birthday';

  @override
  String get eventCategoryOther => 'Other';

  @override
  String get calendarCategories => 'Categories';

  @override
  String get calendarCategoriesDesc => 'Create and customize event categories';

  @override
  String get createCategory => 'Create category';

  @override
  String get editCategory => 'Edit category';

  @override
  String get categoryName => 'Name';

  @override
  String get categoryNameHint => 'e.g. Stretching';

  @override
  String get categoryColor => 'Color';

  @override
  String get categoryDefault => 'Built-in category';

  @override
  String get deleteCategory => 'Delete category';

  @override
  String deleteCategoryConfirm(String name) {
    return 'Delete \"$name\"? Events using it will move to Other.';
  }

  @override
  String get categoryDeleted => 'Category deleted';

  @override
  String get calendarEventsSection => 'Events';

  @override
  String get deleteAllEvents => 'Delete all events';

  @override
  String get deleteAllEventsDesc =>
      'Permanently remove every event you created. Holidays are kept.';

  @override
  String get deleteAllEventsConfirm =>
      'Delete all your events? Public holidays aren\'t affected. This can\'t be undone.';

  @override
  String get noEventsToDelete => 'No events to delete';

  @override
  String get allEventsDeleted => 'All events deleted';

  @override
  String get eventType => 'Type';

  @override
  String get recurrence => 'Repeats';

  @override
  String get recurrenceNone => 'Once';

  @override
  String get recurrenceDaily => 'Daily';

  @override
  String get recurrenceWeekly => 'Weekly';

  @override
  String get recurrenceMonthly => 'Monthly';

  @override
  String get recurrenceYearly => 'Yearly';

  @override
  String get editEvent => 'Edit event';

  @override
  String get deleteEvent => 'Delete event';

  @override
  String deleteEventConfirm(String title) {
    return 'Delete \"$title\"? This cannot be undone.';
  }

  @override
  String get iconLabel => 'Icon';

  @override
  String get iconDefault => 'Default for category';

  @override
  String get iconCustom => 'Custom icon';

  @override
  String get pickIcon => 'Choose icon';

  @override
  String get pickCategory => 'Change category';

  @override
  String get resetToDefault => 'Reset to Default';

  @override
  String get eventDate => 'Date';

  @override
  String get startsOn => 'Starts on this date';

  @override
  String get repeatMode => 'Repeats';

  @override
  String get repeatOnce => 'One time';

  @override
  String get repeatRecurring => 'Recurring';

  @override
  String get frequency => 'Frequency';

  @override
  String get recurrenceWorkdays => 'Workdays';

  @override
  String get recurrenceWeekends => 'Weekends';

  @override
  String get recurrenceHolidaysOnly => 'Public holidays only';

  @override
  String recurrenceEveryDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count days',
      one: 'Daily',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count weeks',
      one: 'Weekly',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryWeeksOn(int count, String days) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count weeks · $days',
      one: 'Weekly · $days',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count months',
      one: 'Monthly',
    );
    return '$_temp0';
  }

  @override
  String recurrenceEveryYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count years',
      one: 'Yearly',
    );
    return '$_temp0';
  }

  @override
  String get recurrenceIntervalLabel => 'Repeat every';

  @override
  String get recurrenceIntervalDecrement => 'Less frequent';

  @override
  String get recurrenceIntervalIncrement => 'More frequent';

  @override
  String recurrenceUnitDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'weeks',
      one: 'week',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'months',
      one: 'month',
    );
    return '$_temp0';
  }

  @override
  String recurrenceUnitYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'years',
      one: 'year',
    );
    return '$_temp0';
  }

  @override
  String get weekdays => 'Weekdays';

  @override
  String get weeklyDaysHint => 'Pick at least one weekday';

  @override
  String get eventUntilLabel => 'Ends on';

  @override
  String get eventUntilNone => 'Never ends';

  @override
  String get eventUntilHint => 'Tap to set an end date';

  @override
  String get recurrenceScopeLabel => 'Occurrences';

  @override
  String get recurrenceScopeFromStart => 'From this date on';

  @override
  String get recurrenceScopeAlways => 'Always';

  @override
  String get recurrenceScopeEveryYear => 'Every year';

  @override
  String get recurrenceScopeHint =>
      'Also shows on matching days before the start date';

  @override
  String recurrenceScopeAlwaysSuffix(String rule) {
    return '$rule · also before';
  }

  @override
  String get datePickerSingleTitle => 'Pick a date';

  @override
  String get datePickerMultiTitle => 'Pick dates';

  @override
  String datePickerSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dates selected',
      one: '1 date selected',
      zero: 'No dates selected',
    );
    return '$_temp0';
  }

  @override
  String get datePickerClear => 'Clear';

  @override
  String get datePickerToday => 'Today';

  @override
  String get datePickerBusyDay => 'Already has events';

  @override
  String get eventDescriptionPreviewOn => 'Show rendered description';

  @override
  String get eventDescriptionPreviewOff => 'Edit description';

  @override
  String get eventDescriptionEmpty => 'Nothing to preview yet';

  @override
  String get eventHasDescription => 'Has notes';

  @override
  String get eventDetailsTitle => 'Event';

  @override
  String get eventDetailsNextOccurrences => 'Next occurrences';

  @override
  String get eventDetailsNoOccurrences => 'No upcoming occurrences';

  @override
  String get eventDetailsNoDescription => 'No notes for this event';

  @override
  String get eventColor => 'Color';

  @override
  String get eventColorCustomTitle => 'Custom color';

  @override
  String get select => 'Select';

  @override
  String get eventTintIcon => 'Tint icon with color';

  @override
  String get eventTintIconHint => 'Use the event color for the icon too';

  @override
  String get eventPriority => 'Priority';

  @override
  String get eventPriorityHint =>
      'Higher priority shows first and keeps its bar when a day is full';

  @override
  String get eventPriorityLowest => 'Lowest';

  @override
  String get eventPriorityLow => 'Low';

  @override
  String get eventPriorityNormal => 'Normal';

  @override
  String get eventPriorityHigh => 'High';

  @override
  String get eventPriorityHighest => 'Highest';

  @override
  String get eventDatesLabel => 'Dates';

  @override
  String get eventDatesHint =>
      'Add more one-off dates to repeat this event without a recurrence';

  @override
  String get eventAddDate => 'Add date';

  @override
  String get eventRemoveDate => 'Remove date';

  @override
  String recurrenceSpecificDates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dates',
      one: 'One date',
    );
    return '$_temp0';
  }

  @override
  String get eventDescription => 'Description';

  @override
  String get eventDescriptionHint => 'Add notes (focus, technique, intensity…)';

  @override
  String get eventLinkedNote => 'Linked note';

  @override
  String get eventLinkNoteHint => 'Link a workout note';

  @override
  String get eventLinkedNoteMissing => 'Linked note no longer exists';

  @override
  String get eventOpenLinkedNote => 'Open linked note';

  @override
  String get eventRemoveNoteLink => 'Remove link';

  @override
  String get iconGroupStrength => 'Strength';

  @override
  String get iconGroupCardio => 'Cardio';

  @override
  String get iconGroupSports => 'Sports';

  @override
  String get iconGroupRecovery => 'Recovery';

  @override
  String get iconGroupBody => 'Body & nutrition';

  @override
  String get iconGroupMeasurement => 'Measurement';

  @override
  String get iconGroupAchievements => 'Achievements';

  @override
  String get iconGroupTravel => 'Travel';

  @override
  String get iconGroupTime => 'Time';

  @override
  String get iconGroupGeneric => 'Other';

  @override
  String get welcomeToGymNotes => 'Welcome to Gym Notes';

  @override
  String get onboardingDescription =>
      'Track your workouts and notes in one place. Get started by creating a fresh workspace or restore from a previous backup.';

  @override
  String get startFresh => 'Start Fresh';

  @override
  String get restoreFromBackup => 'Restore from Backup';

  @override
  String get confirmImport => 'Confirm Import';

  @override
  String get backupContains => 'This backup contains:';

  @override
  String exportedOn(String date) {
    return 'Exported on: $date';
  }

  @override
  String get import => 'Import';

  @override
  String importSuccess(int folders, int notes) {
    return 'Successfully imported $folders folders and $notes notes';
  }

  @override
  String get importFailed => 'Import failed';

  @override
  String get invalidBackupFile => 'Invalid backup file';

  @override
  String get exportBackup => 'Export Backup';

  @override
  String get folders => 'Folders';

  @override
  String get notes => 'Notes';

  @override
  String get createFolder => 'Create Folder';

  @override
  String get createNote => 'Create Note';

  @override
  String get folderName => 'Folder Name';

  @override
  String get noteName => 'Note Name';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get search => 'Search';

  @override
  String error(String message) {
    return 'Error: $message';
  }

  @override
  String created(String date) {
    return 'Created: $date';
  }

  @override
  String updated(String date) {
    return 'Updated: $date';
  }

  @override
  String get deleteFolder => 'Delete Folder';

  @override
  String deleteFolderConfirm(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String deleteFolderWithNotesConfirm(String name, int count) {
    return 'Are you sure you want to delete \"$name\"? This will also delete $count note(s).';
  }

  @override
  String get rename => 'Rename';

  @override
  String get renameFolder => 'Rename Folder';

  @override
  String get untitledNote => 'Untitled Note';

  @override
  String get emptyNote => 'Empty note';

  @override
  String get deleteNote => 'Delete Note';

  @override
  String deleteNoteConfirm(String title) {
    return 'Are you sure you want to delete \"$title\"?';
  }

  @override
  String get deleteThisNote => 'this note';

  @override
  String get enterFolderName => 'Enter folder name';

  @override
  String get newNote => 'New Note';

  @override
  String get switchToEditMode => 'Switch to Edit mode';

  @override
  String get previewMarkdown => 'Preview markdown';

  @override
  String get preview => 'Preview';

  @override
  String get autoSaveOn => 'Auto-save is ON (saves every 5s after changes)';

  @override
  String get enableAutoSave => 'Enable auto-save';

  @override
  String get autoSaveOff => 'Auto-save OFF';

  @override
  String get saveNote => 'Save note';

  @override
  String get noContentYet => '*No content yet*';

  @override
  String get startWriting => 'Start writing your first note...';

  @override
  String get noteCannotBeEmpty => 'Note cannot be empty';

  @override
  String get noteSaved => 'Note saved!';

  @override
  String get editTitle => 'Edit Title';

  @override
  String get enterNoteTitle => 'Enter note title';

  @override
  String get autoSaveEnabled => 'Auto-save enabled';

  @override
  String get autoSaveDisabled => 'Auto-save disabled';

  @override
  String get markdownShortcuts => 'Markdown Shortcuts';

  @override
  String get markdownShortcutsDesc => 'Customize toolbar buttons and actions';

  @override
  String get removeAllCustom => 'Remove All Custom';

  @override
  String get noCustomShortcutsYet => 'No custom shortcuts yet';

  @override
  String get tapToAddShortcut => 'Tap the + button to add one';

  @override
  String get deleteShortcut => 'Delete Shortcut';

  @override
  String get deleteShortcutConfirm =>
      'Are you sure you want to delete this shortcut?';

  @override
  String get resetDialogTitle => 'Reset to Default';

  @override
  String get resetDialogMessage =>
      'This will restore all default shortcuts to their original order and settings. Custom shortcuts will be kept but moved to the end.';

  @override
  String get reset => 'Reset';

  @override
  String get removeCustomDialogTitle => 'Remove All Custom';

  @override
  String get removeCustomDialogMessage =>
      'This will permanently delete all custom shortcuts you created. Default shortcuts will remain.';

  @override
  String get remove => 'Remove';

  @override
  String get defaultLabel => 'DEFAULT';

  @override
  String get insertsCurrentDate => 'Inserts current date';

  @override
  String get opensHeaderMenu => 'Opens header menu (H1-H6)';

  @override
  String beforeAfterText(String before, String after) {
    return 'Before: \"$before\" | After: \"$after\"';
  }

  @override
  String get hide => 'Hide';

  @override
  String get show => 'Show';

  @override
  String get newShortcut => 'New Shortcut';

  @override
  String get editShortcut => 'Edit Shortcut';

  @override
  String get icon => 'Icon';

  @override
  String get tapToChangeIcon => 'Tap to change icon';

  @override
  String get selectIcon => 'Select Icon';

  @override
  String get searchIcons => 'Search icons...';

  @override
  String get noIconsFound => 'No icons found';

  @override
  String get label => 'Label';

  @override
  String get labelHint => 'e.g., Highlight';

  @override
  String get insertType => 'Insert Type';

  @override
  String get wrapSelectedText => 'Wrap Selected Text';

  @override
  String get insertCurrentDate => 'Insert Current Date';

  @override
  String get beforeDate => 'Before Date (optional)';

  @override
  String get markdownStart => 'Markdown Start';

  @override
  String get markdownStartHint => 'e.g., ==';

  @override
  String get optionalTextBeforeDate => 'Optional text before date';

  @override
  String get afterDate => 'After Date (optional)';

  @override
  String get markdownEnd => 'Markdown End';

  @override
  String get optionalTextAfterDate => 'Optional text after date';

  @override
  String get labelCannotBeEmpty => 'Label cannot be empty';

  @override
  String get formHasErrors => 'Please fix the errors in the form';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get headers => 'Headers';

  @override
  String get pointList => 'Point List';

  @override
  String get strikethrough => 'Strikethrough';

  @override
  String get bulletList => 'Bullet List';

  @override
  String get numberedList => 'Numbered List';

  @override
  String get checkbox => 'Checkbox';

  @override
  String get quote => 'Quote';

  @override
  String get inlineCode => 'Inline Code';

  @override
  String get codeBlock => 'Code Block';

  @override
  String get link => 'Link';

  @override
  String get currentDate => 'Current Date';

  @override
  String get header1 => 'Header 1';

  @override
  String get header2 => 'Header 2';

  @override
  String get header3 => 'Header 3';

  @override
  String get header4 => 'Header 4';

  @override
  String get header5 => 'Header 5';

  @override
  String get header6 => 'Header 6';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get paste => 'Paste';

  @override
  String get decreaseFontSize => 'Decrease Font Size';

  @override
  String get increaseFontSize => 'Increase Font Size';

  @override
  String get settings => 'Settings';

  @override
  String get dropPosition => 'Drop position';

  @override
  String get longPressToReorder => 'Long press to reorder';

  @override
  String shortcutButton(String label) {
    return '$label button';
  }

  @override
  String get markdownSpaceWarning =>
      'Tip: Add a space after markdown syntax (e.g., \'# \' or \'- \') for proper formatting.';

  @override
  String get reorderShortcuts => 'Reorder shortcuts';

  @override
  String get doneReordering => 'Done';

  @override
  String get noSearchResults => 'No results found';

  @override
  String get searchHint => 'Type to search notes';

  @override
  String get loadingMore => 'Loading more...';

  @override
  String get noMoreNotes => 'No more notes';

  @override
  String get sortBy => 'Sort by';

  @override
  String get sortByUpdated => 'Last updated';

  @override
  String get sortByCreated => 'Date created';

  @override
  String get sortByTitle => 'Title';

  @override
  String get ascending => 'Ascending';

  @override
  String get descending => 'Descending';

  @override
  String get loadingContent => 'Loading content...';

  @override
  String get largeNoteWarning =>
      'This note is very large and may take a moment to load';

  @override
  String noteStats(int count, int chunks) {
    return '$count distinct characters, $chunks chunks';
  }

  @override
  String get compressedNote => 'Compressed';

  @override
  String get searchInFolder => 'Search in this folder';

  @override
  String get searchAll => 'Search all notes';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearSearchHistory => 'Clear search history';

  @override
  String get filterByDate => 'Filter by date';

  @override
  String get fromDate => 'From';

  @override
  String get toDate => 'To';

  @override
  String get applyFilter => 'Apply filter';

  @override
  String get clearFilter => 'Clear filter';

  @override
  String matchesFound(int count) {
    return '$count matches found';
  }

  @override
  String get autoSaving => 'Auto-saving...';

  @override
  String get changesSaved => 'Changes saved';

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get discardChanges => 'Discard changes';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get virtualScrollEnabled => 'Virtual scroll enabled for large content';

  @override
  String lineCount(int count) {
    return '$count lines';
  }

  @override
  String get emptyFoldersHint => 'Looks like you might want to create a folder';

  @override
  String get emptyNotesHint => 'Write your first note';

  @override
  String get tapPlusToCreate => 'Tap + to get started';

  @override
  String charactersCount(int current, int max) {
    return '$current/$max characters';
  }

  @override
  String get databaseSettings => 'Database';

  @override
  String get databaseSettingsDesc => 'Manage database location and storage';

  @override
  String get about => 'About';

  @override
  String get databaseLocation => 'Database Location';

  @override
  String get copyPath => 'Copy Path';

  @override
  String get openInFinder => 'Open Folder';

  @override
  String get databaseStats => 'Statistics';

  @override
  String get size => 'Size';

  @override
  String get lastModified => 'Last Modified';

  @override
  String get maintenance => 'Maintenance';

  @override
  String get maintenanceDesc =>
      'Run SQLite VACUUM to reclaim unused space from deleted notes and folders. This rebuilds the database file, defragments the data, and can significantly reduce file size after deleting large amounts of content. The operation may take a few seconds depending on database size.';

  @override
  String get optimizeDatabase => 'Optimize Database';

  @override
  String get dangerZone => 'Danger Zone';

  @override
  String get dangerZoneDesc =>
      'These actions are irreversible. All your notes and folders will be permanently deleted.';

  @override
  String get deleteAllData => 'Delete All Data';

  @override
  String get pathCopied => 'Path copied to clipboard';

  @override
  String get notSupportedOnPlatform => 'Not supported on this platform';

  @override
  String get errorOpeningFolder => 'Error opening folder';

  @override
  String get optimizing => 'Optimizing database...';

  @override
  String get optimizationComplete => 'Database optimized successfully';

  @override
  String get saved => 'saved';

  @override
  String get alreadyOptimized => 'database already optimized';

  @override
  String get deleteConfirmation =>
      'This action cannot be undone. All your notes, folders, and data will be permanently deleted. Are you absolutely sure?';

  @override
  String get deleteNotImplemented =>
      'Delete functionality not yet implemented for safety';

  @override
  String get deletingData => 'Deleting all data...';

  @override
  String get dataDeleted => 'Data Deleted';

  @override
  String get restartRequired => 'Restart may be required for full effect';

  @override
  String get exitApp => 'Exit App';

  @override
  String get errorDeletingData => 'Error deleting data';

  @override
  String get shareDatabase => 'Share Database';

  @override
  String get shareDatabaseDesc =>
      'Export and share your database file via email, messaging apps, or cloud storage for backup purposes.';

  @override
  String get preparingShare => 'Preparing to share...';

  @override
  String get shareError => 'Error sharing database';

  @override
  String get databaseNotFound => 'Database file not found';

  @override
  String get renameNote => 'Rename Note';

  @override
  String get enterNewName => 'Enter new name';

  @override
  String get reorderMode => 'Reorder Mode';

  @override
  String get dragToReorder => 'Drag items to reorder';

  @override
  String get sortByCustom => 'Custom Order';

  @override
  String get quickSort => 'Quick Sort';

  @override
  String get sortItems => 'Sort Items';

  @override
  String get sortFolders => 'Sort Folders';

  @override
  String get sortNotes => 'Sort Notes';

  @override
  String get sortByName => 'By Name';

  @override
  String get moveUp => 'Move Up';

  @override
  String get moveDown => 'Move Down';

  @override
  String get controlsSettings => 'Controls';

  @override
  String get controlsSettingsDesc => 'Gestures, haptics and interactions';

  @override
  String get gesturesSection => 'Gestures';

  @override
  String get folderSwipeGesture => 'Swipe to open menu in folders';

  @override
  String get folderSwipeGestureDesc =>
      'Swipe from left edge to open the navigation menu when browsing folders';

  @override
  String get noteSwipeGesture => 'Swipe to open menu in notes';

  @override
  String get noteSwipeGestureDesc =>
      'Swipe from left edge to open the navigation menu when editing notes';

  @override
  String get feedbackSection => 'Feedback';

  @override
  String get hapticFeedback => 'Haptic feedback';

  @override
  String get hapticFeedbackDesc =>
      'Vibrate on interactions like toggling switches';

  @override
  String get confirmDelete => 'Confirm before delete';

  @override
  String get confirmDeleteDesc =>
      'Show confirmation dialog before deleting notes or folders';

  @override
  String get autoSaveSection => 'Auto-save';

  @override
  String get autoSave => 'Auto-save notes';

  @override
  String get autoSaveDesc => 'Automatically save notes while editing';

  @override
  String get autoSaveInterval => 'Auto-save interval';

  @override
  String autoSaveIntervalDesc(int seconds) {
    return 'Save every $seconds seconds';
  }

  @override
  String get displaySection => 'Display';

  @override
  String get showNotePreview => 'Show note preview';

  @override
  String get showNotePreviewDesc =>
      'Display a preview of note content in the list';

  @override
  String get showStatsBar => 'Show stats bar';

  @override
  String get showStatsBarDesc =>
      'Display character count and line count in note editor';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get resetToDefaultsConfirm =>
      'Are you sure you want to reset all settings to their default values?';

  @override
  String get settingsReset => 'Settings have been reset to defaults';

  @override
  String get shareNote => 'Share Note';

  @override
  String get shareFolder => 'Share Folder';

  @override
  String get exportingFolder => 'Exporting folder...';

  @override
  String get folderExportError => 'Error exporting folder';

  @override
  String get importingFile => 'Importing...';

  @override
  String get importFileError => 'Error importing file';

  @override
  String get importNoteOrFolder => 'Import';

  @override
  String importedSummary(int folders, int notes) {
    return 'Imported $folders folders, $notes notes';
  }

  @override
  String get shareSelected => 'Share';

  @override
  String get exportingSelection => 'Exporting selection...';

  @override
  String get selectionExportError => 'Error exporting selection';

  @override
  String get noteOptions => 'Note Options';

  @override
  String get exportingNote => 'Exporting note...';

  @override
  String get noteExportError => 'Error exporting note';

  @override
  String get chooseExportFormat => 'Choose Export Format';

  @override
  String get exportAsMarkdown => 'Markdown (.md)';

  @override
  String get exportAsJson => 'JSON (.json)';

  @override
  String get exportAsText => 'Plain Text (.txt)';

  @override
  String get activeDatabaseSection => 'Active Database';

  @override
  String get activeDatabaseDesc =>
      'Select which database to use. Creating or switching databases will restart the app.';

  @override
  String get selectDatabase => 'Select Database';

  @override
  String currentDatabase(String name) {
    return 'Current: $name';
  }

  @override
  String get createNewDatabase => 'Create New Database';

  @override
  String get newDatabaseName => 'Database Name';

  @override
  String get enterDatabaseName => 'Enter database name';

  @override
  String get invalidDatabaseName =>
      'Invalid name. Use only letters, numbers, underscores, and hyphens (max 50 characters).';

  @override
  String get databaseExists => 'A database with this name already exists.';

  @override
  String get creatingDatabase => 'Creating database...';

  @override
  String get databaseCreated => 'Database created successfully';

  @override
  String get renameDatabase => 'Rename Database';

  @override
  String get renamingDatabase => 'Renaming database...';

  @override
  String get databaseRenamed => 'Database renamed successfully';

  @override
  String get switchingDatabase => 'Switching database...';

  @override
  String get availableDatabases => 'Available Databases';

  @override
  String get noDatabases => 'No databases found';

  @override
  String get databaseOptions => 'Database Options';

  @override
  String get switchTo => 'Switch to this database';

  @override
  String deleteDatabaseConfirm(String name) {
    return 'Are you sure you want to delete the database \"$name\"? This action cannot be undone.';
  }

  @override
  String get cannotDeleteActive =>
      'Cannot delete the currently active database. Please switch to another database first.';

  @override
  String get databaseDeleted => 'Database deleted';

  @override
  String get findInNote => 'Find in note';

  @override
  String get replaceWith => 'Replace with';

  @override
  String get replaceOne => 'Replace';

  @override
  String get replaceAll => 'All';

  @override
  String replacedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Replaced $count matches',
      one: 'Replaced 1 match',
    );
    return '$_temp0';
  }

  @override
  String get matchCase => 'Match case';

  @override
  String get wholeWord => 'Whole word';

  @override
  String get useRegex => 'Use regex';

  @override
  String get findAndReplace => 'Find & Replace';

  @override
  String get options => 'Options';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get close => 'Close';

  @override
  String get dateFormatSettings => 'Date Format';

  @override
  String get selectDateFormat => 'Choose how dates will be displayed:';

  @override
  String get longPressToChangeFormat => 'Long press to change format';

  @override
  String get languageSettings => 'Language';

  @override
  String get languageSettingsDesc => 'Change app display language';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get english => 'English';

  @override
  String get german => 'German';

  @override
  String get romanian => 'Romanian';

  @override
  String get systemDefault => 'System Default';

  @override
  String get themeSettings => 'Appearance';

  @override
  String get themeSettingsDesc => 'Dark mode, colors and display';

  @override
  String get selectTheme => 'Select Theme';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get systemTheme => 'System';

  @override
  String get searchSection => 'Search';

  @override
  String get searchCursorBehavior => 'Search Navigation';

  @override
  String get searchCursorBehaviorDesc =>
      'Where to place the cursor when jumping to a search match';

  @override
  String get cursorAtStart => 'Before';

  @override
  String get cursorAtEnd => 'After';

  @override
  String get selectMatch => 'Select';

  @override
  String get searching => 'Searching...';

  @override
  String get editorSection => 'Editor';

  @override
  String get liveMarkdownRendering => 'Live Markdown Rendering';

  @override
  String get liveMarkdownRenderingDesc =>
      'Render headers, lists, checkboxes and text styles directly while editing';

  @override
  String get showLineNumbers => 'Line Numbers';

  @override
  String get showLineNumbersDesc =>
      'Display line numbers on the left side of the editor';

  @override
  String get wordWrap => 'Word Wrap';

  @override
  String get wordWrapDesc => 'Wrap long lines to fit within the editor width';

  @override
  String get showCursorLine => 'Highlight Current Line';

  @override
  String get showCursorLineDesc =>
      'Highlight the line where the cursor is positioned';

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
  String get previewSection => 'Preview';

  @override
  String get showPreviewScrollbar => 'Preview Scrollbar';

  @override
  String get showPreviewScrollbarDesc =>
      'Show an interactive scrollbar in preview mode (experimental)';

  @override
  String get previewPerformanceSection => 'Preview Performance';

  @override
  String get previewLinesPerChunk => 'Lines Per Chunk';

  @override
  String previewLinesPerChunkDesc(int count) {
    return '$count lines per chunk (higher = better performance, lower = more precise search scroll)';
  }

  @override
  String get calendarSection => 'Calendar';

  @override
  String get calendarSettings => 'Calendar';

  @override
  String get calendarMaxDayBars => 'Maximum bars per day';

  @override
  String calendarMaxDayBarsDesc(int count) {
    return 'Show up to $count bars per day. Extra categories collapse into a +N indicator.';
  }

  @override
  String get calendarAppearanceSection => 'Appearance';

  @override
  String get calendarTodayStyleTitle => 'Today highlight';

  @override
  String get todayStyleTonal => 'Soft';

  @override
  String get todayStyleRing => 'Ring';

  @override
  String get todayStyleFilled => 'Filled';

  @override
  String get calendarAccentColor => 'Highlight color';

  @override
  String get calendarAccentColorDesc => 'Colors today and the selected day';

  @override
  String get calendarAccentThemeDefault => 'Theme color';

  @override
  String get calendarMarkerStyleTitle => 'Event markers';

  @override
  String get markerStyleBars => 'Bars';

  @override
  String get markerStyleDots => 'Dots';

  @override
  String get calendarHighlightWeekends => 'Tint weekends';

  @override
  String get calendarHighlightWeekendsDesc =>
      'Show Saturday and Sunday in a distinct color';

  @override
  String get calendarShowWeekNumbers => 'Week numbers';

  @override
  String get calendarShowWeekNumbersDesc =>
      'Show week numbers at the left edge';

  @override
  String get calendarWeekStartTitle => 'Week starts on';

  @override
  String daySummaryEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get dateOffset => 'Date Offset';

  @override
  String get dateOffsetDescription =>
      'Shift the date forward or backward from today';

  @override
  String get days => 'Days';

  @override
  String get monthsLabel => 'Months';

  @override
  String get yearsLabel => 'Years';

  @override
  String get repeatSettings => 'Repeat';

  @override
  String get repeatDescription => 'Insert this shortcut multiple times';

  @override
  String get repeatCount => 'Repeat count';

  @override
  String get separator => 'Separator';

  @override
  String get newLine => 'New line';

  @override
  String get noSeparator => 'None';

  @override
  String get space => 'Space';

  @override
  String get nbspSpace => 'Non-breaking';

  @override
  String get blankLine => 'Blank line';

  @override
  String get comma => 'Comma';

  @override
  String get pipe => 'Pipe';

  @override
  String get incrementDateOnRepeat => 'Increment date on repeat';

  @override
  String get incrementByEachRepeat => 'Increment by for each repetition:';

  @override
  String get advancedOptions => 'Advanced Options';

  @override
  String get advancedOptionsDescription => 'Date offset, repeat, and more';

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
  String get toolbarLayout => 'Toolbar Layout';

  @override
  String get shortcuts => 'Shortcuts';

  @override
  String get utilities => 'Utilities';

  @override
  String get splitToolbar => 'Split toolbar';

  @override
  String get utilityButtons => 'Utility Buttons';

  @override
  String get utilityButtonsHint => 'Toggle visibility and drag to reorder';

  @override
  String get markdownBars => 'Markdown Bars';

  @override
  String get activeBar => 'Active Bar';

  @override
  String get editingBar => 'Editing Bar';

  @override
  String get addBar => 'Add Bar';

  @override
  String get deleteBar => 'Delete Bar';

  @override
  String get deleteBarConfirm =>
      'Are you sure you want to delete this bar? Notes using it will fall back to the global active bar.';

  @override
  String get renameBar => 'Rename Bar';

  @override
  String get duplicateBar => 'Duplicate Bar';

  @override
  String get barName => 'Bar Name';

  @override
  String get defaultBar => 'Default';

  @override
  String get switchBar => 'Switch Bar';

  @override
  String get searchBars => 'Search bars...';

  @override
  String get noMatchingBars => 'No matching bars';

  @override
  String get perNoteBarAssignment => 'Per-Note Bar Assignment';

  @override
  String get perNoteBarHint =>
      'Assign a specific bar to individual notes. Notes without an override use the global active bar.';

  @override
  String get useGlobalBar => 'Use Global Bar';

  @override
  String get cannotDeleteDefault => 'Cannot delete the default bar';

  @override
  String get cannotRenameDefault => 'Cannot rename the default bar';

  @override
  String get barSwitcherTitle => 'Select Markdown Bar';

  @override
  String get noteBarOverride => 'Note Override';

  @override
  String get clearOverride => 'Clear Override';

  @override
  String get manageBarProfiles => 'Manage Bar Profiles';

  @override
  String get alwaysVisible => 'Always visible';

  @override
  String get visible => 'Visible';

  @override
  String get goToTop => 'Go to Top';

  @override
  String get goToBottom => 'Go to Bottom';

  @override
  String get hidden => 'Hidden';

  @override
  String get insertCounter => 'Insert Counter Value';

  @override
  String get counterBindingsTitle => 'Counter Bindings';

  @override
  String get counterBindingsDescription =>
      'Bind up to two counters to this shortcut and use the c1 and c2 tokens (in curly braces) inside the before/after text to insert their values. Each token expansion mutates the counter once per repeat.';

  @override
  String get addCounterBinding => 'Add counter binding';

  @override
  String get addSecondCounterBinding => 'Add second counter binding';

  @override
  String get removeCounterBinding => 'Remove counter binding';

  @override
  String get counterTokensHint =>
      'Tap a token to insert it where the cursor is.';

  @override
  String get counterOperation => 'Operation';

  @override
  String get counterOpIncrement => 'Increment';

  @override
  String get counterOpKeep => 'Keep';

  @override
  String get counterOpDecrement => 'Decrement';

  @override
  String get selectCounter => 'Select Counter';

  @override
  String get noCountersYet => 'No counters created yet';

  @override
  String get noCountersYetHint =>
      'No counters created yet. Use the \"Add counter\" button below to create one.';

  @override
  String get addCounter => 'Add Counter';

  @override
  String get counterName => 'Counter Name';

  @override
  String get startValue => 'Start Value';

  @override
  String get step => 'Step';

  @override
  String get counterScope => 'Counter Scope';

  @override
  String get global => 'Global';

  @override
  String get perNote => 'Per Note';

  @override
  String get editCounter => 'Edit Counter';

  @override
  String get deleteCounter => 'Delete Counter';

  @override
  String get deleteCounterConfirm =>
      'Are you sure you want to delete this counter? This cannot be undone.';

  @override
  String get resetCounter => 'Reset Counter';

  @override
  String get resetCounterConfirm => 'Reset this counter to its start value?';

  @override
  String get counters => 'Counters';

  @override
  String get counterSettings => 'Counters';

  @override
  String get counterSettingsDesc => 'Create and manage auto-increment counters';

  @override
  String counterCurrentValue(int value) {
    return 'Current: $value';
  }

  @override
  String counterStepLabel(int step) {
    return 'Step: $step';
  }

  @override
  String get counterEmptyState => 'No counters yet. Tap + to create one.';

  @override
  String get counterResetSuccess => 'Counter reset to start value';

  @override
  String get counterDeleteSuccess => 'Counter deleted';

  @override
  String get counterSetValue => 'Set Value';

  @override
  String get counterValuePerNote => 'Value varies per note';

  @override
  String get counterScopeGlobalDesc => 'Shared across all notes';

  @override
  String get counterScopePerNoteDesc => 'Independent value per note';

  @override
  String get pickCounter => 'Pick Counter';

  @override
  String get searchCounters => 'Search counters…';

  @override
  String get noCountersMatchSearch => 'No counters match your search';

  @override
  String get counterInsertTooltip => 'Insert counter value';

  @override
  String get createCounterInline => 'Create new counter';

  @override
  String get manageCounters => 'Manage counters';

  @override
  String counterPickerPage(int current, int total) {
    return '$current / $total';
  }

  @override
  String get selectNote => 'Select a note';

  @override
  String get searchNotes => 'Search notes…';

  @override
  String get noNotesAvailable => 'No notes yet';

  @override
  String get noNotesMatchSearch => 'No notes match your search';

  @override
  String get counterSelectNoteToView => 'Tap to manage note values';

  @override
  String get counterLoadError => 'Failed to load counters';

  @override
  String get counterRetry => 'Retry';

  @override
  String get counterPerNoteValues => 'Values per Note';

  @override
  String get counterPerNoteEmpty => 'No notes have values for this counter yet';

  @override
  String get counterResetAllNotes => 'Reset All Notes';

  @override
  String get counterResetAllConfirm =>
      'Reset this counter to its start value for all notes?';

  @override
  String get counterResetAllSuccess => 'All note values reset';

  @override
  String get counterManageNoteValues => 'Manage note values';

  @override
  String get pinCounter => 'Pin';

  @override
  String get unpinCounter => 'Unpin';

  @override
  String get addNote => 'Add Note';

  @override
  String get removeNote => 'Remove Note';

  @override
  String get removeNoteConfirm =>
      'Remove this note from the counter? The value will be lost.';

  @override
  String get noteAlreadyAdded => 'This note is already added';

  @override
  String get moveToFolder => 'Move to Folder';

  @override
  String get selectDestinationFolder => 'Select Destination';

  @override
  String get moveToTitle => 'Move to…';

  @override
  String get currentlyIn => 'Currently in';

  @override
  String subfoldersOf(String name) {
    return 'Subfolders of $name';
  }

  @override
  String moveToDestination(String name) {
    return 'Move to $name';
  }

  @override
  String get rootFolder => 'Root';

  @override
  String get noteMoved => 'Note moved successfully';

  @override
  String get noteMoveFailed => 'Failed to move note';

  @override
  String get alreadyInThisFolder => 'Note is already in this folder';

  @override
  String get noFoldersAvailable => 'No folders available';

  @override
  String get noSubfolders => 'No subfolders here';

  @override
  String get back => 'Back';

  @override
  String get openFolder => 'Open folder';

  @override
  String get selectAsDestination => 'Select as destination';

  @override
  String get moveHere => 'Move Here';

  @override
  String get folderMoved => 'Folder moved successfully';

  @override
  String get folderMoveFailed => 'Failed to move folder';

  @override
  String get cannotMoveIntoSelf =>
      'Cannot move a folder into itself or its subfolder';

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
  String get moveHistory => 'Move History';

  @override
  String get noMoveHistory => 'No recent moves';

  @override
  String get clearHistory => 'Clear History';

  @override
  String movedToTarget(String target) {
    return 'Moved to $target';
  }

  @override
  String get undone => 'Undone';

  @override
  String get moveUndone => 'Move undone';

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
  String get originalLocationGone => 'Original location no longer exists';

  @override
  String get moveUndoCanceled => 'Restore canceled';

  @override
  String get clearMoveHistoryConfirm =>
      'Clear all move history? This cannot be undone.';

  @override
  String get searchFolders => 'Search folders';

  @override
  String get noFoldersFound => 'No folders found';

  @override
  String get recentDestinations => 'Recent';

  @override
  String itemsMoved(int count) {
    return '$count items moved';
  }

  @override
  String get moveSelected => 'Move';

  @override
  String get deleteSelected => 'Delete';

  @override
  String deleteSelectedConfirm(int count) {
    return 'Delete $count selected items? This cannot be undone.';
  }

  @override
  String get selectAll => 'Select all';

  @override
  String get linkOpenFailed => 'Couldn\'t open link';

  @override
  String get linkSchemeNotAllowed => 'Link type not supported';

  @override
  String linkOpenPrompt(String target) {
    return 'Open $target?';
  }

  @override
  String get linkOpenAction => 'Open';

  @override
  String get moneySection => 'Money ledger';

  @override
  String get moneyLedgerEnabledLabel => 'Enable money ledger';

  @override
  String get moneyLedgerEnabledDesc =>
      'Render \$ money lines in notes and on the calendar';

  @override
  String get moneyStartBalance => 'Start balance';

  @override
  String get moneyStartBalanceDesc =>
      'Every note\'s ledger starts from this amount';

  @override
  String get moneyCurrencySymbolLabel => 'Currency symbol';

  @override
  String get moneyCurrencySymbolDesc =>
      'Shown on computed amounts (e.g. lei, €, \$)';

  @override
  String get moneyCurrencySuffixLabel => 'Symbol after amount';

  @override
  String get moneyCurrencySuffixDesc => '12.50 lei instead of lei12.50';

  @override
  String get moneyPerNoteCurrency => 'Per-note currency';

  @override
  String get useGlobalCurrency => 'Use global currency';

  @override
  String get moneyCustomSymbol => 'Custom…';

  @override
  String get moneyDetailTitle => 'Ledger';

  @override
  String get moneyErrorMissingAmount => 'missing amount after \":\"';

  @override
  String get moneyErrorUnknownColour => 'unknown colour name';

  @override
  String get moneyErrorInvalidAmount => 'invalid amount';

  @override
  String get moneyErrorInvalidCount => 'invalid count';

  @override
  String get moneyErrorDivideByZero => 'divide by zero';

  @override
  String get moneyErrorAmountTooLarge =>
      'amount too large (max 99,999,999,999.99)';

  @override
  String get moneyErrorTooManyDecimals => 'too many decimals';

  @override
  String moneyDaySummaryTitle(String amount) {
    return 'Money: $amount';
  }

  @override
  String get markdownColorsTitle => 'Text colors';

  @override
  String get markdownColorsSubtitle => 'Colors for text and highlights';

  @override
  String get markdownColorsHowTo =>
      'Type a color name before the text. Unknown names stay plain.';

  @override
  String get markdownColorsSampleText => 'sample text';

  @override
  String get markdownColorsFallbackNote =>
      'Custom colors are adjusted automatically when they would be unreadable on the current theme.';

  @override
  String get markdownColorsPresets => 'Presets';

  @override
  String get markdownColorsCustom => 'Custom colors';

  @override
  String get markdownColorsEmpty => 'No custom colors yet. Tap + to add one.';

  @override
  String get markdownColorsNameTitle => 'Color name';

  @override
  String get markdownColorsNameHint => 'lowercase letters, digits, - and _';

  @override
  String get markdownColorsNameInvalid =>
      'Enter a name using letters, digits, - or _';

  @override
  String get markdownColorsRecolor => 'Change color';

  @override
  String get markdownColorsRename => 'Rename';

  @override
  String get markdownColorsDelete => 'Delete';

  @override
  String get markdownColorsDeleteTitle => 'Delete color';

  @override
  String get markdownColorsOverridden => 'Overridden by a custom color';

  @override
  String markdownColorsNameTaken(String name) {
    return '\"$name\" is already used';
  }

  @override
  String markdownColorsLimitReached(int count) {
    return 'Color limit reached ($count)';
  }

  @override
  String markdownColorsDeleteMessage(String name) {
    return 'Delete \"$name\"? Notes using it will show plain text.';
  }

  @override
  String get upcomingEvents => 'Upcoming';

  @override
  String get upcomingSearchHint => 'Search events';

  @override
  String get upcomingClearSearch => 'Clear search';

  @override
  String upcomingPeriodDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get upcomingPeriodCustom => 'Custom';

  @override
  String get upcomingPriority => 'Priority';

  @override
  String get upcomingPriorityAny => 'Any';

  @override
  String get upcomingNoEvents => 'Nothing coming up';

  @override
  String get upcomingNoEventsHint => 'Try a longer period or a lower priority';

  @override
  String get upcomingToday => 'Today';

  @override
  String get upcomingTomorrow => 'Tomorrow';

  @override
  String get upcomingEditEvent => 'Edit event';

  @override
  String get upcomingShowHolidays => 'Holidays';

  @override
  String get upcomingFilters => 'Filters';

  @override
  String get panelExpand => 'Expand panel';

  @override
  String get panelShowCalendar => 'Show calendar';

  @override
  String get panelModeDay => 'Day';

  @override
  String get panelModeTimeline => 'Timeline';

  @override
  String get timelineEmptyHint =>
      'Events with a start time appear on the timeline';

  @override
  String get exportEventsIcs => 'Export events (.ics)';

  @override
  String get exportingEvents => 'Exporting events...';

  @override
  String get eventsExportError => 'Could not export events';

  @override
  String eventsExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count events exported',
      one: '1 event exported',
      zero: 'No events exported',
    );
    return '$_temp0';
  }
}
