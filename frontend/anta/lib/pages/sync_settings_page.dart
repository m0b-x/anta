import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/pairing/pairing_bloc.dart';
import '../bloc/sync/sync_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../services/sync/sync_cadence.dart';
import '../utils/auth_error.dart';
import '../utils/custom_snackbar.dart';
import '../utils/pairing_error.dart';
import '../utils/settings_search.dart';
import '../utils/sync_moment_format.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/form_rows.dart' show FormCaptionSlot;
import '../widgets/pairing_sheet.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/sync_space_picker_sheet.dart';
import '../widgets/unified_app_bars.dart';
import '../widgets/user_avatar.dart';

/// Cloud account settings. Phase 00 established the identity; Phase 01 links
/// two accounts into a pair; Phase 02 syncs this database with the account's
/// other devices.
class SyncSettingsPage extends StatelessWidget {
  const SyncSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SyncBloc>(
          create: (_) => getIt<SyncBloc>()..add(const LoadSyncStatus()),
        ),
        BlocProvider<PairingBloc>(
          create: (_) => getIt<PairingBloc>()..add(const LoadPairing()),
        ),
      ],
      child: const _SyncSettingsView(),
    );
  }
}

class _SyncSettingsView extends StatefulWidget {
  const _SyncSettingsView();

  @override
  State<_SyncSettingsView> createState() => _SyncSettingsViewState();
}

class _SyncSettingsViewState extends State<_SyncSettingsView> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  /// The ended notice is a one-time dialog, and the bloc can re-emit the same
  /// state (a rebuild, a reconcile) before the user acknowledges it.
  bool _endedNoticeShown = false;

  /// The last status a state carried. A sign-in in flight, a failed one and
  /// the state before the first load carry none, and without this a bound
  /// database drew its unbound row — "Sign in to sync" — on every sign-in.
  /// Null until a state has carried one.
  SyncStatus? _lastStatus;

  /// What the announcements judge a state against (final review D-2): the
  /// last state's step and status, whether the step in flight is a stop —
  /// an account change mid-step shows an idle flow, so it is remembered from
  /// the step's first busy flow — and the space a picker choice named, the one
  /// name the page knows; a bind decided in the tap names none.
  bool _wasStepping = false;
  bool _stepIsStop = false;
  bool _stepIsDeletion = false;

  /// Whether the deletion step in flight is "Delete account": its end is
  /// said by the account's own end, never as a cloud copy's.
  bool _stepIsAccount = false;
  SyncStatus? _spokenStatus;
  String? _bindingSpaceName;

  /// Whether the deletion section was on screen at the last state outside a
  /// step: one that was stays, held, through a delete step, so nothing
  /// above it moves on a page scrolled to its end (review K6).
  bool _deletionShownBeforeStep = false;

  /// The account whose deletion section has had something running or
  /// pending since the page opened: its deletion ending leaves the row in
  /// place as done, as a held-back row that lands stays, so nothing moves;
  /// a page opened afresh shows no section with nothing left.
  String? _deletionSeenFor;

  /// The account whose own deletion was running at the last status the page
  /// saw with anything left: a status with nothing left right after it is
  /// that run having ended the account, which the signed-out state says —
  /// not "Cloud copy deleted". Only a run ends an account, so a deletion
  /// that was waiting, or was given up on the way, ends as its copies' do
  /// and never reads as an account deleted.
  String? _accountRunSeenFor;

  /// Whether the deletion step in flight has seen its run's status running:
  /// a delete whose space was already gone needs no run, and its step's end
  /// is then what says it (review H4).
  bool _deletionRanInStep = false;

  /// The binding a step that ended is still to show, said when it does: a
  /// settle whose read failed keeps the status the step started from, and
  /// the outcome arrives with a later status (review RC2-3). Null when none
  /// is awaited.
  bool? _awaitedBinding;

  /// Whether [_spokenStatus] already carried the engine's status: until
  /// then a pause is the engine's stored one arriving, not one beginning
  /// (review RC2-4).
  bool _pauseBaseline = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _keywords(String csv) =>
      csv.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // A step in flight holds the page: a download ends on the restart
    // prompt, which the page must still be there to raise, and the app's
    // singletons still hold the database it left. The bloc's flag, not the
    // flow shown: an account change mid-step shows an idle flow (final
    // review U-1). Until it settles, however long: a page released mid-step
    // lets a second bloc overlap it (review RC1b). The bar's back arrow pops
    // through the same scope.
    return BlocSelector<SyncBloc, SyncState, bool>(
      selector: (state) => state.stepInFlight,
      builder: (context, busy) =>
          PopScope(canPop: !busy, child: _scaffold(context, l10n)),
    );
  }

  Widget _scaffold(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.sharingSettings,
        identifier: SemanticsIds.settingsBarSharing,
      ),
      body: SafeArea(
        top: false,
        child: MultiBlocListener(
          listeners: [
            BlocListener<PairingBloc, PairingState>(
              listenWhen: (previous, current) => current is PairingEnded,
              listener: (context, state) =>
                  _showEndedNotice(context, l10n, state),
            ),
            // Same dual treatment sign-in already gets: a transient snackbar
            // for the moment it happens, plus the row keeping the reason so it
            // survives the snackbar being dismissed.
            BlocListener<PairingBloc, PairingState>(
              listenWhen: (previous, current) =>
                  _failureOf(current) != null &&
                  _failureOf(previous) != _failureOf(current),
              listener: (context, state) => CustomSnackbar.showError(
                context,
                PairingErrorMessages.of(l10n).resolve(_failureOf(state)!.error),
              ),
            ),
            // The bind flow's moments, each once as the flow reaches it: the
            // picker, a failure's snackbar (the bind row keeps the reason; a
            // failed stop's row only its glyph and its spoken value), and
            // the restart a download's switch needs.
            BlocListener<SyncBloc, SyncState>(
              listenWhen: (previous, current) =>
                  _syncOf(previous).flow != _syncOf(current).flow,
              listener: (context, state) => _onBindFlow(context, l10n, state),
            ),
            // Every state, before the rebuild it causes: a builder sees only
            // the last of several states emitted in one frame.
            BlocListener<SyncBloc, SyncState>(
              listener: (context, state) {
                _announce(context, l10n, state);
                _followDeletion(state);
                if (_carriedStatusOf(state) case final status?) {
                  _lastStatus = status;
                }
                _rememberHeld(state);
              },
            ),
            BlocListener<SyncBloc, SyncState>(
              listenWhen: _deletionRunEnded,
              listener: (context, state) =>
                  _sayDeletionEnded(context, l10n, state),
            ),
            // The account's deletion ended in this signed-out state: said
            // once, as it turns up. A snackbar, so a screen reader hears it
            // too.
            BlocListener<SyncBloc, SyncState>(
              listenWhen: (previous, current) =>
                  current is SyncSignedOut &&
                  current.accountDeleted &&
                  !(previous is SyncSignedOut && previous.accountDeleted),
              listener: (context, state) => CustomSnackbar.showSuccess(
                context,
                l10n.syncDeleteAccountDone,
              ),
            ),
          ],
          child: BlocConsumer<SyncBloc, SyncState>(
            // A deletion status re-stamping a failure is not a new failure.
            listenWhen: (previous, current) =>
                current is SyncFailure &&
                (previous is! SyncFailure ||
                    previous.withDeletion(null) != current.withDeletion(null)),
            listener: (context, state) {
              if (state is SyncFailure) {
                CustomSnackbar.showError(
                  context,
                  state.action == SyncAccountAction.signOut
                      ? l10n.authSignOutFailedRetry
                      : AuthErrorMessages.of(l10n).resolve(state.error),
                );
              }
            },
            builder: (context, state) {
              return Column(
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
                    child: BlocBuilder<PairingBloc, PairingState>(
                      builder: (context, pairing) => SettingsSectionList(
                        query: _query,
                        listIdentifier: SemanticsIds.sharingList,
                        sections: _buildSections(context, l10n, state, pairing),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
    PairingState pairing,
  ) {
    return [
      SettingsSectionData(
        icon: Icons.cloud_outlined,
        title: l10n.accountSection,
        entries: [
          SettingsEntry(
            title: _titleFor(l10n, state),
            description: _descriptionFor(l10n, state),
            keywords: _keywords(l10n.sharingKeywords),
            identifier: switch (state) {
              SyncUnavailable() => SemanticsIds.sharingUnavailable,
              SyncInitial() || SyncSignedOut() => SemanticsIds.sharingSignIn,
              SyncSignedIn() ||
              SyncFailure(
                action: SyncAccountAction.signOut,
              ) => SemanticsIds.sharingSignOut,
              SyncFailure() => SemanticsIds.sharingRetry,
              _ => null,
            },
            builder: (context, title, description) =>
                _accountRow(context, l10n, state, pairing, title, description),
          ),
          // In every state but the one where no account can exist here: held
          // while nobody is signed in, like every row of this page that
          // needs an account, so a sign-in or a sign-out moves nothing below
          // and the settings search still finds it.
          if (state is! SyncUnavailable)
            _deleteAccountEntry(context, l10n, state),
        ],
      ),
      _syncSection(context, l10n, state),
      // Rendered even when signed out — a disabled row keeps the section
      // findable by the settings search, which a hidden one would not be.
      if (pairing is! PairingUnavailable)
        SettingsSectionData(
          icon: Icons.link_rounded,
          title: l10n.pairingSection,
          entries: [
            SettingsEntry(
              title: _pairingTitleFor(l10n, pairing),
              description: _pairingDescriptionFor(l10n, pairing),
              keywords: _keywords(l10n.sharingKeywords),
              identifier: switch (pairing) {
                PairingUnpaired() ||
                PairingInviting() => SemanticsIds.sharingPair,
                PairingPaired() => SemanticsIds.sharingUnpair,
                PairingEnded() => SemanticsIds.sharingClose,
                _ => null,
              },
              builder: (context, title, description) =>
                  _pairingRow(context, l10n, pairing, title, description),
            ),
          ],
        ),
      // Last, so nothing above it moves when it comes or goes.
      ?_heldBackSection(context, l10n, state),
      // Last of all, for the same reason (review H2).
      ?_deletionSection(context, l10n, state),
    ];
  }

  String _titleFor(AppLocalizations l10n, SyncState state) => switch (state) {
    SyncUnavailable() => l10n.syncUnavailablePlatform,
    SyncSignedIn(:final user) =>
      user.displayName ?? user.email ?? l10n.accountSection,
    SyncSigningIn() => l10n.signingIn,
    SyncFailure(action: SyncAccountAction.signOut) => l10n.authSignOutFailed,
    SyncFailure() => l10n.signInFailed,
    _ => l10n.signInWithGoogle,
  };

  String? _descriptionFor(AppLocalizations l10n, SyncState state) =>
      switch (state) {
        SyncUnavailable() => l10n.syncUnavailablePlatformDesc,
        SyncSignedIn(:final user) => user.uid,
        SyncSignedOut() => l10n.notSignedIn,
        // The account still signed in, as the signed-in row's second line:
        // the row keeps that shape, so nothing below it moves (review
        // D3-2). The snackbar says the rest.
        SyncFailure(action: SyncAccountAction.signOut, :final user) =>
          user?.displayName ?? user?.email ?? user?.uid,
        SyncFailure(:final error) => AuthErrorMessages.of(l10n).resolve(error),
        _ => null,
      };

  Widget _accountRow(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
    PairingState pairing,
    Widget title,
    Widget? description,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    // No account change while a bind or stop step runs: its settle must land
    // on the account it started on (final review U-1).
    final stepping = state.stepInFlight;

    switch (state) {
      case SyncUnavailable():
        return ListTile(
          enabled: false,
          leading: Icon(
            Icons.cloud_off_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          title: title,
          subtitle: description,
        );

      case SyncSigningIn():
        return ListTile(
          leading: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: title,
          subtitle: description,
        );

      case SyncSignedIn(:final user):
        return _actionRow(
          context,
          leading: UserAvatar(user: user),
          title: title,
          subtitle: description == null
              ? null
              : DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  child: description,
                ),
          action: l10n.signOut,
          onTap: () => _signOut(context, l10n, pairing),
          enabled: !stepping,
        );

      // Still signed in after a failed sign-out: the row signs out again.
      case SyncFailure(action: SyncAccountAction.signOut):
        return _actionRow(
          context,
          leading: Icon(Icons.error_outline_rounded, color: colorScheme.error),
          title: title,
          subtitle: description,
          action: l10n.signOut,
          onTap: () => _signOut(context, l10n, pairing),
          enabled: !stepping,
        );

      case SyncFailure():
        return _actionRow(
          context,
          leading: Icon(Icons.error_outline_rounded, color: colorScheme.error),
          title: title,
          subtitle: description,
          action: l10n.retry,
          onTap: () => context.read<SyncBloc>().add(const SignInRequested()),
        );

      case SyncInitial():
      case SyncSignedOut():
        return ListTile(
          enabled: !stepping,
          leading: Icon(Icons.login_rounded, color: colorScheme.primary),
          title: title,
          subtitle: description,
          onTap: () => context.read<SyncBloc>().add(const SignInRequested()),
        );
    }
  }

  /// "Delete account" (cloud-multi-user-roadmap §6.1), the Account
  /// section's destructive row. During its start — Google's prompt, then the
  /// short step — the spinner takes the glyph; after a failed one the glyph
  /// turns to the error and the reason is the row's value, as the cloud
  /// copy's row does it. Held while nobody is signed in, while another step
  /// runs and while the account's deletion is already running, which the
  /// page's last section shows.
  SettingsEntry _deleteAccountEntry(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final flow = _syncOf(state).flow;
    final starting = flow is SyncAccountDeleting;
    final deletion = _deletionOf(state);
    final running = deletion != null && deletion.account && deletion.running;
    final enabled = _signedIn(state) && !_stepping(state) && !running;
    return SettingsEntry(
      title: l10n.syncDeleteAccount,
      description: l10n.syncDeleteAccountDesc,
      // Dimmed as every disabled title is: an explicit colour would outlive
      // the disabled tile's.
      titleStyle: TextStyle(
        color: enabled || starting ? colorScheme.error : null,
      ),
      keywords: _keywords(l10n.sharingKeywords),
      identifier: SemanticsIds.sharingDeleteAccount,
      builder: (context, title, description) => _deletionRow(
        context,
        title,
        _FixedLinesSlot(
          templates: [l10n.syncDeleteAccountDesc],
          child: description!,
        ),
        glyph: Icons.person_remove_outlined,
        glyphColor: colorScheme.error,
        busy: starting,
        failure: flow is SyncBindFailed && flow.account
            ? _bindFailureText(l10n, flow, stopping: false)
            : null,
        enabled: enabled,
        onTap: () => _deleteAccount(context, l10n),
        titleAlignment: ListTileTitleAlignment.top,
      ),
    );
  }

  /// A row whose tap is its action, the action's word read as its value in
  /// the colour a button's label had. A trailing button was laid out before
  /// the title, and at 200 % in German "Erneut versuchen" left the title
  /// zero wide (S5); the value yields instead, under the description when it
  /// must. [enabled] false greys the row in place while a request runs.
  Widget _actionRow(
    BuildContext context, {
    required Widget leading,
    required Widget title,
    Widget? subtitle,
    required String action,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsYieldingTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      value: action,
      trailing: (maxWidth) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          action,
          style: TextStyle(
            color: enabled
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(
                    alpha: FormMetrics.disabledOpacity,
                  ),
          ),
        ),
      ),
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// The status and the bind flow an account state carries; the states
  /// before an account is known carry neither.
  static ({SyncStatus status, SyncBindFlow flow}) _syncOf(SyncState state) =>
      switch (state) {
        SyncSignedIn(:final status, :final flow) ||
        SyncSignedOut(
          :final status,
          :final flow,
        ) => (status: status, flow: flow),
        _ => (status: SyncStatus.empty, flow: const SyncBindIdle()),
      };

  /// Whether a step runs, though the flow [state] shows may not say so: one
  /// an account change left behind shows idle (final review U-5).
  static bool _stepping(SyncState state) =>
      state.stepInFlight || _syncOf(state).flow.isBusy;

  /// Whether the section offers what a signed-in account may do. A failed
  /// sign-out left the user signed in, as the Account row says; a failed
  /// sign-in did not (review RC3-4).
  static bool _signedIn(SyncState state) => switch (state) {
    SyncSignedIn() || SyncFailure(action: SyncAccountAction.signOut) => true,
    _ => false,
  };

  /// The status [state] itself carries; null for the states that carry
  /// none, where the section draws [_lastStatus].
  static SyncStatus? _carriedStatusOf(SyncState state) => switch (state) {
    SyncSignedIn(:final status) || SyncSignedOut(:final status) => status,
    _ => null,
  };

  /// The held-back rows listed since the page opened, by table and key, in
  /// the order first seen, each as last listed. A row that lands stays in
  /// its place, read as synced, so nothing moves under a user reading the
  /// list while the parks clear (S7 design review); a page opened afresh
  /// lists only what is held. Kept by [_rememberHeld] from the bloc's
  /// states, never from a build.
  final Map<(String, String), SyncHeldItem> _heldSeen = {};

  @override
  void initState() {
    super.initState();
    _rememberHeld(context.read<SyncBloc>().state);
  }

  /// Adds [state]'s held-back rows to [_heldSeen], or forgets them all
  /// once the database does not sync — unbound, or sync unavailable.
  void _rememberHeld(SyncState state) {
    final status = _carriedStatusOf(state) ?? _lastStatus;
    if (state is SyncUnavailable || status == null || status.binding == null) {
      _heldSeen.clear();
      return;
    }
    for (final item in status.heldBack) {
      _heldSeen[(item.table, item.rowKey)] = item;
    }
  }

  /// The rows held back, each by name with its reason (scalability record
  /// S7, the D14 promise): the status row only counts them. Read-only rows,
  /// the first [FormMetrics.syncHeldBackShown] and one that counts the rest;
  /// absent while the database does not sync, or when nothing was held
  /// since the page opened. The header counts what is held now, and says
  /// so in words once nothing is, as the intro does in its place.
  ///
  /// The rows carry no keywords: a search for "sync" must not list every
  /// held row, and a held row is found by its name.
  SettingsSectionData? _heldBackSection(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) {
    final status = _carriedStatusOf(state) ?? _lastStatus;
    if (state is SyncUnavailable ||
        status == null ||
        status.binding == null ||
        _heldSeen.isEmpty) {
      return null;
    }
    final held = {
      for (final item in status.heldBack) (item.table, item.rowKey),
    };
    final colorScheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colorScheme.onSurfaceVariant);
    final listed = _heldSeen.entries
        .take(FormMetrics.syncHeldBackShown)
        .toList();
    final unlisted = _heldSeen.length - listed.length;
    final listedKeys = {for (final entry in listed) entry.key};
    final stillHeld = held.where((key) => !listedKeys.contains(key)).length;
    final done = held.isEmpty;
    return SettingsSectionData(
      icon: Icons.sync_problem_rounded,
      title: done
          ? l10n.syncHeldBackAllDone
          : l10n.syncParkedCount(held.length),
      intro: Padding(
        padding: FormMetrics.settingsRowPadding.copyWith(
          bottom: FormMetrics.settingsRowVerticalPadding,
        ),
        // As tall as the taller of its two texts, so the rows below never
        // move when the last one goes through.
        child: Stack(
          children: [
            ExcludeSemantics(
              child: Opacity(
                opacity: 0,
                child: Text(
                  done ? l10n.syncHeldBackIntro : l10n.syncHeldBackIntroDone,
                ),
              ),
            ),
            Text(done ? l10n.syncHeldBackIntroDone : l10n.syncHeldBackIntro),
          ],
        ),
      ),
      entries: [
        for (final (index, MapEntry(:key, value: item)) in listed.indexed)
          _heldBackEntry(
            l10n,
            colorScheme,
            item,
            index: index,
            synced: !held.contains(key),
          ),
        if (unlisted > 0)
          SettingsEntry(
            // The rows it stands for still held now; once none is, it says
            // they went through, in place.
            title: stillHeld > 0
                ? l10n.syncHeldBackMoreHeld(stillHeld)
                : l10n.syncHeldBackMoreSynced(unlisted),
            titleStyle: muted,
            identifier: SemanticsIds.sharingHeldBackMore,
            builder: (context, title, description) => ListTile(
              leading: const SizedBox(width: FormMetrics.settingsLeadingWidth),
              title: title,
            ),
          ),
      ],
    );
  }

  /// One held-back row; one that went through while the page is open reads
  /// [AppLocalizations.syncHeldBackSynced] in its reason's place under a
  /// check in its kind glyph's place, its title muted, as tall as its
  /// reason made it — told apart from a held row by more than its words.
  SettingsEntry _heldBackEntry(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    SyncHeldItem item, {
    required int index,
    required bool synced,
  }) {
    final reason = _heldBackReason(l10n, item);
    return SettingsEntry(
      title: _heldBackTitle(l10n, item),
      titleStyle: synced
          ? TextStyle(color: colorScheme.onSurfaceVariant)
          : null,
      description: synced ? l10n.syncHeldBackSynced(item.kind.name) : reason,
      identifier: SemanticsIds.sharingHeldBackRow(index),
      builder: (context, title, description) => ListTile(
        titleAlignment: ListTileTitleAlignment.top,
        leading: Icon(
          synced ? Icons.check_rounded : _heldBackGlyph(item.kind),
          color: colorScheme.onSurfaceVariant,
        ),
        title: DefaultTextStyle.merge(
          maxLines: FormMetrics.syncHeldBackTitleLines,
          overflow: TextOverflow.ellipsis,
          child: title,
        ),
        subtitle: synced
            ? Stack(
                children: [
                  // The reason it replaced, unseen, keeps the row's height.
                  ExcludeSemantics(
                    child: Opacity(
                      opacity: 0,
                      child: HighlightedText(
                        text: reason,
                        style: settingsCaptionStyle,
                      ),
                    ),
                  ),
                  ?description,
                ],
              )
            : description,
      ),
    );
  }

  /// A note or a folder by its name; any other row by its kind, which is
  /// all the page can say of a calendar row or a counter, and so is a note
  /// or a folder this device holds no copy of.
  static String _heldBackTitle(AppLocalizations l10n, SyncHeldItem item) =>
      switch ((item.kind, item.name)) {
        (SyncHeldKind.note, '') => l10n.untitledNote,
        (SyncHeldKind.note || SyncHeldKind.folder, final name?)
            when name.isNotEmpty =>
          name,
        (final kind, _) => l10n.syncHeldBackKind(kind.name),
      };

  static String _heldBackReason(AppLocalizations l10n, SyncHeldItem item) {
    final reason = switch (item.reason) {
      SyncHeldReason.refused => l10n.syncHeldBackRefused,
      SyncHeldReason.unencodable => l10n.syncHeldBackUnencodable,
      SyncHeldReason.awaitingText => l10n.syncHeldBackAwaitingText,
      SyncHeldReason.unreadable => l10n.syncHeldBackUnreadable,
    };
    return item.deleted
        ? l10n.syncHeldBackDeleted(item.kind.name, reason)
        : reason;
  }

  /// The glyph names the kind of a held row; a synced one's is a check.
  static IconData _heldBackGlyph(SyncHeldKind kind) => switch (kind) {
    SyncHeldKind.note => Icons.note_outlined,
    SyncHeldKind.folder => Icons.folder_outlined,
    SyncHeldKind.event ||
    SyncHeldKind.category ||
    SyncHeldKind.template ||
    SyncHeldKind.view ||
    SyncHeldKind.filter ||
    SyncHeldKind.digest => Icons.event_outlined,
    SyncHeldKind.counter => Icons.pin_rounded,
    SyncHeldKind.vocabulary => Icons.format_list_bulleted_rounded,
    SyncHeldKind.other => Icons.sync_rounded,
  };

  /// The pauses Sync now exists to end: the engine's run lifts the quota
  /// hold and checks access again. Signed out, on another account or on an
  /// outdated app a run can do nothing.
  static const Set<SyncPause> _syncNowPauses = {
    SyncPause.none,
    SyncPause.quotaExhausted,
    SyncPause.noAccess,
    SyncPause.spaceDeleted,
  };

  /// A count as wide as any the outbox reaches, for the templates that size
  /// the status row: sized for it once, the row never grows when a count
  /// appears or gains a digit.
  static const int _countTemplate = 99999;

  /// A count of cloud copies left half deleted as wide as any install
  /// reaches — one per space the account ever deleted from here — for the
  /// Finish row's template: the outbox's width would size it for a count
  /// it never says.
  static const int _copiesTemplate = 99;

  /// A time of day as wide as the quota pause's usually is, in either
  /// clock, for the templates.
  static const TimeOfDay _quotaTimeTemplate = TimeOfDay(hour: 22, minute: 58);

  /// Rendered in every state, like Pairing: a disabled row keeps the
  /// section findable by the settings search. Unbound it is "Sync this
  /// database"; bound (D4) the status row, Sync now, the switch, the stop
  /// row and "Delete cloud copy" — signed out too, where the binding stays
  /// and pauses (D5), and while a sign-in runs or has failed, on the last
  /// status known. A deletion that runs on is shown by its own section.
  SettingsSectionData _syncSection(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) {
    final carried = _carriedStatusOf(state);
    final status = state is SyncUnavailable
        ? SyncStatus.empty
        : carried ?? _lastStatus ?? SyncStatus.empty;
    final flow = _syncOf(state).flow;
    // The rows read busy until the step ends, whatever its flow shows.
    final stepping = _stepping(state);
    final keywords = _keywords(l10n.syncKeywords);
    final bound = status.binding != null;

    if (!bound) {
      final copyOf = status.unboundAsCopyOf;
      return SettingsSectionData(
        icon: Icons.sync_rounded,
        title: l10n.syncSection,
        entries: [
          SettingsEntry(
            title: l10n.syncThisDatabase,
            description:
                (flow is SyncBindFailed && _bindOrStopFailed(flow)
                    ? _bindFailureText(l10n, flow, stopping: false)
                    : null) ??
                switch (state) {
                  SyncUnavailable() => l10n.syncThisDatabaseUnavailable,
                  // The heal stopped this copy without a word from the user
                  // (final review X-2): said until a bind clears it, where
                  // the row can act on it — signed out the row says why it
                  // cannot.
                  _ when _signedIn(state) && copyOf != null =>
                    l10n.syncUnboundAsCopyOf(copyOf),
                  SyncInitial() => l10n.syncThisDatabaseDesc,
                  _ when _signedIn(state) => l10n.syncThisDatabaseDesc,
                  _ => l10n.syncSignInFirst,
                },
            keywords: keywords,
            identifier: SemanticsIds.sharingSync,
            // One height in every unbound state, so a sign-in, a check or a
            // failure moves nothing below (final review D-5): the slot fits
            // the three fixed descriptions, and a failure's reason or the
            // heal's note ellipsizes inside it — the snackbar says a failure
            // whole.
            builder: (context, title, description) => _bindRow(
              context,
              state,
              flow,
              title,
              _FixedLinesSlot(
                templates: [
                  l10n.syncThisDatabaseDesc,
                  l10n.syncSignInFirst,
                  l10n.syncThisDatabaseUnavailable,
                ],
                child: description!,
              ),
            ),
          ),
        ],
      );
    }

    final canSync =
        _signedIn(state) &&
        _syncNowPauses.contains(status.pause) &&
        status.activity == SyncActivity.idle &&
        !stepping;
    final canDelete =
        _signedIn(state) && status.canDeleteCloudCopy && !stepping;
    final (line, glyph, carriesCount) = _statusLine(context, l10n, status);
    final automatic = status.cadence == SyncCadence.automatic;
    final lastSync = status.lastSyncAt;
    // The details (review D2-3): the last sync, the ones held back — said
    // nowhere else, so before what an ellipsis cuts first (RC3b-3) — then the
    // changes waiting unless the line above already counts them.
    final details = [
      lastSync == null
          ? l10n.syncNeverSynced
          : l10n.syncLastSynced(formatSyncMoment(context, lastSync)),
      if (status.parkedCount > 0) l10n.syncParkedCount(status.parkedCount),
      if (status.pendingCount > 0 && !carriesCount)
        l10n.syncDetailsWaiting(status.pendingCount),
    ].join(' · ');
    final colorScheme = Theme.of(context).colorScheme;

    return SettingsSectionData(
      icon: Icons.sync_rounded,
      title: l10n.syncSection,
      entries: [
        SettingsEntry(
          title: line,
          description: details,
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncStatus,
          // Sync now and Stop sit under this row, so it is as tall in every
          // state as the tallest line it may say over one details line: a
          // run starting or a count appearing moves nothing. The line and
          // the details share one slot, so the room a short state leaves
          // falls under its last line, not between the two (final review
          // D-1), and the glyph stays on the line it labels.
          builder: (context, title, description) => ListTile(
            titleAlignment: ListTileTitleAlignment.top,
            leading: Icon(glyph, color: colorScheme.onSurfaceVariant),
            title: _StatusLines(
              templates: _statusLineTemplates(context, l10n),
              line: line,
              title: title,
              details: description!,
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.syncNow,
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncNow,
          // The group's glyphs all sit on their first line, so a title that
          // wraps at 2.0 reads as the status row's does (review D2-8).
          builder: (context, title, description) => ListTile(
            titleAlignment: ListTileTitleAlignment.top,
            enabled: canSync,
            leading: Icon(
              Icons.sync_rounded,
              color: canSync
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(
                      alpha: FormMetrics.disabledOpacity,
                    ),
            ),
            title: title,
            onTap: () => context.read<SyncBloc>().add(const SyncNowRequested()),
          ),
        ),
        // The cadence (record §13): on, the engine runs by itself; off, only
        // the row above does. Local to this database, so it flips signed in
        // or out; held while a step runs, as every row is, and while the
        // state carries no status of its own (a sign-in in flight, a
        // failure) — the row then shows the last status known, where a flip
        // could not be shown. The two subtitles share one slot, so the flip
        // moves nothing below; the glyph sits on the first line like its
        // neighbours', which `SwitchListTile` has no parameter for.
        SettingsEntry(
          title: l10n.syncAutomatic,
          description: automatic
              ? l10n.syncAutomaticOnDesc
              : l10n.syncAutomaticOffDesc,
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncAutomatic,
          builder: (context, title, description) {
            final held = stepping || carried == null;
            return ListTileTheme.merge(
              titleAlignment: ListTileTitleAlignment.top,
              child: SwitchListTile(
                secondary: Icon(
                  Icons.autorenew_rounded,
                  color: held
                      ? colorScheme.onSurface.withValues(
                          alpha: FormMetrics.disabledOpacity,
                        )
                      : colorScheme.onSurfaceVariant,
                ),
                title: title,
                subtitle: _FixedLinesSlot(
                  templates: [
                    l10n.syncAutomaticOnDesc,
                    l10n.syncAutomaticOffDesc,
                  ],
                  child: description!,
                ),
                value: automatic,
                onChanged: held
                    ? null
                    : (value) => context.read<SyncBloc>().add(
                        SyncCadenceChanged(
                          value ? SyncCadence.automatic : SyncCadence.manual,
                        ),
                      ),
              ),
            );
          },
        ),
        // No failure line: a failed stop is said by its snackbar alone, so
        // the row is one height and Pairing below it never moves (final
        // review D-4).
        SettingsEntry(
          title: l10n.syncStop,
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncStop,
          // A failed sign-in keeps Stop on the last binding known: an unbind
          // is local and needs no account (D5, final review U-4). A sign-in
          // in flight still waits for its answer.
          builder: (context, title, description) =>
              carried == null && state is! SyncFailure
              ? _disabledTile(
                  context,
                  glyph: Icon(
                    Icons.sync_disabled_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  title: title,
                  description: description,
                  titleAlignment: ListTileTitleAlignment.top,
                )
              : _stopRow(
                  context,
                  l10n,
                  flow,
                  title,
                  description,
                  stepping: stepping,
                  spaceDeleted: status.pause == SyncPause.spaceDeleted,
                ),
        ),
        // The page's one destructive row (cloud-multi-user-roadmap §5), last,
        // so the row that only unbinds is met first. Held by the rule the
        // bloc refuses the request by (`canDeleteCloudCopy`): under
        // `spaceDeleted` "Stop syncing" is the way out, and "Finish
        // deleting" follows it (review S3).
        SettingsEntry(
          title: l10n.syncDeleteCloud,
          description: l10n.syncDeleteCloudDesc,
          // Dimmed as every disabled title is: an explicit colour would
          // outlive the disabled tile's.
          titleStyle: TextStyle(
            color: canDelete || flow is SyncBindDeleting
                ? colorScheme.error
                : null,
          ),
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncDelete,
          builder: (context, title, description) => _deletionRow(
            context,
            title,
            _FixedLinesSlot(
              templates: [l10n.syncDeleteCloudDesc],
              child: description!,
            ),
            glyph: Icons.delete_forever_outlined,
            glyphColor: colorScheme.error,
            busy: flow is SyncBindDeleting,
            failure: flow is SyncBindFailed && flow.deleting
                ? _bindFailureText(l10n, flow, stopping: false)
                : null,
            enabled: canDelete,
            onTap: () => _deleteCloudCopy(context, l10n),
            titleAlignment: ListTileTitleAlignment.top,
          ),
        ),
      ],
    );
  }

  /// The deletion status of the account [state] carries — a failed
  /// sign-out's included, which the bloc stamps as it does the account's
  /// (reviews H5, K3); null for every state without the account.
  static SyncDeletionStatus? _deletionOf(SyncState state) => switch (state) {
    SyncSignedIn(:final deletion) => deletion,
    SyncFailure(action: SyncAccountAction.signOut, :final deletion) => deletion,
    _ => null,
  };

  /// The deletion [state] would show in its section, a step aside: one
  /// that runs or is left unfinished, or one that ended since the page saw
  /// it live.
  SyncDeletionStatus? _shownDeletion(SyncState state) {
    final deletion = _deletionOf(state);
    if (deletion == null) return null;
    if (!deletion.isLive && deletion.accountUid != _deletionSeenFor) {
      return null;
    }
    return deletion;
  }

  /// A deletion — a cloud copy's (cloud-multi-user-roadmap §5) or the
  /// account's with its copies (§6.1) — in a section of its own, last on
  /// the page, as the held-back rows are: its coming, changing and going
  /// move nothing above it (review H2). Shown while the account's deletion
  /// runs or is left unfinished; one that ended while the page is open
  /// stays as done until the page is opened again. A delete step whose own
  /// row spins alone (review H1) brings no section in; one already on
  /// screen stays through it, held, since its leaving would shrink a page
  /// scrolled to its end under the finger (review K6).
  SettingsSectionData? _deletionSection(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) {
    final deletion = _shownDeletion(state);
    if (deletion == null) return null;
    final stepping = _stepping(state);
    final flow = _syncOf(state).flow;
    if (stepping &&
        (_deletionStep(flow) || _stepIsDeletion) &&
        !_deletionShownBeforeStep) {
      return null;
    }
    return SettingsSectionData(
      icon: Icons.delete_sweep_outlined,
      title: l10n.syncDeletionSection,
      entries: [
        _deletionEntry(
          context,
          l10n,
          deletion,
          _keywords(l10n.syncKeywords),
          done: !deletion.isLive,
          accountEnded: deletion.accountUid == _accountRunSeenFor,
          enabled: !stepping,
        ),
      ],
    );
  }

  /// The deletion section's one row. While the service's background run is
  /// in flight it spins over the documents removed so far and asks nothing;
  /// between runs it is "Finish deleting" — asked when the deletion began,
  /// so a tap finishes every one left without asking again — with the last
  /// run's failure as its value under the error glyph, held when only an
  /// update can finish it (review H3); [done], muted under a check, with no
  /// count — a resumed deletion's last run knows only its own (review K8).
  /// The title and the subtitle each sit in a slot sized from everything
  /// they may say, so the row is one height in every state, the empty
  /// subtitle of [done] included; a space's name too long for it
  /// ellipsizes, and a screen reader hears it whole.
  ///
  /// While the account itself is being deleted (cloud-multi-user-roadmap
  /// §6.1) the row is the account's: "Deleting account" over the same
  /// count, and between runs "Finish deleting account", whose tap asks
  /// again and then has Google sign the account in once more — the copies
  /// left are its part, so they are not named. [accountEnded]: the run the
  /// page last saw was deleting this account, so [done] is the account's
  /// end, said for the moment before the session's own end takes the
  /// section away.
  SettingsEntry _deletionEntry(
    BuildContext context,
    AppLocalizations l10n,
    SyncDeletionStatus deletion,
    List<String> keywords, {
    required bool done,
    required bool accountEnded,
    required bool enabled,
  }) {
    final running = deletion.running;
    final pending = deletion.pending;
    final account = deletion.account;
    final failure = done || running ? null : deletion.failure;
    final outdated = failure == SyncBindFailure.appOutdated;
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsEntry(
      title: done
          ? (accountEnded
                ? l10n.syncDeleteAccountDone
                : l10n.syncDeleteCloudDone)
          : account
          ? (running
                ? l10n.syncDeleteAccountRunning
                : l10n.syncDeleteAccountFinish)
          : running
          ? l10n.syncDeleteCloudRunning
          : l10n.syncDeleteCloudFinish,
      titleStyle: done ? TextStyle(color: colorScheme.onSurfaceVariant) : null,
      // The space's name last, so an ellipsis cuts the name and never the
      // meaning; with several left the row counts them, since a tap
      // finishes them all (review S2, S8).
      description: done
          ? null
          : running
          ? l10n.syncDeleteCloudProgress(deletion.removed)
          : outdated
          ? l10n.syncDeleteCloudFinishUpdate
          : account
          ? l10n.syncDeleteAccountFinishDesc
          : pending.length > 1
          ? l10n.syncDeleteCloudFinishMany(pending.length)
          : l10n.syncDeleteCloudFinishDesc(pending.first.spaceName),
      keywords: keywords,
      identifier: SemanticsIds.sharingSyncFinishDelete,
      builder: (context, title, description) {
        const titleAlignment = ListTileTitleAlignment.top;
        final titleSlot = FormCaptionSlot(
          candidates: [
            Text(l10n.syncDeleteCloudRunning),
            Text(l10n.syncDeleteCloudFinish),
            Text(l10n.syncDeleteCloudDone),
            Text(l10n.syncDeleteAccountRunning),
            Text(l10n.syncDeleteAccountFinish),
            Text(l10n.syncDeleteAccountDone),
          ],
          child: title,
        );
        final subtitleSlot = _FixedLinesSlot(
          templates: [
            l10n.syncDeleteCloudProgress(0),
            l10n.syncDeleteCloudProgress(_countTemplate),
            l10n.syncDeleteCloudFinishDesc(''),
            l10n.syncDeleteCloudFinishMany(_copiesTemplate),
            l10n.syncDeleteCloudFinishUpdate,
            l10n.syncDeleteAccountFinishDesc,
          ],
          child: description ?? const SizedBox.shrink(),
        );
        if (running) {
          return _BusyValue(
            busy: true,
            child: ListTile(
              titleAlignment: titleAlignment,
              leading: const _RowBusyIndicator(),
              title: titleSlot,
              subtitle: subtitleSlot,
            ),
          );
        }
        if (done) {
          return ListTile(
            titleAlignment: titleAlignment,
            leading: Icon(
              Icons.check_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            title: titleSlot,
            subtitle: subtitleSlot,
          );
        }
        final glyph = failure == null
            ? Icon(Icons.delete_sweep_outlined, color: colorScheme.primary)
            : Icon(Icons.error_outline_rounded, color: colorScheme.error);
        return Semantics(
          value: failure == null
              ? null
              : _bindFailureText(
                  l10n,
                  SyncBindFailed(failure, account: account),
                  stopping: false,
                ),
          child: !enabled || outdated
              ? _disabledTile(
                  context,
                  glyph: glyph,
                  title: titleSlot,
                  description: subtitleSlot,
                  titleAlignment: titleAlignment,
                )
              : ListTile(
                  titleAlignment: titleAlignment,
                  leading: glyph,
                  title: titleSlot,
                  subtitle: subtitleSlot,
                  onTap: account
                      ? () => _deleteAccount(context, l10n)
                      : () => context.read<SyncBloc>().add(
                          const FinishDeletingRequested(),
                        ),
                ),
        );
      },
    );
  }

  /// Everything the status row's title may say, at one count and at
  /// [_countTemplate], laid out unseen under the line it says now — the
  /// quota pause at [_quotaTimeTemplate], wider than most times it says.
  List<String> _statusLineTemplates(
    BuildContext context,
    AppLocalizations l10n,
  ) => [
    l10n.syncPausedQuotaUntil(formatSyncTimeOfDay(context, _quotaTimeTemplate)),
    l10n.syncPausedQuota,
    l10n.syncPausedSignedOut,
    l10n.syncPausedOtherAccount,
    l10n.syncPausedAppOutdated,
    l10n.syncPausedNoAccess,
    l10n.syncPausedSpaceDeleted,
    for (final count in const [1, _countTemplate]) ...[
      l10n.syncSending(count),
      l10n.syncDownloading(count),
      l10n.syncPendingCount(count),
      l10n.syncUpdatingNotes(count, count),
      l10n.syncUpdatingSending(count, count),
    ],
    l10n.syncUpdating,
    l10n.syncReceiving,
    l10n.syncOffline,
    l10n.syncRetrying,
    l10n.syncOfflineManual,
    l10n.syncFailedManual,
    l10n.syncManualIdle,
    l10n.syncUpToDate,
    l10n.syncWaitingFirst,
  ];

  /// [child] in the tile's subtitle style, for the status row's details,
  /// which sit in its title slot under the line.
  static Widget _asSubtitle(BuildContext context, Widget child) =>
      DefaultTextStyle.merge(
        style: ListTileTheme.of(context).subtitleTextStyle,
        child: child,
      );

  /// The one line that says what sync is doing, its glyph, and whether the
  /// line already counts the pending changes the details would repeat. A
  /// pause outranks a run, and a run the last failure it will retry.
  (String, IconData, bool) _statusLine(
    BuildContext context,
    AppLocalizations l10n,
    SyncStatus status,
  ) {
    const paused = Icons.pause_circle_outline_rounded;
    // Under the manual cadence nothing retries by itself and nothing keeps
    // the device current between presses, so the failure lines promise no
    // retry, the quota pause names no time it will resume at, and the idle
    // line says how a sync happens rather than "Up to date", which a week
    // later would still read so (record §13).
    final manual = status.cadence == SyncCadence.manual;
    switch (status.pause) {
      case SyncPause.quotaExhausted:
        final reset = manual ? null : status.quotaResetAfter(DateTime.now());
        return (
          reset == null
              ? l10n.syncPausedQuota
              : l10n.syncPausedQuotaUntil(formatSyncQuotaReset(context, reset)),
          paused,
          false,
        );
      case SyncPause.signedOut:
        return (l10n.syncPausedSignedOut, paused, false);
      case SyncPause.accountMismatch:
        return (l10n.syncPausedOtherAccount, paused, false);
      case SyncPause.appOutdated:
        return (l10n.syncPausedAppOutdated, paused, false);
      case SyncPause.noAccess:
        return (l10n.syncPausedNoAccess, paused, false);
      case SyncPause.spaceDeleted:
        return (l10n.syncPausedSpaceDeleted, paused, false);
      case SyncPause.none:
        break;
    }
    switch (status.activity) {
      case SyncActivity.pushing:
        if (syncUpdatingText(l10n, status) case final updating?) {
          return (updating, Icons.cloud_upload_outlined, false);
        }
        return (
          l10n.syncSending(status.pendingCount),
          Icons.cloud_upload_outlined,
          true,
        );
      // A count only the initial download after a bind and the re-read of
      // the notes after a wire update keep: an ordinary pull is over too
      // fast for one.
      case SyncActivity.pulling:
        if (syncUpdatingText(l10n, status) case final updating?) {
          return (updating, Icons.cloud_download_outlined, false);
        }
        return status.downloadedRows > 0
            ? (
                l10n.syncDownloading(status.downloadedRows),
                Icons.cloud_download_outlined,
                false,
              )
            : (l10n.syncReceiving, Icons.cloud_download_outlined, false);
      case SyncActivity.idle:
        break;
    }
    if (status.lastFailure case final failure?) {
      return failure.failure == SyncGatewayFailure.offline
          ? (
              manual ? l10n.syncOfflineManual : l10n.syncOffline,
              Icons.cloud_off_outlined,
              false,
            )
          : (
              manual ? l10n.syncFailedManual : l10n.syncRetrying,
              Icons.error_outline_rounded,
              false,
            );
    }
    if (status.pendingCount > 0) {
      return (
        l10n.syncPendingCount(status.pendingCount),
        Icons.cloud_queue_rounded,
        true,
      );
    }
    // Nothing received yet is not up to date: the details would say "Not
    // synced yet" beside it.
    if (status.lastPullAt == null) {
      return (l10n.syncWaitingFirst, Icons.cloud_queue_rounded, false);
    }
    if (manual) {
      return (l10n.syncManualIdle, Icons.cloud_outlined, false);
    }
    return (l10n.syncUpToDate, Icons.cloud_done_outlined, false);
  }

  /// [stopping] words an unknown failure as the stop's: the bind is offered
  /// only unbound, so a failure while bound is the stop's.
  String _bindFailureText(
    AppLocalizations l10n,
    SyncBindFailed failed, {
    required bool stopping,
  }) => switch (failed.failure) {
    SyncBindFailure.offline => l10n.syncFailedOffline,
    SyncBindFailure.quotaExhausted => l10n.syncFailedQuota,
    SyncBindFailure.permissionDenied => l10n.syncFailedPermission,
    SyncBindFailure.spaceGone => l10n.syncFailedSpaceGone,
    SyncBindFailure.appOutdated => l10n.syncFailedAppOutdated,
    SyncBindFailure.suspended => l10n.syncFailedSuspended,
    SyncBindFailure.alreadyBound => l10n.syncFailedAlreadyBound,
    SyncBindFailure.spaceHeldByAnotherDatabase =>
      failed.holderDatabase == null
          ? l10n.syncFailedHeldUnnamed
          : l10n.syncFailedHeld(failed.holderDatabase!),
    SyncBindFailure.invalidSpaceName => l10n.syncFailedInvalidName,
    SyncBindFailure.newDatabaseFailed => l10n.syncFailedNewDatabase,
    SyncBindFailure.otherAccount => l10n.syncFailedOtherAccount,
    SyncBindFailure.accountDeleting => l10n.syncFailedAccountDeleting,
    // Worded for what failed: a failure with no better reason must not say
    // "sync couldn't be turned on" of an account's deletion.
    SyncBindFailure.unknown =>
      failed.account
          ? l10n.syncDeleteAccountFailed
          : stopping
          ? l10n.syncStopFailed
          : l10n.syncFailedUnknown,
  };

  /// Whether [flow] is a failure of the bind or the stop — the two the Sync
  /// section's first and stop rows word as their own. A deletion's failure,
  /// a cloud copy's or the account's, is said on its own row.
  static bool _bindOrStopFailed(SyncBindFlow flow) =>
      flow is SyncBindFailed && !flow.deleting && !flow.account;

  /// Whether [flow] is a deletion's own short step — a cloud copy's or the
  /// account's — during which the deleting row spins alone and the bind and
  /// stop rows only look held (review S5).
  static bool _deletionStep(SyncBindFlow flow) =>
      flow is SyncBindDeleting || flow is SyncAccountDeleting;

  /// Enabled once signed in. While the flow checks or binds, a spinner
  /// takes the glyph's box and the tap does nothing — the text stays, so the
  /// row keeps its height. A failure's reason is its description until the
  /// next tap starts again. Before the bloc's first answer nothing is known
  /// — signed in or out, bound or not — so the first frame shows the row
  /// spinning, as a check, rather than offering a sign-in.
  Widget _bindRow(
    BuildContext context,
    SyncState state,
    SyncBindFlow flow,
    Widget title,
    Widget? description,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final loading = state is SyncInitial;
    // A deletion spins on its own row, and its failure is that row's; held
    // meanwhile, this one looks held (review S5). Held too for as long as
    // the account itself is being deleted: the service refuses every bind
    // then, since a copy made now could outlive the account.
    final deleting =
        _deletionStep(flow) || (_deletionOf(state)?.account ?? false);
    if ((!_signedIn(state) && !loading) || deleting) {
      return _disabledTile(
        context,
        glyph: Icon(Icons.cloud_sync_outlined, color: colorScheme.primary),
        title: title,
        description: description,
      );
    }
    final busy = loading || _stepping(state);
    final failed = _bindOrStopFailed(flow);
    return _BusyValue(
      busy: busy,
      child: ListTile(
        leading: busy
            ? const _RowBusyIndicator()
            : Icon(
                failed
                    ? Icons.error_outline_rounded
                    : Icons.cloud_sync_outlined,
                color: failed ? colorScheme.error : colorScheme.primary,
              ),
        title: title,
        subtitle: description,
        onTap: busy
            ? null
            : () => context.read<SyncBloc>().add(
                const SyncThisDatabaseRequested(),
              ),
      ),
    );
  }

  /// A row of this page that cannot be used now (sync signed out or
  /// unavailable, pairing signed out): the glyph and the title dimmed
  /// together, the description — the reason — kept whole in
  /// `onSurfaceVariant`, which the tile's disabled grey would have taken to
  /// under 2:1. [titleIsReason] for a row with no description that says
  /// its reason in its title ("Sign in to share"): that title is the part
  /// kept whole. Still announced disabled. The settings kit elsewhere keeps
  /// the stock disabled tile.
  Widget _disabledTile(
    BuildContext context, {
    required Widget glyph,
    required Widget title,
    Widget? description,
    bool titleIsReason = false,
    ListTileTitleAlignment? titleAlignment,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      titleAlignment: titleAlignment,
      enabled: false,
      leading: Opacity(opacity: FormMetrics.disabledOpacity, child: glyph),
      title: titleIsReason
          ? DefaultTextStyle.merge(
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              child: title,
            )
          : Opacity(
              opacity: FormMetrics.disabledOpacity,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: colorScheme.onSurface),
                child: title,
              ),
            ),
      subtitle: description == null
          ? null
          : DefaultTextStyle.merge(
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              child: description,
            ),
    );
  }

  /// Available whenever a binding exists — signed out, and paused on
  /// another account (D5's way out) — and always asks first. While
  /// [stepping] it spins and asks nothing, whatever the flow shows. After a
  /// failed stop the row draws no line (final review D-4), so the reason is
  /// its value: a screen reader hears what the red glyph means (RC3-7).
  Widget _stopRow(
    BuildContext context,
    AppLocalizations l10n,
    SyncBindFlow flow,
    Widget title,
    Widget? description, {
    bool stepping = false,
    bool spaceDeleted = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    // A deletion spins, and fails, on its own row; held meanwhile, this one
    // looks held (review S5).
    if (stepping && _deletionStep(flow)) {
      return _disabledTile(
        context,
        glyph: Icon(
          Icons.sync_disabled_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
        title: title,
        description: description,
        titleAlignment: ListTileTitleAlignment.top,
      );
    }
    final failed = _bindOrStopFailed(flow);
    final failure = flow is SyncBindFailed && failed && !stepping
        ? _bindFailureText(l10n, flow, stopping: true)
        : null;
    return _BusyValue(
      busy: stepping,
      child: Semantics(
        value: failure,
        child: ListTile(
          titleAlignment: ListTileTitleAlignment.top,
          leading: stepping
              ? const _RowBusyIndicator()
              : Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : Icons.sync_disabled_rounded,
                  color: failed
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
          title: title,
          subtitle: description,
          onTap: stepping
              ? null
              : () => _stopSyncing(context, l10n, spaceDeleted: spaceDeleted),
        ),
      ),
    );
  }

  /// Not drawn as destructive: nothing is deleted — the cloud copy stays and
  /// the database can bind again (D6 A). Under [spaceDeleted] there is no
  /// copy left to stay, so the body says what stopping still does.
  Future<void> _stopSyncing(
    BuildContext context,
    AppLocalizations l10n, {
    required bool spaceDeleted,
  }) async {
    final bloc = context.read<SyncBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.syncStopConfirmTitle,
      content: spaceDeleted
          ? l10n.syncStopConfirmBodyDeleted
          : l10n.syncStopConfirmBody,
      confirmText: l10n.syncStopConfirmAction,
      icon: Icons.sync_disabled_rounded,
      confirmIdentifier: SemanticsIds.sharingSyncStopConfirm,
    );
    if (confirmed) bloc.add(const StopSyncingRequested());
  }

  /// A destructive row of the page — "Delete cloud copy"
  /// (cloud-multi-user-roadmap §5) and "Delete account" (§6.1). While
  /// [busy], its own short step, the spinner takes the glyph and the tap
  /// does nothing, as the stop row's do during a stop; after a failed one
  /// the glyph turns to the error and [failure], the reason, is the row's
  /// value, as the stop row's is — the snackbar says it once. Held, it is
  /// this page's disabled tile.
  Widget _deletionRow(
    BuildContext context,
    Widget title,
    Widget description, {
    required IconData glyph,
    required Color glyphColor,
    required bool busy,
    required String? failure,
    required bool enabled,
    required VoidCallback onTap,
    ListTileTitleAlignment? titleAlignment,
  }) {
    if (!enabled && !busy) {
      return _disabledTile(
        context,
        glyph: Icon(glyph, color: glyphColor),
        title: title,
        description: description,
        titleAlignment: titleAlignment,
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return _BusyValue(
      busy: busy,
      child: Semantics(
        value: failure,
        child: ListTile(
          titleAlignment: titleAlignment,
          leading: busy
              ? const _RowBusyIndicator()
              : failure != null
              ? Icon(Icons.error_outline_rounded, color: colorScheme.error)
              : Icon(glyph, color: glyphColor),
          title: title,
          subtitle: description,
          onTap: busy ? null : onTap,
        ),
      ),
    );
  }

  /// Destructive, the page's one such dialog: the copy in the account is
  /// gone for good, and the body says what stays.
  Future<void> _deleteCloudCopy(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final bloc = context.read<SyncBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.syncDeleteCloudConfirmTitle,
      content: l10n.syncDeleteCloudConfirmBody,
      confirmText: l10n.syncDeleteCloudConfirmAction,
      icon: Icons.delete_forever_outlined,
      isDestructive: true,
      confirmIdentifier: SemanticsIds.sharingSyncDeleteConfirm,
    );
    if (confirmed && !bloc.isClosed) bloc.add(const DeleteCloudCopyRequested());
  }

  /// Destructive, and asked every time — from the Account section's row
  /// and from "Finish deleting account" alike: finishing marks whatever
  /// cloud copies the account has by then, so the same words hold. Google's
  /// own prompt follows the confirm.
  Future<void> _deleteAccount(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final bloc = context.read<SyncBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.syncDeleteAccountConfirmTitle,
      content: l10n.syncDeleteAccountConfirmBody,
      confirmText: l10n.syncDeleteAccount,
      icon: Icons.person_remove_outlined,
      isDestructive: true,
      confirmIdentifier: SemanticsIds.sharingDeleteAccountConfirm,
    );
    if (confirmed && !bloc.isClosed) bloc.add(const DeleteAccountRequested());
  }

  /// A failure's snackbar is the moment; the bind row keeps the reason until
  /// its next tap, which starts the step again — the bloc restarts from a
  /// failure without a dismiss, so none is sent behind the user's back. A
  /// failed stop's row keeps only its glyph, the reason as its spoken value
  /// (final review D-4, review RC3-7).
  Future<void> _onBindFlow(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) async {
    final bloc = context.read<SyncBloc>();
    final (:status, :flow) = _syncOf(state);
    switch (flow) {
      case SyncBindPicking():
        final event = await SyncSpacePickerSheet.show(context, picking: flow);
        _bindingSpaceName = switch (event) {
          MergeIntoSpaceRequested(:final space) ||
          DownloadSpaceRequested(:final space) => space.name,
          UploadAsNewSpaceRequested(:final name) => name,
          _ => null,
        };
        if (!bloc.isClosed) bloc.add(event ?? const BindFlowDismissed());
      case SyncBindFailed():
        CustomSnackbar.showError(
          context,
          _bindFailureText(
            l10n,
            flow,
            stopping: status.binding != null && _bindOrStopFailed(flow),
          ),
        );
      // The download switched the app to the new database in place; the
      // Databases page's switch asks for the same restart.
      case SyncBindIdle(switchedToDatabase: _?):
        bloc.add(const BindFlowDismissed());
        await AppDialogs.action(
          context,
          title: l10n.restartRequiredTitle,
          content: l10n.restartRequiredNewDatabase,
          actionText: l10n.exitApp,
          icon: Icons.restart_alt_rounded,
          onAction: () => SystemNavigator.pop(),
          actionIdentifier: SemanticsIds.sharingSyncRestart,
        );
      default:
        break;
    }
  }

  /// Says politely what a screen reader would otherwise miss (final review
  /// D-2, WCAG 2.2 SC 4.1.3): a bind or a stop that ended, once a status
  /// shows its outcome, and a pause that began on a status already shown —
  /// not one found on opening the page, which the page itself reads out, nor
  /// the engine's stored one arriving after the first read. A failure is not
  /// said here: its
  /// snackbar is a live region and says it. Nor a run's ticking count,
  /// which would only be noise.
  void _announce(BuildContext context, AppLocalizations l10n, SyncState state) {
    final flow = _syncOf(state).flow;
    final carried = _carriedStatusOf(state);
    final stepping = _stepping(state);
    if (flow is SyncBindChecking) _bindingSpaceName = null;
    if (flow is SyncBindDeleting && !_wasStepping) _deletionRanInStep = false;
    if (flow.isBusy) {
      _stepIsStop = flow is SyncBindStopping;
      _stepIsDeletion = _deletionStep(flow);
      _stepIsAccount = flow is SyncAccountDeleting;
      _awaitedBinding = null;
    }
    String? message;
    if (_wasStepping && !stepping && flow is SyncBindIdle) {
      // A deletion's step ends with its run going on, which the deletion
      // section shows and [_followDeletion] says the end of — unless the
      // space was already gone and no run was needed: then the step's end
      // is the deletion's (review H4). An account's is never said here: its
      // end is the signed-out state's "Account deleted".
      _awaitedBinding = _stepIsDeletion ? null : !_stepIsStop;
      if (_stepIsDeletion &&
          !_stepIsAccount &&
          !_deletionRanInStep &&
          !(_deletionOf(state)?.running ?? false)) {
        message = l10n.syncDeleteCloudDone;
      }
    }
    _wasStepping = stepping;
    if (carried != null) {
      final bound = carried.binding != null;
      if (_awaitedBinding == bound) {
        _awaitedBinding = null;
        final name = _bindingSpaceName;
        message = !bound
            ? l10n.syncAnnounceStopped
            : name == null
            ? l10n.syncAnnounceBoundUnnamed
            : l10n.syncAnnounceBound(name);
      }
      final before = _spokenStatus;
      final baseline = _pauseBaseline;
      _spokenStatus = carried;
      _pauseBaseline = context.read<SyncBloc>().engineStatusSeen;
      if (message == null &&
          baseline &&
          before != null &&
          before.binding != null &&
          bound &&
          carried.pause != before.pause &&
          carried.pause != SyncPause.none) {
        message = _statusLine(context, l10n, carried).$1;
      }
    }
    if (message == null) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  /// What the deletion section is judged by, as each state comes: the
  /// account seen deleting, whether what ran last was the account's own
  /// deletion, whether the delete step's run was seen, and whether the
  /// section is on screen outside a step.
  void _followDeletion(SyncState state) {
    final deletion = _deletionOf(state);
    if (deletion != null && deletion.isLive) {
      _deletionSeenFor = deletion.accountUid;
      _accountRunSeenFor = deletion.account && deletion.running
          ? deletion.accountUid
          : null;
    }
    if (deletion?.running ?? false) _deletionRanInStep = true;
    if (!_stepping(state)) {
      _deletionShownBeforeStep = _shownDeletion(state) != null;
    }
  }

  /// Whether the account's deletion status turned from running to ended
  /// between [previous] and [current] — on the account or on a failed
  /// sign-out, which still carries it (review K3). A status found on
  /// opening the page, or another account's, is no such turn.
  static bool _deletionRunEnded(SyncState previous, SyncState current) {
    final before = _deletionOf(previous);
    final deletion = _deletionOf(current);
    return before != null &&
        deletion != null &&
        before.accountUid == deletion.accountUid &&
        before.running &&
        !deletion.running;
  }

  /// The end of a deletion's background run, once: "Cloud copy deleted"
  /// said politely when nothing is left and nothing failed, the failure's
  /// snackbar when it stopped short — the row keeps the reason as its value.
  ///
  /// An account's run says its own: stopped with nothing failed it waits
  /// for the sign-in, and says so; ended with the account gone it says
  /// nothing here — the signed-out state that follows says "Account
  /// deleted".
  void _sayDeletionEnded(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) {
    final deletion = _deletionOf(state)!;
    final failure = deletion.failure;
    final String message;
    if (failure != null) {
      CustomSnackbar.showError(
        context,
        _bindFailureText(
          l10n,
          SyncBindFailed(failure, account: deletion.account),
          stopping: false,
        ),
      );
      return;
    } else if (deletion.account) {
      message = l10n.syncDeleteAccountFinishDesc;
    } else if (deletion.pending.isEmpty &&
        deletion.accountUid != _accountRunSeenFor) {
      message = l10n.syncDeleteCloudDone;
    } else {
      return;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  String _pairingTitleFor(AppLocalizations l10n, PairingState state) =>
      switch (state) {
        PairingSignedOut() => l10n.pairingSignInFirst,
        PairingInviting() => l10n.pairingWaiting,
        PairingPaired(:final partner) =>
          partner?.displayName == null
              ? l10n.pairingPartnerUnknown
              : l10n.pairingPairedWith(partner!.displayName!),
        PairingEnded() => l10n.pairingEndedTitle,
        _ => l10n.pairingNotPaired,
      };

  /// The recoverable failure a state is carrying, if any. Failures ride on the
  /// state they failed from, so this is the one place that digs them out.
  PairingFailure? _failureOf(PairingState state) => switch (state) {
    PairingUnpaired(:final failure) => failure,
    PairingInviting(:final failure) => failure,
    PairingPaired(:final failure) => failure,
    _ => null,
  };

  String? _pairingDescriptionFor(AppLocalizations l10n, PairingState state) {
    final failure = _failureOf(state);
    if (failure != null) {
      return PairingErrorMessages.of(l10n).resolve(failure.error);
    }

    return switch (state) {
      PairingInviting(:final code) => PairingService.formatCode(code),
      PairingEnded(:final partnerName) =>
        partnerName == null
            ? l10n.pairingEndedByPartner
            : l10n.pairingEndedBy(partnerName),
      // Says what pairing does today. Nothing syncs until Phase 02, and a bare
      // "Paired with X" invites the assumption that content is already moving.
      PairingPaired() => l10n.pairingPairedDesc,
      PairingUnpaired() => l10n.pairingNotPairedDesc,
      _ => null,
    };
  }

  Widget _pairingRow(
    BuildContext context,
    AppLocalizations l10n,
    PairingState state,
    Widget title,
    Widget? description,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (state) {
      case PairingInitial():
      case PairingLoading():
        return ListTile(
          leading: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: title,
          subtitle: description,
        );

      case PairingUnavailable():
      case PairingSignedOut():
        return _disabledTile(
          context,
          glyph: Icon(
            Icons.link_off_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          title: title,
          description: description,
          titleIsReason: description == null,
        );

      case PairingEnded():
        return _actionRow(
          context,
          leading: Icon(
            Icons.link_off_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          title: title,
          subtitle: description,
          action: l10n.close,
          onTap: () =>
              context.read<PairingBloc>().add(const EndedNoticeDismissed()),
        );

      case PairingPaired(:final partner, :final busy):
        return _actionRow(
          context,
          leading: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : partner == null
              ? Icon(Icons.link_rounded, color: colorScheme.primary)
              : UserAvatar(user: partner.toUser()),
          title: title,
          subtitle: description,
          action: l10n.unpair,
          onTap: () => _unpair(context, l10n, state),
          enabled: !busy,
        );

      case PairingUnpaired(:final busy):
      case PairingInviting(:final busy):
        return ListTile(
          leading: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.link_rounded, color: colorScheme.primary),
          title: title,
          subtitle: description,
          onTap: () => showPairingSheet(context, context.read<PairingBloc>()),
        );
    }
  }

  Future<void> _unpair(
    BuildContext context,
    AppLocalizations l10n,
    PairingPaired state,
  ) async {
    final bloc = context.read<PairingBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.unpair,
      content: l10n.pairingUnpairConfirm(
        state.partner?.displayName ?? l10n.pairingPartnerUnknown,
      ),
      confirmText: l10n.unpair,
      isDestructive: true,
      icon: Icons.link_off_rounded,
    );
    if (confirmed) bloc.add(const UnpairRequested());
  }

  /// The whole account row signs out, so a stray tap must not: it always
  /// asks, and while a pair exists it says that sharing stops too. While
  /// the account's own deletion is unfinished it says what signing out
  /// does to that instead — it gives it up (cloud-multi-user-roadmap §6.1
  /// d) — which matters more than the pause.
  Future<void> _signOut(
    BuildContext context,
    AppLocalizations l10n,
    PairingState pairing,
  ) async {
    final bloc = context.read<SyncBloc>();
    final deleting = _deletionOf(bloc.state)?.account ?? false;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.signOut,
      content: deleting
          ? l10n.signOutConfirmDeleting
          : pairing is PairingPaired
          ? l10n.pairingSignOutConfirm(
              pairing.partner?.displayName ?? l10n.pairingPartnerUnknown,
            )
          : l10n.signOutConfirm,
      confirmText: l10n.signOut,
      icon: Icons.logout_rounded,
    );
    if (confirmed) bloc.add(const SignOutRequested());
  }

  /// The app has no push notifications, so the first foreground after the
  /// partner unpaired is the only moment available to say so.
  Future<void> _showEndedNotice(
    BuildContext context,
    AppLocalizations l10n,
    PairingState state,
  ) async {
    if (_endedNoticeShown || state is! PairingEnded) return;
    _endedNoticeShown = true;
    final bloc = context.read<PairingBloc>();
    await AppDialogs.action(
      context,
      title: l10n.pairingEndedTitle,
      content: state.partnerName == null
          ? l10n.pairingEndedByPartner
          : l10n.pairingEndedBy(state.partnerName!),
      actionText: l10n.close,
      icon: Icons.link_off_rounded,
      onAction: () {
        Navigator.of(context).pop();
        bloc.add(const EndedNoticeDismissed());
      },
    );
  }
}

/// A description slot as tall as the tallest of [templates] at its width,
/// whatever [child] says: a longer text ellipsizes on the slot's last line
/// rather than growing the row. The lines are counted in the ambient style
/// the description is drawn in, under the caption role it carries.
class _FixedLinesSlot extends StatelessWidget {
  final List<String> templates;
  final Widget child;

  const _FixedLinesSlot({required this.templates, required this.child});

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(settingsCaptionStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        var lines = 1;
        for (final template in templates) {
          lines = math.max(
            lines,
            _linesOf(context, template, style, constraints.maxWidth),
          );
        }
        return FormCaptionSlot(
          candidates: [
            for (final template in templates)
              Text(template, style: settingsCaptionStyle),
          ],
          child: DefaultTextStyle.merge(
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            child: child,
          ),
        );
      },
    );
  }
}

/// The lines [text] takes in [style] at [width], laid out as a `Text` in
/// [context] would lay it out.
int _linesOf(BuildContext context, String text, TextStyle style, double width) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
  )..layout(maxWidth: width);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// The status row's text: the line over the details, in a slot as tall as
/// the tallest line [templates] may say over one details line. The slot is a
/// budget of lines: a status line shorter than the tallest leaves its lines
/// to the details, which ellipsize only past what is left (review D3-1), so
/// the time is never cut while room sits under it. A screen reader hears the
/// details whole either way.
class _StatusLines extends StatelessWidget {
  final List<String> templates;
  final String line;
  final Widget title;
  final Widget details;

  const _StatusLines({
    required this.templates,
    required this.line,
    required this.title,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var budget = 1;
        for (final template in templates) {
          budget = math.max(budget, _linesOf(context, template, style, width));
        }
        // One line more than the tallest status line: the details' own.
        final detailLines = math.max(
          1,
          budget + 1 - _linesOf(context, line, style, width),
        );
        return FormCaptionSlot(
          candidates: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FormCaptionSlot(
                  candidates: [
                    for (final template in templates) Text(template),
                  ],
                  child: const SizedBox.shrink(),
                ),
                // The details' own line: any one line of the details style
                // sizes it, so a fixed text never re-lays out the slot.
                _SyncSettingsViewState._asSubtitle(
                  context,
                  Text(
                    AppLocalizations.of(context)!.syncNeverSynced,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              _SyncSettingsViewState._asSubtitle(
                context,
                DefaultTextStyle.merge(
                  maxLines: detailLines,
                  overflow: TextOverflow.ellipsis,
                  child: details,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The spinner a Sync section row shows in its glyph's place while its step
/// runs. Silent: the row says it is working, after its name (review RC2-5).
class _RowBusyIndicator extends StatelessWidget {
  const _RowBusyIndicator();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox.square(
      dimension: FormMetrics.rowBusyIndicatorSize,
      child: CircularProgressIndicator(
        strokeWidth: FormMetrics.rowBusyIndicatorStroke,
      ),
    ),
  );
}

/// A Sync section row's value while its step runs: a screen reader hears
/// the row's name, then that it is working, rather than its idle words
/// alone (final review D-2). A value, not a label on the spinner, which
/// would be read before the name (review RC2-5).
class _BusyValue extends StatelessWidget {
  final bool busy;
  final Widget child;

  const _BusyValue({required this.busy, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    value: busy ? AppLocalizations.of(context)!.syncBusyLabel : null,
    child: child,
  );
}
