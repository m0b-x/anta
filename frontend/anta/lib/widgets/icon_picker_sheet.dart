import 'package:flutter/material.dart';

import '../constants/calendar_icons.dart';
import '../l10n/app_localizations.dart';

/// Modal bottom-sheet icon picker. Pops with the selected icon key, or
/// `null` if the user dismissed.
class IconPickerSheet extends StatelessWidget {
  final String? initialKey;
  final Color tint;

  const IconPickerSheet({super.key, required this.tint, this.initialKey});

  static Future<String?> show(
    BuildContext context, {
    required Color tint,
    String? initialKey,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: IconPickerSheet(initialKey: initialKey, tint: tint),
      ),
    );
  }

  String _groupLabel(AppLocalizations l10n, IconGroupId id) {
    return switch (id) {
      IconGroupId.strength => l10n.iconGroupStrength,
      IconGroupId.cardio => l10n.iconGroupCardio,
      IconGroupId.sports => l10n.iconGroupSports,
      IconGroupId.recovery => l10n.iconGroupRecovery,
      IconGroupId.body => l10n.iconGroupBody,
      IconGroupId.measurement => l10n.iconGroupMeasurement,
      IconGroupId.achievements => l10n.iconGroupAchievements,
      IconGroupId.travel => l10n.iconGroupTravel,
      IconGroupId.time => l10n.iconGroupTime,
      IconGroupId.generic => l10n.iconGroupGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // `useSafeArea: true` on the modal route avoids the status bar but has
    // proven unreliable against the bottom gesture/nav bar on real devices
    // (the last icon row rendered under it) — same fix as `EventEditorSheet`
    // / `CategoryEditorSheet`: pad the grid's bottom by the larger of the
    // keyboard inset and the system's bottom inset.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            l10n.pickIcon,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + bottomClearance),
            itemCount: CalendarIcons.groups.length,
            itemBuilder: (context, index) {
              final group = CalendarIcons.groups[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        _groupLabel(l10n, group.id),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final key in group.iconKeys)
                          _IconTile(
                            iconKey: key,
                            selected: key == initialKey,
                            tint: tint,
                            onTap: () => Navigator.of(context).pop(key),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  final String iconKey;
  final bool selected;
  final Color tint;
  final VoidCallback onTap;

  const _IconTile({
    required this.iconKey,
    required this.selected,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = CalendarIcons.forKey(iconKey);
    if (icon == null) return const SizedBox.shrink();

    final bg = selected
        ? tint.withValues(alpha: 0.18)
        : theme.colorScheme.surfaceContainerHighest;
    final fg = selected ? tint : theme.colorScheme.onSurfaceVariant;
    final border = selected
        ? Border.all(color: tint, width: 2)
        : Border.all(color: Colors.transparent, width: 2);

    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border,
        ),
        child: Icon(icon, color: fg, size: 24),
      ),
    );
  }
}
