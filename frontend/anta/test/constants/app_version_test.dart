import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_version.dart';

/// `kAppVersion` is a copy of the pubspec's version (S16 of
/// `docs/settings-rework-roadmap.md`): this keeps the copy honest.
void main() {
  test('kAppVersion is the pubspec version without its build number', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.singleWhere((line) => line.startsWith('version:'));
    final version = line.substring('version:'.length).trim().split('+').first;

    expect(kAppVersion, version);
  });
}
