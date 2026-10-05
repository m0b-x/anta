/// Date placeholders for seed fixtures and step files.
///
/// A calendar fixture written with fixed dates drifts: a week after it is
/// written its "upcoming" events are in the past, the Today chip points at an
/// empty day and every flow that asserts on the grid breaks. So a fixture and
/// a flow name their dates relative to the day they run, and the tool
/// resolves them on the way to the device — the app never sees a placeholder.
///
/// Forms (`N` is a signed integer, `+0` may be omitted):
///
/// | Placeholder | Value | Example |
/// | --- | --- | --- |
/// | `{{today}}`, `{{today+N}}` | UTC midnight of that day, epoch ms — what `startDateMs` and `dayMs` hold | `1790380800000` |
/// | `{{now}}` | this instant, epoch ms — for `createdAtMs` | `1790412345678` |
/// | `{{day+N}}` | that day as `yyyy-MM-dd` — the tail of a day cell's semantics id | `2026-09-29` |
/// | `{{weekday+N}}` | that day's ISO weekday, 1 = Monday | `2` |
/// | `{{year+N}}` | that day's year | `2026` |
/// | `{{month+N}}` | that day's month, 1–12 | `9` |
/// | `{{dom+N}}` | that day's day of month | `29` |
/// | `{{longdate+N}}` | the label a month-grid day cell carries in English, so a step can tap a day (`tap "{{longdate+1}}"`) | `Sunday, September 27, 2026` |
/// | `{{minute+N}}` | the minute of the day the clock shows **N minutes** from now, 0–1439 — what `startMinute` holds | `873` |
/// | `{{minuteday+N}}` | UTC midnight of the local day that minute falls on, epoch ms — the `startDateMs` / `dayMs` beside it | `1790380800000` |
///
/// A numeric placeholder written as a JSON string — `"startDateMs":
/// "{{today+3}}"` — loses its quotes on resolution, so a fixture stays valid
/// JSON before *and* after. `{{day+N}}` keeps them: it is text.
///
/// **The two minute forms count N in minutes, and are written as a pair.** A
/// fixture that has to make an alert fire cannot name a clock time: it would
/// ring once a day at best. `"startDateMs": "{{minuteday+3}}"` beside
/// `"startMinute": "{{minute+3}}"` puts an event three minutes ahead of the
/// run, and at 23:58 that is 00:01 **tomorrow** — the day half is what keeps
/// the pair right across midnight, which `{{today}}` beside `{{minute+3}}`
/// would not be. The event starts when the clock *turns* to that minute, so
/// between N−1 and N minutes after the fixture is resolved: a fixture that
/// has to ring before anything else happens gives itself that margin.
library;

final RegExp _placeholder = RegExp(
  r'("?)\{\{\s*(today|now|day|weekday|year|month|dom|longdate|minuteday|minute)\s*([+-]\s*\d+)?\s*\}\}("?)',
);

/// The kinds whose value is a number, and therefore shed surrounding quotes.
const Set<String> _numericKinds = {
  'today',
  'now',
  'weekday',
  'year',
  'month',
  'dom',
  'minute',
  'minuteday',
};

/// Replaces every placeholder in [text]; [now] is the reference instant
/// (the local wall clock by default).
String resolvePlaceholders(String text, {DateTime? now}) {
  if (!text.contains('{{')) return text;
  final reference = now ?? DateTime.now();
  return text.replaceAllMapped(_placeholder, (match) {
    final openQuote = match.group(1)!;
    final kind = match.group(2)!;
    final offsetText = match.group(3)?.replaceAll(' ', '') ?? '0';
    final closeQuote = match.group(4)!;
    final offset = int.parse(offsetText);
    final value = _valueOf(kind, offset, reference);
    final quoted = openQuote.isNotEmpty && closeQuote.isNotEmpty;
    if (quoted && _numericKinds.contains(kind)) return value;
    return '$openQuote$value$closeQuote';
  });
}

/// How many placeholders [text] carries — for the `pushed … (N placeholders
/// resolved)` line, so a fixture that resolved nothing is visible.
int countPlaceholders(String text) => _placeholder.allMatches(text).length;

String _valueOf(String kind, int offset, DateTime reference) {
  if (kind == 'now') return reference.millisecondsSinceEpoch.toString();
  if (kind == 'minute' || kind == 'minuteday') {
    final at = _wallClockAhead(reference, offset);
    return kind == 'minute'
        ? (at.hour * Duration.minutesPerHour + at.minute).toString()
        : DateTime.utc(
            at.year,
            at.month,
            at.day,
          ).millisecondsSinceEpoch.toString();
  }
  final day = DateTime.utc(
    reference.year,
    reference.month,
    reference.day,
  ).add(Duration(days: offset));
  switch (kind) {
    case 'today':
      return day.millisecondsSinceEpoch.toString();
    case 'day':
      return '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
    case 'weekday':
      return day.weekday.toString();
    case 'year':
      return day.year.toString();
    case 'month':
      return day.month.toString();
    case 'dom':
      return day.day.toString();
    case 'longdate':
      return '${_weekdayNames[day.weekday - 1]}, '
          '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';
  }
  throw ArgumentError.value(kind, 'kind');
}

/// The wall clock [minutes] after [reference]'s, to the minute.
///
/// Built the way the app builds the instant it will fire at
/// (`AlertPlanner.fireInstant`): the day's `y/m/d` with the whole minute
/// count in the constructor's minute slot, never local midnight plus a
/// `Duration`. Local midnight carries the offset the day *started* with, so
/// on a clock-change day the `Duration` form lands an hour away from the
/// wall clock for every minute after the change — and a fixture that says
/// "in three minutes" would then ring in sixty-three, or not at all. The
/// constructor also carries a count past 1439 into the next day, which is
/// the midnight wrap.
DateTime _wallClockAhead(DateTime reference, int minutes) {
  return DateTime(
    reference.year,
    reference.month,
    reference.day,
    0,
    reference.hour * Duration.minutesPerHour + reference.minute + minutes,
  );
}

const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
