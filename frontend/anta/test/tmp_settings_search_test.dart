import 'package:flutter/services.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:anta/services/folder_search_service.dart'
    show normalizeForSearch;
import 'package:anta/utils/settings_search.dart';

void main() {
  group('FoldedText', () {
    test('agrees with normalizeForSearch on real app strings', () {
      const samples = [
        'Schriftgröße verkleinern',
        'Ausgewählten Text umschließen',
        'Culori pentru text și evidențieri',
        'Șterge căutarea și filtrele pentru a reordona',
        'Auto-save interval',
        'Große Fastenzeit',
        'Bußtag',
        '',
      ];
      for (final s in samples) {
        final folded = FoldedText.of(s);
        expect(folded.value, normalizeForSearch(s), reason: s);
        expect(folded.sourceIndex.length, folded.value.length, reason: s);
      }
    });

    test('maps spans back across a multi-character fold', () {
      // 'ß' folds to 'ss', so folded indices drift right of source indices.
      const source = 'umschließen';
      final folded = FoldedText.of(source);
      expect(folded.value, 'umschliessen');

      final at = folded.value.indexOf('schliessen');
      final range = folded.toSourceRange(at, at + 'schliessen'.length);

      expect(source.substring(range.start, range.end), 'schließen');
    });

    test(
      'a span landing inside a multi-unit fold covers the whole source char',
      () {
        const source = 'Fußzeile';
        final folded = FoldedText.of(source);
        expect(folded.value, 'fusszeile');

        // Match only the first 's' of the 'ss' pair.
        final range = folded.toSourceRange(2, 3);
        expect(source.substring(range.start, range.end), 'ß');
      },
    );
  });

  group('matchSettingsEntry', () {
    test('folds diacritics — the ro/de bug this exists to fix', () {
      expect(
        matchSettingsEntry(
          SettingsQuery.parse('evidentieri'),
          title: 'Culori pentru text și evidențieri',
        ),
        isNotNull,
      );
      expect(
        matchSettingsEntry(
          SettingsQuery.parse('schriftgrosse'),
          title: 'Schriftgröße verkleinern',
        ),
        isNotNull,
      );
      expect(
        matchSettingsEntry(SettingsQuery.parse('sterge'), title: 'Șterge tot'),
        isNotNull,
      );
    });

    test('multi-token AND with prefixes', () {
      final match = matchSettingsEntry(
        SettingsQuery.parse('aut sav'),
        title: 'Auto-save interval',
        description: 'How often the note is written to disk',
      );
      expect(match, isNotNull);

      expect(
        matchSettingsEntry(
          SettingsQuery.parse('aut zzz'),
          title: 'Auto-save interval',
        ),
        isNull,
      );
    });

    test('matches description and keywords, spans only from rendered text', () {
      final viaDescription = matchSettingsEntry(
        SettingsQuery.parse('disk'),
        title: 'Auto-save',
        description: 'Writes the note to disk',
      );
      expect(viaDescription, isNotNull);
      expect(viaDescription!.titleSpans, isEmpty);
      expect(viaDescription.descriptionSpans, isNotEmpty);

      final viaKeyword = matchSettingsEntry(
        SettingsQuery.parse('vibration'),
        title: 'Haptic feedback',
        description: 'Buzz on interaction',
        keywords: ['vibration', 'rumble'],
      );
      expect(viaKeyword, isNotNull);
      expect(viaKeyword!.titleSpans, isEmpty);
      expect(viaKeyword.descriptionSpans, isEmpty);
    });

    test('prefers word-start hits over mid-word ones', () {
      final match = matchSettingsEntry(
        SettingsQuery.parse('set'),
        title: 'Offset settings',
      );
      expect(match, isNotNull);
      // Only "settings" should highlight, not the "set" inside "Offset".
      expect(match!.titleSpans.length, 1);
      expect(match.titleSpans.single.start, 'Offset '.length);
    });

    test('falls back to mid-word when there is no word-start hit', () {
      final match = matchSettingsEntry(
        SettingsQuery.parse('fset'),
        title: 'Offset',
      );
      expect(match, isNotNull);
      expect(match!.titleSpans.single.start, 2);
    });

    test('section match short-circuits with no spans', () {
      final match = matchSettingsEntry(
        SettingsQuery.parse('gestures'),
        title: 'Folder swipe',
        sectionMatched: true,
      );
      expect(match, isNotNull);
      expect(match!.titleSpans, isEmpty);
    });

    test('empty query matches everything', () {
      expect(
        matchSettingsEntry(SettingsQuery.parse('   '), title: 'Anything'),
        isNotNull,
      );
      expect(SettingsQuery.parse('   ').isEmpty, isTrue);
    });

    test('merges overlapping spans', () {
      final match = matchSettingsEntry(
        SettingsQuery.parse('auto au'),
        title: 'Auto-save',
      );
      expect(match, isNotNull);
      expect(match!.titleSpans.length, 1);
      expect(match.titleSpans.single, const TextRange(start: 0, end: 4));
    });
  });

  group('matchesSettingsQuery', () {
    test('folds and ANDs across fields', () {
      expect(
        matchesSettingsQuery(SettingsQuery.parse('schriftgrosse'), [
          'Schriftgröße verkleinern',
          '',
        ]),
        isTrue,
      );
      expect(
        matchesSettingsQuery(SettingsQuery.parse('grosse zzz'), [
          'Schriftgröße',
        ]),
        isFalse,
      );
      expect(matchesSettingsQuery(SettingsQuery.parse(''), ['x']), isTrue);
    });
  });
}
