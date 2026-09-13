import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/search/search_bloc.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/search_surface.dart';

/// The header over a colour listing, rendered straight from a state rather
/// than through a page: the two numbers it could show — how many notes the
/// colours gather, and how many rows fitted under the listing's cap — are the
/// same in every realistic fixture, and only a hand-made state tells them
/// apart.
void main() {
  final l10n = AppLocalizationsEn();

  NoteMetadata note(String id) => NoteMetadata(
    id: id,
    folderId: 'f1',
    title: 'Note $id',
    preview: 'preview',
    contentLength: 1,
    chunkCount: 1,
    isCompressed: false,
    createdAt: DateTime(2026, 9, 13),
    updatedAt: DateTime(2026, 9, 13),
    label: ItemLabel.red,
  );

  SearchResult unmatched(String id) =>
      SearchResult(metadata: note(id), matches: const [], relevanceScore: 0);

  Future<void> pumpSurface(WidgetTester tester, SearchState state) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => CustomScrollView(
              slivers: SearchSurface.resultSlivers(context, state),
            ),
          ),
        ),
      ),
    );
  }

  List<String> sectionLabels(WidgetTester tester) => tester
      .widgetList<ContentSectionHeader>(find.byType(ContentSectionHeader))
      .map((header) => header.label)
      .toList();

  testWidgets('the count is the colours\' total, not the rows listed', (
    tester,
  ) async {
    await pumpSurface(
      tester,
      SearchState(
        phase: SearchPhase.quick,
        labels: const {ItemLabel.red},
        titleHits: [unmatched('a'), unmatched('b')],
        labelledTotal: 97,
      ),
    );

    expect(sectionLabels(tester), [l10n.labelledNotesHeader(97, 'Red')]);
    expect(find.byType(SearchResultRow), findsNWidgets(2));
  });

  testWidgets('several colours are named with a comma, the count after '
      'them', (tester) async {
    await pumpSurface(
      tester,
      SearchState(
        phase: SearchPhase.quick,
        labels: const {ItemLabel.teal, ItemLabel.red},
        titleHits: [unmatched('a')],
        labelledTotal: 1,
      ),
    );

    expect(
      sectionLabels(tester),
      [l10n.labelledNotesHeader(1, 'Red, Teal')],
      reason:
          'palette order whatever order they were tapped in, and a comma '
          'between names so the ` · ` before the count reads as one break',
    );
  });
}
