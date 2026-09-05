import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../bloc/counter/counter_bloc.dart';
import '../l10n/app_localizations.dart';
import '../models/counter.dart';
import '../models/custom_markdown_shortcut.dart';
import '../widgets/markdown_bar.dart';
import '../widgets/overlay_snackbar.dart';
import '../widgets/simple_markdown_preview.dart';
import '../constants/settings_keys.dart';
import '../services/settings_service.dart';
import '../utils/icon_utils.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_list_utils.dart';
import '../utils/money_display_config.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/unified_app_bars.dart';
import '../services/app_navigator.dart';

class ShortcutEditorPage extends StatefulWidget {
  final CustomMarkdownShortcut? shortcut;
  final Function(CustomMarkdownShortcut) onSave;

  const ShortcutEditorPage({super.key, this.shortcut, required this.onSave});

  @override
  State<ShortcutEditorPage> createState() => _ShortcutEditorPageState();
}

class _ShortcutEditorPageState extends State<ShortcutEditorPage> {
  late TextEditingController _labelController;
  late TextEditingController _beforeController;
  late TextEditingController _afterController;
  late FocusNode _labelFocusNode;
  late FocusNode _beforeFocusNode;
  late FocusNode _afterFocusNode;
  late FocusNode _beforeRepeatFocusNode;
  late FocusNode _afterRepeatFocusNode;
  late IconData _selectedIcon;
  late String _insertType;
  late String _selectedDateFormat;
  static const int _maxChars = 250;
  List<CustomMarkdownShortcut> _shortcuts = [];
  String _previousBeforeText = '';
  String _previousAfterText = '';
  bool _isProcessingTextChange = false;
  String? _labelError;

  // Preview expand state
  bool _isPreviewExpanded = false;

  // Money ledger + palette config for the live preview. Resolved async
  // on init; until it lands the preview renders `$` lines as plain text,
  // so a shortcut that inserts money markdown would otherwise never look
  // like the real thing.
  MoneyDisplayConfig _moneyConfig = MoneyDisplayConfig.disabled;
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  // Advanced mode toggle
  late bool _isAdvancedMode;

  // Counter state — up to two bindings expanded via {c1} / {c2} tokens.
  List<CounterBinding> _counterBindings = [];
  List<Counter> _availableCounters = [];
  static const int _maxCounterBindings = 2;

  // Date offset state
  late int _dateOffsetDays;
  late int _dateOffsetMonths;
  late int _dateOffsetYears;

  // Repeat config state
  late int _repeatCount;
  late bool _incrementDateOnRepeat;
  late int _dateIncrementDays;
  late int _dateIncrementMonths;
  late int _dateIncrementYears;
  late String _repeatSeparator;
  late TextEditingController _beforeRepeatController;
  late TextEditingController _afterRepeatController;

  static const List<String> _dateFormats = [
    'MMMM d, yyyy',
    'MMM d, yyyy',
    'd MMMM yyyy',
    'd MMM yyyy',
    'yyyy-MM-dd',
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'dd.MM.yyyy',
    'EEEE d MMMM yyyy',
    'EEEE, MMMM d, yyyy',
    'EEE, MMM d, yyyy',
    'd/M/yy',
  ];

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
      text: widget.shortcut?.label ?? '',
    );
    _beforeController = TextEditingController(
      text: widget.shortcut?.beforeText ?? '',
    );
    _afterController = TextEditingController(
      text: widget.shortcut?.afterText ?? '',
    );
    _previousBeforeText = _beforeController.text;
    _previousAfterText = _afterController.text;

    _beforeController.addListener(
      () => _handleTextChange(_beforeController, true),
    );
    _beforeController.addListener(() => setState(() {}));
    _afterController.addListener(
      () => _handleTextChange(_afterController, false),
    );
    _afterController.addListener(() => setState(() {}));

    _labelFocusNode = FocusNode();
    _beforeFocusNode = FocusNode();
    _afterFocusNode = FocusNode();
    _beforeRepeatFocusNode = FocusNode();
    _afterRepeatFocusNode = FocusNode();

    // Use simple focus listeners only to rebuild toolbar visibility —
    // no state variables tracking active controller to avoid cursor loop.
    _beforeFocusNode.addListener(_onFocusChange);
    _afterFocusNode.addListener(_onFocusChange);

    _selectedIcon = widget.shortcut != null
        ? IconUtils.getIconFromData(
            widget.shortcut!.iconCodePoint,
            widget.shortcut!.iconFontFamily,
          )
        : Icons.tag;
    _insertType = widget.shortcut?.insertType ?? 'wrap';
    _selectedDateFormat =
        widget.shortcut?.dateFormat ?? SettingsKeys.defaultDateFormat;

    // Initialize date offset
    final dateOffset = widget.shortcut?.dateOffset;
    _dateOffsetDays = dateOffset?.days ?? 0;
    _dateOffsetMonths = dateOffset?.months ?? 0;
    _dateOffsetYears = dateOffset?.years ?? 0;

    // Initialize repeat config
    final repeatConfig = widget.shortcut?.repeatConfig;
    _repeatCount = repeatConfig?.count ?? 1;
    _incrementDateOnRepeat = repeatConfig?.incrementDate ?? false;
    _dateIncrementDays = repeatConfig?.dateIncrementDays ?? 1;
    _dateIncrementMonths = repeatConfig?.dateIncrementMonths ?? 0;
    _dateIncrementYears = repeatConfig?.dateIncrementYears ?? 0;
    _repeatSeparator = repeatConfig?.separator ?? '\n';
    _beforeRepeatController = TextEditingController(
      text: repeatConfig?.beforeRepeatText ?? '',
    );
    _afterRepeatController = TextEditingController(
      text: repeatConfig?.afterRepeatText ?? '',
    );

    // Counter bindings must be initialised before _hasAdvancedFeatures() so
    // the check for length > 1, non-increment ops and token presence is
    // accurate when opening an existing shortcut.
    _counterBindings = List<CounterBinding>.from(
      widget.shortcut?.effectiveCounters ?? const [],
    );

    // Auto-enable advanced mode if any advanced features are configured
    _isAdvancedMode = _hasAdvancedFeatures();

    _loadShortcuts();
    _loadCounters();
    _loadPreviewConfig();
  }

  /// Resolves the money ledger + colour config the preview needs so a
  /// shortcut inserting `$` markdown renders the way it will in a real
  /// note. Without this the preview builder falls back to
  /// `moneyEnabled: false` and every money line shows as plain text.
  Future<void> _loadPreviewConfig() async {
    final settings = await SettingsService.getInstance();
    final money = await settings.getMoneyConfig();
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _moneyConfig = MoneyDisplayConfig(
        enabled: money.enabled,
        startCents: money.startCents,
        currencySymbol: money.symbol,
        currencySuffix: money.suffix,
        errorMessages: l10n == null ? null : MoneyErrorMessages.of(l10n),
      );
      _colorPalette = palette;
    });
  }

  void _onFocusChange() {
    setState(() {});
  }

  bool _hasAdvancedFeatures() {
    return _repeatCount > 1 ||
        _dateOffsetDays != 0 ||
        _dateOffsetMonths != 0 ||
        _dateOffsetYears != 0 ||
        _beforeRepeatController.text.isNotEmpty ||
        _afterRepeatController.text.isNotEmpty ||
        _counterBindings.length > 1 ||
        _counterBindings.any((b) => b.op != CounterOp.increment) ||
        _hasCounterToken();
  }

  bool _hasCounterToken() {
    final pattern = RegExp(r'\{c\d+\}');
    return pattern.hasMatch(_beforeController.text) ||
        pattern.hasMatch(_afterController.text) ||
        pattern.hasMatch(_beforeRepeatController.text) ||
        pattern.hasMatch(_afterRepeatController.text);
  }

  void _resetAdvancedFeatures() {
    setState(() {
      _repeatCount = 1;
      _incrementDateOnRepeat = false;
      _dateIncrementDays = 1;
      _dateIncrementMonths = 0;
      _dateIncrementYears = 0;
      _repeatSeparator = '\n';
      _beforeRepeatController.clear();
      _afterRepeatController.clear();
      _dateOffsetDays = 0;
      _dateOffsetMonths = 0;
      _dateOffsetYears = 0;
      // Collapse to a single increment binding (or none) so the simple
      // counter dropdown can still drive insertType='counter' shortcuts.
      if (_counterBindings.isNotEmpty) {
        _counterBindings = [
          _counterBindings.first.copyWith(op: CounterOp.increment),
        ];
      }
    });
  }

  @override
  void dispose() {
    _labelController.dispose();
    _beforeController.dispose();
    _afterController.dispose();
    _beforeRepeatController.dispose();
    _afterRepeatController.dispose();
    _labelFocusNode.dispose();
    _beforeFocusNode.dispose();
    _afterFocusNode.dispose();
    _beforeRepeatFocusNode.dispose();
    _afterRepeatFocusNode.dispose();
    super.dispose();
  }

  void _showIconPicker() async {
    final selectedIcon = await AppDialogs.iconPicker(
      context,
      currentIcon: _selectedIcon,
    );

    if (selectedIcon != null && mounted) {
      setState(() {
        _selectedIcon = selectedIcon;
      });
    }
  }

  void _loadShortcuts() {
    final state = context.read<MarkdownBarBloc>().state;
    if (state is MarkdownBarLoaded) {
      setState(() {
        _shortcuts = List.from(state.currentShortcuts);
      });
    }
  }

  void _loadCounters() {
    final state = context.read<CounterBloc>().state;
    if (state is CounterLoaded) {
      setState(() {
        _availableCounters = List.from(state.counters);
      });
    }
  }

  Future<void> _showCreateCounterDialog() async {
    final result = await AppDialogs.counterForm(context);
    if (result == null || !mounted) return;

    final bloc = context.read<CounterBloc>();
    bloc.add(
      AddCounter(
        name: result.name,
        startValue: result.startValue,
        step: result.step,
        scope: result.scope,
      ),
    );

    // Wait for the BLoC to actually emit the updated state.
    final updated = await bloc.stream
        .where((s) => s is CounterLoaded)
        .first
        .timeout(const Duration(seconds: 2), onTimeout: () => bloc.state);
    if (updated is CounterLoaded && mounted) {
      setState(() {
        _availableCounters = List.from(updated.counters);
        if (_availableCounters.isNotEmpty) {
          final newCounterId = _availableCounters.last.id;
          if (_counterBindings.isEmpty) {
            _counterBindings = [CounterBinding(counterId: newCounterId)];
          } else if (_counterBindings.length < _maxCounterBindings) {
            _counterBindings = [
              ..._counterBindings,
              CounterBinding(counterId: newCounterId),
            ];
          } else {
            _counterBindings = [
              ..._counterBindings.sublist(0, _counterBindings.length - 1),
              CounterBinding(counterId: newCounterId),
            ];
          }
        }
      });
    }
  }

  void _handleTextChange(TextEditingController controller, bool isBefore) {
    if (_isProcessingTextChange) return;

    final text = controller.text;
    final selection = controller.selection;
    final previousText = isBefore ? _previousBeforeText : _previousAfterText;

    final textLengthIncreased = text.length > previousText.length;
    if (isBefore) {
      _previousBeforeText = text;
    } else {
      _previousAfterText = text;
    }

    if (!textLengthIncreased) return;

    if (selection.baseOffset > 0 &&
        selection.baseOffset <= text.length &&
        text[selection.baseOffset - 1] == '\n') {
      _isProcessingTextChange = true;
      int prevLineStart;
      if (selection.baseOffset < 2) {
        prevLineStart = 0;
      } else {
        prevLineStart = text.lastIndexOf('\n', selection.baseOffset - 2);
        if (prevLineStart == -1) {
          prevLineStart = 0;
        } else {
          prevLineStart++;
        }
      }

      String prevLine = text.substring(prevLineStart, selection.baseOffset - 1);

      if (MarkdownListUtils.isEmptyListItem(prevLine)) {
        final newText =
            text.substring(0, prevLineStart) +
            text.substring(selection.baseOffset);
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: prevLineStart),
        );
        if (isBefore) {
          _previousBeforeText = newText;
        } else {
          _previousAfterText = newText;
        }
        _isProcessingTextChange = false;
        return;
      }

      final String? listPrefix = MarkdownListUtils.getListPrefix(prevLine);
      if (listPrefix != null) {
        final beforeCursor = text.substring(0, selection.baseOffset);
        final afterCursor = text.substring(selection.baseOffset);

        if (!afterCursor.startsWith(listPrefix)) {
          final newText = beforeCursor + listPrefix + afterCursor;
          final newOffset = selection.baseOffset + listPrefix.length;

          controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newOffset),
          );
          if (isBefore) {
            _previousBeforeText = newText;
          } else {
            _previousAfterText = newText;
          }
        }
      }
      _isProcessingTextChange = false;
    }
  }

  /// Resolves the active controller/focusNode at call time using focus state —
  /// avoids storing them in state variables which caused cursor-selection loops.
  (TextEditingController, FocusNode)? _resolveActiveField() {
    if (_beforeFocusNode.hasFocus) return (_beforeController, _beforeFocusNode);
    if (_afterFocusNode.hasFocus) return (_afterController, _afterFocusNode);
    return null;
  }

  void _handleShortcut(CustomMarkdownShortcut shortcut) {
    final field = _resolveActiveField();
    if (field == null) return;

    final (controller, focusNode) = field;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start;
    final end = selection.end;

    if (start < 0 || end < 0) return;

    String newText = text;
    int newCursor = end;

    if (shortcut.insertType == 'date') {
      final now = DateTime.now();
      final formatted = DateFormat(
        shortcut.dateFormat ?? 'yyyy-MM-dd',
      ).format(now);
      final middle = start != end ? text.substring(start, end) : formatted;
      final wrapped = '${shortcut.beforeText}$middle${shortcut.afterText}';
      newText = text.replaceRange(start, end, wrapped);
      newCursor = start + wrapped.length;
    } else if (shortcut.insertType == 'header') {
      final lineStart = text.lastIndexOf('\n', start - 1) + 1;
      int lineEnd = text.indexOf('\n', lineStart);
      if (lineEnd == -1) lineEnd = text.length;
      final lineText = text.substring(lineStart, lineEnd);

      final headerMatch = RegExp(r'^(#{1,6})\s').firstMatch(lineText);
      String newLineText;

      if (headerMatch != null) {
        final currentHashes = headerMatch.group(1)!;
        final textWithoutHeader = lineText.substring(headerMatch.end);

        if (currentHashes.length >= 6) {
          newLineText = textWithoutHeader;
        } else {
          newLineText = '$currentHashes# $textWithoutHeader';
        }
      } else {
        newLineText = '# $lineText';
      }

      newText = text.replaceRange(lineStart, lineEnd, newLineText);
      newCursor = lineStart + newLineText.length;
    } else {
      final before = shortcut.beforeText;
      final after = shortcut.afterText;

      if (start != end) {
        final replaced = '$before${text.substring(start, end)}$after';
        newText = text.replaceRange(start, end, replaced);
        newCursor = start + replaced.length;
      } else {
        final inserted = '$before$after';
        newText = text.replaceRange(start, end, inserted);
        newCursor = start + before.length;
      }
    }

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    focusNode.requestFocus();
  }

  void _save() {
    if (_labelController.text.isEmpty) {
      setState(() {
        _labelError = AppLocalizations.of(context)!.labelCannotBeEmpty;
      });
      OverlaySnackbar.show(
        context,
        AppLocalizations.of(context)!.formHasErrors,
      );
      return;
    }

    // Build date offset if any values are set
    DateOffset? dateOffset;
    if (_insertType == 'date' &&
        (_dateOffsetDays != 0 ||
            _dateOffsetMonths != 0 ||
            _dateOffsetYears != 0)) {
      dateOffset = DateOffset(
        days: _dateOffsetDays,
        months: _dateOffsetMonths,
        years: _dateOffsetYears,
      );
    }

    // Build repeat config if repeat count > 1 or wrapper text is set
    RepeatConfig? repeatConfig;
    if (_repeatCount > 1 ||
        _beforeRepeatController.text.isNotEmpty ||
        _afterRepeatController.text.isNotEmpty) {
      repeatConfig = RepeatConfig(
        count: _repeatCount,
        incrementDate: _incrementDateOnRepeat,
        dateIncrementDays: _dateIncrementDays,
        dateIncrementMonths: _dateIncrementMonths,
        dateIncrementYears: _dateIncrementYears,
        separator: _repeatSeparator,
        beforeRepeatText: _beforeRepeatController.text,
        afterRepeatText: _afterRepeatController.text,
      );
    }

    final shortcut = CustomMarkdownShortcut(
      id: widget.shortcut?.id ?? const Uuid().v4(),
      label: _labelController.text,
      iconCodePoint: _selectedIcon.codePoint,
      iconFontFamily: _selectedIcon.fontFamily ?? 'MaterialIcons',
      beforeText: _beforeController.text,
      afterText: _afterController.text,
      insertType: _insertType,
      dateFormat: _insertType == 'date' ? _selectedDateFormat : null,
      dateOffset: dateOffset,
      repeatConfig: repeatConfig,
      isVisible: widget.shortcut?.isVisible ?? true,
      counterId: _insertType == 'counter' && _counterBindings.isNotEmpty
          ? _counterBindings.first.counterId
          : null,
      counters: List.unmodifiable(_counterBindings),
    );

    widget.onSave(shortcut);
    AppNavigator.pop(context);
  }

  Widget _buildAdvancedModeToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isAdvancedMode
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isAdvancedMode
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune,
            size: 20,
            color: _isAdvancedMode
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.advancedOptions,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: _isAdvancedMode
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                Text(
                  AppLocalizations.of(context)!.advancedOptionsDescription,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isAdvancedMode,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              setState(() {
                _isAdvancedMode = value;
                if (!value) {
                  _resetAdvancedFeatures();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildDateOffsetRow() {
    return Row(
      children: [
        Expanded(
          child: _buildOffsetField(
            label: AppLocalizations.of(context)!.days,
            value: _dateOffsetDays,
            onChanged: (v) => setState(() => _dateOffsetDays = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildOffsetField(
            label: AppLocalizations.of(context)!.monthsLabel,
            value: _dateOffsetMonths,
            onChanged: (v) => setState(() => _dateOffsetMonths = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildOffsetField(
            label: AppLocalizations.of(context)!.yearsLabel,
            value: _dateOffsetYears,
            onChanged: (v) => setState(() => _dateOffsetYears = v),
          ),
        ),
      ],
    );
  }

  Widget _buildOffsetField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(value - 1),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.remove, size: 18),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: value != 0
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(value + 1),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRepeatCountRow() {
    return Row(
      children: [
        Text(
          AppLocalizations.of(context)!.repeatCount,
          style: const TextStyle(fontSize: 14),
        ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _repeatCount > 1 ? () => setState(() => _repeatCount--) : null,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.remove,
              size: 20,
              color: _repeatCount > 1 ? null : Theme.of(context).disabledColor,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$_repeatCount×',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: _repeatCount > 1
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _repeatCount < 100
              ? () => setState(() => _repeatCount++)
              : null,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.add,
              size: 20,
              color: _repeatCount < 100
                  ? null
                  : Theme.of(context).disabledColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeparatorSelector() {
    final separators = [
      ('\n', AppLocalizations.of(context)!.newLine),
      ('\n\n', AppLocalizations.of(context)!.blankLine),
      ('', AppLocalizations.of(context)!.noSeparator),
      (' ', AppLocalizations.of(context)!.space),
      ('\u00A0', AppLocalizations.of(context)!.nbspSpace),
      (', ', AppLocalizations.of(context)!.comma),
      (' | ', AppLocalizations.of(context)!.pipe),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.separator,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: separators.map((sep) {
            final isSelected = _repeatSeparator == sep.$1;
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _repeatSeparator = sep.$1);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  sep.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : null,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRepeatWrapperTextFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.repeatWrapperText,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          AppLocalizations.of(context)!.repeatWrapperTextDesc,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _beforeRepeatController,
          focusNode: _beforeRepeatFocusNode,
          onTapOutside: (_) => _beforeRepeatFocusNode.unfocus(),
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.beforeAllRepeats,
            hintText: AppLocalizations.of(context)!.beforeAllRepeatsHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _afterRepeatController,
          focusNode: _afterRepeatFocusNode,
          onTapOutside: (_) => _afterRepeatFocusNode.unfocus(),
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.afterAllRepeats,
            hintText: AppLocalizations.of(context)!.afterAllRepeatsHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildDateIncrementSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _incrementDateOnRepeat
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.incrementDateOnRepeat,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Switch(
                value: _incrementDateOnRepeat,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _incrementDateOnRepeat = value);
                },
              ),
            ],
          ),
          if (_incrementDateOnRepeat) ...[
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.incrementByEachRepeat,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildIncrementField(
                    label: AppLocalizations.of(context)!.days,
                    value: _dateIncrementDays,
                    onChanged: (v) => setState(() => _dateIncrementDays = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIncrementField(
                    label: AppLocalizations.of(context)!.monthsLabel,
                    value: _dateIncrementMonths,
                    onChanged: (v) => setState(() => _dateIncrementMonths = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIncrementField(
                    label: AppLocalizations.of(context)!.yearsLabel,
                    value: _dateIncrementYears,
                    onChanged: (v) => setState(() => _dateIncrementYears = v),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIncrementField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: value > 0 ? () => onChanged(value - 1) : null,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.remove,
                  size: 16,
                  color: value > 0 ? null : Theme.of(context).disabledColor,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: value > 0
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(value + 1),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.add, size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCounterBindingsList() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _counterBindings.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == _counterBindings.length - 1 ? 0 : 12,
            ),
            child: _buildCounterBindingRow(i),
          ),
        if (_counterBindings.length < _maxCounterBindings) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addCounterBinding,
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              _counterBindings.isEmpty
                  ? l10n.addCounterBinding
                  : l10n.addSecondCounterBinding,
            ),
          ),
        ],
        if (_counterBindings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.counterTokensHint,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _counterBindings.length; i++)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('{c${i + 1}}'),
                  onPressed: () => _insertTokenAtCursor('{c${i + 1}}'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCounterBindingRow(int index) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final binding = _counterBindings[index];
    final hasCounter = _availableCounters.any((c) => c.id == binding.counterId);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '{c${index + 1}}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.removeCounterBinding,
                onPressed: () => _removeCounterBinding(index),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_availableCounters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l10n.noCountersYet,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: hasCounter ? binding.counterId : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
              hint: Text(l10n.selectCounter),
              items: _availableCounters.map((c) {
                final scopeLabel = c.scope == CounterScope.global
                    ? l10n.global
                    : l10n.perNote;
                return DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.name} ($scopeLabel)'),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _counterBindings = [
                    for (int i = 0; i < _counterBindings.length; i++)
                      if (i == index)
                        _counterBindings[i].copyWith(counterId: value)
                      else
                        _counterBindings[i],
                  ];
                });
              },
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Each segment needs roughly 80 px; below that shrink the
                    // label font so everything stays on one line.
                    final perSegment = constraints.maxWidth / 3;
                    final fontSize = (perSegment / 5).clamp(10.0, 13.0);
                    final labelStyle = TextStyle(fontSize: fontSize);
                    return SegmentedButton<CounterOp>(
                      segments: [
                        ButtonSegment(
                          value: CounterOp.increment,
                          label: Text(
                            l10n.counterOpIncrement,
                            style: labelStyle,
                          ),
                          icon: const Icon(Icons.add, size: 16),
                        ),
                        ButtonSegment(
                          value: CounterOp.keep,
                          label: Text(l10n.counterOpKeep, style: labelStyle),
                          icon: const Icon(Icons.drag_handle, size: 16),
                        ),
                        ButtonSegment(
                          value: CounterOp.decrement,
                          label: Text(
                            l10n.counterOpDecrement,
                            style: labelStyle,
                          ),
                          icon: const Icon(Icons.remove, size: 16),
                        ),
                      ],
                      selected: {binding.op},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        HapticFeedback.selectionClick();
                        setState(() {
                          _counterBindings = [
                            for (int i = 0; i < _counterBindings.length; i++)
                              if (i == index)
                                _counterBindings[i].copyWith(
                                  op: selection.first,
                                )
                              else
                                _counterBindings[i],
                          ];
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addCounterBinding() {
    if (_counterBindings.length >= _maxCounterBindings) return;
    setState(() {
      final defaultCounterId = _availableCounters.isNotEmpty
          ? _availableCounters.first.id
          : '';
      _counterBindings = [
        ..._counterBindings,
        CounterBinding(counterId: defaultCounterId),
      ];
    });
  }

  void _removeCounterBinding(int index) {
    setState(() {
      final list = List<CounterBinding>.from(_counterBindings);
      list.removeAt(index);
      _counterBindings = list;
    });
  }

  /// Inserts [token] (e.g. `{c1}`) into whichever before/after field is
  /// focused. Falls back to appending to `beforeText` when nothing is
  /// focused so the action always has a visible effect.
  void _insertTokenAtCursor(String token) {
    final field = _resolveActiveField();
    // When nothing is focused, fall back to the before field and focus it
    // so the user can see where the token landed.
    final controller = field?.$1 ?? _beforeController;
    final focusNode = field?.$2 ?? _beforeFocusNode;
    final selection = controller.selection;
    final text = controller.text;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, text.length)
        : text.length;
    final newText = text.replaceRange(start, end, token);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    focusNode.requestFocus();
  }

  DateTime _getPreviewDate() {
    var date = DateTime.now();
    date = DateTime(
      date.year + _dateOffsetYears,
      date.month + _dateOffsetMonths,
      date.day + _dateOffsetDays,
    );
    return date;
  }

  String _generatePreviewText() {
    String result;

    final hasCounterToken = _hasCounterToken();
    String renderMiddle(int iteration) {
      if (_insertType == 'date') {
        var date = _getPreviewDate();
        if (_incrementDateOnRepeat && iteration > 0) {
          date = DateTime(
            date.year + (_dateIncrementYears * iteration),
            date.month + (_dateIncrementMonths * iteration),
            date.day + (_dateIncrementDays * iteration),
          );
        }
        return DateFormat(_selectedDateFormat).format(date);
      }
      if (_insertType == 'counter' &&
          !hasCounterToken &&
          _counterBindings.isNotEmpty) {
        return _previewCounterValue(0, iteration);
      }
      return 'text';
    }

    final results = <String>[];
    for (int i = 0; i < _repeatCount; i++) {
      final middle = renderMiddle(i);
      final before = _expandPreviewTokens(_beforeController.text, i);
      final after = _expandPreviewTokens(_afterController.text, i);
      results.add('$before$middle$after');
    }
    result = results.join(_repeatSeparator);

    // Apply wrapper text around all repeated items
    if (_beforeRepeatController.text.isNotEmpty ||
        _afterRepeatController.text.isNotEmpty) {
      final beforeWrap = _expandPreviewTokens(
        _beforeRepeatController.text,
        _repeatCount,
      );
      final afterWrap = _expandPreviewTokens(
        _afterRepeatController.text,
        _repeatCount + 1,
      );
      result = '$beforeWrap$result$afterWrap';
    }

    return result;
  }

  /// Substitutes `{cN}` tokens with deterministic preview values so the
  /// user can see exactly which token resolves to which counter.
  String _expandPreviewTokens(String input, int iteration) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(RegExp(r'\{c(\d+)\}'), (match) {
      final index = int.tryParse(match.group(1) ?? '') ?? 0;
      final bindingIndex = index - 1;
      if (bindingIndex < 0 || bindingIndex >= _counterBindings.length) {
        return match.group(0)!;
      }
      return _previewCounterValue(bindingIndex, iteration);
    });
  }

  String _previewCounterValue(int bindingIndex, int iteration) {
    if (bindingIndex < 0 || bindingIndex >= _counterBindings.length) return '?';
    final binding = _counterBindings[bindingIndex];
    final counter = _availableCounters
        .where((c) => c.id == binding.counterId)
        .firstOrNull;
    final base = counter?.startValue ?? 1;
    final step = counter?.step ?? 1;
    if (binding.op == CounterOp.keep) return base.toString();
    final delta = (iteration + 1) * step;
    final value = binding.op == CounterOp.increment
        ? base + delta - step
        : base - delta + step;
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool showToolbar =
        _beforeFocusNode.hasFocus || _afterFocusNode.hasFocus;

    return Scaffold(
      appBar: SettingsAppBar(
        title: widget.shortcut == null ? l10n.newShortcut : l10n.editShortcut,
        showMenuButton: false,
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(
              l10n.save,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: showToolbar
          ? null
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(l10n.save),
            ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.icon),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _showIconPicker,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(_selectedIcon, size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                l10n.tapToChangeIcon,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _labelController,
                      focusNode: _labelFocusNode,
                      onTapOutside: (_) => _labelFocusNode.unfocus(),
                      onChanged: (_) {
                        if (_labelError != null) {
                          setState(() => _labelError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: l10n.label,
                        hintText: l10n.labelHint,
                        border: const OutlineInputBorder(),
                        errorText: _labelError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.insertType),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _insertType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'wrap',
                          child: Text(l10n.wrapSelectedText),
                        ),
                        DropdownMenuItem(
                          value: 'date',
                          child: Text(l10n.insertCurrentDate),
                        ),
                        DropdownMenuItem(
                          value: 'counter',
                          child: Text(l10n.insertCounter),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _insertType = value ?? 'wrap';
                          if (_insertType == 'date') {
                            _beforeController.text = '';
                            _afterController.text = '';
                          }
                        });
                      },
                    ),
                    if (_insertType == 'counter') ...[
                      const SizedBox(height: 16),
                      Text(l10n.selectCounter),
                      const SizedBox(height: 8),
                      if (_availableCounters.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l10n.noCountersYetHint,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue:
                              _counterBindings.isNotEmpty &&
                                  _availableCounters.any(
                                    (c) =>
                                        c.id ==
                                        _counterBindings.first.counterId,
                                  )
                              ? _counterBindings.first.counterId
                              : null,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          hint: Text(l10n.selectCounter),
                          items: _availableCounters.map((c) {
                            final scopeLabel = c.scope == CounterScope.global
                                ? l10n.global
                                : l10n.perNote;
                            return DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.name} ($scopeLabel)'),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              if (value == null) return;
                              if (_counterBindings.isEmpty) {
                                _counterBindings = [
                                  CounterBinding(counterId: value),
                                ];
                              } else {
                                _counterBindings = [
                                  _counterBindings.first.copyWith(
                                    counterId: value,
                                  ),
                                  ..._counterBindings.skip(1),
                                ];
                              }
                            });
                          },
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _showCreateCounterDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(l10n.addCounter),
                      ),
                    ],
                    if (_insertType == 'date') ...[
                      const SizedBox(height: 16),
                      Text(l10n.dateFormatSettings),
                      const SizedBox(height: 8),
                      Container(
                        height: 180,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Material(
                            color: Colors.transparent,
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _dateFormats.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              itemBuilder: (context, index) {
                                final format = _dateFormats[index];
                                final isSelected =
                                    format == _selectedDateFormat;
                                final formattedDate = DateFormat(
                                  format,
                                ).format(DateTime.now());
                                return ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  selected: isSelected,
                                  selectedTileColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.3),
                                  leading: Icon(
                                    isSelected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outline,
                                    size: 20,
                                  ),
                                  title: Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                    format,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(
                                      () => _selectedDateFormat = format,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                    // Advanced mode toggle
                    const SizedBox(height: 16),
                    _buildAdvancedModeToggle(),
                    // Advanced features (date offset and repeat)
                    if (_isAdvancedMode) ...[
                      // Date offset section (only for date insert type)
                      if (_insertType == 'date') ...[
                        const SizedBox(height: 16),
                        _buildSectionHeader(
                          l10n.dateOffset,
                          Icons.calendar_today,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.dateOffsetDescription,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDateOffsetRow(),
                      ],
                      // Repeat section (for all insert types)
                      const SizedBox(height: 16),
                      _buildSectionHeader(l10n.repeatSettings, Icons.repeat),
                      const SizedBox(height: 8),
                      Text(
                        l10n.repeatDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildRepeatCountRow(),
                      if (_repeatCount > 1) ...[
                        const SizedBox(height: 12),
                        _buildSeparatorSelector(),
                        const SizedBox(height: 12),
                        _buildRepeatWrapperTextFields(),
                        if (_insertType == 'date') ...[
                          const SizedBox(height: 12),
                          _buildDateIncrementSection(),
                        ],
                      ],
                      // Counter bindings section (always available in
                      // advanced mode, regardless of insertType — lets users
                      // combine date + counter, two counters, etc.).
                      const SizedBox(height: 16),
                      _buildSectionHeader(l10n.counterBindingsTitle, Icons.tag),
                      const SizedBox(height: 8),
                      Text(
                        l10n.counterBindingsDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildCounterBindingsList(),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.markdownSpaceWarning,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _beforeController,
                      focusNode: _beforeFocusNode,
                      onTapOutside: (_) => _beforeFocusNode.unfocus(),
                      maxLines: null,
                      minLines: 3,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLength: _maxChars,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      decoration: InputDecoration(
                        labelText: _insertType == 'date'
                            ? l10n.beforeDate
                            : l10n.markdownStart,
                        hintText: _insertType == 'date'
                            ? l10n.optionalTextBeforeDate
                            : l10n.markdownStartHint,
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.charactersCount(
                          _beforeController.text.length,
                          _maxChars,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _afterController,
                      focusNode: _afterFocusNode,
                      onTapOutside: (_) => _afterFocusNode.unfocus(),
                      maxLines: null,
                      minLines: 3,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLength: _maxChars,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      decoration: InputDecoration(
                        labelText: _insertType == 'date'
                            ? l10n.afterDate
                            : l10n.markdownEnd,
                        hintText: _insertType == 'date'
                            ? l10n.optionalTextAfterDate
                            : l10n.markdownStartHint,
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.charactersCount(
                          _afterController.text.length,
                          _maxChars,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.preview,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => setState(
                            () => _isPreviewExpanded = !_isPreviewExpanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isPreviewExpanded ? l10n.hide : l10n.show,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                AnimatedRotation(
                                  turns: _isPreviewExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      width: double.infinity,
                      height: _isPreviewExpanded ? 480 : 200,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: SimpleMarkdownPreview(
                        data: _generatePreviewText(),
                        fontSize: 14,
                        moneyConfig: _moneyConfig,
                        colorPalette: _colorPalette,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showToolbar && _shortcuts.isNotEmpty)
              // TextFieldTapRegion marks the MarkdownBar as belonging to the
              // text-field tap group. This means: (a) any current/future
              // TextField.onTapOutside callback in this tree will NOT fire
              // when the user taps a markdown shortcut button, and (b) the
              // focused TextField won't be unfocused, so _resolveActiveField()
              // continues to return the correct controller in _handleShortcut.
              TextFieldTapRegion(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  child: MarkdownBar(
                    shortcuts: _shortcuts.where((s) => s.isVisible).toList(),
                    isPreviewMode: false,
                    canUndo: false,
                    canRedo: false,
                    previewFontSize: 16,
                    onUndo: () {},
                    onRedo: () {},
                    onDecreaseFontSize: () {},
                    onIncreaseFontSize: () {},
                    onSettings: () {},
                    onShortcutPressed: _handleShortcut,
                    showSettings: false,
                    showBackground: false,
                    showReorder: false,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
