import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The calendar guide quotes the app's own labels through placeholders, so a
/// translation that drops one silently stops quoting that label — and still
/// compiles, because gen-l10n takes the placeholder list from the English
/// file alone. This reads the ARBs and holds every German and Romanian guide
/// string to the placeholders its English `@` block declares.
void main() {
  Map<String, dynamic> read(String language) =>
      json.decode(File('lib/l10n/app_$language.arb').readAsStringSync())
          as Map<String, dynamic>;

  final english = read('en');
  final guideKeys = [
    for (final key in english.keys)
      if (key.startsWith('calendarGuide')) key,
  ];

  test('the guide has strings to check', () {
    expect(guideKeys, isNotEmpty);
  });

  for (final language in const ['de', 'ro']) {
    test('every $language guide string keeps the English placeholders', () {
      final translated = read(language);
      for (final key in guideKeys) {
        final value = translated[key];
        expect(value, isA<String>(), reason: '$language lacks $key');
        final meta = english['@$key'] as Map<String, dynamic>?;
        final placeholders =
            (meta?['placeholders'] as Map<String, dynamic>?)?.keys ??
            const <String>[];
        for (final name in placeholders) {
          expect(
            value as String,
            contains('{$name}'),
            reason: '$language $key drops {$name}',
          );
        }
      }
    });
  }
}
