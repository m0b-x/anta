import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/note_position_service.dart';

/// Mirrors what [NotePositionService.savePosition] writes and what
/// [NotePositionService.getPosition] reads back: a `jsonEncode` of
/// [NotePositionData.toJson], decoded through [NotePositionData.fromJson]
/// with a `defaultPosition` fallback on anything that throws.
NotePositionData _roundTrip(NotePositionData position) {
  final encoded = jsonEncode(position.toJson());
  return NotePositionData.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
}

NotePositionData _decodeOrDefault(String stored) {
  try {
    return NotePositionData.fromJson(
      jsonDecode(stored) as Map<String, dynamic>,
    );
  } catch (_) {
    return NotePositionData.defaultPosition;
  }
}

void main() {
  group('NotePositionData round-trip', () {
    test('preserves every field including isPreviewMode', () {
      const saved = NotePositionData(
        isPreviewMode: true,
        previewScrollProgress: 0.42,
        editorLineIndex: 137,
        editorColumnOffset: 9,
      );

      final restored = _roundTrip(saved);

      expect(restored.isPreviewMode, isTrue);
      expect(restored.previewScrollProgress, closeTo(0.42, 1e-9));
      expect(restored.editorLineIndex, 137);
      expect(restored.editorColumnOffset, 9);
    });

    test('preserves an editor-mode position', () {
      const saved = NotePositionData(
        isPreviewMode: false,
        previewScrollProgress: 0.0,
        editorLineIndex: 4,
        editorColumnOffset: 12,
      );

      final restored = _roundTrip(saved);

      expect(restored.isPreviewMode, isFalse);
      expect(restored.editorLineIndex, 4);
      expect(restored.editorColumnOffset, 12);
    });

    test('serializes the scroll progress under the legacy JSON key', () {
      const saved = NotePositionData(
        isPreviewMode: true,
        previewScrollProgress: 0.75,
        editorLineIndex: 0,
        editorColumnOffset: 0,
      );

      final json = saved.toJson();

      expect(json['previewScrollOffset'], 0.75);
      expect(json.containsKey('previewScrollProgress'), isFalse);
      expect(json['isPreviewMode'], isTrue);
    });
  });

  group('NotePositionData.fromJson defaults', () {
    test('defaults isPreviewMode to false when the key is missing', () {
      final restored = NotePositionData.fromJson(const {
        'previewScrollOffset': 0.5,
        'editorLineIndex': 3,
        'editorColumnOffset': 1,
      });

      expect(restored.isPreviewMode, isFalse);
      expect(restored.previewScrollProgress, 0.5);
      expect(restored.editorLineIndex, 3);
    });

    test('a non-bool isPreviewMode falls back per field, keeping the caret', () {
      final restored = _decodeOrDefault(
        jsonEncode(const {'isPreviewMode': 'true', 'editorLineIndex': 2}),
      );

      expect(restored.isPreviewMode, isFalse);
      expect(restored.editorLineIndex, 2);
    });

    test('non-numeric caret fields fall back without dropping the rest', () {
      final restored = _decodeOrDefault(
        jsonEncode(const {
          'isPreviewMode': true,
          'previewScrollOffset': 'half',
          'editorLineIndex': '7',
          'editorColumnOffset': 5,
        }),
      );

      expect(restored.isPreviewMode, isTrue);
      expect(restored.previewScrollProgress, 0.0);
      expect(restored.editorLineIndex, 0);
      expect(restored.editorColumnOffset, 5);
    });

    test('an integer-valued double caret index is accepted', () {
      final restored = _decodeOrDefault(
        jsonEncode(const {'editorLineIndex': 12.0, 'editorColumnOffset': 3.0}),
      );

      expect(restored.editorLineIndex, 12);
      expect(restored.editorColumnOffset, 3);
    });

    test('legacy rows without any known key fall back to the defaults', () {
      final restored = NotePositionData.fromJson(const {'scrollOffset': 120.0});

      expect(restored.isPreviewMode, isFalse);
      expect(restored.previewScrollProgress, 0.0);
      expect(restored.editorLineIndex, 0);
      expect(restored.editorColumnOffset, 0);
    });

    test('malformed JSON decodes to the default position', () {
      final restored = _decodeOrDefault('{not json');

      expect(restored.isPreviewMode, isFalse);
      expect(restored.previewScrollProgress, 0.0);
      expect(restored.editorLineIndex, 0);
      expect(restored.editorColumnOffset, 0);
    });

    test('a JSON list (not an object) decodes to the default position', () {
      final restored = _decodeOrDefault('[1,2,3]');

      expect(restored.isPreviewMode, isFalse);
      expect(restored.editorLineIndex, 0);
    });

    test('defaultPosition never opens a note in preview', () {
      expect(NotePositionData.defaultPosition.isPreviewMode, isFalse);
      expect(NotePositionData.defaultPosition.previewScrollProgress, 0.0);
    });
  });
}
