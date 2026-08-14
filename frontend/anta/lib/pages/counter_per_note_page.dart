import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/counter_per_note/counter_per_note_bloc.dart';
import '../bloc/counter_per_note/counter_per_note_event.dart';
import '../bloc/counter_per_note/counter_per_note_state.dart';
import '../l10n/app_localizations.dart';
import '../models/counter.dart';
import '../repositories/note_repository.dart';
import '../services/counter_service.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_loading_bar.dart';
import '../widgets/info_chip.dart';
import '../widgets/note_picker_dialog.dart';
import '../widgets/unified_app_bars.dart';
import '../utils/custom_snackbar.dart';

class CounterPerNotePage extends StatelessWidget {
  final Counter counter;

  const CounterPerNotePage({super.key, required this.counter});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CounterPerNoteBloc(
        counterService: GetIt.I<CounterService>(),
        noteRepository: GetIt.I<NoteRepository>(),
      )..add(CounterPerNoteOpened(counterId: counter.id)),
      child: _CounterPerNoteView(counter: counter),
    );
  }
}

class _CounterPerNoteView extends StatelessWidget {
  final Counter counter;

  const _CounterPerNoteView({required this.counter});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return LoadingScaffold(
      appBar: SettingsAppBar(title: l10n.counterPerNoteValues),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addNote(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: BlocBuilder<CounterPerNoteBloc, CounterPerNoteState>(
        builder: (context, state) {
          return switch (state) {
            CounterPerNoteInitial() || CounterPerNoteLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
            CounterPerNoteError(:final message) => _buildErrorState(
              context,
              l10n,
              colorScheme,
              message,
            ),
            CounterPerNoteLoaded() => _buildLoaded(context, state),
          };
        },
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    String message,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: colorScheme.error.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.read<CounterPerNoteBloc>().add(
              CounterPerNoteOpened(counterId: counter.id),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.counterRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context, CounterPerNoteLoaded state) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final entries = state.entries;

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.counterPerNoteEmpty,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _resetAll(context),
                icon: Icon(
                  Icons.restart_alt_rounded,
                  size: 18,
                  color: colorScheme.error,
                ),
                label: Text(
                  l10n.counterResetAllNotes,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            proxyDecorator: (child, index, animation) {
              return Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(12),
                child: child,
              );
            },
            onReorderItem: (oldIndex, newIndex) {
              context.read<CounterPerNoteBloc>().add(
                CounterPerNoteReorder(oldIndex: oldIndex, newIndex: newIndex),
              );
            },
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _NoteValueCard(
                key: ValueKey(entry.note.id),
                entry: entry,
                counter: state.counter,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addNote(BuildContext context) async {
    final picked = await showNotePickerDialog(context);
    if (picked == null || !context.mounted) return;
    final bloc = context.read<CounterPerNoteBloc>();
    final state = bloc.state;
    if (state is CounterPerNoteLoaded &&
        state.entries.any((e) => e.note.id == picked.id)) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        CustomSnackbar.show(context, l10n.noteAlreadyAdded);
      }
      return;
    }
    bloc.add(CounterPerNoteAddNote(noteId: picked.id));
  }

  Future<void> _resetAll(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.counterResetAllNotes,
      content: l10n.counterResetAllConfirm,
      icon: Icons.restart_alt_rounded,
    );
    if (!confirmed || !context.mounted) return;
    context.read<CounterPerNoteBloc>().add(const CounterPerNoteResetAll());
    if (context.mounted) {
      CustomSnackbar.showSuccess(context, l10n.counterResetAllSuccess);
    }
  }
}

class _NoteValueCard extends StatelessWidget {
  final NoteValueEntry entry;
  final Counter counter;

  const _NoteValueCard({super.key, required this.entry, required this.counter});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final note = entry.note;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: entry.isPinned
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: _indexInParent(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 20,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (entry.isPinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.push_pin_rounded,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              note.title.isEmpty
                                  ? l10n.untitledNote
                                  : note.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (note.preview.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            note.preview,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (action) => _handleAction(context, action),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: ListTile(
                        leading: Icon(
                          entry.isPinned
                              ? Icons.push_pin_outlined
                              : Icons.push_pin_rounded,
                        ),
                        title: Text(
                          entry.isPinned ? l10n.unpinCounter : l10n.pinCounter,
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'set',
                      child: ListTile(
                        leading: const Icon(Icons.edit_rounded),
                        title: Text(l10n.counterSetValue),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reset',
                      child: ListTile(
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: Text(l10n.resetCounter),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          l10n.removeNote,
                          style: TextStyle(color: colorScheme.error),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  icon: const Icon(Icons.remove_rounded),
                  onPressed: () => context.read<CounterPerNoteBloc>().add(
                    CounterPerNoteDecrement(noteId: note.id),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _setValueDialog(context),
                  child: Tooltip(
                    message: l10n.counterSetValue,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 80),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${entry.value}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => context.read<CounterPerNoteBloc>().add(
                    CounterPerNoteIncrement(noteId: note.id),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                InfoChip(
                  label: l10n.counterStepLabel(counter.step),
                  color: colorScheme.secondaryContainer,
                  textColor: colorScheme.onSecondaryContainer,
                ),
                InfoChip(
                  label: '${l10n.startValue}: ${counter.startValue}',
                  color: colorScheme.surfaceContainerHighest,
                  textColor: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _indexInParent(BuildContext context) {
    final state = context.read<CounterPerNoteBloc>().state;
    if (state is CounterPerNoteLoaded) {
      return state.entries.indexWhere((e) => e.note.id == entry.note.id);
    }
    return 0;
  }

  Future<void> _setValueDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final raw = await AppDialogs.textInput(
      context,
      title: l10n.counterSetValue,
      initialValue: '${entry.value}',
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
    );
    if (raw == null || !context.mounted) return;
    final value = int.tryParse(raw.trim());
    if (value == null) return;
    context.read<CounterPerNoteBloc>().add(
      CounterPerNoteSetValue(noteId: entry.note.id, value: value),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final l10n = AppLocalizations.of(context)!;
    switch (action) {
      case 'pin':
        context.read<CounterPerNoteBloc>().add(
          CounterPerNoteTogglePin(noteId: entry.note.id),
        );
        break;
      case 'set':
        await _setValueDialog(context);
        break;
      case 'reset':
        final confirmed = await AppDialogs.confirm(
          context,
          title: l10n.resetCounter,
          content: l10n.resetCounterConfirm,
          icon: Icons.restart_alt_rounded,
        );
        if (!confirmed || !context.mounted) return;
        context.read<CounterPerNoteBloc>().add(
          CounterPerNoteReset(noteId: entry.note.id),
        );
        if (context.mounted) {
          CustomSnackbar.showSuccess(context, l10n.counterResetSuccess);
        }
        break;
      case 'remove':
        final confirmed = await AppDialogs.confirm(
          context,
          title: l10n.removeNote,
          content: l10n.removeNoteConfirm,
          icon: Icons.delete_outline_rounded,
        );
        if (!confirmed || !context.mounted) return;
        context.read<CounterPerNoteBloc>().add(
          CounterPerNoteRemoveNote(noteId: entry.note.id),
        );
        break;
    }
  }
}
