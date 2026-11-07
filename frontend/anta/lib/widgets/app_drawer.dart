import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/sync/sync_bloc.dart';
import '../constants/app_version.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import 'app_dialogs.dart';
import '../models/app_user.dart';
import '../models/dev_options.dart';
import '../services/app_navigator.dart';
import '../services/auth_service.dart';
import '../services/dev_options_service.dart';
import '../services/permission_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/sync_moment_format.dart';
import 'drawer_sync_status.dart';
import 'form_rows.dart';
import 'user_avatar.dart';

/// The app's places — the calendar's pages, counters, the settings hub, the
/// how-to and About.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  static const Duration _tapTimeout = Duration(seconds: 2);

  void _resetTapCount() {
    setState(() {
      _tapCount = 0;
      _lastTapTime = null;
    });
  }

  Future<void> _handleIconTap(BuildContext context) async {
    final now = DateTime.now();

    // Reset if timeout expired
    if (_lastTapTime != null && now.difference(_lastTapTime!) > _tapTimeout) {
      _resetTapCount();
    }

    setState(() {
      _tapCount++;
      _lastTapTime = now;
    });

    if (_tapCount >= 5) {
      final devOptions = DevOptions.instance;
      if (!devOptions.developerModeUnlocked) {
        devOptions.developerModeUnlocked = true;
        final service = await DevOptionsService.getInstance();
        await service.saveOptions();
        HapticFeedback.mediumImpact();
        if (context.mounted) {
          AppNavigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 100));
          if (context.mounted) {
            CustomSnackbar.showSuccess(
              context,
              AppLocalizations.of(context)!.developerModeUnlocked,
            );
          }
        }
      }
      _resetTapCount();
    }
  }

  /// Closes the drawer, then pushes without awaiting: back lands on the page
  /// the drawer was opened over (D3), so nothing waits for the push's result.
  void _go(BuildContext context, Future<void> Function(BuildContext) push) {
    AppNavigator.pop(context);
    push(context);
  }

  /// A heading as the settings kit's section headers are, so TalkBack can
  /// jump between groups; it reads the label as written, never the capitals
  /// it is drawn in, which a screen reader may spell out ("A-P-P").
  Widget _buildGroupLabel(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset,
        RowMetrics.groupGap,
        RowMetrics.groupInset,
        RowMetrics.sectionLabelBottomPadding,
      ),
      child: Semantics(
        container: true,
        header: true,
        headingLevel: 2,
        label: label,
        child: ExcludeSemantics(
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: RowMetrics.sectionLabelFontSize,
              fontWeight: RowMetrics.sectionLabelFontWeight,
              letterSpacing: RowMetrics.sectionLabelLetterSpacing,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // The drawer lists places, never settings (D1 of
    // `docs/settings-rework-roadmap.md`): the hub behind the Settings row is
    // where a setting is chosen, so no page is reached two ways from here.
    return Drawer(
      child: Column(
        children: [
          // Header
          _buildHeader(context, colorScheme),

          // Menu items. The list carries its own id: a device flow reaching a
          // row past the cache extent swipes inside it, and the drawer's
          // first scrollable in a dump was the header's block, where the
          // account rode as a badge before it became this list's first row,
          // and a swipe there scrolls nothing.
          Expanded(
            child: _buildAccountScope(
              (user) => Semantics(
                identifier: SemanticsIds.drawerList,
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    if (user != null) _buildAccountRow(context, user),
                    _buildGroupLabel(context, l10n.calendar),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.calendar_month_rounded,
                      title: l10n.calendar,
                      subtitle: l10n.calendarDesc,
                      identifier: SemanticsIds.drawerCalendar,
                      onTap: () => _go(context, AppNavigator.toCalendar),
                    ),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.grid_view_rounded,
                      title: l10n.calendarOverview,
                      subtitle: l10n.calendarOverviewDesc,
                      identifier: SemanticsIds.drawerCalendarOverview,
                      onTap: () =>
                          _go(context, AppNavigator.toCalendarOverview),
                    ),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.bar_chart_rounded,
                      title: l10n.reportTitle,
                      subtitle: l10n.calendarReportRowDesc,
                      identifier: SemanticsIds.drawerCalendarReport,
                      onTap: () => _go(context, AppNavigator.toCalendarReport),
                    ),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.category_rounded,
                      title: l10n.calendarCategories,
                      subtitle: l10n.calendarCategoriesRowDesc,
                      identifier: SemanticsIds.drawerCalendarCategories,
                      onTap: () =>
                          _go(context, AppNavigator.toCalendarCategories),
                    ),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.notifications_active_rounded,
                      title: l10n.alertsTitle,
                      subtitle: l10n.alertsRowDesc,
                      identifier: SemanticsIds.drawerAlerts,
                      onTap: () => _go(context, AppNavigator.toAlerts),
                    ),

                    _buildGroupLabel(context, l10n.notes),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.pin_rounded,
                      title: l10n.counterSettings,
                      // The hub's one-line subtitle: the page's own wraps to an
                      // 80 dp row and pushes About below the fold on 360 × 780.
                      subtitle: l10n.settingsRowCountersDesc,
                      identifier: SemanticsIds.drawerCounters,
                      onTap: () =>
                          _go(context, AppNavigator.toCounterManagement),
                    ),

                    _buildGroupLabel(context, l10n.appGroupLabel),
                    _buildSettingsItem(context, l10n),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.school_rounded,
                      title: l10n.howToUseAnta,
                      subtitle: l10n.calendarGuideTitle,
                      identifier: SemanticsIds.drawerHowTo,
                      onTap: () => _go(context, AppNavigator.toCalendarGuide),
                    ),
                    _buildMenuItem(
                      context: context,
                      icon: Icons.info_outline_rounded,
                      title: l10n.about,
                      subtitle: kAppVersion,
                      identifier: SemanticsIds.drawerAbout,
                      onTap: () {
                        AppNavigator.pop(context);
                        _showAboutDialog(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 24,
        bottom: 24,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  colorScheme.surfaceContainerHigh,
                  colorScheme.surfaceContainerHighest,
                ]
              : [
                  colorScheme.primaryContainer,
                  colorScheme.primary.withValues(alpha: 0.5),
                ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Gym icon with tap (5x) or swipe-to-unlock developer mode. The
          // signed-in account is the list's first row, not a badge here: a
          // drawer row's tile carries a status and a 48 dp target, and the
          // icon's five-tap node keeps its box to itself.
          //
          // Named after the app it shows, so the tappable is never an
          // unlabelled node; what five taps do stays unsaid.
          Semantics(
            container: true,
            identifier: SemanticsIds.drawerHeaderIcon,
            label: l10n.appTitle,
            button: true,
            child: GestureDetector(
              onTap: () => _handleIconTap(context),
              onHorizontalDragEnd: (details) async {
                // Swipe left-to-right with sufficient velocity
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 200) {
                  final devOptions = DevOptions.instance;
                  if (!devOptions.developerModeUnlocked) {
                    devOptions.developerModeUnlocked = true;
                    final service = await DevOptionsService.getInstance();
                    await service.saveOptions();
                    HapticFeedback.mediumImpact();
                    if (context.mounted) {
                      AppNavigator.pop(context);
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (context.mounted) {
                        CustomSnackbar.showSuccess(
                          context,
                          l10n.developerModeUnlocked,
                        );
                      }
                    }
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  size: 37,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)!.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? colorScheme.onSurface
                        : colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.settings,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The list, given the signed-in account or null, under the account
  /// row's bloc. Both sit above the `ListView`, never in its first child:
  /// signed out the list's children are exactly the places, so a screen
  /// reader's "x of n" counts only them, and a row scrolled out of the cache
  /// and back at a large text scale finds the same bloc rather than a new
  /// read and a blank line meanwhile.
  ///
  /// The bloc lives as long as the open drawer, is created only when the
  /// row first reads it, and only loads: it never signs in, binds or syncs,
  /// so nothing the Sync page's own bloc does is raced from here.
  Widget _buildAccountScope(Widget Function(AppUser? user) list) {
    final authService = getIt<AuthService>();
    final presence = StreamBuilder<AppUser?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) => list(snapshot.data),
    );
    if (!getIt.isRegistered<SyncBloc>()) return presence;
    return BlocProvider<SyncBloc>(
      create: (_) => getIt<SyncBloc>()..add(const LoadSyncStatus()),
      child: presence,
    );
  }

  /// The signed-in account as the list's first row (§12 of
  /// `docs/cloud-sync-phase-02-own-space.md`): what sync is doing, seen from
  /// the first menu the user opens, one tap from Sync & sharing.
  Widget _buildAccountRow(BuildContext context, AppUser user) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      identifier: SemanticsIds.drawerAccount,
      child: _buildMenuTile(
        context: context,
        leading: ExcludeSemantics(
          child: UserAvatar(
            user: user,
            radius: RowMetrics.drawerAvatarRadius,
            backgroundColor: colorScheme.onSurfaceVariant,
            foregroundColor: colorScheme.surfaceContainerLow,
          ),
        ),
        title: user.displayName ?? user.email ?? l10n.accountSection,
        titleMaxLines: 1,
        subtitleWidget: getIt.isRegistered<SyncBloc>()
            ? BlocBuilder<SyncBloc, SyncState>(
                builder: (context, state) => _buildAccountStatus(
                  context,
                  state is SyncSignedIn && state.statusRead
                      ? state.status
                      : null,
                ),
              )
            : _buildAccountStatus(context, null),
        onTap: () => _go(context, AppNavigator.toSyncSettings),
      ),
    );
  }

  /// The account row's status line in a slot as tall as the lines the text
  /// scale gives it, blank until a status lands: no state, and no answer
  /// arriving after the drawer opened, moves a place below it (§12 (j),
  /// (k)). The line count follows the scale, never the words, so every
  /// state is one height.
  Widget _buildAccountStatus(BuildContext context, SyncStatus? status) {
    final colorScheme = Theme.of(context).colorScheme;
    final factor =
        MediaQuery.textScalerOf(context).scale(RowMetrics.secondLineFontSize) /
        RowMetrics.secondLineFontSize;
    final lines = factor < RowMetrics.drawerStatusTwoLineTextScale
        ? 1
        : factor < RowMetrics.drawerStatusThreeLineTextScale
        ? 2
        : 3;
    final line = status == null
        ? null
        : drawerSyncStatusLine(
            AppLocalizations.of(context)!,
            status,
            formatMoment: (at) => formatSyncMoment(context, at),
          );
    final style = _subtitleStyle(
      context,
      line != null && line.isError ? colorScheme.error : null,
    );

    return FormCaptionSlot(
      candidates: [
        Text(List.filled(lines, ' ').join('\n'), maxLines: lines, style: style),
      ],
      // Never an empty `Text`: its strut stands a dp taller than the slot's
      // template at 1.3, and the row would grow when the status lands.
      child: line == null
          ? const SizedBox.shrink()
          : Text(
              line.text,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
    );
  }

  /// The Settings row wears the permissions attention line in place of its
  /// subtitle while an essential permission is off (D2): Permissions left the
  /// drawer for the hub, and a missing permission must still be seen from
  /// the first menu the user opens.
  Widget _buildSettingsItem(BuildContext context, AppLocalizations l10n) {
    Widget row(int missing) => _buildMenuItem(
      context: context,
      icon: Icons.settings_rounded,
      title: l10n.settingsHubTitle,
      subtitle: missing > 0
          ? l10n.permissionsRowAttention(missing)
          : l10n.settingsHubRowDesc,
      subtitleColor: missing > 0 ? Theme.of(context).colorScheme.error : null,
      identifier: SemanticsIds.drawerSettings,
      onTap: () => _go(context, AppNavigator.toSettingsHub),
    );
    if (!getIt.isRegistered<PermissionService>()) return row(0);
    return ValueListenableBuilder(
      valueListenable: getIt<PermissionService>().snapshot,
      builder: (context, snapshot, _) =>
          row(snapshot?.missingEssential.length ?? 0),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Color? subtitleColor,
    required VoidCallback onTap,
    String? identifier,
  }) {
    final row = _buildMenuTile(
      context: context,
      leading: Icon(
        icon,
        size: RowMetrics.drawerGlyphSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: title,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      onTap: onTap,
    );
    if (identifier == null) return row;
    return Semantics(identifier: identifier, child: row);
  }

  /// [subtitleWidget] stands in for [subtitle] where the line is drawn in a
  /// slot of its own (the account row's status); [titleMaxLines] holds a
  /// title that is the user's own text, an account name, to its line.
  Widget _buildMenuTile({
    required BuildContext context,
    required Widget leading,
    required String title,
    int? titleMaxLines,
    String? subtitle,
    Widget? subtitleWidget,
    Color? subtitleColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Plain rows on the settings kit's tile geometry (D10): no tinted chip,
    // so a glyph names its place without competing with the header's mark.
    return ListTile(
      contentPadding: FormMetrics.settingsRowPadding,
      minVerticalPadding: FormMetrics.settingsRowVerticalPadding,
      minTileHeight: RowMetrics.singleLineMinHeight,
      minLeadingWidth: FormMetrics.settingsLeadingWidth,
      horizontalTitleGap: FormMetrics.settingsTitleGap,
      leading: leading,
      title: Text(
        title,
        maxLines: titleMaxLines,
        overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: RowMetrics.titleFontSize,
          height: FormMetrics.labelLineHeight / RowMetrics.titleFontSize,
          fontWeight: FontWeight.w400,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle:
          subtitleWidget ??
          (subtitle != null
              ? Text(subtitle, style: _subtitleStyle(context, subtitleColor))
              : null),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }

  /// One style for a place's subtitle and the account row's status: the
  /// status slot's template is laid out in it too, so the two rows' second
  /// lines are one height.
  TextStyle? _subtitleStyle(BuildContext context, Color? color) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyMedium?.copyWith(
      fontSize: RowMetrics.secondLineFontSize,
      height: FormMetrics.captionLineHeight / RowMetrics.secondLineFontSize,
      fontWeight: FontWeight.w400,
      color: color ?? theme.colorScheme.onSurfaceVariant,
    );
  }

  void _showAboutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppDialogs.about(
      context,
      icon: Image.asset(kAppIconAsset),
      name: l10n.appTitle,
      version: kAppVersion,
      description: l10n.aboutDescription,
    );
  }
}
