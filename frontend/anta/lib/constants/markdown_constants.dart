import 'dart:ui' show Color, FontWeight;

import 'package:flutter/material.dart' show IconData, Icons;

import '../utils/markdown_callout_syntax.dart';
import '../utils/markdown_money_syntax.dart';

/// Constants for markdown rendering and preview
class MarkdownConstants {
  MarkdownConstants._();

  // Thresholds
  /// Character delta threshold for content change detection
  static const int contentChangeDeltaThreshold = 500;

  // Timing
  /// Debounce duration for search content in milliseconds
  static const int searchDebounceMs = 200;

  /// Animation duration for scroll and transitions in milliseconds
  static const int animationDurationMs = 200;

  // Layout
  /// Default line height multiplier for text
  static const double lineHeight = 1.55;

  /// Cache extent for virtualized ListView
  static const int cacheExtent = 500;

  /// Default item extent for virtualized ListView
  static const double itemExtent = 32.0;

  // Heading scale factors
  //
  // Set against the 16 px body: h1 24, h2 20.8, h3 18.4, h4 16.8, h5 and
  // h6 at the base size. The old 22 / 18 / 17 / 16 steps were too close to
  // the body for a heading to read as structure at a glance. Both surfaces
  // read these, so preview and live editor cannot size a heading
  // differently.
  static const double h1Scale = 1.5;
  static const double h2Scale = 1.3;
  static const double h3Scale = 1.15;
  static const double h4Scale = 1.05;
  static const double h5Scale = 1.0;
  static const double h6Scale = 1.0;

  /// The weight every heading renders at, on both surfaces: semibold, so
  /// the base-size h5 and h6 still stand apart from body text.
  static const FontWeight headingWeight = FontWeight.w600;

  /// Heading scale in the live editor — the same factors the preview
  /// reads, so the two surfaces size a heading identically. H5 and H6
  /// sit at the base size and distinguish themselves by colour as well
  /// (see the span builder's header branch).
  static double editorHeaderScale(int level) => switch (level) {
    1 => h1Scale,
    2 => h2Scale,
    3 => h3Scale,
    4 => h4Scale,
    _ => 1.0,
  };

  // Line height scales (for height calculations)
  /// Scale for normal text lines (baseline)
  static const double normalLineScale = 1.0;

  /// Scale for empty lines (renders at half height)
  static const double emptyLineScale = 0.5;

  /// Scale for horizontal rule lines
  static const double horizontalRuleScale = 0.5;

  /// Scale for code block text (slightly smaller than normal)
  static const double codeBlockScale = 0.9;

  /// Scale for inline code (`` `code` ``) relative to its surrounding
  /// text. Read by both surfaces — the preview renderer and the live
  /// editor's inline emitter — so a code chip is the same size in each.
  static const double inlineCodeScale = 0.9;

  // Checkbox
  /// Multiplier for checkbox icon size relative to font size
  static const double checkboxIconScale = 1.25;

  /// Live editor task checkbox: box side as a fraction of the line's
  /// font size. The box is custom-painted into a placeholder run
  /// (fork's CodeInlinePaintSpan) and centered on the line box, so this
  /// scale holds across every editor font-size setting. Must stay
  /// comfortably below [lineHeight] or the placeholder grows the line.
  static const double editorCheckboxScale = 1.05;

  /// Live editor callout icon: the blank after its square on a titleless
  /// lead, as a fraction of the icon's side — about a space's width, so
  /// the painted label does not touch the icon where no source blank
  /// stands between them.
  static const double editorCalloutLabelGapScale = 0.3;

  /// Indent multiplier per level for checkboxes and lists
  static const double indentPerLevel = 16.0;

  // Code block
  /// Font size for code blocks
  static const double codeBlockFontSize = 14.0;

  // Border widths
  /// Width of selection border indicator
  static const double selectionBorderWidth = 2.0;

  /// Width of quote border
  static const double quoteBorderWidth = 4.0;

  // Opacity values
  /// Opacity for unchecked checkbox icons
  static const double uncheckedCheckboxOpacity = 0.6;

  /// Opacity for checked/disabled text
  static const double checkedTextOpacity = 0.5;

  /// Opacity for quote text
  static const double quoteTextOpacity = 0.7;

  /// Alpha of the tinted chip the live editor paints behind an accented
  /// run: `#tag` pills and money value chips, which must read as the
  /// same weight of tint.
  static const double editorChipBackgroundAlpha = 0.12;

  // List item widths
  /// Width reserved for numbered list numbers
  static const double numberedListNumberWidth = 24.0;

  // Highlighter (`==mark==`) backgrounds
  /// Theme-matched highlighter amber that keeps the light-theme text
  /// colour readable on top. Shared by preview and live editor so the
  /// two surfaces always match.
  static const Color markBackgroundLight = Color(0xFFFFF176);

  /// Dark-theme counterpart of [markBackgroundLight].
  static const Color markBackgroundDark = Color(0xFF5A4B1C);

  /// ASCII-punctuation test for backslash escaping (CommonMark allows
  /// escaping any ASCII punctuation). Shared by the preview renderer and
  /// the live editor scanner so escape grammar can never diverge.
  static bool isEscapablePunctuation(int codeUnit) =>
      (codeUnit >= 0x21 && codeUnit <= 0x2F) ||
      (codeUnit >= 0x3A && codeUnit <= 0x40) ||
      (codeUnit >= 0x5B && codeUnit <= 0x60) ||
      (codeUnit >= 0x7B && codeUnit <= 0x7E);

  /// The named HTML entities the inline grammar decodes, each to one
  /// BMP code unit. A fixed, short list of what notes actually carry
  /// (pasted web text, typography, units) rather than HTML's 2,000-odd
  /// names: an unknown name stays literal on every surface.
  static const Map<String, int> htmlEntities = <String, int>{
    'amp': 0x26,
    'lt': 0x3C,
    'gt': 0x3E,
    'quot': 0x22,
    'apos': 0x27,
    'nbsp': 0xA0,
    'copy': 0xA9,
    'reg': 0xAE,
    'trade': 0x2122,
    'deg': 0xB0,
    'plusmn': 0xB1,
    'times': 0xD7,
    'divide': 0xF7,
    'hellip': 0x2026,
    'mdash': 0x2014,
    'ndash': 0x2013,
    'euro': 0x20AC,
    'pound': 0xA3,
    'yen': 0xA5,
    'cent': 0xA2,
    'sect': 0xA7,
    'para': 0xB6,
    'middot': 0xB7,
    'laquo': 0xAB,
    'raquo': 0xBB,
    'frac12': 0xBD,
    'frac14': 0xBC,
    'frac34': 0xBE,
    'sup2': 0xB2,
    'sup3': 0xB3,
    'micro': 0xB5,
    'bull': 0x2022,
  };

  /// Accent for money-ledger additions (`$+`), in a light/dark variant.
  /// Shared by the preview renderer and the live editor so the two
  /// surfaces always match; values mirror the tip-callout greens.
  static Color moneyPositive({required bool dark}) =>
      dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);

  /// Accent for money-ledger subtractions (`$-`) and negative totals;
  /// values mirror the caution-callout reds.
  static Color moneyNegative({required bool dark}) =>
      dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);

  /// Accent for money-ledger multiply/divide (`$*` / `$/`); values
  /// mirror the warning-callout ambers.
  static Color moneyNeutral({required bool dark}) =>
      dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);

  /// Accent for money-ledger error rows (over-limit amount, divide by
  /// zero, …) and for computed values pinned at the balance cap. Shared
  /// by the preview renderer, the live editor, and the detail sheet so
  /// every surface warns in the same yellow.
  static Color moneyWarning({required bool dark}) =>
      dark ? const Color(0xFFFFC107) : const Color(0xFFB28704);

  /// Semantic accent for a money row: fixed sign colours on op rows,
  /// value-sign colours on display rows (`$$` red only when negative,
  /// `$?`/`$^`/`$~` by direction, bare `$!` green while the budget
  /// holds — zero included, "didn't spend more than the target" — red
  /// once overspent), [primary] where the row is a neutral statement
  /// (`$=`, and `$! N` declarations, whose value is the target itself).
  /// One source for the preview and the live editor — they used to keep
  /// twin switches — while the detail sheet keeps its deliberately
  /// flatter row-accent policy. An explicit accent token overrides this
  /// at the call site, exactly as before; callers resolve the
  /// no-target sentinel to [moneyWarning] before asking here.
  static Color moneyAccent(
    MoneyLineKind kind,
    int value, {
    required bool dark,
    required Color primary,
  }) => switch (kind) {
    MoneyLineKind.add => moneyPositive(dark: dark),
    MoneyLineKind.subtract => moneyNegative(dark: dark),
    MoneyLineKind.multiply || MoneyLineKind.divide => moneyNeutral(dark: dark),
    MoneyLineKind.set || MoneyLineKind.target => primary,
    MoneyLineKind.total => value < 0 ? moneyNegative(dark: dark) : primary,
    MoneyLineKind.remaining =>
      value < 0 ? moneyNegative(dark: dark) : moneyPositive(dark: dark),
    MoneyLineKind.delta || MoneyLineKind.diff || MoneyLineKind.span =>
      value > 0
          ? moneyPositive(dark: dark)
          : value < 0
          ? moneyNegative(dark: dark)
          : primary,
  };

  /// The accent colour for a callout [type], in a light/dark variant.
  /// Shared by the preview renderer (bar, icon-label header, band tint)
  /// and the live editor (quote bar + `[!TYPE]` token tint) so the two
  /// surfaces always match.
  static Color calloutAccent(MarkdownCalloutType type, {required bool dark}) {
    switch (type) {
      case MarkdownCalloutType.note:
        return dark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);
      case MarkdownCalloutType.tip:
        return dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      case MarkdownCalloutType.important:
        return dark ? const Color(0xFFBA68C8) : const Color(0xFF6A1B9A);
      case MarkdownCalloutType.warning:
        return dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
      case MarkdownCalloutType.caution:
        return dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
      case MarkdownCalloutType.success:
        return dark ? const Color(0xFF4DB6AC) : const Color(0xFF00897B);
      case MarkdownCalloutType.pr:
        return dark ? const Color(0xFFFFD54F) : const Color(0xFFF9A825);
      // The kinds below keep their light variant at 4.5:1 or better on
      // the light page, so a title in the accent reads as body text does.
      case MarkdownCalloutType.example:
        return dark ? const Color(0xFFB39DDB) : const Color(0xFF5E35B1);
      case MarkdownCalloutType.question:
        return dark ? const Color(0xFFFFCC80) : const Color(0xFF9A6700);
      case MarkdownCalloutType.danger:
        return dark ? const Color(0xFFFF8A80) : const Color(0xFFB71C1C);
      case MarkdownCalloutType.bug:
        return dark ? const Color(0xFFF48FB1) : const Color(0xFFAD1457);
      case MarkdownCalloutType.todo:
        return dark ? const Color(0xFF9FA8DA) : const Color(0xFF3949AB);
      case MarkdownCalloutType.quote:
        return dark ? const Color(0xFFBDBDBD) : const Color(0xFF616161);
      case MarkdownCalloutType.abstract:
        return dark ? const Color(0xFF80DEEA) : const Color(0xFF00737D);
      case MarkdownCalloutType.failure:
        return dark ? const Color(0xFFFFAB91) : const Color(0xFFBF360C);
    }
  }

  /// The icon for a callout [type], painted in the type's accent by the
  /// live editor's lead line (the preview keeps the emoji from
  /// `MarkdownCalloutSyntax.iconFor` in its header run). Kept beside
  /// [calloutAccent] so icon and colour are chosen from one table.
  static IconData calloutIcon(MarkdownCalloutType type) {
    switch (type) {
      case MarkdownCalloutType.note:
        return Icons.edit_note_rounded;
      case MarkdownCalloutType.tip:
        return Icons.lightbulb_outline_rounded;
      case MarkdownCalloutType.important:
        return Icons.priority_high_rounded;
      case MarkdownCalloutType.warning:
        return Icons.warning_amber_rounded;
      case MarkdownCalloutType.caution:
        return Icons.dangerous_outlined;
      case MarkdownCalloutType.success:
        return Icons.check_circle_outline_rounded;
      case MarkdownCalloutType.pr:
        return Icons.emoji_events_outlined;
      case MarkdownCalloutType.example:
        return Icons.list_alt_rounded;
      case MarkdownCalloutType.question:
        return Icons.help_outline_rounded;
      case MarkdownCalloutType.danger:
        return Icons.bolt_rounded;
      case MarkdownCalloutType.bug:
        return Icons.bug_report_outlined;
      case MarkdownCalloutType.todo:
        return Icons.checklist_rounded;
      case MarkdownCalloutType.quote:
        return Icons.format_quote_rounded;
      case MarkdownCalloutType.abstract:
        return Icons.summarize_outlined;
      case MarkdownCalloutType.failure:
        return Icons.cancel_outlined;
    }
  }
}
