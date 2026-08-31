import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/search_constants.dart';
import 'package:anta/services/folder_search_service.dart';

/// Reference oracle: the old per-code-unit-as-`String` algorithm that
/// [removeDiacritics] replaced. `removeDiacritics` now iterates `codeUnits`
/// and only consults the map above U+00BF for speed, but it must still fold
/// every string exactly the way this does — see the doc comment on
/// [removeDiacritics] for why that equivalence holds.
String _oldRemoveDiacritics(String text) {
  final buffer = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    buffer.write(SearchConstants.diacriticsMap[char] ?? char);
  }
  return buffer.toString();
}

void main() {
  group('removeDiacritics equivalence with the old algorithm', () {
    test('every single key in SearchConstants.diacriticsMap', () {
      for (final key in SearchConstants.diacriticsMap.keys) {
        expect(
          removeDiacritics(key),
          _oldRemoveDiacritics(key),
          reason: 'mismatch for key U+${key.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('the whole key set concatenated into one string', () {
      final allKeys = SearchConstants.diacriticsMap.keys.join();
      expect(removeDiacritics(allKeys), _oldRemoveDiacritics(allKeys));
    });

    test('the key set interleaved with ASCII', () {
      final buffer = StringBuffer();
      var i = 0;
      for (final key in SearchConstants.diacriticsMap.keys) {
        buffer.write('ascii${i++}_');
        buffer.write(key);
        buffer.write('_');
      }
      final interleaved = buffer.toString();
      expect(removeDiacritics(interleaved), _oldRemoveDiacritics(interleaved));
    });
  });

  group('astral-plane safety', () {
    test('emoji round-trips identically to the old algorithm', () {
      const text = 'Café \u{1F600} déjà vu \u{1F4A9}';
      expect(removeDiacritics(text), _oldRemoveDiacritics(text));
    });

    test('surrogate-pair-heavy text mixed with diacritics', () {
      const text =
          '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} Ïñtérnâtiônàlizætiøn \u{1F30D}';
      expect(removeDiacritics(text), _oldRemoveDiacritics(text));
    });

    test('lone emoji alone is unchanged', () {
      const text = '\u{1F600}';
      expect(removeDiacritics(text), text);
      expect(removeDiacritics(text), _oldRemoveDiacritics(text));
    });
  });

  group('exact expected output', () {
    test('empty string', () {
      expect(removeDiacritics(''), '');
    });

    test('pure ASCII string is unchanged', () {
      const text = 'The quick brown fox jumps over the lazy dog 123!?';
      expect(removeDiacritics(text), text);
    });

    test('realistic Romanian sentence', () {
      const text = 'Sărbătoare în Țara Românească';
      expect(removeDiacritics(text), 'Sarbatoare in Tara Romaneasca');
    });
  });

  group('multi-char values', () {
    test('Æ folds to AE', () {
      expect(removeDiacritics('Æ'), 'AE');
    });

    test('ß folds to ss', () {
      expect(removeDiacritics('ß'), 'ss');
    });

    test('Þ folds to TH', () {
      expect(removeDiacritics('Þ'), 'TH');
    });
  });
}
