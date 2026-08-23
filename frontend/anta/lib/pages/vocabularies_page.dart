import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/vocabulary.dart';
import '../services/vocabulary_service.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/unified_app_bars.dart';
import '../widgets/vocabulary_editor_sheet.dart';

/// Management page for the editor's suggestion lists. Create, edit, enable and
/// reorder vocabularies; the terms themselves are edited in
/// [VocabularyEditorSheet].
///
/// Order matters beyond looks: it is the tie-break the suggestion bar ranks by,
/// so dragging a list to the top makes it win ties everywhere.
///
/// Mutations go directly through [VocabularyService] (the same service-direct
/// pattern the category settings use); the in-memory `Vocabularies` cache is
/// updated by the service, so the editor reflects changes on its next open.
class VocabulariesPage extends StatefulWidget {
  const VocabulariesPage({super.key});

  @override
  State<VocabulariesPage> createState() => _VocabulariesPageState();
}

class _VocabulariesPageState extends State<VocabulariesPage> {
  VocabularyService? _service;
  List<Vocabulary> _vocabularies = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await VocabularyService.getInstance();
    if (!mounted) return;
    setState(() {
      _service = service;
      _vocabularies = service.vocabularies;
      _isLoading = false;
    });
  }

  void _refresh() {
    final service = _service;
    if (service == null) return;
    setState(() => _vocabularies = service.vocabularies);
  }

  Future<void> _create() async {
    final created = await VocabularyEditorSheet.show(context);
    if (created == null || !mounted) return;
    _refresh();
  }

  Future<void> _edit(Vocabulary vocabulary) async {
    final updated = await VocabularyEditorSheet.show(
      context,
      initial: vocabulary,
    );
    if (updated == null || !mounted) return;
    _refresh();
  }

  Future<void> _toggle(Vocabulary vocabulary, bool isEnabled) async {
    await _service?.setEnabled(vocabulary.id, isEnabled);
    if (!mounted) return;
    _refresh();
  }

  Future<void> _delete(Vocabulary vocabulary) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteVocabulary,
      content: l10n.deleteVocabularyConfirm(vocabulary.name),
      confirmText: l10n.delete,
      icon: Icons.delete_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _service?.deleteVocabulary(vocabulary.id);
    if (!mounted) return;
    _refresh();
    CustomSnackbar.showSuccess(context, l10n.vocabularyDeleted);
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final ordered = List<Vocabulary>.from(_vocabularies);
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    setState(() => _vocabularies = ordered);
    await _service?.reorder([for (final v in ordered) v.id]);
    if (!mounted) return;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SettingsAppBar(title: l10n.vocabularies, showMenuButton: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.createVocabulary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vocabularies.isEmpty
          ? _EmptyState(message: l10n.vocabulariesEmpty)
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _vocabularies.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) {
                final vocabulary = _vocabularies[index];
                return Padding(
                  key: ValueKey(vocabulary.id),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainer,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: const Icon(Icons.format_list_bulleted_rounded),
                      ),
                      title: Text(vocabulary.name),
                      subtitle: Text(
                        l10n.vocabularyTermCount(vocabulary.items.length),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: vocabulary.isEnabled,
                            onChanged: (value) => _toggle(vocabulary, value),
                          ),
                          IconButton(
                            tooltip: l10n.deleteVocabulary,
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: theme.colorScheme.error,
                            ),
                            onPressed: () => _delete(vocabulary),
                          ),
                        ],
                      ),
                      onTap: () => _edit(vocabulary),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_list_bulleted_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
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
