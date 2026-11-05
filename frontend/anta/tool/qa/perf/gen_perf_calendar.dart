/// Emits the seed `qa relaunch --fresh --seed` takes for the Report's cost
/// measurement on a device (docs/calendar-analytics-roadmap.md §13.1 line 4
/// and §14 "The fold's frame on a device"): the twin of
/// test/services/calendar_report_benchmark_test.dart's fixture, so the
/// device sees what the host benchmark folds — five profiled, tagged
/// categories; ten daily routines (five assume absent with every other past
/// day present, five with every third past day missed); ten weekly routines
/// with per-day task lists; fifteen weekly repeats on two weekdays with
/// skipped days; fifteen one-offs carrying a task list. The span is the
/// benchmark's 2026 with the series starting in December 2024, so a This
/// year report folds the previous year too. Days are UTC midnights, the
/// placeholder grammar's own convention.
///
///   dart run tool/qa/perf/gen_perf_calendar.dart > build/qa/perf_calendar.json
library;

import 'dart:convert';
import 'dart:io';

void main() {
  int utc(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch;
  final now = DateTime.now().millisecondsSinceEpoch;
  final seriesStart = utc(2024, 12, 1);
  final days = [for (var i = 0; i < 366; i++) DateTime.utc(2026, 1, 1 + i)];
  final clock = DateTime.now().toUtc();
  final today = DateTime.utc(clock.year, clock.month, clock.day);
  const tasks = '- [x] warm up\n- [ ] sets\n- [ ] stretch';

  // id: (name, colour, icon, kind, area, targetKind, targetValue, targetPeriod)
  final categories =
      <String, (String, int, String, String, String, String, int, String?)>{
        'perf-gym': (
          'Gym #push',
          4284955319,
          'fitness_center',
          'workout',
          'health',
          'atLeast',
          3,
          'week',
        ),
        'perf-cardio': (
          'Cardio #run',
          4283215696,
          'directions_run',
          'routine',
          'health',
          'atLeast',
          2,
          'week',
        ),
        'perf-mobility': (
          'Mobility #stretch',
          4288585374,
          'self_improvement',
          'maintenance',
          'health',
          'maxGap',
          10,
          null,
        ),
        'perf-friends': (
          'Friends #ana',
          4294940672,
          'people',
          'social',
          'people',
          'atLeast',
          2,
          'month',
        ),
        'perf-other': (
          'Errands #trip',
          4286141768,
          'task_alt',
          'task',
          'other',
          'atLeast',
          1,
          'week',
        ),
      };

  Map<String, dynamic> event({
    required String id,
    required String title,
    required String category,
    required int startDateMs,
    String? ruleKind,
    String? rulePayload,
    int? startMinute,
    int? durationMinutes,
    String? description,
    bool tracksPresence = false,
    bool assumeAbsent = false,
    bool perOccurrenceDescriptions = false,
  }) => {
    'id': id,
    'title': title,
    'category': category,
    'startDateMs': startDateMs,
    'allDay': startMinute == null,
    'iconKey': null,
    'ruleKind': ruleKind,
    'rulePayload': rulePayload,
    'endDateMs': null,
    'startMinute': startMinute,
    'durationMinutes': durationMinutes,
    'description': description,
    'noteId': null,
    'colorValue': null,
    'tintIcon': false,
    'priority': 2,
    'retroactive': false,
    'countOccurrences': false,
    'countStyle': 'numbered',
    'tracksPresence': tracksPresence,
    'assumeAbsent': assumeAbsent,
    'assumeAbsentFromMs': null,
    'perOccurrenceDescriptions': perOccurrenceDescriptions,
    'showInDayRail': true,
    'createdAtMs': now,
    'updatedAtMs': now,
  };

  Set<int> repeatDays(int i) => {i % 7 + 1, (i + 3) % 7 + 1};
  String weekly(Set<int> weekdays) =>
      jsonEncode({'weekdays': weekdays.toList()..sort()});

  final events = <Map<String, dynamic>>[
    for (var i = 0; i < 10; i++)
      event(
        id: 'daily$i',
        title: 'Daily $i #push',
        category: 'perf-gym',
        startDateMs: seriesStart,
        ruleKind: 'daily',
        tracksPresence: true,
        assumeAbsent: i < 5,
        startMinute: 6 * 60 + i,
        durationMinutes: 45,
      ),
    for (var i = 0; i < 10; i++)
      event(
        id: 'weekly$i',
        title: 'Weekly $i #run',
        category: 'perf-cardio',
        startDateMs: seriesStart,
        ruleKind: 'weekly',
        rulePayload: weekly({i % 7 + 1}),
        tracksPresence: true,
        perOccurrenceDescriptions: true,
        description: tasks,
        startMinute: 18 * 60,
        durationMinutes: 60,
      ),
    for (var i = 0; i < 15; i++)
      event(
        id: 'repeat$i',
        title: 'Repeat $i #stretch',
        category: 'perf-mobility',
        startDateMs: seriesStart,
        ruleKind: 'weekly',
        rulePayload: weekly(repeatDays(i)),
      ),
    for (var i = 0; i < 15; i++)
      event(
        id: 'once$i',
        title: 'Once $i ${i.isEven ? '#trip' : '#ana'}',
        category: i.isEven ? 'perf-other' : 'perf-friends',
        startDateMs: days[i * 24].millisecondsSinceEpoch,
        description: '- [x] book\n- [ ] pack\n- [ ] go',
      ),
  ];

  final past = days.where((d) => !d.isAfter(today)).toList();
  final absences = <Map<String, dynamic>>[
    for (var i = 0; i < 10; i++)
      for (final (n, d) in past.indexed)
        if (i < 5 ? n.isEven : n % 3 == 0)
          {
            'eventId': 'daily$i',
            'dayMs': d.millisecondsSinceEpoch,
            'status': i < 5 ? 'present' : 'missed',
            'createdAtMs': now,
            'updatedAtMs': now,
          },
  ];
  final skips = <Map<String, dynamic>>[
    for (var i = 0; i < 15; i++)
      for (final (n, d)
          in days.where((d) => repeatDays(i).contains(d.weekday)).indexed)
        if (n % 10 == 0)
          {
            'eventId': 'repeat$i',
            'dayMs': d.millisecondsSinceEpoch,
            'createdAtMs': now,
            'updatedAtMs': now,
          },
  ];
  final occurrences = <Map<String, dynamic>>[
    for (var i = 0; i < 10; i++)
      for (final d in days.where((d) => d.weekday == i % 7 + 1).take(20))
        {
          'eventId': 'weekly$i',
          'dayMs': d.millisecondsSinceEpoch,
          'description': '- [x] warm up\n- [x] sets\n- [ ] stretch',
          'createdAtMs': now,
          'updatedAtMs': now,
        },
  ];

  var order = 100;
  final seed = <String, dynamic>{
    'version': 8,
    'exportedAt': DateTime.now().toIso8601String(),
    'calendarCategories': [
      for (final MapEntry(key: id, value: c) in categories.entries)
        {
          'id': id,
          'name': c.$1,
          'colorValue': c.$2,
          'iconKey': c.$3,
          'sortOrder': order++,
          'isBuiltIn': false,
          'isHidden': false,
          'createdAtMs': now,
          'updatedAtMs': now,
        },
    ],
    'categoryProfiles': [
      for (final MapEntry(key: id, value: c) in categories.entries)
        {
          'id': 'profile-$id',
          'categoryId': id,
          'kind': c.$4,
          'area': c.$5,
          'measure': null,
          'nominalMinutes': 30,
          'markVerb': null,
          'marksNew': null,
          'assumeAbsentNew': null,
          'countsHours': null,
          'targetKind': c.$6,
          'targetValue': c.$7,
          'targetPeriod': c.$8,
          'createdAtMs': now,
          'updatedAtMs': now,
        },
    ],
    'calendarEvents': events,
    'eventAbsences': absences,
    'eventSkips': skips,
    'eventOccurrences': occurrences,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(seed));
}
