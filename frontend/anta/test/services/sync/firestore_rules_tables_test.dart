import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/sync/sync_tables.dart';

/// Pins the rules' allow-list of table names to the binding registry.
/// `firestore.rules` names its 17 collections literally, and the rules are
/// the one surface of this app with no local safety net and no deployment of
/// their own: a binding added without the matching rules line is invisible
/// until the day they are deployed, and then every push of that table is
/// denied, the engine's diagnosis reads a readable space at an equal schema,
/// the bisect parks the rows and raises `noAccess` with `recheckable: false`
/// — a pause until relaunch. Reading a file is all this costs, so it runs in
/// the default gate while the emulator suite (`test/firestore`) does not.
void main() {
  test('the rules allow exactly the tables the bindings push', () {
    final rules = File('firestore.rules').readAsStringSync();
    final list = RegExp(r'table in \[(.*?)\]', dotAll: true).firstMatch(rules);

    expect(
      list,
      isNotNull,
      reason:
          'no `table in [...]` list in firestore.rules — the rules'
          ' changed shape and this test can no longer read them',
    );
    final allowed = RegExp(
      "'([^']*)'",
    ).allMatches(list!.group(1)!).map((m) => m.group(1)!).toSet();

    expect(allowed, syncTableBindings.map((b) => b.table).toSet());
  });
}
