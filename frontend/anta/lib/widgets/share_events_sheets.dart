import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../bloc/share/share_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_categories.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/partner_look.dart';
import '../models/share_overview.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../services/share_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/event_agenda.dart';
import '../utils/share_copy.dart';
import 'agenda_list_view.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';

/// Opens an event's sheets from a row — `EventSheetsFlow.openDetail`, whose
/// door sends my own event to its detail sheet and a partner's to its read
/// sheet (§6.9).
typedef ShareEventOpener =
    Future<void> Function(
      BuildContext context,
      CalendarEvent event,
      DateTime day,
    );

/// The events I share one by one, from the Sharing page's YOU SHARE section
/// (`docs/cloud-share-surfaces-roadmap.md` §6.2; the slice C spec §4): each
/// row's ✕ takes the event's own mark away at once, with Undo, and the row
/// leaves.
///
/// A filler: a list that shrinks under the finger would change a
/// content-tall sheet's height on every ✕, so the box is the editor's.
class MySharedEventsSheet extends StatefulWidget {
  final ShareBloc bloc;
  final ShareEventOpener? onOpen;

  /// Resolves the service an Undo writes through once [bloc] has closed;
  /// [ShareService.getInstance] unless a test passes its own.
  final Future<ShareService> Function() shareService;

  const MySharedEventsSheet({
    super.key,
    required this.bloc,
    this.onOpen,
    this.shareService = ShareService.getInstance,
  });

  /// [bloc] is the Sharing page's, which lists the events and takes the ✕;
  /// [onOpen] opens a row's event (the page's `EventSheetsFlow.openDetail`,
  /// on a guard of its own — the slot this sheet holds would refuse it).
  /// Null — the Sharing page's call — makes each row a read row: only its ✕
  /// acts.
  static Future<void> show(
    BuildContext context, {
    required ShareBloc bloc,
    ShareEventOpener? onOpen,
  }) => _showFiller(context, MySharedEventsSheet(bloc: bloc, onOpen: onOpen));

  @override
  State<MySharedEventsSheet> createState() => _MySharedEventsSheetState();
}

class _MySharedEventsSheetState extends State<MySharedEventsSheet> {
  /// Rows whose ✕ was tapped and that the overview still lists: hidden at
  /// once, so the row leaves under the finger rather than when the reload
  /// lands, and shown again by an Undo that was written or a ✕ that failed.
  final Set<String> _leaving = {};

  /// The rows whose Undo the bloc was asked for, oldest first. The bloc runs
  /// its acts in order and none but this sheet's can be asked for while it
  /// is up, so each undo outcome answers the oldest.
  final List<String> _undoing = [];

  /// The last outcome this sheet has seen, so a failure is answered once.
  int? _seenOutcome;

  @override
  void initState() {
    super.initState();
    final state = widget.bloc.state;
    if (state is ShareLoaded) _seenOutcome = state.outcome?.sequence;
  }

  void _unshare(MySharedEvent shared) {
    final bloc = widget.bloc;
    // A sheet left up past the page's close acts on nothing.
    if (!mounted || bloc.isClosed) return;
    final l10n = AppLocalizations.of(context)!;
    // The app's own, which outlives this sheet and the page under it: where
    // an Undo tapped after both have gone says that it failed.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final shareService = widget.shareService;
    final generation = ShareService.databaseGeneration;
    final event = shared.event;
    setState(() => _leaving.add(event.id));
    bloc.add(ShareEventUnshared(event.id));
    // Said at the tap, as every share switch says it (D6): the reload that
    // drops the row may land after the finger has moved on.
    final category = CalendarCategories.byId(event.categoryId);
    final message = shared.categoryShared && category != null
        ? l10n.shareStaysThroughCategory(
            event.title,
            CalendarCategories.labelOf(category, l10n),
          )
        : l10n.shareStopped(event.title);
    CustomSnackbar.showWithAction(
      context,
      message: message,
      actionLabel: l10n.undo,
      actionIdentifier: SemanticsIds.snackbarUndo,
      overSheet: true,
      onAction: () => _undo(
        bloc,
        event,
        generation: generation,
        shareService: shareService,
        messenger: messenger,
        l10n: l10n,
      ),
    );
  }

  /// The snackbar's Undo of [event]'s ✕, which may be tapped after this
  /// sheet and the page that owns [bloc] are gone, so it reads nothing of
  /// the sheet's but [mounted]. While [bloc] is open the undo goes through
  /// it, queued behind the ✕, and the row comes back on its outcome. Once
  /// it is closed the undo writes through [undoSharePastBloc].
  ///
  /// [generation] is the database's when the bar was shown: tapped under
  /// another, the undo would land in a database that never saw the ✕ —
  /// where a built-in category of the same id would be shared without a
  /// switch anyone flipped — so it writes nothing and says nothing.
  void _undo(
    ShareBloc bloc,
    CalendarEvent event, {
    required int generation,
    required Future<ShareService> Function() shareService,
    required ScaffoldMessengerState? messenger,
    required AppLocalizations l10n,
  }) {
    if (ShareService.databaseGeneration != generation) return;
    final change = ShareChange(unsharedEvents: [event]);
    if (!bloc.isClosed) {
      if (mounted) _undoing.add(event.id);
      bloc.add(ShareUndoRequested(change));
      return;
    }
    unawaited(
      undoSharePastBloc(
        change,
        shareService: shareService,
        messenger: messenger,
        l10n: l10n,
      ),
    );
  }

  /// A ✕ the service refused or failed brings its rows back and says why;
  /// a success needs nothing — the overview stops listing the event. An
  /// Undo's row comes back once its undo was written, and stays out, said
  /// over the sheet, when it was not.
  void _onState(BuildContext context, ShareState state) {
    if (state is! ShareLoaded) return;
    final outcome = state.outcome;
    if (outcome == null || outcome.sequence == _seenOutcome) return;
    _seenOutcome = outcome.sequence;
    final failure = outcome.failure;
    switch (outcome.act) {
      case ShareAct.eventUnshared:
        if (failure == null || _leaving.isEmpty) return;
        setState(_leaving.clear);
      case ShareAct.undo:
        if (_undoing.isEmpty) return;
        final id = _undoing.removeAt(0);
        if (failure == null) {
          setState(() => _leaving.remove(id));
          return;
        }
      case ShareAct.categoriesSet || ShareAct.stopAll:
        return;
    }
    final l10n = AppLocalizations.of(context)!;
    OverlaySnackbar.show(
      context,
      failure == ShareFailure.refused
          ? l10n.shareNeedsSync
          : l10n.shareChangeFailed,
      duration: AppConstants.snackbarErrorDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final today = _today();
    final withYear = DateFormat.yMMMd(l10n.localeName);
    return BlocConsumer<ShareBloc, ShareState>(
      bloc: widget.bloc,
      listener: _onState,
      builder: (context, state) {
        final events = [
          if (state is ShareLoaded)
            for (final shared in state.overview.events)
              if (!_leaving.contains(shared.event.id)) shared,
        ];
        return _FillerFrame(
          identifier: SemanticsIds.shareEventsSheet,
          title: l10n.shareRowEvents,
          empty: l10n.shareEventsEmpty,
          rows: [
            for (final shared in events)
              _row(context, l10n, withYear, shared, today),
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    DateFormat withYear,
    MySharedEvent shared,
    DateTime today,
  ) {
    final event = shared.event;
    final day = _dayOf(event, today);
    final category = CalendarCategories.byId(event.categoryId);
    final when = _whenOf(context, l10n, withYear, event, day, today);
    // An event its category shares too stays on the partner's phone after
    // the ✕, and its row says so rather than let the ✕ read as "private".
    final through = shared.categoryShared && category != null
        ? l10n.shareThroughCategory(CalendarCategories.labelOf(category, l10n))
        : null;
    return FormPickerRow(
      leading: _avatar(l10n, event, partner: null),
      label: event.title,
      caption: through == null ? when : '$when\n$through',
      captionWraps: true,
      showChevron: false,
      onTap: switch (widget.onOpen) {
        final open? => () => open(context, event, day),
        null => null,
      },
      trailingButton: FormTrailingButton(
        icon: Icons.close_rounded,
        tooltip: l10n.shareStopSharingTooltip,
        identifier: SemanticsIds.shareEventUnshare(event.id),
        onPressed: () => _unshare(shared),
      ),
    );
  }
}

/// The partner's events that came without a category of theirs, from the
/// Sharing page's "{name} shares with you" section: [MySharedEventsSheet]'s
/// shape, read-only — rows in the partner's look, no ✕. Where the host has
/// event sheets ([onOpen]) a tap opens the event's read sheet; where it has
/// none — Sync & sharing, which holds no calendar — the rows take no tap,
/// as [MySharedEventsSheet]'s do there: a row that looked tappable and did
/// nothing would be a dead end.
class PartnerSharedEventsSheet extends StatelessWidget {
  final ShareBloc bloc;
  final PartnerLook partner;
  final ShareEventOpener? onOpen;

  const PartnerSharedEventsSheet({
    super.key,
    required this.bloc,
    required this.partner,
    this.onOpen,
  });

  /// [partner] is the page's look for a partner's event, and who the
  /// partner is: the rows draw in it and the caption names them.
  static Future<void> show(
    BuildContext context, {
    required ShareBloc bloc,
    required PartnerLook partner,
    ShareEventOpener? onOpen,
  }) => _showFiller(
    context,
    PartnerSharedEventsSheet(bloc: bloc, partner: partner, onOpen: onOpen),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final today = _today();
    final withYear = DateFormat.yMMMd(l10n.localeName);
    return BlocBuilder<ShareBloc, ShareState>(
      bloc: bloc,
      builder: (context, state) {
        final events = state is ShareLoaded
            ? state.overview.partnerEvents
            : const <CalendarEvent>[];
        return _FillerFrame(
          identifier: SemanticsIds.sharedEventsSheet,
          title: l10n.shareRowEvents,
          // The name goes under the title, never into it: a long one cut
          // the title at large text (decision aa).
          caption: l10n.shareFromPartner(
            ShareCopy.partnerName(l10n, partner.name),
          ),
          empty: l10n.shareNone,
          rows: [
            for (final event in events)
              () {
                final day = _dayOf(event, today);
                return FormPickerRow(
                  leading: _avatar(l10n, event, partner: partner),
                  label: event.title,
                  caption: _whenOf(context, l10n, withYear, event, day, today),
                  captionWraps: true,
                  showChevron: false,
                  onTap: switch (onOpen) {
                    final open? => () => open(context, event, day),
                    null => null,
                  },
                );
              }(),
          ],
        );
      },
    );
  }
}

/// An Undo tapped once the surface that offered it has gone with its bloc —
/// the events sheet's or the Sharing page's: it writes through
/// [ShareService.undo] itself, the one place a sharing surface acts past
/// its bloc, since nothing is left to act through. A failure is said on
/// [messenger], the app's own captured when the bar was shown, as a plain
/// floating bar: no context that has gone is read and no host Scaffold is
/// looked for, which over a bottom route that does not resize would reach
/// for an overlay from above it.
Future<void> undoSharePastBloc(
  ShareChange change, {
  required Future<ShareService> Function() shareService,
  required ScaffoldMessengerState? messenger,
  required AppLocalizations l10n,
}) async {
  String? failure;
  try {
    await (await shareService()).undo(change);
  } on ShareRefused {
    failure = l10n.shareNeedsSync;
  } catch (e, st) {
    debugPrint('[undoSharePastBloc] undo failed: $e\n$st');
    failure = l10n.shareChangeFailed;
  }
  if (failure == null) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(failure),
        behavior: SnackBarBehavior.floating,
        margin: AppSpacing.snackbarMargin(),
        duration: AppConstants.snackbarErrorDuration,
        showCloseIcon: true,
      ),
    );
}

/// The filler box both lists open in: the editor's fixed height, the
/// route's own drag, nothing to guard — every ✕ writes at once.
Future<void> _showFiller(BuildContext context, Widget sheet) {
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
      child: sheet,
    ),
  );
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day);
}

/// The day a row names and opens on: the next occurrence from today within
/// the agenda's range, or — an event whose days are all behind it — its
/// start.
DateTime _dayOf(CalendarEvent event, DateTime today) {
  for (var i = 0; i < EventAgenda.maxRangeDays; i++) {
    final day = today.add(Duration(days: i));
    if (event.occursOn(day)) return day;
  }
  return event.startDateUtc;
}

/// The day a shared event's row names: the agenda's own words — "Today",
/// "Tomorrow", "Aug 25" — except that a day behind [today] (an event with
/// no coming occurrence) or in another year carries its year in
/// [withYear], which the short date leaves out: a one-off more than a year
/// ahead read as the coming one. Today and tomorrow keep their words
/// whatever the year, so the last day of a year still says "Tomorrow".
@visibleForTesting
String shareEventDayLabel(
  AppLocalizations l10n,
  DateFormat withYear,
  DateTime day,
  DateTime today,
) {
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final soon = day == today || day == tomorrow;
  if (!soon && (day.isBefore(today) || day.year != today.year)) {
    return withYear.format(day);
  }
  return AgendaListView.shortDayLabel(l10n, day, today);
}

/// "Tomorrow · 18:00 – 19:00": [shareEventDayLabel] and the event's time.
String _whenOf(
  BuildContext context,
  AppLocalizations l10n,
  DateFormat withYear,
  CalendarEvent event,
  DateTime day,
  DateTime today,
) {
  final date = shareEventDayLabel(l10n, withYear, day, today);
  final time = event.time;
  if (time == null) return date;
  return '$date · ${EventTimeFormatter.formatRangeOfContext(time, context)}';
}

EventAvatar _avatar(
  AppLocalizations l10n,
  CalendarEvent event, {
  required PartnerLook? partner,
}) => EventAvatar.ofRow(
  icon: CalendarCategories.iconFor(event),
  color: EventSummaryProvider.colorFor(
    event,
    CalendarCategories.resolve(event.categoryId),
  ),
  partner: partner,
  l10n: l10n,
);

/// The two lists' one frame: handle, a header with ✕ and no action — a list
/// that writes at once has nothing to confirm — the optional caption pinned
/// under it, and the rows, or the one line that says there are none.
class _FillerFrame extends StatelessWidget {
  final String identifier;
  final String title;
  final String? caption;
  final String empty;
  final List<Widget> rows;

  const _FillerFrame({
    required this.identifier,
    required this.title,
    required this.empty,
    required this.rows,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final caption = this.caption;
    return Semantics(
      container: true,
      identifier: identifier,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.close,
            onLeading: () => Navigator.of(context).pop(),
            title: title,
            // A heading, as the read sheet's: a screen reader's headings
            // list then holds every share sheet by its name.
            titleIsHeading: true,
            trailingInset: FormMetrics.headerActionInset,
            trailing: const SizedBox.shrink(),
            stackTitleAtLargeText: true,
          ),
          if (caption != null)
            FormCaption(
              text: caption,
              padding: const EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                0,
                RowMetrics.groupInset,
                FormMetrics.headerCaptionBottomPadding,
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: rows.isEmpty
                  ? FormCaption(
                      text: empty,
                      padding: FormMetrics.groupCaptionPadding,
                    )
                  : FormRowGroup(trailingGap: false, children: rows),
            ),
          ),
        ],
      ),
    );
  }
}
