import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/search/search_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/app_icon_sizes.dart';
import '../constants/app_spacing.dart';
import '../constants/label_appearance.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/item_label.dart';
import '../models/label_style.dart';
import '../models/note_metadata.dart';
import '../models/search_scope.dart';
import '../services/app_navigator.dart';
import '../services/folder_search_service.dart';
import 'content_rows.dart';
import 'label_dot.dart';
import 'note_row.dart';

const String _pathSeparator = ' › ';

/// What joins two facts about a row that are not the same kind of thing —
/// where a note lives and when it was last touched. The colour names in the
/// labelled header are a list rather than two facts, so they are joined with
/// a comma and only the count after them uses this, from inside the ICU
/// message.
const String _factSeparator = ' · ';

/// The body of the search surface: scope chips, then whatever the current
/// phase has to show.
///
/// Everything below is built as **slivers** even though the standalone route
/// only needs a box, so hosting the same content under the browser's sliver
/// app bar costs a different outer scroll view and nothing else. The chips
/// are a widget of their own for the same reason: in place they belong beside
/// the field, not at the top of the list.
class SearchSurface extends StatelessWidget {
  /// The folder half of the scope choice, or null for the two hosts that have
  /// no second scope to offer — the root, and a `#tag` tap, both of which are
  /// already searching everywhere. Held here rather than read off the state
  /// so the folder chip survives switching to Everywhere and back.
  final FolderScope? folderScope;

  const SearchSurface({super.key, this.folderScope});

  @override
  Widget build(BuildContext context) {
    final folderScope = this.folderScope;
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            if (SearchScopeChips.shows(
              folderScope: folderScope,
              labelsInUse: state.labelsInUse,
            ))
              SliverToBoxAdapter(
                child: SearchScopeChips(
                  folderScope: folderScope,
                  selected: state.scope,
                  labelsInUse: state.labelsInUse,
                  selectedLabels: state.labels,
                ),
              ),
            ...resultSlivers(context, state),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          ],
        );
      },
    );
  }

  /// The result region on its own, so a host that supplies its own app bar
  /// sliver and chip placement can splice it into that scroll view.
  static List<Widget> resultSlivers(BuildContext context, SearchState state) {
    final l10n = AppLocalizations.of(context)!;

    // Before the "nothing found" check, so a pass that is still running never
    // flashes an empty-result message on its way to results. Recents count as
    // something to keep showing: re-running an idle surface after a note was
    // edited through it must not blank the list it is refreshing, which threw
    // away the scroll offset the user came back to.
    if (state.isSearching && !state.hasResults && state.recents.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state.phase == SearchPhase.idle) {
      if (state.recents.isEmpty) {
        return [_messageSliver(context, Icons.search, l10n.searchHint)];
      }
      return [
        SliverToBoxAdapter(child: ContentSectionHeader(label: l10n.recent)),
        _rowsSliver(
          state.recents.length,
          (index) => SearchResultRow(
            metadata: state.recents[index],
            groupPosition: _positionFor(index, state.recents.length),
            path: state.folderPaths[state.recents[index].folderId],
            showDate: true,
          ),
        ),
      ];
    }

    if (!state.hasResults) {
      return [_messageSliver(context, Icons.search_off, l10n.noSearchResults)];
    }

    final showLabels =
        state.titleHits.isNotEmpty && state.contentHits.isNotEmpty;
    // Nothing typed and a colour picked: the rows are not there because of a
    // query, so the header names what actually gathered them.
    // The count is the total the colours gather, not the rows that fitted
    // under the listing's cap — a header reading "3 notes" over a capped list
    // of fifty would be the one number on screen that is wrong.
    final labelHeader = state.isLabelOnly
        ? l10n.labelledNotesHeader(
            state.labelledTotal,
            _labelNames(l10n, state.labels),
          )
        : null;

    return [
      if (labelHeader != null)
        SliverToBoxAdapter(child: ContentSectionHeader(label: labelHeader))
      else if (showLabels && state.titleHits.isNotEmpty)
        SliverToBoxAdapter(
          child: ContentSectionHeader(label: l10n.titlesSection),
        ),
      if (state.titleHits.isNotEmpty)
        _hitsSliver(state, state.titleHits, matchType: SearchMatchType.title),
      if (showLabels && state.contentHits.isNotEmpty)
        SliverToBoxAdapter(
          child: ContentSectionHeader(label: l10n.inTextSection),
        ),
      if (state.contentHits.isNotEmpty)
        _hitsSliver(
          state,
          state.contentHits,
          matchType: SearchMatchType.content,
        ),
    ];
  }

  /// The picked colours, in palette order, as a list: a comma, because these
  /// are several of one kind of thing. The ICU message joins the count after
  /// them with the separator the path line uses.
  static String _labelNames(AppLocalizations l10n, Set<ItemLabel> labels) {
    return [
      for (final label in ItemLabel.inPaletteOrder(labels))
        label.displayName(l10n),
    ].join(', ');
  }

  static Widget _hitsSliver(
    SearchState state,
    List<SearchResult> hits, {
    required SearchMatchType matchType,
  }) {
    return _rowsSliver(hits.length, (index) {
      final hit = hits[index];
      return SearchResultRow(
        metadata: hit.metadata,
        groupPosition: _positionFor(index, hits.length),
        path: state.folderPaths[hit.metadata.folderId],
        titleMatch: _firstMatch(hit, SearchMatchType.title),
        snippet: matchType == SearchMatchType.content
            ? _firstMatch(hit, SearchMatchType.content)
            : null,
        // A colour listing is the recents' stand-in, not a set of hits with
        // the reason stripped out: it says when each note was last touched,
        // exactly as the list it replaced does.
        showDate: state.isLabelOnly,
      );
    });
  }

  static Widget _rowsSliver(int count, Widget Function(int index) builder) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => builder(index),
        childCount: count,
      ),
    );
  }

  static SearchMatch? _firstMatch(SearchResult result, SearchMatchType type) {
    for (final match in result.matches) {
      if (match.type == type) return match;
    }
    return null;
  }

  static RowGroupPosition _positionFor(int index, int count) {
    if (count == 1) return RowGroupPosition.single;
    if (index == 0) return RowGroupPosition.first;
    if (index == count - 1) return RowGroupPosition.last;
    return RowGroupPosition.middle;
  }

  static Widget _messageSliver(
    BuildContext context,
    IconData icon,
    String message,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppIconSizes.extraLarge,
              color: colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(message, style: TextStyle(color: colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

/// The filter row under the search field: the scope pair — the folder the
/// surface was opened on and the whole app — then a dot per colour label any
/// note in that scope actually wears.
///
/// **One horizontally scrollable row, never a `Wrap`.** The in-place host
/// hands this to a sliver app bar's `bottom` at [preferredHeight], a height
/// committed to before the row is built, so a second line would be cut off
/// rather than open the bar. Seven dot chips after a long folder name
/// overflow a 360 dp phone, and scrolling is the only answer that keeps the
/// height fixed.
class SearchScopeChips extends StatelessWidget {
  /// What a host with a fixed box to fill has to reserve — the browser's
  /// in-place bar puts this row in its `bottom`, which wants a height up
  /// front. One chip at the default padded tap target plus the row's own top
  /// padding.
  static const double preferredHeight = 48 + AppSpacing.md;

  /// The chip row's own height, inside the top padding. Fixed rather than
  /// shrink-wrapped so [preferredHeight] is the truth at any chip count and
  /// any density.
  static const double _rowHeight = preferredHeight - AppSpacing.md;

  /// The dot inside a label chip. Two dp over the row dot: a chip whose whole
  /// content is one circle needs the circle to read as the control.
  static const double _labelChipDotSize = 12;

  /// The gap between the dot and the ring drawn around it while the chip is
  /// selected, and the ring's own width — the swatch strip's 2 dp ring, at
  /// the chip's smaller dot.
  static const double _selectedRingGap = 2;
  static const double _selectedRingWidth = 2;

  /// What a selected chip's content measures, ring included. The unselected
  /// dot is centred in the same box, so selecting one moves nothing.
  static const double _labelChipContentSize =
      _labelChipDotSize + 2 * (_selectedRingGap + _selectedRingWidth);

  /// The hairline between the scope pair and the colours, so the row reads as
  /// two groups rather than nine chips.
  static const double _separatorHeight = 18;

  /// The folder chip's scope, fixed for the life of the surface. Null on a
  /// host with no second scope to offer — the root browser, the note lists
  /// and a `#tag` tap — where the row carries colours alone.
  final FolderScope? folderScope;

  /// Which of the two scopes is currently searching.
  final SearchScope selected;

  /// The colours worth offering: the ones notes in this scope carry, in
  /// palette order.
  final List<ItemLabel> labelsInUse;

  /// The colours currently filtering, OR-ed together.
  final Set<ItemLabel> selectedLabels;

  const SearchScopeChips({
    super.key,
    this.folderScope,
    required this.selected,
    this.labelsInUse = const [],
    this.selectedLabels = const {},
  });

  /// Whether there is anything for this row to show at all.
  ///
  /// The root browser has no second scope, so before labels it showed
  /// nothing and its host dropped the bar's `bottom` outright. It still does,
  /// unless a colour is in use — the same conditional, one term wider.
  static bool shows({
    FolderScope? folderScope,
    List<ItemLabel> labelsInUse = const [],
  }) {
    return folderScope != null || labelsInUse.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final folderScope = this.folderScope;
    final isFolder = selected is FolderScope;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: SizedBox(
        height: _rowHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (folderScope != null) ...[
                _scopeChip(
                  context,
                  label: folderScope.name.trim().isEmpty
                      ? l10n.thisFolder
                      : folderScope.name,
                  selected: isFolder,
                  onSelected: () => context.read<SearchBloc>().add(
                    SearchScopeChanged(folderScope),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _scopeChip(
                  context,
                  label: l10n.everywhere,
                  selected: !isFolder,
                  onSelected: () => context.read<SearchBloc>().add(
                    const SearchScopeChanged(SearchScope.everywhere()),
                  ),
                ),
                if (labelsInUse.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  Container(
                    width: 1,
                    height: _separatorHeight,
                    color: colorScheme.rowDivider,
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
              ],
              for (var i = 0; i < labelsInUse.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                _labelChip(context, l10n, labelsInUse[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One colour, drawn as the dot itself rather than its name: the row has to
  /// fit seven of these beside two word chips at 360 dp, and the dot is the
  /// thing the user is matching against the rows below.
  ///
  /// The name is what a screen reader gets, in place of the dot's own
  /// `<Colour> label` — inside a chip the control already says it is a
  /// filter, and the colour is all that is left to name.
  ///
  /// Selection is said with the swatch strip's ring rather than with the
  /// chip's fill: on `secondaryContainer` the yellow, orange and green dots
  /// come out under 3:1, so a user who cannot see the fill change has nothing
  /// to read the state from. The ring is the same 2 dp `primary` circle the
  /// picker draws, and it is drawn inside a box the unselected dot also
  /// fills — selecting a chip must not resize it.
  Widget _labelChip(
    BuildContext context,
    AppLocalizations l10n,
    ItemLabel label,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selectedLabels.contains(label);

    return FilterChip(
      label: Semantics(
        label: label.displayName(l10n),
        excludeSemantics: true,
        child: Container(
          width: _labelChipContentSize,
          height: _labelChipContentSize,
          alignment: Alignment.center,
          decoration: isSelected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary,
                    width: _selectedRingWidth,
                  ),
                )
              : null,
          child: LabelDot(label: label, size: _labelChipDotSize),
        ),
      ),
      labelPadding: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
      selected: isSelected,
      onSelected: (_) =>
          context.read<SearchBloc>().add(SearchLabelsChanged(_toggled(label))),
      side: isSelected
          ? BorderSide.none
          : BorderSide(color: colorScheme.outlineVariant),
    );
  }

  /// The whole set after [label] flips. A `Set` has no order to arrange, and
  /// the one surface that lists these by name sorts them itself.
  Set<ItemLabel> _toggled(ItemLabel label) {
    final next = {...selectedLabels};
    if (!next.remove(label)) next.add(label);
    return next;
  }

  /// The unselected chip carries the outline the mock draws explicitly: the
  /// theme's default border is a tone the rest of the page never uses, and
  /// the selected chip drops the border altogether under its fill.
  Widget _scopeChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      iconTheme: const IconThemeData(size: AppIconSizes.tiny),
      side: selected
          ? BorderSide.none
          : BorderSide(color: colorScheme.outlineVariant),
    );
  }
}

/// A note in the search surface, in the browser's row shell so a result reads
/// like the same object the list below it shows.
///
/// The extra line search needs — where the note lives, and the text that
/// matched — is why this is not [NoteRow] itself: that row's second line is
/// the edit date joined to the stored preview, and a result has two more
/// things to say in the same space.
class SearchResultRow extends StatelessWidget {
  final NoteMetadata metadata;
  final RowGroupPosition groupPosition;

  /// Folder path segments, root-first, or null when the folder is unknown.
  final List<String>? path;

  /// Where the query hit the title, for highlighting it in place.
  final SearchMatch? titleMatch;

  /// The body excerpt to show under the title, with its own highlight.
  final SearchMatch? snippet;

  /// Whether the second line ends with when the note was last edited, the way
  /// the idle "Recent" list says it — a result names the query's own text
  /// instead.
  final bool showDate;

  const SearchResultRow({
    super.key,
    required this.metadata,
    required this.groupPosition,
    this.path,
    this.titleMatch,
    this.snippet,
    this.showDate = false,
  });

  /// Every result subscribes, labelled or not, for the reason [NoteRow]
  /// gives: one root widget type whatever the label.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LabelStyle>(
      valueListenable: LabelAppearance.style,
      builder: (context, style, _) => _buildRow(
        context,
        LabelRowDecoration.resolve(
          context,
          label: metadata.label,
          style: style,
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, LabelRowDecoration decoration) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final title = metadata.title.isEmpty ? l10n.untitledNote : metadata.title;
    final pathLabel = path == null || path!.isEmpty
        ? null
        : path!.join(_pathSeparator);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _highlighted(
          context,
          text: title,
          match: metadata.title.isEmpty ? null : titleMatch,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: RowMetrics.titleFontSize,
            color: colorScheme.onSurface,
          ),
          maxLines: 1,
        ),
        const SizedBox(height: RowMetrics.lineGap),
        _buildPathLine(context, l10n, colorScheme, pathLabel),
        if (snippet != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: _highlighted(
              context,
              text: snippet!.text,
              match: snippet,
              style: TextStyle(
                fontSize: RowMetrics.secondLineFontSize,
                color: colorScheme.onSurface,
              ),
              maxLines: 2,
            ),
          ),
      ],
    );

    return ContentRowShell(
      position: groupPosition,
      edgeStripe: decoration.stripeColor,
      edgeStripeSemantics: decoration.stripeSemantics,
      child: InkWell(
        onTap: () => AppNavigator.toNoteEditorInstant(
          context,
          folderId: metadata.folderId,
          noteId: metadata.id,
          metadata: metadata,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RowMetrics.twoLineMinHeight,
          ),
          child: Padding(
            padding: RowMetrics.twoLinePadding,
            // The label dot sits at the trailing edge, the way it does on a
            // note row, so a result and the browser row it stands for read the
            // same. An unlabelled result keeps the bare Column it always had.
            child: !decoration.showsDot
                ? body
                : Row(
                    children: [
                      Expanded(child: body),
                      const SizedBox(width: RowMetrics.gap),
                      LabelDot(label: metadata.label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// "Training › Winter block · Today" — where the note lives, then when it
  /// was last touched, the date in the weight [NoteRow] gives it so the two
  /// lists read the same.
  Widget _buildPathLine(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    String? pathLabel,
  ) {
    final date = showDate
        ? formatRowDate(
            date: metadata.updatedAt,
            now: DateTime.now(),
            locale: Localizations.localeOf(context).toString(),
            l10n: l10n,
          )
        : null;
    if (pathLabel == null && date == null) return const SizedBox.shrink();

    return Text.rich(
      TextSpan(
        children: [
          if (pathLabel != null) TextSpan(text: pathLabel),
          if (pathLabel != null && date != null)
            const TextSpan(text: _factSeparator),
          if (date != null)
            TextSpan(
              text: date,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: RowMetrics.secondLineFontSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// Paints [text] with the span [match] covers picked out.
  ///
  /// The offsets come straight off the grammar-free [SearchMatch] the service
  /// produced, so nothing here re-scans the text for the query — that is what
  /// used to let the title highlight and the body highlight disagree about
  /// diacritics.
  Widget _highlighted(
    BuildContext context, {
    required String text,
    required SearchMatch? match,
    required TextStyle style,
    required int maxLines,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolved = style.copyWith(
      color: style.color ?? colorScheme.onSurface,
    );

    if (match == null ||
        match.startIndex < 0 ||
        match.endIndex > text.length ||
        match.startIndex >= match.endIndex) {
      return Text(
        text,
        style: resolved,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        style: resolved,
        children: [
          TextSpan(text: text.substring(0, match.startIndex)),
          TextSpan(
            text: text.substring(match.startIndex, match.endIndex),
            style: TextStyle(
              backgroundColor: colorScheme.primaryContainer,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          TextSpan(text: text.substring(match.endIndex)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
