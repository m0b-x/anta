import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/settings_keys.dart';
import '../utils/editor_render_context.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/money_display_config.dart';

/// Everything the editor page needs to turn a [CodeLine] into a span:
/// the markdown span builder, the theme generation it renders under, and
/// the two resolved settings objects (money display, colour palette) both
/// render surfaces must agree on.
///
/// The page owns one of these and holds no renderer state of its own. It
/// exists so the routing rule — live markdown first, ghost text as the
/// fallback for every line the markdown builder does not handle — lives
/// in one place next to the configuration that decides what "handled"
/// means.
class EditorRenderController {
  /// The configuration in force before settings are read: the shipped
  /// defaults, so a line built during the first frame renders the same
  /// way it will once the resolved config lands (unless the user changed
  /// it, which arrives through [applyMoneyConfig]).
  static const MoneyDisplayConfig defaultMoneyConfig = MoneyDisplayConfig(
    enabled: SettingsKeys.defaultMoneyLedgerEnabled,
    startCents: SettingsKeys.defaultMoneyStartCents,
    currencySymbol: SettingsKeys.defaultMoneyCurrencySymbol,
    currencySuffix: SettingsKeys.defaultMoneyCurrencySuffix,
  );

  final MarkdownEditorSpanBuilder _spanBuilder = MarkdownEditorSpanBuilder();

  /// The renderer's theme generation, resolved once per theme/style
  /// change instead of once per line — see [EditorRenderContextCache].
  final EditorRenderContextCache _renderContexts = EditorRenderContextCache();

  MoneyDisplayConfig _moneyConfig = defaultMoneyConfig;
  MarkdownColorPalette _palette = MarkdownColorPalette.presets;

  /// Seeds the builder with the same [defaultMoneyConfig] this
  /// controller reports, so the two can never start out disagreeing.
  /// The builder's own default is the disabled config, which matches
  /// only while [SettingsKeys.defaultMoneyLedgerEnabled] is false —
  /// seeding here makes [applyMoneyConfig]'s "changed" report true by
  /// construction instead of by coincidence.
  EditorRenderController() {
    _spanBuilder.configureMoney(defaultMoneyConfig);
  }

  /// The live-rendering span builder, exposed for the collaborators that
  /// need it directly — the tap interceptor's zone resolution and the
  /// vocabulary controller's line lookups.
  MarkdownEditorSpanBuilder get spanBuilder => _spanBuilder;

  /// The money configuration currently applied to the builder. The page
  /// hands this same instance to the preview bloc and the detail sheet,
  /// so no surface can see a different half of the config.
  MoneyDisplayConfig get moneyConfig => _moneyConfig;

  /// The colour palette currently applied to the builder.
  MarkdownColorPalette get palette => _palette;

  void bind(CodeLineEditingController controller) {
    _spanBuilder.bind(controller);
  }

  /// Applies [config] and reports whether it differs from what was
  /// applied before — the page repaints the editor only on a change, but
  /// the builder is configured on *every* call so its state can never
  /// drift from the value this controller reports.
  bool applyMoneyConfig(MoneyDisplayConfig config) {
    final changed = config != _moneyConfig;
    _spanBuilder.configureMoney(config);
    _moneyConfig = config;
    return changed;
  }

  /// Applies [palette] and reports whether it differs from what was
  /// applied before. Same contract as [applyMoneyConfig]: configure
  /// always, report change only on a real change.
  bool applyPalette(MarkdownColorPalette palette) {
    final changed = palette != _palette;
    _spanBuilder.configureColors(palette);
    _palette = palette;
    return changed;
  }

  /// Whether [lineIndex] is inside (or delimiting) a ``` fence — the
  /// positional check the tap interception needs before it may read a
  /// line as markdown.
  bool lineInFence(int lineIndex) => _spanBuilder.lineInFence(lineIndex);

  /// Whether [lineIndex] is a line *inside* a ``` fence — the ```
  /// delimiters themselves answer false.
  ///
  /// Narrower than [lineInFence] on purpose: a caller that only wants to
  /// leave verbatim code alone (the editor's typing helpers) must still
  /// treat the delimiter lines as ordinary markdown, or the line that
  /// opens a fence stops behaving like the line the user is typing on.
  bool lineInFenceBody(int lineIndex) =>
      _spanBuilder.lineInFenceBody(lineIndex);

  /// Routes line rendering: live markdown styling when the editor setting
  /// is on (unhandled lines fall through), the ghost-text builder
  /// otherwise.
  TextSpan buildSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
    required bool liveRendering,
  }) {
    final render = _renderContexts.of(Theme.of(context), style);
    if (liveRendering) {
      final span = _spanBuilder.build(
        context: render,
        index: index,
        codeLine: codeLine,
      );
      if (span != null) return span;
    }
    return ghostSpan(
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
      baseColor: render.baseColor,
    );
  }

  /// re_editor [CodeLineSpanBuilder] that renders `{{ … }}` ghost-text
  /// runs as dimmed inner text with the markers visually concealed.
  ///
  /// The marker characters are kept in the line (re_editor maps caret /
  /// selection offsets through the rendered span, so removing them would
  /// desync the model) but are painted transparent and collapsed to a
  /// near-zero width, so only the grey inner text shows. A whitespace-only
  /// placeholder gets an underline so the empty slot stays findable.
  /// Lines without the opening marker short-circuit so the common path
  /// stays allocation-free.
  ///
  /// [baseColor] comes from the caller's [EditorRenderContext], the same
  /// theme generation the markdown builder renders under, so the ghost
  /// tone matches whichever surface drew the line — and the theme is read
  /// once per generation instead of once per ghost line.
  static TextSpan ghostSpan({
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
    required Color baseColor,
  }) {
    final text = codeLine.text;
    if (!GhostText.mightContain(text)) return textSpan;
    final ghosts = GhostText.findGhosts(text);
    if (ghosts.isEmpty) return textSpan;

    final ghostColor = baseColor.withValues(alpha: 0.45);
    final ghostStyle = style.copyWith(color: ghostColor);
    // Markers stay in the model (offset integrity) but are painted
    // transparent and collapsed to ~0 width so they read as invisible.
    final concealStyle = style.copyWith(
      color: const Color(0x00000000),
      fontSize: 0.01,
    );

    final children = <TextSpan>[];
    int pos = 0;
    for (final g in ghosts) {
      if (g.start > pos) {
        children.add(
          TextSpan(text: text.substring(pos, g.start), style: style),
        );
      }
      // Opening `{{` — concealed.
      children.add(
        TextSpan(
          text: text.substring(g.start, g.innerStart),
          style: concealStyle,
        ),
      );
      // Inner text — dimmed; underline when blank so the slot stays visible.
      final inner = text.substring(g.innerStart, g.innerEnd);
      children.add(
        TextSpan(
          text: inner,
          style: inner.trim().isEmpty
              ? ghostStyle.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: ghostColor,
                )
              : ghostStyle,
        ),
      );
      // Closing `}}` — concealed.
      children.add(
        TextSpan(text: text.substring(g.innerEnd, g.end), style: concealStyle),
      );
      pos = g.end;
    }
    if (pos < text.length) {
      children.add(TextSpan(text: text.substring(pos), style: style));
    }
    return TextSpan(style: style, children: children);
  }
}
