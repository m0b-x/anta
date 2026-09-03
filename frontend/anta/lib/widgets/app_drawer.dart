import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/app_settings/app_settings_bloc.dart';
import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../core/di/injection.dart';
import '../l10n/app_localizations.dart';
import 'app_dialogs.dart';
import '../models/app_user.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/dev_options.dart';
import '../services/app_navigator.dart';
import '../services/auth_service.dart';
import '../services/dev_options_service.dart';
import '../utils/custom_snackbar.dart';
import 'user_avatar.dart';

/// Global navigation drawer for app-wide settings
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

  void _openSettingsPage(
    BuildContext context,
    Future<SettingsResult?> Function(BuildContext) push,
  ) {
    AppNavigator.pop(context);
    push(context).then((result) {
      if (result == SettingsResult.openDrawer && context.mounted) {
        Scaffold.of(context).openDrawer();
      }
    });
  }

  Widget _buildGroupLabel(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Drawer(
      child: Column(
        children: [
          // Header
          _buildHeader(context, colorScheme),

          // Menu items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 4),

                _buildGroupLabel(context, l10n.calendar),
                _buildMenuItem(
                  context: context,
                  icon: Icons.calendar_month_rounded,
                  title: l10n.calendar,
                  subtitle: l10n.calendarDesc,
                  onTap: () {
                    AppNavigator.pop(context);
                    AppNavigator.toCalendar(context);
                  },
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.tune_rounded,
                  title: l10n.calendarSettingsRow,
                  subtitle: l10n.calendarSettingsRowDesc,
                  onTap: () {
                    AppNavigator.pop(context);
                    AppNavigator.toCalendarSettings(context);
                  },
                ),

                _buildGroupLabel(context, l10n.notes),
                _buildMenuItem(
                  context: context,
                  icon: Icons.text_format_rounded,
                  title: l10n.markdownShortcuts,
                  subtitle: l10n.markdownShortcutsDesc,
                  onTap: () {
                    final blocState = context.read<MarkdownBarBloc>().state;
                    final shortcuts = blocState is MarkdownBarLoaded
                        ? blocState.currentShortcuts
                        : <CustomMarkdownShortcut>[];
                    _openSettingsPage(
                      context,
                      (ctx) => AppNavigator.toMarkdownSettings(
                        ctx,
                        allShortcuts: shortcuts,
                      ),
                    );
                  },
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.pin_rounded,
                  title: l10n.counterSettings,
                  subtitle: l10n.counterSettingsDesc,
                  onTap: () => _openSettingsPage(
                    context,
                    AppNavigator.toCounterManagement,
                  ),
                ),

                const SizedBox(height: 12),
                _buildMenuItem(
                  context: context,
                  icon: Icons.cloud_sync_rounded,
                  title: l10n.sharingSettings,
                  subtitle: l10n.sharingSettingsDesc,
                  onTap: () =>
                      _openSettingsPage(context, AppNavigator.toSyncSettings),
                ),

                _buildGroupLabel(context, l10n.appGroupLabel),
                _buildMenuItem(
                  context: context,
                  icon: Icons.settings_rounded,
                  title: l10n.appSettings,
                  subtitle: l10n.appSettingsDesc,
                  onTap: () =>
                      _openSettingsPage(context, AppNavigator.toSettings),
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.storage_rounded,
                  title: l10n.databaseSettings,
                  subtitle: l10n.databaseSettingsDesc,
                  onTap: () => _openSettingsPage(
                    context,
                    AppNavigator.toDatabaseSettings,
                  ),
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.language_rounded,
                  title: l10n.languageSettings,
                  subtitle: l10n.languageSettingsDesc,
                  onTap: () {
                    AppNavigator.pop(context);
                    _showLanguageDialog(context);
                  },
                ),
                _buildMenuItem(
                  context: context,
                  icon: Icons.palette_rounded,
                  title: l10n.themeSettings,
                  subtitle: l10n.themeSettingsDesc,
                  onTap: () {
                    AppNavigator.pop(context);
                    _showThemeDialog(context);
                  },
                ),
                ListenableBuilder(
                  listenable: DevOptions.instance,
                  builder: (context, _) {
                    if (!DevOptions.instance.developerModeUnlocked) {
                      return const SizedBox.shrink();
                    }
                    return _buildMenuItem(
                      context: context,
                      icon: Icons.developer_mode_rounded,
                      title: l10n.developerOptions,
                      subtitle: l10n.developerOptionsDesc,
                      onTap: () => _openSettingsPage(
                        context,
                        AppNavigator.toDeveloperOptions,
                      ),
                    );
                  },
                ),

                const Divider(indent: 16, endIndent: 16),

                _buildMenuItem(
                  context: context,
                  icon: Icons.info_outline_rounded,
                  title: l10n.about,
                  subtitle: 'ANTA v1.0.0',
                  onTap: () {
                    AppNavigator.pop(context);
                    _showAboutDialog(context);
                  },
                ),
              ],
            ),
          ),

          // Footer
          _buildFooter(context, colorScheme),
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
          // signed-in account rides as a corner badge on the icon itself —
          // one identity mark, not a second row at a mismatched scale.
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
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
              Positioned(
                right: -10,
                bottom: -4,
                child: _buildAvatarBadge(context, colorScheme, isDark),
              ),
            ],
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

  /// Signed-in account's avatar, worn as a badge on the app icon's corner.
  /// The ring matches the header background (not the icon's), so the badge
  /// reads as cut into the icon rather than pasted on top of it. Renders
  /// nothing when signed out, so the icon looks exactly as it always has.
  Widget _buildAvatarBadge(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final authService = getIt<AuthService>();
    final ringColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.primaryContainer;

    return StreamBuilder<AppUser?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () {
            AppNavigator.pop(context);
            AppNavigator.toSyncSettings(context).then((result) {
              if (result == SettingsResult.openDrawer && context.mounted) {
                Scaffold.of(context).openDrawer();
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ringColor,
              border: Border.all(color: colorScheme.surface, width: 1.5),
            ),
            child: UserAvatar(
              user: user,
              radius: 11,
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 22, color: colorScheme.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.copyright_rounded,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '2026 ANTA',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'ANTA',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.fitness_center_rounded,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      children: [
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.aboutDescription),
      ],
    );
  }

  void _showLanguageDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settingsBloc = context.read<AppSettingsBloc>();
    final currentLocale = settingsBloc.state.localeCode;

    const systemDefault = '_system_';
    final selected = await AppDialogs.radioSelect<String>(
      context,
      title: l10n.selectLanguage,
      options: [
        (value: systemDefault, label: l10n.systemDefault, subtitle: null),
        (value: 'en', label: l10n.english, subtitle: 'English'),
        (value: 'de', label: l10n.german, subtitle: 'Deutsch'),
        (value: 'ro', label: l10n.romanian, subtitle: 'Română'),
      ],
      currentValue: currentLocale ?? systemDefault,
      cancelText: l10n.close,
    );
    if (selected == null) return; // cancelled
    settingsBloc.add(ChangeLocale(selected == systemDefault ? null : selected));
  }

  void _showThemeDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settingsBloc = context.read<AppSettingsBloc>();
    final currentTheme = settingsBloc.state.themeMode;

    final selected = await AppDialogs.choose<ThemeMode>(
      context,
      title: l10n.selectTheme,
      options: [
        (
          value: ThemeMode.system,
          label: l10n.systemTheme,
          icon: Icons.settings_brightness_rounded,
        ),
        (
          value: ThemeMode.light,
          label: l10n.lightTheme,
          icon: Icons.light_mode_rounded,
        ),
        (
          value: ThemeMode.dark,
          label: l10n.darkTheme,
          icon: Icons.dark_mode_rounded,
        ),
      ],
      currentValue: currentTheme,
      cancelText: l10n.close,
    );
    if (selected == null) return;
    settingsBloc.add(ChangeThemeMode(selected));
  }
}
