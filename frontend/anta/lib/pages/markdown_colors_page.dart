import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../utils/markdown_color_syntax.dart';
import '../widgets/app_dialogs.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/color_wheel_picker.dart';
import '../widgets/unified_app_bars.dart';

/// Settings page for the markdown colour palette shared by coloured
/// text (`{name:text}`) and coloured highlights (`==name:text==`).
///
/// Presets are listed read-only for reference; custom colours are
/// name -> colour pairs the user can add, recolour, rename, or delete.
/// A custom colour may reuse a preset name to override it.
class MarkdownColorsPage extends StatefulWidget {
  const MarkdownColorsPage({super.key});

  @override
  State<MarkdownColorsPage> createState() => _MarkdownColorsPageState();
}

class _MarkdownColorsPageState extends State<MarkdownColorsPage> {
  bool _loading = true;
  SettingsService? _settings;

  /// Custom colours in insertion order; the persisted source keeps this
  /// order, so the list stays stable across reopens.
  final Map<String, Color> _custom = {};

  /// Resolved palette backing the live syntax preview. Recomputed only
  /// when the colours actually change — decoding runs the per-colour
  /// contrast resolution, which has no business running per frame.
  MarkdownColorPalette _palette = MarkdownColorPalette.presets;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await SettingsService.getInstance();
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _custom
        ..clear()
        ..addAll(palette.toCustomColorMap());
      _palette = palette;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    _palette = MarkdownColorPalette.decode(
      MarkdownColorPalette.encode(_custom),
    );
    await _settings?.setCustomColors(_custom);
  }

  Future<void> _addColor() async {
    final l10n = AppLocalizations.of(context)!;
    if (_custom.length >= MarkdownColorPalette.maxCustomColors) {
      CustomSnackbar.showError(
        context,
        l10n.markdownColorsLimitReached(MarkdownColorPalette.maxCustomColors),
      );
      return;
    }
    final name = await _promptName();
    if (name == null || !mounted) return;
    final argb = await ColorWheelDialog.show(context);
    if (argb == null) return;
    setState(() => _custom[name] = Color(argb));
    await _persist();
  }

  Future<void> _recolor(String name) async {
    final argb = await ColorWheelDialog.show(
      context,
      initialColor: _custom[name]?.toARGB32(),
    );
    if (argb == null) return;
    setState(() => _custom[name] = Color(argb));
    await _persist();
  }

  Future<void> _rename(String name) async {
    final next = await _promptName(initial: name, editing: name);
    if (next == null || next == name) return;
    // Rebuild the map so the renamed entry keeps its position rather
    // than jumping to the end.
    final rebuilt = <String, Color>{};
    for (final entry in _custom.entries) {
      rebuilt[entry.key == name ? next : entry.key] = entry.value;
    }
    setState(() {
      _custom
        ..clear()
        ..addAll(rebuilt);
    });
    await _persist();
  }

  Future<void> _delete(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.markdownColorsDeleteTitle,
      content: l10n.markdownColorsDeleteMessage(name),
      isDestructive: true,
    );
    if (!confirmed) return;
    setState(() => _custom.remove(name));
    await _persist();
  }

  /// Prompts for a colour name, normalizing and validating against the
  /// scanner's grammar so a saved name is always one the markdown can
  /// actually match. [editing] is the name being renamed, which is
  /// allowed to collide with itself.
  Future<String?> _promptName({String? initial, String? editing}) async {
    final l10n = AppLocalizations.of(context)!;
    while (true) {
      final raw = await AppDialogs.textInput(
        context,
        title: l10n.markdownColorsNameTitle,
        hintText: l10n.markdownColorsNameHint,
        initialValue: initial ?? '',
        maxLength: MarkdownColorPalette.maxNameLength,
      );
      if (raw == null) return null;
      final name = MarkdownColorPalette.normalizeName(raw);
      if (name.isEmpty) {
        if (!mounted) return null;
        CustomSnackbar.showError(context, l10n.markdownColorsNameInvalid);
        initial = raw;
        continue;
      }
      if (name != editing && _custom.containsKey(name)) {
        if (!mounted) return null;
        CustomSnackbar.showError(context, l10n.markdownColorsNameTaken(name));
        initial = raw;
        continue;
      }
      return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: SettingsAppBar(title: l10n.markdownColorsTitle),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  _buildSyntaxCard(theme, l10n, isDark),
                  _buildSectionHeader(theme, l10n.markdownColorsCustom),
                  if (_custom.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        l10n.markdownColorsEmpty,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ..._custom.keys.map(_buildCustomRow),
                  _buildSectionHeader(theme, l10n.markdownColorsPresets),
                  ...MarkdownColorPalette.presetNames.map(
                    (name) => _buildPresetRow(name, isDark),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _addColor,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    child: Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    ),
  );

  /// Live syntax reference: the examples are rendered with the same
  /// resolved palette the editor uses, so what the user sees here is
  /// exactly what a note will show.
  Widget _buildSyntaxCard(ThemeData theme, AppLocalizations l10n, bool isDark) {
    final sample = _custom.keys.isNotEmpty
        ? _custom.keys.first
        : MarkdownColorPalette.presetNames.first;
    final spec = _palette.lookup(sample);
    final base = theme.textTheme.bodyMedium;

    return Card(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.markdownColorsHowTo,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            RichText(
              text: TextSpan(
                style: base,
                children: [
                  TextSpan(text: '{$sample:', style: _monoDim(theme)),
                  TextSpan(
                    text: l10n.markdownColorsSampleText,
                    style: base?.copyWith(color: spec?.text(dark: isDark)),
                  ),
                  TextSpan(text: '}', style: _monoDim(theme)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            RichText(
              text: TextSpan(
                style: base,
                children: [
                  TextSpan(text: '==$sample:', style: _monoDim(theme)),
                  TextSpan(
                    text: l10n.markdownColorsSampleText,
                    style: base?.copyWith(
                      backgroundColor: spec?.highlight(dark: isDark),
                    ),
                  ),
                  TextSpan(text: '==', style: _monoDim(theme)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.markdownColorsFallbackNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _monoDim(ThemeData theme) => theme.textTheme.bodyMedium?.copyWith(
    fontFamily: 'monospace',
    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
  );

  Widget _buildCustomRow(String name) {
    final l10n = AppLocalizations.of(context)!;
    final color = _custom[name]!;
    return ListTile(
      leading: _swatch(color),
      title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text('{$name:…}   ==$name:…=='),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'recolor':
              _recolor(name);
            case 'rename':
              _rename(name);
            case 'delete':
              _delete(name);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'recolor',
            child: Row(
              children: [
                const Icon(Icons.palette_outlined),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.markdownColorsRecolor),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.markdownColorsRename),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.markdownColorsDelete),
              ],
            ),
          ),
        ],
      ),
      onTap: () => _recolor(name),
    );
  }

  Widget _buildPresetRow(String name, bool isDark) {
    final spec = MarkdownColorPalette.presets.lookup(name)!;
    final overridden = _custom.containsKey(name);
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: _swatch(spec.text(dark: isDark)),
      title: Text(
        name,
        style: TextStyle(
          fontFamily: 'monospace',
          decoration: overridden ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        overridden ? l10n.markdownColorsOverridden : '{$name:…}   ==$name:…==',
      ),
    );
  }

  Widget _swatch(Color color) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
      ),
    ),
  );
}
