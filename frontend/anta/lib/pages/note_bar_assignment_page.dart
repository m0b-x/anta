import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../database/database.dart';
import '../l10n/app_localizations.dart';
import '../models/markdown_bar_profile.dart';
import '../services/markdown_bar_service.dart';
import '../widgets/app_loading_bar.dart';
import '../widgets/unified_app_bars.dart';

/// Page that lets users assign (or clear) a specific markdown bar profile
/// for individual notes.
///
/// Notes without an override use the globally active bar.
class NoteBarAssignmentPage extends StatefulWidget {
  const NoteBarAssignmentPage({super.key});

  @override
  State<NoteBarAssignmentPage> createState() => _NoteBarAssignmentPageState();
}

class _NoteBarAssignmentPageState extends State<NoteBarAssignmentPage> {
  bool _loading = true;
  List<_NoteBarEntry> _entries = [];
  List<MarkdownBarProfile> _profiles = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.getInstance();
    final svc = GetIt.I<MarkdownBarService>();
    final notes = await db.noteDao.getAllNotes();
    final assignments = await svc.getAllNoteBarAssignments();
    if (!mounted) return;
    final blocState = context.read<MarkdownBarBloc>().state;
    final profiles = blocState is MarkdownBarLoaded
        ? blocState.profiles
        : svc.profiles;

    final entries = notes.map((note) {
      return _NoteBarEntry(
        noteId: note.id,
        noteTitle: note.title.isNotEmpty ? note.title : 'Untitled',
        assignedProfileId: assignments[note.id],
      );
    }).toList();

    // Sort: notes with overrides first, then alphabetically.
    entries.sort((a, b) {
      final aHas = a.assignedProfileId != null ? 0 : 1;
      final bHas = b.assignedProfileId != null ? 0 : 1;
      if (aHas != bHas) return aHas.compareTo(bHas);
      return a.noteTitle.toLowerCase().compareTo(b.noteTitle.toLowerCase());
    });

    if (mounted) {
      setState(() {
        _entries = entries;
        _profiles = profiles;
        _loading = false;
      });
    }
  }

  String _profileName(String? profileId) {
    if (profileId == null) return '';
    final p = _profiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => _profiles.first,
    );
    return p.name;
  }

  void _assignProfile(int index, String? profileId) {
    final entry = _entries[index];
    context.read<MarkdownBarBloc>().add(
      SetNoteBarAssignment(noteId: entry.noteId, profileId: profileId),
    );
    setState(() {
      _entries[index] = entry.copyWith(assignedProfileId: profileId);
    });
  }

  List<_NoteBarEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    final q = _searchQuery.toLowerCase();
    return _entries
        .where((e) => e.noteTitle.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filtered = _filteredEntries;

    return LoadingScaffold(
      appBar: SettingsAppBar(title: l10n.perNoteBarAssignment),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Description
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.perNoteBarHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
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
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(height: 4),
                // List
                Expanded(
                  child: filtered.isEmpty
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final entry = filtered[index];
                            // Find the real index in _entries for mutations.
                            final realIndex = _entries.indexWhere(
                              (e) => e.noteId == entry.noteId,
                            );
                            final hasOverride = entry.assignedProfileId != null;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: Icon(
                                  hasOverride ? Icons.link : Icons.link_off,
                                  color: hasOverride
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.3,
                                        ),
                                ),
                                title: Text(
                                  entry.noteTitle,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  hasOverride
                                      ? _profileName(entry.assignedProfileId)
                                      : l10n.useGlobalBar,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: hasOverride
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                  ),
                                ),
                                trailing: PopupMenuButton<String?>(
                                  tooltip: '',
                                  onSelected: (profileId) {
                                    _assignProfile(realIndex, profileId);
                                  },
                                  itemBuilder: (ctx) => [
                                    // "Use Global Bar" option
                                    PopupMenuItem<String?>(
                                      value: null,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.public,
                                            size: 18,
                                            color:
                                                entry.assignedProfileId == null
                                                ? theme.colorScheme.primary
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(l10n.useGlobalBar),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    // Each profile
                                    ..._profiles.map((p) {
                                      final isSelected =
                                          p.id == entry.assignedProfileId;
                                      return PopupMenuItem<String?>(
                                        value: p.id,
                                        child: Row(
                                          children: [
                                            Icon(
                                              isSelected
                                                  ? Icons.check_circle
                                                  : Icons.dashboard_customize,
                                              size: 18,
                                              color: isSelected
                                                  ? theme.colorScheme.primary
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                p.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// Internal model pairing a note with its bar assignment.
class _NoteBarEntry {
  final String noteId;
  final String noteTitle;
  final String? assignedProfileId;

  const _NoteBarEntry({
    required this.noteId,
    required this.noteTitle,
    this.assignedProfileId,
  });

  _NoteBarEntry copyWith({String? assignedProfileId}) {
    return _NoteBarEntry(
      noteId: noteId,
      noteTitle: noteTitle,
      assignedProfileId: assignedProfileId,
    );
  }
}
