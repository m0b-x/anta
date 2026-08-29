import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import 'fuzzy_rank.dart';
import 'settings_search.dart';

/// One ranked row: the category and the band it landed in. Lower is better.
typedef RankedCategory = ({CalendarCategory category, int band});

/// Band assigned to a category that matched only through its icon — its
/// keywords, its key or its icon group's label — and not through its name.
///
/// [FuzzyRank] scores a name hit 0..[FuzzyRank.tiers] - 1, so sitting one
/// above that ceiling is what "below every name hit" means, expressed as a
/// band rather than a filter: an icon match still gets you there, it just
/// never gets you there *first*.
const int kIconOnlyBand = FuzzyRank.tiers;

/// The one ranking function behind every searchable category list — the
/// management page and the picker sheet — so the two cannot answer the same
/// query differently.
///
/// **Membership** is [matchesSettingsQuery] (an AND over tokens, so extra
/// words narrow) across the localized label, the raw stored `name`, the icon
/// key read with underscores as spaces, the icon's keywords and the icon
/// group's localized label. The last three come from
/// `CalendarIcons.searchTextOf`, a **prebuilt folded index** rather than a
/// per-keystroke fold of the catalog.
///
/// **Order** is `(band, sortOrder)`, sorted explicitly on both — `List.sort`
/// is not stable in Dart, and same-band rows are the common case here, so a
/// bare band sort reshuffles identical input between rebuilds. The agenda's
/// summary cards hit exactly this.
///
/// An empty query yields every category in [categories], in display order:
/// `FuzzyRank.score` treats the empty term as a prefix of everything, so they
/// all land in band 0 and the `sortOrder` tiebreak carries the result.
List<RankedCategory> rankCategories(
  SettingsQuery query,
  Iterable<CalendarCategory> categories,
  AppLocalizations l10n,
) {
  // The whole query as one folded term. Tokens are already folded and
  // whitespace-collapsed, so joining them is the normalized form of what the
  // user typed — and `FuzzyRank` needs the whole string, not a token at a
  // time, or "gtlnt" stops reaching "Great Lent".
  final term = query.tokens.join(' ');

  // Group labels are localized, so unlike the icon index they cannot be
  // precomputed at catalog level — but they change with the locale, not with
  // the keystroke, so folding each one once per call is enough.
  final groupLabels = <IconGroupId, String>{};
  String foldedGroupLabelOf(String iconKey) {
    final id = CalendarIcons.groupIdOf(iconKey);
    if (id == null) return '';
    return groupLabels[id] ??= normalizeForSearch(
      CalendarIcons.groupLabel(id, l10n),
    );
  }

  final ranked = <RankedCategory>[];
  for (final category in categories) {
    final label = CalendarCategories.labelOf(category, l10n);
    final foldedLabel = normalizeForSearch(label);
    final foldedName = normalizeForSearch(category.name);

    // Membership decides, ranking only orders — `fuzzy_rank.dart`'s own rule.
    // A name hit that `FuzzyRank` cannot score (its tiers are prefix /
    // word-start / substring / subsequence over the *whole* term, so multi-word
    // queries spread across a label can miss all four) still ranks as a name
    // hit, at the weakest name tier. Demoting it to the icon band would put a
    // real name match below a keyword match.
    if (matchesSettingsQuery(query, [
      foldedLabel,
      foldedName,
    ], preFolded: true)) {
      final scored = query.isEmpty
          ? FuzzyRank.tierPrefix
          : _bestOf(
              FuzzyRank.score(foldedLabel, term),
              FuzzyRank.score(foldedName, term),
            );
      ranked.add((
        category: category,
        band: scored >= 0 ? scored : FuzzyRank.tiers - 1,
      ));
      continue;
    }

    // Not a name hit — but the icon still counts, one band below every name.
    final matched = matchesSettingsQuery(query, [
      foldedLabel,
      foldedName,
      CalendarIcons.searchTextOf(category.iconKey),
      foldedGroupLabelOf(category.iconKey),
    ], preFolded: true);
    if (matched) ranked.add((category: category, band: kIconOnlyBand));
  }

  ranked.sort((a, b) {
    final byBand = a.band.compareTo(b.band);
    if (byBand != 0) return byBand;
    final byOrder = a.category.sortOrder.compareTo(b.category.sortOrder);
    return byOrder != 0 ? byOrder : a.category.id.compareTo(b.category.id);
  });
  return ranked;
}

/// The stronger of two [FuzzyRank] scores, treating `-1` (no match) as worst.
int _bestOf(int a, int b) {
  if (a < 0) return b;
  if (b < 0) return a;
  return a < b ? a : b;
}
