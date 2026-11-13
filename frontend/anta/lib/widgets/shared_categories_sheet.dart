import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/share/share_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/partner_look.dart';
import '../models/share_overview.dart';
import '../utils/share_copy.dart';
import 'form_rows.dart';
import 'shared_category_sheet.dart';

/// The received list's order (decision df): the partner's own categories
/// first, by name, then the shared built-ins in the order of my Categories
/// page — [mine] is my categories as that page has them (In use, then
/// Archived, each by its stored order). A built-in [mine] does not hold
/// goes last, as the overview listed it.
///
/// By name, not by the order the partner keeps them in: the reader stores
/// every category of theirs at order 0 — their order is no place in this
/// person's list — so the stored order would sort them by id. It is the
/// catalogue's own rule for a partner's (`CalendarCategories.partner`), so
/// this sheet, the Categories page and the filters list them alike.
///
/// The order is the categories', never the switches': a row does not move
/// when its switch flips.
List<PartnerSharedCategory> orderSharedCategories(
  List<PartnerSharedCategory> shared,
  List<CalendarCategory> mine,
) {
  final own = [
    for (final entry in shared)
      if (!entry.joinsMine) entry,
  ];
  own.sort((a, b) {
    final byName = a.category.name.toLowerCase().compareTo(
      b.category.name.toLowerCase(),
    );
    return byName != 0 ? byName : a.category.id.compareTo(b.category.id);
  });
  final pageOrder = [
    for (final c in mine)
      if (!c.fromPartner && !c.isHidden) c.id,
    for (final c in mine)
      if (!c.fromPartner && c.isHidden) c.id,
  ];
  final position = {for (final (i, id) in pageOrder.indexed) id: i};
  final builtIns = [
    for (final entry in shared)
      if (entry.joinsMine) entry,
  ];
  final unplaced = pageOrder.length;
  final indexed = [...builtIns.indexed];
  indexed.sort((a, b) {
    final byPage = (position[a.$2.category.id] ?? unplaced).compareTo(
      position[b.$2.category.id] ?? unplaced,
    );
    return byPage != 0 ? byPage : a.$1.compareTo(b.$1);
  });
  return [...own, for (final (_, entry) in indexed) entry];
}

/// What the partner shares with me, category by category (share surfaces
/// §6.4, the slice D spec §2): each row's switch shows it on my calendar or
/// hides it — the partner never learns which. An own category's row opens
/// [SharedCategorySheet]; a shared built-in's row is its switch, since my
/// own category editor governs the rest of it (decision dm).
///
/// Rows are the bloc's state and nothing else: a flip is drawn when the
/// bloc says it holds.
class SharedCategoriesSheet extends StatelessWidget {
  final ShareBloc bloc;
  final PartnerLook partner;

  const SharedCategoriesSheet({
    super.key,
    required this.bloc,
    required this.partner,
  });

  /// [bloc] is the Sharing page's, which lists the categories and takes the
  /// switches; [partner] is the page's look, which the avatars draw in, and
  /// who the partner is, whom the title and the caption name.
  ///
  /// A filler (decision da): the list can change under the open sheet when
  /// a shared read lands, and a content-tall box would move its header.
  static Future<void> show(
    BuildContext context, {
    required ShareBloc bloc,
    required PartnerLook partner,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
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
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: SharedCategoriesSheet(bloc: bloc, partner: partner),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = ShareCopy.partnerName(l10n, partner.name);
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return Semantics(
      container: true,
      identifier: SemanticsIds.sharedCategoriesSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          // The name may be cut here at large text; the caption under it
          // names the person whole (decision dd).
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.close,
            onLeading: () => Navigator.of(context).pop(),
            title: l10n.shareTheirCategoriesTitle(name),
            trailingInset: FormMetrics.headerActionInset,
            trailing: const SizedBox.shrink(),
            stackTitleAtLargeText: true,
            titleIsHeading: true,
          ),
          FormCaption(
            text: l10n.shareTheirCategoriesCaption(name),
            padding: const EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              0,
              RowMetrics.groupInset,
              FormMetrics.headerCaptionBottomPadding,
            ),
          ),
          Expanded(
            child: BlocBuilder<ShareBloc, ShareState>(
              bloc: bloc,
              builder: (context, state) {
                final shared = state is ShareLoaded
                    ? orderSharedCategories(
                        state.overview.partnerCategories,
                        CalendarCategories.all,
                      )
                    : const <PartnerSharedCategory>[];
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    RowMetrics.groupInset,
                    FormMetrics.bodyTop,
                    RowMetrics.groupInset,
                    FormMetrics.bodyBottom + clearance,
                  ),
                  child: shared.isEmpty
                      ? FormCaption(
                          text: l10n.shareNone,
                          padding: FormMetrics.groupCaptionPadding,
                        )
                      : FormRowGroup(
                          trailingGap: false,
                          children: [
                            for (final entry in shared)
                              _row(context, l10n, entry),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    PartnerSharedCategory entry,
  ) {
    final id = entry.category.id;
    // A shared built-in draws as mine — my colour, my icon, my label —
    // since its events join my category of that id (D14).
    final category = entry.joinsMine
        ? CalendarCategories.resolve(id)
        : entry.category;
    final label = CalendarCategories.labelOf(category, l10n);
    final count = l10n.categoryEventCount(entry.eventCount);
    Widget avatar = sharedCategoryAvatar(category, partner);
    // Hidden dims the avatar alone; the text stays readable and the switch
    // carries the state (decision de).
    if (!entry.shown) {
      avatar = Opacity(opacity: FormMetrics.disabledOpacity, child: avatar);
    }
    void setShown(bool shown) =>
        bloc.add(ShareCategoryShownSet(id, shown: shown));
    if (entry.joinsMine) {
      return FormPickerSwitchRow(
        key: ValueKey(id),
        leading: avatar,
        label: label,
        caption: '$count · ${l10n.shareJoinsYours(label)}',
        captionMaxLines: FormMetrics.receivedCaptionMaxLines,
        value: entry.shown,
        onTap: null,
        onChanged: setShown,
        switchIdentifier: SemanticsIds.sharedCategoryShow(id),
      );
    }
    return FormPickerSwitchRow(
      key: ValueKey(id),
      leading: avatar,
      label: label,
      caption: count,
      captionMaxLines: FormMetrics.receivedCaptionMaxLines,
      value: entry.shown,
      onTap: () => SharedCategorySheet.show(
        context,
        bloc: bloc,
        categoryId: id,
        partner: partner,
      ),
      onChanged: setShown,
      switchSemanticsLabel: l10n.shareShowCategoryOnCalendar(label),
      identifier: SemanticsIds.sharedCategoryRow(id),
      switchIdentifier: SemanticsIds.sharedCategoryShow(id),
    );
  }
}
