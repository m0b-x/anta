import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart';
import '../models/app_user.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/folder.dart';
import '../models/note_metadata.dart';
import '../models/partner_look.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import 'agenda_day_list_rows.dart';
import 'content_rows.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'note_row.dart' show formatRowDate;
import 'row_share_mark.dart';
import 'settings_reorder.dart';

/// What the sharing cards of the sync book (`docs/guide-hub-roadmap.md`
/// §11.4) draw on their phones: the phones' marks, the two ways a phone
/// names the other person, and the app's rows — a category as the
/// Categories page draws it, a folder and a note as the browser does, a
/// day's events as the day list does — fed the card's world instead of a
/// bloc, so a tap stays on the stage (D41, D56).
///
/// The rows sit in the card's own `FormRowGroup`s rather than on
/// `ContentRowShell`, as the calendar guide's categories card does: the
/// shell's 16 dp side insets are the page's margin to the screen edge,
/// which the stage already gives.
abstract final class GuideShareLooks {
  /// Her phone's mark (§11.8 G).
  static Widget herMark(BuildContext context) => Icon(
    Icons.smartphone_rounded,
    size: GuideMetrics.phoneMarkSize,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  /// The mark of Sam's phone: his initial on the app's avatar disc, at the
  /// partner avatar's size and in its tokens. The app draws a partner with
  /// no picture as the person glyph, which on this stage is already the
  /// faceless "from you" mark on Sam's rows ([fromYou]) — so the guide's
  /// own bar draws a letter, and the glyph means only her. The letter takes
  /// the bar title's type, unscaled: the disc is a fixed 20 dp.
  static Widget samMark(AppLocalizations l10n) => Builder(
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return CircleAvatar(
        radius: RowMetrics.partnerAvatarRadius,
        backgroundColor: colorScheme.primaryContainer,
        child: Text(
          l10n.syncGuideDemoPartner.characters.first,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: RowMetrics.secondLineFontSize,
            fontWeight: FontWeight.w500,
            color: colorScheme.primary,
          ),
        ),
      );
    },
  );

  static AppUser sam(AppLocalizations l10n) => AppUser(
    uid: '${GuideDemoCalendar.idPrefix}sam',
    displayName: l10n.syncGuideDemoPartner,
  );

  /// How her phone draws what she shares with Sam.
  static PartnerLook toSam(AppLocalizations l10n) =>
      PartnerLook(name: l10n.syncGuideDemoPartner);

  /// Her, as Sam's phone names her: "you", in the case "From {name}" takes
  /// (D45), faceless: the guide has no picture of the reader, so a row that
  /// draws a face draws the person glyph a phone shows before the partner's
  /// picture is read.
  static PartnerLook fromYou(AppLocalizations l10n) =>
      PartnerLook(name: l10n.syncGuideDemoYou);
}

/// [events] as the day list draws them on [day] (`AgendaDayListRowBuilder`),
/// read through [look] — hers with the share sign on [sharedByMe], or Sam's
/// with each marked as from her. [onTap] makes each row a tap; [selected]
/// draws that row on the wash Material selects with, the flag on the row's
/// own node.
///
/// A stage's events are one-offs on one day, so a row's second line is the
/// event's time alone — written as the read sheet writes it
/// ([EventTimeFormatter.formatRangeOfContext]), so a card never shows one
/// event at two clocks.
List<Widget> guideShareDayRows(
  BuildContext context, {
  required DateTime day,
  required List<CalendarEvent> events,
  required PartnerLook look,
  Set<String> sharedByMe = const {},
  String Function(String eventId)? identifier,
  ValueChanged<String>? onTap,
  String? selected,
}) {
  final l10n = AppLocalizations.of(context)!;
  final builder = AgendaDayListRowBuilder(
    rows: const [],
    today: day,
    onEntryTap: onTap == null ? null : (entry) => onTap(entry.eventId!),
    rowIdentifier: identifier == null
        ? null
        : (entry) => identifier(entry.eventId!),
    partnerLook: look,
  );
  final summaries = EventSummaryProvider(l10n, showRecurrence: false);
  AgendaDayListEntry entryOf(CalendarEvent event) {
    final summary = summaries.entryFor(event, day);
    final time = event.time;
    return AgendaDayListEntry(
      day: day,
      icon: summary.icon,
      color: summary.color,
      title: summary.title,
      subtitle: time == null
          ? summary.subtitle
          : EventTimeFormatter.formatRangeOfContext(time, context),
      eventId: event.id,
      categoryId: event.categoryId,
      fromPartner: event.fromPartner,
      sharedByMe: sharedByMe.contains(event.id),
    );
  }

  final wash = Theme.of(context).colorScheme.secondaryContainer;
  Widget rowOf(CalendarEvent event) {
    final row = builder.entryRow(context, entryOf(event));
    if (event.id != selected) return row;
    // The outer merge folds the flag into the row's one node, beside its id
    // and its label; the group reads the divider's indent off the wrapper.
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentTitle,
      child: MergeSemantics(
        child: Semantics(
          selected: true,
          child: ColoredBox(color: wash, child: row),
        ),
      ),
    );
  }

  return [for (final event in events) rowOf(event)];
}

/// The leading of a category or partner row narrows to the bare glyph from
/// [RowMetrics.compactLeadingTextScale] up, as the Categories page's does.
bool _compactLeading(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler.scale(RowMetrics.titleFontSize) / RowMetrics.titleFontSize >=
      RowMetrics.compactLeadingTextScale;
}

/// One of her categories as the Categories page lays it out — the handle,
/// the avatar wearing the share sign while shared, the name over its
/// caption, the ⋮ — with the page's one node per row and the ⋮ a sibling.
/// The handle is inert: the stage keeps no order to drag.
class GuideShareCategoryRow extends FormDividedRow {
  const GuideShareCategoryRow({
    super.key,
    required this.category,
    required this.caption,
    required this.spokenCaption,
    required this.shared,
    this.captionReserve,
    this.identifier,
    this.onMenu,
    this.menuIdentifier,
  });

  final CalendarCategory category;
  final String caption;

  /// The tallest caption the row may come to show — shared, its count at
  /// its highest — held from the first frame in a caption slot, so a share
  /// or an added event that wraps the caption moves no row below it.
  final String? captionReserve;

  /// [caption] as the node says it — "Shared" names Sam there, since the
  /// avatar's sign is excluded from the node.
  final String spokenCaption;
  final bool shared;
  final String? identifier;

  /// Opens the row's menu at its ⋮; null draws the row without one.
  final void Function(BuildContext anchor)? onMenu;
  final String? menuIdentifier;

  @override
  double get dividerIndent => RowMetrics.reorderAvatarTextInset;

  @override
  double dividerIndentIn(BuildContext context) => _compactLeading(context)
      ? RowMetrics.reorderGlyphTextInset
      : RowMetrics.reorderAvatarTextInset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = CalendarCategories.labelOf(category, l10n);
    final icon = CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
    // The compact row's bare glyph carries no sign: its caption's "Shared"
    // says it, as on the page.
    final leading = _compactLeading(context)
        ? ExcludeSemantics(
            child: Icon(
              icon,
              size: RowMetrics.glyphSize,
              color: category.color,
            ),
          )
        : EventAvatar(
            icon: icon,
            color: category.color,
            badge: shared ? EventAvatarBadge.mine : null,
          );
    final menu = onMenu;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            identifier: identifier,
            label: [name, spokenCaption].join('\n'),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: RowMetrics.twoLineMinHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: RowMetrics.reorderHandleLead,
                  ),
                  child: Row(
                    children: [
                      const ReorderHandle(),
                      leading,
                      const SizedBox(width: RowMetrics.gap),
                      Expanded(
                        child: _TwoLines(
                          title: name,
                          titleWeight: FontWeight.w400,
                          second: TextSpan(text: caption),
                          reserve: [
                            if (captionReserve case final reserve?)
                              TextSpan(text: reserve),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (menu != null)
          Builder(
            builder: (anchor) => FormTrailingButton(
              icon: Icons.more_vert_rounded,
              tooltip: l10n.categoryActions,
              identifier: menuIdentifier,
              onPressed: () => menu(anchor),
            ),
          )
        else
          const SizedBox(width: RowMetrics.groupInset),
      ],
    );
  }
}

/// A folder as the browser's row draws it (`FolderRow`): the folder glyph,
/// the name, the share sign or the partner's face ([mark]) before the count
/// and chevron, read first on the row. [count] null leaves the count and
/// chevron off; [opens] false keeps the count and leaves the chevron's room
/// blank — a row that opens nothing here, its count still in line with its
/// neighbours'; [onMenu] puts the folder's ⋮ at its end.
class GuideShareFolderRow extends FormDividedRow {
  const GuideShareFolderRow({
    super.key,
    required this.folder,
    required this.mark,
    this.count,
    this.opens = true,
    this.onTap,
    this.identifier,
    this.onMenu,
    this.menuIdentifier,
  });

  final Folder folder;
  final RowShareMark? mark;
  final int? count;
  final bool opens;
  final VoidCallback? onTap;
  final String? identifier;
  final void Function(BuildContext anchor)? onMenu;
  final String? menuIdentifier;

  @override
  double get dividerIndent => RowMetrics.dividerIndentWithGlyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sign = mark?.trailing(context);
    final count = this.count;
    final menu = onMenu;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: RowMetrics.singleLineMinHeight,
      ),
      child: Padding(
        padding: menu == null
            ? RowMetrics.singleLinePadding
            : const EdgeInsets.only(left: RowMetrics.groupInset),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: RowMetrics.glyphSize,
              color: AppColors.folderIcon(context),
            ),
            const SizedBox(width: RowMetrics.gap),
            Expanded(
              child: Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: RowMetrics.titleFontSize,
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (sign != null) ...[const SizedBox(width: RowMetrics.gap), sign],
            if (count != null) ...[
              SizedBox(
                width: sign == null ? RowMetrics.gap : RowMetrics.shareMarkGap,
              ),
              if (opens)
                RowCountChevron(count: count)
              else
                _CountOnly(count: count),
            ],
          ],
        ),
      ),
    );
    final labelled = mark?.labelled(content) ?? content;
    final tap = onTap;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            container: true,
            identifier: identifier,
            child: tap == null
                ? MergeSemantics(child: labelled)
                : InkWell(onTap: tap, child: labelled),
          ),
        ),
        if (menu != null)
          Builder(
            builder: (anchor) => FormTrailingButton(
              icon: Icons.more_vert_rounded,
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              identifier: menuIdentifier,
              onPressed: () => menu(anchor),
            ),
          ),
      ],
    );
  }
}

/// A note as the browser's row draws it (`NoteRow`): the title over its
/// edit date, the partner's face leading the date on a partner's note, its
/// "From {name}" read first.
class GuideShareNoteRow extends FormDividedRow {
  const GuideShareNoteRow({
    super.key,
    required this.note,
    required this.mark,
    required this.now,
    this.onTap,
    this.identifier,
    this.wrapTitle = false,
  });

  final NoteMetadata note;
  final RowShareMark? mark;
  final DateTime now;
  final VoidCallback? onTap;
  final String? identifier;

  /// The title and date wrap rather than cut at one line, as the browser's
  /// row does: for a stage whose lesson is the title itself — a conflict
  /// copy's, which names the moment it was filed.
  final bool wrapTitle;

  @override
  double get dividerIndent => RowMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final date = formatRowDate(
      date: note.updatedAt,
      now: now,
      locale: Localizations.localeOf(context).toString(),
      l10n: l10n,
    );
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RowMetrics.twoLineMinHeight),
      child: Padding(
        padding: RowMetrics.twoLinePadding,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: _TwoLines(
            title: note.title.isEmpty ? l10n.untitledNote : note.title,
            titleWeight: FontWeight.w500,
            singleLine: !wrapTitle,
            second: TextSpan(
              children: [
                ?mark?.inlineFace(),
                TextSpan(
                  text: date,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final labelled = mark?.labelled(content) ?? content;
    return Semantics(
      container: true,
      identifier: identifier,
      child: InkWell(onTap: onTap, child: labelled),
    );
  }
}

/// [RowCountChevron]'s count with the chevron's room kept blank, for a
/// folder row that opens nothing on the stage.
class _CountOnly extends StatelessWidget {
  const _CountOnly({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: RowMetrics.countMinWidth),
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            maxLines: 1,
            style: TextStyle(
              fontSize: RowMetrics.countFontSize,
              color: Theme.of(context).colorScheme.outline,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: RowMetrics.gap + RowMetrics.chevronSize),
      ],
    );
  }
}

/// A row's title over its second line in the browser's two type roles.
class _TwoLines extends StatelessWidget {
  const _TwoLines({
    required this.title,
    required this.titleWeight,
    required this.second,
    this.singleLine = false,
    this.reserve = const [],
  });

  final String title;
  final FontWeight titleWeight;
  final InlineSpan second;

  /// One line each, cut with an ellipsis, as a note row's are.
  final bool singleLine;

  /// Second lines the row may come to show, whose room [second] keeps
  /// ([FormCaptionSlot]).
  final List<InlineSpan> reserve;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget secondLine(InlineSpan span) => Text.rich(
      span,
      maxLines: singleLine ? 1 : null,
      overflow: singleLine ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: RowMetrics.secondLineFontSize,
        height: singleLine
            ? null
            : FormMetrics.captionLineHeight / RowMetrics.secondLineFontSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: singleLine
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              vertical: RowMetrics.twoLinePadding.vertical / 2,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: singleLine ? 1 : null,
            overflow: singleLine ? TextOverflow.ellipsis : null,
            style: TextStyle(
              fontSize: RowMetrics.titleFontSize,
              fontWeight: titleWeight,
              height: singleLine
                  ? null
                  : FormMetrics.labelLineHeight / RowMetrics.titleFontSize,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: RowMetrics.lineGap),
          if (reserve.isEmpty)
            secondLine(second)
          else
            FormCaptionSlot(
              candidates: [for (final span in reserve) secondLine(span)],
              child: secondLine(second),
            ),
        ],
      ),
    );
  }
}
