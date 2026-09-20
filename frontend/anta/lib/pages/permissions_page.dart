import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/permissions/permissions_bloc.dart';
import '../constants/app_spacing.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import '../models/app_permission.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_drawer.dart';
import '../widgets/permission_tile.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

class PermissionsPage extends StatelessWidget {
  const PermissionsPage({super.key, this.popsToDrawer = false})
    : _service = null;

  @visibleForTesting
  const PermissionsPage.forTesting({
    super.key,
    required PermissionService service,
    this.popsToDrawer = false,
  }) : _service = service;

  final bool popsToDrawer;
  final PermissionService? _service;

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return BlocProvider<PermissionsBloc>(
      create: (_) =>
          (service == null
                ? getIt<PermissionsBloc>()
                : PermissionsBloc(service: service))
            ..add(const PermissionsStarted())
            ..add(const PermissionsRefreshRequested()),
      child: _PermissionsView(popsToDrawer: popsToDrawer),
    );
  }
}

class _PermissionsView extends StatefulWidget {
  const _PermissionsView({required this.popsToDrawer});

  final bool popsToDrawer;

  @override
  State<_PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<_PermissionsView> {
  bool _swipeEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSwipeSetting();
  }

  Future<void> _loadSwipeSetting() async {
    try {
      final settings = await SettingsService.getInstance();
      final swipe = await settings.getFolderSwipeEnabled();
      if (mounted) setState(() => _swipeEnabled = swipe);
    } catch (e) {
      debugPrint('[PermissionsPage] swipe setting unreadable: $e');
    }
  }

  void _onNotice(BuildContext context, PermissionsState state) {
    if (state is! PermissionsReady) return;
    final notice = state.notice;
    if (notice == null) return;
    if (notice.outcome != PermissionRequestOutcome.unavailable) return;
    CustomSnackbar.showError(
      context,
      AppLocalizations.of(context)!.permissionsSettingsUnavailable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      drawer: const AppDrawer(),
      drawerEnableOpenDragGesture: _swipeEnabled,
      appBar: SettingsAppBar(
        title: l10n.permissionsTitle,
        popsToDrawer: widget.popsToDrawer,
      ),
      body: SafeArea(
        top: false,
        child: BlocConsumer<PermissionsBloc, PermissionsState>(
          listenWhen: (previous, current) =>
              current is PermissionsReady &&
              current.notice != null &&
              (previous is! PermissionsReady ||
                  previous.notice?.serial != current.notice?.serial),
          listener: _onNotice,
          builder: (context, state) {
            if (state is! PermissionsReady) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.snapshot.isEmpty) {
              return _EmptyState(
                title: l10n.permissionsNoneNeeded,
                body: l10n.permissionsNoneNeededDesc,
              );
            }
            return SettingsSectionList(
              query: SettingsQuery.empty,
              header: [_SummaryBanner(snapshot: state.snapshot)],
              sections: _buildSections(context, l10n, state),
            );
          },
        ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(
    BuildContext context,
    AppLocalizations l10n,
    PermissionsReady state,
  ) {
    final essential = state.snapshot.withImportance(
      PermissionImportance.essential,
    );
    final recommended = state.snapshot.withImportance(
      PermissionImportance.recommended,
    );
    return [
      if (essential.isNotEmpty)
        SettingsSectionData(
          icon: Icons.gpp_good_outlined,
          title: l10n.permissionsEssentialSection,
          entries: [
            for (final entry in essential)
              _permissionEntry(context, l10n, state, entry),
          ],
        ),
      if (recommended.isNotEmpty)
        SettingsSectionData(
          icon: Icons.thumb_up_alt_outlined,
          title: l10n.permissionsRecommendedSection,
          entries: [
            for (final entry in recommended)
              _permissionEntry(context, l10n, state, entry),
          ],
        ),
      SettingsSectionData(
        icon: Icons.tune_rounded,
        title: l10n.permissionsOptionsSection,
        entries: [
          SettingsEntry(
            title: l10n.permissionsLaunchCheck,
            description: l10n.permissionsLaunchCheckDesc,
            builder: (context, title, description) => SwitchListTile(
              title: title,
              subtitle: description,
              value: state.launchPromptEnabled,
              onChanged: (value) => context.read<PermissionsBloc>().add(
                LaunchPromptToggled(value),
              ),
            ),
          ),
          if (state.hasAppSettings)
            SettingsEntry(
              title: l10n.permissionsSystemSettings,
              description: l10n.permissionsSystemSettingsDesc,
              builder: (context, title, description) => ListTile(
                title: title,
                subtitle: description,
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => context.read<PermissionsBloc>().add(
                  const AppSettingsRequested(),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  SettingsEntry _permissionEntry(
    BuildContext context,
    AppLocalizations l10n,
    PermissionsReady state,
    PermissionEntry entry,
  ) {
    return SettingsEntry(
      title: PermissionPresentation.titleOf(l10n, entry.permission),
      description: PermissionPresentation.descriptionOf(l10n, entry.permission),
      builder: (context, title, description) => PermissionTile(
        entry: entry,
        title: title,
        description: description,
        busy: state.isBusy,
        onRequest: () => context.read<PermissionsBloc>().add(
          PermissionRequested(entry.permission),
        ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.snapshot});

  final PermissionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final IconData icon;
    final String title;
    final String body;
    final Color background;
    final Color foreground;
    if (snapshot.needsAttention) {
      icon = Icons.gpp_maybe_rounded;
      title = l10n.permissionsAttentionTitle;
      body = l10n.permissionsRowAttention(snapshot.missingEssential.length);
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
    } else if (snapshot.hasUnknown) {
      icon = Icons.help_outline_rounded;
      title = l10n.permissionsUnknownTitle;
      body = l10n.permissionsUnknownBody;
      background = colorScheme.surfaceContainerHigh;
      foreground = colorScheme.onSurface;
    } else if (snapshot.hasMissing) {
      icon = Icons.verified_user_outlined;
      title = l10n.permissionsEssentialsOk;
      body = l10n.permissionsRecommendedBody;
      background = colorScheme.secondaryContainer;
      foreground = colorScheme.onSecondaryContainer;
    } else {
      icon = Icons.verified_rounded;
      title = l10n.permissionsAllSet;
      body = l10n.permissionsAllSetBody;
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
