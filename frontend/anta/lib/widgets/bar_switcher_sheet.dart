import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/markdown_bar_profile.dart';
import '../services/app_navigator.dart';
import '../services/markdown_bar_service.dart';

/// A bottom sheet that lets the user search and pick a markdown bar profile.
///
/// Returns the selected [MarkdownBarProfile] via `Navigator.pop`, or null
/// if the user dismisses the sheet.
class BarSwitcherSheet extends StatefulWidget {
  /// The profile ID currently active (for highlighting).
  final String currentProfileId;

  /// Optional note ID – when provided, shows a "clear override" option.
  final String? noteId;

  const BarSwitcherSheet({
    super.key,
    required this.currentProfileId,
    this.noteId,
  });

  /// Convenience method to show this as a modal bottom sheet.
  static Future<BarSwitcherResult?> show(
    BuildContext context, {
    required String currentProfileId,
    String? noteId,
  }) {
    return showModalBottomSheet<BarSwitcherResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) =>
          BarSwitcherSheet(currentProfileId: currentProfileId, noteId: noteId),
    );
  }

  @override
  State<BarSwitcherSheet> createState() => _BarSwitcherSheetState();
}

/// Result returned by [BarSwitcherSheet].
class BarSwitcherResult {
  /// The selected profile, or null when the user chose "Use Global Bar".
  final MarkdownBarProfile? profile;

  /// Whether the user explicitly cleared the per-note override.
  final bool clearedOverride;

  const BarSwitcherResult({this.profile, this.clearedOverride = false});
}

class _BarSwitcherSheetState extends State<BarSwitcherSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<MarkdownBarProfile> _allProfiles = [];
  List<MarkdownBarProfile> _filtered = [];
  bool _loading = true;
  String? _noteOverrideId;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final svc = GetIt.I<MarkdownBarService>();
    final profiles = svc.profiles;

    String? overrideId;
    if (widget.noteId != null) {
      overrideId = await svc.getNoteBarId(widget.noteId!);
    }

    if (mounted) {
      setState(() {
        _allProfiles = profiles;
        _filtered = profiles;
        _noteOverrideId = overrideId;
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = _allProfiles;
      } else {
        _filtered = _allProfiles
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  l10n.barSwitcherTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: l10n.searchBars,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Per-note override indicator
              if (widget.noteId != null && _noteOverrideId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.noteBarOverride,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          AppNavigator.pop(
                            context,
                            const BarSwitcherResult(clearedOverride: true),
                          );
                        },
                        child: Text(l10n.clearOverride),
                      ),
                    ],
                  ),
                ),

              // List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noMatchingBars,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final profile = _filtered[index];
                          final isActive =
                              profile.id == widget.currentProfileId;

                          return ListTile(
                            leading: Icon(
                              profile.isDefault
                                  ? Icons.view_day
                                  : Icons.dashboard_customize,
                              color: isActive
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              profile.name,
                              style: isActive
                                  ? TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                            ),
                            subtitle: Text(
                              '${profile.shortcuts.where((s) => s.isVisible).length} shortcuts',
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: isActive
                                ? Icon(
                                    Icons.check_circle,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () {
                              AppNavigator.pop(
                                context,
                                BarSwitcherResult(profile: profile),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
