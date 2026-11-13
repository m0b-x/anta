import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ro.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('ro'),
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'ANTA'**
  String get appTitle;

  /// Drawer item and page title for the calendar feature, also the view menu row opening it
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// Drawer subtitle for the calendar feature
  ///
  /// In en, this message translates to:
  /// **'Plan gym sessions and events'**
  String get calendarDesc;

  /// Empty state shown when the selected calendar day has no events
  ///
  /// In en, this message translates to:
  /// **'No events for this day'**
  String get calendarNoEventsForDay;

  /// Button or tooltip for creating a calendar event
  ///
  /// In en, this message translates to:
  /// **'Add event'**
  String get addEvent;

  /// Label for a calendar event title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get eventTitle;

  /// Label for an all-day calendar event
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get eventAllDay;

  /// Label for the event start-time picker
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get eventStartTime;

  /// Label for the event end-time picker when set
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get eventEndTime;

  /// Title shown when an event has no end time set
  ///
  /// In en, this message translates to:
  /// **'No end time'**
  String get eventEndTimeNone;

  /// Hint shown when the chosen end time crosses midnight
  ///
  /// In en, this message translates to:
  /// **'Ends next day'**
  String get eventCrossesMidnight;

  /// Calendar view menu row showing the grid a month at a time
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarFormatMonth;

  /// Calendar view menu row showing the grid two weeks at a time
  ///
  /// In en, this message translates to:
  /// **'2 weeks'**
  String get calendarFormatTwoWeeks;

  /// Calendar view menu row showing the grid a week at a time
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarFormatWeek;

  /// Title of the calendar filter sheet
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get calendarFiltersTitle;

  /// Label of the filter sheet's row that names the saved filter the draft matches and opens the saved-filters sheet
  ///
  /// In en, this message translates to:
  /// **'Saved filter'**
  String get calendarFilterSavedFilter;

  /// Value of the filter sheet's saved-filter row while the draft matches no saved filter
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get calendarFilterSavedNone;

  /// Section label above the filter sheet's narrowing rows (categories, priority, repeat, time of day, only show)
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get calendarFilterSectionEvents;

  /// Value of the filter sheet's Categories row while no category is hidden
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get calendarFilterCategoriesAll;

  /// Value of the filter sheet's Only show row while no trait is set
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get calendarFilterOnlyShowAny;

  /// Section label above the filter sheet's layer switches (holidays, fasting, money) and the day-panel switch
  ///
  /// In en, this message translates to:
  /// **'Also show'**
  String get calendarFilterSectionAlsoShow;

  /// Action row at the bottom of the filter sheet that clears every filter; the sheet stays open
  ///
  /// In en, this message translates to:
  /// **'Reset filters'**
  String get calendarFilterReset;

  /// First row of the saved-filters sheet, checked while nothing is filtered; tapping it clears every filter
  ///
  /// In en, this message translates to:
  /// **'No filter'**
  String get filterPresetNone;

  /// Section label for the calendar filter that keeps only repeating or only one-time events
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get calendarFilterRepeat;

  /// Section label for the calendar filter that keeps only timed or only all-day events
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get calendarFilterTiming;

  /// Calendar filter option keeping only events that carry a time of day
  ///
  /// In en, this message translates to:
  /// **'Timed'**
  String get calendarFilterTimed;

  /// Section label for the calendar filter's on/off traits
  ///
  /// In en, this message translates to:
  /// **'Only show'**
  String get calendarFilterOnlyShow;

  /// Calendar filter option keeping only events that track presence
  ///
  /// In en, this message translates to:
  /// **'Tracked'**
  String get calendarFilterTracked;

  /// Calendar filter option keeping only events whose end date has not passed; read as "Only show … Not ended" on the filter sheet and as a chip above the grid
  ///
  /// In en, this message translates to:
  /// **'Not ended'**
  String get calendarFilterHideEnded;

  /// Calendar filter option keeping only events that carry description text
  ///
  /// In en, this message translates to:
  /// **'With description'**
  String get calendarFilterWithDescription;

  /// Calendar filter option keeping only events whose linked note has ledger entries
  ///
  /// In en, this message translates to:
  /// **'With money'**
  String get calendarFilterWithMoney;

  /// Calendar filter option keeping only events that show an occurrence count label
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get calendarFilterCounted;

  /// Calendar filter toggle for the money bar and the day panel's money row
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get calendarFilterMoneyLayer;

  /// Chip naming a day-annotation layer the calendar filter has turned off
  ///
  /// In en, this message translates to:
  /// **'Without {layer}'**
  String calendarFilterLayerHidden(String layer);

  /// Switch under the filter sheet's Also show label that exempts the day and timeline panels from the calendar filters
  ///
  /// In en, this message translates to:
  /// **'All events in the day panel'**
  String get calendarFilterPanelShowsAll;

  /// Summary shown for a saved filter that hides nothing
  ///
  /// In en, this message translates to:
  /// **'Shows everything'**
  String get calendarFilterShowsEverything;

  /// Summary label when every event category is hidden
  ///
  /// In en, this message translates to:
  /// **'No categories'**
  String get calendarFilterNoCategories;

  /// Title of the saved-filters sheet and the tooltip of the button that opens it
  ///
  /// In en, this message translates to:
  /// **'Saved filters'**
  String get filterPresetsTitle;

  /// Hint text of the saved-filter search field
  ///
  /// In en, this message translates to:
  /// **'Search saved filters'**
  String get filterPresetSearchHint;

  /// Shown when a saved-filter search returns nothing
  ///
  /// In en, this message translates to:
  /// **'No saved filter matches your search'**
  String get filterPresetNoMatches;

  /// Tooltip and dialog title for saving the current filter
  ///
  /// In en, this message translates to:
  /// **'Save filter'**
  String get filterPresetSave;

  /// Confirmation after saving a filter, and the tooltip once the current filter is already saved
  ///
  /// In en, this message translates to:
  /// **'Saved as \"{name}\"'**
  String filterPresetSaved(String name);

  /// Row in the saved-filters sheet that saves the filter currently applied to the calendar
  ///
  /// In en, this message translates to:
  /// **'Save the current filter'**
  String get filterPresetSaveCurrent;

  /// Label of the saved-filter name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get filterPresetName;

  /// Menu item and dialog title for renaming a saved filter
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get filterPresetRename;

  /// Menu item that re-points a saved filter at what the calendar shows now
  ///
  /// In en, this message translates to:
  /// **'Update to current filter'**
  String get filterPresetUpdate;

  /// Menu item and confirmation title for deleting a saved filter
  ///
  /// In en, this message translates to:
  /// **'Delete saved filter'**
  String get filterPresetDelete;

  /// Confirmation body for deleting a saved filter
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? The events it hides are untouched.'**
  String filterPresetDeleteConfirm(String name);

  /// Tooltip of the per-row menu in the saved-filters sheet
  ///
  /// In en, this message translates to:
  /// **'Saved filter options'**
  String get filterPresetActions;

  /// Shown when the saved-filter limit is reached
  ///
  /// In en, this message translates to:
  /// **'You can save up to {count} filters'**
  String filterPresetLimitReached(int count);

  /// Accessible name of the drag handle on a saved-filter row (a label, never a tooltip)
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get filterPresetReorder;

  /// Tooltip for the calendar filter button
  ///
  /// In en, this message translates to:
  /// **'Filter calendar'**
  String get filterCalendar;

  /// Tooltip for the button that jumps the calendar back to today
  ///
  /// In en, this message translates to:
  /// **'Go to today'**
  String get goToToday;

  /// Generic confirm button label
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// Tooltip/semantics label for the weekend bar in a calendar day cell
  ///
  /// In en, this message translates to:
  /// **'Weekend'**
  String get dayBarWeekend;

  /// Tooltip/semantics label for the public holiday bar in a calendar day cell
  ///
  /// In en, this message translates to:
  /// **'Public holiday'**
  String get dayBarPublicHoliday;

  /// Semantics label for a missed occurrence on the day-cell rail, so the missed state is announced and not carried by colour alone
  ///
  /// In en, this message translates to:
  /// **'{title}, missed'**
  String calendarRailMarkMissedLabel(String title);

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'New Year\'s Day'**
  String get publicHolidayNewYear;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Labour Day'**
  String get publicHolidayLabourDay;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Christmas Day'**
  String get publicHolidayChristmasDay;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Second Day of Christmas'**
  String get publicHolidaySecondChristmasDay;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Epiphany'**
  String get publicHolidayEpiphany;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Good Friday'**
  String get publicHolidayGoodFriday;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Easter Sunday'**
  String get publicHolidayEasterSunday;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Easter Monday'**
  String get publicHolidayEasterMonday;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Ascension Day'**
  String get publicHolidayAscension;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Pentecost'**
  String get publicHolidayPentecost;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Whit Monday'**
  String get publicHolidayWhitMonday;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Assumption of Mary'**
  String get publicHolidayAssumption;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'All Saints\' Day'**
  String get publicHolidayAllSaints;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'Christmas Eve'**
  String get publicHolidayChristmasEve;

  /// Public holiday name shown in the calendar day summary
  ///
  /// In en, this message translates to:
  /// **'New Year\'s Eve'**
  String get publicHolidayNewYearsEve;

  /// Romanian public holiday on January 24
  ///
  /// In en, this message translates to:
  /// **'Union of the Romanian Principalities Day'**
  String get publicHolidayUnificationDay;

  /// Public holiday on June 1
  ///
  /// In en, this message translates to:
  /// **'Children\'s Day'**
  String get publicHolidayChildrensDay;

  /// Public holiday on November 30
  ///
  /// In en, this message translates to:
  /// **'Saint Andrew\'s Day'**
  String get publicHolidayStAndrewDay;

  /// Romanian public holiday on December 1
  ///
  /// In en, this message translates to:
  /// **'Romanian National Day'**
  String get publicHolidayNationalDayRomania;

  /// US public holiday on the third Monday of January
  ///
  /// In en, this message translates to:
  /// **'Martin Luther King Jr. Day'**
  String get publicHolidayMartinLutherKingDay;

  /// US public holiday on the third Monday of February
  ///
  /// In en, this message translates to:
  /// **'Presidents\' Day'**
  String get publicHolidayPresidentsDay;

  /// US public holiday on the last Monday of May
  ///
  /// In en, this message translates to:
  /// **'Memorial Day'**
  String get publicHolidayMemorialDay;

  /// US public holiday on June 19
  ///
  /// In en, this message translates to:
  /// **'Juneteenth'**
  String get publicHolidayJuneteenth;

  /// US public holiday on July 4
  ///
  /// In en, this message translates to:
  /// **'Independence Day'**
  String get publicHolidayIndependenceDay;

  /// US public holiday on the first Monday of September
  ///
  /// In en, this message translates to:
  /// **'Labor Day'**
  String get publicHolidayLaborDayUnitedStates;

  /// US public holiday on the second Monday of October
  ///
  /// In en, this message translates to:
  /// **'Columbus Day'**
  String get publicHolidayColumbusDay;

  /// US public holiday on November 11
  ///
  /// In en, this message translates to:
  /// **'Veterans Day'**
  String get publicHolidayVeteransDay;

  /// US public holiday on the fourth Thursday of November
  ///
  /// In en, this message translates to:
  /// **'Thanksgiving'**
  String get publicHolidayThanksgiving;

  /// UK bank holiday on the first Monday of May
  ///
  /// In en, this message translates to:
  /// **'Early May Bank Holiday'**
  String get publicHolidayEarlyMayBankHoliday;

  /// UK bank holiday on the last Monday of May
  ///
  /// In en, this message translates to:
  /// **'Spring Bank Holiday'**
  String get publicHolidaySpringBankHoliday;

  /// UK bank holiday on the last Monday of August
  ///
  /// In en, this message translates to:
  /// **'Summer Bank Holiday'**
  String get publicHolidaySummerBankHoliday;

  /// German public holiday on October 3
  ///
  /// In en, this message translates to:
  /// **'German Unity Day'**
  String get publicHolidayGermanUnityDay;

  /// Europe Day on May 9
  ///
  /// In en, this message translates to:
  /// **'Europe Day'**
  String get publicHolidayEuropeDay;

  /// Settings tile title for the holiday profile selector
  ///
  /// In en, this message translates to:
  /// **'Holiday set'**
  String get holidayProfileTitle;

  /// Holiday profile name for the default Catholic-leaning Christian set
  ///
  /// In en, this message translates to:
  /// **'Christian (Western)'**
  String get holidayProfileGeneric;

  /// Holiday profile name for Romanian national + Orthodox Christian holidays
  ///
  /// In en, this message translates to:
  /// **'Romania'**
  String get holidayProfileRomania;

  /// Holiday profile name for US federal holidays
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get holidayProfileUnitedStates;

  /// Holiday profile name for UK bank holidays
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get holidayProfileUnitedKingdom;

  /// Holiday profile name for German federal holidays
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get holidayProfileGermany;

  /// Holiday profile name for the combined pan-European set
  ///
  /// In en, this message translates to:
  /// **'Europe'**
  String get holidayProfileEurope;

  /// Holiday profile name for the empty set
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get holidayProfileNone;

  /// Title of the confirmation dialog and tooltip for removing a public holiday on a specific date
  ///
  /// In en, this message translates to:
  /// **'Remove holiday'**
  String get removeHoliday;

  /// Confirmation prompt before removing a public holiday occurrence
  ///
  /// In en, this message translates to:
  /// **'Remove \"{holiday}\" for this date? You can restore it anytime from Calendar Settings.'**
  String removeHolidayConfirm(String holiday);

  /// Snackbar message after removing a public holiday occurrence
  ///
  /// In en, this message translates to:
  /// **'Holiday removed'**
  String get holidayRemoved;

  /// Settings tile title and sheet header for the list of removed public holidays
  ///
  /// In en, this message translates to:
  /// **'Removed holidays'**
  String get removedHolidays;

  /// Empty-state text in the removed-holidays list
  ///
  /// In en, this message translates to:
  /// **'No holidays removed'**
  String get removedHolidaysEmpty;

  /// Action button label to restore a removed public holiday
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get holidayRestore;

  /// Snackbar message after restoring a removed public holiday
  ///
  /// In en, this message translates to:
  /// **'Holiday restored'**
  String get holidayRestored;

  /// Message over the removed-holidays sheet when restoring a holiday throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the holiday'**
  String get holidayRestoreFailed;

  /// Snackbar on calendar settings when switching the holiday profile throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t switch the holiday set'**
  String get holidayProfileSwitchFailed;

  /// Calendar event category: gym session
  ///
  /// In en, this message translates to:
  /// **'Gym'**
  String get eventCategoryGym;

  /// Calendar event category: cardio
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get eventCategoryCardio;

  /// Calendar event category: rest/recovery day
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get eventCategoryRest;

  /// Calendar event category: personal holiday/time off
  ///
  /// In en, this message translates to:
  /// **'Holiday'**
  String get eventCategoryHoliday;

  /// Calendar event category: competition
  ///
  /// In en, this message translates to:
  /// **'Competition'**
  String get eventCategoryCompetition;

  /// Calendar event category: body measurement
  ///
  /// In en, this message translates to:
  /// **'Measurement'**
  String get eventCategoryMeasurement;

  /// Calendar event category: mobility/stretching/yoga session
  ///
  /// In en, this message translates to:
  /// **'Mobility'**
  String get eventCategoryMobility;

  /// Calendar event category: birthday (defaults to a yearly recurrence)
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get eventCategoryBirthday;

  /// Calendar event category: other
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get eventCategoryOther;

  /// Title of the event categories management page and its settings entry
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get calendarCategories;

  /// Subtitle for the manage-categories entry on calendar settings
  ///
  /// In en, this message translates to:
  /// **'Create and customize event categories'**
  String get calendarCategoriesDesc;

  /// Action to create a new event category
  ///
  /// In en, this message translates to:
  /// **'Create category'**
  String get createCategory;

  /// Title of the category editor when editing
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get editCategory;

  /// Label for the category name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get categoryName;

  /// Hint for the category name field
  ///
  /// In en, this message translates to:
  /// **'e.g. Stretching'**
  String get categoryNameHint;

  /// Badge shown on built-in categories that cannot be deleted
  ///
  /// In en, this message translates to:
  /// **'Built-in category'**
  String get categoryDefault;

  /// Action/title for deleting a custom event category
  ///
  /// In en, this message translates to:
  /// **'Delete category'**
  String get deleteCategory;

  /// Snackbar shown after a custom category is deleted
  ///
  /// In en, this message translates to:
  /// **'Category deleted'**
  String get categoryDeleted;

  /// Snackbar shown when saving a category from the editor sheet fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the category'**
  String get categorySaveFailed;

  /// Snackbar on the categories page when hiding, deleting or reordering a category fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the change'**
  String get categoryChangeFailed;

  /// Number of events using a category, shown in the category row subtitle and the delete sheet's counts. Keep the no-break spaces in the counted arms so a number never strands from its noun; the =0 arm has no number and takes a plain space so a narrow column can wrap it
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No events} =1{1 event} other{{count} events}}'**
  String categoryEventCount(int count);

  /// Placeholder for the category search field
  ///
  /// In en, this message translates to:
  /// **'Search categories'**
  String get searchCategories;

  /// Empty state when a category search returns nothing
  ///
  /// In en, this message translates to:
  /// **'No categories match'**
  String get noCategoriesMatch;

  /// Action in the category picker's empty state, prefilling the typed text as the new category's name
  ///
  /// In en, this message translates to:
  /// **'Create \"{name}\"'**
  String createCategoryNamed(String name);

  /// Subtitle marking a hidden category that is only listed because it is already selected
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get categoryHidden;

  /// Soft warning under the category name field when the name matches an existing category. Never blocks saving.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" already exists'**
  String categoryNameExists(String name);

  /// Soft warning under the category name field when the matching category is hidden. Never blocks saving.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" already exists but is hidden'**
  String categoryNameExistsHidden(String name);

  /// Subtitle of the categories filter tile when no category is filtered out
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get categoriesAllSelected;

  /// Subtitle of the categories filter tile when it cannot name the selection
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No categories} =1{1 category} other{{count} categories}}'**
  String categoriesNSelected(int count);

  /// Suffix on the categories filter tile subtitle for the selected categories it did not name
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String categoriesMore(int count);

  /// Button in the category picker sheet that checks every listed row
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get categoriesSelectAll;

  /// Button in the category picker sheet that unchecks every listed row
  ///
  /// In en, this message translates to:
  /// **'Select none'**
  String get categoriesSelectNone;

  /// Overflow menu action sorting categories alphabetically
  ///
  /// In en, this message translates to:
  /// **'Sort A–Z'**
  String get sortCategoriesAlphabetically;

  /// Title of the dialog confirming that the categories are sorted alphabetically
  ///
  /// In en, this message translates to:
  /// **'Sort categories A–Z?'**
  String get categorySortConfirmTitle;

  /// Body of the dialog confirming an A–Z sort: the user's manual category order is lost
  ///
  /// In en, this message translates to:
  /// **'Your own order is replaced.'**
  String get categorySortConfirmBody;

  /// Confirm button that sorts a list
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// Row menu action moving an item to the first position
  ///
  /// In en, this message translates to:
  /// **'Move to top'**
  String get moveToTop;

  /// Section title in markdown settings for vocabulary autocomplete
  ///
  /// In en, this message translates to:
  /// **'Autocomplete'**
  String get vocabularySection;

  /// Master switch label for vocabulary autocomplete
  ///
  /// In en, this message translates to:
  /// **'Suggest terms while typing'**
  String get vocabularySuggestionsLabel;

  /// Explanation under the vocabulary autocomplete master switch
  ///
  /// In en, this message translates to:
  /// **'Offer terms from your lists after the trigger character, or when you tap a placeholder.'**
  String get vocabularySuggestionsDesc;

  /// Tooltip on the button that closes the suggestion bar
  ///
  /// In en, this message translates to:
  /// **'Hide suggestions'**
  String get vocabularySuggestionsDismiss;

  /// Setting label for the character that opens the suggestion bar
  ///
  /// In en, this message translates to:
  /// **'Trigger character'**
  String get vocabularyTriggerLabel;

  /// Explanation under the trigger character setting
  ///
  /// In en, this message translates to:
  /// **'Type it after a space to start searching your lists.'**
  String get vocabularyTriggerDesc;

  /// Button opening the vocabulary management page
  ///
  /// In en, this message translates to:
  /// **'Edit lists'**
  String get manageVocabularies;

  /// Title of the vocabulary management page
  ///
  /// In en, this message translates to:
  /// **'Word lists'**
  String get vocabularies;

  /// Empty state on the vocabulary management page
  ///
  /// In en, this message translates to:
  /// **'No lists yet. Create one to get suggestions for the things you write often — exercises, meals, clients.'**
  String get vocabulariesEmpty;

  /// Action for creating a vocabulary
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get createVocabulary;

  /// Title when editing an existing vocabulary
  ///
  /// In en, this message translates to:
  /// **'Edit list'**
  String get editVocabulary;

  /// Label for the vocabulary name field
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get vocabularyName;

  /// Placeholder for the vocabulary name field
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get vocabularyNameHint;

  /// Helper text explaining that a ghost placeholder matching the list name scopes suggestions to it
  ///
  /// In en, this message translates to:
  /// **'A placeholder with this name suggests only this list.'**
  String get vocabularyNameHelper;

  /// Switch label controlling whether a vocabulary is offered in the editor
  ///
  /// In en, this message translates to:
  /// **'Use for suggestions'**
  String get vocabularyEnabled;

  /// Explanation under the per-vocabulary enable switch
  ///
  /// In en, this message translates to:
  /// **'Turn off to keep the list without suggesting it.'**
  String get vocabularyEnabledDesc;

  /// Label above the vocabulary terms field
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get vocabularyTerms;

  /// Placeholder for the multiline terms field, showing the one-per-line format and the ;; section header syntax
  ///
  /// In en, this message translates to:
  /// **'One per line:\nBench Press\nDeadlift\n\n;; Legs\nSquat'**
  String get vocabularyTermsHint;

  /// Tooltip on the button that folds the name field and enable switch away while editing terms
  ///
  /// In en, this message translates to:
  /// **'List name and settings'**
  String get vocabularyDetails;

  /// Number of terms in a vocabulary
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No terms} =1{1 term} other{{count} terms}}'**
  String vocabularyTermCount(int count);

  /// Action/title for deleting a vocabulary
  ///
  /// In en, this message translates to:
  /// **'Delete list'**
  String get deleteVocabulary;

  /// Confirmation message when deleting a vocabulary
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Notes you already wrote keep their text.'**
  String deleteVocabularyConfirm(String name);

  /// Snackbar shown after a vocabulary is deleted
  ///
  /// In en, this message translates to:
  /// **'List deleted'**
  String get vocabularyDeleted;

  /// Section title on calendar settings grouping event data actions
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get calendarEventsSection;

  /// Title of the slider setting the character budget of an event description
  ///
  /// In en, this message translates to:
  /// **'Description length'**
  String get eventDescriptionLimit;

  /// Subtitle for the event description length slider
  ///
  /// In en, this message translates to:
  /// **'Allow up to {count} characters in an event description.'**
  String eventDescriptionLimitDesc(int count);

  /// Character counter shown above the event description field
  ///
  /// In en, this message translates to:
  /// **'{count} / {limit}'**
  String eventDescriptionCount(int count, int limit);

  /// Explanation shown under the description field when it exceeds the configured limit
  ///
  /// In en, this message translates to:
  /// **'The description is over the {limit} character limit. Shorten it or raise the limit in calendar settings.'**
  String eventDescriptionTooLong(int limit);

  /// Title of the switch enabling per-occurrence event descriptions
  ///
  /// In en, this message translates to:
  /// **'Separate description per day'**
  String get eventPerOccurrenceDescriptions;

  /// Segment label: edit the shared template description
  ///
  /// In en, this message translates to:
  /// **'All days'**
  String get eventDescriptionScopeAllDays;

  /// Segment label: edit only the selected occurrence's description
  ///
  /// In en, this message translates to:
  /// **'This day'**
  String get eventDescriptionScopeThisDay;

  /// Hint shown while the description scope is the shared template
  ///
  /// In en, this message translates to:
  /// **'Editing the description every day starts from.'**
  String get eventDescriptionScopeAllDaysHint;

  /// Hint shown while the description scope is a single occurrence
  ///
  /// In en, this message translates to:
  /// **'Editing this day only. Other days keep the shared description.'**
  String get eventDescriptionScopeThisDayHint;

  /// Action removing one occurrence's description override
  ///
  /// In en, this message translates to:
  /// **'Reset this day to the shared description'**
  String get eventDescriptionResetDay;

  /// Action/title for deleting every custom calendar event
  ///
  /// In en, this message translates to:
  /// **'Delete all events'**
  String get deleteAllEvents;

  /// Subtitle for the delete-all-events entry on calendar settings
  ///
  /// In en, this message translates to:
  /// **'Permanently remove every event you created. Holidays are kept.'**
  String get deleteAllEventsDesc;

  /// Confirmation message when deleting all custom calendar events
  ///
  /// In en, this message translates to:
  /// **'Delete all your events? Public holidays aren\'t affected. This can\'t be undone.'**
  String get deleteAllEventsConfirm;

  /// Subtitle shown when there are no custom events to delete
  ///
  /// In en, this message translates to:
  /// **'No events to delete'**
  String get noEventsToDelete;

  /// Snackbar shown after all custom events are deleted
  ///
  /// In en, this message translates to:
  /// **'All events deleted'**
  String get allEventsDeleted;

  /// Section label in the calendar event editor for the recurrence rule
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get recurrence;

  /// Recurrence option meaning the event occurs once (no repeat)
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get recurrenceNone;

  /// Recurrence option meaning the event repeats every day
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get recurrenceDaily;

  /// Recurrence option meaning the event repeats every week on the same weekday
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get recurrenceWeekly;

  /// Recurrence option meaning the event repeats every month on the same day
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get recurrenceMonthly;

  /// Recurrence option meaning the event repeats every year on the same date
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get recurrenceYearly;

  /// Title of the calendar event editor when modifying an existing event
  ///
  /// In en, this message translates to:
  /// **'Edit event'**
  String get editEvent;

  /// Title of the confirmation dialog for deleting a calendar event
  ///
  /// In en, this message translates to:
  /// **'Delete event'**
  String get deleteEvent;

  /// Confirmation prompt before deleting a calendar event
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"? This cannot be undone.'**
  String deleteEventConfirm(String title);

  /// Section label in the event editor for the icon picker
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get iconLabel;

  /// Shown when the user picked a specific icon for an event
  ///
  /// In en, this message translates to:
  /// **'Custom icon'**
  String get iconCustom;

  /// Title of the icon picker bottom sheet / subtitle of the picker tile
  ///
  /// In en, this message translates to:
  /// **'Choose icon'**
  String get pickIcon;

  /// Tooltip on the button that clears the custom icon override
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// Section label in the event editor for the recurring event start date
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get eventDate;

  /// Recurrence option: every Mon-Fri excluding public holidays
  ///
  /// In en, this message translates to:
  /// **'Workdays'**
  String get recurrenceWorkdays;

  /// Recurrence option: every Saturday and Sunday
  ///
  /// In en, this message translates to:
  /// **'Weekends'**
  String get recurrenceWeekends;

  /// Recurrence option: only on public holidays
  ///
  /// In en, this message translates to:
  /// **'Public holidays only'**
  String get recurrenceHolidaysOnly;

  /// Recurrence summary for daily events, honoring the interval
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Daily} other{Every {count} days}}'**
  String recurrenceEveryDays(int count);

  /// Recurrence summary for weekly events without explicit weekdays, honoring the interval
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Weekly} other{Every {count} weeks}}'**
  String recurrenceEveryWeeks(int count);

  /// Recurrence summary for weekly events with explicit weekdays, honoring the interval
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Weekly · {days}} other{Every {count} weeks · {days}}}'**
  String recurrenceEveryWeeksOn(int count, String days);

  /// Recurrence summary for monthly events, honoring the interval
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Monthly} other{Every {count} months}}'**
  String recurrenceEveryMonths(int count);

  /// Recurrence summary for yearly events, honoring the interval
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Yearly} other{Every {count} years}}'**
  String recurrenceEveryYears(int count);

  /// Section label above the recurrence interval stepper
  ///
  /// In en, this message translates to:
  /// **'Repeat every'**
  String get recurrenceIntervalLabel;

  /// Tooltip for the button that decreases the recurrence interval: a smaller interval is a more frequent event
  ///
  /// In en, this message translates to:
  /// **'More frequent'**
  String get recurrenceIntervalDecrement;

  /// Tooltip for the button that increases the recurrence interval: a larger interval is a less frequent event
  ///
  /// In en, this message translates to:
  /// **'Less frequent'**
  String get recurrenceIntervalIncrement;

  /// Unit shown next to the interval stepper for daily recurrence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String recurrenceUnitDays(int count);

  /// Unit shown next to the interval stepper for weekly recurrence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{week} other{weeks}}'**
  String recurrenceUnitWeeks(int count);

  /// Unit shown next to the interval stepper for monthly recurrence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{month} other{months}}'**
  String recurrenceUnitMonths(int count);

  /// Unit shown next to the interval stepper for yearly recurrence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{year} other{years}}'**
  String recurrenceUnitYears(int count);

  /// Validation hint shown when the user clears all weekday selections
  ///
  /// In en, this message translates to:
  /// **'Pick at least one weekday'**
  String get weeklyDaysHint;

  /// Section label for the recurrence scope chips (forward-only vs retroactive)
  ///
  /// In en, this message translates to:
  /// **'Occurrences'**
  String get recurrenceScopeLabel;

  /// Recurrence scope option for non-yearly rules: also fires before the start date
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get recurrenceScopeAlways;

  /// Recurrence scope option shown for yearly rules: also fires in previous years
  ///
  /// In en, this message translates to:
  /// **'Every year'**
  String get recurrenceScopeEveryYear;

  /// Recurrence label suffixed to mark a rule that also fires before its start date
  ///
  /// In en, this message translates to:
  /// **'{rule} · also before'**
  String recurrenceScopeAlwaysSuffix(String rule);

  /// Switch in the event editor: the event records which days were missed
  ///
  /// In en, this message translates to:
  /// **'Track presence'**
  String get eventTrackPresence;

  /// Segment label: unmarked days count as attended
  ///
  /// In en, this message translates to:
  /// **'Assume present'**
  String get eventAssumePresent;

  /// Segment label: unmarked days count as missed
  ///
  /// In en, this message translates to:
  /// **'Assume absent'**
  String get eventAssumeAbsent;

  /// Label of the tile picking the day the assume-absent default starts
  ///
  /// In en, this message translates to:
  /// **'Absent from'**
  String get eventAssumeAbsentFrom;

  /// Value shown when the assume-absent default covers the whole event
  ///
  /// In en, this message translates to:
  /// **'Start of event'**
  String get eventAssumeAbsentFromStart;

  /// Label for the three-way day-rail membership control in the event editor
  ///
  /// In en, this message translates to:
  /// **'Day rail'**
  String get eventShowInDayRail;

  /// Day rail membership: follow presence tracking
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get eventShowInDayRailAuto;

  /// Day rail membership: always show on the rail
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get eventShowInDayRailAlways;

  /// Day rail membership: never show on the rail
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get eventShowInDayRailNever;

  /// Presence toggle option in the event detail sheet: this occurrence was attended
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get eventPresencePresent;

  /// Presence toggle option in the event detail sheet: this occurrence was skipped
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get eventPresenceMissed;

  /// Tooltip on the day-panel button that marks an occurrence as missed
  ///
  /// In en, this message translates to:
  /// **'Mark as missed'**
  String get eventMarkMissed;

  /// Tooltip on the day-panel button that returns a missed occurrence to present
  ///
  /// In en, this message translates to:
  /// **'Mark as present'**
  String get eventMarkPresent;

  /// Switch in the event editor: each occurrence shows the elapsed time since the start date
  ///
  /// In en, this message translates to:
  /// **'Count occurrences'**
  String get eventCountOccurrences;

  /// Counting origin chip: the start day is the first occurrence, so labels read Day 1 / Week 3
  ///
  /// In en, this message translates to:
  /// **'Count from 1'**
  String get eventCountStyleNumbered;

  /// Counting origin chip: the start day is zero, so a birth date makes later occurrences the age
  ///
  /// In en, this message translates to:
  /// **'Count from 0'**
  String get eventCountStyleElapsed;

  /// Numbered occurrence label for a daily rule
  ///
  /// In en, this message translates to:
  /// **'Day {count}'**
  String eventNumberedDays(int count);

  /// Numbered occurrence label for a weekly rule (all sessions of a week share the number)
  ///
  /// In en, this message translates to:
  /// **'Week {count}'**
  String eventNumberedWeeks(int count);

  /// Numbered occurrence label for a monthly rule
  ///
  /// In en, this message translates to:
  /// **'Month {count}'**
  String eventNumberedMonths(int count);

  /// Numbered occurrence label for a yearly rule
  ///
  /// In en, this message translates to:
  /// **'Year {count}'**
  String eventNumberedYears(int count);

  /// Elapsed time since an event's start date, shown on counted occurrences of a daily rule
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String eventElapsedDays(int count);

  /// Elapsed time since an event's start date, shown on counted occurrences of a weekly rule
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 week} other{{count} weeks}}'**
  String eventElapsedWeeks(int count);

  /// Elapsed time since an event's start date, shown on counted occurrences of a monthly rule
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String eventElapsedMonths(int count);

  /// Elapsed time since an event's start date, shown on counted occurrences of a yearly rule (a birthday's age)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 year} other{{count} years}}'**
  String eventElapsedYears(int count);

  /// Title of the in-app calendar date picker in single-date mode
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get datePickerSingleTitle;

  /// Title of the in-app calendar date picker in multi-date mode
  ///
  /// In en, this message translates to:
  /// **'Pick dates'**
  String get datePickerMultiTitle;

  /// Title of the sheet that jumps the calendar to a chosen date
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get monthYearPickerTitle;

  /// Switch row in the month/year picker that swaps the wheels for a typed date field
  ///
  /// In en, this message translates to:
  /// **'Type the date'**
  String get monthYearPickerTypedEntry;

  /// Label of the text field for typing a date
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get monthYearPickerFieldLabel;

  /// Placeholder showing the expected typed day/month/year format
  ///
  /// In en, this message translates to:
  /// **'15/08/2026'**
  String get monthYearPickerFieldHint;

  /// Error shown when the typed date cannot be understood
  ///
  /// In en, this message translates to:
  /// **'Type a date, like 15/08/2026'**
  String get monthYearPickerInvalid;

  /// Error shown when the typed year falls outside the calendar range
  ///
  /// In en, this message translates to:
  /// **'Choose a year between {first} and {last}'**
  String monthYearPickerRange(String first, String last);

  /// Calendar settings section for computed fasting periods
  ///
  /// In en, this message translates to:
  /// **'Religious fasting'**
  String get fastingSectionTitle;

  /// Explanatory line under the fasting settings section header
  ///
  /// In en, this message translates to:
  /// **'Computed fasting periods with each day\'s rule, shown on the grid and in the day panel'**
  String get fastingSectionDesc;

  /// Fasting tradition toggle: Eastern Orthodox
  ///
  /// In en, this message translates to:
  /// **'Orthodox'**
  String get fastingTraditionOrthodox;

  /// Fasting tradition toggle: Roman Catholic
  ///
  /// In en, this message translates to:
  /// **'Catholic'**
  String get fastingTraditionCatholic;

  /// Fasting tradition toggle: Islamic
  ///
  /// In en, this message translates to:
  /// **'Muslim'**
  String get fastingTraditionMuslim;

  /// Fasting tradition toggle: Jewish
  ///
  /// In en, this message translates to:
  /// **'Jewish'**
  String get fastingTraditionJewish;

  /// Comma-separated hidden search synonyms for the Orthodox fasting tradition, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'orthodox, orthodoxe, ortodox, fasting, church'**
  String get fastingTraditionOrthodoxKeywords;

  /// Comma-separated hidden search synonyms for the Catholic fasting tradition, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'catholic, katholisch, catolic, roman catholic, church'**
  String get fastingTraditionCatholicKeywords;

  /// Comma-separated hidden search synonyms for the Muslim fasting tradition, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'muslim, muslimisch, musulman, islamic, mosque'**
  String get fastingTraditionMuslimKeywords;

  /// Comma-separated hidden search synonyms for the Jewish fasting tradition, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'jewish, judisch, evreiesc, synagogue, hebrew'**
  String get fastingTraditionJewishKeywords;

  /// Orthodox Easter fast (Postul Pastelui)
  ///
  /// In en, this message translates to:
  /// **'Great Lent'**
  String get fastingGreatLent;

  /// Orthodox fast before Sts Peter and Paul
  ///
  /// In en, this message translates to:
  /// **'Apostles\' Fast'**
  String get fastingApostlesFast;

  /// Orthodox fast Aug 1-14
  ///
  /// In en, this message translates to:
  /// **'Dormition Fast'**
  String get fastingDormitionFast;

  /// Orthodox Christmas fast Nov 15 - Dec 24
  ///
  /// In en, this message translates to:
  /// **'Nativity Fast'**
  String get fastingNativityFast;

  /// Orthodox year-round fast on Wednesdays and Fridays
  ///
  /// In en, this message translates to:
  /// **'Wednesday/Friday fast'**
  String get fastingWeekdayFast;

  /// Orthodox week before Lent when dairy is still allowed
  ///
  /// In en, this message translates to:
  /// **'Cheesefare Week'**
  String get fastingCheesefareWeek;

  /// Orthodox strict fast day on January 5
  ///
  /// In en, this message translates to:
  /// **'Eve of Theophany'**
  String get fastingEveOfTheophany;

  /// Orthodox strict fast day on August 29
  ///
  /// In en, this message translates to:
  /// **'Beheading of St John'**
  String get fastingBeheadingOfStJohn;

  /// Orthodox strict fast day on September 14
  ///
  /// In en, this message translates to:
  /// **'Exaltation of the Cross'**
  String get fastingExaltationOfCross;

  /// Catholic penitential season before Easter
  ///
  /// In en, this message translates to:
  /// **'Lent'**
  String get fastingLent;

  /// Catholic fast day opening Lent
  ///
  /// In en, this message translates to:
  /// **'Ash Wednesday'**
  String get fastingAshWednesday;

  /// Catholic fast day before Easter
  ///
  /// In en, this message translates to:
  /// **'Good Friday'**
  String get fastingGoodFriday;

  /// Catholic year-round Friday abstinence from meat
  ///
  /// In en, this message translates to:
  /// **'Friday abstinence'**
  String get fastingFridayAbstinence;

  /// Catholic preparation season before Christmas
  ///
  /// In en, this message translates to:
  /// **'Advent'**
  String get fastingAdvent;

  /// Islamic month of fasting
  ///
  /// In en, this message translates to:
  /// **'Ramadan'**
  String get fastingRamadan;

  /// Islamic recommended fast on 9 Dhu al-Hijjah
  ///
  /// In en, this message translates to:
  /// **'Day of Arafah'**
  String get fastingDayOfArafah;

  /// Islamic recommended fast on 10 Muharram
  ///
  /// In en, this message translates to:
  /// **'Ashura'**
  String get fastingAshura;

  /// Jewish Day of Atonement, a full fast
  ///
  /// In en, this message translates to:
  /// **'Yom Kippur'**
  String get fastingYomKippur;

  /// Jewish full fast mourning the Temples
  ///
  /// In en, this message translates to:
  /// **'Tisha B\'Av'**
  String get fastingTishaBAv;

  /// Jewish minor fast on 3 Tishrei
  ///
  /// In en, this message translates to:
  /// **'Fast of Gedaliah'**
  String get fastingGedaliah;

  /// Jewish minor fast on 10 Tevet
  ///
  /// In en, this message translates to:
  /// **'Tenth of Tevet'**
  String get fastingTenthOfTevet;

  /// Jewish minor fast on 17 Tammuz
  ///
  /// In en, this message translates to:
  /// **'Seventeenth of Tammuz'**
  String get fastingSeventeenthOfTammuz;

  /// Jewish minor fast before Purim
  ///
  /// In en, this message translates to:
  /// **'Fast of Esther'**
  String get fastingEstherFast;

  /// Comma-separated hidden search synonyms for Great Lent, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'lent, great lent, easter fast, post, postul mare, fastenzeit'**
  String get fastingGreatLentKeywords;

  /// Comma-separated hidden search synonyms for the Catholic Lent period, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'fastenzeit, postul mare, lenten season, easter fast, penance'**
  String get fastingLentKeywords;

  /// Comma-separated hidden search synonyms for the Advent period, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'advent, christmas fast, pre-christmas, waiting season'**
  String get fastingAdventKeywords;

  /// Comma-separated hidden search synonyms for Ramadan, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'ramadan, ramazan, muslim fast, islamic month, fasting month'**
  String get fastingRamadanKeywords;

  /// Comma-separated hidden search synonyms for the Nativity Fast, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'nativity fast, christmas fast, weihnachtsfasten, postul craciunului, advent'**
  String get fastingNativityFastKeywords;

  /// Comma-separated hidden search synonyms for the Dormition Fast, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'dormition fast, assumption fast, august fast, entschlafungsfasten, postul adormirii'**
  String get fastingDormitionFastKeywords;

  /// Comma-separated hidden search synonyms for the Apostles' Fast, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'apostles fast, peter and paul fast, apostelfasten, postul sfintilor apostoli'**
  String get fastingApostlesFastKeywords;

  /// Comma-separated hidden search synonyms for the weekly Wednesday/Friday fast, matched but never shown
  ///
  /// In en, this message translates to:
  /// **'wednesday, friday, weekly fast, miercuri, vineri, mittwoch, freitag'**
  String get fastingWeekdayFastKeywords;

  /// Fasting rule: strict fast, no oil
  ///
  /// In en, this message translates to:
  /// **'Strict fast'**
  String get fastingRegimeStrict;

  /// Fasting rule: dispensation for wine and oil
  ///
  /// In en, this message translates to:
  /// **'Wine and oil allowed'**
  String get fastingRegimeOil;

  /// Fasting rule: dispensation for fish
  ///
  /// In en, this message translates to:
  /// **'Fish allowed'**
  String get fastingRegimeFish;

  /// Fasting rule: dairy and eggs permitted, no meat
  ///
  /// In en, this message translates to:
  /// **'Dairy and eggs allowed'**
  String get fastingRegimeDairy;

  /// Fasting rule: penitential day without a binding food rule
  ///
  /// In en, this message translates to:
  /// **'Day of penance'**
  String get fastingRegimePenitential;

  /// Fasting rule: dawn-to-sunset fast (Ramadan, Jewish minor fasts)
  ///
  /// In en, this message translates to:
  /// **'Fast from dawn to sunset'**
  String get fastingRegimeDaylight;

  /// Fasting rule: complete fast (Yom Kippur, Tisha B'Av)
  ///
  /// In en, this message translates to:
  /// **'Total fast'**
  String get fastingRegimeFull;

  /// Dropdown choosing how fasting days render on the calendar grid
  ///
  /// In en, this message translates to:
  /// **'Show on the grid'**
  String get fastingStyleTitle;

  /// Fasting grid style: faint violet cell background
  ///
  /// In en, this message translates to:
  /// **'Subtle tint'**
  String get fastingStyleTint;

  /// Fasting grid style: a violet bar in the day markers, like events
  ///
  /// In en, this message translates to:
  /// **'Day bar'**
  String get fastingStyleBar;

  /// Fasting grid style: violet bold day number
  ///
  /// In en, this message translates to:
  /// **'Bold day number'**
  String get fastingStyleStrong;

  /// Fasting grid style: nothing on the grid, info only in the day panel
  ///
  /// In en, this message translates to:
  /// **'Day panel only'**
  String get fastingStyleNone;

  /// Toggle for the Orthodox multi-day fasts and strict single days
  ///
  /// In en, this message translates to:
  /// **'Multi-day fasts'**
  String get fastingOrthodoxGreatFasts;

  /// Subtitle listing what the Orthodox multi-day fasts toggle covers
  ///
  /// In en, this message translates to:
  /// **'Great Lent, Nativity, Apostles\', Dormition, strict single days'**
  String get fastingOrthodoxGreatFastsDesc;

  /// Label above the weekday chips selecting personal weekly fast days
  ///
  /// In en, this message translates to:
  /// **'Weekly fast days'**
  String get fastingWeekdayDaysTitle;

  /// Hint under the weekly fast day chips
  ///
  /// In en, this message translates to:
  /// **'Pick the days you keep — many fast only on Wednesday and Friday'**
  String get fastingWeekdayDaysDesc;

  /// Label for the chips choosing where the fasting row sits
  ///
  /// In en, this message translates to:
  /// **'Order in the day panel'**
  String get fastingPlacementTitle;

  /// Fasting row placement: above everything including events
  ///
  /// In en, this message translates to:
  /// **'First'**
  String get fastingPlacementFirst;

  /// Fasting row placement: after events, before the public holiday
  ///
  /// In en, this message translates to:
  /// **'After events'**
  String get fastingPlacementBeforeHolidays;

  /// Fasting row placement: after the public holiday (default)
  ///
  /// In en, this message translates to:
  /// **'After holidays'**
  String get fastingPlacementAfterHolidays;

  /// Fasting row placement: below everything
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get fastingPlacementLast;

  /// Swatch restoring the shared fasting violet
  ///
  /// In en, this message translates to:
  /// **'Default color'**
  String get fastingColorDefault;

  /// Shown when a tradition uses its built-in icon
  ///
  /// In en, this message translates to:
  /// **'Default icon'**
  String get fastingIconDefault;

  /// Label above the live preview of a fasting day row
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get fastingPreviewLabel;

  /// Field replacing the computed fast name in the day panel row
  ///
  /// In en, this message translates to:
  /// **'Custom title'**
  String get fastingTitleOverrideLabel;

  /// Field adding a description line to the fasting day panel row
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get fastingDescriptionLabel;

  /// Placeholder for the fasting description field
  ///
  /// In en, this message translates to:
  /// **'Shown under the rule — markdown works here'**
  String get fastingDescriptionHint;

  /// Schedule summary fragment: every month is kept
  ///
  /// In en, this message translates to:
  /// **'All year'**
  String get fastingScheduleAllYear;

  /// Schedule summary fragment: no weekday is kept
  ///
  /// In en, this message translates to:
  /// **'No weekly days'**
  String get fastingScheduleNoDays;

  /// Schedule summary fragment: no month is kept
  ///
  /// In en, this message translates to:
  /// **'No months kept'**
  String get fastingScheduleNoMonths;

  /// Label above the month chips in the fasting schedule sheet
  ///
  /// In en, this message translates to:
  /// **'Months you keep'**
  String get fastingMonthsTitle;

  /// Caption under the month chips of the fasting schedule sheet: what turning a month off does
  ///
  /// In en, this message translates to:
  /// **'A month you turn off is never marked'**
  String get fastingMonthsDesc;

  /// Schedule summary fragment: how many months are kept
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String fastingMonthsCount(int count);

  /// Label above the weekday scope chips
  ///
  /// In en, this message translates to:
  /// **'Weekdays apply to'**
  String get fastingWeekdayScopeTitle;

  /// Hint under the weekday scope chips while the weekday set gates only the weekly fast
  ///
  /// In en, this message translates to:
  /// **'Multi-day fasts still mark every one of their days'**
  String get fastingWeekdayScopeHintWeekly;

  /// Hint under the weekday scope chips while the weekday set gates every fast
  ///
  /// In en, this message translates to:
  /// **'A day you turn off is never marked'**
  String get fastingWeekdayScopeHintAll;

  /// Weekday scope option: the weekday set gates only the weekly fast
  ///
  /// In en, this message translates to:
  /// **'Weekly fast only'**
  String get fastingWeekdayScopeWeekly;

  /// Weekday scope option: the weekday set gates every fast
  ///
  /// In en, this message translates to:
  /// **'All fasts'**
  String get fastingWeekdayScopeAll;

  /// Label above the skipped fasting dates list
  ///
  /// In en, this message translates to:
  /// **'Dates I don\'t fast'**
  String get fastingExceptionsSkipTitle;

  /// Hint under the skipped fasting dates list
  ///
  /// In en, this message translates to:
  /// **'Never marked, whatever the calendar says'**
  String get fastingExceptionsSkipHint;

  /// Label above the forced fasting dates list
  ///
  /// In en, this message translates to:
  /// **'Extra fast days'**
  String get fastingExceptionsForceTitle;

  /// Hint under the forced fasting dates list
  ///
  /// In en, this message translates to:
  /// **'Always marked, even outside your practice'**
  String get fastingExceptionsForceHint;

  /// Schedule summary fragment: how many exception dates exist
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exception} other{{count} exceptions}}'**
  String fastingExceptionsCount(int count);

  /// Shown when an exception date list hit its cap
  ///
  /// In en, this message translates to:
  /// **'Limit reached'**
  String get fastingExceptionsFull;

  /// Button opening the date picker for exception dates
  ///
  /// In en, this message translates to:
  /// **'Add dates'**
  String get fastingAddDates;

  /// Day panel title for a date the user forced on themselves
  ///
  /// In en, this message translates to:
  /// **'Personal fast'**
  String get fastingPersonalFast;

  /// Quick action clearing every chip in a selection row
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get selectNone;

  /// Event editor section header: scheduling
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get eventSectionWhen;

  /// Event editor section header: optional details
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get eventSectionDetails;

  /// Count of currently selected days in the multi-date picker
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No dates selected} =1{1 date selected} other{{count} dates selected}}'**
  String datePickerSelectedCount(int count);

  /// Button that clears every selected day in the multi-date picker
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get datePickerClear;

  /// Button that jumps the picker's calendar back to the current month
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get datePickerToday;

  /// Accessibility label for a picker day that already carries events
  ///
  /// In en, this message translates to:
  /// **'Already has events'**
  String get datePickerBusyDay;

  /// Tooltip for the button that switches the description field to its markdown preview
  ///
  /// In en, this message translates to:
  /// **'Show rendered description'**
  String get eventDescriptionPreviewOn;

  /// Tooltip for the button that switches the description preview back to editing
  ///
  /// In en, this message translates to:
  /// **'Edit description'**
  String get eventDescriptionPreviewOff;

  /// Accessibility label for the indicator marking a day-panel row that carries a description
  ///
  /// In en, this message translates to:
  /// **'Has notes'**
  String get eventHasDescription;

  /// Title of the read-only event detail sheet
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get eventDetailsTitle;

  /// Detail sheet row label for the event's time of day: the range with its duration, or All day
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get eventTime;

  /// Detail sheet row label for the next day a recurring event occurs after the opened occurrence (from today when a past occurrence is opened)
  ///
  /// In en, this message translates to:
  /// **'Next occurrence'**
  String get eventDetailsNext;

  /// Caption under the next-occurrence row listing the following dates, joined by a middle dot
  ///
  /// In en, this message translates to:
  /// **'then {dates}'**
  String eventDetailsThen(String dates);

  /// Detail sheet row label beside the Present / Missed chips for the opened occurrence
  ///
  /// In en, this message translates to:
  /// **'Presence'**
  String get eventPresence;

  /// Shown when a recurring event has no occurrence left in the scanned window
  ///
  /// In en, this message translates to:
  /// **'No upcoming occurrences'**
  String get eventDetailsNoOccurrences;

  /// Section label for the combined icon and color picker in the event editor
  ///
  /// In en, this message translates to:
  /// **'Icon & color'**
  String get eventAppearance;

  /// Section label for the per-event color picker
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get eventColor;

  /// Title of the custom color wheel dialog
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get eventColorCustomTitle;

  /// Generic confirm button for a selection dialog
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// Toggle label: also apply the event color to the icon
  ///
  /// In en, this message translates to:
  /// **'Tint icon with color'**
  String get eventTintIcon;

  /// Section label for the event priority stepper
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get eventPriority;

  /// Qualitative label for priority level 1
  ///
  /// In en, this message translates to:
  /// **'Lowest'**
  String get eventPriorityLowest;

  /// Qualitative label for priority level 2
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get eventPriorityLow;

  /// Qualitative label for priority level 3 (default)
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get eventPriorityNormal;

  /// Qualitative label for priority level 4
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get eventPriorityHigh;

  /// Qualitative label for priority level 5
  ///
  /// In en, this message translates to:
  /// **'Highest'**
  String get eventPriorityHighest;

  /// Action chip that adds another one-off date
  ///
  /// In en, this message translates to:
  /// **'Add date'**
  String get eventAddDate;

  /// Tooltip to remove an additional one-off date chip
  ///
  /// In en, this message translates to:
  /// **'Remove date'**
  String get eventRemoveDate;

  /// Summary for a one-time event pinned to several specific dates
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One date} other{{count} dates}}'**
  String recurrenceSpecificDates(int count);

  /// Label for the optional multiline description / notes field on an event
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get eventDescription;

  /// Tooltip for the pencil button that opens the full description editor
  ///
  /// In en, this message translates to:
  /// **'Edit description'**
  String get eventDescriptionEdit;

  /// Label on the tappable empty state that opens the full description editor for an event with no description yet
  ///
  /// In en, this message translates to:
  /// **'Add description'**
  String get eventDescriptionAdd;

  /// Tooltip for the expand button that opens the description in a full-height editor sheet
  ///
  /// In en, this message translates to:
  /// **'Open full editor'**
  String get eventDescriptionExpand;

  /// Confirm button in the full-height description editor sheet
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get eventDescriptionDone;

  /// Caption shown in the description editor when the edit changes the shared description used by every occurrence of a repeating event
  ///
  /// In en, this message translates to:
  /// **'Applies to every occurrence'**
  String get eventDescriptionAppliesAllOccurrences;

  /// Caption under a repeating event's description in the read-only detail sheet, explaining why its task checkboxes cannot be ticked
  ///
  /// In en, this message translates to:
  /// **'Ticking here would apply to every occurrence. Turn on per-day descriptions to tick just this one.'**
  String get eventDescriptionTickAllOccurrences;

  /// Section label for the optional workout note linked to a calendar event
  ///
  /// In en, this message translates to:
  /// **'Linked note'**
  String get eventLinkedNote;

  /// Shown when the note linked to an event has been deleted
  ///
  /// In en, this message translates to:
  /// **'Linked note no longer exists'**
  String get eventLinkedNoteMissing;

  /// Shown when an event is opened for editing after it was deleted elsewhere
  ///
  /// In en, this message translates to:
  /// **'Event no longer exists'**
  String get eventNoLongerExists;

  /// Tooltip for the button that opens the note linked to an event
  ///
  /// In en, this message translates to:
  /// **'Open linked note'**
  String get eventOpenLinkedNote;

  /// Tooltip for the button that unlinks the note from an event
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get eventRemoveNoteLink;

  /// Icon picker group: strength training
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get iconGroupStrength;

  /// Icon picker group: cardio
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get iconGroupCardio;

  /// Icon picker group: team/racket sports
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get iconGroupSports;

  /// Icon picker group: rest and recovery
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get iconGroupRecovery;

  /// Icon picker group: body and nutrition
  ///
  /// In en, this message translates to:
  /// **'Body & nutrition'**
  String get iconGroupBody;

  /// Icon picker group: measurement
  ///
  /// In en, this message translates to:
  /// **'Measurement'**
  String get iconGroupMeasurement;

  /// Icon picker group: achievements
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get iconGroupAchievements;

  /// Icon picker group: travel
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get iconGroupTravel;

  /// Icon picker group: time and schedule
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get iconGroupTime;

  /// Icon picker group: miscellaneous icons
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get iconGroupGeneric;

  /// Icon picker group: work and office icons
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get iconGroupWork;

  /// Icon picker group: study and school icons
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get iconGroupEducation;

  /// Icon picker group: medical and health icons
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get iconGroupHealth;

  /// Icon picker group: household and chore icons
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get iconGroupHome;

  /// Icon picker group: money and banking icons
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get iconGroupFinance;

  /// Icon picker group: meal and drink icons
  ///
  /// In en, this message translates to:
  /// **'Food & drink'**
  String get iconGroupFoodDrink;

  /// Icon picker group: vehicle and travel icons
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get iconGroupTransport;

  /// Icon picker group: media and hobby icons
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get iconGroupEntertainment;

  /// Icon picker group: social and community icons
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get iconGroupPeople;

  /// Icon picker group: weather and outdoor icons
  ///
  /// In en, this message translates to:
  /// **'Nature'**
  String get iconGroupNature;

  /// Icon picker group: device and computing icons
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get iconGroupTech;

  /// Icon picker group: shapes and status marker icons
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get iconGroupSymbols;

  /// Icon picker group: A-Z letter glyphs used as icons
  ///
  /// In en, this message translates to:
  /// **'Letters'**
  String get iconGroupLetters;

  /// Icon picker group: 0-9 digit glyphs used as icons
  ///
  /// In en, this message translates to:
  /// **'Numbers'**
  String get iconGroupDigits;

  /// Icon picker section listing the icons picked most recently
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get iconGroupRecent;

  /// Welcome message on onboarding screen
  ///
  /// In en, this message translates to:
  /// **'Welcome to ANTA'**
  String get welcomeToApp;

  /// Description on onboarding screen
  ///
  /// In en, this message translates to:
  /// **'Track your notes, spending, and schedule in one place. Get started by creating a fresh workspace or restore from a previous backup.'**
  String get onboardingDescription;

  /// Button to start with empty workspace
  ///
  /// In en, this message translates to:
  /// **'Start Fresh'**
  String get startFresh;

  /// Button to restore from backup file
  ///
  /// In en, this message translates to:
  /// **'Restore from Backup'**
  String get restoreFromBackup;

  /// Title for import confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get confirmImport;

  /// Label before listing backup contents
  ///
  /// In en, this message translates to:
  /// **'This backup contains:'**
  String get backupContains;

  /// Onboarding's restore confirmation: how many folders the chosen backup holds
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}}'**
  String onboardingBackupFolders(int count);

  /// Onboarding's restore confirmation: how many notes the chosen backup holds
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}}'**
  String onboardingBackupNotes(int count);

  /// Caption at the foot of the welcome screen; names the drawer row howToUseAnta
  ///
  /// In en, this message translates to:
  /// **'You can open How to use ANTA from the menu at any time'**
  String get onboardingHowToHint;

  /// Shows when backup was exported
  ///
  /// In en, this message translates to:
  /// **'Exported on: {date}'**
  String exportedOn(String date);

  /// Button to import data
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// Success message after import
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {folders} folders and {notes} notes'**
  String importSuccess(int folders, int notes);

  /// Error message when import fails
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// Error message for invalid backup file
  ///
  /// In en, this message translates to:
  /// **'Invalid backup file'**
  String get invalidBackupFile;

  /// Button to export all data as backup
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get exportBackup;

  /// Label for folders section
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// Label for notes section
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// Button text to create a new folder
  ///
  /// In en, this message translates to:
  /// **'Create Folder'**
  String get createFolder;

  /// Button text to create a new note
  ///
  /// In en, this message translates to:
  /// **'Create Note'**
  String get createNote;

  /// Label for folder name input
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// Label for note name input
  ///
  /// In en, this message translates to:
  /// **'Note Name'**
  String get noteName;

  /// Cancel button text
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Create button text
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Edit button text
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Delete button text
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Save button text
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Search placeholder text
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Error message with placeholder
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String error(String message);

  /// Created date label
  ///
  /// In en, this message translates to:
  /// **'Created: {date}'**
  String created(String date);

  /// Updated date label
  ///
  /// In en, this message translates to:
  /// **'Updated: {date}'**
  String updated(String date);

  /// Delete folder dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// Delete folder confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteFolderConfirm(String name);

  /// Delete folder confirmation message when folder contains notes
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? {count, plural, =1{This will also delete 1 note.} other{This will also delete {count} notes.}}'**
  String deleteFolderWithNotesConfirm(String name, int count);

  /// Rename button text
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Rename folder dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolder;

  /// Default title for untitled notes
  ///
  /// In en, this message translates to:
  /// **'Untitled Note'**
  String get untitledNote;

  /// Text shown for empty notes
  ///
  /// In en, this message translates to:
  /// **'Empty note'**
  String get emptyNote;

  /// Error shown when a note action cannot find the note — it has no saved copy yet, or it was deleted elsewhere
  ///
  /// In en, this message translates to:
  /// **'Note not found'**
  String get noteNotFound;

  /// Delete note dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get deleteNote;

  /// Delete note confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"?'**
  String deleteNoteConfirm(String title);

  /// Text for deleting unnamed note
  ///
  /// In en, this message translates to:
  /// **'this note'**
  String get deleteThisNote;

  /// Hint text for folder name input
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get enterFolderName;

  /// Title for new note
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get newNote;

  /// Tooltip for switching to edit mode
  ///
  /// In en, this message translates to:
  /// **'Switch to Edit mode'**
  String get switchToEditMode;

  /// Tooltip for previewing markdown
  ///
  /// In en, this message translates to:
  /// **'Preview markdown'**
  String get previewMarkdown;

  /// Preview button text
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// Tooltip when auto-save is enabled
  ///
  /// In en, this message translates to:
  /// **'Auto-save is ON (saves every 5s after changes)'**
  String get autoSaveOn;

  /// Tooltip to enable auto-save
  ///
  /// In en, this message translates to:
  /// **'Enable auto-save'**
  String get enableAutoSave;

  /// Auto-save off tooltip
  ///
  /// In en, this message translates to:
  /// **'Auto-save OFF'**
  String get autoSaveOff;

  /// Tooltip for save button
  ///
  /// In en, this message translates to:
  /// **'Save note'**
  String get saveNote;

  /// Placeholder text when no content
  ///
  /// In en, this message translates to:
  /// **'*No content yet*'**
  String get noContentYet;

  /// Hint text for note editor
  ///
  /// In en, this message translates to:
  /// **'Start writing your first note...'**
  String get startWriting;

  /// Error message when note is empty
  ///
  /// In en, this message translates to:
  /// **'Note cannot be empty'**
  String get noteCannotBeEmpty;

  /// Success message when note is saved
  ///
  /// In en, this message translates to:
  /// **'Note saved!'**
  String get noteSaved;

  /// Edit title dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit title'**
  String get editTitle;

  /// Hint text for note title input
  ///
  /// In en, this message translates to:
  /// **'Enter note title'**
  String get enterNoteTitle;

  /// Message when auto-save is enabled
  ///
  /// In en, this message translates to:
  /// **'Auto-save enabled'**
  String get autoSaveEnabled;

  /// Message when auto-save is disabled
  ///
  /// In en, this message translates to:
  /// **'Auto-save disabled'**
  String get autoSaveDisabled;

  /// Markdown shortcuts page title
  ///
  /// In en, this message translates to:
  /// **'Markdown Shortcuts'**
  String get markdownShortcuts;

  /// Remove all custom shortcuts button text
  ///
  /// In en, this message translates to:
  /// **'Remove All Custom'**
  String get removeAllCustom;

  /// Message when no custom shortcuts exist
  ///
  /// In en, this message translates to:
  /// **'No custom shortcuts yet'**
  String get noCustomShortcutsYet;

  /// Hint to add shortcuts
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to add one'**
  String get tapToAddShortcut;

  /// Delete shortcut dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Shortcut'**
  String get deleteShortcut;

  /// Delete shortcut confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this shortcut?'**
  String get deleteShortcutConfirm;

  /// Reset dialog title
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get resetDialogTitle;

  /// Reset dialog message
  ///
  /// In en, this message translates to:
  /// **'This will restore all default shortcuts to their original order and settings. Custom shortcuts will be kept but moved to the end.'**
  String get resetDialogMessage;

  /// Reset button text
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Remove custom dialog title
  ///
  /// In en, this message translates to:
  /// **'Remove All Custom'**
  String get removeCustomDialogTitle;

  /// Remove custom dialog message
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all custom shortcuts you created. Default shortcuts will remain.'**
  String get removeCustomDialogMessage;

  /// Remove button text
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Label for default shortcuts
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get defaultLabel;

  /// Description for date shortcut
  ///
  /// In en, this message translates to:
  /// **'Inserts current date'**
  String get insertsCurrentDate;

  /// Description for header shortcut
  ///
  /// In en, this message translates to:
  /// **'Opens the heading menu (body text, H1-H6)'**
  String get opensHeaderMenu;

  /// Description showing before and after text
  ///
  /// In en, this message translates to:
  /// **'Before: \"{before}\" | After: \"{after}\"'**
  String beforeAfterText(String before, String after);

  /// Hide button tooltip
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// Show button tooltip
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// New shortcut dialog title
  ///
  /// In en, this message translates to:
  /// **'New Shortcut'**
  String get newShortcut;

  /// Edit shortcut dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit Shortcut'**
  String get editShortcut;

  /// Icon label
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get icon;

  /// Hint to change icon
  ///
  /// In en, this message translates to:
  /// **'Tap to change icon'**
  String get tapToChangeIcon;

  /// Select icon dialog title
  ///
  /// In en, this message translates to:
  /// **'Select Icon'**
  String get selectIcon;

  /// Placeholder for icon search input
  ///
  /// In en, this message translates to:
  /// **'Search icons...'**
  String get searchIcons;

  /// Message when no icons match search
  ///
  /// In en, this message translates to:
  /// **'No icons found'**
  String get noIconsFound;

  /// Label input field
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// Hint for label input
  ///
  /// In en, this message translates to:
  /// **'e.g., Highlight'**
  String get labelHint;

  /// Insert type label
  ///
  /// In en, this message translates to:
  /// **'Insert Type'**
  String get insertType;

  /// Wrap selected text option
  ///
  /// In en, this message translates to:
  /// **'Wrap Selected Text'**
  String get wrapSelectedText;

  /// Insert current date option
  ///
  /// In en, this message translates to:
  /// **'Insert Current Date'**
  String get insertCurrentDate;

  /// Before date label
  ///
  /// In en, this message translates to:
  /// **'Before Date (optional)'**
  String get beforeDate;

  /// Markdown start label
  ///
  /// In en, this message translates to:
  /// **'Markdown Start'**
  String get markdownStart;

  /// Hint for markdown start
  ///
  /// In en, this message translates to:
  /// **'e.g., =='**
  String get markdownStartHint;

  /// Hint for text before date
  ///
  /// In en, this message translates to:
  /// **'Optional text before date'**
  String get optionalTextBeforeDate;

  /// After date label
  ///
  /// In en, this message translates to:
  /// **'After Date (optional)'**
  String get afterDate;

  /// Markdown end label
  ///
  /// In en, this message translates to:
  /// **'Markdown End'**
  String get markdownEnd;

  /// Hint for text after date
  ///
  /// In en, this message translates to:
  /// **'Optional text after date'**
  String get optionalTextAfterDate;

  /// Error message when label is empty
  ///
  /// In en, this message translates to:
  /// **'Label cannot be empty'**
  String get labelCannotBeEmpty;

  /// Snackbar message when form has validation errors
  ///
  /// In en, this message translates to:
  /// **'Please fix the errors in the form'**
  String get formHasErrors;

  /// Bold shortcut label
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// Italic shortcut label
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// Headers shortcut label
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get headers;

  /// Point list shortcut label
  ///
  /// In en, this message translates to:
  /// **'Point List'**
  String get pointList;

  /// Strikethrough shortcut label
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get strikethrough;

  /// Bullet list shortcut label
  ///
  /// In en, this message translates to:
  /// **'Bullet List'**
  String get bulletList;

  /// Numbered list shortcut label
  ///
  /// In en, this message translates to:
  /// **'Numbered List'**
  String get numberedList;

  /// Checkbox shortcut label
  ///
  /// In en, this message translates to:
  /// **'Checkbox'**
  String get checkbox;

  /// Quote shortcut label
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get quote;

  /// Inline code shortcut label
  ///
  /// In en, this message translates to:
  /// **'Inline Code'**
  String get inlineCode;

  /// Code block shortcut label
  ///
  /// In en, this message translates to:
  /// **'Code Block'**
  String get codeBlock;

  /// Link shortcut label
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// Current date shortcut label
  ///
  /// In en, this message translates to:
  /// **'Current Date'**
  String get currentDate;

  /// Header 1 menu item
  ///
  /// In en, this message translates to:
  /// **'Heading 1'**
  String get header1;

  /// Header 2 menu item
  ///
  /// In en, this message translates to:
  /// **'Heading 2'**
  String get header2;

  /// Header 3 menu item
  ///
  /// In en, this message translates to:
  /// **'Heading 3'**
  String get header3;

  /// Header 4 menu item
  ///
  /// In en, this message translates to:
  /// **'Heading 4'**
  String get header4;

  /// Header 5 menu item
  ///
  /// In en, this message translates to:
  /// **'Heading 5'**
  String get header5;

  /// Header 6 menu item
  ///
  /// In en, this message translates to:
  /// **'Heading 6'**
  String get header6;

  /// The heading menu's first item: turns the caret line back into plain text
  ///
  /// In en, this message translates to:
  /// **'Body text'**
  String get headingBodyText;

  /// Markdown bar button tooltip: indent the list line one level
  ///
  /// In en, this message translates to:
  /// **'Indent'**
  String get indentLine;

  /// Markdown bar button tooltip: move the list line one level out
  ///
  /// In en, this message translates to:
  /// **'Outdent'**
  String get outdentLine;

  /// Highlight shortcut label
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get shortcutHighlight;

  /// Callout shortcut label (a > [!NOTE] block)
  ///
  /// In en, this message translates to:
  /// **'Callout'**
  String get shortcutCallout;

  /// Checked checkbox shortcut label
  ///
  /// In en, this message translates to:
  /// **'Checked Checkbox'**
  String get shortcutCheckedCheckbox;

  /// Table shortcut label
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get shortcutTable;

  /// Horizontal rule shortcut label
  ///
  /// In en, this message translates to:
  /// **'Horizontal Rule'**
  String get shortcutHorizontalRule;

  /// Image shortcut label
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get shortcutImage;

  /// Ghost text shortcut label (a {{ placeholder }} the user fills in later)
  ///
  /// In en, this message translates to:
  /// **'Ghost Text'**
  String get shortcutGhostText;

  /// Coloured text shortcut label
  ///
  /// In en, this message translates to:
  /// **'Color Text'**
  String get shortcutColorText;

  /// Coloured highlight shortcut label
  ///
  /// In en, this message translates to:
  /// **'Color Highlight'**
  String get shortcutColorHighlight;

  /// Money ledger shortcut label: add an amount
  ///
  /// In en, this message translates to:
  /// **'Money +'**
  String get shortcutMoneyAdd;

  /// Money ledger shortcut label: subtract an amount
  ///
  /// In en, this message translates to:
  /// **'Money -'**
  String get shortcutMoneySubtract;

  /// Money ledger shortcut label: multiply the balance
  ///
  /// In en, this message translates to:
  /// **'Money ×'**
  String get shortcutMoneyMultiply;

  /// Money ledger shortcut label: divide the balance
  ///
  /// In en, this message translates to:
  /// **'Money ÷'**
  String get shortcutMoneyDivide;

  /// Money ledger shortcut label: set the starting balance
  ///
  /// In en, this message translates to:
  /// **'Money Start'**
  String get shortcutMoneyStart;

  /// Money ledger shortcut label: show the running total
  ///
  /// In en, this message translates to:
  /// **'Money Total'**
  String get shortcutMoneyTotal;

  /// Money ledger shortcut label: show the change since a point
  ///
  /// In en, this message translates to:
  /// **'Money Change'**
  String get shortcutMoneyChange;

  /// Money ledger shortcut label: a target amount
  ///
  /// In en, this message translates to:
  /// **'Money Target'**
  String get shortcutMoneyTarget;

  /// Money ledger shortcut label: the difference between two amounts
  ///
  /// In en, this message translates to:
  /// **'Money Diff'**
  String get shortcutMoneyDiff;

  /// Money ledger shortcut label: the total over a span of lines
  ///
  /// In en, this message translates to:
  /// **'Money Span'**
  String get shortcutMoneySpan;

  /// Undo button tooltip
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Redo button tooltip
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// Paste button tooltip
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// Decrease font size button tooltip
  ///
  /// In en, this message translates to:
  /// **'Decrease Font Size'**
  String get decreaseFontSize;

  /// Increase font size button tooltip
  ///
  /// In en, this message translates to:
  /// **'Increase Font Size'**
  String get increaseFontSize;

  /// Accessibility label for drop indicator during drag
  ///
  /// In en, this message translates to:
  /// **'Drop position'**
  String get dropPosition;

  /// Accessibility label for shortcut button
  ///
  /// In en, this message translates to:
  /// **'{label} button'**
  String shortcutButton(String label);

  /// Warning message to remind users to add space after markdown syntax
  ///
  /// In en, this message translates to:
  /// **'Tip: Add a space after markdown syntax (e.g., \'# \' or \'- \') for proper formatting.'**
  String get markdownSpaceWarning;

  /// Tooltip for reorder shortcuts button
  ///
  /// In en, this message translates to:
  /// **'Reorder shortcuts'**
  String get reorderShortcuts;

  /// Button text to finish reordering
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneReordering;

  /// Message when search returns no results
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noSearchResults;

  /// Hint text for search input
  ///
  /// In en, this message translates to:
  /// **'Type to search notes'**
  String get searchHint;

  /// Text shown while loading more items
  ///
  /// In en, this message translates to:
  /// **'Loading more...'**
  String get loadingMore;

  /// Text shown when all notes are loaded
  ///
  /// In en, this message translates to:
  /// **'No more notes'**
  String get noMoreNotes;

  /// Label for sort options
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// Sort option for last updated
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get sortByUpdated;

  /// Sort option for date created
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get sortByCreated;

  /// Sort option for title
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortByTitle;

  /// Sort option for colour label
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get sortByLabel;

  /// Ascending sort order
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascending;

  /// Descending sort order
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descending;

  /// Message shown while loading note content
  ///
  /// In en, this message translates to:
  /// **'Loading content...'**
  String get loadingContent;

  /// Warning for large notes
  ///
  /// In en, this message translates to:
  /// **'This note is very large and may take a moment to load'**
  String get largeNoteWarning;

  /// Note statistics display
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 character} other{{count} characters}} · {lines, plural, =1{1 line} other{{lines} lines}}'**
  String noteStats(int count, int lines);

  /// Storage chunk count on the note stats strip, shown only with the developer chunk indicators on
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 chunk} other{{count} chunks}}'**
  String noteChunkCount(int count);

  /// Dimmed hint in an empty note editor
  ///
  /// In en, this message translates to:
  /// **'Start typing…'**
  String get editorHint;

  /// Tooltip of the in-note find row's trailing X while its query is empty
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// Spoken label of the note editor's save indicator when every change is saved
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saveStateSaved;

  /// Spoken label of the note editor's save indicator while changes wait for the next save
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get saveStateUnsaved;

  /// Spoken label of the note editor's save indicator while a save runs
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get saveStateSaving;

  /// Spoken label of the note editor's save indicator when the last save failed
  ///
  /// In en, this message translates to:
  /// **'Not saved'**
  String get saveStateError;

  /// Label for compressed notes
  ///
  /// In en, this message translates to:
  /// **'Compressed'**
  String get compressedNote;

  /// Tooltip for folder search
  ///
  /// In en, this message translates to:
  /// **'Search in this folder'**
  String get searchInFolder;

  /// Tooltip for global search
  ///
  /// In en, this message translates to:
  /// **'Search all notes'**
  String get searchAll;

  /// Label for recent searches section
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// Search scope chip that searches every note in the app
  ///
  /// In en, this message translates to:
  /// **'Everywhere'**
  String get everywhere;

  /// Search scope chip for the current folder and its subfolders, used when the folder name is unavailable
  ///
  /// In en, this message translates to:
  /// **'This folder'**
  String get thisFolder;

  /// Section label above recently edited notes shown before anything is typed into search, and the title of the page the root browser's Recent row opens
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// Root browser row and page title for the flat list of every note in every folder
  ///
  /// In en, this message translates to:
  /// **'All notes'**
  String get allNotes;

  /// Relative date on a note row and a search result, for a note edited today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Relative date on a note row and a search result, for a note edited yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Search results section label for notes matched by their title
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get titlesSection;

  /// Search results section label for notes matched inside their text
  ///
  /// In en, this message translates to:
  /// **'In text'**
  String get inTextSection;

  /// One line above full-search results while the note search index is still being built, so some matching notes may not be listed yet
  ///
  /// In en, this message translates to:
  /// **'Still indexing notes — some may be missing'**
  String get searchStillIndexing;

  /// Button to clear search history
  ///
  /// In en, this message translates to:
  /// **'Clear search history'**
  String get clearSearchHistory;

  /// Label for date filter
  ///
  /// In en, this message translates to:
  /// **'Filter by date'**
  String get filterByDate;

  /// Label for start date filter
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromDate;

  /// Label for end date filter
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toDate;

  /// Button to apply filters
  ///
  /// In en, this message translates to:
  /// **'Apply filter'**
  String get applyFilter;

  /// Button to clear filters
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get clearFilter;

  /// Number of search matches
  ///
  /// In en, this message translates to:
  /// **'{count} matches found'**
  String matchesFound(int count);

  /// Message shown during auto-save
  ///
  /// In en, this message translates to:
  /// **'Auto-saving...'**
  String get autoSaving;

  /// Message after successful save
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get changesSaved;

  /// Warning about unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// Button to discard changes
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get discardChanges;

  /// Button to continue editing
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// Info about virtual scrolling
  ///
  /// In en, this message translates to:
  /// **'Virtual scroll enabled for large content'**
  String get virtualScrollEnabled;

  /// Number of lines in note
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String lineCount(int count);

  /// Hint text shown when there are no folders
  ///
  /// In en, this message translates to:
  /// **'Looks like you might want to create a folder'**
  String get emptyFoldersHint;

  /// Hint text shown when there are no notes in a folder
  ///
  /// In en, this message translates to:
  /// **'Write your first note'**
  String get emptyNotesHint;

  /// Empty-state hint pointing at the browser's bottom create bar
  ///
  /// In en, this message translates to:
  /// **'Use the bar below to add one'**
  String get createFromBarBelow;

  /// Tooltip on the bottom bar's create-folder button
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// How many folders a list holds
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No folders} =1{1 folder} other{{count} folders}}'**
  String folderCountLabel(int count);

  /// How many notes a folder or list holds, counting subfolders on a folder row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No notes} =1{1 note} other{{count} notes}}'**
  String noteCountLabel(int count);

  /// Joins an already-pluralised folder count and note count, e.g. "3 folders, 5 notes"
  ///
  /// In en, this message translates to:
  /// **'{folders}, {notes}'**
  String folderAndNoteCount(String folders, String notes);

  /// Character count display
  ///
  /// In en, this message translates to:
  /// **'{current}/{max} characters'**
  String charactersCount(int current, int max);

  /// Settings label
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Database settings menu item
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get databaseSettings;

  /// About menu item
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// Database location card title
  ///
  /// In en, this message translates to:
  /// **'Database Location'**
  String get databaseLocation;

  /// Copy path button text
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get copyPath;

  /// Open in Finder/Explorer button text
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get openInFinder;

  /// Database statistics card title
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get databaseStats;

  /// Size label
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// Last modified label
  ///
  /// In en, this message translates to:
  /// **'Last Modified'**
  String get lastModified;

  /// Maintenance card title
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

  /// Maintenance description
  ///
  /// In en, this message translates to:
  /// **'Run SQLite VACUUM to reclaim unused space from deleted notes and folders. This rebuilds the database file, defragments the data, and can significantly reduce file size after deleting large amounts of content. The operation may take a few seconds depending on database size.'**
  String get maintenanceDesc;

  /// Optimize database button text
  ///
  /// In en, this message translates to:
  /// **'Optimize Database'**
  String get optimizeDatabase;

  /// Danger zone card title
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get dangerZone;

  /// Danger zone description
  ///
  /// In en, this message translates to:
  /// **'These actions are irreversible. All your notes and folders will be permanently deleted.'**
  String get dangerZoneDesc;

  /// Delete all data button text
  ///
  /// In en, this message translates to:
  /// **'Delete All Data'**
  String get deleteAllData;

  /// Path copied confirmation message
  ///
  /// In en, this message translates to:
  /// **'Path copied to clipboard'**
  String get pathCopied;

  /// Platform not supported message
  ///
  /// In en, this message translates to:
  /// **'Not supported on this platform'**
  String get notSupportedOnPlatform;

  /// Error opening folder message
  ///
  /// In en, this message translates to:
  /// **'Error opening folder'**
  String get errorOpeningFolder;

  /// Optimizing message
  ///
  /// In en, this message translates to:
  /// **'Optimizing database...'**
  String get optimizing;

  /// Snackbar after Optimize on the Databases page: the free space inside the database file that the run gave back
  ///
  /// In en, this message translates to:
  /// **'Freed {size}'**
  String optimizeFreed(String size);

  /// Snackbar after Optimize on the Databases page when the database file held no free space to give back
  ///
  /// In en, this message translates to:
  /// **'Already compact'**
  String get optimizeAlreadyCompact;

  /// Delete confirmation message
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. All your notes, folders, and data will be permanently deleted. Are you absolutely sure?'**
  String get deleteConfirmation;

  /// Delete not implemented message
  ///
  /// In en, this message translates to:
  /// **'Delete functionality not yet implemented for safety'**
  String get deleteNotImplemented;

  /// Loading text while deleting data
  ///
  /// In en, this message translates to:
  /// **'Deleting all data...'**
  String get deletingData;

  /// Title for data deleted success dialog
  ///
  /// In en, this message translates to:
  /// **'Data Deleted'**
  String get dataDeleted;

  /// Message after data deletion requiring restart
  ///
  /// In en, this message translates to:
  /// **'All data has been deleted. Please restart the app to continue.'**
  String get restartRequiredAfterDeletion;

  /// Button to exit the app
  ///
  /// In en, this message translates to:
  /// **'Exit App'**
  String get exitApp;

  /// Error message prefix for deletion failure
  ///
  /// In en, this message translates to:
  /// **'Error deleting data'**
  String get errorDeletingData;

  /// Share database button text
  ///
  /// In en, this message translates to:
  /// **'Share Database'**
  String get shareDatabase;

  /// Share database description
  ///
  /// In en, this message translates to:
  /// **'Export and share your database file via email, messaging apps, or cloud storage for backup purposes.'**
  String get shareDatabaseDesc;

  /// Message shown while preparing share
  ///
  /// In en, this message translates to:
  /// **'Preparing to share...'**
  String get preparingShare;

  /// Share error message prefix
  ///
  /// In en, this message translates to:
  /// **'Error sharing database'**
  String get shareError;

  /// Error when database file does not exist
  ///
  /// In en, this message translates to:
  /// **'Database file not found'**
  String get databaseNotFound;

  /// Rename note dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename note'**
  String get renameNote;

  /// Hint text for rename input
  ///
  /// In en, this message translates to:
  /// **'Enter new name'**
  String get enterNewName;

  /// Custom sort order option
  ///
  /// In en, this message translates to:
  /// **'Custom Order'**
  String get sortByCustom;

  /// Quick sort button label
  ///
  /// In en, this message translates to:
  /// **'Quick Sort'**
  String get quickSort;

  /// Sort items dialog title
  ///
  /// In en, this message translates to:
  /// **'Sort Items'**
  String get sortItems;

  /// Sort folders option
  ///
  /// In en, this message translates to:
  /// **'Sort Folders'**
  String get sortFolders;

  /// Sort notes option
  ///
  /// In en, this message translates to:
  /// **'Sort Notes'**
  String get sortNotes;

  /// Sort by name option
  ///
  /// In en, this message translates to:
  /// **'By Name'**
  String get sortByName;

  /// Move item up action
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get moveUp;

  /// Move item down action
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get moveDown;

  /// Folder swipe gesture setting
  ///
  /// In en, this message translates to:
  /// **'Swipe to open menu in folders'**
  String get folderSwipeGesture;

  /// Folder swipe gesture description
  ///
  /// In en, this message translates to:
  /// **'Swipe from left edge to open the navigation menu when browsing folders'**
  String get folderSwipeGestureDesc;

  /// Note swipe gesture setting
  ///
  /// In en, this message translates to:
  /// **'Swipe to open menu in notes'**
  String get noteSwipeGesture;

  /// Note swipe gesture description
  ///
  /// In en, this message translates to:
  /// **'Swipe from left edge to open the navigation menu when editing notes'**
  String get noteSwipeGestureDesc;

  /// Feedback section title
  ///
  /// In en, this message translates to:
  /// **'Feedback & confirmation'**
  String get feedbackSection;

  /// Haptic feedback setting
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get hapticFeedback;

  /// Haptic feedback description
  ///
  /// In en, this message translates to:
  /// **'Vibrate on interactions like toggling switches'**
  String get hapticFeedbackDesc;

  /// Confirm delete setting
  ///
  /// In en, this message translates to:
  /// **'Confirm before delete'**
  String get confirmDelete;

  /// Confirm delete description
  ///
  /// In en, this message translates to:
  /// **'Show confirmation dialog before deleting notes or folders'**
  String get confirmDeleteDesc;

  /// Auto-save section title
  ///
  /// In en, this message translates to:
  /// **'Auto-save'**
  String get autoSaveSection;

  /// Auto-save setting
  ///
  /// In en, this message translates to:
  /// **'Auto-save notes'**
  String get autoSave;

  /// Auto-save description: what the switch's off state still writes, so nobody expects text to be lost
  ///
  /// In en, this message translates to:
  /// **'Save while you type. Off, a note is saved when you leave it or the app goes to the background.'**
  String get autoSaveDesc;

  /// Auto-save interval setting
  ///
  /// In en, this message translates to:
  /// **'Auto-save interval'**
  String get autoSaveInterval;

  /// Auto-save interval description: the slider sets the debounce after the last keystroke, not a fixed cadence
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Saves one second after the last change} other{Saves {seconds} seconds after the last change}}'**
  String autoSaveIntervalDesc(int seconds);

  /// The auto-save interval slider's value label: a number of seconds with the unit's symbol
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String autoSaveSeconds(int count);

  /// Startup section title on the controls settings page
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get startupSection;

  /// Setting that controls how much of the previous navigation stack is restored on launch
  ///
  /// In en, this message translates to:
  /// **'Reopen last screen'**
  String get restoreLocation;

  /// Description for the reopen-last-screen setting
  ///
  /// In en, this message translates to:
  /// **'What ANTA opens when you launch it'**
  String get restoreLocationDesc;

  /// Reopen-last-screen option: always start at the home screen
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get restoreLocationOff;

  /// Reopen-last-screen option: restore only the folder and note the user was in
  ///
  /// In en, this message translates to:
  /// **'Folders and notes'**
  String get restoreLocationNotes;

  /// Reopen-last-screen option: restore the whole chain, calendar and settings pages included
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get restoreLocationEverything;

  /// Comma-separated hidden search synonyms for the reopen-last-screen setting
  ///
  /// In en, this message translates to:
  /// **'launch, resume, remember, last, screen, start'**
  String get restoreLocationKeywords;

  /// Section title for the folder/note browser settings
  ///
  /// In en, this message translates to:
  /// **'Folders & notes'**
  String get displaySection;

  /// Show note preview setting
  ///
  /// In en, this message translates to:
  /// **'Show note preview'**
  String get showNotePreview;

  /// Show note preview description
  ///
  /// In en, this message translates to:
  /// **'Display a preview of note content in the list'**
  String get showNotePreviewDesc;

  /// Show stats bar setting
  ///
  /// In en, this message translates to:
  /// **'Show stats bar'**
  String get showStatsBar;

  /// Show stats bar description
  ///
  /// In en, this message translates to:
  /// **'Display character count and line count in note editor'**
  String get showStatsBarDesc;

  /// Reset to defaults button
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaults;

  /// Reset to defaults confirmation
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset all settings to their default values?'**
  String get resetToDefaultsConfirm;

  /// Settings reset confirmation message
  ///
  /// In en, this message translates to:
  /// **'Settings have been reset to defaults'**
  String get settingsReset;

  /// Error shown when App settings' Reset to defaults fails part-way
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset the settings'**
  String get settingsResetFailed;

  /// Share note option
  ///
  /// In en, this message translates to:
  /// **'Share note'**
  String get shareNote;

  /// Share folder option (exports folder tree as zip archive)
  ///
  /// In en, this message translates to:
  /// **'Share folder'**
  String get shareFolder;

  /// Message shown while exporting a folder archive
  ///
  /// In en, this message translates to:
  /// **'Exporting folder...'**
  String get exportingFolder;

  /// Error message when folder export fails
  ///
  /// In en, this message translates to:
  /// **'Error exporting folder'**
  String get folderExportError;

  /// Message shown while importing a file or archive
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get importingFile;

  /// Error message when import fails
  ///
  /// In en, this message translates to:
  /// **'Error importing file'**
  String get importFileError;

  /// Menu entry to import a note file or folder archive
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importNoteOrFolder;

  /// Snackbar after a successful import
  ///
  /// In en, this message translates to:
  /// **'{folders, plural, =1{Imported 1 folder} other{Imported {folders} folders}}, {notes, plural, =1{1 note} other{{notes} notes}}'**
  String importedSummary(int folders, int notes);

  /// Selection action bar button to export the current selection as a zip
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareSelected;

  /// Loading message while building a multi-select archive
  ///
  /// In en, this message translates to:
  /// **'Exporting selection...'**
  String get exportingSelection;

  /// Error message when multi-select export fails
  ///
  /// In en, this message translates to:
  /// **'Error exporting selection'**
  String get selectionExportError;

  /// Note options bottom sheet title
  ///
  /// In en, this message translates to:
  /// **'Note Options'**
  String get noteOptions;

  /// Message shown while exporting note
  ///
  /// In en, this message translates to:
  /// **'Exporting note...'**
  String get exportingNote;

  /// Error message when note export fails
  ///
  /// In en, this message translates to:
  /// **'Error exporting note'**
  String get noteExportError;

  /// Title for export format selection dialog
  ///
  /// In en, this message translates to:
  /// **'Choose Export Format'**
  String get chooseExportFormat;

  /// Export as markdown option
  ///
  /// In en, this message translates to:
  /// **'Markdown (.md)'**
  String get exportAsMarkdown;

  /// Export as JSON option
  ///
  /// In en, this message translates to:
  /// **'JSON (.json)'**
  String get exportAsJson;

  /// Export as plain text option
  ///
  /// In en, this message translates to:
  /// **'Plain Text (.txt)'**
  String get exportAsText;

  /// Section title for active database selection
  ///
  /// In en, this message translates to:
  /// **'Active Database'**
  String get activeDatabaseSection;

  /// Description for active database section
  ///
  /// In en, this message translates to:
  /// **'Select which database to use. Creating or switching databases will restart the app.'**
  String get activeDatabaseDesc;

  /// Label for database selector
  ///
  /// In en, this message translates to:
  /// **'Select Database'**
  String get selectDatabase;

  /// Shows current active database
  ///
  /// In en, this message translates to:
  /// **'Current: {name}'**
  String currentDatabase(String name);

  /// Button to create new database
  ///
  /// In en, this message translates to:
  /// **'Create New Database'**
  String get createNewDatabase;

  /// Label for new database name input
  ///
  /// In en, this message translates to:
  /// **'Database Name'**
  String get newDatabaseName;

  /// Hint for database name input
  ///
  /// In en, this message translates to:
  /// **'Enter database name'**
  String get enterDatabaseName;

  /// Error for invalid database name
  ///
  /// In en, this message translates to:
  /// **'Invalid name. Use only letters, numbers, underscores, and hyphens (max 50 characters).'**
  String get invalidDatabaseName;

  /// Error when database already exists
  ///
  /// In en, this message translates to:
  /// **'A database with this name already exists.'**
  String get databaseExists;

  /// Message while creating database
  ///
  /// In en, this message translates to:
  /// **'Creating database...'**
  String get creatingDatabase;

  /// Success message after creating database
  ///
  /// In en, this message translates to:
  /// **'Database created successfully'**
  String get databaseCreated;

  /// Button and dialog title to import an external database file
  ///
  /// In en, this message translates to:
  /// **'Import Database'**
  String get importDatabase;

  /// Message while importing a database file
  ///
  /// In en, this message translates to:
  /// **'Importing database...'**
  String get importingDatabase;

  /// Success message after importing a database
  ///
  /// In en, this message translates to:
  /// **'Database imported successfully'**
  String get databaseImported;

  /// Error when the selected file is not a SQLite database
  ///
  /// In en, this message translates to:
  /// **'This file is not a valid database.'**
  String get invalidDatabaseFile;

  /// Import dialog's second step, after the copy: the copied database file is being checked and can no longer be cancelled
  ///
  /// In en, this message translates to:
  /// **'Checking the file...'**
  String get checkingDatabaseFile;

  /// Error when an imported database file fails its integrity check
  ///
  /// In en, this message translates to:
  /// **'This database file is damaged and can\'t be imported.'**
  String get databaseImportCorrupt;

  /// Error when an imported file is a SQLite database from another app
  ///
  /// In en, this message translates to:
  /// **'This file is not an ANTA database.'**
  String get databaseImportNotAnta;

  /// Error when an imported database was written by a newer version of the app
  ///
  /// In en, this message translates to:
  /// **'This database is from a newer version of ANTA. Update the app to import it.'**
  String get databaseImportTooNew;

  /// Dialog title for renaming database
  ///
  /// In en, this message translates to:
  /// **'Rename Database'**
  String get renameDatabase;

  /// Message while renaming database
  ///
  /// In en, this message translates to:
  /// **'Renaming database...'**
  String get renamingDatabase;

  /// Success message after renaming database
  ///
  /// In en, this message translates to:
  /// **'Database renamed successfully'**
  String get databaseRenamed;

  /// Message while switching database
  ///
  /// In en, this message translates to:
  /// **'Switching database...'**
  String get switchingDatabase;

  /// Section title for database list
  ///
  /// In en, this message translates to:
  /// **'Available Databases'**
  String get availableDatabases;

  /// Message when no databases exist
  ///
  /// In en, this message translates to:
  /// **'No databases found'**
  String get noDatabases;

  /// Title for database options menu
  ///
  /// In en, this message translates to:
  /// **'Database Options'**
  String get databaseOptions;

  /// Option to switch to a database
  ///
  /// In en, this message translates to:
  /// **'Switch to this database'**
  String get switchTo;

  /// Confirm before switching the active database; name is the database's file name
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}? ANTA restarts on it.'**
  String databaseSwitchConfirm(String name);

  /// A database file's size in bytes; size is the number, already formatted
  ///
  /// In en, this message translates to:
  /// **'{size} B'**
  String databaseSizeBytes(String size);

  /// A database file's size in kilobytes; size is the number, already formatted with one decimal
  ///
  /// In en, this message translates to:
  /// **'{size} KB'**
  String databaseSizeKilobytes(String size);

  /// A database file's size in megabytes; size is the number, already formatted with two decimals
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String databaseSizeMegabytes(String size);

  /// Shown in place of a value that could not be read (a size, a date, a path)
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownValue;

  /// Shown in place of the database path when reading it failed
  ///
  /// In en, this message translates to:
  /// **'Could not read the storage path'**
  String get databasePathError;

  /// Snackbar on the Databases page when creating a database throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the database'**
  String get databaseCreateFailed;

  /// Snackbar on the Databases page when renaming a database throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rename the database'**
  String get databaseRenameFailed;

  /// Snackbar on the Databases page when deleting a database throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the database'**
  String get databaseDeleteFailed;

  /// Snackbar on the Databases page when switching the active database throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t switch the database'**
  String get databaseSwitchFailed;

  /// Snackbar on the Databases page when optimizing the database throws
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t optimize the database'**
  String get databaseOptimizeFailed;

  /// Caption under the Optimize button on the Databases page: the free space inside the database file that optimizing would give back
  ///
  /// In en, this message translates to:
  /// **'Reclaimable: {size}'**
  String databaseReclaimable(String size);

  /// Caption under the Optimize button on the Databases page when the free space inside the database file could not be read
  ///
  /// In en, this message translates to:
  /// **'Reclaimable space unknown'**
  String get databaseReclaimableUnknown;

  /// Shown at launch, only while the database is being upgraded to a new app version
  ///
  /// In en, this message translates to:
  /// **'Updating your data…'**
  String get launchUpdatingData;

  /// Shown at launch after Retry on the failed state, while the database is opened again
  ///
  /// In en, this message translates to:
  /// **'Opening your data…'**
  String get launchOpeningData;

  /// Shown at launch when the database could not be opened or upgraded; the technical details follow it
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open your data'**
  String get launchOpenFailed;

  /// Under the launch's failed state: what the user can do next. The app's own pages are out of reach while the database cannot open
  ///
  /// In en, this message translates to:
  /// **'Try again, or restart the app. If this keeps happening, free up some storage space.'**
  String get launchOpenFailedNext;

  /// Confirmation message for database deletion
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the database \"{name}\"? This action cannot be undone.'**
  String deleteDatabaseConfirm(String name);

  /// Error when trying to delete active database
  ///
  /// In en, this message translates to:
  /// **'Cannot delete the currently active database. Please switch to another database first.'**
  String get cannotDeleteActive;

  /// Success message after deleting database
  ///
  /// In en, this message translates to:
  /// **'Database deleted'**
  String get databaseDeleted;

  /// Message after switching or importing a database, asking for an app restart
  ///
  /// In en, this message translates to:
  /// **'Please restart the app to use the new database.'**
  String get restartRequiredNewDatabase;

  /// Placeholder for note search field
  ///
  /// In en, this message translates to:
  /// **'Find in note'**
  String get findInNote;

  /// Tooltip for the button that empties the search field
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// Hint for the counter chip that opens the match list
  ///
  /// In en, this message translates to:
  /// **'Jump to match'**
  String get jumpToMatch;

  /// Label for the field that jumps to a match by number
  ///
  /// In en, this message translates to:
  /// **'Go to match'**
  String get goToMatchNumber;

  /// Placeholder for the jump-to-match-number field
  ///
  /// In en, this message translates to:
  /// **'Match #'**
  String get matchNumberHint;

  /// Valid range shown under the jump-to-match-number field
  ///
  /// In en, this message translates to:
  /// **'{min}–{max}'**
  String matchNumberRange(int min, int max);

  /// Accessibility hint for the jump-to-match-number field
  ///
  /// In en, this message translates to:
  /// **'Enter a number between {min} and {max}'**
  String enterMatchNumber(int min, int max);

  /// Long-press action on the counter chip that opens the match list with the number field focused
  ///
  /// In en, this message translates to:
  /// **'Type a match number'**
  String get typeMatchNumber;

  /// Title of the match list sheet
  ///
  /// In en, this message translates to:
  /// **'Matches for “{query}”'**
  String matchesForQuery(String query);

  /// Accessibility label for the search match counter
  ///
  /// In en, this message translates to:
  /// **'Match {current} of {total}'**
  String matchPosition(int current, int total);

  /// Number of search matches shown in the match list sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String matchCountLabel(int count);

  /// Line number of a search match in the match list
  ///
  /// In en, this message translates to:
  /// **'Line {line}'**
  String matchAtLine(int line);

  /// Announced when stepping past the last search match
  ///
  /// In en, this message translates to:
  /// **'Wrapped to first match'**
  String get wrappedToFirstMatch;

  /// Announced when stepping back past the first search match
  ///
  /// In en, this message translates to:
  /// **'Wrapped to last match'**
  String get wrappedToLastMatch;

  /// Placeholder for replace field
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get replaceWith;

  /// Button to replace current match
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replaceOne;

  /// Button to replace all matches
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get replaceAll;

  /// Message showing how many matches were replaced
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Replaced 1 match} other{Replaced {count} matches}}'**
  String replacedCount(int count);

  /// Option to enable case-sensitive search
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get matchCase;

  /// Option to match whole words only
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get wholeWord;

  /// Option to enable regex search
  ///
  /// In en, this message translates to:
  /// **'Use regex'**
  String get useRegex;

  /// Option to show replace field
  ///
  /// In en, this message translates to:
  /// **'Find & Replace'**
  String get findAndReplace;

  /// Search options button tooltip
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// Previous match button tooltip
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// Next match button tooltip
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Close button tooltip
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Date format settings dialog title
  ///
  /// In en, this message translates to:
  /// **'Date Format'**
  String get dateFormatSettings;

  /// Date format selection hint
  ///
  /// In en, this message translates to:
  /// **'Choose how dates will be displayed:'**
  String get selectDateFormat;

  /// Hint for date button long press
  ///
  /// In en, this message translates to:
  /// **'Long press to change format'**
  String get longPressToChangeFormat;

  /// Language settings menu item
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSettings;

  /// Language settings description
  ///
  /// In en, this message translates to:
  /// **'Change app display language'**
  String get languageSettingsDesc;

  /// Language selection dialog title
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// English language option
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// German language option
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// Romanian language option
  ///
  /// In en, this message translates to:
  /// **'Romanian'**
  String get romanian;

  /// System default language option
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// Theme settings menu item
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeSettings;

  /// Theme settings description
  ///
  /// In en, this message translates to:
  /// **'Light, dark or follow the phone'**
  String get themeSettingsDesc;

  /// Theme selection dialog title
  ///
  /// In en, this message translates to:
  /// **'Select Theme'**
  String get selectTheme;

  /// Light theme option
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// Dark theme option
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// System theme option
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// Title of the dialog that asks the user to restart the app
  ///
  /// In en, this message translates to:
  /// **'Restart required'**
  String get restartRequiredTitle;

  /// Search settings section title
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchSection;

  /// Setting for cursor behavior when navigating search matches
  ///
  /// In en, this message translates to:
  /// **'Search Navigation'**
  String get searchCursorBehavior;

  /// Description for search cursor behavior setting
  ///
  /// In en, this message translates to:
  /// **'Where to place the cursor when jumping to a search match'**
  String get searchCursorBehaviorDesc;

  /// Place cursor before the match
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get cursorAtStart;

  /// Place cursor after the match
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get cursorAtEnd;

  /// Select the entire match
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectMatch;

  /// Shown while search is in progress
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searching;

  /// Editor settings section title
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorSection;

  /// Setting for rendering markdown live inside the text editor
  ///
  /// In en, this message translates to:
  /// **'Live Markdown Rendering'**
  String get liveMarkdownRendering;

  /// Description for the live markdown rendering setting
  ///
  /// In en, this message translates to:
  /// **'Render headers, lists, checkboxes and text styles directly while editing'**
  String get liveMarkdownRenderingDesc;

  /// Setting for showing line numbers in editor
  ///
  /// In en, this message translates to:
  /// **'Line Numbers'**
  String get showLineNumbers;

  /// Description for show line numbers setting
  ///
  /// In en, this message translates to:
  /// **'Display line numbers on the left side of the editor'**
  String get showLineNumbersDesc;

  /// Setting for word wrapping in editor
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get wordWrap;

  /// Description for word wrap setting
  ///
  /// In en, this message translates to:
  /// **'Wrap long lines to fit within the editor width'**
  String get wordWrapDesc;

  /// Setting for highlighting the current line in editor
  ///
  /// In en, this message translates to:
  /// **'Highlight Current Line'**
  String get showCursorLine;

  /// Description for show cursor line setting
  ///
  /// In en, this message translates to:
  /// **'Highlight the line where the cursor is positioned'**
  String get showCursorLineDesc;

  /// Setting for automatically breaking long lines on paste
  ///
  /// In en, this message translates to:
  /// **'Auto-Break Long Lines'**
  String get autoBreakLongLines;

  /// Description for auto break long lines setting
  ///
  /// In en, this message translates to:
  /// **'Automatically break long lines when pasting text.'**
  String get autoBreakLongLinesDesc;

  /// Setting to show preview mode when keyboard is hidden
  ///
  /// In en, this message translates to:
  /// **'Preview When Keyboard Hidden'**
  String get previewWhenKeyboardHidden;

  /// Description for preview when keyboard hidden setting
  ///
  /// In en, this message translates to:
  /// **'Show rendered markdown preview when the keyboard is hidden. The editor appears when you tap to type.'**
  String get previewWhenKeyboardHiddenDesc;

  /// Setting to scroll cursor into view when keyboard appears
  ///
  /// In en, this message translates to:
  /// **'Scroll Cursor on Keyboard'**
  String get scrollCursorOnKeyboard;

  /// Description for scroll cursor on keyboard setting
  ///
  /// In en, this message translates to:
  /// **'Automatically scroll to keep the cursor visible when the keyboard appears.'**
  String get scrollCursorOnKeyboardDesc;

  /// Toast message when lines are formatted on paste
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 long line was formatted} other{{count} long lines were formatted}}'**
  String linesFormatted(int count);

  /// Deprecated features settings section title
  ///
  /// In en, this message translates to:
  /// **'Deprecated features'**
  String get deprecatedSection;

  /// Explanatory line shown at the top of the deprecated features section
  ///
  /// In en, this message translates to:
  /// **'Kept for people who already use them. Off by default, and they may be removed in a future version.'**
  String get deprecatedSectionIntro;

  /// Master switch that brings back the separate rendered preview
  ///
  /// In en, this message translates to:
  /// **'Preview Mode'**
  String get previewModeEnabled;

  /// Description for the preview mode master switch
  ///
  /// In en, this message translates to:
  /// **'Bring back the separate rendered preview and its eye button. The editor already renders markdown as you type.'**
  String get previewModeEnabledDesc;

  /// Comma-separated hidden search synonyms for the preview mode setting
  ///
  /// In en, this message translates to:
  /// **'preview, render, eye, deprecated, legacy'**
  String get previewModeKeywords;

  /// Setting for showing scrollbar in preview mode
  ///
  /// In en, this message translates to:
  /// **'Preview Scrollbar'**
  String get showPreviewScrollbar;

  /// Description for show preview scrollbar setting
  ///
  /// In en, this message translates to:
  /// **'Show an interactive scrollbar in preview mode (experimental)'**
  String get showPreviewScrollbarDesc;

  /// Setting for number of lines per render chunk in preview
  ///
  /// In en, this message translates to:
  /// **'Lines Per Chunk'**
  String get previewLinesPerChunk;

  /// Description for lines per chunk setting
  ///
  /// In en, this message translates to:
  /// **'{count} lines per chunk (higher = better performance, lower = more precise search scroll)'**
  String previewLinesPerChunkDesc(int count);

  /// Calendar settings: the first section's title, over the holiday set and the removed holidays
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get calendarSection;

  /// Title of the calendar settings page, and the settings hub row, the calendar overflow-menu row and the guide's quotes that open it
  ///
  /// In en, this message translates to:
  /// **'Calendar settings'**
  String get calendarSettings;

  /// Calendar settings: the holiday set row's description; the chosen set's name is the row's value, which opens a menu of the sets
  ///
  /// In en, this message translates to:
  /// **'Public holidays shown on the calendar; also used by Workdays repeats'**
  String get holidayProfileDesc;

  /// Calendar settings: the section that groups the rows opening Appearance, Categories, Fasting and Alert settings
  ///
  /// In en, this message translates to:
  /// **'More settings'**
  String get calendarSettingsPagesSection;

  /// Error snackbar when Calendar settings' Delete all events fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the events'**
  String get deleteAllEventsFailed;

  /// Drawer group label above the Settings, how-to and About rows
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get appGroupLabel;

  /// Label for the calendar max-day-bars slider
  ///
  /// In en, this message translates to:
  /// **'Maximum bars per day'**
  String get calendarMaxDayBars;

  /// Description for calendar max day bars slider
  ///
  /// In en, this message translates to:
  /// **'Show up to {count} bars per day. Extra categories collapse into a +N indicator.'**
  String calendarMaxDayBarsDesc(int count);

  /// Calendar appearance settings section title, and the title of the calendar appearance page
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get calendarAppearanceSection;

  /// Subtitle of the calendar settings row that opens the calendar appearance page
  ///
  /// In en, this message translates to:
  /// **'Preview and tune how the grid looks'**
  String get calendarAppearanceDesc;

  /// Calendar appearance page section title for the day-cell options
  ///
  /// In en, this message translates to:
  /// **'Day cell'**
  String get calendarAppearanceDayCellSection;

  /// Calendar appearance page section title for the day marker options
  ///
  /// In en, this message translates to:
  /// **'Markers'**
  String get calendarAppearanceMarkersSection;

  /// Calendar appearance page section title for the left-edge day rail options
  ///
  /// In en, this message translates to:
  /// **'Day rail'**
  String get calendarAppearanceRailSection;

  /// Calendar appearance page section title for the week options
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarAppearanceWeekSection;

  /// Calendar appearance page section title for the color options
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get calendarAppearanceColorSection;

  /// Calendar appearance page section title for the row label options
  ///
  /// In en, this message translates to:
  /// **'Row labels'**
  String get calendarAppearanceLabelsSection;

  /// Label for the today-highlight style selector
  ///
  /// In en, this message translates to:
  /// **'Today highlight'**
  String get calendarTodayStyleTitle;

  /// Today highlight style: soft tinted circle
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get todayStyleTonal;

  /// Today highlight style: outlined ring
  ///
  /// In en, this message translates to:
  /// **'Ring'**
  String get todayStyleRing;

  /// Today highlight style: solid circle
  ///
  /// In en, this message translates to:
  /// **'Filled'**
  String get todayStyleFilled;

  /// Label for the calendar accent color picker
  ///
  /// In en, this message translates to:
  /// **'Highlight color'**
  String get calendarAccentColor;

  /// Description for the calendar accent color picker
  ///
  /// In en, this message translates to:
  /// **'Colors today and the selected day'**
  String get calendarAccentColorDesc;

  /// Tooltip for the accent swatch that follows the app theme
  ///
  /// In en, this message translates to:
  /// **'Theme color'**
  String get calendarAccentThemeDefault;

  /// Label for the event marker style selector
  ///
  /// In en, this message translates to:
  /// **'Event markers'**
  String get calendarMarkerStyleTitle;

  /// Event marker style: stacked bars
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get markerStyleBars;

  /// Event marker style: row of dots
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get markerStyleDots;

  /// Label for the day-rail style selector in calendar settings
  ///
  /// In en, this message translates to:
  /// **'Day rail'**
  String get calendarDayRailStyleTitle;

  /// Description for the day-rail style selector
  ///
  /// In en, this message translates to:
  /// **'A vertical rail on the left of each day, one mark per tracked commitment — so a day carrying three of them stops reading as one. Rail events leave the bottom markers.'**
  String get calendarDayRailStyleDesc;

  /// Day rail style: no rail
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get dayRailStyleNone;

  /// Day rail style: stacked vertical segments
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get dayRailStyleLine;

  /// Day rail style: stacked circles
  ///
  /// In en, this message translates to:
  /// **'Dots'**
  String get dayRailStyleDot;

  /// Label for the day-rail capacity slider
  ///
  /// In en, this message translates to:
  /// **'Maximum rail marks per day'**
  String get calendarMaxDayRailMarks;

  /// Description for the day-rail capacity slider
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show one rail mark per day. The rest collapse into one neutral mark.} other{Show up to {count} rail marks per day. The rest collapse into one neutral mark.}}'**
  String calendarMaxDayRailMarksDesc(int count);

  /// Label for the day-rail fasting band position picker
  ///
  /// In en, this message translates to:
  /// **'Fasting half of the rail'**
  String get calendarDayRailBasePositionTitle;

  /// Description for the day-rail fasting band position picker
  ///
  /// In en, this message translates to:
  /// **'On a day that is both, the rail splits in two equal halves — your marks and the fast. This picks which end the fast takes.'**
  String get calendarDayRailBasePositionDesc;

  /// Day-rail fasting band sits above the marks
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get dayRailBasePositionTop;

  /// Day-rail fasting band sits below the marks
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get dayRailBasePositionBottom;

  /// Switch title for weekend day-number tinting
  ///
  /// In en, this message translates to:
  /// **'Tint weekends'**
  String get calendarHighlightWeekends;

  /// Switch subtitle for weekend day-number tinting
  ///
  /// In en, this message translates to:
  /// **'Show Saturday and Sunday in a distinct color'**
  String get calendarHighlightWeekendsDesc;

  /// Switch title for ISO week numbers
  ///
  /// In en, this message translates to:
  /// **'Week numbers'**
  String get calendarShowWeekNumbers;

  /// Switch subtitle for ISO week numbers
  ///
  /// In en, this message translates to:
  /// **'Show week numbers at the left edge'**
  String get calendarShowWeekNumbersDesc;

  /// Calendar settings section holding the filtering options
  ///
  /// In en, this message translates to:
  /// **'Filtering'**
  String get calendarFilteringSection;

  /// Switch title for the active-filter chips row above the calendar grid
  ///
  /// In en, this message translates to:
  /// **'Filter chips'**
  String get calendarShowFilterChips;

  /// Switch subtitle for the active-filter chips row
  ///
  /// In en, this message translates to:
  /// **'Show a row of active filters above the grid'**
  String get calendarShowFilterChipsDesc;

  /// Label for a substitute day off given because a holiday fell on a weekend (UK bank holidays, US federal observance)
  ///
  /// In en, this message translates to:
  /// **'{name} (observed)'**
  String publicHolidayObserved(String name);

  /// Switch title: event rows mention the repeat pattern (Daily, Weekly, ...)
  ///
  /// In en, this message translates to:
  /// **'Repeat pattern in rows'**
  String get calendarShowRecurrenceLabels;

  /// Switch subtitle for the repeat-pattern-in-rows option
  ///
  /// In en, this message translates to:
  /// **'Mention the repeat pattern (Daily, Weekly…) in event rows'**
  String get calendarShowRecurrenceLabelsDesc;

  /// Setting title for how missed days of a presence-tracked event are drawn
  ///
  /// In en, this message translates to:
  /// **'Missed days'**
  String get calendarMissedDisplayTitle;

  /// Setting subtitle for the missed-days display option
  ///
  /// In en, this message translates to:
  /// **'How missed days of a tracked event appear in the calendar'**
  String get calendarMissedDisplayDesc;

  /// Missed-days display option: still shown, dimmed
  ///
  /// In en, this message translates to:
  /// **'Faded'**
  String get calendarMissedDisplayFaded;

  /// Missed-days display option: not drawn at all
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get calendarMissedDisplayHidden;

  /// Action that cancels a single occurrence of a recurring event
  ///
  /// In en, this message translates to:
  /// **'Skip this day'**
  String get eventSkipOccurrence;

  /// Confirmation after cancelling a single occurrence
  ///
  /// In en, this message translates to:
  /// **'Occurrence skipped'**
  String get eventOccurrenceSkipped;

  /// Editor row listing the occurrences the user cancelled
  ///
  /// In en, this message translates to:
  /// **'Skipped days'**
  String get eventSkippedDays;

  /// How many occurrences of this event are cancelled
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 day skipped} few{{count} days skipped} other{{count} days skipped}}'**
  String eventSkippedDaysCount(int count);

  /// Subtitle of the skipped-days row when nothing is cancelled
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get eventNoSkippedDays;

  /// Alert timing for a timed event with no lead time
  ///
  /// In en, this message translates to:
  /// **'At start'**
  String get eventAlertAtStart;

  /// Alert timing for a timed event, minutes of lead time
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 min before} other{{count} min before}}'**
  String eventAlertMinutesBefore(int count);

  /// Alert timing for a timed event, whole hours of lead time
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 h before} other{{count} h before}}'**
  String eventAlertHoursBefore(int count);

  /// Alert timing for a timed event, whole days of lead time
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 day before} other{{count} days before}}'**
  String eventAlertDaysBefore(int count);

  /// Alert timing for an all-day event firing on the day itself
  ///
  /// In en, this message translates to:
  /// **'On the day, {time}'**
  String eventAlertAllDayOnDay(String time);

  /// Alert timing for an all-day event firing the previous day
  ///
  /// In en, this message translates to:
  /// **'The day before, {time}'**
  String eventAlertAllDayDayBefore(String time);

  /// Alert timing for an all-day event firing several days ahead
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 day before, {time}} other{{count} days before, {time}}}'**
  String eventAlertAllDayDaysBefore(int count, String time);

  /// Title of the event templates management page
  ///
  /// In en, this message translates to:
  /// **'Event templates'**
  String get eventTemplates;

  /// Settings row subtitle for the event templates page
  ///
  /// In en, this message translates to:
  /// **'Reusable presets — category, schedule, color and details prefilled'**
  String get eventTemplatesDesc;

  /// Button that opens the template editor for a new template
  ///
  /// In en, this message translates to:
  /// **'New template'**
  String get createTemplate;

  /// Title of the template editor when editing
  ///
  /// In en, this message translates to:
  /// **'Edit template'**
  String get editTemplate;

  /// Label of the template name field; doubles as the created event's title
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get templateName;

  /// Button in the event editor that stores the current form as a reusable template
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get saveAsTemplate;

  /// Confirmation after storing a template
  ///
  /// In en, this message translates to:
  /// **'Template saved'**
  String get templateSaved;

  /// Delete action for a template
  ///
  /// In en, this message translates to:
  /// **'Delete template'**
  String get deleteTemplate;

  /// Confirmation dialog body when deleting a template
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Events already created from it are not affected.'**
  String deleteTemplateConfirm(String name);

  /// Confirmation after deleting a template
  ///
  /// In en, this message translates to:
  /// **'Template deleted'**
  String get templateDeleted;

  /// Title of the sheet that picks a template to create an event from
  ///
  /// In en, this message translates to:
  /// **'Add from template'**
  String get addFromTemplate;

  /// Row in the template picker that opens the normal empty event editor
  ///
  /// In en, this message translates to:
  /// **'Blank event'**
  String get templateBlankEvent;

  /// Row in the template picker that opens the quick-alarm sheet
  ///
  /// In en, this message translates to:
  /// **'Alarm…'**
  String get quickAlarmRow;

  /// Title of the quick-alarm sheet
  ///
  /// In en, this message translates to:
  /// **'Quick alarm'**
  String get quickAlarmTitle;

  /// Default name of a quick alarm's event; also used when the name field is left empty
  ///
  /// In en, this message translates to:
  /// **'Alarm'**
  String get quickAlarmName;

  /// Tooltip on the quick-alarm sheet's big time, which opens the time picker
  ///
  /// In en, this message translates to:
  /// **'Change time'**
  String get quickAlarmPickTime;

  /// Preset chip on the quick-alarm sheet: twenty minutes from now
  ///
  /// In en, this message translates to:
  /// **'In 20 min'**
  String get quickAlarmIn20Min;

  /// Preset chip on the quick-alarm sheet: one hour from now
  ///
  /// In en, this message translates to:
  /// **'In 1 hour'**
  String get quickAlarmIn1Hour;

  /// Preset chip on the quick-alarm sheet: today at the given evening time
  ///
  /// In en, this message translates to:
  /// **'Tonight {time}'**
  String quickAlarmTonight(String time);

  /// Snackbar after a quick alarm was created for today, with Undo
  ///
  /// In en, this message translates to:
  /// **'{title} set for {time}'**
  String quickAlarmSet(String title, String time);

  /// Snackbar after a quick alarm was created for another day, naming it
  ///
  /// In en, this message translates to:
  /// **'{title} set for {time}, {day}'**
  String quickAlarmSetOn(String title, String time, String day);

  /// Snackbar after a template created an event on the long-pressed day
  ///
  /// In en, this message translates to:
  /// **'Added: {title}'**
  String eventCreatedFromTemplate(String title);

  /// Snackbar when the template's rule does not fire on the long-pressed day, naming the first day it does
  ///
  /// In en, this message translates to:
  /// **'Added: {title} — first on {date}'**
  String eventCreatedFromTemplateOn(String title, String date);

  /// Empty state on the templates page
  ///
  /// In en, this message translates to:
  /// **'No templates yet'**
  String get noEventTemplates;

  /// Empty state body on the templates page
  ///
  /// In en, this message translates to:
  /// **'Save an event as a template to reuse its details later.'**
  String get noEventTemplatesDesc;

  /// Attendance ratio for a presence-tracked event over the trailing window
  ///
  /// In en, this message translates to:
  /// **'{attended}/{total} attended · last {days} days'**
  String eventAdherenceSummary(int attended, int total, int days);

  /// Current and longest attendance streak for a presence-tracked event
  ///
  /// In en, this message translates to:
  /// **'Streak {count} · best {best}'**
  String eventAdherenceStreak(int count, int best);

  /// Setting title for washing day cells with their top event's color
  ///
  /// In en, this message translates to:
  /// **'Tint days by event color'**
  String get calendarEventTintTitle;

  /// Setting subtitle explaining that the tint strength encodes event priority
  ///
  /// In en, this message translates to:
  /// **'Wash each day with its top event\'s color. Stronger color means higher priority.'**
  String get calendarEventTintDesc;

  /// Setting title for which tint wins when a day is both an event day and a fasting day
  ///
  /// In en, this message translates to:
  /// **'On fasting days'**
  String get calendarTintConflictTitle;

  /// Setting subtitle for the tint conflict option
  ///
  /// In en, this message translates to:
  /// **'Which color wins when a day has both an event and a fast'**
  String get calendarTintConflictDesc;

  /// Tint conflict option: the event color wins the cell
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get calendarTintConflictEvent;

  /// Tint conflict option: the fasting color wins the cell
  ///
  /// In en, this message translates to:
  /// **'Fasting'**
  String get calendarTintConflictFasting;

  /// Tint conflict option: winner fills the cell, runner-up shows as an edge stripe
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get calendarTintConflictBoth;

  /// Setting title for how the event color fills a day cell, chosen per theme
  ///
  /// In en, this message translates to:
  /// **'Day cell style'**
  String get calendarCellStyleTitle;

  /// Setting subtitle explaining that the day cell style is stored separately for light and dark
  ///
  /// In en, this message translates to:
  /// **'How an event\'s color fills the day cell. Each theme keeps its own choice.'**
  String get calendarCellStyleDesc;

  /// Label above the day cell style buttons that apply to the light theme
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get calendarCellStyleLight;

  /// Label above the day cell style buttons that apply to the dark theme
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get calendarCellStyleDark;

  /// Day cell style option: the color fills the cell evenly
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get calendarCellStyleSolid;

  /// Day cell style option: the color fades in from the top of the cell
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get calendarCellStyleFade;

  /// Day cell style option: a faint fill under a colored border
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get calendarCellStyleOutline;

  /// Label for the first-day-of-week row, whose value opens a menu of the days
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get calendarWeekStartTitle;

  /// Entry count badge in the day summary header
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 entry} other {{count} entries}}'**
  String daySummaryEntryCount(int count);

  /// Section title for date offset settings
  ///
  /// In en, this message translates to:
  /// **'Date Offset'**
  String get dateOffset;

  /// Description for date offset feature
  ///
  /// In en, this message translates to:
  /// **'Shift the date forward or backward from today'**
  String get dateOffsetDescription;

  /// Label for days input
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get days;

  /// Label for months input
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get monthsLabel;

  /// Label for years input
  ///
  /// In en, this message translates to:
  /// **'Years'**
  String get yearsLabel;

  /// Section title for repeat settings
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeatSettings;

  /// Description for repeat feature
  ///
  /// In en, this message translates to:
  /// **'Insert this shortcut multiple times'**
  String get repeatDescription;

  /// Label for repeat count
  ///
  /// In en, this message translates to:
  /// **'Repeat count'**
  String get repeatCount;

  /// Label for separator selection
  ///
  /// In en, this message translates to:
  /// **'Separator'**
  String get separator;

  /// New line separator option
  ///
  /// In en, this message translates to:
  /// **'New line'**
  String get newLine;

  /// No separator option
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noSeparator;

  /// Space separator option
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get space;

  /// Non-breaking space separator option
  ///
  /// In en, this message translates to:
  /// **'Non-breaking'**
  String get nbspSpace;

  /// Blank line separator option (double newline)
  ///
  /// In en, this message translates to:
  /// **'Blank line'**
  String get blankLine;

  /// Comma separator option
  ///
  /// In en, this message translates to:
  /// **'Comma'**
  String get comma;

  /// Pipe separator option
  ///
  /// In en, this message translates to:
  /// **'Pipe'**
  String get pipe;

  /// Toggle to increment date for each repetition
  ///
  /// In en, this message translates to:
  /// **'Increment date on repeat'**
  String get incrementDateOnRepeat;

  /// Label for date increment values
  ///
  /// In en, this message translates to:
  /// **'Increment by for each repetition:'**
  String get incrementByEachRepeat;

  /// Toggle label for advanced shortcut options
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get advancedOptions;

  /// Description for advanced options toggle
  ///
  /// In en, this message translates to:
  /// **'Date offset, repeat, and more'**
  String get advancedOptionsDescription;

  /// Label for wrapper text around all repeated items
  ///
  /// In en, this message translates to:
  /// **'Wrapper text'**
  String get repeatWrapperText;

  /// Description for wrapper text fields
  ///
  /// In en, this message translates to:
  /// **'Text inserted before/after all repeated items'**
  String get repeatWrapperTextDesc;

  /// Label for text before all repeated items
  ///
  /// In en, this message translates to:
  /// **'Before all'**
  String get beforeAllRepeats;

  /// Hint for before all repeats field
  ///
  /// In en, this message translates to:
  /// **'e.g., ## Week 1\\n'**
  String get beforeAllRepeatsHint;

  /// Label for text after all repeated items
  ///
  /// In en, this message translates to:
  /// **'After all'**
  String get afterAllRepeats;

  /// Hint for after all repeats field
  ///
  /// In en, this message translates to:
  /// **'e.g., \\n---'**
  String get afterAllRepeatsHint;

  /// Title for developer options page
  ///
  /// In en, this message translates to:
  /// **'Developer options'**
  String get developerOptions;

  /// Subtitle of the settings hub's Developer options row
  ///
  /// In en, this message translates to:
  /// **'Debug tools and diagnostics'**
  String get developerOptionsDesc;

  /// Warning message on developer options page
  ///
  /// In en, this message translates to:
  /// **'These options are for debugging only. Enabling them may affect app performance.'**
  String get developerOptionsWarning;

  /// Toast message when dev options are reset
  ///
  /// In en, this message translates to:
  /// **'Developer options reset to defaults'**
  String get developerOptionsReset;

  /// Body of the confirmation before Developer options' Reset to defaults, which also clears the unlock
  ///
  /// In en, this message translates to:
  /// **'Reset every developer option? This also locks developer mode.'**
  String get developerOptionsResetConfirm;

  /// Toast message when developer mode is unlocked by swiping gym icon
  ///
  /// In en, this message translates to:
  /// **'Developer mode unlocked!'**
  String get developerModeUnlocked;

  /// Button to hide developer options from menu
  ///
  /// In en, this message translates to:
  /// **'Lock Developer Mode'**
  String get lockDeveloperMode;

  /// Toast message when developer mode is locked
  ///
  /// In en, this message translates to:
  /// **'Developer mode locked'**
  String get developerModeLocked;

  /// Section title for visualization debug options
  ///
  /// In en, this message translates to:
  /// **'Visualization / Debug'**
  String get visualizationDebug;

  /// Option to color different markdown blocks
  ///
  /// In en, this message translates to:
  /// **'Color Markdown Blocks'**
  String get colorMarkdownBlocks;

  /// Description for color markdown blocks option
  ///
  /// In en, this message translates to:
  /// **'Show different colors for headers, code, lists, etc.'**
  String get colorMarkdownBlocksDesc;

  /// Option to show block boundaries
  ///
  /// In en, this message translates to:
  /// **'Show Block Boundaries'**
  String get showBlockBoundaries;

  /// Description for show block boundaries option
  ///
  /// In en, this message translates to:
  /// **'Draw borders around each parsed element'**
  String get showBlockBoundariesDesc;

  /// Option to show whitespace characters
  ///
  /// In en, this message translates to:
  /// **'Show Whitespace'**
  String get showWhitespace;

  /// Description for show whitespace option
  ///
  /// In en, this message translates to:
  /// **'Visualize spaces, tabs, and newlines'**
  String get showWhitespaceDesc;

  /// Developer option: caption the calendar's add button with the scroll notification its collapse rule last saw and what it decided
  ///
  /// In en, this message translates to:
  /// **'Trace the calendar add button'**
  String get showAddButtonTrace;

  /// Description for the add button trace developer option
  ///
  /// In en, this message translates to:
  /// **'Show the last scroll event the add button reacted to and whether it extended or collapsed'**
  String get showAddButtonTraceDesc;

  /// Section title for performance monitoring options
  ///
  /// In en, this message translates to:
  /// **'Performance Monitoring'**
  String get performanceMonitoring;

  /// Option to show render time
  ///
  /// In en, this message translates to:
  /// **'Show Render Time'**
  String get showRenderTime;

  /// Description for show render time option
  ///
  /// In en, this message translates to:
  /// **'Display how long preview takes to render'**
  String get showRenderTimeDesc;

  /// Option to show FPS counter
  ///
  /// In en, this message translates to:
  /// **'Show FPS Counter'**
  String get showFpsCounter;

  /// Description for show FPS counter option
  ///
  /// In en, this message translates to:
  /// **'Monitor scroll and animation performance'**
  String get showFpsCounterDesc;

  /// Option to show chunk indicators
  ///
  /// In en, this message translates to:
  /// **'Show Chunk Indicators'**
  String get showChunkIndicators;

  /// Description for show chunk indicators option
  ///
  /// In en, this message translates to:
  /// **'Highlight which chunks are loaded in preview'**
  String get showChunkIndicatorsDesc;

  /// Option to show repaint rainbow
  ///
  /// In en, this message translates to:
  /// **'Show Repaint Rainbow'**
  String get showRepaintRainbow;

  /// Description for show repaint rainbow option
  ///
  /// In en, this message translates to:
  /// **'Color widgets when they repaint (Flutter debug)'**
  String get showRepaintRainbowDesc;

  /// Section title for editor debug options
  ///
  /// In en, this message translates to:
  /// **'Editor Debug'**
  String get editorDebug;

  /// Option to show cursor position info
  ///
  /// In en, this message translates to:
  /// **'Show Cursor Info'**
  String get showCursorInfo;

  /// Description for show cursor info option
  ///
  /// In en, this message translates to:
  /// **'Display line, column, and character offset'**
  String get showCursorInfoDesc;

  /// Option to show selection details
  ///
  /// In en, this message translates to:
  /// **'Show Selection Details'**
  String get showSelectionDetails;

  /// Description for show selection details option
  ///
  /// In en, this message translates to:
  /// **'Display start, end positions and length'**
  String get showSelectionDetailsDesc;

  /// Option to log parser events
  ///
  /// In en, this message translates to:
  /// **'Log Parser Events'**
  String get logParserEvents;

  /// Description for log parser events option
  ///
  /// In en, this message translates to:
  /// **'Output parsing info to debug console'**
  String get logParserEventsDesc;

  /// Section title for storage data options
  ///
  /// In en, this message translates to:
  /// **'Storage / Data'**
  String get storageData;

  /// Option to show note size
  ///
  /// In en, this message translates to:
  /// **'Show Note Size'**
  String get showNoteSize;

  /// Description for show note size option
  ///
  /// In en, this message translates to:
  /// **'Display content size in bytes'**
  String get showNoteSizeDesc;

  /// Option to show database stats
  ///
  /// In en, this message translates to:
  /// **'Show Database Stats'**
  String get showDatabaseStats;

  /// Description for show database stats option
  ///
  /// In en, this message translates to:
  /// **'Query count and cache information'**
  String get showDatabaseStatsDesc;

  /// Indicator label when note is fully saved
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saveStatusSaved;

  /// Indicator label when note has unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get saveStatusUnsaved;

  /// Indicator label when note is being saved
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saveStatusSaving;

  /// Indicator label when the last save attempt failed
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get saveStatusError;

  /// Section header for toolbar ratio adjuster
  ///
  /// In en, this message translates to:
  /// **'Toolbar Layout'**
  String get toolbarLayout;

  /// Label for the shortcuts section of the toolbar
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcuts;

  /// Label for the utilities section of the toolbar
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get utilities;

  /// Toggle label for split toolbar mode
  ///
  /// In en, this message translates to:
  /// **'Split toolbar'**
  String get splitToolbar;

  /// Toggle label: keep Undo and Redo outside the scrolling utility strip
  ///
  /// In en, this message translates to:
  /// **'Pin undo and redo'**
  String get pinUndoRedo;

  /// Section header for utility button customization
  ///
  /// In en, this message translates to:
  /// **'Utility Buttons'**
  String get utilityButtons;

  /// Hint text for utility button customization section
  ///
  /// In en, this message translates to:
  /// **'Toggle visibility and drag to reorder'**
  String get utilityButtonsHint;

  /// Title for markdown bar profiles section
  ///
  /// In en, this message translates to:
  /// **'Markdown Bars'**
  String get markdownBars;

  /// Label for the currently active markdown bar
  ///
  /// In en, this message translates to:
  /// **'Active Bar'**
  String get activeBar;

  /// Label for the bar currently being edited in settings
  ///
  /// In en, this message translates to:
  /// **'Editing Bar'**
  String get editingBar;

  /// Button text to create a new markdown bar
  ///
  /// In en, this message translates to:
  /// **'Add Bar'**
  String get addBar;

  /// Button text to delete a markdown bar
  ///
  /// In en, this message translates to:
  /// **'Delete Bar'**
  String get deleteBar;

  /// Confirmation message when deleting a markdown bar
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this bar? Notes using it will fall back to the global active bar.'**
  String get deleteBarConfirm;

  /// Button text to rename a markdown bar
  ///
  /// In en, this message translates to:
  /// **'Rename Bar'**
  String get renameBar;

  /// Button text to duplicate a markdown bar
  ///
  /// In en, this message translates to:
  /// **'Duplicate Bar'**
  String get duplicateBar;

  /// Label for the bar name text field
  ///
  /// In en, this message translates to:
  /// **'Bar Name'**
  String get barName;

  /// Name of the default markdown bar
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultBar;

  /// Tooltip for the bar switcher button in toolbar
  ///
  /// In en, this message translates to:
  /// **'Switch Bar'**
  String get switchBar;

  /// Hint text for searching markdown bars
  ///
  /// In en, this message translates to:
  /// **'Search bars...'**
  String get searchBars;

  /// Shown when bar search yields no results
  ///
  /// In en, this message translates to:
  /// **'No matching bars'**
  String get noMatchingBars;

  /// Title for the per-note bar assignment page
  ///
  /// In en, this message translates to:
  /// **'Per-Note Bar Assignment'**
  String get perNoteBarAssignment;

  /// Description for per-note bar assignment
  ///
  /// In en, this message translates to:
  /// **'Assign a specific bar to individual notes. Notes without an override use the global active bar.'**
  String get perNoteBarHint;

  /// Option to use the global active bar for a note
  ///
  /// In en, this message translates to:
  /// **'Use Global Bar'**
  String get useGlobalBar;

  /// Message when user tries to delete the default bar
  ///
  /// In en, this message translates to:
  /// **'Cannot delete the default bar'**
  String get cannotDeleteDefault;

  /// Message when user tries to rename the default bar
  ///
  /// In en, this message translates to:
  /// **'Cannot rename the default bar'**
  String get cannotRenameDefault;

  /// Title for the bar switcher bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Select Markdown Bar'**
  String get barSwitcherTitle;

  /// Label indicating a per-note bar override is set
  ///
  /// In en, this message translates to:
  /// **'Note Override'**
  String get noteBarOverride;

  /// Button to remove per-note bar override
  ///
  /// In en, this message translates to:
  /// **'Clear Override'**
  String get clearOverride;

  /// Link to open the per-note bar assignment page
  ///
  /// In en, this message translates to:
  /// **'Manage Bar Profiles'**
  String get manageBarProfiles;

  /// Subtitle for locked utility buttons that are always shown
  ///
  /// In en, this message translates to:
  /// **'Always visible'**
  String get alwaysVisible;

  /// Status label when a utility button is visible
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get visible;

  /// Tooltip for the scroll-to-top utility button
  ///
  /// In en, this message translates to:
  /// **'Go to Top'**
  String get goToTop;

  /// Tooltip for the scroll-to-bottom utility button
  ///
  /// In en, this message translates to:
  /// **'Go to Bottom'**
  String get goToBottom;

  /// Status label when a utility button is hidden
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hidden;

  /// Insert type option for counter shortcuts
  ///
  /// In en, this message translates to:
  /// **'Insert Counter Value'**
  String get insertCounter;

  /// Section header for the counter bindings list inside a shortcut
  ///
  /// In en, this message translates to:
  /// **'Counter Bindings'**
  String get counterBindingsTitle;

  /// Helper text explaining the counter bindings + tokens system
  ///
  /// In en, this message translates to:
  /// **'Bind up to two counters to this shortcut and use the c1 and c2 tokens (in curly braces) inside the before/after text to insert their values. Each token expansion mutates the counter once per repeat.'**
  String get counterBindingsDescription;

  /// Button label for adding the first counter binding
  ///
  /// In en, this message translates to:
  /// **'Add counter binding'**
  String get addCounterBinding;

  /// Button label for adding a second counter binding
  ///
  /// In en, this message translates to:
  /// **'Add second counter binding'**
  String get addSecondCounterBinding;

  /// Tooltip for removing a counter binding
  ///
  /// In en, this message translates to:
  /// **'Remove counter binding'**
  String get removeCounterBinding;

  /// Hint above the {c1}/{c2} insert chips
  ///
  /// In en, this message translates to:
  /// **'Tap a token to insert it where the cursor is.'**
  String get counterTokensHint;

  /// Label for the increment/decrement segmented control
  ///
  /// In en, this message translates to:
  /// **'Operation'**
  String get counterOperation;

  /// Counter operation: increment
  ///
  /// In en, this message translates to:
  /// **'Increment'**
  String get counterOpIncrement;

  /// Counter operation: read current value without changing it
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get counterOpKeep;

  /// Counter operation: decrement
  ///
  /// In en, this message translates to:
  /// **'Decrement'**
  String get counterOpDecrement;

  /// Label for counter selection dropdown
  ///
  /// In en, this message translates to:
  /// **'Select Counter'**
  String get selectCounter;

  /// Empty state when no counters exist
  ///
  /// In en, this message translates to:
  /// **'No counters created yet'**
  String get noCountersYet;

  /// Info banner shown in the counter insert type section when no counters exist
  ///
  /// In en, this message translates to:
  /// **'No counters created yet. Use the \"Add counter\" button below to create one.'**
  String get noCountersYetHint;

  /// Button to create a new counter
  ///
  /// In en, this message translates to:
  /// **'Add Counter'**
  String get addCounter;

  /// Label for counter name input
  ///
  /// In en, this message translates to:
  /// **'Counter Name'**
  String get counterName;

  /// Label for counter start value
  ///
  /// In en, this message translates to:
  /// **'Start Value'**
  String get startValue;

  /// Label for counter increment step
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get step;

  /// Label for counter scope selection
  ///
  /// In en, this message translates to:
  /// **'Counter Scope'**
  String get counterScope;

  /// Counter scope: shared across all notes
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get global;

  /// Counter scope: independent per note
  ///
  /// In en, this message translates to:
  /// **'Per Note'**
  String get perNote;

  /// Title for edit counter dialog
  ///
  /// In en, this message translates to:
  /// **'Edit Counter'**
  String get editCounter;

  /// Title for delete counter confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete Counter'**
  String get deleteCounter;

  /// Confirmation message for counter deletion
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this counter? This cannot be undone.'**
  String get deleteCounterConfirm;

  /// Button to reset counter value
  ///
  /// In en, this message translates to:
  /// **'Reset Counter'**
  String get resetCounter;

  /// Confirmation message for counter reset
  ///
  /// In en, this message translates to:
  /// **'Reset this counter to its start value?'**
  String get resetCounterConfirm;

  /// Section title for counters
  ///
  /// In en, this message translates to:
  /// **'Counters'**
  String get counters;

  /// Drawer menu title for the counter management page
  ///
  /// In en, this message translates to:
  /// **'Counters'**
  String get counterSettings;

  /// Shows the current value of a counter
  ///
  /// In en, this message translates to:
  /// **'Current: {value}'**
  String counterCurrentValue(int value);

  /// Shows the step increment value
  ///
  /// In en, this message translates to:
  /// **'Step: {step}'**
  String counterStepLabel(int step);

  /// Empty state message on the counter management page
  ///
  /// In en, this message translates to:
  /// **'No counters yet. Tap + to create one.'**
  String get counterEmptyState;

  /// Snackbar message after resetting a counter
  ///
  /// In en, this message translates to:
  /// **'Counter reset to start value'**
  String get counterResetSuccess;

  /// Snackbar message after deleting a counter
  ///
  /// In en, this message translates to:
  /// **'Counter deleted'**
  String get counterDeleteSuccess;

  /// Dialog title / tooltip for manually setting a counter's current value
  ///
  /// In en, this message translates to:
  /// **'Set Value'**
  String get counterSetValue;

  /// Shown on per-note counter cards in the management page instead of a stepper
  ///
  /// In en, this message translates to:
  /// **'Value varies per note'**
  String get counterValuePerNote;

  /// Description for global counter scope
  ///
  /// In en, this message translates to:
  /// **'Shared across all notes'**
  String get counterScopeGlobalDesc;

  /// Description for per-note counter scope
  ///
  /// In en, this message translates to:
  /// **'Independent value per note'**
  String get counterScopePerNoteDesc;

  /// Title for the counter picker dialog in the toolbar
  ///
  /// In en, this message translates to:
  /// **'Pick Counter'**
  String get pickCounter;

  /// Hint text for the search field in the counter picker dialog
  ///
  /// In en, this message translates to:
  /// **'Search counters…'**
  String get searchCounters;

  /// Empty state when counter search has no results
  ///
  /// In en, this message translates to:
  /// **'No counters match your search'**
  String get noCountersMatchSearch;

  /// Tooltip for the counter utility button in the toolbar
  ///
  /// In en, this message translates to:
  /// **'Insert counter value'**
  String get counterInsertTooltip;

  /// Button to create a new counter from the picker dialog
  ///
  /// In en, this message translates to:
  /// **'Create new counter'**
  String get createCounterInline;

  /// Button to navigate to the counter management / settings page
  ///
  /// In en, this message translates to:
  /// **'Manage counters'**
  String get manageCounters;

  /// Page indicator in the counter picker dialog (e.g. 1 / 3)
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String counterPickerPage(int current, int total);

  /// Title for the note picker dialog
  ///
  /// In en, this message translates to:
  /// **'Select a note'**
  String get selectNote;

  /// Hint text for the search field in the note picker dialog
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get searchNotes;

  /// Empty state message when there are no notes to pick from
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noNotesAvailable;

  /// Message when the search query doesn't match any notes
  ///
  /// In en, this message translates to:
  /// **'No notes match your search'**
  String get noNotesMatchSearch;

  /// Prompt shown on per-note counter cards to open the per-note values page
  ///
  /// In en, this message translates to:
  /// **'Tap to manage note values'**
  String get counterSelectNoteToView;

  /// Error message shown when counter loading fails
  ///
  /// In en, this message translates to:
  /// **'Failed to load counters'**
  String get counterLoadError;

  /// Shown on the per-note values page when its counter is gone, for example deleted on another device
  ///
  /// In en, this message translates to:
  /// **'This counter no longer exists'**
  String get counterNotFound;

  /// Button label to retry loading counters
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get counterRetry;

  /// Title for the per-note counter values page
  ///
  /// In en, this message translates to:
  /// **'Values per Note'**
  String get counterPerNoteValues;

  /// Empty state when no notes exist for per-note counter
  ///
  /// In en, this message translates to:
  /// **'No notes have values for this counter yet'**
  String get counterPerNoteEmpty;

  /// Button to reset counter value for all notes
  ///
  /// In en, this message translates to:
  /// **'Reset All Notes'**
  String get counterResetAllNotes;

  /// Confirmation message for resetting all per-note values
  ///
  /// In en, this message translates to:
  /// **'Reset this counter to its start value for all notes?'**
  String get counterResetAllConfirm;

  /// Snackbar after resetting all per-note values
  ///
  /// In en, this message translates to:
  /// **'All note values reset'**
  String get counterResetAllSuccess;

  /// Menu item to open per-note values page
  ///
  /// In en, this message translates to:
  /// **'Manage note values'**
  String get counterManageNoteValues;

  /// Menu action to pin a counter
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinCounter;

  /// Menu action to unpin a counter
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinCounter;

  /// Button to add a note to the per-note counter
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get addNote;

  /// Menu action to remove a note from per-note counter
  ///
  /// In en, this message translates to:
  /// **'Remove Note'**
  String get removeNote;

  /// Confirmation message for removing a note from per-note counter
  ///
  /// In en, this message translates to:
  /// **'Remove this note from the counter? The value will be lost.'**
  String get removeNoteConfirm;

  /// Snackbar when trying to add a duplicate note
  ///
  /// In en, this message translates to:
  /// **'This note is already added'**
  String get noteAlreadyAdded;

  /// Menu action to move a note to another folder
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// Title for the folder picker dialog when moving a note
  ///
  /// In en, this message translates to:
  /// **'Select Destination'**
  String get selectDestinationFolder;

  /// Title for the folder picker dialog (action-oriented)
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get moveToTitle;

  /// Label above the path/address bar indicating the user's current browse location
  ///
  /// In en, this message translates to:
  /// **'Currently in'**
  String get currentlyIn;

  /// Section overline above the folder list naming the parent folder
  ///
  /// In en, this message translates to:
  /// **'Subfolders of {name}'**
  String subfoldersOf(String name);

  /// Confirm-action label naming the destination folder
  ///
  /// In en, this message translates to:
  /// **'Move to {name}'**
  String moveToDestination(String name);

  /// Label for the root level in the folder picker
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get rootFolder;

  /// Snackbar after successfully moving a note
  ///
  /// In en, this message translates to:
  /// **'Note moved successfully'**
  String get noteMoved;

  /// Snackbar when moving a note fails
  ///
  /// In en, this message translates to:
  /// **'Failed to move note'**
  String get noteMoveFailed;

  /// Snackbar when trying to move a note to its current folder
  ///
  /// In en, this message translates to:
  /// **'Note is already in this folder'**
  String get alreadyInThisFolder;

  /// Empty state in the folder picker when there are no folders
  ///
  /// In en, this message translates to:
  /// **'No folders available'**
  String get noFoldersAvailable;

  /// Empty state in the folder picker when the current folder has no subfolders
  ///
  /// In en, this message translates to:
  /// **'No subfolders here'**
  String get noSubfolders;

  /// Tooltip for the back/up navigation button in the folder picker
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Tooltip for the drill-into-folder button in the folder picker
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// Tooltip for the trailing button on a folder row that picks it as the move destination
  ///
  /// In en, this message translates to:
  /// **'Select as destination'**
  String get selectAsDestination;

  /// Button to confirm moving the note to the selected folder
  ///
  /// In en, this message translates to:
  /// **'Move Here'**
  String get moveHere;

  /// Snackbar after successfully moving a folder
  ///
  /// In en, this message translates to:
  /// **'Folder moved successfully'**
  String get folderMoved;

  /// Snackbar when moving a folder fails
  ///
  /// In en, this message translates to:
  /// **'Failed to move folder'**
  String get folderMoveFailed;

  /// Snackbar when trying to move a folder into itself or a descendant
  ///
  /// In en, this message translates to:
  /// **'Cannot move a folder into itself or its subfolder'**
  String get cannotMoveIntoSelf;

  /// Snackbar shown when a folder name collides with an existing sibling
  ///
  /// In en, this message translates to:
  /// **'A folder named \"{name}\" already exists here'**
  String folderNameAlreadyExists(String name);

  /// Snackbar shown when a note title collides with an existing sibling
  ///
  /// In en, this message translates to:
  /// **'A note titled \"{title}\" already exists here'**
  String noteTitleAlreadyExists(String title);

  /// Snackbar shown after a move when some items collided with existing names at the destination
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 item was skipped because the destination already has an item with the same name} other{{count} items were skipped because the destination already has items with the same name}}'**
  String moveSkippedDueToDuplicates(int count);

  /// Title for move history bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Move History'**
  String get moveHistory;

  /// Empty state for move history
  ///
  /// In en, this message translates to:
  /// **'No recent moves'**
  String get noMoveHistory;

  /// Button to clear move history
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// Move history entry showing target folder
  ///
  /// In en, this message translates to:
  /// **'Moved to {target}'**
  String movedToTarget(String target);

  /// Label for undone move history entry
  ///
  /// In en, this message translates to:
  /// **'Undone'**
  String get undone;

  /// Snackbar when a move is undone from history
  ///
  /// In en, this message translates to:
  /// **'Move undone'**
  String get moveUndone;

  /// Time display for less than one minute ago
  ///
  /// In en, this message translates to:
  /// **'<1m'**
  String get timeLessThanMinute;

  /// Time display in minutes
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String timeMinutes(int count);

  /// Time display in hours
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String timeHours(int count);

  /// Time display in days
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String timeDays(int count);

  /// Snackbar shown when undoing a move whose source folder was deleted
  ///
  /// In en, this message translates to:
  /// **'Original location no longer exists'**
  String get originalLocationGone;

  /// Snackbar when user cancels picking a destination during undo
  ///
  /// In en, this message translates to:
  /// **'Restore canceled'**
  String get moveUndoCanceled;

  /// Confirmation dialog body when clearing move history
  ///
  /// In en, this message translates to:
  /// **'Clear all move history? This cannot be undone.'**
  String get clearMoveHistoryConfirm;

  /// Hint text for the folder search field in the move-to picker
  ///
  /// In en, this message translates to:
  /// **'Search folders'**
  String get searchFolders;

  /// Empty state when folder search returns no results
  ///
  /// In en, this message translates to:
  /// **'No folders found'**
  String get noFoldersFound;

  /// Section label for recently-used move destinations
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentDestinations;

  /// Snackbar shown after a batch move completes
  ///
  /// In en, this message translates to:
  /// **'{count} items moved'**
  String itemsMoved(int count);

  /// Bottom-bar action label to move all selected items
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveSelected;

  /// Bottom-bar action label to delete all selected items
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteSelected;

  /// Confirmation dialog body when deleting multiple selected items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 selected item? This cannot be undone.} other{Delete {count} selected items? This cannot be undone.}}'**
  String deleteSelectedConfirm(int count);

  /// Tooltip on the select-all action in selection mode
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// Snackbar shown when a markdown preview link cannot be launched
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open link'**
  String get linkOpenFailed;

  /// Snackbar shown when a markdown preview link uses an unsupported URL scheme
  ///
  /// In en, this message translates to:
  /// **'Link type not supported'**
  String get linkSchemeNotAllowed;

  /// Snackbar prompt shown before opening a link tapped in the editor
  ///
  /// In en, this message translates to:
  /// **'Open {target}?'**
  String linkOpenPrompt(String target);

  /// Snackbar action label that opens the tapped link
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get linkOpenAction;

  /// Snackbar shown when a tapped [[wiki link]] matches no note title
  ///
  /// In en, this message translates to:
  /// **'No note titled \"{title}\"'**
  String wikiLinkNoteNotFound(String title);

  /// Settings section header for the money ledger feature
  ///
  /// In en, this message translates to:
  /// **'Money ledger'**
  String get moneySection;

  /// Master switch for rendering $-prefixed money lines
  ///
  /// In en, this message translates to:
  /// **'Enable money ledger'**
  String get moneyLedgerEnabledLabel;

  /// Subtitle for the money ledger master switch
  ///
  /// In en, this message translates to:
  /// **'Render \$ money lines in notes and on the calendar'**
  String get moneyLedgerEnabledDesc;

  /// Setting label: the balance every note's ledger starts from
  ///
  /// In en, this message translates to:
  /// **'Start balance'**
  String get moneyStartBalance;

  /// Subtitle for the start balance setting
  ///
  /// In en, this message translates to:
  /// **'Every note\'s ledger starts from this amount'**
  String get moneyStartBalanceDesc;

  /// Setting label for the currency symbol shown on computed money values
  ///
  /// In en, this message translates to:
  /// **'Currency symbol'**
  String get moneyCurrencySymbolLabel;

  /// Subtitle for the currency symbol setting
  ///
  /// In en, this message translates to:
  /// **'Shown on computed amounts (e.g. lei, €, \$)'**
  String get moneyCurrencySymbolDesc;

  /// Setting label: place the currency symbol after the number
  ///
  /// In en, this message translates to:
  /// **'Symbol after amount'**
  String get moneyCurrencySuffixLabel;

  /// Subtitle for the currency placement setting
  ///
  /// In en, this message translates to:
  /// **'12.50 lei instead of lei12.50'**
  String get moneyCurrencySuffixDesc;

  /// Label and page title for per-note currency overrides
  ///
  /// In en, this message translates to:
  /// **'Per-note currency'**
  String get moneyPerNoteCurrency;

  /// Menu option clearing a note's currency override
  ///
  /// In en, this message translates to:
  /// **'Use global currency'**
  String get useGlobalCurrency;

  /// Menu option to enter a custom currency symbol
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get moneyCustomSymbol;

  /// Title of the bottom sheet listing money ledger entries
  ///
  /// In en, this message translates to:
  /// **'Ledger'**
  String get moneyDetailTitle;

  /// Money ledger error: label-first row ends with a colon but has no trailing amount
  ///
  /// In en, this message translates to:
  /// **'missing amount after \":\"'**
  String get moneyErrorMissingAmount;

  /// Money ledger error: accent colour token does not resolve against the palette
  ///
  /// In en, this message translates to:
  /// **'unknown colour name'**
  String get moneyErrorUnknownColour;

  /// Money ledger error: amount contains non-numeric characters
  ///
  /// In en, this message translates to:
  /// **'invalid amount'**
  String get moneyErrorInvalidAmount;

  /// Money ledger error: window count is not numeric or ALL
  ///
  /// In en, this message translates to:
  /// **'invalid count'**
  String get moneyErrorInvalidCount;

  /// Money ledger error: $/ 0 division
  ///
  /// In en, this message translates to:
  /// **'divide by zero'**
  String get moneyErrorDivideByZero;

  /// Money ledger error: amount exceeds the integer digit limit
  ///
  /// In en, this message translates to:
  /// **'amount too large (max 99,999,999,999.99)'**
  String get moneyErrorAmountTooLarge;

  /// Money ledger error: amount exceeds the decimal digit limit
  ///
  /// In en, this message translates to:
  /// **'too many decimals'**
  String get moneyErrorTooManyDecimals;

  /// Calendar day summary entry showing the net money change of linked notes
  ///
  /// In en, this message translates to:
  /// **'Money: {amount}'**
  String moneyDaySummaryTitle(String amount);

  /// Page title and settings row for the markdown color palette
  ///
  /// In en, this message translates to:
  /// **'Text colors'**
  String get markdownColorsTitle;

  /// Settings row subtitle for the markdown color palette
  ///
  /// In en, this message translates to:
  /// **'Colors for text and highlights'**
  String get markdownColorsSubtitle;

  /// Button inside the folded Text colors section that navigates to the color palette page
  ///
  /// In en, this message translates to:
  /// **'Edit colors'**
  String get editColors;

  /// Explains how the colored text syntax works
  ///
  /// In en, this message translates to:
  /// **'Type a color name before the text. Unknown names stay plain.'**
  String get markdownColorsHowTo;

  /// Placeholder body text shown in the syntax examples
  ///
  /// In en, this message translates to:
  /// **'sample text'**
  String get markdownColorsSampleText;

  /// Note explaining automatic contrast adjustment for custom colors
  ///
  /// In en, this message translates to:
  /// **'Custom colors are adjusted automatically when they would be unreadable on the current theme.'**
  String get markdownColorsFallbackNote;

  /// Section header listing the built-in color names
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get markdownColorsPresets;

  /// Section header listing the user's own color names
  ///
  /// In en, this message translates to:
  /// **'Custom colors'**
  String get markdownColorsCustom;

  /// Empty state for the custom colors list
  ///
  /// In en, this message translates to:
  /// **'No custom colors yet. Tap + to add one.'**
  String get markdownColorsEmpty;

  /// Title of the dialog asking for a color name
  ///
  /// In en, this message translates to:
  /// **'Color name'**
  String get markdownColorsNameTitle;

  /// Hint describing the characters allowed in a color name
  ///
  /// In en, this message translates to:
  /// **'lowercase letters, digits, - and _'**
  String get markdownColorsNameHint;

  /// Error shown when a color name normalizes to empty
  ///
  /// In en, this message translates to:
  /// **'Enter a name using letters, digits, - or _'**
  String get markdownColorsNameInvalid;

  /// Menu action to pick a new color for an existing name
  ///
  /// In en, this message translates to:
  /// **'Change color'**
  String get markdownColorsRecolor;

  /// Menu action to rename a custom color
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get markdownColorsRename;

  /// Menu action to delete a custom color
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get markdownColorsDelete;

  /// Title of the delete confirmation dialog for a custom color
  ///
  /// In en, this message translates to:
  /// **'Delete color'**
  String get markdownColorsDeleteTitle;

  /// Subtitle on a preset row that a custom color shadows
  ///
  /// In en, this message translates to:
  /// **'Overridden by a custom color'**
  String get markdownColorsOverridden;

  /// Error when the entered color name already exists
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is already used'**
  String markdownColorsNameTaken(String name);

  /// Error when the custom color limit is reached
  ///
  /// In en, this message translates to:
  /// **'Color limit reached ({count})'**
  String markdownColorsLimitReached(int count);

  /// Confirmation message when deleting a custom color
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Notes using it will show plain text.'**
  String markdownColorsDeleteMessage(String name);

  /// Title of the upcoming events bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcomingEvents;

  /// Hint of the search field in the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Search events'**
  String get upcomingSearchHint;

  /// Tooltip of the button clearing the upcoming events search field
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get upcomingClearSearch;

  /// Agenda display control label: how events are listed
  ///
  /// In en, this message translates to:
  /// **'Event rows'**
  String get upcomingEventDisplayTitle;

  /// Agenda event display option: one row per occurring day
  ///
  /// In en, this message translates to:
  /// **'Every one'**
  String get upcomingEventDisplayEveryOccurrence;

  /// Agenda event display option: a repeating event shown once, carrying how many occurrences it stands for
  ///
  /// In en, this message translates to:
  /// **'Per event'**
  String get upcomingEventDisplayPerEvent;

  /// Agenda event display option: a single summary card per category, digesting the whole window
  ///
  /// In en, this message translates to:
  /// **'One card'**
  String get upcomingEventDisplaySummary;

  /// How many distinct events a category summary card stands for
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 event} other {{count} events}}'**
  String upcomingEventCount(int count);

  /// Agenda display control label: how fasting days are listed
  ///
  /// In en, this message translates to:
  /// **'Fasting rows'**
  String get upcomingFastingDisplayTitle;

  /// Agenda fasting display option: one row per fasting day
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get upcomingFastingDisplayEveryDay;

  /// Agenda fasting display option: one row per fasting period, spanning it
  ///
  /// In en, this message translates to:
  /// **'Periods'**
  String get upcomingFastingDisplayPeriods;

  /// Agenda fasting display option: a single summary card per fasting tradition, digesting the whole window
  ///
  /// In en, this message translates to:
  /// **'One card'**
  String get upcomingFastingDisplaySummary;

  /// Agenda display control label: how public holidays are listed
  ///
  /// In en, this message translates to:
  /// **'Holiday rows'**
  String get upcomingHolidayDisplayTitle;

  /// Agenda holiday display option: one row per public holiday, interleaved by day
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get upcomingHolidayDisplayEveryDay;

  /// Agenda holiday display option: a single summary card digesting every public holiday in the window
  ///
  /// In en, this message translates to:
  /// **'One card'**
  String get upcomingHolidayDisplaySummary;

  /// How many public holidays the summary card stands for, shown before its date range
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 holiday} other {{count} holidays}}'**
  String upcomingHolidayCount(int count);

  /// Tooltip on a summary card's button opening the full list of the days it stands for
  ///
  /// In en, this message translates to:
  /// **'Show every day'**
  String get upcomingShowAllDays;

  /// Agenda display switch: the look-ahead window restarts from the day selected in the calendar instead of always starting today
  ///
  /// In en, this message translates to:
  /// **'Start from selected day'**
  String get upcomingFollowSelectedDay;

  /// Badge on a collapsed agenda row saying how many occurrences of the recurring event fall inside the window
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1× in window} other {{count}× in window}}'**
  String upcomingCollapsedTimes(int count);

  /// Length of a collapsed fasting period, shown after its date range
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 day} other {{count} days}}'**
  String upcomingFastingSpanDays(int count);

  /// Chip in the agenda header showing which day the look-ahead window starts on, when that is not today
  ///
  /// In en, this message translates to:
  /// **'from {date}'**
  String upcomingAnchorFrom(String date);

  /// Tooltip of the delete button on an active-filter chip in the agenda, which returns that one filter to its default
  ///
  /// In en, this message translates to:
  /// **'Remove filter'**
  String get upcomingRemoveFilter;

  /// Tooltip of the delete button on the agenda's anchor chip, which returns the look-ahead window to today
  ///
  /// In en, this message translates to:
  /// **'Back to today'**
  String get upcomingResetAnchor;

  /// Section heading for the agenda's presentation switches in the filters sheet
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get upcomingSectionDisplay;

  /// Agenda layer toggle: whether calendar events are listed at all
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get upcomingShowEvents;

  /// Summary chip shown when the events layer is switched off, leaving only holiday and fasting rows
  ///
  /// In en, this message translates to:
  /// **'No events'**
  String get upcomingEventsHidden;

  /// Label of the period menu row in the agenda filters sheet
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get upcomingPeriod;

  /// One of the three day presets in the Period menu of the agenda filters sheet, a rolling look-ahead of that many days; the panel's period chip reads the same label
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 day} other {{count} days}}'**
  String upcomingPeriodDays(int count);

  /// Item of the Period menu in the agenda filters sheet covering from the window's start day to 31 December of that year; the panel's period chip reads the same label
  ///
  /// In en, this message translates to:
  /// **'Rest of year'**
  String get upcomingPeriodRestOfYear;

  /// Item of the Period menu in the agenda filters sheet covering the whole calendar year, 1 January to 31 December, including days already past; the panel's period chip reads the same label
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get upcomingPeriodWholeYear;

  /// Item of the Period menu in the agenda filters sheet that opens the custom date range picker
  ///
  /// In en, this message translates to:
  /// **'Custom range…'**
  String get upcomingPeriodCustom;

  /// Label of the priority filter in the upcoming agenda
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get upcomingPriority;

  /// Value the Priority row of the agenda and calendar filter sheets reads back while no priority is selected, meaning events of every priority
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get upcomingPriorityAny;

  /// Empty state title of the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Nothing coming up'**
  String get upcomingNoEvents;

  /// Label before suggestion chips shown when a search returns nothing
  ///
  /// In en, this message translates to:
  /// **'Did you mean'**
  String get upcomingDidYouMean;

  /// Empty state hint of the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Try a longer period or a lower priority'**
  String get upcomingNoEventsHint;

  /// Day header for today in the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get upcomingToday;

  /// Day header for tomorrow in the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get upcomingTomorrow;

  /// Tooltip of the edit affordance on an upcoming event row
  ///
  /// In en, this message translates to:
  /// **'Edit event'**
  String get upcomingEditEvent;

  /// Label of the Holidays switch row under ALSO SHOW in the agenda and calendar filter sheets, listing public holidays alongside events; also the agenda's holidays heading and the name of that layer in a 'Without …' chip
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get upcomingShowHolidays;

  /// Label of the Fasting switch row under ALSO SHOW in the agenda and calendar filter sheets, listing configured fasting days alongside events; also the name of that layer in a 'Without …' chip
  ///
  /// In en, this message translates to:
  /// **'Fasting'**
  String get upcomingShowFasting;

  /// Label of the agenda's event-type filter row (which events to show)
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get upcomingEventType;

  /// Agenda event-type chip: show every event
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get upcomingEventTypeAll;

  /// Agenda event-type chip: show only repeating events
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get upcomingEventTypeRecurring;

  /// Agenda event-type chip: show only single-occurrence events
  ///
  /// In en, this message translates to:
  /// **'One-time'**
  String get upcomingEventTypeOneTime;

  /// Title of the agenda filters sheet, and the tooltip of the button that opens it
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get upcomingFilters;

  /// Tooltip of the toggle that hides the calendar grid so the bottom panel fills the page
  ///
  /// In en, this message translates to:
  /// **'Expand panel'**
  String get panelExpand;

  /// Tooltip of the toggle that brings the calendar grid back after expanding the panel
  ///
  /// In en, this message translates to:
  /// **'Show calendar'**
  String get panelShowCalendar;

  /// Calendar panel mode showing the selected day's entries
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get panelModeDay;

  /// Calendar panel mode showing the selected day as an hour grid
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get panelModeTimeline;

  /// Empty state hint of the calendar timeline panel mode
  ///
  /// In en, this message translates to:
  /// **'Events with a start time appear on the timeline'**
  String get timelineEmptyHint;

  /// Calendar and overview overflow-menu action exporting events as iCalendar
  ///
  /// In en, this message translates to:
  /// **'Export events (.ics)'**
  String get exportEventsIcs;

  /// Progress message shown while writing the .ics export
  ///
  /// In en, this message translates to:
  /// **'Exporting events...'**
  String get exportingEvents;

  /// Error message shown when the .ics export fails
  ///
  /// In en, this message translates to:
  /// **'Could not export events'**
  String get eventsExportError;

  /// Confirmation shown after a successful .ics export
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No events exported} one {1 event exported} other {{count} events exported}}'**
  String eventsExported(int count);

  /// Hint text of the search field above the shortcut list in markdown settings
  ///
  /// In en, this message translates to:
  /// **'Search shortcuts'**
  String get searchShortcuts;

  /// Label for the free-text category assigned to a markdown shortcut
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get shortcutCategory;

  /// Shortcut card menu action that opens the category dialog
  ///
  /// In en, this message translates to:
  /// **'Set category'**
  String get setCategory;

  /// Filter chip and label for shortcuts without a category
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// Hint text of the category input field
  ///
  /// In en, this message translates to:
  /// **'e.g. Push day'**
  String get categoryHint;

  /// Action in the category dialog that removes the shortcut's category
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get noCategory;

  /// Header above the list of already used categories in the category dialog
  ///
  /// In en, this message translates to:
  /// **'Existing categories'**
  String get existingCategories;

  /// Button that clears the shortcut search query and selected category chips
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearFilters;

  /// Hint shown above the shortcut list explaining why dragging is disabled
  ///
  /// In en, this message translates to:
  /// **'Clear search and filters to reorder'**
  String get clearSearchToReorder;

  /// Empty state shown when the search or category filter matches nothing
  ///
  /// In en, this message translates to:
  /// **'No shortcuts match'**
  String get noShortcutsMatchFilter;

  /// Badge next to the shortcuts section title showing matches vs total
  ///
  /// In en, this message translates to:
  /// **'{shown} / {total}'**
  String shortcutCountFiltered(int shown, int total);

  /// App bar action that folds every section of the markdown settings page
  ///
  /// In en, this message translates to:
  /// **'Collapse all'**
  String get collapseAll;

  /// App bar action that unfolds every section of the markdown settings page
  ///
  /// In en, this message translates to:
  /// **'Expand all'**
  String get expandAll;

  /// Hint text of the search field above the utility button list
  ///
  /// In en, this message translates to:
  /// **'Search buttons'**
  String get searchUtilityButtons;

  /// Neutral empty state shown when a settings list search matches nothing
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatchesFound;

  /// Hint text of the search field on settings pages
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get searchSettings;

  /// Trailing hint on a collapsed settings section header, saying how many rows it is hiding
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 option} other{{count} options}}'**
  String settingsSectionCollapsedCount(int count);

  /// Comma-separated hidden search synonyms for the haptic feedback setting. Translate to words users of this locale would actually type; they are matched but never displayed.
  ///
  /// In en, this message translates to:
  /// **'vibration, buzz, rumble'**
  String get hapticFeedbackKeywords;

  /// Comma-separated hidden search synonyms for the auto-save settings
  ///
  /// In en, this message translates to:
  /// **'backup, persist, write'**
  String get autoSaveKeywords;

  /// Comma-separated hidden search synonyms for the word wrap setting
  ///
  /// In en, this message translates to:
  /// **'line, overflow, break'**
  String get wordWrapKeywords;

  /// Comma-separated hidden search synonyms for the swipe gesture settings
  ///
  /// In en, this message translates to:
  /// **'gesture, slide, drag'**
  String get swipeKeywords;

  /// Comma-separated hidden search synonyms for the live markdown rendering setting
  ///
  /// In en, this message translates to:
  /// **'preview, render, format'**
  String get liveMarkdownKeywords;

  /// Comma-separated hidden search synonyms for the line numbers setting
  ///
  /// In en, this message translates to:
  /// **'gutter, numbering'**
  String get lineNumbersKeywords;

  /// Comma-separated hidden search synonyms for the delete confirmation setting
  ///
  /// In en, this message translates to:
  /// **'trash, remove, prompt'**
  String get confirmDeleteKeywords;

  /// Comma-separated hidden search synonyms for preview performance settings
  ///
  /// In en, this message translates to:
  /// **'speed, lag, chunk, fast'**
  String get performanceKeywords;

  /// Comma-separated hidden search synonyms for cursor related editor settings
  ///
  /// In en, this message translates to:
  /// **'caret, current line'**
  String get cursorKeywords;

  /// Comma-separated hidden search synonyms for keyboard related editor settings
  ///
  /// In en, this message translates to:
  /// **'typing, input'**
  String get keyboardKeywords;

  /// Sharing settings menu item
  ///
  /// In en, this message translates to:
  /// **'Sync & sharing'**
  String get sharingSettings;

  /// Section heading for the cloud account rows
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// Button starting the Google sign-in flow
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// Button ending the signed-in session
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// Shown when no cloud account is connected
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notSignedIn;

  /// Shown while the sign-in flow is running
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// Shown on desktop, where cloud sync cannot run
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get syncUnavailablePlatform;

  /// Explains that desktop remains local-only
  ///
  /// In en, this message translates to:
  /// **'Sharing works on Android and iOS. Your data stays on this device.'**
  String get syncUnavailablePlatformDesc;

  /// Title of the note sync files when another device's newer edit replaced an unsynced local edit; the local text is kept under this title
  ///
  /// In en, this message translates to:
  /// **'{title} (conflict copy, {dateTime})'**
  String syncConflictCopyTitle(String title, DateTime dateTime);

  /// Quiet snackbar in the note editor when the open note, with no unsaved changes, was reloaded with text synced from another device
  ///
  /// In en, this message translates to:
  /// **'Updated from another device'**
  String get syncNoteUpdatedElsewhere;

  /// Snackbar in the note editor when another device changed the open note while it had unsaved changes: the typed text stays, the other device's text becomes a conflict copy note
  ///
  /// In en, this message translates to:
  /// **'Another device\'s version was saved as a copy'**
  String get syncNoteConflictCopyFiled;

  /// Snackbar after the note editor closes because the open note, with no unsaved changes, was deleted on another device
  ///
  /// In en, this message translates to:
  /// **'Deleted on another device'**
  String get syncNoteDeletedElsewhere;

  /// Snackbar in the note editor when the open note, with unsaved changes, was deleted on another device: the typed text is saved as a new note the editor keeps editing
  ///
  /// In en, this message translates to:
  /// **'Deleted on another device — your text was kept as a new note'**
  String get syncNoteKeptAsNew;

  /// Snackbar in the note editor when saving a sync conflict copy failed; saving waits and retries
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save a copy — your text is kept and the next save tries again'**
  String get syncNoteConflictCopyFailed;

  /// Snackbar in the note editor when the open note, with unsaved changes, was deleted on another device and saving the typed text as a new note failed; the editor stays open with the text and retries
  ///
  /// In en, this message translates to:
  /// **'Deleted on another device — couldn\'t keep your text as a new note yet; the next save tries again'**
  String get syncNoteKeptAsNewFailed;

  /// Error title when the sign-in flow throws
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get signInFailed;

  /// Account row title when signing out threw or took too long; the user is still signed in
  ///
  /// In en, this message translates to:
  /// **'Sign-out failed'**
  String get authSignOutFailed;

  /// Snackbar when signing out threw or took too long; the account row offers Sign out again
  ///
  /// In en, this message translates to:
  /// **'Sign-out failed — try again'**
  String get authSignOutFailedRetry;

  /// Sign-in error: the device could not reach the server
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network and try again.'**
  String get authErrorOffline;

  /// Sign-in error: the bound auth service cannot sign in at all
  ///
  /// In en, this message translates to:
  /// **'Sign-in is not available here'**
  String get authErrorUnavailable;

  /// Sign-in error: the platform does not support the interactive flow
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In is not available on this device'**
  String get authErrorNotSupported;

  /// Sign-in error: no more specific reason is known
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Try again.'**
  String get authErrorUnknown;

  /// Button re-running a failed action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Comma-separated hidden search synonyms for the sharing settings
  ///
  /// In en, this message translates to:
  /// **'cloud, sync, account, google, login, share, partner, pairing, code, invite, unpair'**
  String get sharingKeywords;

  /// Sharing page section that syncs this database with the account's other devices
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncSection;

  /// Comma-separated hidden search synonyms for the Sync section of the sharing settings
  ///
  /// In en, this message translates to:
  /// **'cloud, sync, devices, phone, tablet, space, merge, download, upload, status, offline, stop, automatic, manual, delete'**
  String get syncKeywords;

  /// Row that turns sync on for the open database; also the title of the sheet that picks a cloud space
  ///
  /// In en, this message translates to:
  /// **'Sync this database'**
  String get syncThisDatabase;

  /// Subtitle of the Sync this database row while signed in
  ///
  /// In en, this message translates to:
  /// **'Your other devices signed in to this account get every change, and send theirs'**
  String get syncThisDatabaseDesc;

  /// Subtitle of the disabled Sync this database row while signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync this database'**
  String get syncSignInFirst;

  /// Subtitle of the disabled Sync this database row where sync cannot run (desktop, a test build without the cloud, or the cloud failed to start); names no platform
  ///
  /// In en, this message translates to:
  /// **'Sync isn\'t available in this version of ANTA'**
  String get syncThisDatabaseUnavailable;

  /// Sync status: nothing waits to be sent or received
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get syncUpToDate;

  /// Sync status of a database bound to a cloud space that has not received from it yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first sync'**
  String get syncWaitingFirst;

  /// Sync status while this device sends its changes to the cloud
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Sending changes} =1{Sending 1 change} other{Sending {count} changes}}'**
  String syncSending(int count);

  /// Sync status while this device reads changes made on the account's other devices
  ///
  /// In en, this message translates to:
  /// **'Receiving changes'**
  String get syncReceiving;

  /// Sync status during the first download after sync was turned on, with the rows applied so far
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Downloading — 1 item so far} other{Downloading — {count} items so far}}'**
  String syncDownloading(int count);

  /// Sync status during the first sync after an app update that changed how notes sync: every note is read again, which slows the app for a while; done is how many notes were read so far, total how many notes this database holds
  ///
  /// In en, this message translates to:
  /// **'Finishing update — notes {done} of {total}'**
  String syncUpdatingNotes(int done, int total);

  /// Sync status during the first sync after an app update that changed how notes sync, before the number of notes is known
  ///
  /// In en, this message translates to:
  /// **'Finishing update'**
  String get syncUpdating;

  /// Sync status during the first sync after an app update that changed how notes sync, once every note was read again: the notes are sent to the cloud copy in the new form, which slows the app for a while; done is how many notes were sent so far, total how many were waiting to be sent
  ///
  /// In en, this message translates to:
  /// **'Finishing update — sending {done} of {total}'**
  String syncUpdatingSending(int done, int total);

  /// Sync status: the last sync found no connection and tries again by itself
  ///
  /// In en, this message translates to:
  /// **'Offline — will retry'**
  String get syncOffline;

  /// Sync status: the last sync failed for another reason and tries again by itself
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync — will retry'**
  String get syncRetrying;

  /// Sync status while Sync automatically is off: the last Sync now met no connection, and nothing retries by itself
  ///
  /// In en, this message translates to:
  /// **'Offline — couldn\'t sync'**
  String get syncOfflineManual;

  /// Sync status while Sync automatically is off: the last Sync now failed for another reason, and nothing retries by itself
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync'**
  String get syncFailedManual;

  /// Sync status while Sync automatically is off and nothing waits or failed: says how syncing happens, since nothing runs by itself
  ///
  /// In en, this message translates to:
  /// **'Syncs when you tap “Sync now”'**
  String get syncManualIdle;

  /// Sync status: the account's daily cloud quota ran out and its reset has passed; sync tries again by itself
  ///
  /// In en, this message translates to:
  /// **'Paused — daily limit reached'**
  String get syncPausedQuota;

  /// Sync status: the account's daily cloud quota ran out; {time} is the local time of day it comes back
  ///
  /// In en, this message translates to:
  /// **'Paused until {time} — daily limit reached'**
  String syncPausedQuotaUntil(String time);

  /// Sync status: the database still syncs, but nobody is signed in
  ///
  /// In en, this message translates to:
  /// **'Paused — signed out'**
  String get syncPausedSignedOut;

  /// Sync status: the signed-in account is not the one this database syncs with
  ///
  /// In en, this message translates to:
  /// **'Paused — this database syncs with another account'**
  String get syncPausedOtherAccount;

  /// Sync status: a newer version of the app wrote to the cloud copy
  ///
  /// In en, this message translates to:
  /// **'Paused — update ANTA on this device'**
  String get syncPausedAppOutdated;

  /// Sync status: this account may not read or write the cloud copy
  ///
  /// In en, this message translates to:
  /// **'Paused — the cloud copy can\'t be reached'**
  String get syncPausedNoAccess;

  /// Sync status: the cloud copy this database synced with was deleted, from this account's other device or the console
  ///
  /// In en, this message translates to:
  /// **'Paused — the cloud copy was deleted'**
  String get syncPausedSpaceDeleted;

  /// Status line of the drawer's account row: this database is not bound to a cloud space
  ///
  /// In en, this message translates to:
  /// **'Not syncing'**
  String get drawerAccountNotSyncing;

  /// Status line of the drawer's account row, short: the account's daily cloud quota ran out and its reset has passed
  ///
  /// In en, this message translates to:
  /// **'Paused — daily limit'**
  String get drawerSyncPausedQuota;

  /// Status line of the drawer's account row, short: the account's daily cloud quota ran out; {time} is the local time of day it comes back
  ///
  /// In en, this message translates to:
  /// **'Paused until {time}'**
  String drawerSyncPausedQuotaUntil(String time);

  /// Status line of the drawer's account row, short: the signed-in account is not the one this database syncs with
  ///
  /// In en, this message translates to:
  /// **'Paused — another account'**
  String get drawerSyncPausedOtherAccount;

  /// Status line of the drawer's account row, short: a newer version of the app wrote to the cloud copy
  ///
  /// In en, this message translates to:
  /// **'Paused — update ANTA'**
  String get drawerSyncPausedAppOutdated;

  /// Status line of the drawer's account row, short: this account may not read or write the cloud copy
  ///
  /// In en, this message translates to:
  /// **'Paused — no access'**
  String get drawerSyncPausedNoAccess;

  /// Status line of the drawer's account row, short: the cloud copy this database synced with was deleted
  ///
  /// In en, this message translates to:
  /// **'Paused — cloud copy deleted'**
  String get drawerSyncPausedSpaceDeleted;

  /// Status line of the drawer's account row, short: the last sync failed for a reason other than no connection and tries again by itself
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync — will retry'**
  String get drawerSyncRetrying;

  /// Status line of the drawer's account row, short: the first sync after an app update that changed how notes sync, reading every note again and then sending them; done is how many notes that step has handled so far, total how many it handles
  ///
  /// In en, this message translates to:
  /// **'Finishing update ({done} of {total})'**
  String drawerSyncUpdating(int done, int total);

  /// Status line of the drawer's account row, short: the first sync after an app update that changed how notes sync, before the number of notes is known
  ///
  /// In en, this message translates to:
  /// **'Finishing update'**
  String get drawerSyncUpdatingNoTotal;

  /// When this database last synced; time is a time of day today, else a date
  ///
  /// In en, this message translates to:
  /// **'Last synced {time}'**
  String syncLastSynced(String time);

  /// Shown in place of the last sync time before the first sync
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get syncNeverSynced;

  /// Changes made on this device that are not in the cloud yet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change waiting} other{{count} changes waiting}}'**
  String syncPendingCount(int count);

  /// Changes not in the cloud yet, short, after the last sync time on one line: 'Last synced 3:09 AM · 3 waiting · 2 held back'
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 waiting} other{{count} waiting}}'**
  String syncDetailsWaiting(int count);

  /// Changes that could not be sent or applied this session and are tried again when the app next starts; short, after the last sync time on one line: 'Last synced 3:09 AM · 3 waiting · 2 held back'
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 held back} other{{count} held back}}'**
  String syncParkedCount(int count);

  /// Why a row in the Sync page's held-back list was not sent: the cloud copy's rules refused it
  ///
  /// In en, this message translates to:
  /// **'Refused by the cloud copy'**
  String get syncHeldBackRefused;

  /// Why a row in the Sync page's held-back list was not sent: it could not be encoded (too large, or a piece of its text is missing)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t be prepared for sending'**
  String get syncHeldBackUnencodable;

  /// Why a note in the Sync page's held-back list was not applied: part of its text has not reached the cloud copy yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for its text'**
  String get syncHeldBackAwaitingText;

  /// Why a row in the Sync page's held-back list was not applied yet: the folder, calendar event or calendar category it belongs to has not arrived from the person's own cloud copy, and a row their partner shares holds that place for now
  ///
  /// In en, this message translates to:
  /// **'Waiting for its folder, event or category'**
  String get syncHeldBackSharedParent;

  /// Why a row in the Sync page's held-back list was not applied: its cloud copy could not be read by this app
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t be read from the cloud copy'**
  String get syncHeldBackUnreadable;

  /// Reason line of a held-back row that was deleted on this device: 'Deleted' then the reason. kind is note, folder, event, category, counter, template, view, filter, digest, vocabulary or other, for languages whose word agrees with the kind
  ///
  /// In en, this message translates to:
  /// **'{kind, select, other{Deleted}} · {reason}'**
  String syncHeldBackDeleted(String kind, String reason);

  /// Title of a held-back row the Sync page cannot name, by its kind: anything but a note or a folder, or a note or folder this device has no copy of
  ///
  /// In en, this message translates to:
  /// **'{kind, select, note{A note} folder{A folder} event{A calendar event} category{A calendar category} counter{A counter} template{An event template} view{A saved view} filter{A saved filter} digest{A digest} vocabulary{A vocabulary list} other{An item}}'**
  String syncHeldBackKind(String kind);

  /// Last row of the Sync page's held-back list, counting the rows not listed that are still held back now
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{And 1 more still held back} other{And {count} more still held back}}'**
  String syncHeldBackMoreHeld(int count);

  /// Last row of the Sync page's held-back list once none of the rows not listed is held back any more, counting them
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The other one was synced} other{The other {count} were synced}}'**
  String syncHeldBackMoreSynced(int count);

  /// Replaces the reason of a held-back row that went through while the Sync page is open — sent, received or overtaken by a newer version; the row stays in place until the page is opened again. kind is note, folder, event, category, counter, template, view, filter, digest, vocabulary or other, for languages whose word agrees with the kind
  ///
  /// In en, this message translates to:
  /// **'{kind, select, other{Synced}}'**
  String syncHeldBackSynced(String kind);

  /// Header of the Sync page's held-back list once none of its rows is held back any more, while the page stays open
  ///
  /// In en, this message translates to:
  /// **'All synced'**
  String get syncHeldBackAllDone;

  /// Line under the Sync page's held-back header: the 'Sync now' row, quoted by its own label, retries the rows listed. One press retries the 100 oldest of each kind; the copy stays short
  ///
  /// In en, this message translates to:
  /// **'“Sync now” tries these again.'**
  String get syncHeldBackIntro;

  /// Replaces the line under the Sync page's held-back header once none of its rows is held back any more, while the page stays open
  ///
  /// In en, this message translates to:
  /// **'Nothing is held back any more.'**
  String get syncHeldBackIntroDone;

  /// Row that runs a sync at once
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// Switch in the bound Sync section: on, syncing runs by itself; off, only the Sync now row runs it
  ///
  /// In en, this message translates to:
  /// **'Sync automatically'**
  String get syncAutomatic;

  /// Subtitle of the Sync automatically switch while it is on
  ///
  /// In en, this message translates to:
  /// **'Changes sync while the app is open, and when you leave it'**
  String get syncAutomaticOnDesc;

  /// Subtitle of the Sync automatically switch while it is off
  ///
  /// In en, this message translates to:
  /// **'Only when you tap “Sync now”'**
  String get syncAutomaticOffDesc;

  /// Row in the Sync section that stops syncing the open database; the cloud copy stays. Short: the section already says Sync, the confirm names the database
  ///
  /// In en, this message translates to:
  /// **'Stop syncing'**
  String get syncStop;

  /// Title of the dialog confirming Stop syncing this database
  ///
  /// In en, this message translates to:
  /// **'Stop syncing this database?'**
  String get syncStopConfirmTitle;

  /// Body of the dialog confirming Stop syncing this database
  ///
  /// In en, this message translates to:
  /// **'This device stops sending and receiving changes for this database. The copy in the cloud stays, and your other devices keep it.'**
  String get syncStopConfirmBody;

  /// Confirm button of the Stop syncing dialog
  ///
  /// In en, this message translates to:
  /// **'Stop syncing'**
  String get syncStopConfirmAction;

  /// Error when stopping sync failed for an unknown reason
  ///
  /// In en, this message translates to:
  /// **'Syncing couldn\'t be stopped — try again'**
  String get syncStopFailed;

  /// Body of the dialog confirming Stop syncing while sync is paused because the cloud copy was deleted from another device
  ///
  /// In en, this message translates to:
  /// **'This database\'s cloud copy was deleted. This device keeps everything and stops trying to sync.'**
  String get syncStopConfirmBodyDeleted;

  /// Last row of the Sync section of a syncing database: removes the database's copy from the cloud account for good; nothing on the device is deleted
  ///
  /// In en, this message translates to:
  /// **'Delete cloud copy'**
  String get syncDeleteCloud;

  /// Subtitle of the Delete cloud copy row
  ///
  /// In en, this message translates to:
  /// **'Removes it from your account. This device keeps everything.'**
  String get syncDeleteCloudDesc;

  /// Subtitle of the Deleting cloud copy row while a cloud copy is being deleted in the background, counting the items removed so far — at zero, before the first items are gone, it says the deletion is starting; also the subtitle of the Cloud copy deleted row, counting what was removed in all. The title already says what is being deleted, so this only counts
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Starting…} =1{1 item removed} other{{count} items removed}}'**
  String syncDeleteCloudProgress(int count);

  /// Title of the dialog confirming Delete cloud copy
  ///
  /// In en, this message translates to:
  /// **'Delete this database\'s cloud copy?'**
  String get syncDeleteCloudConfirmTitle;

  /// Body of the dialog confirming Delete cloud copy
  ///
  /// In en, this message translates to:
  /// **'The copy is removed from your account for good, and this database stops syncing. Nothing is deleted on this device. Your other devices keep what they hold and stop syncing too.'**
  String get syncDeleteCloudConfirmBody;

  /// Destructive confirm button of the Delete cloud copy dialog
  ///
  /// In en, this message translates to:
  /// **'Delete cloud copy'**
  String get syncDeleteCloudConfirmAction;

  /// Announced to screen readers when deleting a cloud copy has finished; also the title the Cloud copy deletion section's row keeps, muted under a check, once the deletion ended while the page was open
  ///
  /// In en, this message translates to:
  /// **'Cloud copy deleted'**
  String get syncDeleteCloudDone;

  /// Header of the last section of the Sync & sharing page, shown while deleting a cloud copy runs or is left unfinished
  ///
  /// In en, this message translates to:
  /// **'Cloud copy deletion'**
  String get syncDeletionSection;

  /// Title of the Cloud copy deletion section's row while a cloud copy's deletion runs in the background; the row's subtitle counts the items removed
  ///
  /// In en, this message translates to:
  /// **'Deleting cloud copy'**
  String get syncDeleteCloudRunning;

  /// Title of the Cloud copy deletion section's row while deleting a cloud copy was cut short: a tap finishes the deletion
  ///
  /// In en, this message translates to:
  /// **'Finish deleting'**
  String get syncDeleteCloudFinish;

  /// Subtitle of the Finish deleting row, held, when only a newer version of the app can finish the deletion (a newer ANTA wrote to the cloud copy)
  ///
  /// In en, this message translates to:
  /// **'Update ANTA to finish'**
  String get syncDeleteCloudFinishUpdate;

  /// Subtitle of the Finish deleting row, naming the cloud space whose deletion was cut short; the name goes last so a long one is the part an ellipsis cuts
  ///
  /// In en, this message translates to:
  /// **'Partly deleted from your account: “{space}”'**
  String syncDeleteCloudFinishDesc(String space);

  /// Subtitle of the Finish deleting row when the deletions of several cloud spaces were cut short: says how many instead of naming one
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cloud copy is partly deleted from your account} other{{count} cloud copies are partly deleted from your account}}'**
  String syncDeleteCloudFinishMany(int count);

  /// Second row of the Account section of the Sync & sharing page, drawn destructive: deletes the signed-in account and everything it holds in the cloud, nothing on the device. Also the destructive confirm button of its dialog
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get syncDeleteAccount;

  /// Subtitle of the Delete account row
  ///
  /// In en, this message translates to:
  /// **'Removes the account and all its cloud copies. This device keeps everything.'**
  String get syncDeleteAccountDesc;

  /// Title of the dialog confirming Delete account
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get syncDeleteAccountConfirmTitle;

  /// Body of the dialog confirming Delete account; after the confirm button Google's own sign-in prompt appears
  ///
  /// In en, this message translates to:
  /// **'Every cloud copy of this account is removed for good, sharing with your partner ends, and the account itself is deleted. Nothing is deleted on this device. Google will ask you to sign in once more.'**
  String get syncDeleteAccountConfirmBody;

  /// Title of the deletion section's row while an account's deletion runs in the background; the row's subtitle counts the items removed
  ///
  /// In en, this message translates to:
  /// **'Deleting account'**
  String get syncDeleteAccountRunning;

  /// Title of the deletion section's row while an account's deletion was cut short: a tap asks Google for the sign-in again and finishes it
  ///
  /// In en, this message translates to:
  /// **'Finish deleting account'**
  String get syncDeleteAccountFinish;

  /// Subtitle of the Finish deleting account row: the tap opens Google's sign-in prompt first
  ///
  /// In en, this message translates to:
  /// **'Sign in again to finish'**
  String get syncDeleteAccountFinishDesc;

  /// Snackbar on the Sync & sharing page once the account was deleted and the page reads signed out
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get syncDeleteAccountDone;

  /// Snackbar when the Google account chosen to confirm Delete account is not the one signed in
  ///
  /// In en, this message translates to:
  /// **'That is another account — nothing was deleted'**
  String get syncFailedOtherAccount;

  /// Snackbar, and the spoken value of the row, when deleting the account failed for no reason the app can name
  ///
  /// In en, this message translates to:
  /// **'The account couldn\'t be deleted — try again'**
  String get syncDeleteAccountFailed;

  /// Snackbar when syncing a database is refused because the signed-in account's own deletion is under way or waiting to be finished
  ///
  /// In en, this message translates to:
  /// **'This account is being deleted — finish that, or sign out to keep the account'**
  String get syncFailedAccountDeleting;

  /// Body of the sign-out confirmation while the account's own deletion is unfinished: signing out gives that deletion up
  ///
  /// In en, this message translates to:
  /// **'Sign out? Your account stays. Cloud copies already being deleted are still removed.'**
  String get signOutConfirmDeleting;

  /// Section label over the account's cloud spaces in the sheet that picks one
  ///
  /// In en, this message translates to:
  /// **'Cloud spaces'**
  String get syncPickerSpaces;

  /// Title of the sheet that picks the cloud space this database syncs with, or a new one; short, it must fit one line at large text
  ///
  /// In en, this message translates to:
  /// **'Choose a space'**
  String get syncPickerTitle;

  /// When a cloud space was last written to; time is a time of day today, else a date
  ///
  /// In en, this message translates to:
  /// **'Last used {time}'**
  String syncPickerLastUsed(String time);

  /// A cloud space nothing was written to yet
  ///
  /// In en, this message translates to:
  /// **'Not used yet'**
  String get syncPickerNotUsed;

  /// Why a cloud space cannot be picked: another database on this device already syncs it
  ///
  /// In en, this message translates to:
  /// **'Synced by “{database}” on this device'**
  String syncPickerHeldBy(String database);

  /// Picker choice: the open database's data and the cloud space's become one
  ///
  /// In en, this message translates to:
  /// **'Merge this database into “{space}”'**
  String syncPickerMerge(String space);

  /// Picker choice under the list of spaces: the open database's data and the checked space's become one
  ///
  /// In en, this message translates to:
  /// **'Merge this database into the selected space'**
  String get syncPickerMergeSelected;

  /// Picker choice: the cloud space becomes a new database on this device, which the app switches to
  ///
  /// In en, this message translates to:
  /// **'Download “{space}” into a new database'**
  String syncPickerDownload(String space);

  /// Picker choice under the list of spaces: the checked space becomes a new database on this device, which the app switches to
  ///
  /// In en, this message translates to:
  /// **'Download the selected space into a new database'**
  String get syncPickerDownloadSelected;

  /// Picker choice for an empty database: it starts syncing with the cloud space
  ///
  /// In en, this message translates to:
  /// **'Sync with “{space}”'**
  String syncPickerJoin(String space);

  /// Picker choice: the open database becomes a new, separate cloud space
  ///
  /// In en, this message translates to:
  /// **'Upload this database as a new space'**
  String get syncPickerUpload;

  /// Turning sync on or off failed: no connection
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — try again once you\'re connected'**
  String get syncFailedOffline;

  /// Turning sync on or off failed: the account's daily cloud quota ran out
  ///
  /// In en, this message translates to:
  /// **'Today\'s sync limit is reached — try again tomorrow'**
  String get syncFailedQuota;

  /// Turning sync on or off failed: the cloud refused the request
  ///
  /// In en, this message translates to:
  /// **'The cloud refused this — check you\'re signed in to the right account, or that sync is set up in the cloud'**
  String get syncFailedPermission;

  /// Downloading a cloud space failed because the space was deleted from the cloud since the picker listed it
  ///
  /// In en, this message translates to:
  /// **'That cloud space no longer exists — pick another, or upload this database as a new space'**
  String get syncFailedSpaceGone;

  /// Deleting the cloud copy failed before anything changed: a newer version of the app wrote to it, and this version may not know all of its data
  ///
  /// In en, this message translates to:
  /// **'A newer ANTA wrote to this cloud copy — update the app first'**
  String get syncFailedAppOutdated;

  /// Turning sync on or off failed: a restore or import is rewriting the database
  ///
  /// In en, this message translates to:
  /// **'A restore is running — try again when it finishes'**
  String get syncFailedSuspended;

  /// Turning sync on failed: the database syncs already
  ///
  /// In en, this message translates to:
  /// **'This database already syncs — stop syncing it first'**
  String get syncFailedAlreadyBound;

  /// Turning sync on failed: another database on this device syncs with the chosen cloud space
  ///
  /// In en, this message translates to:
  /// **'The database “{database}” on this device already syncs with that space'**
  String syncFailedHeld(String database);

  /// Turning sync on failed: another database on this device, whose name is not known, syncs with the chosen cloud space
  ///
  /// In en, this message translates to:
  /// **'Another database on this device already syncs with that space'**
  String get syncFailedHeldUnnamed;

  /// Turning sync on failed: the new cloud space's name is empty or too long
  ///
  /// In en, this message translates to:
  /// **'A space name needs 1 to 100 characters'**
  String get syncFailedInvalidName;

  /// Downloading a cloud space failed: the new database could not be created
  ///
  /// In en, this message translates to:
  /// **'The new database couldn\'t be created — nothing changed'**
  String get syncFailedNewDatabase;

  /// Turning sync on failed for an unknown reason
  ///
  /// In en, this message translates to:
  /// **'Sync couldn\'t be turned on — try again'**
  String get syncFailedUnknown;

  /// Title of the dialog that asks before a database holding data merges into a cloud space
  ///
  /// In en, this message translates to:
  /// **'Merge into “{space}”?'**
  String syncMergeConfirmTitle(String space);

  /// Body of the merge confirmation: what a merge does to data both sides hold and to data only this device holds
  ///
  /// In en, this message translates to:
  /// **'Rows this database and the cloud both hold take the cloud\'s version. Rows only here are uploaded.'**
  String get syncMergeConfirmBody;

  /// Confirm button of the merge confirmation
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get syncMergeConfirmAction;

  /// Shown under 'Sync this database' once sync stopped by itself because this database turned out to be a copy of another database on this device that syncs with the same cloud space
  ///
  /// In en, this message translates to:
  /// **'Stopped syncing — a copy of “{database}” already syncs with this space'**
  String syncUnboundAsCopyOf(String database);

  /// Spoken by screen readers for the spinner of a Sync row while turning sync on or off runs
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get syncBusyLabel;

  /// Announced to screen readers when this database starts syncing with a cloud space
  ///
  /// In en, this message translates to:
  /// **'Syncing with “{space}”'**
  String syncAnnounceBound(String space);

  /// Announced to screen readers when this database starts syncing and the space's name is not known to the page (the space was created or joined in the same tap)
  ///
  /// In en, this message translates to:
  /// **'Syncing this database'**
  String get syncAnnounceBoundUnnamed;

  /// Announced to screen readers when this database stops syncing
  ///
  /// In en, this message translates to:
  /// **'Stopped syncing'**
  String get syncAnnounceStopped;

  /// One-sentence app description in the About dialog
  ///
  /// In en, this message translates to:
  /// **'An offline-first personal tracker: folders, markdown notes, a money ledger, counters, and a calendar.'**
  String get aboutDescription;

  /// Sharing page section that links two accounts
  ///
  /// In en, this message translates to:
  /// **'Pairing'**
  String get pairingSection;

  /// Pairing row title when no partner is linked
  ///
  /// In en, this message translates to:
  /// **'Not paired'**
  String get pairingNotPaired;

  /// Pairing row subtitle when no partner is linked
  ///
  /// In en, this message translates to:
  /// **'Share with someone'**
  String get pairingNotPairedDesc;

  /// Pairing row title when the user is signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in to share'**
  String get pairingSignInFirst;

  /// Pairing row title while a generated code is unused
  ///
  /// In en, this message translates to:
  /// **'Waiting for your partner'**
  String get pairingWaiting;

  /// Pairing row title naming the linked partner
  ///
  /// In en, this message translates to:
  /// **'Paired with {name}'**
  String pairingPairedWith(String name);

  /// Pairing row subtitle when paired: the link exists but no content syncs yet
  ///
  /// In en, this message translates to:
  /// **'Linked. Nothing is shared yet.'**
  String get pairingPairedDesc;

  /// Pairing row title before the partner has published a name
  ///
  /// In en, this message translates to:
  /// **'Paired'**
  String get pairingPartnerUnknown;

  /// Title of the pairing sheet
  ///
  /// In en, this message translates to:
  /// **'Pair with someone'**
  String get pairingTitle;

  /// Button minting an invite code
  ///
  /// In en, this message translates to:
  /// **'Create a code'**
  String get pairingGenerateCode;

  /// Explains what to do with a freshly generated code
  ///
  /// In en, this message translates to:
  /// **'Read this code to the other person. It works once.'**
  String get pairingCodeIntro;

  /// Countdown under a generated pairing code
  ///
  /// In en, this message translates to:
  /// **'Expires in {time}'**
  String pairingCodeExpiresIn(String time);

  /// Shown when a generated code ran out before it was used
  ///
  /// In en, this message translates to:
  /// **'This code expired'**
  String get pairingCodeExpired;

  /// Generic button copying a value to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Generic button opening the system share sheet
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Confirmation after copying the pairing code
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get pairingCodeCopied;

  /// Text shared from the pairing sheet
  ///
  /// In en, this message translates to:
  /// **'Pair with me in ANTA using this code: {code}'**
  String pairingShareMessage(String code);

  /// Label of the code entry field
  ///
  /// In en, this message translates to:
  /// **'Enter their code'**
  String get pairingEnterCode;

  /// Placeholder showing the shape of a pairing code
  ///
  /// In en, this message translates to:
  /// **'XXXX-XXXX'**
  String get pairingCodeHint;

  /// Button redeeming an entered code
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get pairingConnect;

  /// Separator between generating a code and entering one
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get pairingOr;

  /// Button ending the link with a partner
  ///
  /// In en, this message translates to:
  /// **'Unpair'**
  String get unpair;

  /// Body of the unpair confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Stop sharing with {name}? Your notes and events stay on this device. Nothing new will be shared.'**
  String pairingUnpairConfirm(String name);

  /// Title of the dialog shown when the partner unpaired
  ///
  /// In en, this message translates to:
  /// **'Sharing ended'**
  String get pairingEndedTitle;

  /// Body of the dialog shown when a named partner unpaired
  ///
  /// In en, this message translates to:
  /// **'{name} ended sharing. Your notes and events stay on this device.'**
  String pairingEndedBy(String name);

  /// Body shown when the partner unpaired and never published a name
  ///
  /// In en, this message translates to:
  /// **'Your partner ended sharing. Your notes and events stay on this device.'**
  String get pairingEndedByPartner;

  /// Body of the sign-out confirmation shown while paired
  ///
  /// In en, this message translates to:
  /// **'Sign out? Sharing with {name} stops until you sign in again.'**
  String pairingSignOutConfirm(String name);

  /// Body of the sign-out confirmation shown while not paired
  ///
  /// In en, this message translates to:
  /// **'Sign out of this account?'**
  String get signOutConfirm;

  /// Pairing error: the device could not reach the server
  ///
  /// In en, this message translates to:
  /// **'No connection. Pairing needs to be online.'**
  String get pairingErrorOffline;

  /// Pairing error: no account is signed in
  ///
  /// In en, this message translates to:
  /// **'Sign in first'**
  String get pairingErrorNotSignedIn;

  /// Pairing error: unsupported platform or failed Firebase init
  ///
  /// In en, this message translates to:
  /// **'Pairing is not available here'**
  String get pairingErrorUnavailable;

  /// Pairing error: the code was mistyped, expired, or already used
  ///
  /// In en, this message translates to:
  /// **'That code is not valid any more. Ask for a new one.'**
  String get pairingErrorCodeInvalid;

  /// Pairing error: the user entered the code their device generated
  ///
  /// In en, this message translates to:
  /// **'That is your own code'**
  String get pairingErrorOwnCode;

  /// Pairing error: a pair already exists on this database
  ///
  /// In en, this message translates to:
  /// **'You are already paired'**
  String get pairingErrorAlreadyPaired;

  /// Pairing error: the server rejected the request
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get pairingErrorPermissionDenied;

  /// Pairing error: fallback for an unrecognised failure
  ///
  /// In en, this message translates to:
  /// **'Pairing failed'**
  String get pairingErrorUnknown;

  /// Title of the shared colour palette sheet and of the settings row that opens it
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get colorPaletteTitle;

  /// Intro line of the colour palette sheet
  ///
  /// In en, this message translates to:
  /// **'Every color the calendar\'s pickers offer. Colors you add show up in all of them.'**
  String get colorPaletteDesc;

  /// Section label above the swatches that ship with the app
  ///
  /// In en, this message translates to:
  /// **'Built-in colors'**
  String get colorPaletteDefaultsLabel;

  /// Section label above the swatches the user added
  ///
  /// In en, this message translates to:
  /// **'Your colors'**
  String get colorPaletteCustomLabel;

  /// Empty state when the user has added no colours
  ///
  /// In en, this message translates to:
  /// **'No colors of your own yet. Add one and it appears in every picker.'**
  String get colorPaletteEmpty;

  /// Button that removes every colour the user added
  ///
  /// In en, this message translates to:
  /// **'Reset colors'**
  String get colorPaletteReset;

  /// Confirmation for resetting the colour palette
  ///
  /// In en, this message translates to:
  /// **'Delete all the colors you added and keep only the built-in ones?'**
  String get colorPaletteResetConfirm;

  /// Message over the palette sheet after the custom colours were removed
  ///
  /// In en, this message translates to:
  /// **'Palette reset'**
  String get colorPaletteResetDone;

  /// Error shown when the custom colour cap is reached
  ///
  /// In en, this message translates to:
  /// **'Your palette is full. Delete a color to add another.'**
  String get colorPaletteFull;

  /// Error shown when the picked colour duplicates an existing swatch
  ///
  /// In en, this message translates to:
  /// **'That color is already in the palette'**
  String get colorAlreadyInPalette;

  /// How many colours the user added, shown under the palette settings row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No colors of your own} =1{1 color of your own} other{{count} colors of your own}}'**
  String colorPaletteCount(int count);

  /// Opens the colour wheel and adds the picked colour to the palette
  ///
  /// In en, this message translates to:
  /// **'Add color'**
  String get addColor;

  /// Recolours one of the user's own swatches
  ///
  /// In en, this message translates to:
  /// **'Edit color'**
  String get editColor;

  /// Removes one of the user's own swatches from the palette
  ///
  /// In en, this message translates to:
  /// **'Delete color'**
  String get deleteColor;

  /// Confirmation for deleting a custom swatch
  ///
  /// In en, this message translates to:
  /// **'Remove this color from the palette? Anything already using it keeps its color.'**
  String get deleteColorConfirm;

  /// Opens the colour palette sheet from a colour picker row
  ///
  /// In en, this message translates to:
  /// **'Manage colors'**
  String get manageColors;

  /// Label of the hex code field in the colour picker
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get colorHexLabel;

  /// Inline error when the typed hex code is not six valid digits
  ///
  /// In en, this message translates to:
  /// **'Enter a color like #3A7BDE'**
  String get colorHexInvalid;

  /// Tooltip on the button copying the picked colour's hex code
  ///
  /// In en, this message translates to:
  /// **'Copy hex code'**
  String get colorCopyHex;

  /// Snackbar confirming the hex code went to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get colorHexCopied;

  /// Tooltip on the before swatch, which reverts the picker to the colour being replaced
  ///
  /// In en, this message translates to:
  /// **'Current color, tap to restore'**
  String get colorPickerCurrent;

  /// Tooltip on the after swatch, showing what Select would return
  ///
  /// In en, this message translates to:
  /// **'New color'**
  String get colorPickerNew;

  /// Accessibility label of the hue slider
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get colorHue;

  /// Accessibility label of the colour picker's square
  ///
  /// In en, this message translates to:
  /// **'Saturation and brightness'**
  String get colorSaturationBrightness;

  /// Accessibility value read out for the colour picker's square
  ///
  /// In en, this message translates to:
  /// **'Saturation {saturation}%, brightness {brightness}%'**
  String colorSaturationBrightnessValue(int saturation, int brightness);

  /// Tooltip on the drag handle of a custom colour row
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get colorReorder;

  /// How many custom colours are used against the maximum
  ///
  /// In en, this message translates to:
  /// **'{count} of {max}'**
  String colorPaletteCapCount(int count, int max);

  /// Name of the saturation/brightness square geometry in the colour picker
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get colorModeSquare;

  /// Name of the hue/saturation wheel geometry in the colour picker
  ///
  /// In en, this message translates to:
  /// **'Wheel'**
  String get colorModeWheel;

  /// Accessibility label of the brightness slider in wheel mode
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get colorBrightness;

  /// Accessibility label of the colour picker's wheel
  ///
  /// In en, this message translates to:
  /// **'Hue and saturation'**
  String get colorHueSaturation;

  /// Accessibility value read out for the colour picker's wheel
  ///
  /// In en, this message translates to:
  /// **'Hue {hue}°, saturation {saturation}%'**
  String colorHueSaturationValue(int hue, int saturation);

  /// Expands a colour row that is showing only its first few rows of swatches
  ///
  /// In en, this message translates to:
  /// **'Show {count} more colors'**
  String colorShowAll(int count);

  /// Tooltip on the swatch meaning: use the colour of the chosen category
  ///
  /// In en, this message translates to:
  /// **'Category color'**
  String get eventColorCategoryDefault;

  /// Drill-down sheet mode: one grouped, dated list of every entry
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get dayListModeList;

  /// Drill-down sheet mode: a mini month calendar with that month's entries below it
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get dayListModeMonth;

  /// Drill-down sheet mode: one tile per month of the window
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get dayListModeYear;

  /// Tooltip of the back arrow returning from a month opened out of the year overview
  ///
  /// In en, this message translates to:
  /// **'Back to months'**
  String get dayListBackToYear;

  /// Clears the selected day in the drill-down's month mode and lists the whole month again
  ///
  /// In en, this message translates to:
  /// **'Whole month'**
  String get dayListWholeMonth;

  /// Empty state of the drill-down's month mode
  ///
  /// In en, this message translates to:
  /// **'Nothing this month'**
  String get dayListEmptyMonth;

  /// Empty state of the drill-down's list mode when no day has entries
  ///
  /// In en, this message translates to:
  /// **'Nothing in this range'**
  String get dayListEmptyRange;

  /// Title of the in-app placeholder shown where a widget failed to build
  ///
  /// In en, this message translates to:
  /// **'This part of the screen could not be drawn'**
  String get renderErrorTitle;

  /// Body of the in-app placeholder shown where a widget failed to build
  ///
  /// In en, this message translates to:
  /// **'Drag down or go back to close. Details: {error}'**
  String renderErrorDetail(String error);

  /// Tooltip of the drill-down month navigation's left chevron
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get dayListPreviousMonth;

  /// Tooltip of the drill-down month navigation's right chevron
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get dayListNextMonth;

  /// Year overview scope: the months of the agenda window the card counted
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get dayListScopeUpcoming;

  /// Tooltip of the button returning a year overview to the current year
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get dayListScopeThisYear;

  /// Year overview scope: the twelve calendar months of one year, paged year by year with the chevrons under it
  ///
  /// In en, this message translates to:
  /// **'Calendar year'**
  String get dayListScopeCalendarYear;

  /// Title of the calendar overview page (events by category across whole years), also the drawer row and the view menu row opening it
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get calendarOverview;

  /// Subtitle of the drawer row opening the calendar overview page
  ///
  /// In en, this message translates to:
  /// **'Events by category, year by year'**
  String get calendarOverviewDesc;

  /// Tooltip of the calendar's and the overview's app-bar title, which opens the menu switching between the two pages and between the grid's month, two-week and week views
  ///
  /// In en, this message translates to:
  /// **'Switch view'**
  String get calendarViewMenuTooltip;

  /// Label of the overview page's row choosing which event categories it shows
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get overviewCategories;

  /// Label of the overview list's row choosing the span of days it lists, and the title of the picker choosing a custom span
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get overviewPeriod;

  /// Overview list period: the calendar week holding today, starting on the calendar's first weekday
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get overviewPeriodThisWeek;

  /// Overview list period: the calendar month holding today, from its 1st to its last day
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get overviewPeriodThisMonth;

  /// Overview list period: the twelve months ending today
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get overviewPeriodLast12Months;

  /// Overview list period: the ninety days ending today
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get overviewPeriodLast90Days;

  /// Overview list period: from the first year any event falls in up to today
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get overviewPeriodAllTime;

  /// Tooltip of the overview list nav's left chevron, which shows the span of the same length just before the one listed
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get overviewPeriodPrevious;

  /// Tooltip of the overview list nav's right chevron, which shows the span of the same length just after the one listed
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get overviewPeriodNext;

  /// Tooltip of the overview list nav's today button, which returns from a stepped span to the period last picked
  ///
  /// In en, this message translates to:
  /// **'Back to {period}'**
  String overviewPeriodHome(String period);

  /// One category's entry count in the overview's totals caption, e.g. 'Gym 41'; several are joined with ' · '
  ///
  /// In en, this message translates to:
  /// **'{label} {count}'**
  String overviewCategoryTotal(String label, int count);

  /// Tooltip of the overview list's options button and the title of the sheet it opens
  ///
  /// In en, this message translates to:
  /// **'List options'**
  String get overviewListOptions;

  /// Label of the overview list options' row choosing which end of the period the list starts from
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get overviewOrder;

  /// Overview list order: earliest day at the top
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get overviewOrderOldestFirst;

  /// Overview list order: latest day at the top
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get overviewOrderNewestFirst;

  /// Label of the overview list options' row choosing whether a recurring event lists every occurrence or one row
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get overviewRows;

  /// Overview list rows: one row per occurrence of a recurring event
  ///
  /// In en, this message translates to:
  /// **'Every occurrence'**
  String get overviewRowsEveryOccurrence;

  /// Overview list rows: one row standing for all of an event's occurrences in the period
  ///
  /// In en, this message translates to:
  /// **'One per event'**
  String get overviewRowsPerEvent;

  /// Switch in the overview list options keeping only the occurrences marked missed
  ///
  /// In en, this message translates to:
  /// **'Missed only'**
  String get overviewMissedOnly;

  /// Title of the overview's saved views sheet and tooltip of its app-bar button; a view is a saved period, list options and categories
  ///
  /// In en, this message translates to:
  /// **'Saved views'**
  String get overviewViewsTitle;

  /// Row in the saved views sheet, and the naming dialog's title, that saves the overview list as shown
  ///
  /// In en, this message translates to:
  /// **'Save the current list'**
  String get overviewViewSaveCurrent;

  /// Confirmation after saving the overview list as a view
  ///
  /// In en, this message translates to:
  /// **'Saved as \"{name}\"'**
  String overviewViewSaved(String name);

  /// Saved view menu action: re-point the view at the list the overview shows now
  ///
  /// In en, this message translates to:
  /// **'Update to current list'**
  String get overviewViewUpdate;

  /// Title of the confirmation for deleting a saved overview view
  ///
  /// In en, this message translates to:
  /// **'Delete saved view'**
  String get overviewViewDelete;

  /// Confirmation body for deleting a saved overview view
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? The events it lists are untouched.'**
  String overviewViewDeleteConfirm(String name);

  /// Tooltip of a saved view row's more button
  ///
  /// In en, this message translates to:
  /// **'Saved view options'**
  String get overviewViewActions;

  /// Shown when the saved view limit is reached
  ///
  /// In en, this message translates to:
  /// **'You can save up to {count} views'**
  String overviewViewLimitReached(int count);

  /// Hint of the saved views sheet's search field
  ///
  /// In en, this message translates to:
  /// **'Search saved views'**
  String get overviewViewSearchHint;

  /// Shown in the saved views sheet when the search matches nothing
  ///
  /// In en, this message translates to:
  /// **'No saved view matches your search'**
  String get overviewViewNoMatches;

  /// Empty state of the overview list when the chosen period holds no entry
  ///
  /// In en, this message translates to:
  /// **'Nothing in this period'**
  String get overviewEmptyPeriod;

  /// Caption at the end of the overview list while the rest of a long period is still being resolved
  ///
  /// In en, this message translates to:
  /// **'Loading more…'**
  String get overviewLoading;

  /// Caption at the end of the overview list when a long period holds more entries than the list shows
  ///
  /// In en, this message translates to:
  /// **'Showing the first {count} entries. Narrow the period to see the rest.'**
  String overviewCapReached(int count);

  /// How many events a category group of the overview list holds
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 event} other {{count} events}}'**
  String overviewEventCount(int count);

  /// The first and last day an event occurs on within the overview list's period
  ///
  /// In en, this message translates to:
  /// **'{first} – {last}'**
  String overviewEventSpan(String first, String last);

  /// Accessibility label of the overview list's month scrubber along its right edge
  ///
  /// In en, this message translates to:
  /// **'Scroll by month'**
  String get overviewScrubberLabel;

  /// Accessibility label of the overview's year scrubber along the right edge of the years scroll
  ///
  /// In en, this message translates to:
  /// **'Scroll by year'**
  String get overviewYearScrubberLabel;

  /// Confirm button of the date picker when it picks a span of days
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get datePickerApply;

  /// Summary of the date picker's span mode before any day is picked
  ///
  /// In en, this message translates to:
  /// **'Pick a start day'**
  String get datePickerRangeNone;

  /// Tooltip of the drill-down month navigation's button returning to the current month
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get dayListJumpToToday;

  /// Suffix after the drill-down's entry count, naming how many of the month's or day's occurrences were marked missed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 missed} other {{count} missed}}'**
  String dayListMissedCount(int count);

  /// Accessibility label of the editor tap zone over a task list checkbox
  ///
  /// In en, this message translates to:
  /// **'Toggle task'**
  String get editorZoneToggleTask;

  /// Accessibility label of the editor tap zone over a markdown link
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get editorZoneOpenLink;

  /// Accessibility label of the editor tap zone over a money row's chip
  ///
  /// In en, this message translates to:
  /// **'Open ledger details'**
  String get editorZoneOpenMoney;

  /// Accessibility label of the editor tap zone over a #tag
  ///
  /// In en, this message translates to:
  /// **'Search tag'**
  String get editorZoneSearchTag;

  /// Accessibility label of the editor tap zone over a [[wiki link]] to another note
  ///
  /// In en, this message translates to:
  /// **'Open linked note'**
  String get editorZoneOpenWikiLink;

  /// Accessibility label of the editor tap zone over a task list checkbox, naming the task's text
  ///
  /// In en, this message translates to:
  /// **'Toggle task: {task}'**
  String editorZoneToggleTaskNamed(String task);

  /// Accessibility label of the editor tap zone over a markdown link, naming the link's text
  ///
  /// In en, this message translates to:
  /// **'Open link: {link}'**
  String editorZoneOpenLinkNamed(String link);

  /// Accessibility label of the editor tap zone over a [[wiki link]], naming the linked note
  ///
  /// In en, this message translates to:
  /// **'Open linked note: {note}'**
  String editorZoneOpenWikiLinkNamed(String note);

  /// Accessibility label of the editor tap zone over a #tag, naming the tag
  ///
  /// In en, this message translates to:
  /// **'Search tag: {tag}'**
  String editorZoneSearchTagNamed(String tag);

  /// Accessibility action on the browser's back button, and hint on the parent name above the folder title, that lists every folder above this one
  ///
  /// In en, this message translates to:
  /// **'Show parent folders'**
  String get showAncestors;

  /// Row action-sheet header and colour-label picker title
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get labelAction;

  /// Bottom-bar action label to colour-label all selected items
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get labelSelected;

  /// Picker swatch that clears the colour label of a note or folder
  ///
  /// In en, this message translates to:
  /// **'No label'**
  String get labelNone;

  /// Name of the red colour label
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get labelRed;

  /// Name of the orange colour label
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get labelOrange;

  /// Name of the yellow colour label
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get labelYellow;

  /// Name of the green colour label
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get labelGreen;

  /// Name of the teal colour label
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get labelTeal;

  /// Name of the blue colour label
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get labelBlue;

  /// Name of the pink colour label
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get labelPink;

  /// Accessibility name of the colour-label dot on a browser row
  ///
  /// In en, this message translates to:
  /// **'{color} label'**
  String labelSemantics(String color);

  /// Settings row choosing how a colour label is drawn on a row
  ///
  /// In en, this message translates to:
  /// **'Label style'**
  String get labelStyle;

  /// Description of the label style setting
  ///
  /// In en, this message translates to:
  /// **'How a labelled note or folder shows its colour in the list'**
  String get labelStyleDesc;

  /// Label style option: a dot at the row's trailing edge
  ///
  /// In en, this message translates to:
  /// **'Dot'**
  String get labelStyleDot;

  /// Label style option: a stripe on the row's leading edge
  ///
  /// In en, this message translates to:
  /// **'Edge stripe'**
  String get labelStyleStripe;

  /// Hidden search keywords for the label style setting
  ///
  /// In en, this message translates to:
  /// **'colour, color, label, dot, stripe, edge, marker'**
  String get labelStyleKeywords;

  /// Search results section header when colour-label chips are filtering and nothing is typed: the selected colour names, then how many notes carry them
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{names} · 1 note} other{{names} · {count} notes}}'**
  String labelledNotesHeader(int count, String names);

  /// Alarm shown as the eyebrow of the full-screen ring page
  ///
  /// In en, this message translates to:
  /// **'Alarm'**
  String get alarmPageTitle;

  /// What a test ring is called where an event's title would be: on the full-screen ring page and as the title of the ring's notification
  ///
  /// In en, this message translates to:
  /// **'Test alarm'**
  String get alarmTestTitle;

  /// Primary action on the alarm page and on the alarm notification: stop the ring
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get alarmStop;

  /// Snooze, wherever an alert offers it: the alarm page's second button, and the second action of the ring's notification (after Stop) and of a reminder's (after Done). Puts the alert off by the configured number of minutes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Snooze 1 min} other{Snooze {count} min}}'**
  String alarmSnoozeMinutes(int count);

  /// Alarm page action: stop ringing and open the event in the calendar. Also the session chip's second action, after Done, when the event has no linked note: open the event
  ///
  /// In en, this message translates to:
  /// **'Open event'**
  String get alarmOpenEvent;

  /// Alarm page button beside the line saying Stop also removes the event: keep the event instead. Short, because it shares a row with that line
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get alarmKeep;

  /// Accessible name of the alarm page's Keep button, for an event set to be removed after it rings: keep it instead
  ///
  /// In en, this message translates to:
  /// **'Keep the event'**
  String get alarmKeepEvent;

  /// Alarm page line that replaces the removal warning once Keep has been saved
  ///
  /// In en, this message translates to:
  /// **'The event will be kept'**
  String get alarmKeptEvent;

  /// Alarm page line directly above the Stop button, for an event set to be removed after it rings. Stop is the alarmStop button's label
  ///
  /// In en, this message translates to:
  /// **'Stop also removes this event'**
  String get alarmRemoveAfterCaption;

  /// Alarm page action when the alarm belongs to a database that is not the open one: make that database the open one
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String alarmSwitchDatabase(String name);

  /// Title of the dialog shown after the alarm page switched to the alarm's database
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}'**
  String alarmDatabaseSwitchedTitle(String name);

  /// Body of the dialog shown after the alarm page switched to the alarm's database. Its one button closes the app
  ///
  /// In en, this message translates to:
  /// **'Exit ANTA and open it again to see this event. The alarm keeps ringing until you stop it.'**
  String get alarmDatabaseSwitchedBody;

  /// Calendar settings section holding reminder and alarm options
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get calendarAlertsSection;

  /// Permission row: whether the app may post notifications at all
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get alertsNotifications;

  /// Description of the notification permission row. Reminders: same word as eventAlertModeNotify, in the plural
  ///
  /// In en, this message translates to:
  /// **'Needed for reminders and alarms to show'**
  String get alertsNotificationsDesc;

  /// Permission row: whether an alarm may take over a locked screen
  ///
  /// In en, this message translates to:
  /// **'Full-screen alarms'**
  String get alertsFullScreenAlarms;

  /// Description of the full-screen alarm permission row
  ///
  /// In en, this message translates to:
  /// **'Lets an alarm take over a locked screen'**
  String get alertsFullScreenAlarmsDesc;

  /// Permission row: whether the system exempts the app from battery optimisation
  ///
  /// In en, this message translates to:
  /// **'Unrestricted battery'**
  String get alertsBattery;

  /// Description of the battery optimisation row
  ///
  /// In en, this message translates to:
  /// **'Battery limits can delay or drop an alarm'**
  String get alertsBatteryDesc;

  /// Status chip on a permission row when the permission is held
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get alertsPermissionOn;

  /// Status chip on a permission row when the permission is missing
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get alertsPermissionOff;

  /// Action on a permission row that raises the system prompt
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get alertsTurnOn;

  /// Action on a permission row that opens the matching system settings page
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get alertsOpenSettings;

  /// Slider: how long Snooze postpones an alert
  ///
  /// In en, this message translates to:
  /// **'Snooze length'**
  String get alertsSnoozeLength;

  /// Caption under the snooze length slider
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Snooze postpones an alert by 1 minute} other{Snooze postpones an alert by {count} minutes}}'**
  String alertsSnoozeLengthDesc(int count);

  /// Slider: how long an unanswered alarm keeps ringing
  ///
  /// In en, this message translates to:
  /// **'Silence after'**
  String get alertsSilenceAfter;

  /// Caption under the silence-after slider
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{An unanswered alarm stops after 1 minute} other{An unanswered alarm stops after {count} minutes}}'**
  String alertsSilenceAfterDesc(int count);

  /// Title of the slider that sets how far ahead of an alarm its quiet notice is posted
  ///
  /// In en, this message translates to:
  /// **'Upcoming alarm notice'**
  String get alertsNoticeLead;

  /// Caption under the upcoming-alarm notice slider
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A quiet notice 1 minute before an alarm, with Skip and Open} other{A quiet notice {count} minutes before an alarm, with Skip and Open}}'**
  String alertsNoticeLeadDesc(int count);

  /// Caption under the upcoming-alarm notice slider when it is at zero
  ///
  /// In en, this message translates to:
  /// **'Off — no notice before an alarm'**
  String get alertsNoticeLeadOff;

  /// Caption under the upcoming-alarm notice slider when its minutes are whole hours, from 60 up
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A quiet notice 1 hour before an alarm, with Skip and Open} other{A quiet notice {count} hours before an alarm, with Skip and Open}}'**
  String alertsNoticeLeadHours(int count);

  /// Text line of the quiet notice posted ahead of an alarm, under the event's title. The time is the alarm's own, followed by its day (alertsWhenOnDay) when the alarm is not due on the day the notice is posted
  ///
  /// In en, this message translates to:
  /// **'Alarm at {time}'**
  String alertsUpcomingTitle(String time);

  /// Text line of an alert's notification, under the event's title: what it is — Alarm (eventAlertModeRing), Reminder (eventAlertModeNotify), Snoozed (alertsOutcomeSnoozed) or Missed (alertsOutcomeMissed) — and the time it is about
  ///
  /// In en, this message translates to:
  /// **'{kind} · {when}'**
  String alertsKindWhen(String kind, String when);

  /// The time on the quiet notice posted ahead of an alarm, when the alarm is not due on the day the notice is posted: the alarm's own time followed by its day, inside alertsUpcomingTitle (Alarm at 7:00 AM, Mon, Sep 21). day is the alarm's date as a short weekday, month and day (DateFormat.MMMEd). An event's own time on another day is alertsDayThenWhen
  ///
  /// In en, this message translates to:
  /// **'{when}, {day}'**
  String alertsWhenOnDay(String when, String day);

  /// An event's own time on an alert that comes on another day than the event, such as one set a day ahead: the event's day first, then its time. The text line of a reminder's or an alarm's notification, after the kind (alertsKindWhen), and the line under the event's title on the alarm page. The day leads because a notification's text is one line beside its icon and the phone cuts the end of it: written after the time, the day was lost and the time read as today's. day is the event's date as a short weekday, month and day (DateFormat.MMMEd); when is the event's own time: a range, a single time, or All day (eventAllDay)
  ///
  /// In en, this message translates to:
  /// **'{day} · {when}'**
  String alertsDayThenWhen(String day, String when);

  /// Upcoming-alarm notice action: skip this one fire of the alarm
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get alertsSkipAction;

  /// Upcoming-alarm notice action: open the event
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get alertsOpenAction;

  /// Session chip body when the event has no end time; the chip's clock counts the elapsed time
  ///
  /// In en, this message translates to:
  /// **'Session in progress'**
  String get alertsSessionInProgress;

  /// Session chip body when the event has an end time
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String alertsSessionUntil(String time);

  /// Session chip's second action, after Done, when the event has a linked note: open that note. Without one the action reads alarmOpenEvent
  ///
  /// In en, this message translates to:
  /// **'Open note'**
  String get alertsSessionOpenNote;

  /// Snackbar after a notice's Skip was applied; carries Undo
  ///
  /// In en, this message translates to:
  /// **'Skipped {title}'**
  String alertsSkippedSnack(String title);

  /// Alerts hub section header over the alarms that rang, were stopped, snoozed or missed in the last week
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get alertsRecent;

  /// Title of a Recent row whose event no longer exists
  ///
  /// In en, this message translates to:
  /// **'Removed event'**
  String get alertsHistoryRemoved;

  /// Recent row outcome: the alarm rang and ended on its own
  ///
  /// In en, this message translates to:
  /// **'Rang'**
  String get alertsOutcomeRang;

  /// Recent row outcome: the alarm was stopped
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get alertsOutcomeStopped;

  /// Recent row outcome: the alert was snoozed. Also the kind word in the text of a snoozed reminder's notification (alertsKindWhen), and the second half of the alarm page's eyebrow on a re-ring, after alarmPageTitle and drawn in capitals (ALARM · SNOOZED). Where the language has gender it agrees with the words for alarm and reminder
  ///
  /// In en, this message translates to:
  /// **'Snoozed'**
  String get alertsOutcomeSnoozed;

  /// Recent row outcome: the alarm was missed. Also the kind word in the text of the Missed notification (alertsKindWhen); it describes the alarm, not the event
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get alertsOutcomeMissed;

  /// Recent row outcome: the reminder notification was delivered
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get alertsOutcomeDelivered;

  /// Note under the alert settings explaining that a force stop cancels pending alarms
  ///
  /// In en, this message translates to:
  /// **'Force stopping ANTA disarms every alarm until you open it again.'**
  String get alertsForceStopNote;

  /// Alert settings button that schedules a ring ten seconds from now. The ring itself is titled alarmTestTitle, on its page and on its notification
  ///
  /// In en, this message translates to:
  /// **'Test alarm in 10 s'**
  String get alertsTestAlarm;

  /// Confirmation after the test alarm was scheduled
  ///
  /// In en, this message translates to:
  /// **'Test alarm set for 10 seconds from now'**
  String get alertsTestAlarmScheduled;

  /// Error shown when the platform refused the test alarm
  ///
  /// In en, this message translates to:
  /// **'The alarm could not be scheduled'**
  String get alertsTestAlarmFailed;

  /// Android notification channel name for the reminder tier. Same word as eventAlertModeNotify, in the plural: the notifications on this channel print that word
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get alertsReminderChannel;

  /// Android notification channel description for the reminder tier. Reminders: same word as eventAlertModeNotify, in the plural
  ///
  /// In en, this message translates to:
  /// **'Event reminders you can snooze or dismiss'**
  String get alertsReminderChannelDesc;

  /// Android notification channel name for the alarm tier
  ///
  /// In en, this message translates to:
  /// **'Alarms'**
  String get alertsAlarmChannel;

  /// Android notification channel description for the alarm tier
  ///
  /// In en, this message translates to:
  /// **'Event alarms that ring until stopped'**
  String get alertsAlarmChannelDesc;

  /// Android notification channel name for the three notifications that never make a sound: the notice posted ahead of an alarm, the notice of a missed alarm, and the session in progress. Read in the phone's own notification settings, beside Reminders and Alarms
  ///
  /// In en, this message translates to:
  /// **'Quiet notices'**
  String get alertsQuietChannel;

  /// Android notification channel description for the quiet channel (alertsQuietChannel)
  ///
  /// In en, this message translates to:
  /// **'Notices of upcoming and missed alarms and the session in progress, always silent'**
  String get alertsQuietChannelDesc;

  /// Android notification channel name for digests: one notification on a schedule that lists the events of a coming day, week or month. Read in the phone's own notification settings, beside Reminders, Alarms and Quiet notices
  ///
  /// In en, this message translates to:
  /// **'Digests'**
  String get alertsDigestChannel;

  /// Android notification channel description for the digest channel (alertsDigestChannel)
  ///
  /// In en, this message translates to:
  /// **'Bundled summaries of upcoming events'**
  String get alertsDigestChannelDesc;

  /// Title of a digest notification that has no name of its own and lists every category
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get digestAllCategories;

  /// Title of a digest notification that has no name of its own and lists several categories
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 category} other{{count} categories}}'**
  String digestCategoriesCount(int count);

  /// Text of a digest notification: how many events the span holds and which span. period is one of digestPeriodToday … digestPeriodNextMonth, or a date range such as '4 Nov – 10 Nov'
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No events {period}} one{1 event {period}} other{{count} events {period}}}'**
  String digestCountPeriod(int count, String period);

  /// The span of a daily digest that lists the day it fires on, inside digestCountPeriod (3 events today)
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get digestPeriodToday;

  /// The span of a daily digest that lists the day after it fires, inside digestCountPeriod (3 events tomorrow)
  ///
  /// In en, this message translates to:
  /// **'tomorrow'**
  String get digestPeriodTomorrow;

  /// The span of a weekly digest that lists the calendar week it fires in, inside digestCountPeriod (3 events this week)
  ///
  /// In en, this message translates to:
  /// **'this week'**
  String get digestPeriodThisWeek;

  /// The span of a weekly digest that lists the calendar week after it fires, inside digestCountPeriod (3 events next week)
  ///
  /// In en, this message translates to:
  /// **'next week'**
  String get digestPeriodNextWeek;

  /// The span of a monthly digest that lists the calendar month it fires in, inside digestCountPeriod (3 events this month)
  ///
  /// In en, this message translates to:
  /// **'this month'**
  String get digestPeriodThisMonth;

  /// The span of a monthly digest that lists the calendar month after it fires, inside digestCountPeriod (3 events next month)
  ///
  /// In en, this message translates to:
  /// **'next month'**
  String get digestPeriodNextMonth;

  /// The span of a digest that no calendar word names (a week from Wednesday, a month from the 15th), inside digestCountPeriod (3 events from Nov 4 to Nov 10). start and end are dates without a weekday
  ///
  /// In en, this message translates to:
  /// **'from {start} to {end}'**
  String digestPeriodSpan(String start, String end);

  /// Last line of an expanded digest notification: how many events the span holds beyond the five it lists
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{+1 more} other{+{count} more}}'**
  String digestMoreCount(int count);

  /// Last row of the Alerts hub's Digests group: opens the digest sheet on a new digest
  ///
  /// In en, this message translates to:
  /// **'Add digest'**
  String get digestsAdd;

  /// Title of the digest sheet when it creates a digest
  ///
  /// In en, this message translates to:
  /// **'New digest'**
  String get digestNew;

  /// Title of the digest sheet when it edits an existing digest
  ///
  /// In en, this message translates to:
  /// **'Edit digest'**
  String get digestEdit;

  /// Digest sheet row label for what a digest lists: what is coming up, or the report of the week or month that just ended (Shows · Upcoming)
  ///
  /// In en, this message translates to:
  /// **'Shows'**
  String get digestShows;

  /// Shows row value: the digest lists the events coming up in its span, from the day it fires
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get digestShowsUpcoming;

  /// Shows row value: the digest is the report of the calendar week that ended before it fires
  ///
  /// In en, this message translates to:
  /// **'The week just ended'**
  String get digestShowsWeekReport;

  /// Shows row value: the digest is the report of the calendar month that ended before it fires
  ///
  /// In en, this message translates to:
  /// **'The month just ended'**
  String get digestShowsMonthReport;

  /// Digest sheet row label for the cadence; its value is Day, Week or Month (Every · Month)
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get digestEvery;

  /// Digest sheet row label for the day a digest fires on; its value is a weekday (On · Monday) or a day of the month (On · the 1st)
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get digestOn;

  /// A monthly digest's day of the month (1 to 28, written as digits) in its bare form, as the On row's value (On · 1st) and inside digestDescribeMonthly (Monthly on the 1st, 09:00). A select on the digits, so each language writes its own ordinal: German '1.', Romanian '1'
  ///
  /// In en, this message translates to:
  /// **'{day, select, 1{1st} 2{2nd} 3{3rd} 21{21st} 22{22nd} 23{23rd} other{{day}th}}'**
  String digestOnDayOfMonth(String day);

  /// Digest sheet row label for the time a digest fires at (At · 09:00), and the title of the time pad it opens
  ///
  /// In en, this message translates to:
  /// **'At'**
  String get digestAt;

  /// Digest sheet row label for which span a digest lists: from the day it fires or from the next day
  ///
  /// In en, this message translates to:
  /// **'Covers'**
  String get digestCovers;

  /// Covers row value: the digest lists a span that starts on the day it fires (this month, this week, today)
  ///
  /// In en, this message translates to:
  /// **'From that day'**
  String get digestCoversSameDay;

  /// Covers row value: the digest lists a span that starts the day after it fires (next week from a Sunday evening, tomorrow)
  ///
  /// In en, this message translates to:
  /// **'From the next day'**
  String get digestCoversNextDay;

  /// Digest sheet switch: the digest still arrives when its span lists no events
  ///
  /// In en, this message translates to:
  /// **'Also when empty'**
  String get digestIncludeEmpty;

  /// Second line of the Also when empty switch (digestIncludeEmpty)
  ///
  /// In en, this message translates to:
  /// **'Send it when nothing is due'**
  String get digestIncludeEmptyDesc;

  /// Caption under the digest sheet's rows: when the digest as drafted next arrives and what it would say. when is a day and a time (Sat 1 Nov 09:00); count is digestCountPeriod (3 events this month)
  ///
  /// In en, this message translates to:
  /// **'Next: {when} · {count}'**
  String digestNext(String when, String count);

  /// Caption under the digest sheet's rows when the digest as drafted would send nothing in its next twelve fires (its spans list no events and Also when empty is off)
  ///
  /// In en, this message translates to:
  /// **'Nothing to send yet'**
  String get digestNextNone;

  /// Caption of a digest row in the Alerts hub whose settings this version cannot read; its switch is disabled and it does not open
  ///
  /// In en, this message translates to:
  /// **'Saved by a newer version of the app'**
  String get digestUnreadable;

  /// End of a digest's caption in the Alerts hub, after digestDescribe*: the day it next arrives (Monthly on the 1st, 09:00 · next Sat 1 Nov)
  ///
  /// In en, this message translates to:
  /// **'next {when}'**
  String digestNextFire(String when);

  /// End of an enabled digest's caption in the Alerts hub, after digestDescribe*, when the database holds more digests than can fire and this one is past the limit (Weekly on Monday, 09:00 · not armed, 10 digests at most)
  ///
  /// In en, this message translates to:
  /// **'not armed, {count} digests at most'**
  String digestOverLimit(int count);

  /// Destructive row at the end of the digest sheet when it edits a digest, and the title of its confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete digest'**
  String get digestDelete;

  /// Text of the confirmation before a digest is deleted; the events it lists are not touched
  ///
  /// In en, this message translates to:
  /// **'Delete this digest?'**
  String get digestDeleteConfirm;

  /// Shown on the digest sheet's Save when the digest limit is reached
  ///
  /// In en, this message translates to:
  /// **'You can keep up to {count} digests'**
  String digestLimitReached(int count);

  /// How a daily digest fires, the first line of its caption in the Alerts hub
  ///
  /// In en, this message translates to:
  /// **'Daily at {time}'**
  String digestDescribeDaily(String time);

  /// How a weekly digest fires. weekday is a full weekday name as intl writes it inside a sentence
  ///
  /// In en, this message translates to:
  /// **'Weekly on {weekday}, {time}'**
  String digestDescribeWeekly(String weekday, String time);

  /// How a monthly digest fires. day is digestOnDayOfMonth (1st)
  ///
  /// In en, this message translates to:
  /// **'Monthly on the {day}, {time}'**
  String digestDescribeMonthly(String day, String time);

  /// How a weekly report digest fires (it sums up the week that just ended). weekday is a full weekday name as intl writes it inside a sentence
  ///
  /// In en, this message translates to:
  /// **'Weekly report on {weekday}, {time}'**
  String digestDescribeWeeklyReport(String weekday, String time);

  /// How a monthly report digest fires (it sums up the month that just ended). day is digestOnDayOfMonth (1st)
  ///
  /// In en, this message translates to:
  /// **'Monthly report on the {day}, {time}'**
  String digestDescribeMonthlyReport(String day, String time);

  /// Opens the title of a weekly report notification, before the categories it covers (Weekly report · Gym)
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get digestReportWeeklyTitle;

  /// Opens the title of a monthly report notification, before the categories it covers (Monthly report · Birthday)
  ///
  /// In en, this message translates to:
  /// **'Monthly report'**
  String get digestReportMonthlyTitle;

  /// The span of a weekly report digest: the calendar week that ended before it fires, inside digestCountPeriod (5 events last week) — lowercase, mid-sentence
  ///
  /// In en, this message translates to:
  /// **'last week'**
  String get digestPeriodLastWeek;

  /// The span of a monthly report digest: the calendar month that ended before it fires, inside digestCountPeriod (5 events last month) — lowercase, mid-sentence
  ///
  /// In en, this message translates to:
  /// **'last month'**
  String get digestPeriodLastMonth;

  /// The whole body of a weekly report notification armed before the week had ended, so its numbers were not known yet
  ///
  /// In en, this message translates to:
  /// **'Last week\'s report is ready'**
  String get digestReportReadyWeek;

  /// The whole body of a monthly report notification armed before the month had ended, so its numbers were not known yet
  ///
  /// In en, this message translates to:
  /// **'Last month\'s report is ready'**
  String get digestReportReadyMonth;

  /// The first line of a report notification: the categories it covers, then its facts joined by middle dots (Gym, Cardio — 5 of 6 attended · 6 h · 1 missed)
  ///
  /// In en, this message translates to:
  /// **'{categories} — {facts}'**
  String digestReportSummary(String categories, String facts);

  /// Opens the goals line of a report notification, before up to three goals joined by middle dots (Goals · Gym 3 of 3 ✓ · Work 42 h (over 40))
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get reportDigestGoalsLead;

  /// Opens the due-soon line of a report notification, before up to two events joined by middle dots (Due · Dentist in 18 days · Rent not marked)
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get reportDigestDueLead;

  /// One met goal in a report notification's goals line: the category, its value and the target, then a check mark
  ///
  /// In en, this message translates to:
  /// **'{name} {value} of {target} ✓'**
  String reportDigestGoalMet(String name, String value, String target);

  /// One at-most or budget goal past its target in a report notification's goals line: the category, its value, then the target it went over
  ///
  /// In en, this message translates to:
  /// **'{name} {value} (over {target})'**
  String reportDigestGoalOver(String name, String value, String target);

  /// One goal neither met nor over in a report notification's goals line: the category, its value and the target
  ///
  /// In en, this message translates to:
  /// **'{name} {value} of {target}'**
  String reportDigestGoalPace(String name, String value, String target);

  /// One most-days-between goal in a report notification's goals line: the category, the time since it last happened (reportGoalGapDays, lowercase), then in brackets the most days allowed as the goal card words it (reportGoalLimit)
  ///
  /// In en, this message translates to:
  /// **'{name} {since} ({limit})'**
  String reportDigestGoalGap(String name, String since, String limit);

  /// One goal in a report notification's goals line when the report spans several of its periods: the category, then how many periods met it (reportGoalPeriodsMet); also the category then its state word (reportGoalStateNotStarted) for a goal with no period yet
  ///
  /// In en, this message translates to:
  /// **'{name} {periods}'**
  String reportDigestGoalPeriods(String name, String periods);

  /// One event in a report notification's due-soon line: its title, then when it is due or that it is not marked (in 18 days, overdue 32 days, not marked)
  ///
  /// In en, this message translates to:
  /// **'{title} {phrase}'**
  String reportDigestDueItem(String title, String phrase);

  /// First action of a reminder's notification, which takes the reminder down; and first action of the session chip, which ends the session and takes the chip down. Snooze, or Open note, follows it
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get alertsDoneAction;

  /// Section label above the alert rows in the event editor
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get eventAlerts;

  /// Chip that adds another alert to the event
  ///
  /// In en, this message translates to:
  /// **'Add alert'**
  String get eventAlertAdd;

  /// Removes one alert from the event
  ///
  /// In en, this message translates to:
  /// **'Remove alert'**
  String get eventAlertRemove;

  /// Switch deleting the event once its alarm is acknowledged
  ///
  /// In en, this message translates to:
  /// **'Remove after it rings'**
  String get eventAlertRemoveAfter;

  /// Hint under the remove-after-it-rings switch
  ///
  /// In en, this message translates to:
  /// **'The event is deleted once you stop the alarm. Undo is offered right after.'**
  String get eventAlertRemoveAfterHint;

  /// Title of the sheet that edits one alert
  ///
  /// In en, this message translates to:
  /// **'Alert'**
  String get eventAlert;

  /// Section label above the reminder/alarm choice
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get eventAlertTypeSection;

  /// The quieter alert tier: a notification. Also the kind word in a reminder's notification text (alertsKindWhen), and that notification's title when the event has none
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get eventAlertModeNotify;

  /// The loud alert tier: rings until stopped. Also the kind word in the ring's notification text (alertsKindWhen), and the title an untitled event's alarm takes on the alarm page and on its notifications
  ///
  /// In en, this message translates to:
  /// **'Alarm'**
  String get eventAlertModeRing;

  /// Hint under the type control while Reminder is picked
  ///
  /// In en, this message translates to:
  /// **'Sits in the shade with Snooze and Done. Silent mode and Focus apply.'**
  String get eventAlertNotifyHint;

  /// Hint under the type control while Alarm is picked
  ///
  /// In en, this message translates to:
  /// **'Plays on the alarm stream until you stop or snooze it.'**
  String get eventAlertRingHint;

  /// Warning shown for an alarm when the full-screen intent permission is missing
  ///
  /// In en, this message translates to:
  /// **'Full-screen alarms are off, so this rings as a banner instead of taking over the screen.'**
  String get eventAlertFullScreenOff;

  /// Section label above the alert timing choices
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get eventAlertWhenSection;

  /// Chip that opens the free-form alert offset row
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get eventAlertCustom;

  /// Last item of an alert's When menu, which opens the custom offset sheet
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get eventAlertCustomItem;

  /// Unit of a custom alert offset
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get eventAlertUnitMinutes;

  /// Unit of a custom alert offset
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get eventAlertUnitHours;

  /// Unit of a custom alert offset
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get eventAlertUnitDays;

  /// Tooltip of the minus button on the custom alert offset
  ///
  /// In en, this message translates to:
  /// **'Less time before'**
  String get eventAlertOffsetDecrement;

  /// Tooltip of the plus button on the custom alert offset
  ///
  /// In en, this message translates to:
  /// **'More time before'**
  String get eventAlertOffsetIncrement;

  /// All-day alert firing on the day of the event
  ///
  /// In en, this message translates to:
  /// **'On the day'**
  String get eventAlertOnTheDay;

  /// All-day alert firing one day early
  ///
  /// In en, this message translates to:
  /// **'The day before'**
  String get eventAlertTheDayBefore;

  /// All-day alert firing seven days early
  ///
  /// In en, this message translates to:
  /// **'A week before'**
  String get eventAlertAWeekBefore;

  /// Row that picks what time an all-day alert fires at
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get eventAlertTimeOfDay;

  /// When this alert is next due, shown on the event detail sheet
  ///
  /// In en, this message translates to:
  /// **'Next {time}'**
  String eventAlertNext(String time);

  /// Caption of an alert an event inherits from its category, in the event editor, the detail sheet and the Alerts hub
  ///
  /// In en, this message translates to:
  /// **'From {category}'**
  String eventAlertFromCategory(String category);

  /// Switch in the event editor's Alerts group: whether this event inherits its category's alerts
  ///
  /// In en, this message translates to:
  /// **'Category alerts'**
  String get eventCategoryAlerts;

  /// Second line of the Category alerts switch in the event editor
  ///
  /// In en, this message translates to:
  /// **'Use the alerts set on {category}'**
  String eventCategoryAlertsDesc(String category);

  /// Caption under the category editor's alerts group
  ///
  /// In en, this message translates to:
  /// **'Every event in this category gets these alerts.'**
  String get categoryAlertsHint;

  /// Second line of a category alert's row: how the alert reads on the category's timed events (the first line is the all-day reading)
  ///
  /// In en, this message translates to:
  /// **'Timed events: {when}'**
  String categoryAlertTimedCaption(String when);

  /// Section header on the categories page above the categories that are not archived
  ///
  /// In en, this message translates to:
  /// **'In use'**
  String get categorySectionInUse;

  /// Section header on the categories page above the archived categories (plural where the language inflects)
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get categorySectionArchived;

  /// The state a screen reader hears on one archived category's row (singular, agreeing with 'category' where the language inflects)
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get categoryRowArchived;

  /// Caption segment on a categories page row marking a built-in category. Keep the no-break space between two words so the segment never splits across lines
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get categoryCaptionBuiltIn;

  /// Caption segment on a categories page row whose category carries an enabled alert. Keep the no-break space between two words so the segment never splits across lines
  ///
  /// In en, this message translates to:
  /// **'Alerts on'**
  String get categoryCaptionAlertsOn;

  /// Tooltip of the ⋮ button on a categories page row that opens the row's menu
  ///
  /// In en, this message translates to:
  /// **'Category options'**
  String get categoryActions;

  /// Accessible name of a category row's or a report card row's drag handle
  ///
  /// In en, this message translates to:
  /// **'Reorder {name}'**
  String categoryReorderLabel(String name);

  /// Screen-reader action on a categories page row that moves the category one place up within its section
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get categoryMoveUp;

  /// Screen-reader action on a categories page row that moves the category one place down within its section
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get categoryMoveDown;

  /// Line under the categories page's search field while a query is live, saying why the drag handles are off
  ///
  /// In en, this message translates to:
  /// **'Clear the search to reorder'**
  String get categoryReorderLockedHint;

  /// Row menu item on the categories page that archives a category (hides it from pickers, keeps its events)
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get categoryArchive;

  /// Row menu item on the categories page that brings an archived category back into use
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get categoryRestore;

  /// Row menu item on the categories page that opens the delete sheet; the ellipsis says a question follows
  ///
  /// In en, this message translates to:
  /// **'Delete…'**
  String get categoryDeleteEllipsis;

  /// Label of the delete sheet's row that picks the category a deleted category's events and templates move to; the value is that category's name
  ///
  /// In en, this message translates to:
  /// **'Move events to'**
  String get categoryDeleteMoveTo;

  /// Delete sheet: how many alerts of the category are removed with it, one segment of the line under its name (omitted at zero). Keep the no-break spaces between the words so the segment never splits across lines
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 alert} other{{count} alerts}}'**
  String categoryDeleteImpactAlerts(int count);

  /// Delete sheet: how many event templates use the category, one segment of the line under its name (omitted at zero). Keep the no-break spaces between the words so the segment never splits across lines
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 template} other{{count} templates}}'**
  String categoryDeleteImpactTemplates(int count);

  /// Caption under the delete sheet's group, always its last sentence: what else the delete changes
  ///
  /// In en, this message translates to:
  /// **'Saved views, digests and reports that pick only {name} show nothing until you pick again.'**
  String categoryDeleteConsequences(String name);

  /// Delete sheet: the caption's sentence shown only when the category has alerts, which are removed with it
  ///
  /// In en, this message translates to:
  /// **'Its alerts are removed.'**
  String get categoryDeleteAlertsRemoved;

  /// Delete sheet: the sentence before the consequences caption when the category has templates, which move to the same category as its events
  ///
  /// In en, this message translates to:
  /// **'Its templates move with the events.'**
  String get categoryDeleteTemplatesMove;

  /// Snackbar after saving an event whose alerts changed: how long until the next one, under a day away
  ///
  /// In en, this message translates to:
  /// **'{kind} in {duration}'**
  String eventAlertCountdown(String kind, String duration);

  /// The same snackbar when the next alert is whole days away
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{kind} in 1 day} other{{kind} in {count} days}}'**
  String eventAlertCountdownDays(int count, String kind);

  /// The same snackbar when the next alert is days and hours away
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{{kind} in 1 day {hours} h} other{{kind} in {days} days {hours} h}}'**
  String eventAlertCountdownDaysHours(int days, String kind, int hours);

  /// Subtitle segment on a row whose event deletes itself once acknowledged
  ///
  /// In en, this message translates to:
  /// **'removed after it rings'**
  String get eventRemovedAfterAlert;

  /// Snackbar shown on the calendar after an acknowledged alert deleted its event
  ///
  /// In en, this message translates to:
  /// **'Event removed'**
  String get eventAlertEventRemoved;

  /// Settings row holding the alert a new timed event starts with
  ///
  /// In en, this message translates to:
  /// **'Timed events'**
  String get alertsDefaultTimed;

  /// Description of the timed default row
  ///
  /// In en, this message translates to:
  /// **'The alert a new timed event starts with'**
  String get alertsDefaultTimedDesc;

  /// Settings row holding the alert a new all-day event starts with
  ///
  /// In en, this message translates to:
  /// **'All-day events'**
  String get alertsDefaultAllDay;

  /// Description of the all-day default row
  ///
  /// In en, this message translates to:
  /// **'The alert a new all-day event starts with'**
  String get alertsDefaultAllDayDesc;

  /// Value of a default row that seeds no alert at all
  ///
  /// In en, this message translates to:
  /// **'No alert'**
  String get alertsDefaultNone;

  /// The alert sheet's remove button when it edits a settings default: removing means a new event starts with no alert
  ///
  /// In en, this message translates to:
  /// **'No default alert'**
  String get alertsDefaultRemove;

  /// Title of the Alert settings page, of the settings hub's row that opens it, of the tooltip on the gear button in the Alerts page's bar, and of the row on Calendar settings that opens it
  ///
  /// In en, this message translates to:
  /// **'Alert settings'**
  String get alertSettingsTitle;

  /// Alert settings section holding the alert a new timed or all-day event starts with
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get alertSettingsSectionDefaults;

  /// Alert settings section holding the alarm sound, snooze, upcoming notice and silence lengths
  ///
  /// In en, this message translates to:
  /// **'Sound and timing'**
  String get alertSettingsSectionTiming;

  /// Alert settings row that opens the categories page, where each category's alerts are set
  ///
  /// In en, this message translates to:
  /// **'Alerts per category'**
  String get alertSettingsCategoriesRow;

  /// Description of the Alerts per category row
  ///
  /// In en, this message translates to:
  /// **'Set on each category'**
  String get alertSettingsCategoriesDesc;

  /// Title of the Fasting settings page and of the row on Calendar settings that opens it
  ///
  /// In en, this message translates to:
  /// **'Fasting'**
  String get fastingSettingsTitle;

  /// Fasting settings section holding one switch per fasting tradition, each with its look row
  ///
  /// In en, this message translates to:
  /// **'Traditions'**
  String get fastingSectionTraditions;

  /// Fasting settings row under a tradition's switch that opens how that tradition's fast is drawn on the calendar
  ///
  /// In en, this message translates to:
  /// **'Look on the calendar'**
  String get fastingLookRow;

  /// Description of the Orthodox multi-day fasts switch while it is off: what the calendar then marks
  ///
  /// In en, this message translates to:
  /// **'Off: only your weekly fast days, all year'**
  String get fastingGreatFastsOffDesc;

  /// Fasting settings section and row opening the personal fasting schedule (weekdays, months, single dates)
  ///
  /// In en, this message translates to:
  /// **'Your practice'**
  String get fastingPracticeRow;

  /// Value of Calendar settings' Fasting row while no fasting tradition is on
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get fastingTraditionsOff;

  /// Settings row and sound chooser title for which sound an alarm plays
  ///
  /// In en, this message translates to:
  /// **'Alarm sound'**
  String get alertsSound;

  /// Description of the alarm sound settings row
  ///
  /// In en, this message translates to:
  /// **'What an alarm plays when its alert names no sound'**
  String get alertsSoundDesc;

  /// Sound choice on one alert: follow the Calendar settings sound
  ///
  /// In en, this message translates to:
  /// **'Use the app setting'**
  String get alertSoundUseAppSetting;

  /// Sound choice: whatever alarm sound the phone is set to
  ///
  /// In en, this message translates to:
  /// **'Phone\'s default alarm'**
  String get alertSoundPhoneDefault;

  /// Sound choice that opens the phone's own sound picker
  ///
  /// In en, this message translates to:
  /// **'Choose from phone'**
  String get alertSoundChooseFromPhone;

  /// Neutral name for a picked phone sound before its own title is known
  ///
  /// In en, this message translates to:
  /// **'Sound from phone'**
  String get alertSoundFromPhone;

  /// Shown for a picked sound this device cannot resolve, e.g. after a restore from another phone
  ///
  /// In en, this message translates to:
  /// **'Not on this phone — plays the phone\'s default alarm'**
  String get alertSoundUnavailable;

  /// Snackbar shown when the system ringtone picker cannot be opened at all
  ///
  /// In en, this message translates to:
  /// **'This phone has no sound picker'**
  String get alertSoundPickerUnavailable;

  /// Title of the Alerts hub page, of its drawer row and of its calendar overflow-menu row
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get alertsTitle;

  /// Subtitle of the Alerts drawer row
  ///
  /// In en, this message translates to:
  /// **'Upcoming reminders and alarms'**
  String get alertsRowDesc;

  /// Empty state title of the Alerts hub
  ///
  /// In en, this message translates to:
  /// **'No upcoming alerts'**
  String get alertsEmpty;

  /// Empty state body of the Alerts hub
  ///
  /// In en, this message translates to:
  /// **'Add a reminder or an alarm to an event and it shows up here.'**
  String get alertsEmptyDesc;

  /// Hub banner shown while the notification permission is denied
  ///
  /// In en, this message translates to:
  /// **'Notifications are off. Reminders stay hidden, and an alarm rings without waking the screen.'**
  String get alertsNotificationsOffBanner;

  /// Hub banner shown while the full-screen intent permission is denied
  ///
  /// In en, this message translates to:
  /// **'Full-screen alarms are off. Alarms show as a banner on a locked phone.'**
  String get alertsFullScreenOffBanner;

  /// Subtitle of a snoozed hub row; alert is the alert's own description, e.g. 10 min before
  ///
  /// In en, this message translates to:
  /// **'Snoozed · {alert}'**
  String alertsSnoozedRow(String alert);

  /// Tooltip of the button that drops a standing snooze
  ///
  /// In en, this message translates to:
  /// **'Cancel snooze'**
  String get alertsCancelSnooze;

  /// Accessibility label of a hub row's on/off switch
  ///
  /// In en, this message translates to:
  /// **'Alert for {title}'**
  String alertsToggleLabel(String title);

  /// Title and confirm button of the dialog that cancels a remove-after-it-rings alarm
  ///
  /// In en, this message translates to:
  /// **'Cancel alarm'**
  String get alertsCancelAlarm;

  /// Body of the cancel-alarm dialog
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is removed after it rings, so cancelling the alarm removes the event.'**
  String alertsCancelAlarmConfirm(String title);

  /// Title of the Permissions page, its settings hub row and the calendar settings row that opens it
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissionsTitle;

  /// Subtitle of the settings hub's Permissions row while nothing essential is missing
  ///
  /// In en, this message translates to:
  /// **'What ANTA may do on this device'**
  String get permissionsRowDesc;

  /// How many essential permissions are missing: the subtitle of the settings hub's Permissions row and of the drawer's Settings row, and the body of the Permissions page's warning banner
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 permission is off} other{{count} permissions are off}}'**
  String permissionsRowAttention(int count);

  /// Title of the settings hub, the page every settings page is opened from
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsHubTitle;

  /// Subtitle of the drawer's Settings row, which opens the settings hub
  ///
  /// In en, this message translates to:
  /// **'Everything you can change'**
  String get settingsHubRowDesc;

  /// Title of the drawer's row that opens the app's guide
  ///
  /// In en, this message translates to:
  /// **'How to use ANTA'**
  String get howToUseAnta;

  /// Subtitle of the drawer's Report row, which opens the calendar's report page
  ///
  /// In en, this message translates to:
  /// **'How a week or a month went'**
  String get calendarReportRowDesc;

  /// Hint of the settings hub's search field, which filters its rows by title, subtitle and the sections of the page each row opens
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsHubSearchHint;

  /// Settings hub section holding the calendar's settings pages
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get settingsSectionCalendar;

  /// Settings hub section holding the editor's and the counters' settings pages
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get settingsSectionNotes;

  /// Settings hub section holding the app-wide settings: general, language, theme, databases, sharing, permissions
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsSectionApp;

  /// Settings hub section holding the guides that explain how the app works
  ///
  /// In en, this message translates to:
  /// **'How to'**
  String get settingsSectionHowTo;

  /// Subtitle of the settings hub row that opens Calendar settings, naming what the page holds
  ///
  /// In en, this message translates to:
  /// **'Holidays, filtering, events'**
  String get settingsRowCalendarDesc;

  /// Subtitle of the settings hub row that opens the calendar's Appearance page
  ///
  /// In en, this message translates to:
  /// **'Week start, cells, markers, colors'**
  String get settingsRowAppearanceDesc;

  /// Subtitle of the settings hub row that opens the Alert settings page
  ///
  /// In en, this message translates to:
  /// **'Defaults, sound, timing, permissions'**
  String get settingsRowAlertsDesc;

  /// Subtitle of the settings hub row that opens the Fasting settings page, naming its traditions and the user's own fasting practice
  ///
  /// In en, this message translates to:
  /// **'Traditions, your practice'**
  String get settingsRowFastingDesc;

  /// Subtitle of the row that opens the calendar's Categories page
  ///
  /// In en, this message translates to:
  /// **'Create, order, archive'**
  String get calendarCategoriesRowDesc;

  /// Title of the settings hub row that opens the markdown shortcuts and editor page
  ///
  /// In en, this message translates to:
  /// **'Editor and markdown'**
  String get settingsRowEditor;

  /// Subtitle of the settings hub row that opens the markdown shortcuts and editor page
  ///
  /// In en, this message translates to:
  /// **'Shortcuts, toolbar, colors, vocabularies, money'**
  String get settingsRowEditorDesc;

  /// Subtitle of the settings hub row that opens the Counters page
  ///
  /// In en, this message translates to:
  /// **'Pinned and per-note counters'**
  String get settingsRowCountersDesc;

  /// Title of the settings hub row that opens the app's general settings page
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsRowGeneral;

  /// Subtitle of the settings hub row that opens the app's general settings page
  ///
  /// In en, this message translates to:
  /// **'Startup, browsing, editor, auto-save'**
  String get settingsRowGeneralDesc;

  /// Title of the settings hub row that opens the light, dark or system theme dialog
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsRowTheme;

  /// Title of the settings hub row that opens the Databases page
  ///
  /// In en, this message translates to:
  /// **'Databases and backup'**
  String get settingsRowDatabases;

  /// Subtitle of the settings hub row that opens the Databases page
  ///
  /// In en, this message translates to:
  /// **'Switch, export, import, delete'**
  String get settingsRowDatabasesDesc;

  /// Subtitle of the settings hub row that opens the Sync & sharing page: its Account, Sync and Pairing sections
  ///
  /// In en, this message translates to:
  /// **'Account, sync and paired devices'**
  String get settingsRowSharingDesc;

  /// Caption of the Alert settings page's Permissions row, which opens the Permissions page; the German says Mitteilungen, the app's word for notifications in running text, because Benachrichtigungen alone is wider than the caption's column at text scale 2.0 on a 360 dp phone
  ///
  /// In en, this message translates to:
  /// **'Notifications, exact timing, full-screen alarms, battery'**
  String get permissionsCalendarRowDesc;

  /// Permissions summary when every permission is granted; also the snackbar after the launch dialog granted everything
  ///
  /// In en, this message translates to:
  /// **'All set'**
  String get permissionsAllSet;

  /// Body of the Permissions summary banner when every permission is granted
  ///
  /// In en, this message translates to:
  /// **'ANTA has everything it needs on this device.'**
  String get permissionsAllSetBody;

  /// Title of the Permissions warning banner while an essential permission is missing
  ///
  /// In en, this message translates to:
  /// **'Alarms and reminders can\'t work yet'**
  String get permissionsAttentionTitle;

  /// Title of the Permissions summary banner when only recommended permissions are missing
  ///
  /// In en, this message translates to:
  /// **'Essentials are allowed'**
  String get permissionsEssentialsOk;

  /// Body of the Permissions summary banner when only recommended permissions are missing
  ///
  /// In en, this message translates to:
  /// **'The recommended ones make alarms more reliable.'**
  String get permissionsRecommendedBody;

  /// Permissions page section: permissions a feature cannot work without
  ///
  /// In en, this message translates to:
  /// **'Essential'**
  String get permissionsEssentialSection;

  /// Permissions page section, and the tag on an optional permission in the launch dialog
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get permissionsRecommendedSection;

  /// Permissions page section holding the page's own options
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get permissionsOptionsSection;

  /// Permission row: whether the app may schedule alarms at an exact time. Use the name Android gives this page in the system settings
  ///
  /// In en, this message translates to:
  /// **'Alarms & reminders'**
  String get permissionExactAlarms;

  /// Description of the exact alarm permission row
  ///
  /// In en, this message translates to:
  /// **'Lets alerts fire at their exact time'**
  String get permissionExactAlarmsDesc;

  /// Switch on the Permissions page: whether the launch dialog may appear
  ///
  /// In en, this message translates to:
  /// **'Check at launch'**
  String get permissionsLaunchCheck;

  /// Description of the launch check switch
  ///
  /// In en, this message translates to:
  /// **'Ask once when something essential is off'**
  String get permissionsLaunchCheckDesc;

  /// Row on the Permissions page that opens the app's page in the operating system's settings
  ///
  /// In en, this message translates to:
  /// **'System settings'**
  String get permissionsSystemSettings;

  /// Description of the system settings row
  ///
  /// In en, this message translates to:
  /// **'Open ANTA\'s page in the system settings'**
  String get permissionsSystemSettingsDesc;

  /// Permissions page empty state title, on a platform where the app needs no permission
  ///
  /// In en, this message translates to:
  /// **'Nothing to allow'**
  String get permissionsNoneNeeded;

  /// Permissions page empty state body
  ///
  /// In en, this message translates to:
  /// **'ANTA needs no system permissions on this device. Alarms and reminders only ring on Android for now.'**
  String get permissionsNoneNeededDesc;

  /// Title of the dialog shown at launch while an essential permission is missing
  ///
  /// In en, this message translates to:
  /// **'ANTA needs your permission'**
  String get permissionsPromptTitle;

  /// Lead line of the launch permission dialog, above the list of missing permissions
  ///
  /// In en, this message translates to:
  /// **'Without these, alarms and reminders stay silent.'**
  String get permissionsPromptBody;

  /// Primary action of the launch permission dialog: run the system prompts
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get permissionsPromptContinue;

  /// Dismiss action of the launch permission dialog
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get permissionsPromptNotNow;

  /// Snackbar when the system settings page for a permission could not be opened
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the system settings'**
  String get permissionsSettingsUnavailable;

  /// Snackbar after saving an alert or pressing Test alarm while an essential permission is missing
  ///
  /// In en, this message translates to:
  /// **'This can\'t ring until a permission is turned on'**
  String get permissionsAlertBlocked;

  /// Snackbar action that opens the Permissions page
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get permissionsReview;

  /// Alerts hub banner while the exact alarm permission is missing
  ///
  /// In en, this message translates to:
  /// **'Alarms & reminders access is off. Alerts can\'t be set for their exact time.'**
  String get alertsExactAlarmsOffBanner;

  /// Title of the Permissions summary banner when the system could not be asked
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check permissions'**
  String get permissionsUnknownTitle;

  /// Body of the Permissions summary banner when the system could not be asked
  ///
  /// In en, this message translates to:
  /// **'Open the system settings to see them.'**
  String get permissionsUnknownBody;

  /// A recommended permission's line in the launch permission dialog: the tag, then that permission's own description
  ///
  /// In en, this message translates to:
  /// **'Recommended · {description}'**
  String permissionsPromptRecommended(String description);

  /// Confirm button of the time pad sheet that sets a start, end, alert or alarm time
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get timePadDone;

  /// Screen-reader label of the time pad's :00 key, which sets the minutes to zero and finishes
  ///
  /// In en, this message translates to:
  /// **'On the hour'**
  String get timePadOnTheHour;

  /// Screen-reader label of the time pad's :30 key, which sets the minutes to thirty and finishes
  ///
  /// In en, this message translates to:
  /// **'Half past'**
  String get timePadHalfPast;

  /// Time pad prompt on a 12-hour clock once the minutes are typed; the placeholders are the platform's AM and PM abbreviations
  ///
  /// In en, this message translates to:
  /// **'{am} or {pm}?'**
  String timePadChoosePeriod(String am, String pm);

  /// Time pad caption while typing a start time: where the event's end lands
  ///
  /// In en, this message translates to:
  /// **'Ends {time}'**
  String timePadEndsAt(String time);

  /// Time pad caption while typing a start time whose end crosses midnight
  ///
  /// In en, this message translates to:
  /// **'Ends {time} next day'**
  String timePadEndsNextDayAt(String time);

  /// Time pad caption while typing an end time: how long after the start it is
  ///
  /// In en, this message translates to:
  /// **'{duration} after {time}'**
  String timePadAfterStart(String duration, String time);

  /// An event's length under one hour
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String eventDurationMinutes(int minutes);

  /// An event's length in whole hours
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String eventDurationHours(int hours);

  /// An event's length in hours and minutes
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String eventDurationHoursMinutes(int hours, int minutes);

  /// Title of the time pad opened from the quick-alarm sheet's big time
  ///
  /// In en, this message translates to:
  /// **'Alarm time'**
  String get quickAlarmTime;

  /// Label of the event editor's category row
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get eventCategory;

  /// Label of the event editor's date row for a one-time event with one date
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get eventDateLabel;

  /// Label of the event editor's start-time row
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get eventStarts;

  /// Label of the event editor's end-time row
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get eventEnds;

  /// Tooltip of the button that clears an event's end time
  ///
  /// In en, this message translates to:
  /// **'Remove end time'**
  String get eventEndTimeRemove;

  /// Label of the event editor's repeat row and title of the repeat sheet
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get eventRepeat;

  /// Repeat value of a one-time event, and the first option of the repeat sheet
  ///
  /// In en, this message translates to:
  /// **'Does not repeat'**
  String get recurrenceDoesNotRepeat;

  /// Label of the repeat sheet's end-date row
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get recurrenceEnds;

  /// Value of the repeat sheet's end-date row when no end date is set
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// Tooltip of the button that clears a recurrence's end date
  ///
  /// In en, this message translates to:
  /// **'Remove end date'**
  String get recurrenceEndDateRemove;

  /// Title of the repeat sheet's retroactive switch
  ///
  /// In en, this message translates to:
  /// **'Also before the start date'**
  String get recurrenceBeforeStart;

  /// Second line of the retroactive switch, naming the start date
  ///
  /// In en, this message translates to:
  /// **'Shows on matching days before {date}'**
  String recurrenceBeforeStartHint(String date);

  /// Second line of the retroactive switch for a yearly rule
  ///
  /// In en, this message translates to:
  /// **'Also in earlier years'**
  String get recurrenceBeforeStartYearlyHint;

  /// Second line of the retroactive switch in an event template's repeat sheet, where there is no start date to name
  ///
  /// In en, this message translates to:
  /// **'Also on matching days before the day it is added'**
  String get recurrenceBeforeStartTemplateHint;

  /// The repeat row's value when an end date is set: the rule label followed by the end date
  ///
  /// In en, this message translates to:
  /// **'{rule} · until {date}'**
  String recurrenceUntilSuffix(String rule, String date);

  /// Value of the Icon & color row when neither an icon nor a colour override is set
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get eventLookDefault;

  /// Value of the Icon & color row when an icon or colour override is set
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get eventLookCustom;

  /// Value of the linked-note row when no note is linked
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get eventLinkedNoteNone;

  /// Value of the linked-note row when the linked note no longer exists
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get eventLinkedNoteNotFound;

  /// Short label of the button that returns one day's description to the shared one
  ///
  /// In en, this message translates to:
  /// **'Reset day'**
  String get eventDescriptionResetDayShort;

  /// The counter under the event editor's title field, shown from 100 characters
  ///
  /// In en, this message translates to:
  /// **'{count}/{limit}'**
  String eventTitleCount(int count, int limit);

  /// Label of the event editor's bundled dates row, shown from four one-off dates on
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get eventDatesLabel;

  /// Value of the bundled dates row: the date count and the span from the first to the last date
  ///
  /// In en, this message translates to:
  /// **'{count} · {range}'**
  String eventDatesSummary(String count, String range);

  /// Empty state of the date picker's list view
  ///
  /// In en, this message translates to:
  /// **'No dates yet. Pick them in Month or Year.'**
  String get datePickerListEmpty;

  /// Position of a date in the picker's list view
  ///
  /// In en, this message translates to:
  /// **'{index} of {count}'**
  String datePickerListIndex(int index, int count);

  /// Tooltip of the year view's back chevron
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get datePickerPreviousYear;

  /// Tooltip of the year view's forward chevron
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get datePickerNextYear;

  /// Footer action of the multi-date picker that projects the selection forward
  ///
  /// In en, this message translates to:
  /// **'Repeat the picked dates…'**
  String get datePickerRepeatPicked;

  /// Label of the stepper saying how many times the picked dates repeat
  ///
  /// In en, this message translates to:
  /// **'Times'**
  String get datePickerRepeatTimes;

  /// Repeat unit segment: one week apart
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get datePickerRepeatWeek;

  /// Repeat unit segment: one month apart
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get datePickerRepeatMonth;

  /// Repeat unit segment: one year apart
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get datePickerRepeatYear;

  /// Value of the repeat stepper
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more} other{{count} more}}'**
  String datePickerRepeatTimesValue(int count);

  /// Tooltip of the repeat stepper's decrement
  ///
  /// In en, this message translates to:
  /// **'Fewer'**
  String get datePickerRepeatFewer;

  /// Tooltip of the repeat stepper's increment
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get datePickerRepeatMore;

  /// Caption previewing what the repeat would add and the last date it reaches
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Adds 1 date} other{Adds {count} dates}} · through {last}'**
  String datePickerRepeatAdds(int count, String last);

  /// Caption suffix for projected days that do not exist, such as a 31st in a short month
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 skipped, no such day} other{{count} skipped, no such day}}'**
  String datePickerRepeatSkipped(int count);

  /// Caption when the repeat would add no new date
  ///
  /// In en, this message translates to:
  /// **'Nothing to add'**
  String get datePickerRepeatNothing;

  /// Confirm button of the repeat panel
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Add dates} =1{Add 1 date} other{Add {count} dates}}'**
  String datePickerRepeatApply(int count);

  /// Second line of the editor's bundled dates row: the next upcoming date
  ///
  /// In en, this message translates to:
  /// **'Next {date}'**
  String eventDatesNext(String date);

  /// How many of an event's pinned dates are still ahead of today
  ///
  /// In en, this message translates to:
  /// **'{ahead} of {total} ahead'**
  String eventDatesAhead(int ahead, int total);

  /// Shown when every pinned date of an event has passed
  ///
  /// In en, this message translates to:
  /// **'All in the past'**
  String get eventDatesAllPast;

  /// Title of the calendar guide page and its row in the calendar's three-dot menu
  ///
  /// In en, this message translates to:
  /// **'How the calendar works'**
  String get calendarGuideTitle;

  /// Hint of the search field on the calendar guide page
  ///
  /// In en, this message translates to:
  /// **'Search the guide'**
  String get calendarGuideSearchHint;

  /// Intro line at the top of the calendar guide hub
  ///
  /// In en, this message translates to:
  /// **'Tap a page. Nothing you try there is real.'**
  String get calendarGuideIntro;

  /// Calendar guide page title about the calendar screen, on its hub row and its topic page
  ///
  /// In en, this message translates to:
  /// **'The calendar screen'**
  String get calendarGuideSectionCalendar;

  /// Calendar guide row title about the day markers
  ///
  /// In en, this message translates to:
  /// **'The coloured bars under a day'**
  String get calendarGuideMarksTitle;

  /// Calendar guide paragraph about the day markers
  ///
  /// In en, this message translates to:
  /// **'A bar under a day means something is planned there, in its category\'s colour. Holidays and weekends have bars of their own.'**
  String get calendarGuideMarksBody;

  /// Calendar guide row title about the grid formats
  ///
  /// In en, this message translates to:
  /// **'Month, two weeks or one week'**
  String get calendarGuideViewsTitle;

  /// Calendar guide paragraph about a grid shrunk by the title's view menu; month is that menu's Month label
  ///
  /// In en, this message translates to:
  /// **'If the days shrink to one or two rows, the title menu was switched: pick “{month}” there again.'**
  String calendarGuideViewsBody(String month);

  /// Calendar guide read row title on the categories page: where the Categories page is
  ///
  /// In en, this message translates to:
  /// **'Where they are managed'**
  String get calendarGuideCategoriesWhereTitle;

  /// Calendar guide read row body; categories is the Categories row's label in the drawer and in the calendar's three-dot menu
  ///
  /// In en, this message translates to:
  /// **'Open the menu (☰) and tap “{categories}”, or tap ⋮ on the calendar, then “{categories}”.'**
  String calendarGuideCategoriesWhereBody(String categories);

  /// Calendar guide row title about an event's category
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get calendarGuideCategoryTitle;

  /// Calendar guide paragraph about categories; category is the editor's row label
  ///
  /// In en, this message translates to:
  /// **'Every event has a category — the “{category}” row under its name — which gives it its colour and icon. Create your own at the bottom of that list.'**
  String calendarGuideCategoryBody(String category);

  /// Calendar guide row title about an event's description
  ///
  /// In en, this message translates to:
  /// **'Notes on an event'**
  String get calendarGuideDescriptionTitle;

  /// Calendar guide paragraph about an event's description
  ///
  /// In en, this message translates to:
  /// **'Under the name there is room for an address, a phone number, what to bring. It shows when you open the event.'**
  String get calendarGuideDescriptionBody;

  /// Calendar guide row title about saving; save is the editor's Save label
  ///
  /// In en, this message translates to:
  /// **'Nothing is saved until “{save}”'**
  String calendarGuideUnsavedTitle(String save);

  /// Calendar guide paragraph about unsaved changes
  ///
  /// In en, this message translates to:
  /// **'If you close an event you were changing, the app asks whether to keep editing or discard. A saved event stays on the phone — no internet needed.'**
  String get calendarGuideUnsavedBody;

  /// Calendar guide row title about event templates
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get calendarGuideTemplatesTitle;

  /// Calendar guide paragraph about templates; saveAsTemplate is the editor's row label
  ///
  /// In en, this message translates to:
  /// **'An event you add often can be saved with “{saveAsTemplate}” at the bottom of the editor. Press and hold + to use it.'**
  String calendarGuideTemplatesBody(String saveAsTemplate);

  /// Calendar guide row title about the two alert tiers
  ///
  /// In en, this message translates to:
  /// **'Reminder or alarm'**
  String get calendarGuideAlertKindsTitle;

  /// Calendar guide paragraph about the alert tiers; the placeholders are the alert sheet's and editor's labels
  ///
  /// In en, this message translates to:
  /// **'“{reminder}”: a notification you can dismiss or snooze. “{alarm}”: it rings until you stop it, even on a locked phone; to go off minutes before, the event needs a start time — turn off “{allDay}”.'**
  String calendarGuideAlertKindsBody(
    String reminder,
    String alarm,
    String allDay,
  );

  /// Calendar guide row title about notification and alarm permissions
  ///
  /// In en, this message translates to:
  /// **'Let the phone ring'**
  String get calendarGuidePermissionsTitle;

  /// Calendar guide paragraph about permissions; battery is the alert permissions' battery row label, settings is the drawer's Settings row label, permissions is the settings hub's Permissions row label
  ///
  /// In en, this message translates to:
  /// **'The first time, ANTA asks to show notifications and set alarms: allow both, or nothing rings. On a Samsung phone also turn on “{battery}”; if something stays silent later, “{settings}” in the main menu, then “{permissions}”, shows what is missing.'**
  String calendarGuidePermissionsBody(
    String battery,
    String settings,
    String permissions,
  );

  /// Calendar guide row title about a firing alert
  ///
  /// In en, this message translates to:
  /// **'When it goes off'**
  String get calendarGuideRingTitle;

  /// Calendar guide paragraph about a firing alert; the placeholders are the notification's and alarm page's buttons
  ///
  /// In en, this message translates to:
  /// **'A reminder is a notification with “{done}” and “{snooze}”. An alarm fills the screen with “{stop}” and “{snooze}”, and falls silent by itself if nobody answers.'**
  String calendarGuideRingBody(String done, String snooze, String stop);

  /// Calendar guide row title about opening the app regularly
  ///
  /// In en, this message translates to:
  /// **'Open ANTA now and then'**
  String get calendarGuideOpenOftenTitle;

  /// Calendar guide paragraph about why the app must be opened regularly
  ///
  /// In en, this message translates to:
  /// **'ANTA lines up the next reminders each time you open it — about ten of each. Open the app every week or so and they never run out.'**
  String get calendarGuideOpenOftenBody;

  /// Calendar guide row title about the overview page
  ///
  /// In en, this message translates to:
  /// **'The overview'**
  String get calendarGuideOverviewTitle;

  /// Calendar guide paragraph about the overview; the placeholders are its labels
  ///
  /// In en, this message translates to:
  /// **'“{overview}” in the title menu shows the months as tiles (“{year}”) or everything in a period as one list (“{list}”). The arrow at the top left brings you back.'**
  String calendarGuideOverviewBody(String overview, String year, String list);

  /// Calendar guide row title about the grid filters
  ///
  /// In en, this message translates to:
  /// **'Filters hide, they never delete'**
  String get calendarGuideFiltersTitle;

  /// Calendar guide paragraph about the grid filters; the placeholders are the filter sheet's buttons
  ///
  /// In en, this message translates to:
  /// **'A filter hides, it never deletes. If events seem to be missing, open the funnel and tap “{reset}”, then “{apply}”.'**
  String calendarGuideFiltersBody(String reset, String apply);

  /// Calendar guide row title about finding the calendar settings
  ///
  /// In en, this message translates to:
  /// **'Where the settings are'**
  String get calendarGuideSettingsTitle;

  /// Calendar guide paragraph about the calendar settings; settings is the drawer's Settings row label, calendarSettings the Calendar settings row's label (on the settings hub and in the calendar's three-dot menu), save the editor's Save label
  ///
  /// In en, this message translates to:
  /// **'Open the menu (☰), tap “{settings}”, then “{calendarSettings}” — or tap ⋮ on the calendar, then “{calendarSettings}”. Everything there applies at once — there is no “{save}” button.'**
  String calendarGuideSettingsBody(
    String settings,
    String calendarSettings,
    String save,
  );

  /// Calendar guide read row body on the setup page, under the Fasting page's title; settings is the settings hub's title, fasting the Fasting page's row label, calendarSettings the Calendar settings row's label
  ///
  /// In en, this message translates to:
  /// **'Under “{settings}” → “{fasting}”, or from “{calendarSettings}”: the traditions, how each looks, your own practice.'**
  String calendarGuideSetupFastingBody(
    String settings,
    String fasting,
    String calendarSettings,
  );

  /// Calendar guide read row body on the setup page, under the Alert settings page's title; settings is the settings hub's title, alerts the Alert settings row's label, alertsPage the Alerts page's title; ⚙ is the gear button on the Alerts page's bar
  ///
  /// In en, this message translates to:
  /// **'Under “{settings}” → “{alerts}”, or the ⚙ on the {alertsPage} page: the default alerts, the sound, snooze and the notice.'**
  String calendarGuideSetupAlertsBody(
    String settings,
    String alerts,
    String alertsPage,
  );

  /// Calendar guide row title about language, theme and text size
  ///
  /// In en, this message translates to:
  /// **'Language, dark mode and text size'**
  String get calendarGuideLanguageTitle;

  /// Calendar guide paragraph about language and theme; settings is the drawer's Settings row label, language and theme are the settings hub's row labels
  ///
  /// In en, this message translates to:
  /// **'In the main menu (three lines, top left), open “{settings}”: “{language}” switches the language and “{theme}” chooses light or dark. The text size follows your phone\'s font size.'**
  String calendarGuideLanguageBody(
    String settings,
    String language,
    String theme,
  );

  /// Calendar guide page title for general tips, on its hub row and its topic page
  ///
  /// In en, this message translates to:
  /// **'Good to know'**
  String get calendarGuideSectionGood;

  /// Calendar guide row title about reaching the calendar
  ///
  /// In en, this message translates to:
  /// **'Opening the calendar'**
  String get calendarGuideOpeningTitle;

  /// Calendar guide paragraph about reaching the calendar and the guide; calendar is the drawer's Calendar label, title is the guide's own menu label
  ///
  /// In en, this message translates to:
  /// **'From the app\'s first screen, tap the menu button at the top left, then “{calendar}”. To come back here: the three dots on the calendar, then “{title}”.'**
  String calendarGuideOpeningBody(String calendar, String title);

  /// Calendar guide row title about going back
  ///
  /// In en, this message translates to:
  /// **'Going back'**
  String get calendarGuideBackTitle;

  /// Calendar guide paragraph about going back and closing sheets
  ///
  /// In en, this message translates to:
  /// **'The arrow at the top left, or your phone\'s back gesture, returns to the previous screen. A sheet that slid up closes with its X, or by swiping it down.'**
  String get calendarGuideBackBody;

  /// Calendar guide row title about the notes side of the app
  ///
  /// In en, this message translates to:
  /// **'The rest of ANTA'**
  String get calendarGuideNotesTitle;

  /// Calendar guide paragraph about notes; linkedNote is the editor's row label
  ///
  /// In en, this message translates to:
  /// **'ANTA is also a notebook: the folders and notes behind the main menu. An event can point to a note through “{linkedNote}”.'**
  String calendarGuideNotesBody(String linkedNote);

  /// Calendar guide row title about the assume-absent switch
  ///
  /// In en, this message translates to:
  /// **'Present unless you say otherwise'**
  String get calendarGuideAssumeTitle;

  /// Calendar guide paragraph about the presence default; the placeholders are the editor's and the detail sheet's labels
  ///
  /// In en, this message translates to:
  /// **'With “{trackPresence}” on, every day counts as “{present}” until you mark it “{missed}”. “{assumeAbsent}” turns that around for things you rarely manage.'**
  String calendarGuideAssumeBody(
    String trackPresence,
    String present,
    String missed,
    String assumeAbsent,
  );

  /// Calendar guide row title about the day rail; dayRail is the editor's Day rail label
  ///
  /// In en, this message translates to:
  /// **'What “{dayRail}” is'**
  String calendarGuideRailTitle(String dayRail);

  /// Calendar guide paragraph about the day rail; the placeholders are the editor's and the settings' labels and the three values of the editor's Day rail menu
  ///
  /// In en, this message translates to:
  /// **'“{dayRail}” is a thin strip at the left edge of a day with one mark per tracked event. Turn it on in “{settingsRow}”, under “{appearance}”; each event can then choose “{railAuto}”, “{railAlways}” or “{railNever}”.'**
  String calendarGuideRailBody(
    String dayRail,
    String settingsRow,
    String appearance,
    String railAuto,
    String railAlways,
    String railNever,
  );

  /// Calendar guide row title about per-day descriptions
  ///
  /// In en, this message translates to:
  /// **'A note for one day only'**
  String get calendarGuidePerDayTitle;

  /// Calendar guide paragraph about per-day descriptions; the placeholders are the editor's labels
  ///
  /// In en, this message translates to:
  /// **'A repeating event shares one description across its days. Turn on “{perDay}” and, above the description, “{thisDay}” writes for that day alone.'**
  String calendarGuidePerDayBody(String perDay, String thisDay);

  /// Calendar guide row title about priority and appearance; priority is the editor's Priority label
  ///
  /// In en, this message translates to:
  /// **'“{priority}” and the look'**
  String calendarGuidePriorityTitle(String priority);

  /// Calendar guide paragraph about priority and appearance; the placeholders are the editor's labels
  ///
  /// In en, this message translates to:
  /// **'“{priority}” orders a busy day and decides which events get a bar when there are more than three. “{iconColor}” gives one event its own icon or colour.'**
  String calendarGuidePriorityBody(String priority, String iconColor);

  /// Label of the sandbox corner on each calendar guide page
  ///
  /// In en, this message translates to:
  /// **'Try it'**
  String get calendarGuideTryIt;

  /// Calendar guide hub label over the task pages
  ///
  /// In en, this message translates to:
  /// **'How do I…'**
  String get calendarGuideHowDoI;

  /// Calendar guide hub row and page title of the practice calendar's events lesson
  ///
  /// In en, this message translates to:
  /// **'Practice calendar events'**
  String get calendarGuidePagePractice;

  /// Calendar guide hub caption of the practice calendar's events lesson row
  ///
  /// In en, this message translates to:
  /// **'A calendar that saves nothing. Add, change and delete freely.'**
  String get calendarGuidePagePracticeCaption;

  /// Calendar guide hub row and page title of the practice calendar's filtering lesson
  ///
  /// In en, this message translates to:
  /// **'Practice calendar filtering'**
  String get calendarGuidePagePracticeFiltering;

  /// Calendar guide hub caption of the practice calendar's filtering lesson row
  ///
  /// In en, this message translates to:
  /// **'The same calendar, fuller. Hide things with the funnel and bring them back.'**
  String get calendarGuidePagePracticeFilteringCaption;

  /// Calendar guide hub caption of the calendar screen page
  ///
  /// In en, this message translates to:
  /// **'The month, the bars, the panel, the menus'**
  String get calendarGuidePageScreenCaption;

  /// Calendar guide hub row and page title about events
  ///
  /// In en, this message translates to:
  /// **'Add, change or delete an event'**
  String get calendarGuidePageEvents;

  /// Calendar guide hub caption of the events page
  ///
  /// In en, this message translates to:
  /// **'The editor, saving, deleting, templates'**
  String get calendarGuidePageEventsCaption;

  /// Calendar guide hub row and page title about one-time and repeating events
  ///
  /// In en, this message translates to:
  /// **'One-time and repeating events'**
  String get calendarGuidePageKinds;

  /// Calendar guide hub caption of the event kinds page
  ///
  /// In en, this message translates to:
  /// **'How the two kinds differ, and the quirks of each'**
  String get calendarGuidePageKindsCaption;

  /// Calendar guide hub row and page title about alerts
  ///
  /// In en, this message translates to:
  /// **'Get reminded'**
  String get calendarGuidePageAlerts;

  /// Calendar guide hub caption of the alerts page
  ///
  /// In en, this message translates to:
  /// **'Reminders, alarms, permissions, the quick alarm'**
  String get calendarGuidePageAlertsCaption;

  /// Calendar guide hub row and page title about attendance
  ///
  /// In en, this message translates to:
  /// **'Keep track of attendance'**
  String get calendarGuidePageAttendance;

  /// Calendar guide hub caption of the attendance page; present and missed are the detail sheet's attendance labels, dayRail is the editor's Day rail label
  ///
  /// In en, this message translates to:
  /// **'“{present}” or “{missed}”, counting, “{dayRail}”, a note per day'**
  String calendarGuidePageAttendanceCaption(
    String present,
    String missed,
    String dayRail,
  );

  /// Calendar guide hub row and page title about categories
  ///
  /// In en, this message translates to:
  /// **'Use categories'**
  String get calendarGuidePageCategories;

  /// Calendar guide hub caption of the categories page
  ///
  /// In en, this message translates to:
  /// **'What they are; create, change, hide, delete'**
  String get calendarGuidePageCategoriesCaption;

  /// Calendar guide hub row and page title about finding events
  ///
  /// In en, this message translates to:
  /// **'Find an event'**
  String get calendarGuidePageFinding;

  /// Calendar guide hub caption of the finding page; overview is the calendar's Overview label
  ///
  /// In en, this message translates to:
  /// **'Search, filters, “{overview}”'**
  String calendarGuidePageFindingCaption(String overview);

  /// Calendar guide hub row and page title about calendar settings
  ///
  /// In en, this message translates to:
  /// **'Set up the calendar'**
  String get calendarGuidePageSetup;

  /// Calendar guide hub caption of the setup page
  ///
  /// In en, this message translates to:
  /// **'Holidays, the week\'s first day, language and dark mode'**
  String get calendarGuidePageSetupCaption;

  /// Calendar guide hub caption of the Good to know page
  ///
  /// In en, this message translates to:
  /// **'Opening the calendar, going back, the rest of ANTA'**
  String get calendarGuidePageGoodCaption;

  /// Calendar guide hub's first card title, over the practice calendar, The calendar screen and Good to know rows
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get calendarGuideStartHere;

  /// Calendar guide topic page's card title over its read rows
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get calendarGuideHowItWorks;

  /// Lead line of the calendar guide's calendar screen page
  ///
  /// In en, this message translates to:
  /// **'What you see when the calendar opens, and what each part is for.'**
  String get calendarGuideScreenLead;

  /// Lead line of the calendar guide's events page
  ///
  /// In en, this message translates to:
  /// **'An event is anything with a day: an appointment, a bill, a class.'**
  String get calendarGuideEventsLead;

  /// Lead line of the calendar guide's event kinds page
  ///
  /// In en, this message translates to:
  /// **'Most events happen once; some come back every week or month.'**
  String get calendarGuideKindsLead;

  /// Lead line of the calendar guide's alerts page
  ///
  /// In en, this message translates to:
  /// **'Nothing rings by itself: you add a reminder or an alarm where you want one.'**
  String get calendarGuideAlertsLead;

  /// Lead line of the calendar guide's attendance page
  ///
  /// In en, this message translates to:
  /// **'For a class or a habit, the calendar can count the days you made it.'**
  String get calendarGuideAttendanceLead;

  /// Lead line of the calendar guide's categories page
  ///
  /// In en, this message translates to:
  /// **'A category gives an event its colour and icon.'**
  String get calendarGuideCategoriesLead;

  /// Lead line of the calendar guide's finding page
  ///
  /// In en, this message translates to:
  /// **'Search by name, hide what you do not need, or look at a whole year.'**
  String get calendarGuideFindingLead;

  /// Lead line of the calendar guide's setup page
  ///
  /// In en, this message translates to:
  /// **'Whose holidays, which day starts the week, the language and the look.'**
  String get calendarGuideSetupLead;

  /// Calendar guide row title about repeating-only features
  ///
  /// In en, this message translates to:
  /// **'What only a repeating event can do'**
  String get calendarGuideKindsOnlyRepeatTitle;

  /// Calendar guide paragraph about repeating-only features; the placeholders are the editor's labels
  ///
  /// In en, this message translates to:
  /// **'“{trackPresence}”, “{countOccurrences}” and a note per day appear once an event has more than one day. “{skippedDays}” in the editor lists the days you skipped; untick one to bring it back.'**
  String calendarGuideKindsOnlyRepeatBody(
    String trackPresence,
    String countOccurrences,
    String skippedDays,
  );

  /// Calendar guide row title about editing a repeating event
  ///
  /// In en, this message translates to:
  /// **'One change, every day'**
  String get calendarGuideKindsOneChangeTitle;

  /// Calendar guide paragraph about editing a repeating event
  ///
  /// In en, this message translates to:
  /// **'Editing a repeating event changes all of its days: a new time moves every session. To change one day, skip it and add a one-time event there.'**
  String get calendarGuideKindsOneChangeBody;

  /// Calendar guide row title about recurrence edge cases
  ///
  /// In en, this message translates to:
  /// **'Where repeating gets tricky'**
  String get calendarGuideKindsTrickyTitle;

  /// Calendar guide paragraph about recurrence edge cases; the placeholders are the repeat sheet's and the editor's labels
  ///
  /// In en, this message translates to:
  /// **'A monthly event on the 31st skips the months without one; a yearly one on 29 February shows only in leap years. “{ends}” inside “{repeat}” stops a rule after a date.'**
  String calendarGuideKindsTrickyBody(String ends, String repeat);

  /// Calendar guide row title about birthday events
  ///
  /// In en, this message translates to:
  /// **'Birthdays'**
  String get calendarGuideKindsBirthdayTitle;

  /// Calendar guide paragraph about birthday events; birthday is the built-in Birthday category's name
  ///
  /// In en, this message translates to:
  /// **'The “{birthday}” category makes a new event yearly and counts from 0: set the real birth date and the event reads the person\'s age.'**
  String calendarGuideKindsBirthdayBody(String birthday);

  /// Calendar guide row title about changing a category
  ///
  /// In en, this message translates to:
  /// **'Change one'**
  String get calendarGuideCatChangeTitle;

  /// Calendar guide paragraph about changing a category
  ///
  /// In en, this message translates to:
  /// **'Tap a category in the list to change its icon or colour. The built-in ones keep their names; your own can be renamed.'**
  String get calendarGuideCatChangeBody;

  /// Calendar guide row title about category alerts
  ///
  /// In en, this message translates to:
  /// **'An alert for a whole category'**
  String get calendarGuideCatAlertsTitle;

  /// Calendar guide paragraph about category alerts; the placeholders are the category page's and the editor's labels
  ///
  /// In en, this message translates to:
  /// **'Inside a category, “{addAlert}” sets an alert every event in it gets automatically. An event can switch it off for itself with “{categoryAlerts}”.'**
  String calendarGuideCatAlertsBody(String addAlert, String categoryAlerts);

  /// Calendar guide demo message for a menu row that opens another page; what is that page's label
  ///
  /// In en, this message translates to:
  /// **'In the real calendar this would open “{what}”.'**
  String calendarGuideWouldOpen(String what);

  /// Calendar guide demo message for the export row
  ///
  /// In en, this message translates to:
  /// **'In the real calendar this would share a file with every event.'**
  String get calendarGuideWouldShare;

  /// Calendar guide demo message for the guide's own menu row
  ///
  /// In en, this message translates to:
  /// **'That is this guide — you are already in it.'**
  String get calendarGuideYouAreHere;

  /// Calendar guide demo message after skipping a day
  ///
  /// In en, this message translates to:
  /// **'Skipped {date} for “{title}”; the other days stay.'**
  String calendarGuideDemoSkipped(String date, String title);

  /// Calendar guide action that resets a Try it card
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get calendarGuideDemoReset;

  /// Calendar guide action row that shows a demo alarm screen
  ///
  /// In en, this message translates to:
  /// **'Show me the alarm screen'**
  String get calendarGuideShowAlarm;

  /// Calendar guide demo wrapper for a real message that only happened in the sandbox
  ///
  /// In en, this message translates to:
  /// **'{message} — here only.'**
  String calendarGuideDemoHereOnly(String message);

  /// Calendar guide demo count of a holiday set's holidays in a year
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One public holiday in {year}} other{{count} public holidays in {year}}}'**
  String calendarGuideDemoHolidays(int count, String year);

  /// Calendar guide action row that opens the permissions page; permissions is the settings hub's Permissions row label
  ///
  /// In en, this message translates to:
  /// **'Open “{permissions}”'**
  String calendarGuideOpenPermissions(String permissions);

  /// Calendar guide action row that opens calendar settings; settingsRow is the calendar's settings label
  ///
  /// In en, this message translates to:
  /// **'Open “{settingsRow}”'**
  String calendarGuideOpenSettings(String settingsRow);

  /// Banner over the calendar guide's practice calendar
  ///
  /// In en, this message translates to:
  /// **'Nothing here is saved.'**
  String get calendarGuidePracticeBanner;

  /// Calendar guide coach line once every step of a Try it card is done
  ///
  /// In en, this message translates to:
  /// **'Done. Nothing here was real. Try anything, or go on.'**
  String get calendarGuideCoachDone;

  /// Tooltip of the calendar guide's button that skips the coach line's current step
  ///
  /// In en, this message translates to:
  /// **'Skip this step'**
  String get calendarGuideSkipStep;

  /// Tooltip of the calendar guide's button that shows the coach line of the step before the one shown again
  ///
  /// In en, this message translates to:
  /// **'Previous step'**
  String get calendarGuideStepBack;

  /// Tooltip of the calendar guide's button that, while an earlier step is shown again, moves one step toward the current instruction
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get calendarGuideStepForward;

  /// Spoken before a calendar guide coach line shown again for a step already done; a state, not a button
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get calendarGuideStepDone;

  /// Calendar guide coach instruction
  ///
  /// In en, this message translates to:
  /// **'Now tap the three dots at the top right: the calendar\'s menu.'**
  String get calendarGuideCoachScreenMore;

  /// Calendar guide coach instruction; day, timeline and upcoming are the panel modes' labels
  ///
  /// In en, this message translates to:
  /// **'Switch the panel at the bottom: “{day}”, “{timeline}”, “{upcoming}”.'**
  String calendarGuideCoachScreenPanel(
    String day,
    String timeline,
    String upcoming,
  );

  /// Calendar guide coach instruction; overview is the overview page's title in the calendar's title menu
  ///
  /// In en, this message translates to:
  /// **'Tap the title at the top and choose “{overview}”: the title is a menu of views.'**
  String calendarGuideCoachScreenOverview(String overview);

  /// Calendar guide coach instruction; report is the report page's title in the calendar's title menu
  ///
  /// In en, this message translates to:
  /// **'Tap the title at the top and choose “{report}”: it counts what happened.'**
  String calendarGuideCoachScreenReport(String report);

  /// Calendar guide coach instruction; overview is the overview page's title; year, month and list are the overview's mode chips' labels
  ///
  /// In en, this message translates to:
  /// **'In “{overview}”, tap “{year}”, “{month}” or “{list}”: three ways to see the same events.'**
  String calendarGuideCoachOverviewMode(
    String overview,
    String year,
    String month,
    String list,
  );

  /// Calendar guide coach instruction about the overview's period arrows and its Today button; overview is the overview page's title
  ///
  /// In en, this message translates to:
  /// **'In “{overview}”, the arrows step back and forward; the button between them returns to today.'**
  String calendarGuideCoachOverviewPeriod(String overview);

  /// Calendar guide coach instruction; save is the editor's Save label
  ///
  /// In en, this message translates to:
  /// **'Tap + to add an event. Give it a name, then tap “{save}”.'**
  String calendarGuideCoachEventsAdd(String save);

  /// Calendar guide coach instruction covering the whole trip: open an event from the list, its detail sheet's Edit, the editor's Save; edit and save are the detail sheet's and the editor's labels
  ///
  /// In en, this message translates to:
  /// **'Tap the event below, then “{edit}” at the top right, change the name, then “{save}”.'**
  String calendarGuideCoachEventsChange(String edit, String save);

  /// Calendar guide coach instruction; edit and deleteEvent are the detail sheet's and the editor's labels
  ///
  /// In en, this message translates to:
  /// **'To delete it: open it, “{edit}”, then “{deleteEvent}” at the bottom.'**
  String calendarGuideCoachEventsDelete(String edit, String deleteEvent);

  /// Calendar guide coach instruction; repeat, weekly and done are the editor's and the repeat sheet's labels
  ///
  /// In en, this message translates to:
  /// **'Tap “{repeat}”, choose “{weekly}”, then “{done}”.'**
  String calendarGuideCoachKindsRepeat(
    String repeat,
    String weekly,
    String done,
  );

  /// Calendar guide coach instruction; skip is the card's row label
  ///
  /// In en, this message translates to:
  /// **'Tap a day with a dot, then “{skip}”.'**
  String calendarGuideCoachKindsSkip(String skip);

  /// Calendar guide coach instruction; repeat and doesNotRepeat are the editor's and the repeat sheet's labels
  ///
  /// In en, this message translates to:
  /// **'Tap “{repeat}” again and choose “{doesNotRepeat}”.'**
  String calendarGuideCoachKindsOnce(String repeat, String doesNotRepeat);

  /// Calendar guide coach instruction; addDate is the Add date row's label
  ///
  /// In en, this message translates to:
  /// **'“{addDate}” gives a one-time event a second day. Try it.'**
  String calendarGuideCoachKindsAddDate(String addDate);

  /// Calendar guide coach instruction; addAlert and done are the editor's and the alert sheet's labels
  ///
  /// In en, this message translates to:
  /// **'Tap “{addAlert}”, choose when it should go off, then “{done}”.'**
  String calendarGuideCoachAlertsAdd(String addAlert, String done);

  /// Calendar guide coach instruction; showAlarm is the card's alarm row label
  ///
  /// In en, this message translates to:
  /// **'Now tap “{showAlarm}” to see how an alarm looks.'**
  String calendarGuideCoachAlertsShow(String showAlarm);

  /// Calendar guide coach instruction
  ///
  /// In en, this message translates to:
  /// **'Tap a day below to mark it missed; tap it again for present.'**
  String get calendarGuideCoachAttendanceMark;

  /// Calendar guide coach instruction; countOccurrences is the editor's switch label
  ///
  /// In en, this message translates to:
  /// **'Turn on “{countOccurrences}”, then pick how to count.'**
  String calendarGuideCoachAttendanceCount(String countOccurrences);

  /// Calendar guide coach instruction; createCategory and save are the categories page's and the form's labels
  ///
  /// In en, this message translates to:
  /// **'Tap “{createCategory}”: a name, an icon, a colour, then “{save}”.'**
  String calendarGuideCoachCategoriesCreate(String createCategory, String save);

  /// Calendar guide coach instruction; archive is the category row menu's Archive label
  ///
  /// In en, this message translates to:
  /// **'Tap the three dots on a category, then “{archive}”: it leaves the pickers; its events and alerts stay.'**
  String calendarGuideCoachCategoriesHide(String archive);

  /// Calendar guide coach instruction; delete is the category menu's Delete… item (categoryDeleteEllipsis), other the built-in Other category's name
  ///
  /// In en, this message translates to:
  /// **'Tap the three dots on your category, then “{delete}”: its events go to “{other}” — or choose where they go.'**
  String calendarGuideCoachCategoriesDelete(String delete, String other);

  /// Calendar guide coach instruction
  ///
  /// In en, this message translates to:
  /// **'Type a word, a category or a date: the list keeps only the matches.'**
  String get calendarGuideCoachFindingSearch;

  /// Calendar guide coach instruction; apply is the filter sheet's Apply label
  ///
  /// In en, this message translates to:
  /// **'Tap the funnel, hide a category, then “{apply}”.'**
  String calendarGuideCoachFindingFilter(String apply);

  /// Calendar guide coach instruction; holidaySet is the holiday set row's label
  ///
  /// In en, this message translates to:
  /// **'Tap “{holidaySet}” and pick your country.'**
  String calendarGuideCoachSetupHolidays(String holidaySet);

  /// Calendar guide coach instruction; weekStart is the week start row's label
  ///
  /// In en, this message translates to:
  /// **'Pick a day under “{weekStart}”.'**
  String calendarGuideCoachSetupWeek(String weekStart);

  /// Practice calendar tour instruction
  ///
  /// In en, this message translates to:
  /// **'Tap a day with a bar under it.'**
  String get calendarGuideTourPick;

  /// Practice calendar tour instruction covering the whole trip: open an event from the panel, its detail sheet's Edit, the editor's Save; edit and save are the detail sheet's and the editor's labels
  ///
  /// In en, this message translates to:
  /// **'Tap the event below, then “{edit}”, change it, then “{save}”.'**
  String calendarGuideTourEdit(String edit, String save);

  /// Practice calendar tour instruction
  ///
  /// In en, this message translates to:
  /// **'Tap + to add an event on the picked day.'**
  String get calendarGuideTourAdd;

  /// Practice calendar tour instruction; apply is the filter sheet's Apply label
  ///
  /// In en, this message translates to:
  /// **'The funnel at the top hides categories. Try it, then “{apply}”.'**
  String calendarGuideTourFilter(String apply);

  /// Practice calendar tour line once every step is done
  ///
  /// In en, this message translates to:
  /// **'That is the whole calendar. Nothing you did here was saved.'**
  String get calendarGuideTourDone;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Dentist'**
  String get calendarGuideDemoEventDentist;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Yoga'**
  String get calendarGuideDemoEventYoga;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get calendarGuideDemoEventRent;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Mum\'s birthday'**
  String get calendarGuideDemoEventBirthday;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Book club'**
  String get calendarGuideDemoEventBookClub;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Flight'**
  String get calendarGuideDemoEventFlight;

  /// Description of the Flight demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Gate opens two hours before.'**
  String get calendarGuideDemoEventFlightNote;

  /// Practice calendar filtering tour's first instruction, covering the whole trip: open the filter sheet from the funnel, its Categories row, Apply; categories is the filter sheet's Categories row label, apply its Apply label
  ///
  /// In en, this message translates to:
  /// **'Tap the funnel, then “{categories}”, untick one, then “{apply}”.'**
  String calendarGuideTourFilterCategory(String categories, String apply);

  /// Practice calendar filtering tour instruction; onlyShow is the filter sheet's Only show row label, apply its Apply label
  ///
  /// In en, this message translates to:
  /// **'Open the funnel again: try “{onlyShow}”, then “{apply}”.'**
  String calendarGuideTourFilterTrait(String onlyShow, String apply);

  /// Practice calendar filtering tour instruction; reset is the filter sheet's Reset filters label, apply its Apply label
  ///
  /// In en, this message translates to:
  /// **'In the funnel, tap “{reset}”, then “{apply}”.'**
  String calendarGuideTourFilterReset(String reset, String apply);

  /// Practice calendar filtering tour line once every step is done
  ///
  /// In en, this message translates to:
  /// **'Everything is back. A filter only hides, it never deletes.'**
  String get calendarGuideTourFilterDone;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Pilates'**
  String get calendarGuideDemoEventPilates;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Piano lesson'**
  String get calendarGuideDemoEventPiano;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Car insurance'**
  String get calendarGuideDemoEventInsurance;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Tax return'**
  String get calendarGuideDemoEventTax;

  /// Description of the Tax return demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Papers are in the blue folder.'**
  String get calendarGuideDemoEventTaxNote;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Team lunch'**
  String get calendarGuideDemoEventLunch;

  /// Name of a demo event in the calendar guide
  ///
  /// In en, this message translates to:
  /// **'Water the plants'**
  String get calendarGuideDemoEventPlants;

  /// Calendar guide hub row and page title: the fasting page
  ///
  /// In en, this message translates to:
  /// **'Fasting days'**
  String get calendarGuidePageFasting;

  /// Calendar guide hub row caption under the fasting page's title
  ///
  /// In en, this message translates to:
  /// **'Orthodox, Catholic, Muslim or Jewish fasts on the grid and in the day panel'**
  String get calendarGuidePageFastingCaption;

  /// Calendar guide: the line under the fasting page's heading
  ///
  /// In en, this message translates to:
  /// **'The calendar can mark the fast days of your tradition, with each day\'s rule.'**
  String get calendarGuideFastingLead;

  /// Calendar guide coach instruction on the fasting card: pick a tradition's chip under the grid
  ///
  /// In en, this message translates to:
  /// **'Pick a tradition under the grid: its fast days get a tint.'**
  String get calendarGuideCoachFastingTradition;

  /// Calendar guide coach instruction on the fasting card; appearance is the fasting appearance row's label
  ///
  /// In en, this message translates to:
  /// **'Tap “{appearance}” to show them as a tint, a bar or a bold day number.'**
  String calendarGuideCoachFastingStyle(String appearance);

  /// Calendar guide coach instruction on the fasting card; myPractice is the fasting schedule row's label
  ///
  /// In en, this message translates to:
  /// **'Tap “{myPractice}” to keep only the weekdays you fast on.'**
  String calendarGuideCoachFastingPractice(String myPractice);

  /// Calendar guide read row title on the fasting page
  ///
  /// In en, this message translates to:
  /// **'Where it is switched on'**
  String get calendarGuideFastingWhereTitle;

  /// Calendar guide read row body; calendarSettings is the Calendar settings row's label, fastingSection the fasting section's title
  ///
  /// In en, this message translates to:
  /// **'“{calendarSettings}” → “{fastingSection}”, one switch per tradition. Several can be on at once, each with its own look.'**
  String calendarGuideFastingWhereBody(
    String calendarSettings,
    String fastingSection,
  );

  /// Calendar guide read row title on the fasting page: the day panel's fasting row
  ///
  /// In en, this message translates to:
  /// **'What the row says'**
  String get calendarGuideFastingRulesTitle;

  /// Calendar guide read row body on the fasting page
  ///
  /// In en, this message translates to:
  /// **'The row names the fast and the day\'s rule: strict, wine and oil, fish, dairy, or dawn to sunset. The dates follow the common printed calendars; Muslim dates can differ by a day from the moon sighting.'**
  String get calendarGuideFastingRulesBody;

  /// Calendar guide read row title on the fasting page
  ///
  /// In en, this message translates to:
  /// **'Your own practice'**
  String get calendarGuideFastingPracticeTitle;

  /// Calendar guide read row body; myPractice is the fasting schedule row's label, applyTo the weekday scope's title, allFasts its All fasts choice
  ///
  /// In en, this message translates to:
  /// **'“{myPractice}” keeps only the weekdays you fast on, turns whole months off, and skips or adds single days. The long fasts still mark every one of their days unless “{applyTo}” is set to “{allFasts}”.'**
  String calendarGuideFastingPracticeBody(
    String myPractice,
    String applyTo,
    String allFasts,
  );

  /// Calendar guide read row title on the fasting page
  ///
  /// In en, this message translates to:
  /// **'Hiding them for a while'**
  String get calendarGuideFastingHideTitle;

  /// Calendar guide read row body; fasting is the filter sheet's fasting layer label, apply its Apply label
  ///
  /// In en, this message translates to:
  /// **'In the funnel, turn off “{fasting}” and tap “{apply}”: the fast days leave the grid and the panel until you turn it on again.'**
  String calendarGuideFastingHideBody(String fasting, String apply);

  /// Title of the calendar report page (what happened and what is planned over a period), also its row in the calendar's title view menu beside Calendar and Overview
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportTitle;

  /// Section label above the report's stat tiles
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get reportSectionTotals;

  /// Section label above the report's card of category groups: each chosen category with what happened in it over the period
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get reportSectionCategories;

  /// Section label above the report's column chart of occurrences per day, week or month
  ///
  /// In en, this message translates to:
  /// **'Over time'**
  String get reportSectionOverTime;

  /// Section label above the report's missed days, grouped by category
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get reportSectionMissed;

  /// Section label above the report's occurrences still to come in the period, grouped by category
  ///
  /// In en, this message translates to:
  /// **'Ahead'**
  String get reportSectionAhead;

  /// Report stat tile: occurrences that happened in the period up to today, missed ones excluded
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get reportTileEvents;

  /// Report stat tile: tracked occurrences attended, shown as attended of total
  ///
  /// In en, this message translates to:
  /// **'Attended'**
  String get reportTileAttended;

  /// Report stat tile: tracked occurrences missed
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get reportTileMissed;

  /// Report stat tile: hours spent on timed occurrences
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get reportTileHours;

  /// Report stat tile: ticked task items of all task items in the descriptions
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get reportTileTasks;

  /// Report stat tile of a future period: every occurrence planned in it
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get reportTilePlanned;

  /// Report stat tile value: a part of a whole, e.g. 21 of 24 attended or 9 of 12 tasks ticked; both numbers already formatted
  ///
  /// In en, this message translates to:
  /// **'{value} of {total}'**
  String reportOfTotal(String value, String total);

  /// Under the report's Tasks tile: how many task items are still unticked
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 open} other {{count} open}}'**
  String reportTasksOpen(int count);

  /// Under the report's Attended tile: the share attended, a whole number
  ///
  /// In en, this message translates to:
  /// **'{percent} %'**
  String reportPercent(String percent);

  /// Screen reader wording of the Attended tile's share
  ///
  /// In en, this message translates to:
  /// **'{percent} percent'**
  String reportPercentSpoken(String percent);

  /// Decimal hours in the report, e.g. 18.5 h; hours is already formatted with the locale's decimal separator
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String reportHours(String hours);

  /// First part of the caption under the report's tiles: the last day counted, e.g. To 30 October
  ///
  /// In en, this message translates to:
  /// **'To {date}'**
  String reportCaptionTo(String date);

  /// Part of the caption under the report's tiles naming the period the tiles' changes compare against
  ///
  /// In en, this message translates to:
  /// **'against {period}'**
  String reportCaptionAgainst(String period);

  /// Part of the caption under the report's tiles: skipped days in the counted part of the period
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 skipped} other {{count} skipped}}'**
  String reportSkippedCount(int count);

  /// Part of the caption under the report's tiles: occurrences still to come in the period
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 ahead} other {{count} ahead}}'**
  String reportAheadCount(int count);

  /// Report band subtitle: occurrences that happened in the period
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 event} other {{count} events}}'**
  String reportEventCount(int count);

  /// Report band subtitle of a future period: occurrences planned in it
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 planned} other {{count} planned}}'**
  String reportPlannedCount(int count);

  /// Caption under the report's tiles when the period holds no occurrence, shown after the period's name and a dot ("October 2026 · Nothing happened")
  ///
  /// In en, this message translates to:
  /// **'Nothing happened'**
  String get reportCaptionNothing;

  /// Screen reader wording of a report tile's change against the previous period, when it grew
  ///
  /// In en, this message translates to:
  /// **'{delta} more than {period}'**
  String reportDeltaMore(String delta, String period);

  /// Screen reader wording of a report tile's change against the previous period, when it shrank
  ///
  /// In en, this message translates to:
  /// **'{delta} less than {period}'**
  String reportDeltaLess(String delta, String period);

  /// Screen reader wording of a report count tile's change against the previous period, when it grew (events, planned, attended, missed, tasks; hours use reportDeltaMore)
  ///
  /// In en, this message translates to:
  /// **'{delta, plural, one {{delta} more than {period}} other {{delta} more than {period}}}'**
  String reportDeltaMoreCount(int delta, String period);

  /// Screen reader wording of a report count tile's change against the previous period, when it shrank (events, planned, attended, missed, tasks; hours use reportDeltaLess)
  ///
  /// In en, this message translates to:
  /// **'{delta, plural, one {{delta} fewer than {period}} other {{delta} fewer than {period}}}'**
  String reportDeltaFewerCount(int delta, String period);

  /// Screen reader wording of a report tile that did not change against the previous period
  ///
  /// In en, this message translates to:
  /// **'same as {period}'**
  String reportDeltaSame(String period);

  /// Screen reader wording of a report tile that has nothing in the period (drawn as a dash)
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get reportTileNone;

  /// Report Period menu item: the calendar week before this one
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get reportPeriodLastWeek;

  /// Report Period menu item: the calendar week after this one
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get reportPeriodNextWeek;

  /// Report Period menu item: the calendar month before this one
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get reportPeriodLastMonth;

  /// Report Period menu item: the calendar month after this one
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get reportPeriodNextMonth;

  /// Report footer row opening the overview's list on the report's period and categories
  ///
  /// In en, this message translates to:
  /// **'Show as list'**
  String get reportShowAsList;

  /// Report footer row sharing the report as text
  ///
  /// In en, this message translates to:
  /// **'Share report'**
  String get reportShare;

  /// Progress message while the report is written as a Markdown file for sharing
  ///
  /// In en, this message translates to:
  /// **'Exporting report...'**
  String get exportingReport;

  /// Snackbar after the report was handed to the share sheet as a Markdown file
  ///
  /// In en, this message translates to:
  /// **'Report exported'**
  String get reportExported;

  /// Snackbar prefix when the report could not be written or shared; the error message follows after a colon
  ///
  /// In en, this message translates to:
  /// **'Could not export the report'**
  String get reportExportError;

  /// Report footer row on a week period, setting up a weekly notification with this report
  ///
  /// In en, this message translates to:
  /// **'Send me this report weekly'**
  String get reportSendWeekly;

  /// Report footer row on a month or longer period, setting up a monthly notification with this report
  ///
  /// In en, this message translates to:
  /// **'Send me this report monthly'**
  String get reportSendMonthly;

  /// Legend item of the report's Over time chart for the occurrences that took place; the other item reuses reportTileMissed
  ///
  /// In en, this message translates to:
  /// **'Happened'**
  String get reportLegendHappened;

  /// Caption under the report's Over time chart naming the weekday with the most occurrences, e.g. Most on Monday
  ///
  /// In en, this message translates to:
  /// **'Most on {weekday}'**
  String reportTrendBusiest(String weekday);

  /// Part of the caption under the report's Over time chart: the usual start and end time of the timed occurrences, e.g. usually 18:00 – 19:30
  ///
  /// In en, this message translates to:
  /// **'usually {from} – {to}'**
  String reportTrendUsual(String from, String to);

  /// Part of the caption under the report's Over time chart when the occurrences have a usual start time but no duration, e.g. usually at 18:00
  ///
  /// In en, this message translates to:
  /// **'usually at {time}'**
  String reportTrendUsualAt(String time);

  /// Spoken summary of the report's Over time chart when it has no caption: the tallest column's count and the day, week or month it covers, e.g. Peak 2 on Monday, October 5
  ///
  /// In en, this message translates to:
  /// **'Peak {peak} on {date}'**
  String reportTrendPeak(String peak, String date);

  /// What a screen reader hears for the report's Over time chart: the section name, then the chart's caption or its peak
  ///
  /// In en, this message translates to:
  /// **'Over time. {summary}'**
  String reportTrendSpoken(String summary);

  /// Spoken summary of the report's Over time chart with one column per week and no caption: the tallest column's count and the first day of its week, e.g. Peak 4 in the week of October 5
  ///
  /// In en, this message translates to:
  /// **'Peak {peak} in the week of {date}'**
  String reportTrendPeakWeek(String peak, String date);

  /// Spoken summary of the report's Over time chart with one column per month and no caption: the tallest column's count and its month, e.g. Peak 12 in October 2026
  ///
  /// In en, this message translates to:
  /// **'Peak {peak} in {month}'**
  String reportTrendPeakMonth(String peak, String month);

  /// Start of a report stat tile's detail line when the tiles are too narrow for '21 of 24' in the value: the whole the large figure is a part of, e.g. of 24 · 88 %
  ///
  /// In en, this message translates to:
  /// **'of {total}'**
  String reportOfTotalOnly(String total);

  /// Row at the end of a report category group that shows the group's remaining events in place
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 more} other {{count} more}}'**
  String reportGroupMore(int count);

  /// Row under the report's Categories card when more categories have events than the card shows; opens the rest
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 more category} other {{count} more categories}}'**
  String reportMoreCategories(int count);

  /// Title of the sheet listing the report's categories past the ones the Categories card shows
  ///
  /// In en, this message translates to:
  /// **'More categories'**
  String get reportMoreCategoriesTitle;

  /// What a screen reader says for the report group's 'n more' row; category is the group's category name
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 more in {category}} other {{count} more in {category}}}'**
  String reportGroupMoreSpoken(int count, String category);

  /// Row at the end of an expanded report category group that folds it back to its first rows
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get reportGroupLess;

  /// What a screen reader says for the report group's 'Show less' row; category is the group's category name
  ///
  /// In en, this message translates to:
  /// **'Show less of {category}'**
  String reportGroupLessSpoken(String category);

  /// Caption of a routine's row in the report: attended days of the days it ran, e.g. 8 of 10 attended
  ///
  /// In en, this message translates to:
  /// **'{total, plural, one {{attended} of 1 attended} other {{attended} of {total} attended}}'**
  String reportAttendedOf(int total, int attended);

  /// Part of a report row's subtitle: ticked task items of the items in the event's description, e.g. 5 of 8 tasks
  ///
  /// In en, this message translates to:
  /// **'{total, plural, one {{ticked} of 1 task} other {{ticked} of {total} tasks}}'**
  String reportTasksOf(int total, int ticked);

  /// Decimal hours as a screen reader says them in the report, e.g. 13.2 hours; hours is already formatted with the locale's decimal separator
  ///
  /// In en, this message translates to:
  /// **'{hours} hours'**
  String reportHoursSpoken(String hours);

  /// A whole number of hours as a screen reader says them in the report
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 hour} other {{count} hours}}'**
  String reportWholeHoursSpoken(int count);

  /// Minutes under an hour as a screen reader says them in the report
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 minute} other {{count} minutes}}'**
  String reportMinutesSpoken(int count);

  /// The day that opens a report row's subtitle, e.g. Thu 8; weekday is the short weekday name, day the day of the month
  ///
  /// In en, this message translates to:
  /// **'{weekday} {day}'**
  String reportRowDay(String weekday, String day);

  /// The day that opens a report row's subtitle when the period spans several months, e.g. Thu 8 Oct; month is the short month name
  ///
  /// In en, this message translates to:
  /// **'{weekday} {day} {month}'**
  String reportRowDayMonth(String weekday, String day, String month);

  /// What a screen reader says for the 'Show as list' row under a long report category group; category is the group's category name
  ///
  /// In en, this message translates to:
  /// **'Show {category} as a list'**
  String reportGroupListSpoken(String category);

  /// Calendar guide hub row and page title: the Report page
  ///
  /// In en, this message translates to:
  /// **'See what happened'**
  String get calendarGuidePageReport;

  /// Calendar guide hub row caption under the Report page's title
  ///
  /// In en, this message translates to:
  /// **'Totals, missed days and what is ahead'**
  String get calendarGuidePageReportCaption;

  /// Calendar guide: the line under the Report page's heading; report is the Report page's name
  ///
  /// In en, this message translates to:
  /// **'“{report}” counts a week, a month or a year, category by category.'**
  String calendarGuideReportLead(String report);

  /// Calendar guide row title on the Report page: where the Report is opened
  ///
  /// In en, this message translates to:
  /// **'Opening it'**
  String get calendarGuideReportOpenTitle;

  /// Calendar guide paragraph: the title menu's three pages, then the Report's period; calendar, overview and report are the pages' names, thisWeek, lastMonth and custom three of the period menu's rows
  ///
  /// In en, this message translates to:
  /// **'Open it from the title: “{calendar}” · “{overview}” · “{report}”. The title between the arrows picks the period — “{thisWeek}”, “{lastMonth}”, “{custom}”; the arrows step by the period\'s own length.'**
  String calendarGuideReportOpenBody(
    String calendar,
    String overview,
    String report,
    String thisWeek,
    String lastMonth,
    String custom,
  );

  /// Calendar guide row title on the Report page: choosing the categories
  ///
  /// In en, this message translates to:
  /// **'Which categories'**
  String get calendarGuideReportCategoriesTitle;

  /// Calendar guide paragraph about the Report's category filter and its groups; categories is the filter button's tooltip, max the most groups the card shows, moreCategories the card's 'n more categories' row label with a sample count, rows the rows a group opens at, more a group's 'n more' row label with a sample count
  ///
  /// In en, this message translates to:
  /// **'The “{categories}” button narrows the page to the ones you choose; below, one group per category, with a meter against the biggest — past {max} categories the rest sit behind “{moreCategories}”, which opens a sheet. A group opens at {rows} rows; “{more}” shows the rest in place, a tap on its header folds it.'**
  String calendarGuideReportCategoriesBody(
    String categories,
    int max,
    String moreCategories,
    int rows,
    String more,
  );

  /// Calendar guide row title on the Report page: the Missed card
  ///
  /// In en, this message translates to:
  /// **'What you missed'**
  String get calendarGuideReportMissedTitle;

  /// Calendar guide paragraph about the Report's Missed card; missed is the card's title, markPresent the presence button's tooltip on a missed row
  ///
  /// In en, this message translates to:
  /// **'“{missed}” lists the sessions you marked or assumed absent; tap “{markPresent}” beside a row and the numbers update.'**
  String calendarGuideReportMissedBody(String missed, String markPresent);

  /// Calendar guide row title on the Report page: the weekly or monthly report notification
  ///
  /// In en, this message translates to:
  /// **'Every week or month by itself'**
  String get calendarGuideReportDigestTitle;

  /// Calendar guide paragraph about the report digest and sharing; weekly and monthly are the Report footer's row on a week and on a month, shows the digest editor's Shows row and weekReport and monthReport its two report values, share the share row's label
  ///
  /// In en, this message translates to:
  /// **'On a week “{weekly}”, on a month “{monthly}”, opens a digest of the period just ended — save it and it arrives on the first day of the next week or month: a digest with “{shows}” set to “{weekReport}” or “{monthReport}”. “{share}” writes the page as Markdown.'**
  String calendarGuideReportDigestBody(
    String weekly,
    String monthly,
    String shows,
    String weekReport,
    String monthReport,
    String share,
  );

  /// The kept chip of a marked occurrence in the event detail sheet, for a category whose kind marks a task or a chore done
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get markVerbDone;

  /// The kept chip of a marked occurrence in the event detail sheet, for a workout, an appointment or a class
  ///
  /// In en, this message translates to:
  /// **'Attended'**
  String get markVerbAttended;

  /// The kept chip of a marked occurrence in the event detail sheet, for a medication
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get markVerbTaken;

  /// The kept chip of a marked occurrence in the event detail sheet, for a bill
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get markVerbPaid;

  /// The kept chip of a marked occurrence in the event detail sheet, for an income
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get markVerbReceived;

  /// The kept chip of a marked occurrence in the event detail sheet, for a social plan
  ///
  /// In en, this message translates to:
  /// **'Met'**
  String get markVerbMet;

  /// The kept chip of a marked occurrence in the event detail sheet, for an expiry
  ///
  /// In en, this message translates to:
  /// **'Renewed'**
  String get markVerbRenewed;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Done
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get eventMarkDone;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Attended
  ///
  /// In en, this message translates to:
  /// **'Mark as attended'**
  String get eventMarkAttended;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Taken
  ///
  /// In en, this message translates to:
  /// **'Mark as taken'**
  String get eventMarkTaken;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Paid
  ///
  /// In en, this message translates to:
  /// **'Mark as paid'**
  String get eventMarkPaid;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Received
  ///
  /// In en, this message translates to:
  /// **'Mark as received'**
  String get eventMarkReceived;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Met
  ///
  /// In en, this message translates to:
  /// **'Mark as met'**
  String get eventMarkMet;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose verb is Renewed
  ///
  /// In en, this message translates to:
  /// **'Mark as renewed'**
  String get eventMarkRenewed;

  /// Tooltip on a row's button that returns a missed occurrence to kept, for a category whose owner wrote their own word for a kept mark
  ///
  /// In en, this message translates to:
  /// **'Mark as {verb}'**
  String eventMarkAsVerb(String verb);

  /// Action in the event detail sheet that cancels a one-time event, keeping it so it can be restored
  ///
  /// In en, this message translates to:
  /// **'Cancel this event'**
  String get eventCancelEvent;

  /// Row in the event detail sheet of a one-time event that was cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get eventCancelledState;

  /// Action in the event detail sheet that brings a cancelled one-time event back
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get eventRestoreEvent;

  /// Confirmation after cancelling a one-time event, with an Undo
  ///
  /// In en, this message translates to:
  /// **'Event cancelled'**
  String get eventCancelled;

  /// Section label in the category editor over the Kind, Mark and Area rows: what the Report treats the category as
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get categoryReportSection;

  /// Section label in the category editor over the Measure, Counts as and Goal rows
  ///
  /// In en, this message translates to:
  /// **'Measure & goal'**
  String get categoryMeasureGoalSection;

  /// Row label in the category editor, and the title of the kind picker: what the category is for (Workout, Bill, …)
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get categoryKindLabel;

  /// Category kind: a habit kept on a rhythm
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get categoryKindRoutine;

  /// Category kind: training sessions
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get categoryKindWorkout;

  /// Category kind: pills and supplements taken
  ///
  /// In en, this message translates to:
  /// **'Medication'**
  String get categoryKindMedication;

  /// Category kind: the night's sleep and its length
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get categoryKindSleep;

  /// Category kind: an illness, a symptom, a cycle
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get categoryKindEpisode;

  /// Category kind: doctor, dentist and other appointments
  ///
  /// In en, this message translates to:
  /// **'Appointment'**
  String get categoryKindAppointment;

  /// Category kind: shifts and working days
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get categoryKindWork;

  /// Category kind: calls and meetings
  ///
  /// In en, this message translates to:
  /// **'Meeting'**
  String get categoryKindMeeting;

  /// Category kind: to-dos and errands
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get categoryKindTask;

  /// Category kind: submissions and filings due on a day
  ///
  /// In en, this message translates to:
  /// **'Deadline'**
  String get categoryKindDeadline;

  /// Category kind: courses, practice, reading
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get categoryKindStudy;

  /// Category kind: rent, bills, subscriptions to pay
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get categoryKindBill;

  /// Category kind: salary and payments received
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get categoryKindIncome;

  /// Category kind: time with people
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get categoryKindSocial;

  /// Category kind: birthdays and name days
  ///
  /// In en, this message translates to:
  /// **'Anniversary'**
  String get categoryKindAnniversary;

  /// Category kind: housework
  ///
  /// In en, this message translates to:
  /// **'Chore'**
  String get categoryKindChore;

  /// Category kind: car service, boiler and other upkeep
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get categoryKindMaintenance;

  /// Category kind: documents and warranties that expire
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get categoryKindExpiry;

  /// Category kind: travel
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get categoryKindTrip;

  /// Category kind: vacation and days off
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get categoryKindLeave;

  /// Category kind: anything else, the kind of a category nobody set one for
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get categoryKindCustom;

  /// Examples under the Routine kind. At most 28 characters and three items
  ///
  /// In en, this message translates to:
  /// **'Stretching, journaling'**
  String get categoryKindExampleRoutine;

  /// Examples under the Workout kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Gym, run, swim, class'**
  String get categoryKindExampleWorkout;

  /// Examples under the Medication kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Pills, supplements'**
  String get categoryKindExampleMedication;

  /// What the Sleep kind holds. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'The night and its length'**
  String get categoryKindExampleSleep;

  /// Examples under the Episode kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Illness, migraine, cycle'**
  String get categoryKindExampleEpisode;

  /// Examples under the Appointment kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Doctor, dentist, vet'**
  String get categoryKindExampleAppointment;

  /// Examples under the Work kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Shifts, working days'**
  String get categoryKindExampleWork;

  /// Examples under the Meeting kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Calls, stand-ups, reviews'**
  String get categoryKindExampleMeeting;

  /// Examples under the Task kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'To-dos, errands'**
  String get categoryKindExampleTask;

  /// Examples under the Deadline kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Submissions, filings'**
  String get categoryKindExampleDeadline;

  /// Examples under the Study kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Courses, practice, reading'**
  String get categoryKindExampleStudy;

  /// Examples under the Bill kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Rent, bills, subscriptions'**
  String get categoryKindExampleBill;

  /// Examples under the Income kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Salary, paid invoices'**
  String get categoryKindExampleIncome;

  /// Examples under the Social kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Dinners, visits, dates'**
  String get categoryKindExampleSocial;

  /// Examples under the Anniversary kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Birthdays, name days'**
  String get categoryKindExampleAnniversary;

  /// Examples under the Chore kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Cleaning, laundry, groceries'**
  String get categoryKindExampleChore;

  /// Examples under the Maintenance kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Car service, boiler'**
  String get categoryKindExampleMaintenance;

  /// Examples under the Expiry kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Passport, ID, warranty'**
  String get categoryKindExampleExpiry;

  /// Examples under the Trip kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Travel, weekends away'**
  String get categoryKindExampleTrip;

  /// Examples under the Leave kind. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Vacation, days off'**
  String get categoryKindExampleLeave;

  /// What the Custom kind holds. At most 28 characters
  ///
  /// In en, this message translates to:
  /// **'Anything else'**
  String get categoryKindExampleCustom;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get lifeAreaHealth;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get lifeAreaWork;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get lifeAreaMoney;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get lifeAreaPeople;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get lifeAreaHome;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'Leisure'**
  String get lifeAreaLeisure;

  /// Life area a category belongs to; also a group label in the kind picker
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get lifeAreaOther;

  /// Row label in the category editor: the word a kept mark is read as (Done, Paid, …)
  ///
  /// In en, this message translates to:
  /// **'Mark'**
  String get categoryMarkLabel;

  /// The Mark row's value and menu item when the category's events are not marked
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get categoryMarkOff;

  /// Mark menu item that opens a dialog for the owner's own word
  ///
  /// In en, this message translates to:
  /// **'Own word…'**
  String get categoryMarkOwn;

  /// Title of the dialog where the owner types their own word for a kept mark
  ///
  /// In en, this message translates to:
  /// **'Mark word'**
  String get categoryMarkOwnTitle;

  /// Hint in the mark word dialog's field
  ///
  /// In en, this message translates to:
  /// **'e.g. Walked'**
  String get categoryMarkOwnHint;

  /// Row label in the category editor: the life area the category's hours count toward
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get categoryAreaLabel;

  /// Row label in the category editor: the number the Report leads the category with
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get categoryMeasureLabel;

  /// The Measure row's value while the kind's own measure leads, and the menu item for it
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get categoryMeasureAuto;

  /// Caption under the Measure row: the measure Auto stands for under the category's kind
  ///
  /// In en, this message translates to:
  /// **'Auto is {measure}'**
  String categoryMeasureAutoIs(String measure);

  /// Caption under the Measure row for a Custom category: the Report picks the measure for each period it shows
  ///
  /// In en, this message translates to:
  /// **'Auto picks per period'**
  String get categoryMeasureAutoPerPeriod;

  /// The Measure menu's first item: Auto, naming the measure it stands for
  ///
  /// In en, this message translates to:
  /// **'Auto · {measure}'**
  String categoryMeasureAutoWith(String measure);

  /// Measure: how many days the category's events took
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get categoryMeasureCount;

  /// Measure: how many of the category's events happened
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get categoryMeasureEvents;

  /// Measure: the hours the category's events took
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get categoryMeasureHours;

  /// Measure: the share of tracked occurrences kept
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get categoryMeasureAttendance;

  /// Measure: the task boxes ticked in the events' descriptions
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get categoryMeasureTasks;

  /// Measure: the money the events' linked notes record
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get categoryMeasureMoney;

  /// Measure: how long since the category last happened
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get categoryMeasureLastSeen;

  /// Measure: how many days until the next occurrence (an expiry)
  ///
  /// In en, this message translates to:
  /// **'Days until'**
  String get categoryMeasureDaysUntil;

  /// Measure: how many of the category's occurrences were cancelled; never offered as a primary, named when one is stored
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get categoryMeasureCancelled;

  /// Measure: how far ahead the category's events were planned; never offered as a primary, named when one is stored
  ///
  /// In en, this message translates to:
  /// **'Lead time'**
  String get categoryMeasureLeadTime;

  /// Measure: the time of day the category's events start; never offered as a primary, named when one is stored
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get categoryMeasureTiming;

  /// Row label in the category editor: how long an untimed event counts for in the hours
  ///
  /// In en, this message translates to:
  /// **'Counts as'**
  String get categoryCountsAsLabel;

  /// The Counts as row's value and menu item when untimed events earn no hours
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get categoryCountsAsOff;

  /// Caption under the Counts as row: the kind's suggested length, which applies only once picked
  ///
  /// In en, this message translates to:
  /// **'Suggested: {duration}'**
  String categoryCountsAsSuggested(String duration);

  /// Counts as menu item that is the kind's suggestion
  ///
  /// In en, this message translates to:
  /// **'{duration} · suggested'**
  String categoryCountsAsSuggestedItem(String duration);

  /// Caption under the Counts as row when the kind suggests no length
  ///
  /// In en, this message translates to:
  /// **'For untimed events'**
  String get categoryCountsAsScope;

  /// Caption under the disabled Counts as row of a Sleep category
  ///
  /// In en, this message translates to:
  /// **'Sleep keeps its own hours'**
  String get categoryCountsAsSleep;

  /// Caption under the disabled Counts as row of a category whose events all repeat untracked
  ///
  /// In en, this message translates to:
  /// **'Repeats earn no counted hours'**
  String get categoryCountsAsRepeats;

  /// Row label in the category editor that opens the goal sheet
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get categoryGoalLabel;

  /// Caption under the Goal row while no goal is set
  ///
  /// In en, this message translates to:
  /// **'No goal'**
  String get categoryGoalNone;

  /// Caption under the disabled Goal row while the measure is Auto on a Custom category
  ///
  /// In en, this message translates to:
  /// **'Pick a measure first'**
  String get categoryGoalNeedsMeasure;

  /// Caption under the disabled Goal row when the measure takes no goal
  ///
  /// In en, this message translates to:
  /// **'No goal for {measure}'**
  String categoryGoalNotFor(String measure);

  /// Title of the goal sheet
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get categoryGoalTitle;

  /// Section label in the goal sheet over the goal's types
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get categoryGoalTypeSection;

  /// Section label in the goal sheet over the goal's value and period
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get categoryGoalTargetSection;

  /// Goal type: at least this much per period
  ///
  /// In en, this message translates to:
  /// **'At least'**
  String get categoryGoalTypeAtLeast;

  /// Goal type: at most this much per period
  ///
  /// In en, this message translates to:
  /// **'At most'**
  String get categoryGoalTypeAtMost;

  /// Goal type on a money measure: at most this much money per period
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get categoryGoalTypeBudget;

  /// Goal type: at most this many days between two occurrences
  ///
  /// In en, this message translates to:
  /// **'Days between'**
  String get categoryGoalTypeMaxGap;

  /// Caption under a stored goal type the category's measure does not offer (synced from another device), shown checked so the goal can be kept or changed
  ///
  /// In en, this message translates to:
  /// **'Not for this measure'**
  String get categoryGoalTypeNotForMeasure;

  /// Label of the goal sheet's value row when the goal counts occurrences
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get categoryGoalUnitCount;

  /// Label of the goal sheet's value row when the goal counts hours
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get categoryGoalUnitHours;

  /// Label of the goal sheet's value row when the goal counts tasks
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get categoryGoalUnitTasks;

  /// Label of the goal sheet's value row when the goal counts money
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get categoryGoalUnitAmount;

  /// Label of the goal sheet's value row for a Days between goal
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get categoryGoalUnitDays;

  /// A goal's amount in hours, inside the goal's read-back; the number arrives formatted (1,200 or 7.5)
  ///
  /// In en, this message translates to:
  /// **'{hours} h'**
  String categoryGoalHours(String hours);

  /// A goal's amount in tasks, inside the goal's read-back
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task} other{{count} tasks}}'**
  String categoryGoalTasks(int count);

  /// Tooltip of the goal value's minus button
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get categoryGoalLess;

  /// Tooltip of the goal value's plus button
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get categoryGoalMore;

  /// Goal period chip
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get categoryGoalPeriodDay;

  /// Goal period chip
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get categoryGoalPeriodWeek;

  /// Goal period chip
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get categoryGoalPeriodMonth;

  /// Goal period chip
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get categoryGoalPeriodYear;

  /// A goal read back: at least an amount per period
  ///
  /// In en, this message translates to:
  /// **'At least {amount} {period, select, day{a day} week{a week} month{a month} year{a year} other{}}'**
  String categoryGoalAtLeast(String amount, String period);

  /// A goal read back: at most an amount per period
  ///
  /// In en, this message translates to:
  /// **'At most {amount} {period, select, day{a day} week{a week} month{a month} year{a year} other{}}'**
  String categoryGoalAtMost(String amount, String period);

  /// A money goal read back: at most this much money per period
  ///
  /// In en, this message translates to:
  /// **'Budget {amount} {period, select, day{a day} week{a week} month{a month} year{a year} other{}}'**
  String categoryGoalBudget(String amount, String period);

  /// A Days between goal read back
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{At most 1 day between} other{At most {days} days between}}'**
  String categoryGoalGap(int days);

  /// Destructive row at the foot of the goal sheet
  ///
  /// In en, this message translates to:
  /// **'Remove goal'**
  String get categoryGoalRemove;

  /// Report page: label of the card listing each category's goal and where it stands
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get reportSectionGoals;

  /// Report page: label of the card with the few things worth noticing in the period
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get reportSectionInsights;

  /// Report page: label of the card listing what is overdue, due, expiring or not marked
  ///
  /// In en, this message translates to:
  /// **'Due soon'**
  String get reportSectionDueSoon;

  /// Report Goals card caption, an at-least count goal still open: how many are still needed before the period ends, e.g. one more by Sunday
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{one more by {day}} other{{count} more by {day}}}'**
  String reportGoalMoreBy(int count, String day);

  /// Report Goals card caption, an at-least count goal per day still open: how many are still needed today
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{one more today} other{{count} more today}}'**
  String reportGoalMoreToday(int count);

  /// Report Goals card caption, an at-least hours or money goal still open: what is still needed before the period ends, e.g. 2 h more by Sunday
  ///
  /// In en, this message translates to:
  /// **'{amount} more by {day}'**
  String reportGoalAmountMoreBy(String amount, String day);

  /// Report Goals card caption, an at-least hours or money goal per day still open: what is still needed today
  ///
  /// In en, this message translates to:
  /// **'{amount} more today'**
  String reportGoalAmountMoreToday(String amount);

  /// Report Goals card caption: an at-least goal already reached before its period ends; period is the goal's period (day, week, month or year)
  ///
  /// In en, this message translates to:
  /// **'{period, select, day{done for today} week{done for the week} month{done for the month} year{done for the year} other{done}}'**
  String reportGoalDone(String period);

  /// Report Goals card caption, an at-most or budget goal: what is left before the limit, e.g. 9 h left
  ///
  /// In en, this message translates to:
  /// **'{amount} left'**
  String reportGoalLeft(String amount);

  /// Report Goals card caption, an at-most or budget goal when the report shows a longer span than the goal's period: what is left in the current period; period is day, week, month or year
  ///
  /// In en, this message translates to:
  /// **'{amount} left {period, select, day{today} week{this week} month{this month} year{this year} other{}}'**
  String reportGoalLeftIn(String amount, String period);

  /// Report Goals card caption, an at-most or budget goal past its limit: by how much, e.g. 4 h over
  ///
  /// In en, this message translates to:
  /// **'{amount} over'**
  String reportGoalOver(String amount);

  /// Report Goals card caption: an at-least goal whose closed period reached its target
  ///
  /// In en, this message translates to:
  /// **'Met'**
  String get reportGoalMet;

  /// Report Goals card caption: an at-least goal whose closed period fell short of its target
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get reportGoalMissed;

  /// Report Goals card caption: an at-most or budget goal whose closed period stayed within its limit
  ///
  /// In en, this message translates to:
  /// **'Within'**
  String get reportGoalWithin;

  /// Report Goals card caption: an at-most or budget goal whose closed period went past its limit
  ///
  /// In en, this message translates to:
  /// **'Over'**
  String get reportGoalOverWord;

  /// Report Goals card caption for a past span holding several goal periods: how many of them met the goal, e.g. 3 of 4 weeks met; period is day, week, month or year
  ///
  /// In en, this message translates to:
  /// **'{total, plural, one{{met} of 1 {period, select, day{day} week{week} month{month} year{year} other{period}} met} other{{met} of {total} {period, select, day{days} week{weeks} month{months} year{years} other{periods}} met}}'**
  String reportGoalPeriodsMet(int met, int total, String period);

  /// Report Goals card caption for a future period: what is planned against the goal's target, e.g. 2 of 3 planned; both already formatted
  ///
  /// In en, this message translates to:
  /// **'{value} of {target} planned'**
  String reportGoalPlanned(String value, String target);

  /// Report Goals card caption, a days-between goal: days since the category last happened
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{1 day} other{{days} days}}'**
  String reportGoalGapDays(int days);

  /// Report Goals card caption, a days-between goal whose category has not happened yet
  ///
  /// In en, this message translates to:
  /// **'None yet'**
  String get reportGoalGapNone;

  /// Report Goals card caption, a days-between goal last kept before the year the report looks back over
  ///
  /// In en, this message translates to:
  /// **'Over a year'**
  String get reportGoalGapLong;

  /// Report Goals card caption, a days-between goal: the most days allowed between two occurrences, e.g. limit 14
  ///
  /// In en, this message translates to:
  /// **'limit {limit}'**
  String reportGoalLimit(int limit);

  /// Report Goals card caption's last part: consecutive periods the goal was met, e.g. 4 in a row
  ///
  /// In en, this message translates to:
  /// **'{count} in a row'**
  String reportGoalStreak(int count);

  /// Screen reader wording of a goal's streak, and an insight: consecutive periods met, e.g. 4 weeks in a row; period is day, week, month or year
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 {period, select, day{day} week{week} month{month} year{year} other{period}} in a row} other{{count} {period, select, day{days} week{weeks} month{months} year{years} other{periods}} in a row}}'**
  String reportGoalStreakSpoken(int count, String period);

  /// Screen reader wording of a goal row's state glyph: the target was reached
  ///
  /// In en, this message translates to:
  /// **'met'**
  String get reportGoalStateMet;

  /// Screen reader wording of a goal row's state glyph: on track to reach the goal
  ///
  /// In en, this message translates to:
  /// **'on pace'**
  String get reportGoalStateOnPace;

  /// Screen reader wording of a goal row's state glyph: behind the even pace
  ///
  /// In en, this message translates to:
  /// **'behind'**
  String get reportGoalStateBehind;

  /// Screen reader wording of a goal row's state glyph: past an at-most or budget limit
  ///
  /// In en, this message translates to:
  /// **'over'**
  String get reportGoalStateOver;

  /// Screen reader wording of a goal row's state glyph: a closed period fell short
  ///
  /// In en, this message translates to:
  /// **'missed'**
  String get reportGoalStateMissed;

  /// Screen reader wording of a goal row's state glyph: nothing counted yet in the period
  ///
  /// In en, this message translates to:
  /// **'not started'**
  String get reportGoalStateNotStarted;

  /// Screen reader wording of a goal row's state glyph: a future period
  ///
  /// In en, this message translates to:
  /// **'planned'**
  String get reportGoalStatePlanned;

  /// Screen reader wording of a days-between goal's state glyph: fewer days than the limit
  ///
  /// In en, this message translates to:
  /// **'within the limit'**
  String get reportGoalStateWithin;

  /// Screen reader wording of a days-between goal's state glyph: close to the limit
  ///
  /// In en, this message translates to:
  /// **'due soon'**
  String get reportGoalStateDueSoon;

  /// Screen reader wording of a days-between goal's state glyph: more days than the limit
  ///
  /// In en, this message translates to:
  /// **'past the limit'**
  String get reportGoalStatePastLimit;

  /// Report band subtitle of a current period, after the event count: goals met or on track of all goals; keep it short, it must fit one line
  ///
  /// In en, this message translates to:
  /// **'{onPace} of {total, plural, one{1 goal} other{{total} goals}} on pace'**
  String reportGoalsOnPace(int onPace, int total);

  /// Report band subtitle of a past period, after the event count: goals met of all goals; keep it short, it must fit one line
  ///
  /// In en, this message translates to:
  /// **'{met} of {total, plural, one{1 goal} other{{total} goals}} met'**
  String reportGoalsMet(int met, int total);

  /// Screen reader wording of an insight's highest-severity glyph
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get reportInsightAttention;

  /// Screen reader wording of an insight's second-severity glyph
  ///
  /// In en, this message translates to:
  /// **'Worth a look'**
  String get reportInsightNotable;

  /// Screen reader wording of an insight's third-severity glyph
  ///
  /// In en, this message translates to:
  /// **'Worth knowing'**
  String get reportInsightObservation;

  /// Screen reader wording of an insight's lowest-severity glyph: a plain fact
  ///
  /// In en, this message translates to:
  /// **'For information'**
  String get reportInsightInfo;

  /// Report Insights card: the subject of the bills-ahead insight, across every bill category
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get reportInsightBills;

  /// Report Insights card: the subject of the trip-ahead insight
  ///
  /// In en, this message translates to:
  /// **'Next trip'**
  String get reportInsightNextTrip;

  /// Report Insights card, an at-least goal behind: progress (e.g. 1 of 3) then what is still needed (e.g. two more by Sunday), both already worded
  ///
  /// In en, this message translates to:
  /// **'{progress}, {more}'**
  String reportInsightBehind(String progress, String more);

  /// Report Insights card, an at-most or budget goal over: progress (e.g. 44 h of 40) in the goal's period (day, week, month or year), then by how much (e.g. 4 h over), both already worded
  ///
  /// In en, this message translates to:
  /// **'{progress} {period, select, day{today} week{this week} month{this month} year{this year} other{}}, {over}'**
  String reportInsightOver(String progress, String period, String over);

  /// Report Insights card, an at-least goal met early: progress (e.g. 3 of 3) then the done phrase (e.g. done for the week), both already worded
  ///
  /// In en, this message translates to:
  /// **'{progress}, {done}'**
  String reportInsightDone(String progress, String done);

  /// Report Insights card: a run of met goal periods broke at the last closed one, e.g. the 5-week streak ended; period is day, week, month or year
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{the 1-{period, select, day{day} week{week} month{month} year{year} other{period}} streak ended} other{the {count}-{period, select, day{day} week{week} month{month} year{year} other{period}} streak ended}}'**
  String reportInsightStreakEnded(int count, String period);

  /// Report Insights card, a leave allowance running low: days left of the year's allowance; left is already formatted
  ///
  /// In en, this message translates to:
  /// **'{total, plural, one{{left} of 1 day left} other{{left} of {total} days left}}'**
  String reportInsightAllowance(String left, int total);

  /// Report Insights card, after a leave allowance's days left: whole months left in the year
  ///
  /// In en, this message translates to:
  /// **'{months, plural, one{1 month to go} other{{months} months to go}}'**
  String reportInsightMonthsToGo(int months);

  /// Report Insights card, a leave allowance late in the year: days of it not taken yet
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{1 day unused} other{{days} days unused}}'**
  String reportInsightAllowanceUnused(int days);

  /// Report Insights card, after the unused leave days: days left until the year ends
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{1 day left in the year} other{{days} days left in the year}}'**
  String reportInsightDaysLeftInYear(int days);

  /// Report Insights card, a days-between goal or a tag past its limit: days since the last time, then the limit in days
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{1 day since the last} other{{days} days since the last}}, the limit is {limit}'**
  String reportInsightGapOverdue(int days, int limit);

  /// Report Insights card, a days-between goal last kept before the year the report looks back over; limit in days
  ///
  /// In en, this message translates to:
  /// **'over a year since the last, the limit is {limit}'**
  String reportInsightGapOverdueLong(int limit);

  /// Report Insights card, a days-between goal close to its limit: days left before it
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{due in 1 day} other{due in {days} days}}'**
  String reportInsightGapDue(int days);

  /// Report Insights card, an expiry ahead, under the event's title: the days until it
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{expires today} one{expires in 1 day} other{expires in {days} days}}'**
  String reportInsightExpires(int days);

  /// Report Insights card, an expiry passed, under the event's title: the days since it
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{expired today} one{expired 1 day ago} other{expired {days} days ago}}'**
  String reportInsightExpired(int days);

  /// Report Insights card, a bill or deadline day passed with no mark, under the event's title: the latest such day (e.g. Nov 1) and how many days are unmarked
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{not marked on {day}} other{{count} days not marked, the latest {day}}}'**
  String reportInsightUnmarked(String day, int count);

  /// Report Insights card, a recurring episode (e.g. a migraine): the weekday the usual gap between episodes points to
  ///
  /// In en, this message translates to:
  /// **'the usual gap puts the next around {day}'**
  String reportInsightEpisodeNext(String day);

  /// Report Insights card, a routine's attendance by weekday: the best weekday and its share attended, then the worst; the percents are whole numbers
  ///
  /// In en, this message translates to:
  /// **'{best} {bestPercent} %, {worst} {worstPercent} %'**
  String reportInsightWeekdays(
    String best,
    String bestPercent,
    String worst,
    String worstPercent,
  );

  /// Report Insights card, work: the most days in one week that ran late into the evening
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 late evening} other{{count} late evenings}} in one week'**
  String reportInsightLateEvenings(int count);

  /// Report Insights card, work: hours worked on Saturdays and Sundays, e.g. 5 h on the weekend
  ///
  /// In en, this message translates to:
  /// **'{hours} on the weekend'**
  String reportInsightWeekend(String hours);

  /// Report Insights card, sleep: the most short nights in one week; hours is the short-night line, e.g. 7 h
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 night} other{{count} nights}} under {hours} in one week'**
  String reportInsightShortNights(int count, String hours);

  /// Report Insights card, sleep: how far apart the usual bedtimes are, e.g. 1.5 h
  ///
  /// In en, this message translates to:
  /// **'bedtimes vary by {spread}'**
  String reportInsightBedtimeSpread(String spread);

  /// Report Insights card, meetings: meeting hours and their share of work and meeting hours; percent is a whole number
  ///
  /// In en, this message translates to:
  /// **'{hours}, {percent} % of your work hours'**
  String reportInsightMeetingShare(String hours, String percent);

  /// Report Insights card: cancelled days of the planned ones, e.g. 3 of 8 cancelled
  ///
  /// In en, this message translates to:
  /// **'{planned, plural, one{{cancelled} of 1 cancelled} other{{cancelled} of {planned} cancelled}}'**
  String reportInsightCancelled(int cancelled, int planned);

  /// Report Insights card, a workout category: the longest run of days without it in the period
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{a break of 1 day} other{a break of {days} days}}'**
  String reportInsightRestGap(int days);

  /// Report Insights card: the money of the bills due in the coming days; amount is already formatted
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{{amount} due in the next day} other{{amount} due in the next {days} days}}'**
  String reportInsightBillsAhead(String amount, int days);

  /// Report Insights card of a year: the twelve-month total of the recurring bills and how many there are; amount is already formatted
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{amount} a year across 1 bill} other{{amount} a year across {count} bills}}'**
  String reportInsightBillsYear(String amount, int count);

  /// Report Insights card, a #tag (a person, a place) not seen for much longer than its usual gap: days since the last time
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{1 day since the last, longer than usual} other{{days} days since the last, longer than usual}}'**
  String reportInsightTagGapLong(int days);

  /// Report Insights card, a #tag: the one seen most often in a people category, with the days it was seen
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{the most seen in {category}, on 1 day} other{the most seen in {category}, on {days} days}}'**
  String reportInsightTagTop(String category, int days);

  /// Report Insights card, appointments: the usual days between adding one and its day
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{usually booked the same day} =1{usually booked a day ahead} other{usually booked {days} days ahead}}'**
  String reportInsightLeadTime(int days);

  /// Report Insights card, deadlines: how many are still open after their day
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 open past its day} other{{count} open past their day}}'**
  String reportInsightOpenPast(int count);

  /// Report Insights card, anniversaries: how many come before the period's last day (e.g. Nov 30)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 ahead by {day}} other{{count} ahead by {day}}}'**
  String reportInsightAhead(int count, String day);

  /// Report Insights card, the next trip: its title and the days until it starts
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{{title} today} =1{{title} tomorrow} other{{title} in {days} days}}'**
  String reportInsightTrip(String title, int days);

  /// Report Insights card, a category's leading measure or a bill's amount rose against the compared period: the value this period, the change in whole percent and the compared period's name
  ///
  /// In en, this message translates to:
  /// **'{value}, up {percent} % on {period}'**
  String reportInsightUpOn(String value, String percent, String period);

  /// Report Insights card, a category's leading measure or a bill's amount fell against the compared period: the value this period, the change in whole percent and the compared period's name
  ///
  /// In en, this message translates to:
  /// **'{value}, down {percent} % on {period}'**
  String reportInsightDownOn(String value, String percent, String period);

  /// Report Due soon row: days past a days-between limit; one line, keep it under 20 characters with the number first where the language allows
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Overdue today} one{Overdue 1 day} other{Overdue {count} days}}'**
  String reportDueOverdue(int count);

  /// Report Due soon row: days left inside a days-between limit; one line, keep it under 20 characters
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Due today} one{Due in 1 day} other{Due in {count} days}}'**
  String reportDueIn(int count);

  /// Report Due soon row: days until an expiry; one line, keep it under 20 characters
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Expires today} one{Expires in 1 day} other{Expires in {count} days}}'**
  String reportDueExpires(int count);

  /// Report Due soon row: days since an expiry passed; one line, keep it under 20 characters
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Expired today} one{Expired 1 day ago} other{Expired {count} days ago}}'**
  String reportDueExpired(int count);

  /// Report Due soon row, after a bill's or deadline's day (e.g. Nov 1 · not marked): the day passed with no mark
  ///
  /// In en, this message translates to:
  /// **'not marked'**
  String get reportDueNotMarked;

  /// Report Due soon row: a days-between goal last kept before the year the report looks back over
  ///
  /// In en, this message translates to:
  /// **'Over a year ago'**
  String get reportDueLong;

  /// Report Categories header caption, a category led by Last seen: days since it last happened
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{today} =1{yesterday} other{{count} days ago}}'**
  String reportLastSeenAgo(int count);

  /// Report Categories header caption, a category led by Cancelled: cancelled days in the period
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 cancelled} other{{count} cancelled}}'**
  String reportCancelledCount(int count);

  /// Report Categories header caption, a category led by Lead time: the usual days between adding an event and its day
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{booked the same day} one{booked 1 day ahead} other{booked {count} days ahead}}'**
  String reportLeadTime(int count);

  /// Report Categories header caption led by Days until, and a Due soon row after a bill's day: days until the next occurrence
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{today} =1{tomorrow} other{in {count} days}}'**
  String reportDaysUntil(int count);

  /// Part of the caption under the report's tiles: Monday-to-Friday days of the period that are no public holiday
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 working day} other{{count} working days}}'**
  String reportWorkingDays(int count);

  /// Part of the caption under the report's tiles: public holidays in the period
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 public holiday} other{{count} public holidays}}'**
  String reportPublicHolidays(int count);

  /// Part of the caption under the report's tiles: how much of the Hours tile comes from days counted as a fixed duration (e.g. a leave day counted as 8 h), not from event times
  ///
  /// In en, this message translates to:
  /// **'Hours incl. {hours} counted as'**
  String reportCaptionCountedAs(String hours);

  /// Screen reader wording appended to the Hours tile: how much of it comes from days counted as a fixed duration; hours is spelled out, e.g. 6 hours
  ///
  /// In en, this message translates to:
  /// **'including {hours} counted as'**
  String reportCountedAsSpoken(String hours);

  /// Section label of the report's By tag card: the #tags typed in event descriptions over the period
  ///
  /// In en, this message translates to:
  /// **'By tag'**
  String get reportSectionTags;

  /// Section label of the report's When card: a weekday by hour heatmap of the timed events
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get reportSectionWhen;

  /// Section label of the report's Balance card: the hours per life area (health, work, people…)
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get reportSectionBalance;

  /// Report By tag row, the first fact: how often the tag was seen, the noun from its category's kind (social, trip, maintenance, workout, other). Keep each noun short (10 characters at most)
  ///
  /// In en, this message translates to:
  /// **'{kind, select, social{{count, plural, =1{1 evening} other{{count} evenings}}} trip{{count, plural, =1{1 trip} other{{count} trips}}} maintenance{{count, plural, =1{1 service} other{{count} services}}} workout{{count, plural, =1{1 session} other{{count} sessions}}} other{{count, plural, =1{once} other{{count} times}}}}'**
  String reportTagCount(String kind, int count);

  /// Report By tag row of a trip tag, the second fact: the days the tag was seen, e.g. 2 trips · 5 days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String reportTagDays(int count);

  /// Report By tag row, the second fact: the latest day the tag was seen; day is the row's day, e.g. last Fri 24, or spelled out for a screen reader
  ///
  /// In en, this message translates to:
  /// **'{when, select, today{today} yesterday{yesterday} other{last {day}}}'**
  String reportTagLastSeen(String when, String day);

  /// Screen reader label of a report By tag row: the tag's name without the # sign, then its facts, e.g. tag ana, 6 evenings, last Saturday 24 October
  ///
  /// In en, this message translates to:
  /// **'tag {name}, {facts}'**
  String reportTagSpoken(String name, String facts);

  /// Screen reader name of a report By tag row's tag, without the # sign, in its disclosures and Show as list, e.g. 2 more in tag ana
  ///
  /// In en, this message translates to:
  /// **'tag {name}'**
  String reportTagName(String name);

  /// Screen reader label of the report By tag card's disclosure that shows the remaining tags
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more tag} other{{count} more tags}}'**
  String reportTagsMoreSpoken(int count);

  /// Screen reader label of the report By tag card's disclosure that folds the tags back to the first four
  ///
  /// In en, this message translates to:
  /// **'Show fewer tags'**
  String get reportTagsLessSpoken;

  /// Caption under the report's When heatmap: the weekday and the hour with the most minutes, e.g. Busiest: Tuesday · 18:00–19:00
  ///
  /// In en, this message translates to:
  /// **'Busiest: {weekday} · {hours}'**
  String reportWhenBusiest(String weekday, String hours);

  /// Screen reader label of the report's When heatmap: the busiest weekday, the busiest hour from its start to its end, and the timed days it was drawn from
  ///
  /// In en, this message translates to:
  /// **'When. Busiest day {weekday}, busiest hour {from} to {to}, over {count, plural, =1{1 timed day} other{{count} timed days}}.'**
  String reportWhenSpoken(String weekday, String from, String to, int count);

  /// Screen reader label of a report Balance row: the life area, its hours spelled out and its share of all the areas' hours, e.g. Work, 38 hours, 67 percent of the hours
  ///
  /// In en, this message translates to:
  /// **'{area}, {hours}, {percent} of the hours'**
  String reportBalanceSpoken(String area, String hours, String percent);

  /// Report footer menu row: what the report's deltas and second column compare the period with
  ///
  /// In en, this message translates to:
  /// **'Compare with'**
  String get reportCompareWith;

  /// Report Compare with menu item and value: the period one step back
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get reportComparePrevious;

  /// Report Compare with menu item and value: the same period one year earlier
  ///
  /// In en, this message translates to:
  /// **'Same period last year'**
  String get reportCompareLastYear;

  /// Report Compare with menu item, disabled, shown when no overview view is saved
  ///
  /// In en, this message translates to:
  /// **'No saved views'**
  String get reportCompareNoViews;

  /// Part of the caption under the report's tiles when it compares with a saved view, e.g. To 30 October · beside Work / Life
  ///
  /// In en, this message translates to:
  /// **'beside {view}'**
  String reportCaptionBeside(String view);

  /// Legend item of the report's Over time chart for the tick at each column's count a year earlier
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get reportLegendLastYear;

  /// Screen reader wording appended to the report's Over time chart under Compare with last year: the events of the same period a year earlier
  ///
  /// In en, this message translates to:
  /// **'same period last year, {count, plural, =1{1 event} other{{count} events}}'**
  String reportTrendLastYearSpoken(int count);

  /// Report Period menu item: the whole previous calendar year
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get reportPeriodLastYear;

  /// Section label of the report's Records card on a whole year: the year's busiest month, longest streak and other peaks
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get reportSectionRecords;

  /// Section label of the report's Months card on a whole year: one strip of twelve months per category
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get reportSectionMonths;

  /// Calendar settings row, and the title of the page it opens: which cards the calendar report shows and in which order
  ///
  /// In en, this message translates to:
  /// **'Report cards'**
  String get calendarSettingsReportTitle;

  /// Subtitle of the Report cards row in Calendar settings
  ///
  /// In en, this message translates to:
  /// **'Which cards the report shows, and in which order'**
  String get calendarSettingsReportDescription;

  /// Section header over the Report cards page's one group: the report's cards, each with a handle and a switch
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get reportCardsSectionTitle;

  /// Report cards page action: puts the cards back in the report's own order with every card on
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get reportCardsReset;

  /// Snackbar after Reset to default on the Report cards page
  ///
  /// In en, this message translates to:
  /// **'Order and cards reset'**
  String get reportCardsResetDone;

  /// Report Records row name: the month with the most events in the year. Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Busiest month'**
  String get reportRecordBusiestMonth;

  /// Report Records row name: the week with the most events in the year. Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Busiest week'**
  String get reportRecordBusiestWeek;

  /// Report Records row name: the month with the most social events (friends, family, evenings out). Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Most social month'**
  String get reportRecordSocialMonth;

  /// Report Records row name: the month with the most money spent. Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Biggest spend'**
  String get reportRecordMoneyMonth;

  /// Report Records row name: the trip with the most days in the year. Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Longest trip'**
  String get reportRecordLongestTrip;

  /// Report Records row name: a routine's most occurrences kept in a row in the year. Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Longest streak'**
  String get reportRecordLongestStreak;

  /// Report Records row name: a category's most days between two of its events in the year. Keep it short (18 characters at most)
  ///
  /// In en, this message translates to:
  /// **'Longest gap'**
  String get reportRecordLongestGap;

  /// Caption of a report Records row: what holds the record (a month, a week, an event or a category) and its value, e.g. June · 31 events
  ///
  /// In en, this message translates to:
  /// **'{subject} · {value}'**
  String reportRecordCaption(String subject, String value);

  /// Screen reader label of a report Records row: the record's name, what holds it and its value, e.g. Busiest month: June, 31 events
  ///
  /// In en, this message translates to:
  /// **'{record}: {subject}, {value}'**
  String reportRecordSpoken(String record, String subject, String value);

  /// Caption of a report Months row: the category's first and last kept day in the year, e.g. Jan 2 – Dec 30
  ///
  /// In en, this message translates to:
  /// **'{first} – {last}'**
  String reportYearSpan(String first, String last);

  /// Caption subject of the year in review's busiest week when its first and last day share a month, the month named once, e.g. Jun 16 – 22
  ///
  /// In en, this message translates to:
  /// **'{month} {first} – {last}'**
  String reportDayRangeSameMonth(String month, String first, String last);

  /// Screen reader form of a report Months row's span: the category's first and last kept day, e.g. from 2 January to 30 December
  ///
  /// In en, this message translates to:
  /// **'from {first} to {last}'**
  String reportYearSpanSpoken(String first, String last);

  /// Screen reader form of a report Months row's span when the category was kept on one day only, e.g. on 2 January
  ///
  /// In en, this message translates to:
  /// **'on {day}'**
  String reportYearDaySpoken(String day);

  /// Screen reader label of a report Months row: the category, its span and its value in each of the twelve months, e.g. Gym, from 2 January to 30 December. By month: January 9, February 8
  ///
  /// In en, this message translates to:
  /// **'{category}, {span}. By month: {months}.'**
  String reportYearMonthsSpoken(String category, String span, String months);

  /// One month in a report Months row's screen reader list: the month's name and its value, e.g. January 9 or January 31 hours
  ///
  /// In en, this message translates to:
  /// **'{month} {value}'**
  String reportYearMonthValue(String month, String value);

  /// Report Goals card caption on a whole year, after the periods met: the most periods met in a row, e.g. 41 of 52 weeks met · longest streak 11. Keep it short
  ///
  /// In en, this message translates to:
  /// **'longest streak {count}'**
  String reportGoalLongestStreak(int count);

  /// Screen reader form of the Goals card's longest streak on a whole year, with the goal's period (day, week or month), e.g. longest streak 11 weeks
  ///
  /// In en, this message translates to:
  /// **'{period, select, day{longest streak {count, plural, =1{1 day} other{{count} days}}} week{longest streak {count, plural, =1{1 week} other{{count} weeks}}} month{longest streak {count, plural, =1{1 month} other{{count} months}}} other{longest streak {count}}}'**
  String reportGoalLongestStreakSpoken(String period, int count);

  /// Report Balance row caption under Compare with last year, after this period's hours: the same area's hours a year earlier, e.g. 1720 h · last year 1650 h
  ///
  /// In en, this message translates to:
  /// **'last year {hours}'**
  String reportBalanceLastYear(String hours);

  /// Screen reader label of a report Balance row under Compare with last year: the life area, its hours and the same area's hours a year earlier, both spelled out
  ///
  /// In en, this message translates to:
  /// **'{area}, {hours}, last year {lastHours}'**
  String reportBalanceLastYearSpoken(
    String area,
    String hours,
    String lastHours,
  );

  /// No description provided for @howToUseAntaDesc.
  ///
  /// In en, this message translates to:
  /// **'Calendar, notes, backup and settings'**
  String get howToUseAntaDesc;

  /// No description provided for @guideHubIntro.
  ///
  /// In en, this message translates to:
  /// **'Three short guides. Search here to look through all of them at once.'**
  String get guideHubIntro;

  /// No description provided for @guideHubSectionGuides.
  ///
  /// In en, this message translates to:
  /// **'Guides'**
  String get guideHubSectionGuides;

  /// No description provided for @guideBookCalendarCaption.
  ///
  /// In en, this message translates to:
  /// **'The screen, events, alerts, attendance, the overview, a practice calendar'**
  String get guideBookCalendarCaption;

  /// No description provided for @guideBookNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes and the editor'**
  String get guideBookNotesTitle;

  /// No description provided for @guideBookNotesCaption.
  ///
  /// In en, this message translates to:
  /// **'Folders, writing, markdown, lists, your own shortcuts, the money ledger, autocomplete, counters'**
  String get guideBookNotesCaption;

  /// No description provided for @guideBookAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup, sync and settings'**
  String get guideBookAppTitle;

  /// No description provided for @guideBookAppCaption.
  ///
  /// In en, this message translates to:
  /// **'The main menu, keeping a copy of your notes, syncing between phones, the settings'**
  String get guideBookAppCaption;

  /// No description provided for @notesGuideIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap a page. Each example shows what you type and what you get.'**
  String get notesGuideIntro;

  /// No description provided for @appGuideIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap a page. Nothing here changes a setting.'**
  String get appGuideIntro;

  /// No description provided for @guideExampleTyped.
  ///
  /// In en, this message translates to:
  /// **'You type'**
  String get guideExampleTyped;

  /// No description provided for @guideExampleShown.
  ///
  /// In en, this message translates to:
  /// **'You get'**
  String get guideExampleShown;

  /// No description provided for @notesGuidePageBasics.
  ///
  /// In en, this message translates to:
  /// **'Folders and notes'**
  String get notesGuidePageBasics;

  /// No description provided for @notesGuidePageBasicsCaption.
  ///
  /// In en, this message translates to:
  /// **'Making a note, finding it again, moving, labelling, deleting'**
  String get notesGuidePageBasicsCaption;

  /// No description provided for @notesGuideBasicsLead.
  ///
  /// In en, this message translates to:
  /// **'ANTA keeps notes in folders, like pages in binders. The first screen holds your folders: make one there, and your notes go inside it.'**
  String get notesGuideBasicsLead;

  /// No description provided for @notesGuideBasicsCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Making a note'**
  String get notesGuideBasicsCreateTitle;

  /// No description provided for @notesGuideBasicsCreateBody.
  ///
  /// In en, this message translates to:
  /// **'Open a folder and tap “{newNote}” at the bottom. The note opens at once and is kept from the first letter. A title can come later: tap the title at the top to set it.'**
  String notesGuideBasicsCreateBody(String newNote);

  /// No description provided for @notesGuideBasicsFoldersTitle.
  ///
  /// In en, this message translates to:
  /// **'Folders inside folders'**
  String get notesGuideBasicsFoldersTitle;

  /// No description provided for @notesGuideBasicsFoldersBody.
  ///
  /// In en, this message translates to:
  /// **'“{newFolder}” makes a folder where you are. Folders can hold folders, so a binder can have sections. Tap a folder to go in; the arrow at the top takes you back out.'**
  String notesGuideBasicsFoldersBody(String newFolder);

  /// No description provided for @notesGuideBasicsSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'There is no Save button'**
  String get notesGuideBasicsSavedTitle;

  /// No description provided for @notesGuideBasicsSavedBody.
  ///
  /// In en, this message translates to:
  /// **'A note is saved on its own a few seconds after you stop typing, and again when you leave it. The word at the top of a note says “{saveStatusSaved}” when it is done.'**
  String notesGuideBasicsSavedBody(String saveStatusSaved);

  /// No description provided for @notesGuideBasicsReopenTitle.
  ///
  /// In en, this message translates to:
  /// **'ANTA opens where you left it'**
  String get notesGuideBasicsReopenTitle;

  /// No description provided for @notesGuideBasicsReopenBody.
  ///
  /// In en, this message translates to:
  /// **'Close the app in the middle of a note and it comes back to that note, on the same line. Folders remember their place too.'**
  String get notesGuideBasicsReopenBody;

  /// No description provided for @notesGuideBasicsMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'A folder\'s ⋮ menu'**
  String get notesGuideBasicsMenuTitle;

  /// No description provided for @notesGuideBasicsMenuBody.
  ///
  /// In en, this message translates to:
  /// **'“{renameFolder}”, “{moveToFolder}”, “{sortBy}”, “{shareFolder}” and “{importNoteOrFolder}” are in the ⋮ at the top of a folder; the first screen\'s ⋮ has only “{sortBy}”, “{select}” and “{importNoteOrFolder}”. “{select}” starts picking several notes at once.'**
  String notesGuideBasicsMenuBody(
    String renameFolder,
    String moveToFolder,
    String sortBy,
    String shareFolder,
    String importNoteOrFolder,
    String select,
  );

  /// No description provided for @notesGuideBasicsHoldTitle.
  ///
  /// In en, this message translates to:
  /// **'Hold to select several'**
  String get notesGuideBasicsHoldTitle;

  /// No description provided for @notesGuideBasicsHoldBody.
  ///
  /// In en, this message translates to:
  /// **'Hold a note or a folder to select it, then tap others to add them. A bar appears with “{moveSelected}”, “{labelSelected}”, “{shareSelected}” and “{deleteSelected}” for the whole selection.'**
  String notesGuideBasicsHoldBody(
    String moveSelected,
    String labelSelected,
    String shareSelected,
    String deleteSelected,
  );

  /// No description provided for @notesGuideBasicsSortTitle.
  ///
  /// In en, this message translates to:
  /// **'Sorting and arranging'**
  String get notesGuideBasicsSortTitle;

  /// No description provided for @notesGuideBasicsSortBody.
  ///
  /// In en, this message translates to:
  /// **'“{sortNotes}” orders a folder by title, by date or by colour label. Choose “{sortByCustom}” to arrange notes and folders yourself, by dragging them.'**
  String notesGuideBasicsSortBody(String sortNotes, String sortByCustom);

  /// No description provided for @notesGuideBasicsLabelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Colour labels'**
  String get notesGuideBasicsLabelsTitle;

  /// No description provided for @notesGuideBasicsLabelsBody.
  ///
  /// In en, this message translates to:
  /// **'“{labelAction}” gives a note or a folder a colour, drawn as a stripe along its edge. Sorting by “{sortByLabel}” groups them by colour.'**
  String notesGuideBasicsLabelsBody(String labelAction, String sortByLabel);

  /// No description provided for @notesGuideBasicsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting'**
  String get notesGuideBasicsDeleteTitle;

  /// No description provided for @notesGuideBasicsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Deleting asks first, and then it is final: there is no bin to take a note back from. A deleted folder takes its notes with it. The way back is a backup — the “{guideBookAppTitle}” guide shows how to keep one.'**
  String notesGuideBasicsDeleteBody(String guideBookAppTitle);

  /// No description provided for @notesGuideBasicsSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Finding a note'**
  String get notesGuideBasicsSearchTitle;

  /// No description provided for @notesGuideBasicsSearchBody.
  ///
  /// In en, this message translates to:
  /// **'The magnifier at the top searches every folder: titles and the text inside notes. Tap a result to open the note.'**
  String get notesGuideBasicsSearchBody;

  /// No description provided for @notesGuideBasicsAllTitle.
  ///
  /// In en, this message translates to:
  /// **'All notes, recent notes'**
  String get notesGuideBasicsAllTitle;

  /// No description provided for @notesGuideBasicsAllBody.
  ///
  /// In en, this message translates to:
  /// **'The first folder has two rows that are not folders: “{allNotes}” lists every note in one place and “{recent}” the ones you touched last.'**
  String notesGuideBasicsAllBody(String allNotes, String recent);

  /// No description provided for @notesGuidePageEditor.
  ///
  /// In en, this message translates to:
  /// **'Writing a note'**
  String get notesGuidePageEditor;

  /// No description provided for @notesGuidePageEditorCaption.
  ///
  /// In en, this message translates to:
  /// **'The screen, the bar above the keyboard, the ⋮ menu, undo, find'**
  String get notesGuidePageEditorCaption;

  /// No description provided for @notesGuideEditorLead.
  ///
  /// In en, this message translates to:
  /// **'A note is a page of text. A few symbols shape it, and the bar above the keyboard types them for you.'**
  String get notesGuideEditorLead;

  /// No description provided for @notesGuideEditorLiveTitle.
  ///
  /// In en, this message translates to:
  /// **'You see the result as you type'**
  String get notesGuideEditorLiveTitle;

  /// No description provided for @notesGuideEditorLiveBody.
  ///
  /// In en, this message translates to:
  /// **'Type **bold** and the stars disappear, leaving bold text. The symbols show again only on the line you are on, so you can change them; move away and they hide.'**
  String get notesGuideEditorLiveBody;

  /// No description provided for @notesGuideEditorBarTitle.
  ///
  /// In en, this message translates to:
  /// **'The bar above the keyboard'**
  String get notesGuideEditorBarTitle;

  /// No description provided for @notesGuideEditorBarBody.
  ///
  /// In en, this message translates to:
  /// **'Each button writes a shape for you — “{headers}”, “{bulletList}”, “{checkbox}” — so you never have to remember a symbol. Select text first and the shape wraps it. The bar scrolls sideways; there is more to the right.'**
  String notesGuideEditorBarBody(
    String headers,
    String bulletList,
    String checkbox,
  );

  /// No description provided for @notesGuideEditorUndoTitle.
  ///
  /// In en, this message translates to:
  /// **'Undo and redo'**
  String get notesGuideEditorUndoTitle;

  /// No description provided for @notesGuideEditorUndoBody.
  ///
  /// In en, this message translates to:
  /// **'The two arrows on the bar take back or redo your last changes, as many steps as you need.'**
  String get notesGuideEditorUndoBody;

  /// No description provided for @notesGuideEditorTitleTitle.
  ///
  /// In en, this message translates to:
  /// **'The title'**
  String get notesGuideEditorTitleTitle;

  /// No description provided for @notesGuideEditorTitleBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the title at the top to change it. Two notes in one folder cannot share a title; ANTA tells you when one would.'**
  String get notesGuideEditorTitleBody;

  /// No description provided for @notesGuideEditorMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'The ⋮ menu'**
  String get notesGuideEditorMenuTitle;

  /// No description provided for @notesGuideEditorMenuBody.
  ///
  /// In en, this message translates to:
  /// **'“{shareNote}” hands the text to another app, “{moveToFolder}” files it elsewhere, “{labelAction}” colours it, “{openFolder}” shows where it lives and “{deleteNote}” removes it — after asking.'**
  String notesGuideEditorMenuBody(
    String shareNote,
    String moveToFolder,
    String labelAction,
    String openFolder,
    String deleteNote,
  );

  /// No description provided for @notesGuideEditorFindTitle.
  ///
  /// In en, this message translates to:
  /// **'Find in this note'**
  String get notesGuideEditorFindTitle;

  /// No description provided for @notesGuideEditorFindBody.
  ///
  /// In en, this message translates to:
  /// **'The magnifier at the top searches this note only. The arrows step through the hits, tapping the counter lists them all, and the bar\'s options menu adds a field that replaces.'**
  String get notesGuideEditorFindBody;

  /// No description provided for @notesGuideEditorFontTitle.
  ///
  /// In en, this message translates to:
  /// **'Bigger or smaller text'**
  String get notesGuideEditorFontTitle;

  /// No description provided for @notesGuideEditorFontBody.
  ///
  /// In en, this message translates to:
  /// **'“{decreaseFontSize}” and “{increaseFontSize}” on the bar change the text size of every note. Your phone\'s own text size applies on top.'**
  String notesGuideEditorFontBody(
    String decreaseFontSize,
    String increaseFontSize,
  );

  /// No description provided for @notesGuideEditorTapTitle.
  ///
  /// In en, this message translates to:
  /// **'Things you can tap'**
  String get notesGuideEditorTapTitle;

  /// No description provided for @notesGuideEditorTapBody.
  ///
  /// In en, this message translates to:
  /// **'Tap a checkbox to tick it, a #tag to find every note that has it, a [[note link]] to open that note, a \$\$ total to see what went into it, a web link to open it.'**
  String get notesGuideEditorTapBody;

  /// No description provided for @notesGuidePageMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown basics'**
  String get notesGuidePageMarkdown;

  /// No description provided for @notesGuidePageMarkdownCaption.
  ///
  /// In en, this message translates to:
  /// **'Headings, bold, lists, checkboxes, quotes, links, tables'**
  String get notesGuidePageMarkdownCaption;

  /// No description provided for @notesGuideMarkdownLead.
  ///
  /// In en, this message translates to:
  /// **'Markdown is a handful of symbols that shape plain text. Type them, or let the bar do it.'**
  String get notesGuideMarkdownLead;

  /// No description provided for @notesGuideExHeadingSource.
  ///
  /// In en, this message translates to:
  /// **'# Leg day\n## Warm-up\nFive minutes on the bike'**
  String get notesGuideExHeadingSource;

  /// No description provided for @notesGuideExHeadingCaption.
  ///
  /// In en, this message translates to:
  /// **'A # and a space start a heading. Two make a smaller one.'**
  String get notesGuideExHeadingCaption;

  /// No description provided for @notesGuideExEmphasisSource.
  ///
  /// In en, this message translates to:
  /// **'**Heavy** day, *felt good*, ~~skipped~~ the rows, ==new record=='**
  String get notesGuideExEmphasisSource;

  /// No description provided for @notesGuideExEmphasisCaption.
  ///
  /// In en, this message translates to:
  /// **'Two stars make bold, one star italic, two tildes cross out, two equals signs highlight.'**
  String get notesGuideExEmphasisCaption;

  /// No description provided for @notesGuideExListSource.
  ///
  /// In en, this message translates to:
  /// **'- Squat\n- Bench\n- Row'**
  String get notesGuideExListSource;

  /// No description provided for @notesGuideExListCaption.
  ///
  /// In en, this message translates to:
  /// **'A dash and a space make a bullet. Enter at the end of an item starts the next; Enter on an empty item ends the list.'**
  String get notesGuideExListCaption;

  /// No description provided for @notesGuideExNumberedSource.
  ///
  /// In en, this message translates to:
  /// **'1. Warm up\n2. Work sets\n3. Stretch'**
  String get notesGuideExNumberedSource;

  /// No description provided for @notesGuideExNumberedCaption.
  ///
  /// In en, this message translates to:
  /// **'A number and a dot make a numbered list. Enter continues the count for you.'**
  String get notesGuideExNumberedCaption;

  /// No description provided for @notesGuideExTaskSource.
  ///
  /// In en, this message translates to:
  /// **'- [ ] Water\n- [x] Protein'**
  String get notesGuideExTaskSource;

  /// No description provided for @notesGuideExTaskCaption.
  ///
  /// In en, this message translates to:
  /// **'A dash, a space and [ ] make a checkbox. Tap it to tick it; the bar\'s “{checkbox}” button starts one.'**
  String notesGuideExTaskCaption(String checkbox);

  /// No description provided for @notesGuideExQuoteSource.
  ///
  /// In en, this message translates to:
  /// **'> Form before weight'**
  String get notesGuideExQuoteSource;

  /// No description provided for @notesGuideExQuoteCaption.
  ///
  /// In en, this message translates to:
  /// **'A > sets a line apart as a quote, with a bar at its left.'**
  String get notesGuideExQuoteCaption;

  /// No description provided for @notesGuideExLinkSource.
  ///
  /// In en, this message translates to:
  /// **'[Program](https://example.com)'**
  String get notesGuideExLinkSource;

  /// No description provided for @notesGuideExLinkCaption.
  ///
  /// In en, this message translates to:
  /// **'Text in square brackets, the address in round ones. Tap the text to open the address.'**
  String get notesGuideExLinkCaption;

  /// No description provided for @notesGuideMarkdownTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Tables, lightly'**
  String get notesGuideMarkdownTableTitle;

  /// No description provided for @notesGuideMarkdownTableBody.
  ///
  /// In en, this message translates to:
  /// **'Cells between vertical bars make a table row. ANTA keeps such a row in a fixed-width font so the columns line up; the bar\'s “{shortcutTable}” button writes an empty one.'**
  String notesGuideMarkdownTableBody(String shortcutTable);

  /// No description provided for @notesGuidePageLists.
  ///
  /// In en, this message translates to:
  /// **'Lists and nesting'**
  String get notesGuidePageLists;

  /// No description provided for @notesGuidePageListsCaption.
  ///
  /// In en, this message translates to:
  /// **'Continuing a list, nesting items, pulling them back, checkboxes'**
  String get notesGuidePageListsCaption;

  /// No description provided for @notesGuideListsLead.
  ///
  /// In en, this message translates to:
  /// **'Most notes are lists: exercises, sets, groceries. ANTA keeps them tidy while you type.'**
  String get notesGuideListsLead;

  /// No description provided for @notesGuideExNestedSource.
  ///
  /// In en, this message translates to:
  /// **'- Legs\n  - Squat 5×5\n  - Lunges\n- Back\n  - Deadlift'**
  String get notesGuideExNestedSource;

  /// No description provided for @notesGuideExNestedCaption.
  ///
  /// In en, this message translates to:
  /// **'An item pushed in under another is nested. It gets a hollow bullet; a third level gets a square.'**
  String get notesGuideExNestedCaption;

  /// No description provided for @notesGuideListsEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter continues the list'**
  String get notesGuideListsEnterTitle;

  /// No description provided for @notesGuideListsEnterBody.
  ///
  /// In en, this message translates to:
  /// **'Enter at the end of an item starts the next at the same depth — a checkbox item starts another empty box, a numbered item the next number. Enter on an empty item moves it out one level; on an outermost item it ends the list and leaves a plain line.'**
  String get notesGuideListsEnterBody;

  /// No description provided for @notesGuideListsNestTitle.
  ///
  /// In en, this message translates to:
  /// **'Three ways to nest'**
  String get notesGuideListsNestTitle;

  /// No description provided for @notesGuideListsNestBody.
  ///
  /// In en, this message translates to:
  /// **'On an empty item, press Space once to push it under the item above. Or swipe the line you are on to the right. Or tap the bar\'s indent arrow. Swipe left, tap the outdent arrow, or press Enter on an empty item to pull it back out.'**
  String get notesGuideListsNestBody;

  /// No description provided for @notesGuideListsCapTitle.
  ///
  /// In en, this message translates to:
  /// **'One step at a time'**
  String get notesGuideListsCapTitle;

  /// No description provided for @notesGuideListsCapBody.
  ///
  /// In en, this message translates to:
  /// **'An item can sit one level deeper than the item above it, never more, so a list cannot wander off the screen.'**
  String get notesGuideListsCapBody;

  /// No description provided for @notesGuideListsTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticking off'**
  String get notesGuideListsTaskTitle;

  /// No description provided for @notesGuideListsTaskBody.
  ///
  /// In en, this message translates to:
  /// **'Tap a checkbox to tick it and tap it again to clear it. The keyboard stays where it is, so a list of sets can be ticked off mid-workout.'**
  String get notesGuideListsTaskBody;

  /// No description provided for @notesGuidePageOwn.
  ///
  /// In en, this message translates to:
  /// **'ANTA\'s own markdown'**
  String get notesGuidePageOwn;

  /// No description provided for @notesGuidePageOwnCaption.
  ///
  /// In en, this message translates to:
  /// **'Tags, callouts, colours, placeholders, links between notes, today\'s date'**
  String get notesGuidePageOwnCaption;

  /// No description provided for @notesGuideOwnLead.
  ///
  /// In en, this message translates to:
  /// **'A few shapes are ANTA\'s own. Each has a button on the bar too.'**
  String get notesGuideOwnLead;

  /// No description provided for @notesGuideExTagSource.
  ///
  /// In en, this message translates to:
  /// **'Deadlift 140 kg #pr #legday'**
  String get notesGuideExTagSource;

  /// No description provided for @notesGuideExTagCaption.
  ///
  /// In en, this message translates to:
  /// **'A word after # is a tag. Tap it to find every note that carries it.'**
  String get notesGuideExTagCaption;

  /// No description provided for @notesGuideExCalloutSource.
  ///
  /// In en, this message translates to:
  /// **'> [!TIP]\n> Warm up before the heavy sets'**
  String get notesGuideExCalloutSource;

  /// No description provided for @notesGuideExCalloutCaption.
  ///
  /// In en, this message translates to:
  /// **'A quote that starts with [!TIP] becomes a coloured box with an icon. NOTE, WARNING, IMPORTANT, SUCCESS and QUESTION work the same way in place of TIP.'**
  String get notesGuideExCalloutCaption;

  /// No description provided for @notesGuideExColourSource.
  ///
  /// In en, this message translates to:
  /// **'{open}red:Max effort{close} and ==green:done=='**
  String notesGuideExColourSource(String open, String close);

  /// No description provided for @notesGuideExColourCaption.
  ///
  /// In en, this message translates to:
  /// **'A colour name before the text colours it; inside two equals signs it colours the highlight. The names are red, orange, yellow, green, teal, blue, purple, pink and gray — or your own, from “{markdownColorsTitle}”.'**
  String notesGuideExColourCaption(String markdownColorsTitle);

  /// No description provided for @notesGuideExGhostSource.
  ///
  /// In en, this message translates to:
  /// **'Squat {open}{open}weight{close}{close} kg × {open}{open}reps{close}{close}'**
  String notesGuideExGhostSource(String open, String close);

  /// No description provided for @notesGuideExGhostCaption.
  ///
  /// In en, this message translates to:
  /// **'Text in double braces is a placeholder, shown dimmed. Tap it and type to fill it in — a template for a workout you repeat. The bar\'s “{shortcutGhostText}” button makes one.'**
  String notesGuideExGhostCaption(String shortcutGhostText);

  /// No description provided for @notesGuideExWikiSource.
  ///
  /// In en, this message translates to:
  /// **'Same warm-up as [[Leg day]]'**
  String get notesGuideExWikiSource;

  /// No description provided for @notesGuideExWikiCaption.
  ///
  /// In en, this message translates to:
  /// **'A note\'s title in double brackets links to that note. Tap it to open the note; if no note has that title, ANTA says so.'**
  String get notesGuideExWikiCaption;

  /// No description provided for @notesGuideOwnDateTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s date'**
  String get notesGuideOwnDateTitle;

  /// No description provided for @notesGuideOwnDateBody.
  ///
  /// In en, this message translates to:
  /// **'The bar\'s “{currentDate}” button types today\'s date, so a log line starts itself.'**
  String notesGuideOwnDateBody(String currentDate);

  /// No description provided for @notesGuidePageMoney.
  ///
  /// In en, this message translates to:
  /// **'The money ledger'**
  String get notesGuidePageMoney;

  /// No description provided for @notesGuidePageMoneyCaption.
  ///
  /// In en, this message translates to:
  /// **'Lines that start with \$ add up'**
  String get notesGuidePageMoneyCaption;

  /// No description provided for @notesGuideMoneyLead.
  ///
  /// In en, this message translates to:
  /// **'Any note can keep a running total. Switch on “{moneyLedgerEnabledLabel}” in “{settingsRowEditor}” › “{moneySection}” first; then lines that start with \$ are the ledger and everything else stays ordinary text.'**
  String notesGuideMoneyLead(
    String moneyLedgerEnabledLabel,
    String settingsRowEditor,
    String moneySection,
  );

  /// No description provided for @notesGuideExMoneyBasicSource.
  ///
  /// In en, this message translates to:
  /// **'\$= 500 budget\n\$- 40 gym\n\$+ 25 refund\n\$\$ left'**
  String get notesGuideExMoneyBasicSource;

  /// No description provided for @notesGuideExMoneyBasicCaption.
  ///
  /// In en, this message translates to:
  /// **'\$= sets the starting amount, \$- spends, \$+ adds — each shows the balance after it in grey. \$\$ shows the total so far as a coloured chip.'**
  String get notesGuideExMoneyBasicCaption;

  /// No description provided for @notesGuideExMoneyMonthsSource.
  ///
  /// In en, this message translates to:
  /// **'## March\n\$= 500\n\$- 120 shoes\n\$? March'**
  String get notesGuideExMoneyMonthsSource;

  /// No description provided for @notesGuideExMoneyMonthsCaption.
  ///
  /// In en, this message translates to:
  /// **'\$? shows how much changed since the last \$=. One \$= under each month\'s heading makes a monthly ledger.'**
  String get notesGuideExMoneyMonthsCaption;

  /// No description provided for @notesGuideExMoneyTargetSource.
  ///
  /// In en, this message translates to:
  /// **'\$= 500\n\$! 300 groceries\n\$- 120 groceries\n\$!'**
  String get notesGuideExMoneyTargetSource;

  /// No description provided for @notesGuideExMoneyTargetCaption.
  ///
  /// In en, this message translates to:
  /// **'\$! with an amount sets a target. A \$! on its own shows what is left of it after the spending since then — green while under, red when over. Neither changes the balance.'**
  String get notesGuideExMoneyTargetCaption;

  /// No description provided for @notesGuideMoneyTapTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap a total'**
  String get notesGuideMoneyTapTitle;

  /// No description provided for @notesGuideMoneyTapBody.
  ///
  /// In en, this message translates to:
  /// **'Tap a \$\$ or \$? value to see every line that went into it.'**
  String get notesGuideMoneyTapBody;

  /// No description provided for @notesGuideMoneyMoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Multiply and divide'**
  String get notesGuideMoneyMoreTitle;

  /// No description provided for @notesGuideMoneyMoreBody.
  ///
  /// In en, this message translates to:
  /// **'\$* 1.19 multiplies the balance, for a tax; \$/ 2 divides it, for a bill split in two.'**
  String get notesGuideMoneyMoreBody;

  /// No description provided for @notesGuideMoneySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Currency and start balance'**
  String get notesGuideMoneySettingsTitle;

  /// No description provided for @notesGuideMoneySettingsBody.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowEditor}” › “{moneySection}” also sets the symbol, where it goes and a start balance every note begins from; a single note can have its own currency. If \$ lines show as plain text, “{moneyLedgerEnabledLabel}” is still off there.'**
  String notesGuideMoneySettingsBody(
    String settingsRowEditor,
    String moneySection,
    String moneyLedgerEnabledLabel,
  );

  /// No description provided for @notesGuideMoneyCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'On the calendar'**
  String get notesGuideMoneyCalendarTitle;

  /// No description provided for @notesGuideMoneyCalendarBody.
  ///
  /// In en, this message translates to:
  /// **'An event\'s linked note shows its money on the calendar: a bar under the day and the month\'s total in the header.'**
  String get notesGuideMoneyCalendarBody;

  /// No description provided for @notesGuideMoneyButtonsTitle.
  ///
  /// In en, this message translates to:
  /// **'On the bar'**
  String get notesGuideMoneyButtonsTitle;

  /// No description provided for @notesGuideMoneyButtonsBody.
  ///
  /// In en, this message translates to:
  /// **'Each ledger line has a button: “{shortcutMoneyAdd}”, “{shortcutMoneySubtract}”, “{shortcutMoneyStart}”, “{shortcutMoneyTotal}”, “{shortcutMoneyChange}”, “{shortcutMoneyTarget}”.'**
  String notesGuideMoneyButtonsBody(
    String shortcutMoneyAdd,
    String shortcutMoneySubtract,
    String shortcutMoneyStart,
    String shortcutMoneyTotal,
    String shortcutMoneyChange,
    String shortcutMoneyTarget,
  );

  /// No description provided for @notesGuidePageBar.
  ///
  /// In en, this message translates to:
  /// **'The bar'**
  String get notesGuidePageBar;

  /// No description provided for @notesGuidePageBarCaption.
  ///
  /// In en, this message translates to:
  /// **'Rearranging buttons, your own shortcuts, several bars'**
  String get notesGuidePageBarCaption;

  /// No description provided for @notesGuideBarLead.
  ///
  /// In en, this message translates to:
  /// **'The bar above the keyboard is yours to arrange. Everything about it lives in “{settingsRowEditor}”.'**
  String notesGuideBarLead(String settingsRowEditor);

  /// No description provided for @notesGuideBarShortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get notesGuideBarShortcutsTitle;

  /// Read row of the bar page; quotes the shortcut list's own header. A built-in shortcut can be hidden and moved, never edited
  ///
  /// In en, this message translates to:
  /// **'Each button is a shortcut: text it writes, or wraps around what you selected. Under “{shortcuts}”, drag them into a new order and hide the ones you never use.'**
  String notesGuideBarShortcutsBody(String shortcuts);

  /// No description provided for @notesGuideBarOwnTitle.
  ///
  /// In en, this message translates to:
  /// **'Your own shortcut'**
  String get notesGuideBarOwnTitle;

  /// Read row of the bar page; quotes the shortcut list's header and the title of the guide page about custom shortcuts
  ///
  /// In en, this message translates to:
  /// **'Tap + on the “{shortcuts}” page to make one: a line you write often — a set format, the heading you start every day with — becomes a button. “{page}” in this guide walks through it.'**
  String notesGuideBarOwnBody(String shortcuts, String page);

  /// No description provided for @notesGuideBarUtilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Utility buttons'**
  String get notesGuideBarUtilityTitle;

  /// No description provided for @notesGuideBarUtilityBody.
  ///
  /// In en, this message translates to:
  /// **'Undo, redo, indent, paste, text size, share, counters, jump to the top or the bottom: “{utilityButtons}” chooses which of them show, and in what order.'**
  String notesGuideBarUtilityBody(String utilityButtons);

  /// No description provided for @notesGuideBarReorderTitle.
  ///
  /// In en, this message translates to:
  /// **'Rearrange from the note'**
  String get notesGuideBarReorderTitle;

  /// No description provided for @notesGuideBarReorderBody.
  ///
  /// In en, this message translates to:
  /// **'The bar\'s “{reorderShortcuts}” button turns the buttons into chips you can drag, right there in the note.'**
  String notesGuideBarReorderBody(String reorderShortcuts);

  /// No description provided for @notesGuideBarProfilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Several bars'**
  String get notesGuideBarProfilesTitle;

  /// No description provided for @notesGuideBarProfilesBody.
  ///
  /// In en, this message translates to:
  /// **'“{manageBarProfiles}” keeps more than one bar — one for workouts, one for money. With two or more, the bar\'s “{switchBar}” button changes the bar for the note you are in, and “{perNoteBarAssignment}” lists those choices.'**
  String notesGuideBarProfilesBody(
    String manageBarProfiles,
    String switchBar,
    String perNoteBarAssignment,
  );

  /// No description provided for @notesGuideBarLayoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Two strips or one'**
  String get notesGuideBarLayoutTitle;

  /// No description provided for @notesGuideBarLayoutBody.
  ///
  /// In en, this message translates to:
  /// **'“{splitToolbar}” keeps the utility buttons in a strip of their own at the right, scrolling apart from your shortcuts; “{pinUndoRedo}” keeps undo and redo in view while the rest of the bar scrolls.'**
  String notesGuideBarLayoutBody(String splitToolbar, String pinUndoRedo);

  /// No description provided for @notesGuidePageAutocomplete.
  ///
  /// In en, this message translates to:
  /// **'Autocomplete'**
  String get notesGuidePageAutocomplete;

  /// No description provided for @notesGuidePageAutocompleteCaption.
  ///
  /// In en, this message translates to:
  /// **'Your own word lists, offered while you type'**
  String get notesGuidePageAutocompleteCaption;

  /// No description provided for @notesGuideAutocompleteLead.
  ///
  /// In en, this message translates to:
  /// **'Give ANTA your lists — exercises, meals, clients — and it offers them as you type, so a long name is one tap.'**
  String get notesGuideAutocompleteLead;

  /// No description provided for @notesGuideAutoListsTitle.
  ///
  /// In en, this message translates to:
  /// **'Make a list'**
  String get notesGuideAutoListsTitle;

  /// No description provided for @notesGuideAutoListsBody.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowEditor}” › “{vocabularySection}” › “{manageVocabularies}”: one entry per line. A line starting with ;; is a heading inside the list and is never offered.'**
  String notesGuideAutoListsBody(
    String settingsRowEditor,
    String vocabularySection,
    String manageVocabularies,
  );

  /// No description provided for @notesGuideAutoTriggerTitle.
  ///
  /// In en, this message translates to:
  /// **'Type @ and a few letters'**
  String get notesGuideAutoTriggerTitle;

  /// No description provided for @notesGuideAutoTriggerBody.
  ///
  /// In en, this message translates to:
  /// **'After a space, type the trigger (“{vocabularyTriggerLabel}”, @ unless you change it) and the start of a word: @ben offers Bench press. Tap the suggestion and it is typed for you, as plain text.'**
  String notesGuideAutoTriggerBody(String vocabularyTriggerLabel);

  /// No description provided for @notesGuideAutoScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'One list only'**
  String get notesGuideAutoScopeTitle;

  /// No description provided for @notesGuideAutoScopeBody.
  ///
  /// In en, this message translates to:
  /// **'Name the list before a colon — @exercises:ben — and only that list is searched. Two names with a comma between them search both.'**
  String get notesGuideAutoScopeBody;

  /// No description provided for @notesGuideAutoGhostTitle.
  ///
  /// In en, this message translates to:
  /// **'Placeholders know your lists'**
  String get notesGuideAutoGhostTitle;

  /// No description provided for @notesGuideAutoGhostBody.
  ///
  /// In en, this message translates to:
  /// **'Tap a placeholder whose name matches one of your lists — {open}{open}exercise{close}{close} for a list called Exercises — and that list is offered. A template fills itself in two taps.'**
  String notesGuideAutoGhostBody(String open, String close);

  /// No description provided for @notesGuideAutoIgnoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Ignoring it costs nothing'**
  String get notesGuideAutoIgnoreTitle;

  /// No description provided for @notesGuideAutoIgnoreBody.
  ///
  /// In en, this message translates to:
  /// **'Keep typing and the suggestions close; what you typed stays exactly as it is. “{vocabularySuggestionsLabel}” turns the feature off altogether.'**
  String notesGuideAutoIgnoreBody(String vocabularySuggestionsLabel);

  /// No description provided for @notesGuidePageCounters.
  ///
  /// In en, this message translates to:
  /// **'Counters'**
  String get notesGuidePageCounters;

  /// No description provided for @notesGuidePageCountersCaption.
  ///
  /// In en, this message translates to:
  /// **'Numbers you tap up: sets, glasses of water, days in a row'**
  String get notesGuidePageCountersCaption;

  /// No description provided for @notesGuideCountersLead.
  ///
  /// In en, this message translates to:
  /// **'A counter is a number with its own + button. Keep one across the app, or one per note.'**
  String get notesGuideCountersLead;

  /// No description provided for @notesGuideCountersMakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Make one'**
  String get notesGuideCountersMakeTitle;

  /// No description provided for @notesGuideCountersMakeBody.
  ///
  /// In en, this message translates to:
  /// **'“{counterSettings}” in the main menu lists your counters. “{addCounter}” makes a new one: give it a name, a start value and a step.'**
  String notesGuideCountersMakeBody(String counterSettings, String addCounter);

  /// No description provided for @notesGuideCountersNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'From inside a note'**
  String get notesGuideCountersNoteTitle;

  /// No description provided for @notesGuideCountersNoteBody.
  ///
  /// In en, this message translates to:
  /// **'The bar\'s “{counterInsertTooltip}” button lists your counters. Pick one: it goes up by one step and the new number is typed where you are.'**
  String notesGuideCountersNoteBody(String counterInsertTooltip);

  /// No description provided for @notesGuideCountersScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Across the app, or per note'**
  String get notesGuideCountersScopeTitle;

  /// No description provided for @notesGuideCountersScopeBody.
  ///
  /// In en, this message translates to:
  /// **'“{counterScope}” decides: “{counterScopeGlobalDesc}”, or “{counterScopePerNoteDesc}” — a tally that belongs to that note alone.'**
  String notesGuideCountersScopeBody(
    String counterScope,
    String counterScopeGlobalDesc,
    String counterScopePerNoteDesc,
  );

  /// No description provided for @notesGuideCountersPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Pinning'**
  String get notesGuideCountersPinTitle;

  /// No description provided for @notesGuideCountersPinBody.
  ///
  /// In en, this message translates to:
  /// **'“{pinCounter}” keeps a counter at the top of the list, so the ones you use every day come first.'**
  String notesGuideCountersPinBody(String pinCounter);

  /// No description provided for @notesGuideCountersShortcutTitle.
  ///
  /// In en, this message translates to:
  /// **'A button that counts'**
  String get notesGuideCountersShortcutTitle;

  /// No description provided for @notesGuideCountersShortcutBody.
  ///
  /// In en, this message translates to:
  /// **'In “{shortcuts}”, a shortcut can be bound to a counter (“{counterBindingsTitle}”): each tap can count it up and type its number — one button per set.'**
  String notesGuideCountersShortcutBody(
    String shortcuts,
    String counterBindingsTitle,
  );

  /// No description provided for @notesGuidePageSettings.
  ///
  /// In en, this message translates to:
  /// **'Where the settings are'**
  String get notesGuidePageSettings;

  /// No description provided for @notesGuidePageSettingsCaption.
  ///
  /// In en, this message translates to:
  /// **'Which page holds what'**
  String get notesGuidePageSettingsCaption;

  /// No description provided for @notesGuideSettingsLead.
  ///
  /// In en, this message translates to:
  /// **'“{settingsHubTitle}” in the main menu lists every settings page with a line on what it holds; its search finds the page that holds a section by the section\'s name.'**
  String notesGuideSettingsLead(String settingsHubTitle);

  /// No description provided for @notesGuideSettingsGeneralTitle.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowGeneral}”'**
  String notesGuideSettingsGeneralTitle(String settingsRowGeneral);

  /// No description provided for @notesGuideSettingsGeneralBody.
  ///
  /// In en, this message translates to:
  /// **'{settingsRowGeneralDesc}: what opens at launch, how a folder shows its notes, the editor\'s line wrapping and line numbers.'**
  String notesGuideSettingsGeneralBody(String settingsRowGeneralDesc);

  /// No description provided for @notesGuideSettingsEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowEditor}”'**
  String notesGuideSettingsEditorTitle(String settingsRowEditor);

  /// No description provided for @notesGuideSettingsEditorBody.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts and bars, utility buttons, text colours, the money ledger, autocomplete — each a section you can fold away.'**
  String get notesGuideSettingsEditorBody;

  /// No description provided for @notesGuideSettingsCountersTitle.
  ///
  /// In en, this message translates to:
  /// **'“{counterSettings}”'**
  String notesGuideSettingsCountersTitle(String counterSettings);

  /// No description provided for @notesGuideSettingsCountersBody.
  ///
  /// In en, this message translates to:
  /// **'Your counters, their pins, and which of them vary per note.'**
  String get notesGuideSettingsCountersBody;

  /// No description provided for @notesGuideSettingsLookTitle.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowTheme}” and “{languageSettings}”'**
  String notesGuideSettingsLookTitle(
    String settingsRowTheme,
    String languageSettings,
  );

  /// No description provided for @notesGuideSettingsLookBody.
  ///
  /// In en, this message translates to:
  /// **'{themeSettingsDesc}; English, German or Romanian. Text size follows your phone\'s setting.'**
  String notesGuideSettingsLookBody(String themeSettingsDesc);

  /// No description provided for @notesGuideSettingsPerNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'What a single note can have'**
  String get notesGuideSettingsPerNoteTitle;

  /// No description provided for @notesGuideSettingsPerNoteBody.
  ///
  /// In en, this message translates to:
  /// **'Its own bar, its own currency and its own counter values. Everything else is shared by all notes.'**
  String get notesGuideSettingsPerNoteBody;

  /// No description provided for @notesGuidePageSafe.
  ///
  /// In en, this message translates to:
  /// **'Nothing gets lost'**
  String get notesGuidePageSafe;

  /// No description provided for @notesGuidePageSafeCaption.
  ///
  /// In en, this message translates to:
  /// **'Auto-save, the word at the top, the way back'**
  String get notesGuidePageSafeCaption;

  /// No description provided for @notesGuideSafeLead.
  ///
  /// In en, this message translates to:
  /// **'ANTA is built so a note survives anything short of losing the phone.'**
  String get notesGuideSafeLead;

  /// No description provided for @notesGuideSafeAutosaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved as you go'**
  String get notesGuideSafeAutosaveTitle;

  /// No description provided for @notesGuideSafeAutosaveBody.
  ///
  /// In en, this message translates to:
  /// **'Text is saved a few seconds after you stop typing and every half minute while you keep going; a save that fails is retried. The most you could lose is the last moment.'**
  String get notesGuideSafeAutosaveBody;

  /// No description provided for @notesGuideSafeStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'The word at the top'**
  String get notesGuideSafeStatusTitle;

  /// No description provided for @notesGuideSafeStatusBody.
  ///
  /// In en, this message translates to:
  /// **'“{saveStatusSaved}”, “{saveStatusSaving}” or “{saveStatusUnsaved}” — a glance says where things stand. “{saveStatusError}” means the phone refused the write; keep going, ANTA tries again.'**
  String notesGuideSafeStatusBody(
    String saveStatusSaved,
    String saveStatusSaving,
    String saveStatusUnsaved,
    String saveStatusError,
  );

  /// No description provided for @notesGuideSafeEventTitle.
  ///
  /// In en, this message translates to:
  /// **'A note on an event'**
  String get notesGuideSafeEventTitle;

  /// No description provided for @notesGuideSafeEventBody.
  ///
  /// In en, this message translates to:
  /// **'A calendar event can point to a note (“{eventLinkedNote}”): the plan for a session, what it cost. Open the note from the event.'**
  String notesGuideSafeEventBody(String eventLinkedNote);

  /// No description provided for @notesGuideSafeBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'The way back'**
  String get notesGuideSafeBackupTitle;

  /// No description provided for @notesGuideSafeBackupBody.
  ///
  /// In en, this message translates to:
  /// **'Deleting is final, and this phone holds the only copy until you keep another. The “{guideBookAppTitle}” guide shows how to back up and how to sync.'**
  String notesGuideSafeBackupBody(String guideBookAppTitle);

  /// No description provided for @notesGuideSafeShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Getting text out'**
  String get notesGuideSafeShareTitle;

  /// No description provided for @notesGuideSafeShareBody.
  ///
  /// In en, this message translates to:
  /// **'“{shareNote}” hands a note to any other app — a message, mail, a drive — as a file in the format you pick.'**
  String notesGuideSafeShareBody(String shareNote);

  /// No description provided for @appGuidePageMenu.
  ///
  /// In en, this message translates to:
  /// **'The main menu'**
  String get appGuidePageMenu;

  /// No description provided for @appGuidePageMenuCaption.
  ///
  /// In en, this message translates to:
  /// **'What the ☰ at the top left holds'**
  String get appGuidePageMenuCaption;

  /// No description provided for @appGuideMenuLead.
  ///
  /// In en, this message translates to:
  /// **'The ☰ at the top left opens the main menu. It lists places, not settings: every row is somewhere you go.'**
  String get appGuideMenuLead;

  /// No description provided for @appGuideMenuAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'The top row'**
  String get appGuideMenuAccountTitle;

  /// No description provided for @appGuideMenuAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Once you are signed in, the top row shows who it is and when the notes last synced — or “{drawerAccountNotSyncing}” while sync is off. Tap it to open “{sharingSettings}”.'**
  String appGuideMenuAccountBody(
    String drawerAccountNotSyncing,
    String sharingSettings,
  );

  /// No description provided for @appGuideMenuCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'“{calendar}”'**
  String appGuideMenuCalendarTitle(String calendar);

  /// No description provided for @appGuideMenuCalendarBody.
  ///
  /// In en, this message translates to:
  /// **'“{calendar}” is the month; “{calendarOverview}” lists what is coming; “{reportTitle}” counts what you did; “{calendarCategories}” and “{alertsTitle}” manage colours and alerts. The “{calendarGuideTitle}” guide, under “{howToUseAnta}”, explains them all.'**
  String appGuideMenuCalendarBody(
    String calendar,
    String calendarOverview,
    String reportTitle,
    String calendarCategories,
    String alertsTitle,
    String calendarGuideTitle,
    String howToUseAnta,
  );

  /// No description provided for @appGuideMenuNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'“{notes}”'**
  String appGuideMenuNotesTitle(String notes);

  /// No description provided for @appGuideMenuNotesBody.
  ///
  /// In en, this message translates to:
  /// **'“{counterSettings}”: your counters and their pins. The notes themselves are not in the menu: they are the folders ANTA opens on.'**
  String appGuideMenuNotesBody(String counterSettings);

  /// No description provided for @appGuideMenuAppTitle.
  ///
  /// In en, this message translates to:
  /// **'“{appGroupLabel}”'**
  String appGuideMenuAppTitle(String appGroupLabel);

  /// No description provided for @appGuideMenuAppBody.
  ///
  /// In en, this message translates to:
  /// **'“{settingsHubTitle}” holds every setting; “{howToUseAnta}” is this guide; “{about}” shows the version.'**
  String appGuideMenuAppBody(
    String settingsHubTitle,
    String howToUseAnta,
    String about,
  );

  /// No description provided for @appGuideMenuBackTitle.
  ///
  /// In en, this message translates to:
  /// **'Going back'**
  String get appGuideMenuBackTitle;

  /// No description provided for @appGuideMenuBackBody.
  ///
  /// In en, this message translates to:
  /// **'The arrow at the top left, or your phone\'s back gesture, returns to where you came from — in the end, to your folders.'**
  String get appGuideMenuBackBody;

  /// No description provided for @appGuidePageSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings worth knowing'**
  String get appGuidePageSettings;

  /// No description provided for @appGuidePageSettingsCaption.
  ///
  /// In en, this message translates to:
  /// **'Dark mode, language, permissions, where ANTA opens'**
  String get appGuidePageSettingsCaption;

  /// No description provided for @appGuideSettingsLead.
  ///
  /// In en, this message translates to:
  /// **'Everything is in “{settingsHubTitle}”. These are the settings a newcomer meets first.'**
  String appGuideSettingsLead(String settingsHubTitle);

  /// No description provided for @appGuideSettingsThemeTitle.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowTheme}”'**
  String appGuideSettingsThemeTitle(String settingsRowTheme);

  /// No description provided for @appGuideSettingsThemeBody.
  ///
  /// In en, this message translates to:
  /// **'{themeSettingsDesc}. Text size follows your phone\'s own setting.'**
  String appGuideSettingsThemeBody(String themeSettingsDesc);

  /// No description provided for @appGuideSettingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'“{languageSettings}”'**
  String appGuideSettingsLanguageTitle(String languageSettings);

  /// No description provided for @appGuideSettingsLanguageBody.
  ///
  /// In en, this message translates to:
  /// **'English, German or Romanian, for the whole app.'**
  String get appGuideSettingsLanguageBody;

  /// No description provided for @appGuideSettingsPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'“{permissionsTitle}”'**
  String appGuideSettingsPermissionsTitle(String permissionsTitle);

  /// No description provided for @appGuideSettingsPermissionsBody.
  ///
  /// In en, this message translates to:
  /// **'What the phone lets ANTA do: ring an alarm, show a notification, and so on. When something needed is off, the “{settingsHubTitle}” row in the main menu says so in red.'**
  String appGuideSettingsPermissionsBody(String settingsHubTitle);

  /// No description provided for @appGuideSettingsStartupTitle.
  ///
  /// In en, this message translates to:
  /// **'Where ANTA opens'**
  String get appGuideSettingsStartupTitle;

  /// No description provided for @appGuideSettingsStartupBody.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowGeneral}” › “{startupSection}”: “{restoreLocation}” chooses what ANTA reopens after a restart — everything, only your folders and notes, or nothing, so it always starts at your folders.'**
  String appGuideSettingsStartupBody(
    String settingsRowGeneral,
    String startupSection,
    String restoreLocation,
  );

  /// No description provided for @appGuideSettingsSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Finding a setting'**
  String get appGuideSettingsSearchTitle;

  /// No description provided for @appGuideSettingsSearchBody.
  ///
  /// In en, this message translates to:
  /// **'The search at the top of “{settingsHubTitle}” looks through every page\'s sections: type “{autoSaveSection}” or “{languageSettings}” and the page that holds it appears.'**
  String appGuideSettingsSearchBody(
    String settingsHubTitle,
    String autoSaveSection,
    String languageSettings,
  );

  /// No description provided for @appGuidePageBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup and restore'**
  String get appGuidePageBackup;

  /// No description provided for @appGuidePageBackupCaption.
  ///
  /// In en, this message translates to:
  /// **'Keeping a copy of your notes, and getting it back'**
  String get appGuidePageBackupCaption;

  /// No description provided for @appGuideBackupLead.
  ///
  /// In en, this message translates to:
  /// **'Your notes live on this phone. A copy somewhere else is what makes a lost phone a nuisance instead of a loss.'**
  String get appGuideBackupLead;

  /// No description provided for @appGuideBackupFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a folder'**
  String get appGuideBackupFolderTitle;

  /// No description provided for @appGuideBackupFolderBody.
  ///
  /// In en, this message translates to:
  /// **'“{shareFolder}” in a folder\'s ⋮ menu packs it — notes and subfolders — into one file and hands it to another app: mail it to yourself, or drop it in a drive.'**
  String appGuideBackupFolderBody(String shareFolder);

  /// No description provided for @appGuideBackupSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a selection'**
  String get appGuideBackupSelectionTitle;

  /// No description provided for @appGuideBackupSelectionBody.
  ///
  /// In en, this message translates to:
  /// **'Hold to select notes and folders, then “{shareSelected}” packs just those.'**
  String appGuideBackupSelectionBody(String shareSelected);

  /// No description provided for @appGuideBackupImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Bring a copy back'**
  String get appGuideBackupImportTitle;

  /// No description provided for @appGuideBackupImportBody.
  ///
  /// In en, this message translates to:
  /// **'“{importNoteOrFolder}” in a folder\'s ⋮ menu takes such a file — or a single markdown file — and puts its notes in that folder.'**
  String appGuideBackupImportBody(String importNoteOrFolder);

  /// No description provided for @appGuideBackupDatabaseTitle.
  ///
  /// In en, this message translates to:
  /// **'The whole database'**
  String get appGuideBackupDatabaseTitle;

  /// No description provided for @appGuideBackupDatabaseBody.
  ///
  /// In en, this message translates to:
  /// **'“{settingsRowDatabases}” in “{settingsHubTitle}” works on everything at once: “{shareDatabase}” sends one file with every folder, note, counter and event; “{importDatabase}” loads such a file as a new database.'**
  String appGuideBackupDatabaseBody(
    String settingsRowDatabases,
    String settingsHubTitle,
    String shareDatabase,
    String importDatabase,
  );

  /// No description provided for @appGuideBackupSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'More than one database'**
  String get appGuideBackupSwitchTitle;

  /// No description provided for @appGuideBackupSwitchBody.
  ///
  /// In en, this message translates to:
  /// **'You can keep several databases — work and home — and switch between them on the same page. ANTA restarts on the one you pick.'**
  String get appGuideBackupSwitchBody;

  /// No description provided for @appGuideBackupFirstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'On a new phone'**
  String get appGuideBackupFirstRunTitle;

  /// No description provided for @appGuideBackupFirstRunBody.
  ///
  /// In en, this message translates to:
  /// **'The first screen offers “{restoreFromBackup}”: pick a backup file and everything is back before you have made a single note.'**
  String appGuideBackupFirstRunBody(String restoreFromBackup);

  /// No description provided for @appGuidePageSync.
  ///
  /// In en, this message translates to:
  /// **'Sync between phones'**
  String get appGuidePageSync;

  /// No description provided for @appGuidePageSyncCaption.
  ///
  /// In en, this message translates to:
  /// **'Sign in once, the same notes on every device'**
  String get appGuidePageSyncCaption;

  /// No description provided for @appGuideSyncLead.
  ///
  /// In en, this message translates to:
  /// **'Sync keeps a copy of a database in your account and sends every change to your other devices. It is off until you turn it on.'**
  String get appGuideSyncLead;

  /// No description provided for @appGuideSyncSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get appGuideSyncSignInTitle;

  /// No description provided for @appGuideSyncSignInBody.
  ///
  /// In en, this message translates to:
  /// **'“{sharingSettings}” in “{settingsHubTitle}”: “{signInWithGoogle}”. Your notes stay on the phone; signing in alone sends nothing.'**
  String appGuideSyncSignInBody(
    String sharingSettings,
    String settingsHubTitle,
    String signInWithGoogle,
  );

  /// No description provided for @appGuideSyncOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn it on'**
  String get appGuideSyncOnTitle;

  /// No description provided for @appGuideSyncOnBody.
  ///
  /// In en, this message translates to:
  /// **'“{syncThisDatabase}” on the same page starts syncing the database you are using. {syncThisDatabaseDesc}.'**
  String appGuideSyncOnBody(
    String syncThisDatabase,
    String syncThisDatabaseDesc,
  );

  /// No description provided for @appGuideSyncStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Where it stands'**
  String get appGuideSyncStatusTitle;

  /// No description provided for @appGuideSyncStatusBody.
  ///
  /// In en, this message translates to:
  /// **'The page says “{syncUpToDate}”, “{syncOffline}” or how many changes are waiting; the main menu\'s top row shows when it last synced. Nothing is lost offline: changes go once the connection is back, and “{syncNow}” does not wait.'**
  String appGuideSyncStatusBody(
    String syncUpToDate,
    String syncOffline,
    String syncNow,
  );

  /// No description provided for @appGuideSyncCadenceTitle.
  ///
  /// In en, this message translates to:
  /// **'When it syncs'**
  String get appGuideSyncCadenceTitle;

  /// No description provided for @appGuideSyncCadenceBody.
  ///
  /// In en, this message translates to:
  /// **'“{syncAutomatic}” on the same page is on to begin with: changes sync while the app is open and when you leave it. Turn it off and nothing moves until you tap “{syncNow}” — for a metered connection, or when you want to say when.'**
  String appGuideSyncCadenceBody(String syncAutomatic, String syncNow);

  /// No description provided for @appGuideSyncOtherTitle.
  ///
  /// In en, this message translates to:
  /// **'On the other phone'**
  String get appGuideSyncOtherTitle;

  /// No description provided for @appGuideSyncOtherBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the same account and turn “{syncThisDatabase}” on there too. ANTA lists the spaces in your account; pick yours and it is downloaded into a new database on that phone. After that, only changes travel.'**
  String appGuideSyncOtherBody(String syncThisDatabase);

  /// No description provided for @appGuideSyncConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Two phones, one note'**
  String get appGuideSyncConflictTitle;

  /// No description provided for @appGuideSyncConflictBody.
  ///
  /// In en, this message translates to:
  /// **'If the same note changes in two places, ANTA keeps both: the other version is filed beside yours as a copy, so nothing is overwritten.'**
  String get appGuideSyncConflictBody;

  /// The bare $! chip's text in the preview when no $! target stands above it, shown in place of an amount
  ///
  /// In en, this message translates to:
  /// **'no target'**
  String get moneyNoTarget;

  /// The markdown page's Try it editor as seeded: plain lines without markdown, so every step starts undone
  ///
  /// In en, this message translates to:
  /// **'Leg day\nSquat 5×5\nBench 3×8\nFelt strong today'**
  String get notesGuideSeedMarkdown;

  /// The lists page's Try it editor as seeded: four flat bullets, nothing nested
  ///
  /// In en, this message translates to:
  /// **'- Legs\n- Squat\n- Lunges\n- Back'**
  String get notesGuideSeedLists;

  /// The own-markdown page's Try it editor as seeded: no tag, ghost, colour or wiki link yet
  ///
  /// In en, this message translates to:
  /// **'Deadlift 140 kg\nNext week: squat\nSame warm-up as last time'**
  String get notesGuideSeedOwn;

  /// The money page's Try it editor as seeded: a start amount, one spend and an empty last line where the caret waits, so a bar button writes a new ledger line
  ///
  /// In en, this message translates to:
  /// **'\$= 500 budget\n\$- 40 gym\n'**
  String get notesGuideSeedMoney;

  /// Coach line of the markdown card; quotes the seed's first line and the bar's heading button, which opens a menu of heading levels
  ///
  /// In en, this message translates to:
  /// **'Tap “Leg day”, then “{headers}” on the bar, and pick a level: a # in front makes it a heading.'**
  String notesGuideCoachMarkdownHeading(String headers);

  /// Coach line of the markdown card; quotes the bar's bold button, which writes the pair of stars around the caret
  ///
  /// In en, this message translates to:
  /// **'Tap “{bold}” and type a word: two stars on each side make it bold.'**
  String notesGuideCoachMarkdownBold(String bold);

  /// Coach line of the markdown card; quotes the bar's bullet list button
  ///
  /// In en, this message translates to:
  /// **'Tap another line, then “{bulletList}”: a dash and a space in front make it a bullet.'**
  String notesGuideCoachMarkdownList(String bulletList);

  /// Coach line of the markdown card; quotes the bar's checkbox button; done when a task line is ticked
  ///
  /// In en, this message translates to:
  /// **'Tap one more line, then “{checkbox}” — and tap the box to tick it.'**
  String notesGuideCoachMarkdownTask(String checkbox);

  /// Coach line of the lists card; quotes the seed's last item
  ///
  /// In en, this message translates to:
  /// **'Tap after “Back” and press Enter: the next bullet is ready.'**
  String get notesGuideCoachListsEnter;

  /// Coach line of the lists card; quotes two seed items and the bar's indent button
  ///
  /// In en, this message translates to:
  /// **'Tap “Squat”, then swipe it right or tap “{indentLine}” on the bar: it nests under Legs.'**
  String notesGuideCoachListsNest(String indentLine);

  /// Coach line of the lists card; quotes the bar's outdent button
  ///
  /// In en, this message translates to:
  /// **'Swipe it left, or tap “{outdentLine}”: it comes back out.'**
  String notesGuideCoachListsOutdent(String outdentLine);

  /// Coach line of the lists card
  ///
  /// In en, this message translates to:
  /// **'Press Enter on an empty bullet: the list ends in a plain line.'**
  String get notesGuideCoachListsEnd;

  /// Coach line of the own-markdown card
  ///
  /// In en, this message translates to:
  /// **'Add #pr at the end of the first line: a word after # is a tag.'**
  String get notesGuideCoachOwnTag;

  /// Coach line of the own-markdown card; quotes a seed word and the bar's ghost text button, which writes the double braces
  ///
  /// In en, this message translates to:
  /// **'Tap after “squat”, then “{shortcutGhostText}” on the bar: a blank to fill in later.'**
  String notesGuideCoachOwnGhost(String shortcutGhostText);

  /// Coach line of the own-markdown card; quotes the bar's colour text button, which writes a red slot the typed word fills
  ///
  /// In en, this message translates to:
  /// **'Tap another line, then “{shortcutColorText}”, and type “heavy”: the word turns red.'**
  String notesGuideCoachOwnColour(String shortcutColorText);

  /// Coach line of the own-markdown card; no bar button writes a wiki link, so it is typed
  ///
  /// In en, this message translates to:
  /// **'On a line of its own, write [[Leg day]]: double brackets link to the note of that name.'**
  String get notesGuideCoachOwnWiki;

  /// Coach line of the money card; quotes the bar's spend button, which writes the $- marker
  ///
  /// In en, this message translates to:
  /// **'Tap the empty line, then “{shortcutMoneySubtract}”, and type 25 shoes: another spend.'**
  String notesGuideCoachMoneySpend(String shortcutMoneySubtract);

  /// Coach line of the money card; quotes the bar's add button, which writes the $+ marker
  ///
  /// In en, this message translates to:
  /// **'Press Enter, then “{shortcutMoneyAdd}”, and type 25 refund: money coming in.'**
  String notesGuideCoachMoneyAdd(String shortcutMoneyAdd);

  /// Coach line of the money card; quotes the bar's total button, which writes $$
  ///
  /// In en, this message translates to:
  /// **'Press Enter and tap “{shortcutMoneyTotal}”: what is left, as a chip.'**
  String notesGuideCoachMoneyTotal(String shortcutMoneyTotal);

  /// A Try it editor's report after a tap on a tag, which a sandbox cannot act on; never quotes the tag
  ///
  /// In en, this message translates to:
  /// **'In a note, tapping a tag lists every note that carries it.'**
  String get notesGuideReportTag;

  /// A Try it editor's report after a tap on a wiki link
  ///
  /// In en, this message translates to:
  /// **'In a note, tapping the link opens that note.'**
  String get notesGuideReportWiki;

  /// A Try it editor's report after a tap on a web link
  ///
  /// In en, this message translates to:
  /// **'In a note, tapping a web link opens it in your browser.'**
  String get notesGuideReportLink;

  /// A Try it editor's report after a tap on a money chip
  ///
  /// In en, this message translates to:
  /// **'In a note, tapping a total shows every line that went into it.'**
  String get notesGuideReportMoney;

  /// The shortcuts card's report when her own button is pressed while the field above the editor is empty; quotes the field's label
  ///
  /// In en, this message translates to:
  /// **'Your button has nothing to write yet: fill in “{markdownStart}” first.'**
  String notesGuideReportEmptyButton(String markdownStart);

  /// Title of the notes guide's page about making custom markdown shortcuts
  ///
  /// In en, this message translates to:
  /// **'Your own shortcuts'**
  String get notesGuidePageShortcuts;

  /// No description provided for @notesGuidePageShortcutsCaption.
  ///
  /// In en, this message translates to:
  /// **'Buttons that write your lines: a set, a date, a count'**
  String get notesGuidePageShortcutsCaption;

  /// No description provided for @notesGuideShortcutsLead.
  ///
  /// In en, this message translates to:
  /// **'A shortcut is a button on the bar that writes for you. ANTA ships a set of them; the ones you make turn the lines you repeat into one tap.'**
  String get notesGuideShortcutsLead;

  /// The shortcuts page's Try it editor as seeded: one plain line and an empty one where the caret waits
  ///
  /// In en, this message translates to:
  /// **'Leg day\n'**
  String get notesGuideSeedShortcuts;

  /// Name of the guide's example shortcut that writes one workout set; a noun
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get notesGuideShortcutSetLabel;

  /// What the guide's example Set shortcut writes: a checkbox line with the set's number and two ghost blanks. count is the counter token, open and close the literal braces
  ///
  /// In en, this message translates to:
  /// **'- [ ] Set {count}: {open}{open}weight{close}{close} kg × {open}{open}reps{close}{close}'**
  String notesGuideShortcutSetText(String count, String open, String close);

  /// Name of the guide's example shortcut that writes today's date as a heading
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get notesGuideShortcutTodayLabel;

  /// Name of the star button on the shortcuts card's bar, the one that writes what she typed in the field
  ///
  /// In en, this message translates to:
  /// **'Your button'**
  String get notesGuideShortcutMineLabel;

  /// Coach line of the shortcuts card; quotes the example Set button. The seed ends in an empty line: a button writes at the cursor, so the line says where to put it first
  ///
  /// In en, this message translates to:
  /// **'Tap the empty line, then “{set}” on the bar: one tap writes a whole line, blanks included.'**
  String notesGuideCoachShortcutsLine(String set);

  /// Coach line of the shortcuts card; the second press writes Set 2
  ///
  /// In en, this message translates to:
  /// **'Tap “{set}” again: the number counts up by itself.'**
  String notesGuideCoachShortcutsCount(String set);

  /// Coach line of the shortcuts card; quotes the example Today button
  ///
  /// In en, this message translates to:
  /// **'Tap “{today}”: today\'s date, written as a heading.'**
  String notesGuideCoachShortcutsDate(String today);

  /// Coach line of the shortcuts card; quotes the label of the field above the stage's editor, the New Shortcut page's own
  ///
  /// In en, this message translates to:
  /// **'Now yours: in “{markdownStart}”, above the note, type a line you write often.'**
  String notesGuideCoachShortcutsWrite(String markdownStart);

  /// Coach line of the shortcuts card; quotes the name of her own button, drawn as a star
  ///
  /// In en, this message translates to:
  /// **'Tap the star on the bar, “{mine}”: it writes your line, every time.'**
  String notesGuideCoachShortcutsPress(String mine);

  /// No description provided for @notesGuideShortcutsMakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Make one'**
  String get notesGuideShortcutsMakeTitle;

  /// No description provided for @notesGuideShortcutsMakeBody.
  ///
  /// In en, this message translates to:
  /// **'In Settings, open “{settingsRowEditor}” and tap + at the bottom of the page: “{newShortcut}” opens. Pick an icon, give the button a name, say what it writes, and tap “{save}”. It joins the end of the bar.'**
  String notesGuideShortcutsMakeBody(
    String settingsRowEditor,
    String newShortcut,
    String save,
  );

  /// No description provided for @notesGuideShortcutsTextTitle.
  ///
  /// In en, this message translates to:
  /// **'What it writes'**
  String get notesGuideShortcutsTextTitle;

  /// No description provided for @notesGuideShortcutsTextBody.
  ///
  /// In en, this message translates to:
  /// **'“{markdownStart}” is written in front of the cursor, or of the text you selected; “{markdownEnd}” behind it. For a whole line — a set, a meal, a heading — put all of it in “{markdownStart}” and leave “{markdownEnd}” empty.'**
  String notesGuideShortcutsTextBody(String markdownStart, String markdownEnd);

  /// No description provided for @notesGuideShortcutsKindsTitle.
  ///
  /// In en, this message translates to:
  /// **'Three kinds'**
  String get notesGuideShortcutsKindsTitle;

  /// Read row of the shortcuts page; quotes the insert type field, its three choices and the names the two text fields take for a date shortcut
  ///
  /// In en, this message translates to:
  /// **'“{insertType}” decides what goes between the two: “{wrapSelectedText}” keeps your selection there, “{insertCurrentDate}” writes the date in the format you choose — the two fields are then called “{beforeDate}” and “{afterDate}” — and “{insertCounter}” the next value of a counter.'**
  String notesGuideShortcutsKindsBody(
    String insertType,
    String wrapSelectedText,
    String insertCurrentDate,
    String insertCounter,
    String beforeDate,
    String afterDate,
  );

  /// No description provided for @notesGuideShortcutsPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'See it before you save'**
  String get notesGuideShortcutsPreviewTitle;

  /// No description provided for @notesGuideShortcutsPreviewBody.
  ///
  /// In en, this message translates to:
  /// **'“{preview}”, at the bottom of that page, shows what the button will write, drawn the way a note draws it.'**
  String notesGuideShortcutsPreviewBody(String preview);

  /// No description provided for @notesGuideShortcutsBlanksTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave blanks'**
  String get notesGuideShortcutsBlanksTitle;

  /// Read row of the shortcuts page; the braces travel as placeholders because ICU reads a bare brace as an argument
  ///
  /// In en, this message translates to:
  /// **'Double braces leave a blank in the line: Squat {open}{open}weight{close}{close} kg writes a dimmed “weight” to tap and type over. One button, a new number every time.'**
  String notesGuideShortcutsBlanksBody(String open, String close);

  /// No description provided for @notesGuideShortcutsRepeatTitle.
  ///
  /// In en, this message translates to:
  /// **'Several at once'**
  String get notesGuideShortcutsRepeatTitle;

  /// No description provided for @notesGuideShortcutsRepeatBody.
  ///
  /// In en, this message translates to:
  /// **'Switch on “{advancedOptions}”: “{repeatSettings}” writes the text several times in one tap — three sets, seven days. With “{incrementDateOnRepeat}”, a date moves on with every copy, so one tap writes the week.'**
  String notesGuideShortcutsRepeatBody(
    String advancedOptions,
    String repeatSettings,
    String incrementDateOnRepeat,
  );

  /// No description provided for @notesGuideShortcutsDateTitle.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow, next week'**
  String get notesGuideShortcutsDateTitle;

  /// No description provided for @notesGuideShortcutsDateBody.
  ///
  /// In en, this message translates to:
  /// **'“{dateOffset}”, under “{advancedOptions}”, shifts the date a button writes: one day for tomorrow\'s plan, seven for next week\'s.'**
  String notesGuideShortcutsDateBody(String dateOffset, String advancedOptions);

  /// No description provided for @notesGuideShortcutsCountersTitle.
  ///
  /// In en, this message translates to:
  /// **'Count as it writes'**
  String get notesGuideShortcutsCountersTitle;

  /// Read row of the shortcuts page; the braces of the counter tokens travel as placeholders
  ///
  /// In en, this message translates to:
  /// **'“{counterBindingsTitle}”, also under “{advancedOptions}”, ties up to two counters to the button. Where the text says {open}c1{close} or {open}c2{close}, the counter\'s next value is written — Set 1, Set 2, Set 3 — one step for every tap.'**
  String notesGuideShortcutsCountersBody(
    String counterBindingsTitle,
    String advancedOptions,
    String open,
    String close,
  );

  /// No description provided for @notesGuideShortcutsTidyTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the bar short'**
  String get notesGuideShortcutsTidyTitle;

  /// No description provided for @notesGuideShortcutsTidyBody.
  ///
  /// In en, this message translates to:
  /// **'In the list of shortcuts, the eye hides a button without deleting it, and a long press drags it to a new place. ⋮ › “{setCategory}” groups buttons, and the chips above the list then filter it by group. ⋮ also edits or deletes a button you made; the built-in ones can only be hidden.'**
  String notesGuideShortcutsTidyBody(String setCategory);

  /// No description provided for @notesGuideShortcutsBarsTitle.
  ///
  /// In en, this message translates to:
  /// **'Each bar has its own'**
  String get notesGuideShortcutsBarsTitle;

  /// No description provided for @notesGuideShortcutsBarsBody.
  ///
  /// In en, this message translates to:
  /// **'A shortcut belongs to the bar you made it in. With several bars under “{manageBarProfiles}”, choose the bar first, then add the button.'**
  String notesGuideShortcutsBarsBody(String manageBarProfiles);

  /// Label over the rendered half of a shortcut recipe on the shortcuts page, in place of You get; the half above it is labelled with the New Shortcut page's own field name
  ///
  /// In en, this message translates to:
  /// **'One tap writes'**
  String get notesGuideRecipeShown;

  /// A shortcut recipe: the text of a button that writes one workout set with two blanks
  ///
  /// In en, this message translates to:
  /// **'- [ ] {open}{open}weight{close}{close} kg × {open}{open}reps{close}{close}'**
  String notesGuideExRecipeSetSource(String open, String close);

  /// No description provided for @notesGuideExRecipeSetCaption.
  ///
  /// In en, this message translates to:
  /// **'A set to tick off, with two blanks to fill in.'**
  String get notesGuideExRecipeSetCaption;

  /// A shortcut recipe: the text of a button that writes a line with a bold label and one blank
  ///
  /// In en, this message translates to:
  /// **'**Warm-up:** {open}{open}minutes{close}{close} min on the bike'**
  String notesGuideExRecipeLabelSource(String open, String close);

  /// No description provided for @notesGuideExRecipeLabelCaption.
  ///
  /// In en, this message translates to:
  /// **'A line that always starts the same: the opening in bold, the number left blank.'**
  String get notesGuideExRecipeLabelCaption;

  /// No description provided for @notesGuideMarkdownCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Code and rules'**
  String get notesGuideMarkdownCodeTitle;

  /// No description provided for @notesGuideMarkdownCodeBody.
  ///
  /// In en, this message translates to:
  /// **'A backtick (`) on each side keeps a word exactly as typed, in a fixed-width font; three backticks on a line of their own start a block that stays as typed until three more end it. Three dashes on a line of their own draw a rule across the note. The bar has “{inlineCode}”, “{codeBlock}” and “{shortcutHorizontalRule}” for them.'**
  String notesGuideMarkdownCodeBody(
    String inlineCode,
    String codeBlock,
    String shortcutHorizontalRule,
  );

  /// No description provided for @notesGuideMoneyBackTitle.
  ///
  /// In en, this message translates to:
  /// **'Looking back'**
  String get notesGuideMoneyBackTitle;

  /// No description provided for @notesGuideMoneyBackBody.
  ///
  /// In en, this message translates to:
  /// **'\$^ 3 shows how much the last three entries changed the balance; \$~ 2 the change across the last two \$= lines. Both only show a number — the balance stays as it is. On the bar they are “{shortcutMoneyDiff}” and “{shortcutMoneySpan}”.'**
  String notesGuideMoneyBackBody(
    String shortcutMoneyDiff,
    String shortcutMoneySpan,
  );

  /// No description provided for @appGuideSyncStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get appGuideSyncStopTitle;

  /// No description provided for @appGuideSyncStopBody.
  ///
  /// In en, this message translates to:
  /// **'“{syncStop}” leaves your notes on this phone and stops sending and receiving; the copy in your account stays. “{signOut}” pauses sync for every database until you sign in again.'**
  String appGuideSyncStopBody(String syncStop, String signOut);

  /// No description provided for @appGuideSyncDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting the cloud copy'**
  String get appGuideSyncDeleteTitle;

  /// No description provided for @appGuideSyncDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'“{delete}” removes the database from your account for good. It stays on this phone, which stops syncing it; your other devices keep theirs and stop too.'**
  String appGuideSyncDeleteBody(String delete);

  /// No description provided for @appGuideSyncDeleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account'**
  String get appGuideSyncDeleteAccountTitle;

  /// No description provided for @appGuideSyncDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'“{deleteAccount}” on the same page removes every cloud copy of the account, ends sharing with your partner and deletes the account itself, once Google has asked you to sign in again. Everything stays on this phone.'**
  String appGuideSyncDeleteAccountBody(String deleteAccount);

  /// Header of the Sync & sharing page's section that says where data is stored
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get dataNoticeSection;

  /// Title of the Privacy section's row, of the notice it opens and of the guide's row about it
  ///
  /// In en, this message translates to:
  /// **'Where your data is stored'**
  String get dataNoticeTitle;

  /// Description of the 'Where your data is stored' row: the short answer, the notice gives the whole one
  ///
  /// In en, this message translates to:
  /// **'On this device, and in Google\'s cloud for a database you sync'**
  String get dataNoticeDesc;

  /// Comma-separated search keywords for the 'Where your data is stored' row, added to the page's own
  ///
  /// In en, this message translates to:
  /// **'privacy, data, location, server, storage, region, country, encryption, encrypted, google, gdpr'**
  String get dataNoticeKeywords;

  /// First paragraph of the data notice: content is local until a database syncs
  ///
  /// In en, this message translates to:
  /// **'Your notes, events and counters are stored on this device. They leave it only when you turn on sync for a database.'**
  String get dataNoticeLocal;

  /// Second paragraph of the data notice while the cloud database is located in the United States
  ///
  /// In en, this message translates to:
  /// **'A database that syncs keeps a copy in Google\'s cloud, on servers in the United States.'**
  String get dataNoticeCloudUs;

  /// Second paragraph of the data notice once the cloud database is located in the European Union
  ///
  /// In en, this message translates to:
  /// **'A database that syncs keeps a copy in Google\'s cloud, on servers in the European Union.'**
  String get dataNoticeCloudEu;

  /// Paragraph of the data notice: who can read a synced copy
  ///
  /// In en, this message translates to:
  /// **'The copy is encrypted on its way and where it is stored, but not end-to-end: the people who run ANTA\'s cloud service can read it.'**
  String get dataNoticeReadable;

  /// Paragraph of the data notice: what signing in stores, and that the sign-in service keeps it in the United States whatever the database's location
  ///
  /// In en, this message translates to:
  /// **'Signing in keeps your Google name, e-mail address and profile picture with your account. Google\'s sign-in service stores them in the United States.'**
  String get dataNoticeAccount;

  /// Paragraph of the data notice: what a paired partner can see
  ///
  /// In en, this message translates to:
  /// **'Once you pair, your partner sees your name and profile picture — and nothing else unless you share it with them.'**
  String get dataNoticePartner;

  /// Paragraph of the data notice: what the paired partner can read of what this person shares, and when it leaves their phone
  ///
  /// In en, this message translates to:
  /// **'What you share with your partner can be read by their account from your cloud copy, and their phone keeps a read-only copy of it. That copy leaves their phone the next time it syncs after you stop sharing.'**
  String get dataNoticeShared;

  /// Last paragraph of the data notice: the two rows that remove cloud data, named by their labels
  ///
  /// In en, this message translates to:
  /// **'“{deleteCopy}” removes a database\'s copy from the cloud; “{deleteAccount}” removes everything your account keeps there. Neither deletes anything on this device.'**
  String dataNoticeRemove(String deleteCopy, String deleteAccount);

  /// Body of the app guide's row about where synced data is stored; its title is dataNoticeTitle
  ///
  /// In en, this message translates to:
  /// **'A database you sync keeps a copy in Google\'s cloud. It is encrypted there, but not end-to-end: the people who run ANTA\'s cloud service can read it. “{dataNotice}” on the same page says where it is kept and how to remove it.'**
  String appGuideSyncDataBody(String dataNotice);

  /// No description provided for @appGuidePageSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing with your partner'**
  String get appGuidePageSharing;

  /// No description provided for @appGuidePageSharingCaption.
  ///
  /// In en, this message translates to:
  /// **'A category or an event, read-only on their phone'**
  String get appGuidePageSharingCaption;

  /// No description provided for @appGuideSharingLead.
  ///
  /// In en, this message translates to:
  /// **'Pair with one person and choose what they see. Nothing is shared until you switch it on; your partner reads and never changes it; switch it off and it leaves their phone.'**
  String get appGuideSharingLead;

  /// No description provided for @appGuideSharingPairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair first'**
  String get appGuideSharingPairTitle;

  /// Body of the app guide's row about pairing before sharing; the placeholders are the app's own labels
  ///
  /// In en, this message translates to:
  /// **'“{pairingSection}” in “{sharingSettings}” links you with one person through a code. Pairing alone shares nothing. Both phones need “{syncThisDatabase}” on — what you share travels with sync.'**
  String appGuideSharingPairBody(
    String pairingSection,
    String sharingSettings,
    String syncThisDatabase,
  );

  /// No description provided for @appGuideSharingCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a category'**
  String get appGuideSharingCategoryTitle;

  /// Body of the app guide's row about sharing a category; shareWith is the switch's label with the stand-in partner name, sharingPage the Sharing page's title
  ///
  /// In en, this message translates to:
  /// **'In a category\'s editor, “{shareWith}” shares every event in it, and every event you add to it later. The ⋮ menu on the “{calendarCategories}” page does the same; “{sharingPage}”, behind the pairing row, ticks several at once.'**
  String appGuideSharingCategoryBody(
    String shareWith,
    String calendarCategories,
    String sharingPage,
  );

  /// No description provided for @appGuideSharingEventTitle.
  ///
  /// In en, this message translates to:
  /// **'Share one event'**
  String get appGuideSharingEventTitle;

  /// Body of the app guide's row about sharing one event
  ///
  /// In en, this message translates to:
  /// **'The same switch, “{shareWith}”, in an event\'s editor shares that event alone. An event in a shared category is shared already; its switch says so.'**
  String appGuideSharingEventBody(String shareWith);

  /// No description provided for @appGuideSharingReadOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'Read-only for them'**
  String get appGuideSharingReadOnlyTitle;

  /// Body of the app guide's row saying a share is read-only and that a copy stays; copy is the read sheet's Copy to my calendar label
  ///
  /// In en, this message translates to:
  /// **'Your partner sees what you share and cannot change it, so a list cannot be ticked off by both of you. “{copy}” gives them an event of their own; your later changes do not reach that copy, and it stays when you stop sharing.'**
  String appGuideSharingReadOnlyBody(String copy);

  /// No description provided for @appGuideSharingTheirsTitle.
  ///
  /// In en, this message translates to:
  /// **'What your partner shares'**
  String get appGuideSharingTheirsTitle;

  /// Body of the app guide's row about what the partner shares with this person
  ///
  /// In en, this message translates to:
  /// **'Their events open a sheet you can read, not edit. On “{sharingPage}” you choose which of their categories show on your calendar and how their events are told apart from yours. Reports, goals and attendance count only your own events.'**
  String appGuideSharingTheirsBody(String sharingPage);

  /// No description provided for @appGuideSharingAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get appGuideSharingAlertsTitle;

  /// Body of the app guide's row about alerts on shared events; the placeholders are the Sharing page's own labels
  ///
  /// In en, this message translates to:
  /// **'Your partner\'s alerts never ring on your phone, nor yours on theirs. Add an alert of your own to a shared event from its sheet. “{shareAlerts}” on the same page can silence them all (“{alertsOff}”) or let shared events follow your own category alerts (“{alertsCategory}”).'**
  String appGuideSharingAlertsBody(
    String shareAlerts,
    String alertsOff,
    String alertsCategory,
  );

  /// No description provided for @appGuideSharingStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get appGuideSharingStopTitle;

  /// Body of the app guide's row about stopping a share, everything, or the pair
  ///
  /// In en, this message translates to:
  /// **'Switch a share off and it leaves your partner\'s phone the next time it syncs. “{stopAll}” takes everything back and keeps you paired; “{unpair}” ends sharing both ways.'**
  String appGuideSharingStopBody(String stopAll, String unpair);

  /// No description provided for @appGuideSharingPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'What is never shared'**
  String get appGuideSharingPrivateTitle;

  /// No description provided for @appGuideSharingPrivateBody.
  ///
  /// In en, this message translates to:
  /// **'Your notes, counters, alerts, attendance marks, templates and settings stay on your side whatever you share.'**
  String get appGuideSharingPrivateBody;

  /// Stands in for {name} in every sharing string when the paired partner has no profile name. Lower case: the code capitalises a string that begins with it
  ///
  /// In en, this message translates to:
  /// **'your partner'**
  String get sharePartnerFallback;

  /// Label of the share switch in the category editor and the event editor, and of the category menu's entry while the category is private. {name} is the paired partner, never declined
  ///
  /// In en, this message translates to:
  /// **'Share with {name}'**
  String shareWithPartner(String name);

  /// The category menu's entry while the category is shared (ticked)
  ///
  /// In en, this message translates to:
  /// **'Shared with {name}'**
  String sharedWithPartner(String name);

  /// Marks something the partner shares: the read sheet's header, a section header in the categories page and the filter lists, a digest line
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String shareFromPartner(String name);

  /// Title of the Sharing page
  ///
  /// In en, this message translates to:
  /// **'Sharing with {name}'**
  String sharingWithTitle(String name);

  /// Section label on the Sharing page over what this person shares with the partner
  ///
  /// In en, this message translates to:
  /// **'You share'**
  String get shareYouShare;

  /// Section label on the Sharing page over what the partner shares with this person
  ///
  /// In en, this message translates to:
  /// **'{name} shares with you'**
  String sharePartnerShares(String name);

  /// Sharing page entry: the shared categories
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get shareRowCategories;

  /// Sharing page entry and sheet title: events shared one by one, outside a shared category
  ///
  /// In en, this message translates to:
  /// **'Single events'**
  String get shareRowEvents;

  /// Description of a Sharing page entry with nothing in it, and the empty line of the partner's single-events list
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get shareNone;

  /// Intro line under the 'You share' section
  ///
  /// In en, this message translates to:
  /// **'{name} sees these and cannot change them.'**
  String shareYouShareCaption(String name);

  /// Snackbar when a share, an un-share, an undo or 'Stop sharing everything' could not be written; nothing changed
  ///
  /// In en, this message translates to:
  /// **'Sharing couldn\'t be changed — try again'**
  String get shareChangeFailed;

  /// The one line the Sharing page shows instead of its sections when what is shared could not be read
  ///
  /// In en, this message translates to:
  /// **'Sharing couldn\'t be loaded'**
  String get shareLoadFailed;

  /// Screen-reader hint on a share row or entry that cannot be used until sync is on: says where its tap leads
  ///
  /// In en, this message translates to:
  /// **'Opens Sync & sharing'**
  String get shareOpensSyncHint;

  /// Intro line under the section of what the partner shares
  ///
  /// In en, this message translates to:
  /// **'Read-only. They leave when {name} stops sharing.'**
  String sharePartnerSharesCaption(String name);

  /// Status beside the 'You share' label while share changes are still leaving this phone
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get shareSending;

  /// Status beside the 'You share' label while offline with share changes waiting
  ///
  /// In en, this message translates to:
  /// **'Waiting to send'**
  String get shareWaitingToSend;

  /// Status beside the partner's section label: when what the partner shares was last read. {when} is a relative moment such as '2 min ago'
  ///
  /// In en, this message translates to:
  /// **'Updated {when}'**
  String shareUpdated(String when);

  /// Reason line of a dimmed share control while this database does not sync
  ///
  /// In en, this message translates to:
  /// **'Turn on sync to share'**
  String get shareNeedsSync;

  /// Line in the partner's section while this database does not sync
  ///
  /// In en, this message translates to:
  /// **'Turn on sync to receive'**
  String get shareNeedsSyncReceive;

  /// Status at the end of the partner's section header after the last read of what the partner shares failed; kept short, the header's title shares its line
  ///
  /// In en, this message translates to:
  /// **'Could not check'**
  String get shareCheckFailed;

  /// Line in the partner's section when nothing was read for seven days or more
  ///
  /// In en, this message translates to:
  /// **'May be out of date'**
  String get shareMaybeStale;

  /// Line in the partner's section when the partner's phone runs a newer version whose rows this build cannot read
  ///
  /// In en, this message translates to:
  /// **'Update ANTA to see everything {name} shares'**
  String shareUpdateApp(String name);

  /// Line in the partner's section: rows of the partner that collide with an id of this person's own and are not shown
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item could not be shown} other{{count} items could not be shown}}'**
  String shareNotShown(int count);

  /// Second line of the event editor's share switch while off
  ///
  /// In en, this message translates to:
  /// **'Only you see this event'**
  String get shareEventOff;

  /// Second line of the event editor's share switch while on
  ///
  /// In en, this message translates to:
  /// **'{name} sees it, read-only'**
  String shareEventOn(String name);

  /// Second line of the event editor's share switch when the event's category is shared: the switch shows on and locked
  ///
  /// In en, this message translates to:
  /// **'On for everything in {category}'**
  String shareThroughCategory(String category);

  /// Snackbar after an event's own share mark was taken away while its category is shared, so the partner still sees it
  ///
  /// In en, this message translates to:
  /// **'{title} stays shared through {category}'**
  String shareStaysThroughCategory(String title, String category);

  /// Second line of the category editor's share switch while off
  ///
  /// In en, this message translates to:
  /// **'Only you see these events'**
  String get shareCategoryOff;

  /// Second line of the category editor's share switch while on, for a category that has events. Zero events uses shareCategoryNewOnly
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Its 1 event, and new ones} other{All {count} events, and new ones}}'**
  String shareCategoryOn(int count);

  /// Second line of the category editor's share switch while on, for a category with no events yet
  ///
  /// In en, this message translates to:
  /// **'New events are shared'**
  String get shareCategoryNewOnly;

  /// Title of the category tick sheet opened from the Sharing page
  ///
  /// In en, this message translates to:
  /// **'Share categories'**
  String get shareCategoriesTitle;

  /// Caption under the header of the category tick sheet
  ///
  /// In en, this message translates to:
  /// **'{name} sees every event in a ticked category, new ones too. Only you can change them.'**
  String shareCategoriesCaption(String name);

  /// Title of the sheet listing the categories the partner shares
  ///
  /// In en, this message translates to:
  /// **'Categories from {name}'**
  String shareTheirCategoriesTitle(String name);

  /// Caption under the header of the sheet listing the partner's categories, each with a show switch
  ///
  /// In en, this message translates to:
  /// **'Switched-off ones stay off your calendar; {name} never sees what you hide.'**
  String shareTheirCategoriesCaption(String name);

  /// Label of the switch that shows or hides one of the partner's categories on this phone
  ///
  /// In en, this message translates to:
  /// **'Show on my calendar'**
  String get shareShowOnCalendar;

  /// Screen-reader label of the show switch on one of the partner's categories in the list of what they share
  ///
  /// In en, this message translates to:
  /// **'Show {category} on my calendar'**
  String shareShowCategoryOnCalendar(String category);

  /// Caption under the dimmed alerts group of a partner's category that is hidden on this phone
  ///
  /// In en, this message translates to:
  /// **'Hidden from your calendar, so these never ring'**
  String get shareHiddenCategoryAlertsCaption;

  /// Second-line fragment for a built-in category the partner shares, after the event count and a middle dot: its events are drawn in this person's own category of the same kind
  ///
  /// In en, this message translates to:
  /// **'joins your {category}'**
  String shareJoinsYours(String category);

  /// Snackbar after something was shared, with Undo. {what} is one name or a comma-separated list
  ///
  /// In en, this message translates to:
  /// **'Sharing {what} with {name}'**
  String shareStarted(String what, String name);

  /// Snackbar after something stopped being shared, with Undo. {what} is one name or a comma-separated list
  ///
  /// In en, this message translates to:
  /// **'No longer shared: {what}'**
  String shareStopped(String what);

  /// Snackbar after a category stopped being shared while some of its events carry a share of their own
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{No longer shared: {what}. 1 event stays shared on its own.} other{No longer shared: {what}. {count} events stay shared on their own.}}'**
  String shareStoppedSomeStay(String what, int count);

  /// Consequence line in the category delete sheet when the deleted category is shared and its events move to a private one
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} stops seeing its 1 event} other{{name} stops seeing its {count} events}}'**
  String shareDeleteImpactStops(String name, int count);

  /// Consequence line in the category delete sheet when the events move to a category that is shared too
  ///
  /// In en, this message translates to:
  /// **'They stay shared through {category}'**
  String shareDeleteImpactStays(String category);

  /// Consequence line in the category delete sheet when the deleted category is private and its events move to a category that is shared: they become shared
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} will see its 1 event through {category}} other{{name} will see its {count} events through {category}}}'**
  String shareDeleteImpactStarts(String name, int count, String category);

  /// Sharing page row that clears every share and keeps the pair; also the confirm button of its dialog
  ///
  /// In en, this message translates to:
  /// **'Stop sharing everything'**
  String get shareStopAll;

  /// Description of the 'Stop sharing everything' row
  ///
  /// In en, this message translates to:
  /// **'You stay paired'**
  String get shareStopAllDesc;

  /// Title of the confirmation before every share is cleared
  ///
  /// In en, this message translates to:
  /// **'Stop sharing everything with {name}?'**
  String shareStopAllConfirmTitle(String name);

  /// Body of the confirmation before every share is cleared, under shareStopAllConfirmTitle
  ///
  /// In en, this message translates to:
  /// **'Your categories and events leave their phone. What {name} shares with you stays.'**
  String shareStopAllConfirm(String name);

  /// Description of the Unpair row on the Sharing page
  ///
  /// In en, this message translates to:
  /// **'Ends sharing both ways'**
  String get shareUnpairDesc;

  /// Sentence added to the unpair confirmation
  ///
  /// In en, this message translates to:
  /// **'If you pair again, you choose again what to share.'**
  String get pairingRepairHint;

  /// Sentence added to the stop-syncing confirmation when this database shares something with the partner
  ///
  /// In en, this message translates to:
  /// **'{name} keeps what you share as it is now, without later changes. To take it back, stop sharing first.'**
  String syncStopSharingLine(String name);

  /// Description of the Pairing row while paired and nothing is shared
  ///
  /// In en, this message translates to:
  /// **'Nothing is shared yet'**
  String get shareNothingYet;

  /// Part of the Pairing row's summary of what is shared, joined with a comma to the event count. Keep the no-break space so a number never strands from its noun
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 category} other{{count} categories}}'**
  String shareSummaryCategories(int count);

  /// Part of the Pairing row's summary and the description of the 'Single events' entry: events shared one by one. Keep the no-break space
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event} other{{count} events}}'**
  String shareSummaryEvents(int count);

  /// Section label over the share switch in the category editor
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get shareSectionLabel;

  /// Caption fragment on a category row that is shared with the partner, beside 'Built in' and 'Alerts on'
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get categoryCaptionShared;

  /// Tooltip of the button that stops sharing one event in the list of singly shared events
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get shareStopSharingTooltip;

  /// The one line of the 'Single events' list when no event is shared one by one
  ///
  /// In en, this message translates to:
  /// **'Share an event from its editor.'**
  String get shareEventsEmpty;

  /// Section label on the Sharing page over the look settings
  ///
  /// In en, this message translates to:
  /// **'How shared things look'**
  String get shareLookSection;

  /// Label of the choice of how the partner's events are drawn
  ///
  /// In en, this message translates to:
  /// **'Events shared with you'**
  String get shareEventLook;

  /// Look choice: the partner's events are drawn hollow, as an outline
  ///
  /// In en, this message translates to:
  /// **'Outlined'**
  String get shareLookOutlined;

  /// Look choice: the partner's events carry the partner's profile picture
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get shareLookAvatar;

  /// Look choice: the partner's events are drawn like this person's own
  ///
  /// In en, this message translates to:
  /// **'Like mine'**
  String get shareLookPlain;

  /// Switch on the Sharing page: show a sign on what this person shares
  ///
  /// In en, this message translates to:
  /// **'Mark what you share'**
  String get shareMarkMine;

  /// Description of the 'Mark what you share' switch
  ///
  /// In en, this message translates to:
  /// **'A sign on the categories and events you share'**
  String get shareMarkMineDesc;

  /// Section label on the Sharing page over the alert setting for shared events
  ///
  /// In en, this message translates to:
  /// **'Alerts'**
  String get shareAlertsSection;

  /// Sharing page entry: whether the partner's events may alert on this phone
  ///
  /// In en, this message translates to:
  /// **'Alerts for shared events'**
  String get shareAlerts;

  /// Alert setting for shared events: nothing rings
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get shareAlertsOff;

  /// Second line of the 'Off' choice
  ///
  /// In en, this message translates to:
  /// **'Nothing shared with you rings'**
  String get shareAlertsOffDesc;

  /// Alert setting for shared events: only the alerts this person added to one event
  ///
  /// In en, this message translates to:
  /// **'Only alerts I add'**
  String get shareAlertsOwn;

  /// Second line of the 'Only alerts I add' choice
  ///
  /// In en, this message translates to:
  /// **'On one event, from its sheet'**
  String get shareAlertsOwnDesc;

  /// Alert setting for shared events: they also follow this person's category alerts
  ///
  /// In en, this message translates to:
  /// **'Category alerts too'**
  String get shareAlertsCategory;

  /// Second line of the 'Category alerts too' choice
  ///
  /// In en, this message translates to:
  /// **'Shared events follow your category alerts, alarms included'**
  String get shareAlertsCategoryDesc;

  /// Caption under the dimmed alerts group of the partner's event sheet while the setting is Off
  ///
  /// In en, this message translates to:
  /// **'Alerts for shared events are off'**
  String get shareAlertsOffCaption;

  /// Caption under the dimmed alerts group of a partner's category sheet unless the setting is 'Category alerts too'
  ///
  /// In en, this message translates to:
  /// **'Category alerts are off for shared events'**
  String get shareCategoryAlertsOffCaption;

  /// Title of a notification or alarm for one of the partner's events
  ///
  /// In en, this message translates to:
  /// **'{title} · From {name}'**
  String shareAlertNoticeTitle(String title, String name);

  /// Section label in the partner's event sheet over this person's own alerts on that event
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get sharedEventYours;

  /// Action in the partner's event sheet: makes an event of this person's own from it
  ///
  /// In en, this message translates to:
  /// **'Copy to my calendar'**
  String get sharedEventCopy;

  /// Snackbar after copying the partner's event
  ///
  /// In en, this message translates to:
  /// **'Copied. Later changes by {name} do not reach your copy.'**
  String sharedEventCopied(String name);

  /// Caption at the end of the partner's event sheet
  ///
  /// In en, this message translates to:
  /// **'Only {name} can change this event. Your alerts follow what this phone last received.'**
  String sharedEventCaption(String name);

  /// Snackbar when one new thing from the partner arrived, with a View action
  ///
  /// In en, this message translates to:
  /// **'{name} shares {what} with you'**
  String shareNewFromPartner(String name, String what);

  /// Snackbar when several categories from the partner arrived in one read
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} shares 1 category with you} other{{name} shares {count} categories with you}}'**
  String shareNewManyFromPartner(String name, int count);

  /// Snackbar action that opens the Sharing page
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get shareView;

  /// Snackbar when the partner's event that is open leaves
  ///
  /// In en, this message translates to:
  /// **'{name} no longer shares this event'**
  String shareGoneEvent(String name);

  /// Snackbar when something of the partner's left and took an armed alert of this person's with it
  ///
  /// In en, this message translates to:
  /// **'{name} no longer shares {what}. Your alert is off.'**
  String shareGoneWithAlert(String name, String what);

  /// Snackbar when several of the partner's events left in one read and took armed alerts of this person's with them
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} no longer shares 1 event. Your alert for it is off.} other{{name} no longer shares {count} events. Your alerts for them are off.}}'**
  String shareGoneWithAlerts(int count, String name);

  /// Screen-reader words for a row of something this person shares
  ///
  /// In en, this message translates to:
  /// **'Shared with {name}'**
  String shareMarkMineLabel(String name);

  /// Screen-reader words for a row of something the partner shares, read first in every look
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String shareMarkPartnerLabel(String name);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'ro'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'ro':
      return AppLocalizationsRo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
