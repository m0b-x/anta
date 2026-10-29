import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/sync/sync_tables.dart';

/// Pins `firestore.indexes.json` to the binding registry.
///
/// Firestore indexes every field of a document and every subfield of a map,
/// ascending and descending, so an unexempted `data` map costs roughly twice
/// its own size in index entries — a 900 KB note about 1.8 MiB of dead weight
/// on Spark's 1 GiB ceiling, for fields no query names: the pull orders by
/// `pushedAt` then `__name__` alone, both top-level and neither touched by an
/// exemption on `data`. A map's subfields inherit the exemption on the map,
/// so one entry per collection group covers the whole payload.
///
/// Nothing is deployed from here, and the emulator cannot prove an exemption
/// (no indexes, no quotas): reading the file is the whole check, which is
/// what makes a binding added without its exemption fail the default gate
/// instead of the day the owner deploys (A4 review R96).
void main() {
  Map<String, dynamic> config() {
    return jsonDecode(File('firestore.indexes.json').readAsStringSync())
        as Map<String, dynamic>;
  }

  test('every synced table exempts its data map from indexing', () {
    final overrides = config()['fieldOverrides'] as List<dynamic>;
    final exempted = {
      for (final override in overrides.cast<Map<String, dynamic>>())
        if (override['fieldPath'] == 'data' &&
            (override['indexes'] as List<dynamic>).isEmpty)
          override['collectionGroup'] as String,
    };

    expect(exempted, syncTableBindings.map((b) => b.table).toSet());
    // The set alone would pass beside a second override for the same group
    // — a `data` with indexes, a `*` — which is what would actually be
    // deployed for it.
    expect(overrides, hasLength(syncTableBindings.length));
  });

  test('the pairs composite index is untouched', () {
    expect(config()['indexes'], [
      {
        'collectionGroup': 'pairs',
        'queryScope': 'COLLECTION',
        'fields': [
          {'fieldPath': 'members', 'arrayConfig': 'CONTAINS'},
          {'fieldPath': 'status', 'order': 'ASCENDING'},
        ],
      },
    ]);
  });
}
