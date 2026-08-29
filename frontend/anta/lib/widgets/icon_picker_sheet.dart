import 'package:flutter/material.dart';

import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../utils/fuzzy_rank.dart';
import '../utils/settings_search.dart';
import 'settings_search_field.dart';

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
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refreshGroupLabels()) _recompute();
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
      if (!matchesSettingsQuery(_query, [
        text,
        groupLabel,
      ], preFolded: true)) {
        continue;
      }
      final scored = FuzzyRank.score(text, _term);
      ranked.add((
        entry: entry,
        band: scored >= 0 ? scored : FuzzyRank.tiers,
        index: i,
      ));
    }
    ranked.sort((a, b) {
      final byBand = a.band.compareTo(b.band);
      return byBand != 0 ? byBand : a.index.compareTo(b.index);
    });
    _results = [for (final r in ranked) r.entry];
  }

  void _clearQuery() {
    _searchController.clear();
    _onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            l10n.pickIcon,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SettingsSearchField(
            controller: _searchController,
            hint: l10n.searchIcons,
            onChanged: _onQueryChanged,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _query.isEmpty
              ? _buildGroups(context, bottomClearance)
              : _results.isEmpty
              ? _buildEmptyState(context)
              : _buildResults(context, bottomClearance),
        ),
      ],
    );
  }

  Widget _buildGroups(BuildContext context, double bottomClearance) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomClearance),
      itemCount: CalendarIcons.groups.length,
      itemBuilder: (context, index) {
        final group = CalendarIcons.groups[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                child: Text(
                  CalendarIcons.groupLabel(group.id, l10n),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildWrap(group.entries),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(BuildContext context, double bottomClearance) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomClearance),
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
            onTap: () => Navigator.of(context).pop(entry.key),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noIconsFound,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _clearQuery,
            child: Text(l10n.clearSearch),
          ),
        ],
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

    return InkResponse(
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
    );
  }
}
