import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/vocabulary.dart';
import '../models/vocabulary_item.dart';
import '../services/vocabulary_service.dart';
import '../widgets/unified_app_bars.dart';

/// Full-screen form for creating or editing a [Vocabulary].
///
/// **A page, not a bottom sheet.** Editing forty exercises is a full-screen
/// task: a sheet is capped at a fraction of the screen and does not shrink for
/// the keyboard, so the list box was left with a handful of visible lines and
/// the only way to see the shape of the list was to dismiss the keyboard. A
/// `Scaffold` resizes for the keyboard on its own, which is also why there is
/// no manual `viewInsets` arithmetic anywhere here.
///
/// Terms are edited as **one per line** rather than as a list of rows. A gym
/// list arrives by paste or by typing straight down the page; a per-row UI
/// would turn that into forty taps. Lines starting with
/// [VocabularyItem.commentMarker] are section headers — they keep a long list
/// navigable and are never suggested.
/// [VocabularyService.parseTerms] does the trimming, blank-dropping and
/// de-duplication on save, and the diff-based write keeps each surviving line's
/// identity.
///
/// Returns the saved vocabulary, or `null` if cancelled.
class VocabularyEditorPage extends StatefulWidget {
  final Vocabulary? initial;

  const VocabularyEditorPage({super.key, this.initial});

  @override
  State<VocabularyEditorPage> createState() => _VocabularyEditorPageState();
}

class _VocabularyEditorPageState extends State<VocabularyEditorPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _termsController;
  late final FocusNode _termsFocus;
  late bool _isEnabled;
  bool _saving = false;

  /// Whether the name and the enable switch are showing.
  ///
  /// They fold away while the terms field has focus so the list gets the whole
  /// body — that is the point of the page. The header button re-opens them
  /// without dismissing the keyboard, so editing the name mid-session never
  /// costs a keyboard round-trip either.
  bool _detailsExpanded = true;

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
    _termsFocus = FocusNode()..addListener(_onTermsFocusChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _termsController.dispose();
    _termsFocus.removeListener(_onTermsFocusChanged);
    _termsFocus.dispose();
    super.dispose();
  }

  void _onTermsFocusChanged() {
    final expanded = !_termsFocus.hasFocus;
    if (expanded == _detailsExpanded || !mounted) return;
    setState(() => _detailsExpanded = expanded);
  }

  bool get _canSave => !_saving && _nameController.text.trim().isNotEmpty;

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

    final lines = VocabularyService.parseTerms(_termsController.text);
    final termCount = lines
        .where((line) => !VocabularyItem.isCommentText(line))
        .length;

    return Scaffold(
      appBar: UnifiedAppBar.settings(
        title: Text(_isEditing ? l10n.editVocabulary : l10n.createVocabulary),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton(
              onPressed: _canSave ? _onSave : null,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.topCenter,
                child: _detailsExpanded
                    ? Column(
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
                            onChanged: (value) =>
                                setState(() => _isEnabled = value),
                            title: Text(l10n.vocabularyEnabled),
                            subtitle: Text(l10n.vocabularyEnabledDesc),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
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
                  IconButton(
                    tooltip: l10n.vocabularyDetails,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _detailsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    onPressed: () => setState(
                      () => _detailsExpanded = !_detailsExpanded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _termsController,
                  focusNode: _termsFocus,
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
    );
  }
}
