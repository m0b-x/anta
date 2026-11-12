import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, setEquals;
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
import '../models/share_overview.dart';
import '../services/share_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../utils/share_copy.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/form_rows.dart' show FormCaptionSlot;
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
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
  /// [ShareBloc] in [BuildContext]. Null leaves the entry in its place and
  /// height, its tap doing nothing.
  final void Function(BuildContext context)? onOpenEvents;

  /// Where an Undo tapped after the page has left writes: the page's bloc
  /// has closed with it.
  final Future<ShareService> Function() shareService;

  const SharingPage({
    super.key,
    required this.pairingBloc,
    this.onOpenEvents,
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
        shareService: shareService,
      ),
    );
  }
}

class _SharingView extends StatefulWidget {
  final void Function(BuildContext context)? onOpenEvents;
  final Future<ShareService> Function() shareService;

  const _SharingView({required this.onOpenEvents, required this.shareService});

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
        // The page's own acts; an un-share from the events sheet is said
        // from inside that sheet.
        BlocListener<ShareBloc, ShareState>(
          listenWhen: (previous, current) {
            final outcome = _outcomeOf(current);
            return outcome != null &&
                outcome.sequence != _outcomeOf(previous)?.sequence &&
                outcome.act != ShareAct.eventUnshared;
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
          final foreign = loaded?.availability is ShareNotPaired;
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
                        if (!failed && !foreign)
                          _youShareSection(context, l10n, loaded, name),
                        // The record's sections 2–4 — what the partner
                        // shares, how shared things look, their alerts —
                        // stand here, between what this person gives and
                        // the way out of it.
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
          description: described(
            overview.categories.isEmpty
                ? l10n.shareNone
                : [
                    for (final category in overview.categories)
                      CalendarCategories.labelOf(category, l10n),
                  ].join(_namesSeparator),
          ),
          descriptionMaxLines: 1,
          identifier: SemanticsIds.sharingMineCategories,
          builder: (context, title, description) => _entryTile(
            context,
            glyph: Icons.category_rounded,
            label: l10n.shareRowCategories,
            title: title,
            description: description,
            needsSync: needsSync,
            onTap: ready ? () => _pickCategories(l10n, overview, name) : null,
          ),
        ),
        SettingsEntry(
          title: l10n.shareRowEvents,
          description: described(
            overview.events.isEmpty
                ? l10n.shareNone
                : l10n.shareSummaryEvents(overview.events.length),
          ),
          descriptionMaxLines: 1,
          identifier: SemanticsIds.sharingMineEvents,
          builder: (context, title, description) => _entryTile(
            context,
            glyph: Icons.event_rounded,
            label: l10n.shareRowEvents,
            title: title,
            description: description,
            needsSync: needsSync,
            onTap: switch (widget.onOpenEvents) {
              final open? when ready => () => open(context),
              _ => null,
            },
          ),
        ),
      ],
    );
  }

  /// A YOU SHARE entry: a page's chevron row. While [needsSync] it is the
  /// kit's disabled tile, in place, and a tap goes back to Sync & sharing,
  /// where sync is turned on (D8) — the reason stands in the intro's slot
  /// above it. Dimmed yet acting, it is one enabled button to a screen
  /// reader, named with [label] and the reason and saying where it goes,
  /// never a disabled tile that answers a tap (design review 2).
  Widget _entryTile(
    BuildContext context, {
    required IconData glyph,
    required String label,
    required Widget title,
    required Widget? description,
    required bool needsSync,
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
      label: '$label\n${l10n.shareNeedsSync}',
      hint: l10n.shareOpensSyncHint,
      onTap: _backToSync,
      excludeSemantics: true,
      child: InkWell(onTap: _backToSync, child: tile),
    );
  }

  /// Sync & sharing is always the page beneath this one: going back to it
  /// never stacks a second copy over the first (review finding 8).
  void _backToSync() {
    if (_leaving || !mounted) return;
    Navigator.of(context).pop();
  }

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
    // The navigator under the app's messenger outlives this page, as the
    // bar does.
    final messenger = Navigator.of(context, rootNavigator: true).context;
    CustomSnackbar.showWithAction(
      context,
      message: shareChangeMessage(l10n, change, name),
      actionLabel: l10n.undo,
      onAction: () {
        if (!bloc.isClosed) {
          bloc.add(ShareUndoRequested(change));
          return;
        }
        unawaited(_undoAfterLeaving(change, resolve, messenger, l10n));
      },
    );
  }

  /// An Undo tapped once the page has left: its bloc closed with it, so the
  /// write goes to [ShareService.undo] itself — the one sanctioned act of
  /// this page past its bloc, as the Categories page's Undo writes — and a
  /// failure is said on the app's messenger through [messenger], the root
  /// navigator's context, since no context of the page lives.
  static Future<void> _undoAfterLeaving(
    ShareChange change,
    Future<ShareService> Function() resolve,
    BuildContext messenger,
    AppLocalizations l10n,
  ) async {
    try {
      await (await resolve()).undo(change);
    } catch (e, st) {
      debugPrint('[SharingPage] undo after leaving failed: $e\n$st');
      if (messenger.mounted) {
        CustomSnackbar.showError(messenger, l10n.shareChangeFailed);
      }
    }
  }
}
