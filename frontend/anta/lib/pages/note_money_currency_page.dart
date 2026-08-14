import 'package:flutter/material.dart';

import '../database/database.dart';
import '../l10n/app_localizations.dart';
import '../services/settings_service.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/app_loading_bar.dart';
import '../widgets/unified_app_bars.dart';

/// Page that lets users assign (or clear) a specific money currency
/// for individual notes.
///
/// Notes without an override use the globally configured currency.
class NoteMoneyCurrencyPage extends StatefulWidget {
  const NoteMoneyCurrencyPage({super.key});

  @override
  State<NoteMoneyCurrencyPage> createState() => _NoteMoneyCurrencyPageState();
}

class _NoteMoneyCurrencyPageState extends State<NoteMoneyCurrencyPage> {
  static const List<({String symbol, bool suffix})> _presets = [
    (symbol: 'lei', suffix: true),
    (symbol: '€', suffix: false),
    (symbol: r'$', suffix: false),
  ];

  bool _loading = true;
  List<_NoteCurrencyEntry> _entries = [];
  bool _globalSuffix = false;
  String _searchQuery = '';
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.getInstance();
    final settings = await SettingsService.getInstance();
    final notes = await db.noteDao.getAllNotes();
    final globalConfig = await settings.getMoneyConfig();

    final entries = <_NoteCurrencyEntry>[];
    for (final note in notes) {
      final override = await settings.getNoteMoneyCurrency(note.id);
      entries.add(
        _NoteCurrencyEntry(
          noteId: note.id,
          noteTitle: note.title,
          override: override,
        ),
      );
    }

    // Sort: notes with overrides first, then alphabetically.
    entries.sort((a, b) {
      final aHas = a.override != null ? 0 : 1;
      final bHas = b.override != null ? 0 : 1;
      if (aHas != bHas) return aHas.compareTo(bHas);
      return a.noteTitle.toLowerCase().compareTo(b.noteTitle.toLowerCase());
    });

    if (mounted) {
      setState(() {
        _settings = settings;
        _globalSuffix = globalConfig.suffix;
        _entries = entries;
        _loading = false;
      });
    }
  }

  void _setOverride(int index, ({String symbol, bool suffix})? currency) {
    final entry = _entries[index];
    _settings?.setNoteMoneyCurrency(entry.noteId, currency: currency);
    setState(() {
      _entries[index] = entry.copyWith(override: currency);
    });
  }

  Future<void> _editCustomSymbol(int index) async {
    final entry = _entries[index];
    final result = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.moneyCustomSymbol,
      initialValue: entry.override?.symbol ?? '',
      maxLength: 8,
    );
    if (result == null) return;
    final symbol = result.trim();
    if (symbol.isEmpty) return;
    _setOverride(index, (symbol: symbol, suffix: _globalSuffix));
  }

  List<_NoteCurrencyEntry> get _filteredEntries {
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
      appBar: SettingsAppBar(title: l10n.moneyPerNoteCurrency),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.searchNotes,
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
                // List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            l10n.noNotesMatchSearch,
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
                            final hasOverride = entry.override != null;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: ListTile(
                                leading: Icon(
                                  hasOverride
                                      ? Icons.payments
                                      : Icons.payments_outlined,
                                  color: hasOverride
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: 0.3,
                                        ),
                                ),
                                title: Text(
                                  entry.noteTitle.isNotEmpty
                                      ? entry.noteTitle
                                      : l10n.untitledNote,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  hasOverride
                                      ? entry.override!.symbol
                                      : l10n.useGlobalCurrency,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: hasOverride
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                  ),
                                ),
                                trailing: PopupMenuButton<int>(
                                  tooltip: '',
                                  onSelected: (value) {
                                    if (value < 0) {
                                      _setOverride(realIndex, null);
                                    } else if (value < _presets.length) {
                                      _setOverride(realIndex, _presets[value]);
                                    } else {
                                      _editCustomSymbol(realIndex);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    // "Use Global Currency" option
                                    PopupMenuItem<int>(
                                      value: -1,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.public,
                                            size: 18,
                                            color: entry.override == null
                                                ? theme.colorScheme.primary
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(l10n.useGlobalCurrency),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    // Each preset currency
                                    ...List.generate(_presets.length, (i) {
                                      final preset = _presets[i];
                                      final isSelected =
                                          entry.override?.symbol ==
                                              preset.symbol &&
                                          entry.override?.suffix ==
                                              preset.suffix;
                                      return PopupMenuItem<int>(
                                        value: i,
                                        child: Row(
                                          children: [
                                            Icon(
                                              isSelected
                                                  ? Icons.check_circle
                                                  : Icons.payments_outlined,
                                              size: 18,
                                              color: isSelected
                                                  ? theme.colorScheme.primary
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(preset.symbol),
                                          ],
                                        ),
                                      );
                                    }),
                                    PopupMenuItem<int>(
                                      value: _presets.length,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.edit, size: 18),
                                          const SizedBox(width: 8),
                                          Text(l10n.moneyCustomSymbol),
                                        ],
                                      ),
                                    ),
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

/// Internal model pairing a note with its currency override.
class _NoteCurrencyEntry {
  final String noteId;
  final String noteTitle;
  final ({String symbol, bool suffix})? override;

  const _NoteCurrencyEntry({
    required this.noteId,
    required this.noteTitle,
    this.override,
  });

  _NoteCurrencyEntry copyWith({({String symbol, bool suffix})? override}) {
    return _NoteCurrencyEntry(
      noteId: noteId,
      noteTitle: noteTitle,
      override: override,
    );
  }
}
