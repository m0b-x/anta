/// The longest custom title a fasting tradition's day-panel row may be
/// given, in characters.
///
/// Its own number rather than the event title's, though both are 120 today:
/// the override is stored under `calendar_fasting_appearance` and read back
/// by the day panel and the grid's bars, which never see an event's title
/// limit — a change to one must not silently cut the other.
const int kFastingTitleMaxLength = 120;

/// The longest description under that row, in characters: the budget the
/// style sheet hands the description sheet.
const int kFastingDescriptionMaxLength = 500;
