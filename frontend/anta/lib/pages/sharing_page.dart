import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/pairing/pairing_bloc.dart';
import '../bloc/share/share_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import '../models/partner_look.dart';
import '../models/share_overview.dart';
import '../models/share_settings.dart';
import '../services/share_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../utils/share_copy.dart';
import '../utils/sync_moment_format.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/form_rows.dart' show FormCaptionSlot;
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/share_events_sheets.dart';
import '../widgets/shared_categories_sheet.dart';
import '../widgets/unified_app_bars.dart';

/// How a list of names reads in a row's description and a snackbar.
const String _namesSeparator = ', ';

/// The snackbar's words for [change] (§6.14): what started, then what
/// stopped — with how many events stay shared on their own mark (C10) —
/// each on a line of its own when one act did both. Public for the sheets
/// the page opens, which say their own acts from inside the sheet.
String shareChangeMessage(
  AppLocalizations l10n,
  ShareChange change,
  String name,
) {
  final shared = [
    for (final category in change.sharedCategories)
      CalendarCategories.labelOf(category, l10n),
    for (final event in change.sharedEvents) event.title,
  ];
  final unshared = [
    for (final category in change.unsharedCategories)
      CalendarCategories.labelOf(category, l10n),
    for (final event in change.unsharedEvents) event.title,
  ];
  return [
    if (shared.isNotEmpty)
      l10n.shareStarted(shared.join(_namesSeparator), name),
    if (unshared.isNotEmpty)
      change.keptOnTheirOwn > 0
          ? l10n.shareStoppedSomeStay(
              unshared.join(_namesSeparator),
              change.keptOnTheirOwn,
            )
          : l10n.shareStopped(unshared.join(_namesSeparator)),
  ].join('\n');
}

/// A moment "Updated {when}" may say at its widest: a date in another year,
/// which spells the year the time of day and this year's dates leave out.
final DateTime _widestMoment = DateTime(2000, 9, 28);

/// Which of the lines under what the partner shares were true as the page
/// first loaded, and the count the third said then.
class _HeldNotices {
  final bool stale;
  final bool newerWire;
  final int notShown;

  const _HeldNotices({
    required this.stale,
    required this.newerWire,
    required this.notShown,
  });

  factory _HeldNotices.of(ShareOverview overview, DateTime now) => _HeldNotices(
    stale: overview.isStale(now),
    newerWire: overview.partnerNewerWire,
    notShown: overview.refusedCount,
  );
}

/// What this database shares, from plural parts — "3 categories, 2 events"
/// — or "Nothing is shared yet": the Pairing row's description while
/// paired.
String shareSummary(AppLocalizations l10n, ShareOverview overview) {
  final parts = [
    if (overview.categories.isNotEmpty)
      l10n.shareSummaryCategories(overview.categories.length),
    if (overview.events.isNotEmpty)
      l10n.shareSummaryEvents(overview.events.length),
  ];
  return parts.isEmpty ? l10n.shareNothingYet : parts.join(_namesSeparator);
}

/// A count as wide as [shareSummary] is likely to say: two digits, which
/// keeps the Pairing row at two lines at 1.3 on a 360 dp phone, where three
/// took a third for a count few will reach.
const int _summaryTemplateCount = 99;

/// Every form [shareSummary] takes, at its widest: the slot that holds the
/// Pairing row's height whatever is shared, so nothing below it moves when
/// a share changes.
List<String> shareSummaryTemplates(AppLocalizations l10n) => [
  l10n.shareNothingYet,
  [
    l10n.shareSummaryCategories(_summaryTemplateCount),
    l10n.shareSummaryEvents(_summaryTemplateCount),
  ].join(_namesSeparator),
];

/// What this person shares with their partner, and the way out of it
/// (`docs/cloud-share-surfaces-roadmap.md` §6.2): the settings kit, pushed
/// from the Pairing row of Sync & sharing while paired. Every control
/// writes at once; the page asks for one shared read as it opens (D22) and
/// closes itself when the pairing bloc says the pair has ended under it.
class SharingPage extends StatelessWidget {
  /// The Sync & sharing page's own: Unpair is that bloc's act, and the
  /// page under this one is where its outcome shows.
  final PairingBloc pairingBloc;

  /// Opens the list of the events shared one by one, under the page's
  /// [ShareBloc] in [BuildContext], completing as it closes: while it is up
  /// the sheet says what its ✕ and its Undo did, and the page says neither.
  /// Null leaves the entry in its place and height, its tap doing nothing.
  final Future<void> Function(BuildContext context)? onOpenEvents;

  /// Opens one of the events the partner shares singly, from their list.
  /// Null where no event sheets can open — Sync & sharing — and the list's
  /// rows then take no tap at all.
  final ShareEventOpener? onOpenPartnerEvent;

  /// Where an Undo tapped after the page has left writes: the page's bloc
  /// has closed with it.
  final Future<ShareService> Function() shareService;

  const SharingPage({
    super.key,
    required this.pairingBloc,
    this.onOpenEvents,
    this.onOpenPartnerEvent,
    this.shareService = ShareService.getInstance,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ShareBloc>(
          create: (_) => getIt<ShareBloc>()..add(const ShareOpened()),
        ),
        BlocProvider<PairingBloc>.value(value: pairingBloc),
      ],
      child: _SharingView(
        onOpenEvents: onOpenEvents,
        onOpenPartnerEvent: onOpenPartnerEvent,
        shareService: shareService,
      ),
    );
  }
}

class _SharingView extends StatefulWidget {
  final Future<void> Function(BuildContext context)? onOpenEvents;
  final ShareEventOpener? onOpenPartnerEvent;
  final Future<ShareService> Function() shareService;

  const _SharingView({
    required this.onOpenEvents,
    required this.onOpenPartnerEvent,
    required this.shareService,
  });

  @override
  State<_SharingView> createState() => _SharingViewState();
}

class _SharingViewState extends State<_SharingView> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  /// Set once the page has asked to go: a pair that ends on both blocs at
  /// once closes it once.
  bool _leaving = false;

  /// While the counts are read and the tick sheet is up, so a second tap
  /// opens no second sheet.
  bool _picking = false;

  /// While the Single events sheet is up: it says the outcome of its ✕ and
  /// of an Undo over itself, and a bar of the page's under it would say a
  /// failure twice (closing review finding 3).
  bool _eventsOpen = false;

  /// Whether the page is in its "pair another account made" shape, taken at
  /// the first loaded state and held for the visit: sharing turns "not
  /// paired" a moment before the pairing bloc says the pair has ended, and
  /// a page that opened whole keeps its sections until it has left.
  bool? _foreign;

  /// The lines under what the partner shares as the first loaded state
  /// said them, held for the visit (the slice C spec, decision t): the
  /// block is sized once, so the entries under it never move. A line that
  /// clears leaves its space; one that comes true waits for the next visit.
  _HeldNotices? _notices;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The partner's name as the copy says it: the audience's once loaded,
  /// the pairing's until then — and whenever sharing names no audience — so
  /// the title never opens on "your partner".
  String _partnerName(AppLocalizations l10n, ShareLoaded? loaded) {
    final pairing = context.read<PairingBloc>().state;
    final raw = loaded != null && loaded.availability is! ShareNotPaired
        ? loaded.availability.audience?.displayName
        : pairing is PairingPaired
        ? pairing.partner?.displayName
        : null;
    return ShareCopy.partnerName(l10n, raw);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return MultiBlocListener(
      listeners: [
        // The page's own acts; an un-share from the events sheet, and an
        // Undo while that sheet is up, are said from inside the sheet.
        BlocListener<ShareBloc, ShareState>(
          listenWhen: (previous, current) {
            final outcome = _outcomeOf(current);
            return outcome != null &&
                outcome.sequence != _outcomeOf(previous)?.sequence &&
                outcome.act != ShareAct.eventUnshared &&
                !(_eventsOpen && outcome.act == ShareAct.undo);
          },
          listener: (context, state) => _sayOutcome(
            context,
            l10n,
            _outcomeOf(state)!,
            _partnerName(l10n, state as ShareLoaded),
          ),
        ),
        // Only the pairing bloc ends the visit: sharing also says "not
        // paired" for a pair another account made, which the page stays
        // open to end.
        BlocListener<PairingBloc, PairingState>(
          listenWhen: (previous, current) =>
              current is PairingEnded ||
              current is PairingUnpaired ||
              current is PairingSignedOut ||
              current is PairingUnavailable,
          listener: (context, state) => _leave(),
        ),
      ],
      child: BlocBuilder<ShareBloc, ShareState>(
        builder: (context, state) {
          final loaded = state is ShareLoaded ? state : null;
          final name = _partnerName(l10n, loaded);
          final failed = state is ShareLoadFailed;
          // The pairing bloc says paired, sharing says not: a pair another
          // account made is stored here. Only the way out of it is drawn.
          if (loaded != null) {
            _foreign ??= loaded.availability is ShareNotPaired;
          }
          final foreign = _foreign ?? false;
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.pageGround,
            appBar: SettingsAppBar(
              title: l10n.sharingWithTitle(name),
              identifier: SemanticsIds.sharingPage,
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: FormMetrics.settingsSearchPadding,
                    child: SettingsSearchField(
                      controller: _searchController,
                      hint: l10n.searchSettings,
                      onChanged: (value) =>
                          setState(() => _query = SettingsQuery.parse(value)),
                    ),
                  ),
                  Expanded(
                    child: SettingsSectionList(
                      query: _query,
                      listIdentifier: SemanticsIds.sharingPageList,
                      header: [
                        if (failed)
                          Padding(
                            padding: FormMetrics.settingsRowPadding,
                            child: Text(
                              l10n.shareLoadFailed,
                              style: settingsCaptionStyle.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                      sections: [
                        if (!failed && !foreign) ...[
                          _youShareSection(context, l10n, loaded, name),
                          _theirsSection(context, l10n, loaded, name),
                          _lookSection(context, l10n, loaded),
                          _alertsSection(context, l10n, loaded),
                        ],
                        _pairingSection(context, l10n, loaded, name),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static ShareOutcome? _outcomeOf(ShareState state) =>
      state is ShareLoaded ? state.outcome : null;

  SettingsSectionData _youShareSection(
    BuildContext context,
    AppLocalizations l10n,
    ShareLoaded? loaded,
    String name,
  ) {
    final overview = loaded?.overview ?? ShareOverview.empty;
    final availability = loaded?.availability;
    final ready = availability is ShareReady;
    final needsSync = availability is ShareNotSyncing;
    // Blank until the first read, never "None" for a moment.
    String described(String text) => loaded == null ? '' : text;
    final intro = ShareCopy.sentence(l10n.shareYouShareCaption(name));
    final categories = described(
      overview.categories.isEmpty
          ? l10n.shareNone
          : [
              for (final category in overview.categories)
                CalendarCategories.labelOf(category, l10n),
            ].join(_namesSeparator),
    );
    final events = described(
      overview.events.isEmpty
          ? l10n.shareNone
          : l10n.shareSummaryEvents(overview.events.length),
    );
    return SettingsSectionData(
      icon: Icons.group_rounded,
      title: l10n.shareYouShare,
      trailing: ready && overview.sending
          ? (overview.offline ? l10n.shareWaitingToSend : l10n.shareSending)
          : null,
      trailingTemplates: [l10n.shareSending, l10n.shareWaitingToSend],
      intro: Padding(
        padding: FormMetrics.settingsRowPadding.copyWith(
          bottom: FormMetrics.settingsRowVerticalPadding,
        ),
        // While this database does not sync the reason stands where the
        // intro stood, in a slot as tall as the taller of the two from the
        // first frame: the entries under it never move (design review 6).
        child: FormCaptionSlot(
          candidates: [Text(intro), Text(l10n.shareNeedsSync)],
          child: Text(needsSync ? l10n.shareNeedsSync : intro),
        ),
      ),
      entries: [
        SettingsEntry(
          title: l10n.shareRowCategories,
          description: categories,
          descriptionMaxLines: 1,
          identifier: SemanticsIds.sharingMineCategories,
          builder: (context, title, description) => _entryTile(
            context,
            glyph: Icons.category_rounded,
            label: l10n.shareRowCategories,
            title: title,
            description: description,
            descriptionText: categories,
            needsSync: needsSync,
            reason: l10n.shareNeedsSync,
            onTap: ready ? () => _pickCategories(l10n, overview, name) : null,
          ),
        ),
        SettingsEntry(
          title: l10n.shareRowEvents,
          description: events,
          descriptionMaxLines: 1,
          identifier: SemanticsIds.sharingMineEvents,
          builder: (context, title, description) => _entryTile(
            context,
            glyph: Icons.event_rounded,
            label: l10n.shareRowEvents,
            title: title,
            description: description,
            descriptionText: events,
            needsSync: needsSync,
            reason: l10n.shareNeedsSync,
            onTap: switch (widget.onOpenEvents) {
              final open? when ready => () => _openEvents(context, open),
              _ => null,
            },
          ),
        ),
      ],
    );
  }

  /// An entry of what is shared, either way: a page's chevron row. While
  /// [needsSync] it is the kit's disabled tile, in place, and a tap goes
  /// back to Sync & sharing, where sync is turned on (D8) — [reason] stands
  /// in the intro's slot above it. Dimmed yet acting, it is one enabled
  /// button to a screen reader, named with [label], [descriptionText] —
  /// what is shared still stands drawn — and [reason], and saying where it
  /// goes, never a disabled tile that answers a tap (design review 2).
  Widget _entryTile(
    BuildContext context, {
    required IconData glyph,
    required String label,
    required Widget title,
    required Widget? description,
    required String descriptionText,
    required bool needsSync,
    required String reason,
    required VoidCallback? onTap,
  }) {
    final tile = ListTile(
      enabled: !needsSync,
      leading: Icon(
        glyph,
        color: needsSync ? null : Theme.of(context).colorScheme.primary,
      ),
      title: title,
      subtitle: description,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
    if (!needsSync) return tile;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      enabled: true,
      label: [
        label,
        if (descriptionText.isNotEmpty) descriptionText,
        reason,
      ].join('\n'),
      hint: l10n.shareOpensSyncHint,
      onTap: _backToSync,
      excludeSemantics: true,
      child: InkWell(onTap: _backToSync, child: tile),
    );
  }

  /// Holds [_eventsOpen] for the Single events sheet's lifetime; a second
  /// tap while it is up opens no second sheet.
  Future<void> _openEvents(
    BuildContext context,
    Future<void> Function(BuildContext context) open,
  ) async {
    if (_eventsOpen) return;
    _eventsOpen = true;
    try {
      await open(context);
    } finally {
      _eventsOpen = false;
    }
  }

  /// Sync & sharing is always the page beneath this one: going back to it
  /// never stacks a second copy over the first (review finding 8).
  void _backToSync() {
    if (_leaving || !mounted) return;
    Navigator.of(context).pop();
  }

  /// What the partner shares (§6.2 item 2): the same two entries as YOU
  /// SHARE, opening the received-categories sheet and the read-only list.
  /// "Could not check" goes in the header's slot, the one line that can
  /// arrive after the page opens; the intro's lines are held from the open.
  SettingsSectionData _theirsSection(
    BuildContext context,
    AppLocalizations l10n,
    ShareLoaded? loaded,
    String name,
  ) {
    final overview = loaded?.overview ?? ShareOverview.empty;
    final availability = loaded?.availability;
    final ready = availability is ShareReady;
    final needsSync = availability is ShareNotSyncing;
    final now = DateTime.now();
    final notices = _notices ??= loaded == null
        ? null
        : _HeldNotices.of(overview, now);
    String described(String text) => loaded == null ? '' : text;
    final intro = ShareCopy.sentence(l10n.sharePartnerSharesCaption(name));
    final names = [
      for (final shared in orderSharedCategories(
        overview.partnerCategories,
        CalendarCategories.all,
      ))
        CalendarCategories.labelOf(shared.category, l10n),
    ];
    final readAt = overview.readAt;
    final categories = described(
      names.isEmpty ? l10n.shareNone : names.join(_namesSeparator),
    );
    final events = described(
      overview.partnerEvents.isEmpty
          ? l10n.shareNone
          : l10n.shareSummaryEvents(overview.partnerEvents.length),
    );
    return SettingsSectionData(
      icon: Icons.group_rounded,
      title: ShareCopy.sentence(l10n.sharePartnerShares(name)),
      trailing: !ready
          ? null
          : overview.readFailed
          ? l10n.shareCheckFailed
          : readAt == null
          ? null
          : l10n.shareUpdated(formatSyncMoment(context, readAt)),
      trailingTemplates: [
        l10n.shareUpdated(formatSyncMoment(context, _widestMoment)),
        l10n.shareCheckFailed,
      ],
      intro: Padding(
        padding: FormMetrics.settingsRowPadding.copyWith(
          bottom: FormMetrics.settingsRowVerticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1's rule: the reason in the intro's place, in a slot
            // as tall as the taller of the two from the first frame.
            FormCaptionSlot(
              candidates: [Text(intro), Text(l10n.shareNeedsSyncReceive)],
              child: Text(needsSync ? l10n.shareNeedsSyncReceive : intro),
            ),
            if (notices != null) ...[
              if (notices.stale)
                _heldLine(
                  l10n.shareMaybeStale,
                  overview.isStale(now) ? l10n.shareMaybeStale : null,
                ),
              if (notices.newerWire)
                _heldLine(
                  ShareCopy.sentence(l10n.shareUpdateApp(name)),
                  overview.partnerNewerWire
                      ? ShareCopy.sentence(l10n.shareUpdateApp(name))
                      : null,
                ),
              if (notices.notShown > 0)
                _heldLine(
                  l10n.shareNotShown(notices.notShown),
                  overview.refusedCount > 0
                      ? l10n.shareNotShown(overview.refusedCount)
                      : null,
                ),
            ],
          ],
        ),
      ),
      entries: [
        SettingsEntry(
          title: l10n.shareRowCategories,
          description: categories,
          descriptionMaxLines: 1,
          identifier: SemanticsIds.sharingTheirsCategories,
          builder: (context, title, description) => _entryTile(
            context,
            glyph: Icons.category_rounded,
            label: l10n.shareRowCategories,
            title: title,
            description: description,
            descriptionText: categories,
            needsSync: needsSync,
            reason: l10n.shareNeedsSyncReceive,
            onTap: ready
                ? () => SharedCategoriesSheet.show(
                    context,
                    bloc: context.read<ShareBloc>(),
                    partner: _partnerLook(loaded!),
                  )
                : null,
          ),
        ),
        SettingsEntry(
          title: l10n.shareRowEvents,
          description: events,
          descriptionMaxLines: 1,
          identifier: SemanticsIds.sharingTheirsEvents,
          builder: (context, title, description) => _entryTile(
            context,
            glyph: Icons.event_rounded,
            label: l10n.shareRowEvents,
            title: title,
            description: description,
            descriptionText: events,
            needsSync: needsSync,
            reason: l10n.shareNeedsSyncReceive,
            onTap: ready
                ? () => PartnerSharedEventsSheet.show(
                    context,
                    bloc: context.read<ShareBloc>(),
                    partner: _partnerLook(loaded!),
                    onOpen: widget.onOpenPartnerEvent,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  /// One held line of the intro: in a slot as tall as it was at the open,
  /// showing [current] while it is still true and nothing once it clears.
  static Widget _heldLine(String atOpen, String? current) => FormCaptionSlot(
    candidates: [Text(atOpen)],
    child: current == null ? const SizedBox.shrink() : Text(current),
  );

  /// How the sheets this page opens draw the partner's things, built as the
  /// calendar builds it: the look this phone picked and who the partner is.
  static PartnerLook _partnerLook(ShareLoaded loaded) {
    final audience = loaded.availability.audience;
    return PartnerLook(
      look: loaded.look.eventLook,
      partner: audience?.members.firstOrNull,
      name: audience?.displayName,
      markMine: loaded.look.markMine,
      unpaired: audience == null,
    );
  }

  /// How shared things look (§6.7): drawn from the bloc's state alone,
  /// which shows a choice from the tap. Until the first read the shipped
  /// values stand, as the bloc's own state does.
  SettingsSectionData _lookSection(
    BuildContext context,
    AppLocalizations l10n,
    ShareLoaded? loaded,
  ) {
    final look = loaded?.look ?? const ShareLook();
    return SettingsSectionData(
      icon: Icons.visibility_rounded,
      title: l10n.shareLookSection,
      entries: [
        SettingsEntry(
          title: l10n.shareEventLook,
          identifier: SemanticsIds.sharingLookEvents,
          builder: (context, title, description) =>
              settingsChoiceRow<ShareEventLook>(
                title: title,
                description: description,
                value: look.eventLook,
                labels: {
                  ShareEventLook.outlined: l10n.shareLookOutlined,
                  ShareEventLook.avatar: l10n.shareLookAvatar,
                  ShareEventLook.plain: l10n.shareLookPlain,
                },
                identifiers: {
                  for (final value in ShareEventLook.values)
                    value: SemanticsIds.sharingLookEventsChoice(value.name),
                },
                onChanged: (value) =>
                    context.read<ShareBloc>().add(ShareEventLookSet(value)),
              ),
        ),
        SettingsEntry(
          title: l10n.shareMarkMine,
          description: l10n.shareMarkMineDesc,
          identifier: SemanticsIds.sharingMarkMine,
          builder: (context, title, description) => SwitchListTile(
            value: look.markMine,
            title: title,
            subtitle: description,
            onChanged: (value) =>
                context.read<ShareBloc>().add(ShareMarkMineSet(value)),
          ),
        ),
      ],
    );
  }

  /// What may ring for a partner's event (§6.8): an entry that opens a
  /// menu rather than a page, so it has no chevron (decision v). Its value
  /// is blank and its tap inert until the first read says what is stored.
  SettingsSectionData _alertsSection(
    BuildContext context,
    AppLocalizations l10n,
    ShareLoaded? loaded,
  ) {
    final alerts = loaded?.alerts;
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsSectionData(
      icon: Icons.notifications_rounded,
      title: l10n.shareAlertsSection,
      entries: [
        SettingsEntry(
          title: l10n.shareAlerts,
          description: alerts == null ? '' : _alertsLabel(l10n, alerts),
          identifier: SemanticsIds.sharingAlerts,
          // A `Builder` so the menu hangs from the row's own box.
          builder: (context, title, description) => Builder(
            builder: (rowContext) => ListTile(
              leading: Icon(
                Icons.notifications_rounded,
                color: colorScheme.primary,
              ),
              title: title,
              subtitle: description,
              onTap: alerts == null
                  ? null
                  : () => _pickAlerts(rowContext, l10n, alerts),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAlerts(
    BuildContext anchor,
    AppLocalizations l10n,
    ShareAlerts current,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final bloc = context.read<ShareBloc>();
    final next = await showFormMenu<ShareAlerts>(
      anchor,
      items: [
        for (final value in ShareAlerts.values)
          FormMenuItem(
            value: value,
            label: _alertsLabel(l10n, value),
            caption: switch (value) {
              ShareAlerts.off => l10n.shareAlertsOffDesc,
              ShareAlerts.own => l10n.shareAlertsOwnDesc,
              ShareAlerts.category => l10n.shareAlertsCategoryDesc,
            },
            identifier: switch (value) {
              ShareAlerts.off => SemanticsIds.sharingAlertsOff,
              ShareAlerts.own => SemanticsIds.sharingAlertsOwn,
              ShareAlerts.category => SemanticsIds.sharingAlertsCategory,
            },
          ),
      ],
      selected: current,
      // Floor and cap at once: a caption of two lines reads as one choice
      // at this width, and the menu never narrows with the language.
      menuWidth: FormMetrics.menuMaxWidth,
    );
    if (next == null || next == current || !_stillHere(bloc)) return;
    bloc.add(ShareAlertsSet(next));
  }

  static String _alertsLabel(AppLocalizations l10n, ShareAlerts value) =>
      switch (value) {
        ShareAlerts.off => l10n.shareAlertsOff,
        ShareAlerts.own => l10n.shareAlertsOwn,
        ShareAlerts.category => l10n.shareAlertsCategory,
      };

  SettingsSectionData _pairingSection(
    BuildContext context,
    AppLocalizations l10n,
    ShareLoaded? loaded,
    String name,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final canStop = loaded?.overview.sharesAnything ?? false;
    final pairing = context.watch<PairingBloc>().state;
    final canUnpair = pairing is PairingPaired && !pairing.busy;
    return SettingsSectionData(
      icon: Icons.link_rounded,
      title: l10n.pairingSection,
      entries: [
        SettingsEntry(
          title: l10n.shareStopAll,
          description: l10n.shareStopAllDesc,
          identifier: SemanticsIds.sharingStopAll,
          builder: (context, title, description) => ListTile(
            enabled: canStop,
            leading: Icon(
              Icons.group_off_rounded,
              color: canStop ? colorScheme.primary : null,
            ),
            title: title,
            subtitle: description,
            onTap: () => _stopAll(l10n, name),
          ),
        ),
        SettingsEntry(
          title: l10n.unpair,
          description: l10n.shareUnpairDesc,
          titleStyle: canUnpair ? TextStyle(color: colorScheme.error) : null,
          identifier: SemanticsIds.sharingUnpair,
          builder: (context, title, description) => ListTile(
            enabled: canUnpair,
            leading: Icon(
              Icons.link_off_rounded,
              color: canUnpair ? colorScheme.error : null,
            ),
            title: title,
            subtitle: description,
            onTap: () => _unpair(l10n),
          ),
        ),
      ],
    );
  }

  /// The tick sheet (§6.3) over this person's categories, each with its
  /// event count from the overview; Done sends the whole ticked set, and an
  /// unchanged one sends nothing.
  Future<void> _pickCategories(
    AppLocalizations l10n,
    ShareOverview overview,
    String name,
  ) async {
    if (_picking) return;
    _picking = true;
    try {
      final bloc = context.read<ShareBloc>();
      final selected = {
        for (final category in overview.categories) category.id,
      };
      final picked = await CategoryPickerSheet.pickMulti(
        context,
        selected: selected,
        title: l10n.shareCategoriesTitle,
        caption: ShareCopy.sentence(l10n.shareCategoriesCaption(name)),
        counts: overview.eventCounts,
        identifier: SemanticsIds.shareCategoriesSheet,
        // Done shares what is ticked: a category made inside the sheet
        // arrives un-ticked, so nobody shares one they only created (C9).
        tickCreated: false,
      );
      if (!_stillHere(bloc)) return;
      if (picked == null || setEquals(picked, selected)) return;
      bloc.add(ShareCategoriesSet(picked));
    } finally {
      _picking = false;
    }
  }

  /// Whether an act that awaited a sheet or a dialog may still go: the
  /// pair can end under it, and the page leaves with its bloc.
  bool _stillHere(BlocBase<Object?> bloc) =>
      mounted && !_leaving && !bloc.isClosed;

  /// The one share act that asks first (D6): it has no Undo.
  Future<void> _stopAll(AppLocalizations l10n, String name) async {
    final bloc = context.read<ShareBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.shareStopAllConfirmTitle(name),
      content: l10n.shareStopAllConfirm(name),
      confirmText: l10n.shareStopAll,
      icon: Icons.group_off_rounded,
    );
    if (confirmed && _stillHere(bloc)) bloc.add(const ShareStopAllRequested());
  }

  /// Moved here from the Pairing row, its dialog saying what a new pair
  /// starts from (S7). The page goes at once: Sync & sharing under it shows
  /// the unpair running and how it ended.
  Future<void> _unpair(AppLocalizations l10n) async {
    final bloc = context.read<PairingBloc>();
    final state = bloc.state;
    if (state is! PairingPaired) return;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.unpair,
      content:
          '${l10n.pairingUnpairConfirm(ShareCopy.partnerName(l10n, state.partner?.displayName))} '
          '${l10n.pairingRepairHint}',
      confirmText: l10n.unpair,
      isDestructive: true,
      icon: Icons.link_off_rounded,
      confirmIdentifier: SemanticsIds.sharingUnpairConfirm,
    );
    if (!confirmed || !_stillHere(bloc)) return;
    bloc.add(const UnpairRequested());
    _leave();
  }

  /// Closes this page wherever it stands, and first whatever it opened
  /// above itself: a sheet left over a page that has gone throws when it
  /// is finished. As a pair ends Sync & sharing raises its ended notice
  /// over everything before this page hears of it; that notice, on top,
  /// stays, and what lies between it and this page goes with the page.
  void _leave() {
    if (_leaving || !mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    _leaving = true;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
      return;
    }
    Route<dynamic>? top;
    // A predicate that holds at once pops nothing: it names the top route.
    navigator.popUntil((above) {
      top = above;
      return true;
    });
    final notice = top;
    final ended = context.read<PairingBloc>().state is PairingEnded;
    if (ended && notice is RawDialogRoute) {
      while (route.isActive) {
        navigator.removeRouteBelow(notice);
      }
      return;
    }
    navigator.popUntil((above) => above == route);
    navigator.pop();
  }

  void _sayOutcome(
    BuildContext context,
    AppLocalizations l10n,
    ShareOutcome outcome,
    String name,
  ) {
    switch (outcome.failure) {
      case ShareFailure.refused:
        CustomSnackbar.showError(context, l10n.shareNeedsSync);
        return;
      case ShareFailure.failed:
        CustomSnackbar.showError(context, l10n.shareChangeFailed);
        return;
      case null:
        break;
    }
    // An undo says nothing more; "Stop sharing everything" was confirmed
    // and its rows say what it did.
    if (outcome.act != ShareAct.categoriesSet || outcome.change.isEmpty) {
      return;
    }
    final bloc = context.read<ShareBloc>();
    final change = outcome.change;
    final resolve = widget.shareService;
    // The app's own, which outlives this page as the bar does.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final generation = ShareService.databaseGeneration;
    CustomSnackbar.showWithAction(
      context,
      message: shareChangeMessage(l10n, change, name),
      actionLabel: l10n.undo,
      onAction: () {
        // An Undo belongs to the database it was offered in: built-in
        // category ids are the same in every database, so one tapped after
        // a switch would share in a database that never saw the act.
        if (ShareService.databaseGeneration != generation) return;
        if (!bloc.isClosed) {
          bloc.add(ShareUndoRequested(change));
          return;
        }
        // The page has left and its bloc with it.
        unawaited(
          undoSharePastBloc(
            change,
            shareService: resolve,
            messenger: messenger,
            l10n: l10n,
          ),
        );
      },
    );
  }
}
