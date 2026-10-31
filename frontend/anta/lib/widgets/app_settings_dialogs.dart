import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/app_settings/app_settings_bloc.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import 'app_dialogs.dart';

/// The name the language picker gives [localeCode] (`null` for the
/// phone's), so the hub's Language row reads its value in the dialog's
/// own words.
String languageName(AppLocalizations l10n, String? localeCode) =>
    switch (localeCode) {
      'en' => l10n.english,
      'de' => l10n.german,
      'ro' => l10n.romanian,
      _ => l10n.systemDefault,
    };

/// The app language picker the settings hub opens. Completes once the
/// dialog is answered or dismissed; the change itself lands through
/// [AppSettingsBloc].
Future<void> showLanguageDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final settingsBloc = context.read<AppSettingsBloc>();
  final currentLocale = settingsBloc.state.localeCode;

  const systemDefault = '_system_';
  final selected = await AppDialogs.radioSelect<String>(
    context,
    title: l10n.selectLanguage,
    options: [
      (value: systemDefault, label: languageName(l10n, null), subtitle: null),
      (value: 'en', label: languageName(l10n, 'en'), subtitle: 'English'),
      (value: 'de', label: languageName(l10n, 'de'), subtitle: 'Deutsch'),
      (value: 'ro', label: languageName(l10n, 'ro'), subtitle: 'Română'),
    ],
    currentValue: currentLocale ?? systemDefault,
    cancelText: l10n.close,
    identifier: SemanticsIds.languageDialog,
  );
  if (selected == null) return; // cancelled
  settingsBloc.add(ChangeLocale(selected == systemDefault ? null : selected));
}

/// The theme picker the settings hub opens. Completes once the dialog is
/// answered or dismissed; the change itself lands through [AppSettingsBloc].
Future<void> showThemeDialog(BuildContext context) async {
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
    identifier: SemanticsIds.themeDialog,
  );
  if (selected == null) return;
  settingsBloc.add(ChangeThemeMode(selected));
}
