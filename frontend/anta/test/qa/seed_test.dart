import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/seed.dart';

void main() {
  late Directory root;
  late QaPaths paths;
  final now = DateTime(2026, 9, 26, 10);

  setUp(() {
    root = Directory.systemTemp.createTempSync('anta_qa_seed');
    paths = QaPaths(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  File fixture(String body) =>
      File('${root.path}/f.json')..writeAsStringSync(body);

  test('resolves placeholders into a copy under build/qa', () {
    final source = fixture(
      '{"calendarEvents":[{"startDateMs":"{{today+1}}"}],"settings":{}}',
    );
    final prepared = prepareSeed(paths, source.path, now: now);
    expect(prepared.path, paths.seedResolved);
    expect(prepared.placeholders, 1);
    final out = jsonDecode(File(prepared.path).readAsStringSync()) as Map;
    final events = out['calendarEvents'] as List;
    expect(
      (events.first as Map)['startDateMs'],
      DateTime.utc(2026, 9, 27).millisecondsSinceEpoch,
    );
    expect(source.readAsStringSync(), contains('{{today+1}}'));
    expect(prepared.describe(), ' (1 placeholder resolved)');
  });

  test('folds --setting overrides into the settings map', () {
    final source = fixture('{"settings":{"money_ledger_enabled":"true"}}');
    final prepared = prepareSeed(
      paths,
      source.path,
      settings: const ['locale=de', 'theme_mode=dark'],
      now: now,
    );
    final out = jsonDecode(File(prepared.path).readAsStringSync()) as Map;
    expect(out['settings'], {
      'money_ledger_enabled': 'true',
      'locale': 'de',
      'theme_mode': 'dark',
    });
    expect(prepared.describe(), ' (settings: locale=de, theme_mode=dark)');
  });

  test('a seed without a settings map gains one', () {
    final source = fixture('{"folders":[]}');
    final prepared = prepareSeed(paths, source.path, settings: const ['locale=ro']);
    final out = jsonDecode(File(prepared.path).readAsStringSync()) as Map;
    expect(out['settings'], {'locale': 'ro'});
  });

  test('a malformed override or a missing fixture is a usage failure', () {
    final source = fixture('{}');
    expect(
      () => prepareSeed(paths, source.path, settings: const ['locale']),
      throwsA(isA<UsageFailure>()),
    );
    expect(
      () => prepareSeed(paths, '${root.path}/missing.json'),
      throwsA(isA<UsageFailure>()),
    );
  });

  test('parseSettingOverride splits on the first equals sign only', () {
    expect(parseSettingOverride('a=b=c'), ('a', 'b=c'));
    expect(() => parseSettingOverride('=x'), throwsA(isA<UsageFailure>()));
    expect(() => parseSettingOverride('x='), throwsA(isA<UsageFailure>()));
  });
}
