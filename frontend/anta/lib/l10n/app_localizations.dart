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

  /// Drawer item and page title for the calendar feature
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

  /// Subtitle hint under the All day toggle in the event editor
  ///
  /// In en, this message translates to:
  /// **'Event spans the entire day'**
  String get eventAllDayHint;

  /// Section label for time-of-day controls in the event editor
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get eventTimeSection;

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

  /// Hint shown beneath the end-time picker when no end is set
  ///
  /// In en, this message translates to:
  /// **'Tap to add an end time'**
  String get eventEndTimeHint;

  /// Hint shown when the chosen end time crosses midnight
  ///
  /// In en, this message translates to:
  /// **'Ends next day'**
  String get eventCrossesMidnight;

  /// Calendar format option for month view
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get calendarFormatMonth;

  /// Calendar format option for two-week view
  ///
  /// In en, this message translates to:
  /// **'2 weeks'**
  String get calendarFormatTwoWeeks;

  /// Calendar format option for week view
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get calendarFormatWeek;

  /// Title of the calendar filter sheet
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get calendarFiltersTitle;

  /// Section label for choosing the calendar view range (month/2 weeks/week)
  ///
  /// In en, this message translates to:
  /// **'View range'**
  String get calendarViewRange;

  /// Section label for the visible event categories filter
  ///
  /// In en, this message translates to:
  /// **'Event categories'**
  String get calendarEventCategories;

  /// Button to select every event category
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get calendarSelectAll;

  /// Button to deselect every event category
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get calendarClearAll;

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

  /// Label for the category color picker
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get categoryColor;

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

  /// Confirmation message when deleting a custom event category
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Events using it will move to Other.'**
  String deleteCategoryConfirm(String name);

  /// Snackbar shown after a custom category is deleted
  ///
  /// In en, this message translates to:
  /// **'Category deleted'**
  String get categoryDeleted;

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

  /// Subtitle explaining per-occurrence event descriptions
  ///
  /// In en, this message translates to:
  /// **'This event keeps its own description for each day. The event\'s description becomes the template every day starts from.'**
  String get eventPerOccurrenceDescriptionsDesc;

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

  /// Section label in the calendar event editor for selecting the category
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get eventType;

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

  /// Shown when no explicit icon has been chosen for an event
  ///
  /// In en, this message translates to:
  /// **'Default for category'**
  String get iconDefault;

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

  /// Subtitle on the category picker tile in the event editor
  ///
  /// In en, this message translates to:
  /// **'Change category'**
  String get pickCategory;

  /// Reset to default button text
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get resetToDefault;

  /// Section label in the event editor for the event date / recurrence anchor
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get eventDate;

  /// Subtitle shown under the date row for recurring events
  ///
  /// In en, this message translates to:
  /// **'Starts on this date'**
  String get startsOn;

  /// Section label for the one-time / recurring toggle
  ///
  /// In en, this message translates to:
  /// **'Repeats'**
  String get repeatMode;

  /// Segmented control option: event occurs only once
  ///
  /// In en, this message translates to:
  /// **'One time'**
  String get repeatOnce;

  /// Segmented control option: event recurs on a schedule
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get repeatRecurring;

  /// Section label for the recurrence frequency chips
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequency;

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

  /// Tooltip for the button that decreases the recurrence interval
  ///
  /// In en, this message translates to:
  /// **'Less frequent'**
  String get recurrenceIntervalDecrement;

  /// Tooltip for the button that increases the recurrence interval
  ///
  /// In en, this message translates to:
  /// **'More frequent'**
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

  /// Section label for the per-weekday chips in the editor
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get weekdays;

  /// Validation hint shown when the user clears all weekday selections
  ///
  /// In en, this message translates to:
  /// **'Pick at least one weekday'**
  String get weeklyDaysHint;

  /// Section label for the optional recurrence end-date picker
  ///
  /// In en, this message translates to:
  /// **'Ends on'**
  String get eventUntilLabel;

  /// Placeholder shown when no recurrence end date is set
  ///
  /// In en, this message translates to:
  /// **'Never ends'**
  String get eventUntilNone;

  /// Subtitle hint for the recurrence end-date picker when empty
  ///
  /// In en, this message translates to:
  /// **'Tap to set an end date'**
  String get eventUntilHint;

  /// Section label for the recurrence scope chips (forward-only vs retroactive)
  ///
  /// In en, this message translates to:
  /// **'Occurrences'**
  String get recurrenceScopeLabel;

  /// Recurrence scope option: the rule only fires on or after the start date
  ///
  /// In en, this message translates to:
  /// **'From this date on'**
  String get recurrenceScopeFromStart;

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

  /// Explanation under the recurrence scope chips when the retroactive option is picked
  ///
  /// In en, this message translates to:
  /// **'Also shows on matching days before the start date'**
  String get recurrenceScopeHint;

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

  /// Explanation under the track-presence switch
  ///
  /// In en, this message translates to:
  /// **'Mark the days you skip.'**
  String get eventTrackPresenceDesc;

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

  /// Explanation under the count-occurrences switch; the origin chips below it show concrete examples
  ///
  /// In en, this message translates to:
  /// **'Each occurrence gets a label counting from the start date. Count from 0 for ages and anniversaries.'**
  String get eventCountOccurrencesHint;

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

  /// Tooltip for switching the month/year picker to typed input
  ///
  /// In en, this message translates to:
  /// **'Type it instead'**
  String get monthYearPickerManualEntry;

  /// Tooltip for switching the month/year picker back to the scroll wheels
  ///
  /// In en, this message translates to:
  /// **'Pick from the wheels'**
  String get monthYearPickerWheelEntry;

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

  /// Row opening the per-tradition fasting appearance editor
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get fastingAppearanceTitle;

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
  /// **'Default colour'**
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

  /// Hint under the fasting row placement chips
  ///
  /// In en, this message translates to:
  /// **'Decides where the row sits among events, holidays and the weekend'**
  String get fastingPlacementHint;

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

  /// Settings row opening the personal fasting schedule sheet
  ///
  /// In en, this message translates to:
  /// **'My practice'**
  String get fastingScheduleTitle;

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

  /// Schedule summary fragment: how many months are kept
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String fastingMonthsCount(int count);

  /// Label above the month scope chips
  ///
  /// In en, this message translates to:
  /// **'Months apply to'**
  String get fastingMonthScopeTitle;

  /// Month scope option: the month set gates only the weekly fast
  ///
  /// In en, this message translates to:
  /// **'Weekly fast only'**
  String get fastingMonthScopeWeekly;

  /// Month scope option: the month set gates every fast
  ///
  /// In en, this message translates to:
  /// **'All fasts'**
  String get fastingMonthScopeAll;

  /// Hint under the month scope chips
  ///
  /// In en, this message translates to:
  /// **'A month you turn off is never marked'**
  String get fastingMonthScopeHint;

  /// Label above the skipped fasting dates list
  ///
  /// In en, this message translates to:
  /// **'Days off'**
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

  /// Event editor section header: what the event is
  ///
  /// In en, this message translates to:
  /// **'What'**
  String get eventSectionWhat;

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

  /// Placeholder shown in the description preview when the field is empty
  ///
  /// In en, this message translates to:
  /// **'Nothing to preview yet'**
  String get eventDescriptionEmpty;

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

  /// Section label listing the upcoming dates a recurring event fires on
  ///
  /// In en, this message translates to:
  /// **'Next occurrences'**
  String get eventDetailsNextOccurrences;

  /// Shown when a recurring event has no occurrence left in the scanned window
  ///
  /// In en, this message translates to:
  /// **'No upcoming occurrences'**
  String get eventDetailsNoOccurrences;

  /// Shown in the detail sheet when the event carries no description
  ///
  /// In en, this message translates to:
  /// **'No notes for this event'**
  String get eventDetailsNoDescription;

  /// Detail sheet row naming the date a recurring series starts, shown when the viewed occurrence is not the first
  ///
  /// In en, this message translates to:
  /// **'Repeats since {date}'**
  String eventDetailsSeriesStart(String date);

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

  /// Subtitle for the tint-icon toggle
  ///
  /// In en, this message translates to:
  /// **'Use the event color for the icon too'**
  String get eventTintIconHint;

  /// Section label for the event priority stepper
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get eventPriority;

  /// Hint shown under the event priority stepper
  ///
  /// In en, this message translates to:
  /// **'Higher priority shows first and keeps its bar when a day is full'**
  String get eventPriorityHint;

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

  /// Section label for the one-time event's date chip list
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get eventDatesLabel;

  /// Hint shown when a one-time event has no additional dates yet
  ///
  /// In en, this message translates to:
  /// **'Add more one-off dates to repeat this event without a recurrence'**
  String get eventDatesHint;

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

  /// Hint text for the optional event description field
  ///
  /// In en, this message translates to:
  /// **'Add notes (focus, technique, intensity…)'**
  String get eventDescriptionHint;

  /// Section label for the optional workout note linked to a calendar event
  ///
  /// In en, this message translates to:
  /// **'Linked note'**
  String get eventLinkedNote;

  /// Picker tile title shown when no note is linked to the event yet
  ///
  /// In en, this message translates to:
  /// **'Link a workout note'**
  String get eventLinkNoteHint;

  /// Shown when the note linked to an event has been deleted
  ///
  /// In en, this message translates to:
  /// **'Linked note no longer exists'**
  String get eventLinkedNoteMissing;

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
  /// **'Delete Folder'**
  String get deleteFolder;

  /// Delete folder confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String deleteFolderConfirm(String name);

  /// Delete folder confirmation message when folder contains notes
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This will also delete {count} note(s).'**
  String deleteFolderWithNotesConfirm(String name, int count);

  /// Rename button text
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Rename folder dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename Folder'**
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

  /// Delete note dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Note'**
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
  /// **'Edit Title'**
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

  /// Markdown shortcuts settings description
  ///
  /// In en, this message translates to:
  /// **'Customize toolbar buttons and actions'**
  String get markdownShortcutsDesc;

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
  /// **'Opens header menu (H1-H6)'**
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
  /// **'Headers'**
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
  /// **'Header 1'**
  String get header1;

  /// Header 2 menu item
  ///
  /// In en, this message translates to:
  /// **'Header 2'**
  String get header2;

  /// Header 3 menu item
  ///
  /// In en, this message translates to:
  /// **'Header 3'**
  String get header3;

  /// Header 4 menu item
  ///
  /// In en, this message translates to:
  /// **'Header 4'**
  String get header4;

  /// Header 5 menu item
  ///
  /// In en, this message translates to:
  /// **'Header 5'**
  String get header5;

  /// Header 6 menu item
  ///
  /// In en, this message translates to:
  /// **'Header 6'**
  String get header6;

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

  /// Settings label
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Accessibility label for drop indicator during drag
  ///
  /// In en, this message translates to:
  /// **'Drop position'**
  String get dropPosition;

  /// Accessibility hint for reorderable buttons
  ///
  /// In en, this message translates to:
  /// **'Long press to reorder'**
  String get longPressToReorder;

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
  /// **'{count} distinct characters, {chunks} chunks'**
  String noteStats(int count, int chunks);

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
  /// **'{count} lines'**
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

  /// Hint to tap the plus button
  ///
  /// In en, this message translates to:
  /// **'Tap + to get started'**
  String get tapPlusToCreate;

  /// Character count display
  ///
  /// In en, this message translates to:
  /// **'{current}/{max} characters'**
  String charactersCount(int current, int max);

  /// Database settings menu item
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get databaseSettings;

  /// Database settings description
  ///
  /// In en, this message translates to:
  /// **'Manage database location and storage'**
  String get databaseSettingsDesc;

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

  /// Optimization complete message
  ///
  /// In en, this message translates to:
  /// **'Database optimized successfully'**
  String get optimizationComplete;

  /// Saved suffix for size reduction
  ///
  /// In en, this message translates to:
  /// **'saved'**
  String get saved;

  /// Message when no space was reclaimed
  ///
  /// In en, this message translates to:
  /// **'database already optimized'**
  String get alreadyOptimized;

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

  /// Hint that restart may be needed
  ///
  /// In en, this message translates to:
  /// **'Restart may be required for full effect'**
  String get restartRequired;

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
  /// **'Rename Note'**
  String get renameNote;

  /// Hint text for rename input
  ///
  /// In en, this message translates to:
  /// **'Enter new name'**
  String get enterNewName;

  /// Reorder mode toggle tooltip
  ///
  /// In en, this message translates to:
  /// **'Reorder Mode'**
  String get reorderMode;

  /// Hint for drag and drop reordering
  ///
  /// In en, this message translates to:
  /// **'Drag items to reorder'**
  String get dragToReorder;

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

  /// Controls settings menu item
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get controlsSettings;

  /// Controls settings description
  ///
  /// In en, this message translates to:
  /// **'Gestures, haptics and interactions'**
  String get controlsSettingsDesc;

  /// Gestures section title
  ///
  /// In en, this message translates to:
  /// **'Gestures'**
  String get gesturesSection;

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
  /// **'Feedback'**
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

  /// Auto-save description
  ///
  /// In en, this message translates to:
  /// **'Automatically save notes while editing'**
  String get autoSaveDesc;

  /// Auto-save interval setting
  ///
  /// In en, this message translates to:
  /// **'Auto-save interval'**
  String get autoSaveInterval;

  /// Auto-save interval description
  ///
  /// In en, this message translates to:
  /// **'Save every {seconds} seconds'**
  String autoSaveIntervalDesc(int seconds);

  /// Display section title
  ///
  /// In en, this message translates to:
  /// **'Display'**
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

  /// Share note option
  ///
  /// In en, this message translates to:
  /// **'Share Note'**
  String get shareNote;

  /// Share folder option (exports folder tree as zip archive)
  ///
  /// In en, this message translates to:
  /// **'Share Folder'**
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
  /// **'Imported {folders} folders, {notes} notes'**
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

  /// Placeholder for note search field
  ///
  /// In en, this message translates to:
  /// **'Find in note'**
  String get findInNote;

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
  /// **'Dark mode, colors and display'**
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
  /// **'Automatically break long lines when pasting text. May slightly affect search positioning accuracy in preview mode.'**
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

  /// Preview settings section title
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewSection;

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

  /// Preview performance settings section title
  ///
  /// In en, this message translates to:
  /// **'Preview Performance'**
  String get previewPerformanceSection;

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

  /// Calendar settings section title
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarSection;

  /// Title of the calendar settings page and tooltip for its entry point
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarSettings;

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

  /// Calendar appearance settings section title
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get calendarAppearanceSection;

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

  /// Placeholder example for the template name field
  ///
  /// In en, this message translates to:
  /// **'Push day'**
  String get templateNameHint;

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

  /// Label for the first-day-of-week dropdown
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
  /// **'Developer Options'**
  String get developerOptions;

  /// Description for developer options in drawer
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

  /// Option to show line numbers in preview
  ///
  /// In en, this message translates to:
  /// **'Preview Line Numbers'**
  String get showPreviewLineNumbers;

  /// Description for show preview line numbers option
  ///
  /// In en, this message translates to:
  /// **'Show source line numbers in preview mode'**
  String get showPreviewLineNumbersDesc;

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

  /// Drawer menu subtitle for counter management
  ///
  /// In en, this message translates to:
  /// **'Create and manage auto-increment counters'**
  String get counterSettingsDesc;

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
  /// **'Move to Folder'**
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
  /// **'Delete {count} selected items? This cannot be undone.'**
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

  /// Look-ahead period preset chip in the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {1 day} other {{count} days}}'**
  String upcomingPeriodDays(int count);

  /// Chip opening a custom date range picker in the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get upcomingPeriodCustom;

  /// Label of the priority filter in the upcoming agenda
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get upcomingPriority;

  /// Priority filter chip that clears the selection and keeps events of every priority
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get upcomingPriorityAny;

  /// Empty state title of the upcoming events sheet
  ///
  /// In en, this message translates to:
  /// **'Nothing coming up'**
  String get upcomingNoEvents;

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

  /// Agenda filter chip that lists public holidays alongside events
  ///
  /// In en, this message translates to:
  /// **'Holidays'**
  String get upcomingShowHolidays;

  /// Tooltip of the button expanding the agenda's period and priority filters
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

  /// Calendar overflow menu action exporting events as iCalendar
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
  /// **'Sharing'**
  String get sharingSettings;

  /// Sharing settings description
  ///
  /// In en, this message translates to:
  /// **'Sign in to share with someone'**
  String get sharingSettingsDesc;

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

  /// Error title when the sign-in flow throws
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get signInFailed;

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
