import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/sync/sync_bloc.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_drawer.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// Cloud account settings. Phase 00 of cloud sync: signing in establishes the
/// identity later phases key sharing off. Nothing syncs yet.
class SyncSettingsPage extends StatelessWidget {
  const SyncSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SyncBloc>(
      create: (_) => getIt<SyncBloc>()..add(const LoadSyncStatus()),
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
        child: BlocConsumer<SyncBloc, SyncState>(
          listenWhen: (previous, current) => current is SyncFailure,
          listener: (context, state) {
            if (state is SyncFailure) {
              CustomSnackbar.showError(context, l10n.signInFailed);
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
                  child: SettingsSectionList(
                    query: _query,
                    sections: _buildSections(context, l10n, state),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
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
                _accountRow(context, l10n, state, title, description),
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
        _ => null,
      };

  Widget _accountRow(
    BuildContext context,
    AppLocalizations l10n,
    SyncState state,
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
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            foregroundImage: user.photoUrl == null
                ? null
                : NetworkImage(user.photoUrl!),
            // Offline-first app: a failed avatar fetch must degrade to the
            // icon child silently, not surface an unhandled image error.
            onForegroundImageError: user.photoUrl == null ? null : (_, _) {},
            child: Icon(Icons.person_rounded, color: colorScheme.primary),
          ),
          title: title,
          subtitle: description == null
              ? null
              : DefaultTextStyle.merge(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  child: description,
                ),
          trailing: TextButton(
            onPressed: () =>
                context.read<SyncBloc>().add(const SignOutRequested()),
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
}
