import 'package:flutter/material.dart';
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
import '../services/sync/sync_gateway.dart';
import '../services/sync/sync_status.dart';
import '../utils/auth_error.dart';
import '../utils/custom_snackbar.dart';
import '../utils/pairing_error.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
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
            // picker, a failure's snackbar (the row keeps the reason), and
            // the restart a download's switch needs.
            BlocListener<SyncBloc, SyncState>(
              listenWhen: (previous, current) =>
                  _syncOf(previous).flow != _syncOf(current).flow,
              listener: (context, state) => _onBindFlow(context, l10n, state),
            ),
          ],
          child: BlocConsumer<SyncBloc, SyncState>(
            listenWhen: (previous, current) => current is SyncFailure,
            listener: (context, state) {
              if (state is SyncFailure) {
                CustomSnackbar.showError(
                  context,
                  AuthErrorMessages.of(l10n).resolve(state.error),
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
              SyncSignedIn() => SemanticsIds.sharingSignOut,
              SyncFailure() => SemanticsIds.sharingRetry,
              _ => null,
            },
            builder: (context, title, description) =>
                _accountRow(context, l10n, state, pairing, title, description),
          ),
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
    ];
  }

  String _titleFor(AppLocalizations l10n, SyncState state) => switch (state) {
    SyncUnavailable() => l10n.syncUnavailablePlatform,
    SyncSignedIn(:final user) =>
      user.displayName ?? user.email ?? l10n.accountSection,
    SyncSigningIn() => l10n.signingIn,
    SyncFailure() => l10n.signInFailed,
    _ => l10n.signInWithGoogle,
  };

  String? _descriptionFor(AppLocalizations l10n, SyncState state) =>
      switch (state) {
        SyncUnavailable() => l10n.syncUnavailablePlatformDesc,
        SyncSignedIn(:final user) => user.uid,
        SyncSignedOut() => l10n.notSignedIn,
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
          leading: Icon(Icons.login_rounded, color: colorScheme.primary),
          title: title,
          subtitle: description,
          onTap: () => context.read<SyncBloc>().add(const SignInRequested()),
        );
    }
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

  /// Rendered in every state, like Pairing: a disabled row keeps the
  /// section findable by the settings search. Unbound it is one row, "Sync
  /// this database"; bound (D4) the status row, Sync now and the stop row —
  /// signed out too, where the binding stays and pauses (D5).
  SettingsSectionData _syncSection(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
  ) {
    final (:status, :flow) = _syncOf(state);
    final keywords = _keywords(l10n.syncKeywords);
    final bound = status.binding != null;
    final failure = flow is SyncBindFailed
        ? _bindFailureText(l10n, flow, stopping: bound)
        : null;

    if (!bound) {
      return SettingsSectionData(
        icon: Icons.sync_rounded,
        title: l10n.syncSection,
        entries: [
          SettingsEntry(
            title: l10n.syncThisDatabase,
            description:
                failure ??
                switch (state) {
                  SyncUnavailable() => l10n.syncThisDatabaseUnavailable,
                  SyncSignedIn() => l10n.syncThisDatabaseDesc,
                  _ => l10n.syncSignInFirst,
                },
            keywords: keywords,
            identifier: SemanticsIds.sharingSync,
            builder: (context, title, description) =>
                _bindRow(context, state, flow, title, description),
          ),
        ],
      );
    }

    final canSync =
        state is SyncSignedIn &&
        status.pause == SyncPause.none &&
        status.activity == SyncActivity.idle &&
        !flow.isBusy;
    final (line, glyph, carriesCount) = _statusLine(l10n, status);
    final lastSync = _lastSyncOf(status);
    final details = [
      [
        lastSync == null
            ? l10n.syncNeverSynced
            : l10n.syncLastSynced(formatSyncMoment(context, lastSync)),
        if (status.pendingCount > 0 && !carriesCount)
          l10n.syncPendingCount(status.pendingCount),
      ].join(' · '),
      if (status.parkedCount > 0) l10n.syncParkedCount(status.parkedCount),
    ].join('\n');
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
          builder: (context, title, description) => ListTile(
            leading: Icon(glyph, color: colorScheme.onSurfaceVariant),
            title: title,
            subtitle: description,
          ),
        ),
        SettingsEntry(
          title: l10n.syncNow,
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncNow,
          builder: (context, title, description) => ListTile(
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
        SettingsEntry(
          title: l10n.syncStop,
          description: failure,
          keywords: keywords,
          identifier: SemanticsIds.sharingSyncStop,
          builder: (context, title, description) =>
              _stopRow(context, l10n, flow, title, description),
        ),
      ],
    );
  }

  /// The one line that says what sync is doing, its glyph, and whether the
  /// line already counts the pending changes the details would repeat. A
  /// pause outranks a run, and a run the last failure it will retry.
  (String, IconData, bool) _statusLine(
    AppLocalizations l10n,
    SyncStatus status,
  ) {
    const paused = Icons.pause_circle_outline_rounded;
    switch (status.pause) {
      case SyncPause.quotaExhausted:
        return (l10n.syncPausedQuota, paused, false);
      case SyncPause.signedOut:
        return (l10n.syncPausedSignedOut, paused, false);
      case SyncPause.accountMismatch:
        return (l10n.syncPausedOtherAccount, paused, false);
      case SyncPause.appOutdated:
        return (l10n.syncPausedAppOutdated, paused, false);
      case SyncPause.noAccess:
        return (l10n.syncPausedNoAccess, paused, false);
      case SyncPause.none:
        break;
    }
    switch (status.activity) {
      case SyncActivity.pushing:
        return (
          l10n.syncSending(status.pendingCount),
          Icons.cloud_upload_outlined,
          true,
        );
      // A count only the initial download after a bind keeps: an ordinary
      // pull is over too fast for one.
      case SyncActivity.pulling:
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
          ? (l10n.syncOffline, Icons.cloud_off_outlined, false)
          : (l10n.syncRetrying, Icons.error_outline_rounded, false);
    }
    if (status.pendingCount > 0) {
      return (
        l10n.syncPendingCount(status.pendingCount),
        Icons.cloud_queue_rounded,
        true,
      );
    }
    return (l10n.syncUpToDate, Icons.cloud_done_outlined, false);
  }

  static DateTime? _lastSyncOf(SyncStatus status) {
    final push = status.lastPushAt;
    final pull = status.lastPullAt;
    if (push == null) return pull;
    if (pull == null) return push;
    return push.isAfter(pull) ? push : pull;
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
    SyncBindFailure.suspended => l10n.syncFailedSuspended,
    SyncBindFailure.alreadyBound => l10n.syncFailedAlreadyBound,
    SyncBindFailure.spaceHeldByAnotherDatabase =>
      failed.holderDatabase == null
          ? l10n.syncFailedHeldUnnamed
          : l10n.syncFailedHeld(failed.holderDatabase!),
    SyncBindFailure.invalidSpaceName => l10n.syncFailedInvalidName,
    SyncBindFailure.newDatabaseFailed => l10n.syncFailedNewDatabase,
    SyncBindFailure.unknown =>
      stopping ? l10n.syncStopFailed : l10n.syncFailedUnknown,
  };

  /// Enabled once signed in. While the flow checks or binds, a spinner
  /// takes the glyph's box and the tap does nothing — the text stays, so the
  /// row keeps its height. A failure's reason is its description until the
  /// next tap starts again.
  Widget _bindRow(
    BuildContext context,
    SyncState state,
    SyncBindFlow flow,
    Widget title,
    Widget? description,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final signedIn = state is SyncSignedIn;
    final busy = flow is SyncBindChecking || flow is SyncBindBinding;
    return ListTile(
      enabled: signedIn,
      leading: busy
          ? const _RowBusyIndicator()
          : Icon(
              flow is SyncBindFailed
                  ? Icons.error_outline_rounded
                  : Icons.cloud_sync_outlined,
              color: !signedIn
                  ? colorScheme.onSurfaceVariant
                  : flow is SyncBindFailed
                  ? colorScheme.error
                  : colorScheme.primary,
            ),
      title: title,
      subtitle: description,
      onTap: busy
          ? null
          : () =>
                context.read<SyncBloc>().add(const SyncThisDatabaseRequested()),
    );
  }

  /// Available whenever a binding exists — signed out, and paused on
  /// another account (D5's way out) — and always asks first.
  Widget _stopRow(
    BuildContext context,
    AppLocalizations l10n,
    SyncBindFlow flow,
    Widget title,
    Widget? description,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final stopping = flow is SyncBindStopping;
    return ListTile(
      leading: stopping
          ? const _RowBusyIndicator()
          : Icon(
              flow is SyncBindFailed
                  ? Icons.error_outline_rounded
                  : Icons.sync_disabled_rounded,
              color: flow is SyncBindFailed
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
      title: title,
      subtitle: description,
      onTap: flow.isBusy ? null : () => _stopSyncing(context, l10n),
    );
  }

  /// Not drawn as destructive: nothing is deleted — the cloud copy stays and
  /// the database can bind again (D6 A).
  Future<void> _stopSyncing(BuildContext context, AppLocalizations l10n) async {
    final bloc = context.read<SyncBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.syncStopConfirmTitle,
      content: l10n.syncStopConfirmBody,
      confirmText: l10n.syncStopConfirmAction,
      icon: Icons.sync_disabled_rounded,
      confirmIdentifier: SemanticsIds.sharingSyncStopConfirm,
    );
    if (confirmed) bloc.add(const StopSyncingRequested());
  }

  /// A failure's snackbar is the moment; the row keeps the reason until its
  /// next tap, which starts the step again — the bloc restarts from a
  /// failure without a dismiss, so none is sent behind the user's back.
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
        if (!bloc.isClosed) bloc.add(event ?? const BindFlowDismissed());
      case SyncBindFailed():
        CustomSnackbar.showError(
          context,
          _bindFailureText(l10n, flow, stopping: status.binding != null),
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
        );
      default:
        break;
    }
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
        return ListTile(
          enabled: false,
          leading: Icon(
            Icons.link_off_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          title: title,
          subtitle: description,
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
  /// asks, and while a pair exists it says that sharing stops too.
  Future<void> _signOut(
    BuildContext context,
    AppLocalizations l10n,
    PairingState pairing,
  ) async {
    final bloc = context.read<SyncBloc>();
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.signOut,
      content: pairing is PairingPaired
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

/// The spinner a Sync section row shows in its glyph's place while its step
/// runs.
class _RowBusyIndicator extends StatelessWidget {
  const _RowBusyIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: FormMetrics.rowBusyIndicatorSize,
    child: CircularProgressIndicator(
      strokeWidth: FormMetrics.rowBusyIndicatorStroke,
    ),
  );
}
