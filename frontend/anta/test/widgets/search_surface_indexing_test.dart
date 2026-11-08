import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/search/search_bloc.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/widgets/search_surface.dart';

/// The one line a full search shows while the body index is still being
/// filled (S11), rendered straight from a state.
void main() {
  NoteMetadata note(String id) => NoteMetadata(
    id: id,
    folderId: 'f1',
    title: 'Note $id',
    preview: 'preview',
    contentLength: 1,
    chunkCount: 1,
    isCompressed: false,
    createdAt: DateTime(2026, 11, 8),
    updatedAt: DateTime(2026, 11, 8),
    label: ItemLabel.none,
  );

  SearchResult hit(String id) => SearchResult(
    metadata: note(id),
    matches: const [
      SearchMatch(
        text: 'a squat here',
        startIndex: 2,
        endIndex: 7,
        type: SearchMatchType.content,
      ),
    ],
    relevanceScore: 1,
  );

  Future<AppLocalizations> pumpSurface(
    WidgetTester tester,
    SearchState state, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context)!;
              return CustomScrollView(
                slivers: SearchSurface.resultSlivers(context, state),
              );
            },
          ),
        ),
      ),
    );
    return l10n;
  }

  testWidgets('a full search read mid-backfill says so above its hits', (
    tester,
  ) async {
    final l10n = await pumpSurface(
      tester,
      SearchState(
        query: 'squat',
        phase: SearchPhase.full,
        contentHits: [hit('a')],
        stillIndexing: true,
      ),
    );

    final line = find.text(l10n.searchStillIndexing);
    expect(line, findsOneWidget);
    expect(
      tester.getTopLeft(line).dy,
      lessThan(tester.getTopLeft(find.byType(SearchResultRow)).dy),
    );
  });

  testWidgets('it stands above "no results" too', (tester) async {
    final l10n = await pumpSurface(
      tester,
      const SearchState(
        query: 'zercher',
        phase: SearchPhase.full,
        stillIndexing: true,
      ),
    );

    expect(find.text(l10n.searchStillIndexing), findsOneWidget);
    expect(find.text(l10n.noSearchResults), findsOneWidget);
  });

  testWidgets('a settled full search and a quick pass show no line', (
    tester,
  ) async {
    var l10n = await pumpSurface(
      tester,
      SearchState(
        query: 'squat',
        phase: SearchPhase.full,
        contentHits: [hit('a')],
      ),
    );
    expect(find.text(l10n.searchStillIndexing), findsNothing);

    l10n = await pumpSurface(
      tester,
      SearchState(
        query: 'squat',
        phase: SearchPhase.quick,
        contentHits: [hit('a')],
        stillIndexing: true,
      ),
    );
    expect(find.text(l10n.searchStillIndexing), findsNothing);
  });

  for (final locale in const [Locale('de'), Locale('ro')]) {
    testWidgets('the line wraps cleanly in $locale at text scale 2.0', (
      tester,
    ) async {
      final l10n = await pumpSurface(
        tester,
        SearchState(
          query: 'squat',
          phase: SearchPhase.full,
          contentHits: [hit('a')],
          stillIndexing: true,
        ),
        locale: locale,
        textScale: 2.0,
      );

      expect(find.text(l10n.searchStillIndexing), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
