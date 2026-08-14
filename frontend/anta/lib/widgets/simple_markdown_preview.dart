import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';
import '../utils/line_based_markdown_builder.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';

class SimpleMarkdownPreview extends StatefulWidget {
  final String data;
  final double fontSize;
  final EdgeInsets? padding;
  final LinkTapCallback? onTapLink;

  /// Toggles a task checkbox. Null (the default) leaves the rendered
  /// boxes inert: [LineBasedMarkdownBuilder] only allocates a
  /// [TapGestureRecognizer] per checkbox when this is non-null, so a
  /// read-only surface pays nothing for them.
  final CheckboxTapCallback? onCheckboxTap;

  /// Money ledger display config, mirroring [LineBasedMarkdownBuilder].
  /// The default leaves the ledger off — a caller that does not resolve
  /// `SettingsService.getMoneyConfig()` renders `$` lines as plain text,
  /// which is why this has to be threaded through rather than assumed.
  final MoneyDisplayConfig moneyConfig;

  /// Resolved colour palette, so `{name:text}` runs and money accent
  /// tokens show the user's custom colours and not just the presets.
  final MarkdownColorPalette colorPalette;

  const SimpleMarkdownPreview({
    super.key,
    required this.data,
    this.fontSize = 14.0,
    this.padding,
    this.onTapLink,
    this.onCheckboxTap,
    this.moneyConfig = MoneyDisplayConfig.disabled,
    this.colorPalette = MarkdownColorPalette.presets,
  });

  @override
  State<SimpleMarkdownPreview> createState() => _SimpleMarkdownPreviewState();
}

class _SimpleMarkdownPreviewState extends State<SimpleMarkdownPreview> {
  LineBasedMarkdownBuilder? _builder;
  String? _lastData;
  double? _lastFontSize;
  ThemeData? _lastTheme;
  MoneyDisplayConfig? _lastMoneyConfig;
  MarkdownColorPalette? _lastColorPalette;
  bool _lastInteractiveCheckboxes = false;

  @override
  void dispose() {
    _builder?.dispose();
    super.dispose();
  }

  /// The money config and palette arrive asynchronously, so they must be
  /// part of the rebuild check — otherwise the first (config-less) build
  /// sticks and `$` lines stay plain text forever. The checkbox callback
  /// is compared by null-ness for the same reason: the builder decides
  /// once, at construction, whether checkboxes get recognizers.
  bool _shouldRebuild(ThemeData theme) {
    return _builder == null ||
        _lastData != widget.data ||
        _lastFontSize != widget.fontSize ||
        _lastTheme?.brightness != theme.brightness ||
        _lastMoneyConfig != widget.moneyConfig ||
        _lastColorPalette != widget.colorPalette ||
        _lastInteractiveCheckboxes != (widget.onCheckboxTap != null);
  }

  void _buildCache(BuildContext context) {
    final theme = Theme.of(context);

    if (!_shouldRebuild(theme)) {
      return;
    }

    _builder?.dispose();

    _lastData = widget.data;
    _lastFontSize = widget.fontSize;
    _lastTheme = theme;
    _lastMoneyConfig = widget.moneyConfig;
    _lastColorPalette = widget.colorPalette;
    _lastInteractiveCheckboxes = widget.onCheckboxTap != null;

    final mdStyle = LineMarkdownStyle.fromTheme(theme, widget.fontSize);

    _builder = LineBasedMarkdownBuilder(
      style: mdStyle,
      onLinkTap: widget.onTapLink,
      onCheckboxTap: widget.onCheckboxTap,
      moneyConfig: widget.moneyConfig,
      colorPalette: widget.colorPalette,
      linesPerChunk: 100,
    );

    _builder!.prepare(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    _buildCache(context);

    if (_builder == null || widget.data.isEmpty) {
      return const SizedBox.shrink();
    }

    final baseStyle = TextStyle(
      fontSize: widget.fontSize,
      height: MarkdownConstants.lineHeight,
    );

    final allSpans = <InlineSpan>[];
    for (int i = 0; i < _builder!.chunkCount; i++) {
      final chunkSpans = _builder!.buildChunk(i);
      allSpans.addAll(chunkSpans);
      if (i < _builder!.chunkCount - 1) {
        allSpans.add(const TextSpan(text: '\n'));
      }
    }

    return SingleChildScrollView(
      padding: widget.padding ?? const EdgeInsets.all(8),
      child: Text.rich(TextSpan(style: baseStyle, children: allSpans)),
    );
  }
}
