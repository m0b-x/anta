import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/vocabulary.dart';
import '../services/vocabulary_service.dart';

/// Bottom-sheet form for creating or editing a [Vocabulary].
///
/// Terms are edited as **one per line** in a single multiline field rather than
/// a list of editable rows. A gym list is forty exercises long and arrives by
/// paste or by typing straight down the page; a per-row UI would turn that into
/// forty taps. [VocabularyService.parseTerms] does the trimming, blank-dropping
/// and de-duplication on save, and the diff-based write keeps each surviving
/// term's identity.
///
/// Returns the saved vocabulary, or `null` if cancelled.
class VocabularyEditorSheet extends StatefulWidget {
  final Vocabulary? initial;

  const VocabularyEditorSheet({super.key, this.initial});

  static Future<Vocabulary?> show(
    BuildContext context, {
    Vocabulary? initial,
  }) {
    return showModalBottomSheet<Vocabulary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: VocabularyEditorSheet(initial: initial),
      ),
    );
  }

  @override
  State<VocabularyEditorSheet> createState() => _VocabularyEditorSheetState();
}

class _VocabularyEditorSheetState extends State<VocabularyEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _termsController;
  late bool _isEnabled;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _termsController = TextEditingController(
      text: VocabularyService.formatTerms(initial?.terms ?? const []),
    );
    _isEnabled = initial?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving && _nameController.text.trim().isNotEmpty;

  Future<void> _onSave() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final terms = VocabularyService.parseTerms(_termsController.text);
    final service = await VocabularyService.getInstance();

    Vocabulary saved;
    final initial = widget.initial;
    if (initial == null) {
      saved = await service.createVocabulary(
        name: name,
        terms: terms,
        isEnabled: _isEnabled,
      );
    } else {
      await service.updateVocabulary(
        id: initial.id,
        name: name,
        terms: terms,
        isEnabled: _isEnabled,
      );
      saved = initial.copyWith(name: name, isEnabled: _isEnabled);
    }

    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    final termCount = VocabularyService.parseTerms(_termsController.text).length;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    _isEditing
                        ? l10n.editVocabulary
                        : l10n.createVocabulary,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton(
                    onPressed: _canSave ? _onSave : null,
                    child: Text(l10n.save),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    autofocus: !_isEditing,
                    maxLength: 40,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: l10n.vocabularyName,
                      hintText: l10n.vocabularyNameHint,
                      helperText: l10n.vocabularyNameHelper,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isEnabled,
                    onChanged: (value) => setState(() => _isEnabled = value),
                    title: Text(l10n.vocabularyEnabled),
                    subtitle: Text(l10n.vocabularyEnabledDesc),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.vocabularyTerms,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        l10n.vocabularyTermCount(termCount),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _termsController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: l10n.vocabularyTermsHint,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
