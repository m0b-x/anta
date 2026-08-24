import 'package:intl/intl.dart';

import '../services/folder_search_service.dart' show normalizeForSearch;

class EventSearchDate {
  final int? year;
  final int? month;
  final int? day;

  const EventSearchDate({this.year, this.month, this.day});

  bool matches(DateTime value) {
    if (year != null && value.year != year) return false;
    if (month != null && value.month != month) return false;
    if (day != null && value.day != day) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is EventSearchDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'EventSearchDate(y: $year, m: $month, d: $day)';
}

class EventSearchClause {
  final int termMask;
  final EventSearchDate? date;

  const EventSearchClause({required this.termMask, this.date});
}

class EventSearchQuery {
  static const EventSearchQuery empty = EventSearchQuery._(
    terms: <String>[],
    clauses: <EventSearchClause>[],
    hasDateClauses: false,
  );

  static const int maxTerms = 30;

  final List<String> terms;
  final List<EventSearchClause> clauses;
  final bool hasDateClauses;

  const EventSearchQuery._({
    required this.terms,
    required this.clauses,
    required this.hasDateClauses,
  });

  bool get isEmpty => clauses.isEmpty;
  bool get isNotEmpty => clauses.isNotEmpty;

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
  static final RegExp _dayNumber = RegExp(r'^(\d{1,2})\.?$');
  static final RegExp _nonWord = RegExp(r'[^a-z0-9]');

  static const List<int> _maxDayInMonth = [
    31,
    29,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];

  static final Map<String, List<List<String>>> _monthNameCache = {};

  static EventSearchQuery parse(String raw, {String? localeName}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return empty;

    final tokens = <String>[];
    for (final piece in trimmed.split(_whitespace)) {
      final folded = normalizeForSearch(piece);
      if (folded.isEmpty) continue;
      tokens.add(folded);
    }
    if (tokens.isEmpty) return empty;

    final months = _monthNamesFor(localeName);
    final terms = <String>[];
    final clauses = <EventSearchClause>[];
    var hasDates = false;

    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;

      if (next != null) {
        final pair = _parsePair(token, next, months);
        if (pair != null) {
          clauses.add(
            EventSearchClause(
              termMask: _termBit(terms, token) | _termBit(terms, next),
              date: pair,
            ),
          );
          hasDates = true;
          i += 2;
          continue;
        }
      }

      final single = _parseSingle(token, months);
      clauses.add(
        EventSearchClause(termMask: _termBit(terms, token), date: single),
      );
      if (single != null) hasDates = true;
      i += 1;
    }

    return EventSearchQuery._(
      terms: List.unmodifiable(terms),
      clauses: List.unmodifiable(clauses),
      hasDateClauses: hasDates,
    );
  }

  int maskOf(String? text) {
    if (text == null || text.isEmpty || terms.isEmpty) return 0;
    final folded = normalizeForSearch(text);
    var mask = 0;
    for (var i = 0; i < terms.length; i++) {
      if (folded.contains(terms[i])) mask |= 1 << i;
    }
    return mask;
  }

  bool couldSatisfy(int mask) {
    for (final clause in clauses) {
      if (clause.date != null) continue;
      if ((mask & clause.termMask) != clause.termMask) return false;
    }
    return true;
  }

  bool satisfied(int mask, DateTime day) {
    for (final clause in clauses) {
      if ((mask & clause.termMask) == clause.termMask) continue;
      final date = clause.date;
      if (date != null && date.matches(day)) continue;
      return false;
    }
    return true;
  }

  bool matchesText(String? text, DateTime day) => satisfied(maskOf(text), day);

  static int _termBit(List<String> terms, String token) {
    final existing = terms.indexOf(token);
    if (existing >= 0) return 1 << existing;
    if (terms.length >= maxTerms) return 0;
    terms.add(token);
    return 1 << (terms.length - 1);
  }

  static EventSearchDate? _parseSingle(
    String token,
    List<List<String>> months,
  ) {
    final iso = _isoDate.firstMatch(token);
    if (iso != null) {
      final year = int.parse(iso.group(1)!);
      final month = int.parse(iso.group(2)!);
      final day = int.parse(iso.group(3)!);
      if (!_isRealDate(year, month, day)) return null;
      return EventSearchDate(year: year, month: month, day: day);
    }
    final month = _monthOf(token, months);
    if (month != null) return EventSearchDate(month: month);
    return null;
  }

  static EventSearchDate? _parsePair(
    String first,
    String second,
    List<List<String>> months,
  ) {
    final leadingMonth = _monthOf(first, months);
    if (leadingMonth != null) {
      final day = _dayOf(second);
      if (day != null && day <= _maxDayInMonth[leadingMonth - 1]) {
        return EventSearchDate(month: leadingMonth, day: day);
      }
      return null;
    }
    final leadingDay = _dayOf(first);
    if (leadingDay == null) return null;
    final trailingMonth = _monthOf(second, months);
    if (trailingMonth == null) return null;
    if (leadingDay > _maxDayInMonth[trailingMonth - 1]) return null;
    return EventSearchDate(month: trailingMonth, day: leadingDay);
  }

  static int? _dayOf(String token) {
    final match = _dayNumber.firstMatch(token);
    if (match == null) return null;
    final value = int.parse(match.group(1)!);
    if (value < 1 || value > 31) return null;
    return value;
  }

  static int? _monthOf(String token, List<List<String>> months) {
    if (token.length < 3) return null;
    int? found;
    for (var m = 0; m < 12; m++) {
      for (final name in months[m]) {
        if (!name.startsWith(token)) continue;
        if (found != null && found != m + 1) return null;
        found = m + 1;
        break;
      }
    }
    return found;
  }

  static bool _isRealDate(int year, int month, int day) {
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    final probe = DateTime.utc(year, month, day);
    return probe.year == year && probe.month == month && probe.day == day;
  }

  static List<List<String>> _monthNamesFor(String? localeName) {
    final key = localeName ?? '';
    return _monthNameCache[key] ??= _buildMonthNames(key);
  }

  static List<List<String>> _buildMonthNames(String key) {
    final byMonth = List.generate(12, (_) => <String>[], growable: false);
    try {
      final format = key.isEmpty ? DateFormat.MMMM() : DateFormat.MMMM(key);
      final symbols = format.dateSymbols;
      final sources = <List<String>>[
        symbols.MONTHS,
        symbols.STANDALONEMONTHS,
        symbols.SHORTMONTHS,
        symbols.STANDALONESHORTMONTHS,
      ];
      for (final source in sources) {
        for (var m = 0; m < 12 && m < source.length; m++) {
          final name = _foldName(source[m]);
          if (name.length < 3) continue;
          if (byMonth[m].contains(name)) continue;
          byMonth[m].add(name);
        }
      }
    } catch (_) {
      return byMonth;
    }
    return byMonth;
  }

  static String _foldName(String raw) =>
      normalizeForSearch(raw).replaceAll(_nonWord, '');
}
