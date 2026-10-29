import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/alarm_metrics.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../controllers/alert_ring_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';
import '../services/app_navigator.dart';
import '../services/event_time_formatter.dart';
import '../services/lock_screen_state.dart';
import '../widgets/alarm_ground.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/automation_id.dart';
import '../widgets/event_avatar.dart';
import '../widgets/form_rows.dart';

/// The full-screen surface an alarm rings on (**§5.5**), redrawn in 2026-10
/// as the UI language's takeover page: one large time, one read-only row
/// group that names the event as its detail sheet names it, and a pinned
/// pair of buttons. The record is
/// `docs/alert-surfaces-redesign-roadmap.md`.
///
/// **Everything that matters sits low.** With the phone in use Android draws
/// the ring's own notification as a heads-up across the top of this page,
/// and the top is also where a thumb does not reach. So the content is
/// anchored to the bottom — a reversed scroll view resting on the dock — and
/// when it is taller than the screen it is the eyebrow and the time that
/// leave through the top, which the heads-up repeats anyway.
///
/// **It renders from the payload alone.** No service and no database read, and
/// the category facade only as the avatar's fallback for an entry armed before
/// the payload carried its tint and glyph, stand between the ring and the
/// screen: an alarm belonging to a database the user is not currently in still
/// has to show a title, a colour and a time (**A9**), and an alarm recovered
/// after a reboot arrives in a process where nothing is loaded yet. What is
/// resolved afterwards is which database is open, and it decides two things:
/// whether the Open row opens the event or switches to its database, and
/// whether the page may say that Stop removes the event. With it, in the same
/// notification, comes what that event says now: one kept since the alarm was
/// armed reads "kept" from the row's first drawing
/// (`AlertRingController.load`).
///
/// **Which rows exist is a payload fact, settled on the first frame.** What
/// arrives later changes a text, a glyph or an enabled flag, never a
/// position: a button that moved as the database name came in, or as Keep
/// was pressed, would move under a thumb already on its way.
///
/// Pushed with `AppNavigator.rootPushInstant` and **never stamped as a
/// `NavDestination`**: a restored last location must not reopen a ring that is
/// long over.
///
/// `PopScope(canPop: false)` because back is not Stop. An alarm is stopped
/// deliberately or not at all, and a back gesture that silenced it would be
/// the easiest thing in the world to do in one's sleep.
///
/// It resumes the app, so it inherits the stale-inset hazard the UX section
/// describes. It has no text field and raises no keyboard; an inset left
/// behind by the page underneath is taken by the `Scaffold`, which lifts the
/// body — and with it the dock — clear of it.
///
/// **It is the one surface allowed on a locked phone.** A ring lifts the whole
/// activity above the keyguard, so the page tells [LockScreenState] whenever
/// it is the topmost page route and whenever it stops being one;
/// `LockScreenCurtain` hides everything else for as long as the phone stays
/// locked. A dialog the page raises is a popup route and leaves it on top.
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.payload, this.controller})
    : _preview = false;

  /// The real page over a demo [payload], for the calendar guide: drawn as a
  /// ring of the open database draws it, but Stop, Snooze, Keep and Open
  /// event only close it, nothing is armed, stopped or written, and the page
  /// never reports itself to [LockScreenState] — a preview that did would
  /// lift the lock-screen curtain. Back closes it, as any page: the real
  /// page refuses back so a ring cannot be silenced by accident, and there
  /// is no ring here to protect.
  ///
  /// Push it on its own page route: the buttons close the page by taking
  /// that route off the navigator, and a sheet or dialog route is not one
  /// the page can name — it falls back to `maybePop`, which closes whatever
  /// is on top.
  const AlarmPage.preview({super.key, required this.payload})
    : controller = null,
      _preview = true;

  final AlertPayload payload;

  final bool _preview;

  /// A controller the page renders instead of building its own.
  ///
  /// Test-only, and the caller owns it: the page disposes only a controller it
  /// created. The alternative would be a widget test that cannot reach the
  /// database switch or the remove row at all, since which database is open
  /// is the one thing the payload cannot say.
  @visibleForTesting
  final AlertRingController? controller;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with RouteAware {
  late final AlertRingController _controller =
      widget.controller ??
      (widget._preview
          ? _PreviewRingController(widget.payload)
          : AlertRingController(payload: widget.payload));

  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute || identical(route, _route)) return;
    final previous = _route;
    _route = route;
    // The route is still needed by [_close]; only the lock-screen reports
    // the subscription drives are left out.
    if (widget._preview) return;
    if (previous != null) AppNavigator.routeObserver.unsubscribe(this);
    AppNavigator.routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    if (!widget._preview) {
      AppNavigator.routeObserver.unsubscribe(this);
      LockScreenState.instance.alarmSurfaceHidden(this);
    }
    _controller.removeListener(_onControllerChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  void didPush() => LockScreenState.instance.alarmSurfaceShown(this);

  @override
  void didPopNext() => LockScreenState.instance.alarmSurfaceShown(this);

  @override
  void didPushNext() => LockScreenState.instance.alarmSurfaceHidden(this);

  @override
  void didPop() => LockScreenState.instance.alarmSurfaceHidden(this);

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.endedElsewhere) {
      _close();
      return;
    }
    setState(() {});
  }

  bool _closed = false;

  /// Takes **this page's own route** off the navigator, wherever it stands.
  ///
  /// Not "pop": pop removes whatever is on top, and this page is not always
  /// it. Two alarms due in one minute put two pages on the navigator — the
  /// plugin sounds one and holds the other, but the app hears of both within
  /// a second — and the one underneath is as likely to close first as the
  /// one on top: its ring is the one sounding, so it is the one stopped on
  /// the heads-up. A pop from it took the other ring's page and left itself
  /// behind, dead, Stop and Snooze spent and back disabled, with the phone
  /// still ringing. The dialog the database switch raises was the other
  /// casualty.
  ///
  /// Popped when it is the top route, so it leaves as any page does and the
  /// page under it hears `didPopNext`; removed outright from underneath
  /// another route, which completes this route's future just the same —
  /// `main.dart` drains the intents a ring held back from it.
  void _close() {
    if (_closed) return;
    _closed = true;
    final route = _route;
    final navigator = route?.navigator;
    if (route == null && widget._preview) {
      // A preview hosted off a page route still owes the guide a way out.
      Navigator.of(context).maybePop();
      return;
    }
    if (route == null || navigator == null) return;
    if (route.isCurrent) {
      if (navigator.canPop()) navigator.pop();
      return;
    }
    // Under another route with nothing beneath it there is no app to go back
    // to; the same rule `canPop` is for the top route.
    if (!route.isFirst) navigator.removeRoute(route);
  }

  Future<void> _stop() async {
    await _controller.stop();
    if (mounted) _close();
  }

  Future<void> _snooze() async {
    await _controller.snooze();
    if (mounted) _close();
  }

  /// Whether the Open row is already being answered.
  ///
  /// Its first step is an unlock, which on a locked phone is a PIN prompt
  /// that stays up for as long as the user takes; the page looks unchanged
  /// underneath, and a second tap would ask the keyguard again and then
  /// stop, or switch, twice. One flag over both of the row's faces — not
  /// the controller's `busy`, which would switch Stop off while the phone is
  /// still ringing behind a prompt.
  bool _opening = false;

  Future<void> _open(Future<void> Function() action) async {
    if (_opening) return;
    _opening = true;
    try {
      await action();
    } finally {
      _opening = false;
    }
  }

  /// Stops first, then opens the day the occurrence belongs to. Stopping is
  /// unconditional: leaving the ring going behind the calendar would be the
  /// one way out of this screen that does not silence the phone.
  Future<void> _openEvent() async {
    if (!await _controller.unlock() || !mounted) return;
    // Read before Stop, which is what carries out the removal (**A3**): an
    // event that Stop deletes is opened on its day alone, where the Undo
    // snackbar is, rather than as a detail sheet over a tombstone.
    final removed = _controller.willRemoveEvent;
    await _controller.stop();
    if (!mounted) return;
    _close();
    await AppNavigator.toCalendarOccurrence(
      day: widget.payload.dayUtc,
      eventId: removed ? null : widget.payload.eventId,
    );
  }

  Future<void> _openDatabase() async {
    final l10n = AppLocalizations.of(context)!;
    final database = widget.payload.database;
    if (!await _controller.unlock() || !mounted) return;
    final switched = await _controller.activateDatabase();
    if (!mounted || !switched) return;
    // A database cannot be swapped under a running process, so the user is
    // told what has happened and what is left to do, and the one button
    // closes the app. The ring is not stopped: it is still theirs to stop,
    // from its notification.
    await AppDialogs.action(
      context,
      title: l10n.alarmDatabaseSwitchedTitle(database),
      content: l10n.alarmDatabaseSwitchedBody,
      actionText: l10n.exitApp,
      icon: Icons.restart_alt_rounded,
      onAction: () => SystemNavigator.pop(),
    );
  }

  /// The instant this ring was due, or null on an entry armed before the
  /// payload carried one.
  DateTime? get _dueAt {
    final fireAtMs = widget.payload.fireAtMs;
    if (fireAtMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(fireAtMs);
  }

  /// The due time on the clock the phone is on, in the app's language — or,
  /// for an entry that carries no instant, the label frozen when it was
  /// armed, which is all there is.
  String _timeLabel(BuildContext context) {
    final dueAt = _dueAt;
    if (dueAt == null) return widget.payload.timeLabel;
    return EventTimeFormatter.formatMinute(
      dueAt.hour * Duration.minutesPerHour + dueAt.minute,
      context,
    );
  }

  /// The day that time is on, spelled in the app's locale: the day this ring
  /// was due, which for an alert a day ahead — or one snoozed past midnight —
  /// is not the occurrence's. An entry with no instant has only the
  /// occurrence's day to show.
  ///
  /// Built per open rather than cached per locale like the agenda's
  /// formatters: this page is shown once per ring, so the cache would only
  /// ever hold one entry.
  String _dayLabel(BuildContext context) {
    final day = _dueAt ?? widget.payload.dayUtc;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.MMMMEEEEd(
      locale,
    ).format(DateTime(day.year, day.month, day.day));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: widget._preview,
      child: AlarmGround(
        // The page scopes its own route for a screen reader. A
        // `MaterialPageRoute` does that for the page it builds; the bare
        // route `rootPushInstant` pushes this one on does not, and Android
        // announces a screen only from a node that scopes a route — the
        // eyebrow's `namesRoute` under no scope names nothing, and the page
        // opened to silence.
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              bottom: false,
              // Inside the `Scaffold`'s body, which is where the insets
              // have their final values: a keyboard inset is already out of
              // the height, and out of the bottom padding the dock reads.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final content = _buildContent(context, l10n);
                  final dock = _buildDock(context, l10n);
                  // Too short to pin anything: the dock becomes the end of
                  // the scroll, still what the page rests on. The scroll is
                  // given the body's whole height, because a `Scaffold`
                  // lets its body be as short as it likes: left to its own
                  // size, a page shorter than the body would hang from the
                  // top of it, the dock in mid-screen and the time under
                  // the heads-up.
                  if (constraints.maxHeight <
                      AlarmMetrics.pinnedDockMinHeight) {
                    return SizedBox(
                      height: constraints.maxHeight,
                      child: _scrolling(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [content, dock],
                        ),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _scrolling(content)),
                      dock,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reversed, which is what anchors the content to the dock: shorter than
  /// the region it rests on its bottom edge, taller it opens scrolled to its
  /// end.
  Widget _scrolling(Widget child) {
    return Semantics(
      identifier: SemanticsIds.alarmBody,
      child: SingleChildScrollView(reverse: true, child: child),
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final payload = widget.payload;
    // Said only where it is known: a snooze taken on this page, or one this
    // process saw the platform make. A test ring is registered as a snooze
    // and is not one.
    final snoozed = payload.reRing || (payload.snooze && !payload.isTest);
    final eyebrow = snoozed
        ? '${l10n.alarmPageTitle} · ${l10n.alertsOutcomeSnoozed}'
        : l10n.alarmPageTitle;
    // What a screen reader announces the page as: the same words, parted by
    // a pause rather than by a dot some voices read out.
    final announced = snoozed
        ? '${l10n.alarmPageTitle}, ${l10n.alertsOutcomeSnoozed}'
        : l10n.alarmPageTitle;
    // A title nobody typed still has to name what is ringing.
    final title = payload.isTest
        ? l10n.alarmTestTitle
        : payload.title.trim().isEmpty
        ? l10n.eventAlertModeRing
        : payload.title;
    // The avatar as it was resolved when the entry was armed; the category
    // facade only for an entry armed before the payload carried it — the
    // facade is empty where no database is open, and another database's.
    final category = CalendarCategories.resolve(payload.categoryId);
    // A test ring is the app's own, so its avatar wears the theme's primary.
    // The tint stamped into its payload is one fixed colour — an entry is
    // armed with no theme to ask — and is there for the notification: on
    // the dark page it was the dimmest thing drawn.
    final tint = payload.isTest
        ? colorScheme.primary
        : Color(
            payload.tintValue ?? payload.iconColorValue(category.colorValue),
          );
    final glyph =
        CalendarIcons.forKey(payload.glyphKey) ??
        CalendarIcons.forKey(payload.iconKey) ??
        CalendarIcons.forKey(category.iconKey) ??
        Icons.alarm_rounded;
    final otherDatabase = _controller.fromOtherDatabase;
    final VoidCallback? onOpen;
    if (_controller.busy) {
      onOpen = null;
    } else if (otherDatabase) {
      onOpen = () => _open(_openDatabase);
    } else if (payload.isTest) {
      // There is no event behind a test ring: the row stays, switched off,
      // so a test looks like the real thing.
      onOpen = null;
    } else if (widget._preview) {
      onOpen = _close;
    } else {
      onOpen = () => _open(_openEvent);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset,
        FormMetrics.bodyTop,
        RowMetrics.groupInset,
        AlarmMetrics.dockGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The page has no app bar to name it: Android announces a route
          // by the first node under the route's scope — the one this page
          // sets around itself — that says it names one. Named in words,
          // not in the capitals the label is drawn in.
          Semantics(
            header: true,
            namesRoute: true,
            label: announced,
            child: ExcludeSemantics(child: FormSectionLabel(text: eyebrow)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RowMetrics.sectionLabelInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The box, not the text, holds the line: a fitted box is
                // only as tall as what it fits, and an entry with no time
                // at all still keeps the day where it is.
                SizedBox(
                  height: AlarmMetrics.heroLineHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: MediaQuery.withNoTextScaling(
                      child: Text(
                        _timeLabel(context),
                        softWrap: false,
                        style: TextStyle(
                          fontSize: AlarmMetrics.heroFontSize,
                          height:
                              AlarmMetrics.heroLineHeight /
                              AlarmMetrics.heroFontSize,
                          fontWeight: FontWeight.w400,
                          color: colorScheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  _dayLabel(context),
                  style: FormLabelValue.labelStyle(
                    colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AlarmMetrics.heroGap),
          FormRowGroup(
            trailingGap: false,
            children: [
              FormReadTitleRow(
                leading: EventAvatar(icon: glyph, color: tint),
                title: title,
                caption: payload.whenLabel.isEmpty ? null : payload.whenLabel,
              ),
              if (payload.excerpt.isNotEmpty)
                FormIndentedRow(
                  dividerIndent: FormMetrics.dividerIndentPlain,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RowMetrics.groupInset,
                      vertical: FormMetrics.descriptionCellPadding,
                    ),
                    child: Text(
                      payload.excerpt,
                      maxLines: AlarmMetrics.excerptMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: FormMetrics.descriptionFontSize,
                        height:
                            FormMetrics.descriptionLineHeight /
                            FormMetrics.descriptionFontSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              // Last in the card and off the bottom edge on purpose: it
              // stops the ring, and may delete the event with it, so it is
              // not what a grabbing hand should land on.
              FormActionRow(
                glyph: otherDatabase
                    ? Icons.storage_rounded
                    : Icons.open_in_new_rounded,
                label: otherDatabase
                    ? l10n.alarmSwitchDatabase(payload.database)
                    : l10n.alarmOpenEvent,
                identifier: otherDatabase
                    ? SemanticsIds.alarmOpenDatabase
                    : SemanticsIds.alarmOpenEvent,
                onTap: onOpen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDock(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final payload = widget.payload;
    final busy = _controller.busy;
    // The slot is a payload fact and is sized on the first frame. Whether
    // anything is drawn in it waits for the database: only an alarm of the
    // open database removes its event on Stop, and only there can Keep write
    // anything, so until that is known — and for another database's alarm,
    // for good — the page claims neither.
    final removeSlot = payload.removeAfterAlert && !payload.isTest;
    final removeKnown = _controller.activeDatabase == payload.database;
    final labelStyle = theme.textTheme.labelLarge;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: AlarmMetrics.dockMaxTextScale,
      child: Padding(
        padding: EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: RowMetrics.groupInset,
          bottom:
              AlarmMetrics.dockBottomPadding +
              MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (removeSlot) ...[
              Visibility(
                visible: removeKnown,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: FormRowGroup(
                  trailingGap: false,
                  children: [
                    _RemoveRow(
                      kept: _controller.keepEvent,
                      // One-way, and in place once pressed: it goes off
                      // while its write is on its way and stays off when the
                      // event is kept.
                      onKeep: busy || !_controller.willRemoveEvent
                          ? null
                          : widget._preview
                          ? _close
                          : _controller.keep,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AlarmMetrics.dockGap),
            ],
            AutomationId(
              identifier: SemanticsIds.alarmStop,
              child: FilledButton.icon(
                onPressed: busy ? null : _stop,
                icon: const Icon(Icons.alarm_off_rounded),
                label: Text(l10n.alarmStop, textAlign: TextAlign.center),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AlarmMetrics.stopHeight),
                  iconSize: AlarmMetrics.dockIconSize,
                  textStyle: labelStyle?.copyWith(
                    fontSize: AlarmMetrics.stopLabelSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AlarmMetrics.dockGap),
            // On the bottom edge, under Stop: a stray grab at the edge of
            // the phone costs a few minutes, not an event.
            AutomationId(
              identifier: SemanticsIds.alarmSnooze,
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : _snooze,
                icon: const Icon(Icons.snooze_rounded),
                label: Text(
                  l10n.alarmSnoozeMinutes(payload.snoozeMinutes),
                  textAlign: TextAlign.center,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AlarmMetrics.snoozeHeight),
                  iconSize: AlarmMetrics.dockIconSize,
                  textStyle: labelStyle?.copyWith(
                    fontSize: AlarmMetrics.snoozeLabelSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What [AlarmPage.preview] renders from: the open database is the payload's,
/// so the page draws the rows a ring of the open database draws, and no call
/// reaches the scheduler, a database, the session chip or the gateway. Stop
/// and Snooze return at once, so the page's own handlers close it.
class _PreviewRingController extends AlertRingController {
  _PreviewRingController(AlertPayload payload) : super(payload: payload);

  @override
  String? get activeDatabase => payload.database;

  @override
  bool get fromOtherDatabase => false;

  @override
  Future<void> load() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> snooze() async {}

  @override
  Future<void> keep() async {}

  @override
  Future<bool> unlock() async => true;

  @override
  Future<bool> activateDatabase() async => false;
}

/// The dock's first row, for an event that Stop removes: what Stop will do,
/// beside the one way out of it. Pinned directly above Stop because it
/// changes what Stop does.
///
/// The line sits in a slot as tall as either thing it may say, so pressing
/// Keep changes the text and the glyph and moves nothing — Stop is the next
/// thing under the thumb.
class _RemoveRow extends StatelessWidget {
  const _RemoveRow({required this.kept, required this.onKeep});

  /// Whether the event is kept: Keep's write has come back, or the ring came
  /// up on an event already kept.
  final bool kept;

  /// Null switches Keep off in place.
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final warning = FormCaption(text: l10n.alarmRemoveAfterCaption);
    final keptLine = FormCaption(text: l10n.alarmKeptEvent);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: FormMetrics.headerActionInset,
        ),
        child: Row(
          children: [
            FormGlyph(
              icon: kept
                  ? Icons.event_available_outlined
                  : Icons.auto_delete_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: FormMetrics.gap),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: RowMetrics.twoLinePadding.top,
                  bottom: RowMetrics.twoLinePadding.bottom,
                ),
                child: FormCaptionSlot(
                  alignment: AlignmentDirectional.centerStart,
                  candidates: [warning, keptLine],
                  child: kept ? keptLine : warning,
                ),
              ),
            ),
            const SizedBox(width: FormMetrics.gap),
            // The word alone is enough beside the sentence it answers; a
            // screen reader reaches the button on its own and hears what is
            // kept.
            FormHeaderTextButton(
              label: l10n.alarmKeep,
              semanticsLabel: l10n.alarmKeepEvent,
              identifier: SemanticsIds.alarmKeepEvent,
              onPressed: onKeep,
            ),
          ],
        ),
      ),
    );
  }
}
