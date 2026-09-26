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
///
/// A numeric placeholder written as a JSON string — `"startDateMs":
/// "{{today+3}}"` — loses its quotes on resolution, so a fixture stays valid
/// JSON before *and* after. `{{day+N}}` keeps them: it is text.
library;

final RegExp _placeholder = RegExp(
  r'("?)\{\{\s*(today|now|day|weekday|year|month|dom|longdate)\s*([+-]\s*\d+)?\s*\}\}("?)',
);

/// The kinds whose value is a number, and therefore shed surrounding quotes.
const Set<String> _numericKinds = {
  'today',
  'now',
  'weekday',
  'year',
  'month',
  'dom',
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
