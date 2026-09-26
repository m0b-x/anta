import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/placeholders.dart';

void main() {
  final now = DateTime(2026, 9, 26, 14, 30);
  final todayUtc = DateTime.utc(2026, 9, 26).millisecondsSinceEpoch;
  const dayMs = 24 * 60 * 60 * 1000;

  test('today resolves to UTC midnight in epoch ms', () {
    expect(resolvePlaceholders('{{today}}', now: now), '$todayUtc');
    expect(resolvePlaceholders('{{today+3}}', now: now), '${todayUtc + 3 * dayMs}');
    expect(resolvePlaceholders('{{today-1}}', now: now), '${todayUtc - dayMs}');
    expect(resolvePlaceholders('{{ today + 2 }}', now: now), '${todayUtc + 2 * dayMs}');
  });

  test('a quoted numeric placeholder sheds its quotes so JSON stays numeric', () {
    expect(
      resolvePlaceholders('{"startDateMs": "{{today+1}}"}', now: now),
      '{"startDateMs": ${todayUtc + dayMs}}',
    );
    expect(
      resolvePlaceholders('"{{weekday}}"', now: now),
      '6',
    );
  });

  test('day keeps its quotes and formats yyyy-MM-dd', () {
    expect(resolvePlaceholders('"{{day}}"', now: now), '"2026-09-26"');
    expect(resolvePlaceholders('id:calendar-day-{{day+5}}', now: now), 'id:calendar-day-2026-10-01');
    expect(resolvePlaceholders('{{day-30}}', now: now), '2026-08-27');
  });

  test('weekday, year, month and dom follow the shifted day', () {
    expect(resolvePlaceholders('{{weekday}}', now: now), '6');
    expect(resolvePlaceholders('{{weekday+2}}', now: now), '1');
    expect(resolvePlaceholders('{{year+120}}', now: now), '2027');
    expect(resolvePlaceholders('{{month+5}}', now: now), '10');
    expect(resolvePlaceholders('{{dom}}', now: now), '26');
  });

  test('longdate is the English label a day cell carries', () {
    expect(resolvePlaceholders('{{longdate}}', now: now), 'Saturday, September 26, 2026');
    expect(resolvePlaceholders('tap "{{longdate+5}}"', now: now), 'tap "Thursday, October 1, 2026"');
  });

  test('now is the instant, not midnight', () {
    expect(resolvePlaceholders('{{now}}', now: now), '${now.millisecondsSinceEpoch}');
  });

  test('text without placeholders is returned untouched, and counts are honest', () {
    const plain = 'tap "Save"';
    expect(identical(resolvePlaceholders(plain, now: now), plain), isTrue);
    expect(countPlaceholders(plain), 0);
    expect(countPlaceholders('{{today}} and "{{day+1}}"'), 2);
  });

  test('a mismatched quote pair keeps what it had', () {
    expect(resolvePlaceholders('"{{today}}', now: now), '"$todayUtc');
  });
}
