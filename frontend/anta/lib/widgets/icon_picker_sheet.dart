import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../services/settings_service.dart';
import '../utils/fuzzy_rank.dart';
import '../utils/settings_search.dart';
import 'form_rows.dart';

/// Band for an entry the query names exactly, one better than
/// [FuzzyRank.tierPrefix] (0) — the only way a one-character query reaches the
/// letter glyphs rather than everything spelled with that letter first.
const int _exactBand = -1;

/// Modal bottom-sheet icon picker. Pops with the selected icon key, or
/// `null` if the user dismissed.
///
/// Two modes over one catalog: an empty query keeps the grouped sections the
/// sheet has always shown, an active one flattens the whole catalog into a
/// single ranked result set.
///
/// **Membership** is [matchesSettingsQuery] over `CalendarIcons.searchTextOf`
/// — a *prebuilt folded index*, so a keystroke costs a `contains` over static
/// strings rather than folding the catalog again. That budget is what keeps
/// the filter synchronous and undebounced. The localized group labels are the
/// one thing that cannot be prebuilt (they move with the locale, the catalog
/// does not), so they are folded once per sheet open and joined into the same
/// match set: a German user typing `Ernährung` still reaches the nutrition
/// section.
///
/// **Order** is [FuzzyRank] over the same index, tie-broken by catalog
/// position — `List.sort` is not stable in Dart, and same-band hits are the
/// common case here. Ranking never decides what matches; that stays with
/// [matchesSettingsQuery].
class IconPickerSheet extends StatefulWidget {
  final String? initialKey;
  final Color tint;

  const IconPickerSheet({super.key, required this.tint, this.initialKey});

  static Future<String?> show(
    BuildContext context, {
    required Color tint,
    String? initialKey,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      // The form sheet's fixed box rather than a content-tall sub-sheet: a
      // grid of hundreds of icons under a live search would change height
      // on every keystroke (D10).
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: IconPickerSheet(initialKey: initialKey, tint: tint),
      ),
    );
  }

  @override
  State<IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<IconPickerSheet> {
  /// The catalog read in one flat pass, in [CalendarIcons.groups] order. Built
  /// once for the process, not once per sheet — it is derived from a `const`
  /// list and never changes.
  static final List<CalendarIconEntry> _flatCatalog = [
    for (final group in CalendarIcons.groups) ...group.entries,
  ];

  final TextEditingController _searchController = TextEditingController();

  SettingsQuery _query = SettingsQuery.empty;
  String _term = '';
  List<CalendarIconEntry> _results = const [];
  Map<IconGroupId, String> _foldedGroupLabels = const {};
  String? _labelsLocale;

  /// The last few picks, newest first — the section that keeps a catalog of
  /// hundreds feeling small. Empty until the settings read lands, and empty
  /// on a fresh install, in which case the section is simply absent.
  List<CalendarIconEntry> _recent = const [];
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refreshGroupLabels()) _recompute();
  }

  Future<void> _loadRecent() async {
    try {
      final settings = await SettingsService.getInstance();
      final keys = await settings.getRecentIconKeys();
      if (!mounted) return;
      final entries = <CalendarIconEntry>[];
      for (final key in keys) {
        final entry = CalendarIcons.entryFor(key);
        if (entry != null) entries.add(entry);
      }
      setState(() {
        _settings = settings;
        _recent = entries;
      });
    } catch (e) {
      debugPrint('[IconPickerSheet] Recent icons load failed: $e');
    }
  }

  /// Returns [key] to the caller and records the pick.
  ///
  /// The write is deliberately not awaited: the sheet is closing, and a
  /// failed write costs the ordering of a convenience list, never the pick.
  void _pick(String key) {
    _recordRecent(key);
    Navigator.of(context).pop(key);
  }

  Future<void> _recordRecent(String key) async {
    try {
      final settings = _settings ?? await SettingsService.getInstance();
      await settings.recordRecentIconKey(key);
    } catch (e) {
      debugPrint('[IconPickerSheet] Recent icon write failed: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Re-folds the localized group labels when the locale has moved, and
  /// reports whether it did.
  bool _refreshGroupLabels() {
    final l10n = AppLocalizations.of(context)!;
    if (_labelsLocale == l10n.localeName) return false;
    _labelsLocale = l10n.localeName;
    _foldedGroupLabels = {
      for (final group in CalendarIcons.groups)
        group.id: normalizeForSearch(CalendarIcons.groupLabel(group.id, l10n)),
    };
    return true;
  }

  void _onQueryChanged(String raw) {
    setState(() {
      _query = SettingsQuery.parse(raw);
      // Tokens are already folded and whitespace-collapsed, so joining them is
      // the normalized form of what was typed — and `FuzzyRank` needs the
      // whole string, not a token at a time.
      _term = _query.tokens.join(' ');
      _recompute();
    });
  }

  void _recompute() {
    if (_query.isEmpty) {
      _results = const [];
      return;
    }
    final ranked = <({CalendarIconEntry entry, int band, int index})>[];
    for (var i = 0; i < _flatCatalog.length; i++) {
      final entry = _flatCatalog[i];
      final text = CalendarIcons.searchTextOf(entry.key);
      final groupLabel =
          _foldedGroupLabels[CalendarIcons.groupIdOf(entry.key)] ?? '';
      if (!matchesSettingsQuery(_query, [text, groupLabel], preFolded: true)) {
        continue;
      }
      // An exact term outranks every FuzzyRank tier — see
      // `CalendarIcons.isExactTerm`. Without it a one-character query can
      // never reach the letter glyphs, because `FuzzyRank` scores a prefix of
      // the whole search text and a letter's text begins with "letter".
      //
      // The two are resolved separately on purpose: `FuzzyRank.score` returns
      // `-1` for "no match", which is the same value as [_exactBand], so
      // folding them into one expression promotes every entry that matched
      // only through its group label to the *best* band instead of the worst.
      final exact = CalendarIcons.isExactTerm(entry.key, _term);
      final scored = FuzzyRank.score(text, _term);
      ranked.add((
        entry: entry,
        band: exact ? _exactBand : (scored >= 0 ? scored : FuzzyRank.tiers),
        index: i,
      ));
    }
    ranked.sort((a, b) {
      final byBand = a.band.compareTo(b.band);
      return byBand != 0 ? byBand : a.index.compareTo(b.index);
    });
    _results = [for (final r in ranked) r.entry];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // `useSafeArea: true` on the modal route avoids the status bar but has
    // proven unreliable against the bottom gesture/nav bar on real devices
    // (the last icon row rendered under it) — same fix as `EventEditorSheet`
    // / `CategoryEditorSheet`: pad the grid's bottom by the larger of the
    // keyboard inset and the system's bottom inset.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.iconPickClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.pickIcon,
          trailingInset: FormMetrics.headerActionInset,
          // A tile pops on tap; there is nothing to confirm.
          trailing: const SizedBox.shrink(),
        ),
        // Pinned between the header and the grid rather than scrolling with
        // it: a field that scrolls away with its results is unreachable
        // while the results change, and pinned it never moves under the
        // finger (D17).
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RowMetrics.groupInset,
            FormMetrics.bodyTop,
            RowMetrics.groupInset,
            0,
          ),
          child: FormRowGroup(
            trailingGap: false,
            children: [
              FormSearchRow(
                controller: _searchController,
                hint: l10n.searchIcons,
                clearTooltip: l10n.clearSearch,
                identifier: SemanticsIds.iconPickSearch,
                onChanged: _onQueryChanged,
              ),
            ],
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? _buildGroups(context, bottomClearance)
              : _results.isEmpty
              ? _buildNoMatch(context)
              : _buildResults(context, bottomClearance),
        ),
      ],
    );
  }

  /// The grid's padding: the language's gap under the pinned search group,
  /// and the clearance below the last row.
  EdgeInsets _gridPadding(double bottomClearance) => EdgeInsets.fromLTRB(
    RowMetrics.groupInset,
    RowMetrics.groupGap,
    RowMetrics.groupInset,
    FormMetrics.bodyBottom + bottomClearance,
  );

  /// The grouped catalog, with "Recently used" pinned above it when there is
  /// anything to show. The section is deliberately absent while a query is
  /// active — this builder only runs for an empty one, because search results
  /// are already the shortlist a recents row exists to provide.
  Widget _buildGroups(BuildContext context, double bottomClearance) {
    final l10n = AppLocalizations.of(context)!;
    final showRecent = _recent.isNotEmpty;

    return ListView.builder(
      padding: _gridPadding(bottomClearance),
      itemCount: CalendarIcons.groups.length + (showRecent ? 1 : 0),
      itemBuilder: (context, index) {
        if (showRecent && index == 0) {
          return _buildSection(context, l10n.iconGroupRecent, _recent);
        }
        final group = CalendarIcons.groups[showRecent ? index - 1 : index];
        return _buildSection(
          context,
          CalendarIcons.groupLabel(group.id, l10n),
          group.entries,
        );
      },
    );
  }

  Widget _buildSection(
    BuildContext context,
    String label,
    List<CalendarIconEntry> entries,
  ) {
    return Padding(
      // The language's gap between groups, the wrap standing for a group
      // under its section label.
      padding: const EdgeInsets.only(bottom: RowMetrics.groupGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [FormSectionLabel(text: label), _buildWrap(entries)],
      ),
    );
  }

  Widget _buildResults(BuildContext context, double bottomClearance) {
    return ListView(
      padding: _gridPadding(bottomClearance),
      children: [_buildWrap(_results)],
    );
  }

  Widget _buildWrap(List<CalendarIconEntry> entries) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          _IconTile(
            iconKey: entry.key,
            selected: entry.key == widget.initialKey,
            tint: widget.tint,
            onTap: () => _pick(entry.key),
          ),
      ],
    );
  }

  /// The no-match line under the search group, where the category picker
  /// puts its own; the row's ✕ is the way back, so no button repeats it.
  Widget _buildNoMatch(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
        child: FormCaption(
          text: l10n.noIconsFound,
          padding: FormMetrics.groupCaptionPadding,
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final String iconKey;
  final bool selected;
  final Color tint;
  final VoidCallback onTap;

  const _IconTile({
    required this.iconKey,
    required this.selected,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = CalendarIcons.forKey(iconKey);
    if (icon == null) return const SizedBox.shrink();

    final bg = selected
        ? tint.withValues(alpha: 0.18)
        : theme.colorScheme.surfaceContainerHighest;
    final fg = selected ? tint : theme.colorScheme.onSurfaceVariant;
    final border = selected
        ? Border.all(color: tint, width: 2)
        : Border.all(color: Colors.transparent, width: 2);

    // A bare `Icon` in an `InkResponse` is an unnamed button to a screen
    // reader, and there are hundreds of them here. The key read with
    // underscores as spaces is the same humanization the search index
    // applies, so it needs no ARB entry — the keywords being English and
    // unlocalized is a decision about *match* text, and this is the one
    // place a key becomes readable.
    return Tooltip(
      message: iconKey.replaceAll('_', ' '),
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: border,
          ),
          child: Icon(icon, color: fg, size: 24),
        ),
      ),
    );
  }
}
