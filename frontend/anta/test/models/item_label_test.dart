import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/models/folder.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';

/// The enum's two decoders are the whole compatibility story for labels: a
/// column written by a newer build, a hand-edited database, and a backup made
/// before labels existed all have to read as "unlabelled" rather than as an
/// arbitrary colour or a crash.
void main() {
  group('fromStorage', () {
    test('maps the palette in declaration order', () {
      expect(ItemLabel.fromStorage(0), ItemLabel.none);
      expect(ItemLabel.fromStorage(1), ItemLabel.red);
      expect(ItemLabel.fromStorage(2), ItemLabel.orange);
      expect(ItemLabel.fromStorage(3), ItemLabel.yellow);
      expect(ItemLabel.fromStorage(4), ItemLabel.green);
      expect(ItemLabel.fromStorage(5), ItemLabel.teal);
      expect(ItemLabel.fromStorage(6), ItemLabel.blue);
      expect(ItemLabel.fromStorage(7), ItemLabel.pink);
    });

    test('round-trips every label through its storage value', () {
      for (final label in ItemLabel.values) {
        expect(ItemLabel.fromStorage(label.storageValue), label);
      }
    });

    test('null, negative and out-of-range read as none', () {
      expect(ItemLabel.fromStorage(null), ItemLabel.none);
      expect(ItemLabel.fromStorage(-1), ItemLabel.none);
      expect(ItemLabel.fromStorage(8), ItemLabel.none);
      expect(ItemLabel.fromStorage(9999), ItemLabel.none);
    });
  });

  group('fromName', () {
    test('round-trips every label through its storage name', () {
      for (final label in ItemLabel.values) {
        expect(ItemLabel.fromName(label.storageName), label);
      }
    });

    test('null, empty and unknown names read as none', () {
      expect(ItemLabel.fromName(null), ItemLabel.none);
      expect(ItemLabel.fromName(''), ItemLabel.none);
      expect(ItemLabel.fromName('purple'), ItemLabel.none);
      expect(
        ItemLabel.fromName('Red'),
        ItemLabel.none,
        reason: 'names are the exact enum spelling, not a fuzzy match',
      );
    });
  });

  test('assignable is the seven colours, none excluded', () {
    expect(ItemLabel.assignable, hasLength(7));
    expect(ItemLabel.assignable, isNot(contains(ItemLabel.none)));
    expect(ItemLabel.assignable.first, ItemLabel.red);
    expect(ItemLabel.assignable.last, ItemLabel.pink);
  });

  group('NoteMetadata JSON', () {
    NoteMetadata noteWith(ItemLabel label) => NoteMetadata(
      id: 'n1',
      folderId: 'f1',
      title: 'Leg day',
      preview: 'squats',
      contentLength: 6,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      label: label,
    );

    test('defaults to none', () {
      expect(
        NoteMetadata(
          id: 'n',
          folderId: 'f',
          title: '',
          preview: '',
          contentLength: 0,
          chunkCount: 1,
          isCompressed: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ).label,
        ItemLabel.none,
      );
    });

    test('round-trips the label as a name', () {
      final json = noteWith(ItemLabel.teal).toJson();
      expect(json[JsonKeys.label], 'teal');
      expect(NoteMetadata.fromJson(json).label, ItemLabel.teal);
    });

    test('a map without the key imports as none', () {
      final json = noteWith(ItemLabel.blue).toJson()..remove(JsonKeys.label);
      expect(NoteMetadata.fromJson(json).label, ItemLabel.none);
    });

    test('copyWith carries and replaces the label', () {
      final note = noteWith(ItemLabel.green);
      expect(note.copyWith(title: 'Other').label, ItemLabel.green);
      expect(note.copyWith(label: ItemLabel.pink).label, ItemLabel.pink);
    });

    test('the label is part of equality', () {
      expect(noteWith(ItemLabel.red), isNot(noteWith(ItemLabel.blue)));
      expect(noteWith(ItemLabel.red), noteWith(ItemLabel.red));
    });
  });

  group('Folder JSON', () {
    Folder folderWith(ItemLabel label) => Folder(
      id: 'f1',
      name: 'Training',
      createdAt: DateTime(2026, 1, 1),
      label: label,
    );

    test('defaults to none', () {
      expect(
        Folder(id: 'f', name: 'F', createdAt: DateTime(2026)).label,
        ItemLabel.none,
      );
    });

    test('round-trips the label as a name', () {
      final json = folderWith(ItemLabel.orange).toJson();
      expect(json[JsonKeys.label], 'orange');
      expect(Folder.fromJson(json).label, ItemLabel.orange);
    });

    test('a map without the key imports as none', () {
      final json = folderWith(ItemLabel.yellow).toJson()
        ..remove(JsonKeys.label);
      expect(Folder.fromJson(json).label, ItemLabel.none);
    });

    test('copyWith carries and replaces the label', () {
      final folder = folderWith(ItemLabel.blue);
      expect(folder.copyWith(name: 'Money').label, ItemLabel.blue);
      expect(folder.copyWith(label: ItemLabel.none).label, ItemLabel.none);
    });

    test('the label is part of equality', () {
      expect(folderWith(ItemLabel.red), isNot(folderWith(ItemLabel.teal)));
      expect(folderWith(ItemLabel.red), folderWith(ItemLabel.red));
    });
  });
}
