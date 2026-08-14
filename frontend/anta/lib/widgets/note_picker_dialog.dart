import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/note_picker/note_picker_bloc.dart';
import '../bloc/note_picker/note_picker_event.dart';
import '../bloc/note_picker/note_picker_state.dart';
import '../l10n/app_localizations.dart';
import '../models/note_metadata.dart';
import '../services/app_navigator.dart';
import '../services/note_storage_service.dart';

Future<NoteMetadata?> showNotePickerDialog(BuildContext context) {
  return showDialog<NoteMetadata>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) =>
          NotePickerBloc(storageService: GetIt.I<NoteStorageService>())
            ..add(const NotePickerOpened()),
      child: const _NotePickerDialog(),
    ),
  );
}

class _NotePickerDialog extends StatefulWidget {
  const _NotePickerDialog();

  @override
  State<_NotePickerDialog> createState() => _NotePickerDialogState();
}

class _NotePickerDialogState extends State<_NotePickerDialog> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    context.read<NotePickerBloc>().add(
      NotePickerQueryChanged(_searchController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.selectNote),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.searchNotes,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: BlocBuilder<NotePickerBloc, NotePickerState>(
                builder: (context, state) {
                  return switch (state) {
                    NotePickerInitial() || NotePickerLoading() => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    NotePickerError() => const SizedBox.shrink(),
                    NotePickerLoaded(:final paginatedNotes, :final query) =>
                      _NoteList(paginatedNotes: paginatedNotes, query: query),
                  };
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => AppNavigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _NoteList extends StatelessWidget {
  final PaginatedNotes paginatedNotes;
  final String query;

  const _NoteList({required this.paginatedNotes, required this.query});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final notes = paginatedNotes.notes;
    final showPagination = paginatedNotes.totalPages > 1;

    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              query.isEmpty ? Icons.note_outlined : Icons.search_off_rounded,
              size: 40,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              query.isEmpty ? l10n.noNotesAvailable : l10n.noNotesMatchSearch,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListView.builder(
          shrinkWrap: true,
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return ListTile(
              leading: Icon(Icons.note_alt_rounded, color: colorScheme.primary),
              title: Text(
                note.title.isEmpty ? l10n.untitledNote : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: note.preview.isNotEmpty
                  ? Text(
                      note.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              onTap: () => AppNavigator.pop(context, note),
            );
          },
        ),
        if (showPagination)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 22),
                  onPressed: paginatedNotes.currentPage > 1
                      ? () => context.read<NotePickerBloc>().add(
                          NotePickerPageChanged(paginatedNotes.currentPage - 1),
                        )
                      : null,
                  visualDensity: VisualDensity.compact,
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).previousPageTooltip,
                ),
                Text(
                  '${paginatedNotes.currentPage} / ${paginatedNotes.totalPages}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  onPressed: paginatedNotes.hasMore
                      ? () => context.read<NotePickerBloc>().add(
                          NotePickerPageChanged(paginatedNotes.currentPage + 1),
                        )
                      : null,
                  visualDensity: VisualDensity.compact,
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
