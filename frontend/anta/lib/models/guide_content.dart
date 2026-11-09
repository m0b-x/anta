import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'calendar_guide_content.dart';

/// One page of a guide book (`docs/guide-hub-roadmap.md` D3, D4): the hub
/// lists it, the top hub's search reaches into its entries, and its page
/// shows them under one "How it works" card.
///
/// An interface rather than a base enum, so each book's pages stay an enum
/// of their own whose slugs cannot collide inside the book; the calendar's
/// [CalendarGuideTopic] keeps its own shape (D7).
abstract interface class GuideTopic {
  /// Frozen: the hub row's, the page's and every entry's ids are built on it
  /// together with the book's slug.
  String get slug;

  IconData get icon;

  String title(AppLocalizations l10n);

  String caption(AppLocalizations l10n);

  /// The one line under the page's heading; null for a page without one.
  String? lead(AppLocalizations l10n);

  /// The page's rows in reading order.
  List<GuideEntry> entries(AppLocalizations l10n);
}

/// One row of a guide page: a paragraph to read or an example to look at.
sealed class GuideEntry {
  const GuideEntry();
}

/// A read row, drawn exactly as the calendar guide draws its own (D4, D7).
final class GuideReadEntry extends GuideEntry {
  const GuideReadEntry(this.row);

  final CalendarGuideRow row;
}

/// A markdown example (§4 of the record): the [source] as typed over what
/// the editor's preview makes of it, with a [caption] under both.
final class GuideExampleEntry extends GuideEntry {
  const GuideExampleEntry({
    required this.slug,
    required this.source,
    required this.caption,
  });

  /// Frozen like a read row's: the example's id is built on it.
  final String slug;
  final String source;
  final String caption;
}
