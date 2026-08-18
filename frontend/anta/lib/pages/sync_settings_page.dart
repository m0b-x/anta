import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/pairing/pairing_bloc.dart';
import '../bloc/sync/sync_bloc.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import '../services/pairing_service.dart';
import '../utils/auth_error.dart';
import '../utils/custom_snackbar.dart';
import '../utils/pairing_error.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_drawer.dart';
import '../widgets/pairing_sheet.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';
import '../widgets/user_avatar.dart';

/// Cloud account settings. Phase 00 established the identity; Phase 01 links
/// two accounts into a pair. Nothing syncs yet.
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
      drawer: const AppDrawer(),
      appBar: SettingsAppBar(title: l10n.sharingSettings),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
            builder: (context, title, description) =>
                _accountRow(context, l10n, state, pairing, title, description),
          ),
        ],
      ),
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
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 4);

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
          contentPadding: padding,
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
          contentPadding: padding,
        );

      case SyncSignedIn(:final user):
        return ListTile(
          leading: UserAvatar(user: user),
          title: title,
          subtitle: description == null
              ? null
              : DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  child: description,
                ),
          trailing: TextButton(
            onPressed: () => _signOut(context, l10n, pairing),
            child: Text(l10n.signOut),
          ),
          contentPadding: padding,
        );

      case SyncFailure():
        return ListTile(
          leading: Icon(Icons.error_outline_rounded, color: colorScheme.error),
          title: title,
          subtitle: description,
          trailing: TextButton(
            onPressed: () =>
                context.read<SyncBloc>().add(const SignInRequested()),
            child: Text(l10n.retry),
          ),
          contentPadding: padding,
        );

      case SyncInitial():
      case SyncSignedOut():
        return ListTile(
          leading: Icon(Icons.login_rounded, color: colorScheme.primary),
          title: title,
          subtitle: description,
          onTap: () => context.read<SyncBloc>().add(const SignInRequested()),
          contentPadding: padding,
        );
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
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 4);

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
          contentPadding: padding,
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
          contentPadding: padding,
        );

      case PairingEnded():
        return ListTile(
          leading: Icon(
            Icons.link_off_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
          title: title,
          subtitle: description,
          trailing: TextButton(
            onPressed: () =>
                context.read<PairingBloc>().add(const EndedNoticeDismissed()),
            child: Text(l10n.close),
          ),
          contentPadding: padding,
        );

      case PairingPaired(:final partner, :final busy):
        return ListTile(
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
          trailing: TextButton(
            onPressed: busy ? null : () => _unpair(context, l10n, state),
            child: Text(l10n.unpair),
          ),
          contentPadding: padding,
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
          contentPadding: padding,
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

  /// Signing out stops sharing, which nothing on the button says — so it only
  /// asks while a pair actually exists.
  Future<void> _signOut(
    BuildContext context,
    AppLocalizations l10n,
    PairingState pairing,
  ) async {
    final bloc = context.read<SyncBloc>();
    if (pairing is PairingPaired) {
      final confirmed = await AppDialogs.confirm(
        context,
        title: l10n.signOut,
        content: l10n.pairingSignOutConfirm(
          pairing.partner?.displayName ?? l10n.pairingPartnerUnknown,
        ),
        confirmText: l10n.signOut,
        icon: Icons.logout_rounded,
      );
      if (!confirmed) return;
    }
    bloc.add(const SignOutRequested());
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
