import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/guide_metrics.dart';
import '../constants/markdown_constants.dart';
import '../constants/semantics_ids.dart';
import '../controllers/editor_edit_tracker.dart';
import '../controllers/editor_render_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/editor_settings.dart';
import '../models/guide_content.dart';
import '../utils/list_aware_paste.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';
import '../utils/re_editor_search_controller.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'modern_editor_wrapper.dart';

/// A notes card's stage (D17): the note editor itself — the same wrapper,
/// paste controller, render controller and edit tracker, wired as the
/// editor page wires them — over an in-memory seed, so every path the book
/// describes works here as in a note. Nothing is saved; the text is hers
/// until the page goes.
///
/// The coach reads the document, never a tap (D18): after every edit each
/// step not yet done runs its check, and every check that passes marks its
/// step, several in one edit if one edit shows them.
class GuideEditorDemo extends GuideCardDemo {
  GuideEditorDemo({required this.book, required GuideEditorCard card})
    : _card = card,
      super(card.spec) {
    _controller = ListAwarePasteController(
      delegate: CodeLineEditingController(
        spanBuilder:
            ({
              required BuildContext context,
              required int index,
              required CodeLine codeLine,
              required TextSpan textSpan,
              required TextStyle style,
            }) => _render.buildSpan(
              context: context,
              index: index,
              codeLine: codeLine,
              textSpan: textSpan,
              style: style,
              liveRendering: true,
            ),
      ),
      isFenceLine: _render.lineInFence,
    );
    _render
      ..bind(_controller)
      ..bindFocus(_focus);
    _search.initialize(_controller);
    _edits = EditorEditTracker(
      controller: _controller,
      // A sandbox has no paste reflow: nothing to measure it against, and
      // nothing a lesson asks her to paste.
      autoBreakLongLines: () => false,
      pasteContext: () => null,
      onLinesReformatted: (_) {},
      isFenceLine: _render.lineInFence,
      lineInFenceBody: _render.lineInFenceBody,
      blockStateAt: _render.blockStateAt,
    );
  }

  /// The book's slug, for the stage's ids.
  final String book;

  final GuideEditorCard _card;

  final EditorRenderController _render = EditorRenderController();
  late final ListAwarePasteController _controller;
  late final EditorEditTracker _edits;
  final FocusNode _focus = FocusNode();
  final CodeScrollController _scroll = CodeScrollController();

  /// The wrapper requires one; a sandbox has no find bar to drive it.
  final ReEditorSearchController _search = ReEditorSearchController();

  bool _seeded = false;

  /// The text the checks last read, so a caret move — which notifies the
  /// controller too — runs none.
  String? _checked;

  /// The lines the checks last read, as they read them: the next change's
  /// `previousLines`, for a step that is a transition.
  List<String> _lastLines = const [];

  /// The stage's air (`docs/guide-hub-roadmap.md` §9.6 (b)): none above or
  /// below — the card's own stage padding holds it — and the card's inset at
  /// the sides, so the text starts under the coach line at every scale.
  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: GuideMetrics.cardInset,
  );

  /// Edge to edge at every scale (`docs/guide-hub-roadmap.md` §9.6 (b)): the
  /// editor is the stage, and a phone line of it is what she reads and types
  /// on.
  @override
  bool get stageFullBleed => true;

  /// Loads the seed in [l10n]'s language the first time there is one
  /// (`docs/guide-hub-roadmap.md` §9.6 (a)): the page builds the demo before
  /// it has a language. Never again — once she typed, a change of language
  /// must not take her text.
  void seed(AppLocalizations l10n) {
    if (_seeded) return;
    _seeded = true;
    _controller.loadText(_card.seed(l10n));
    // The wrapper is not mounted yet, so the tracker never saw the load:
    // adopt its length, or her first keystroke reads as a paste.
    _edits.syncLength();
    _checked = _controller.text;
  }

  /// Her money config and colours, once the page has read them (D20):
  /// applied to the renderer and, on a change, repainted in place — never
  /// a remount, which tears the editor down mid-mount. The rebuild hands
  /// the wrapper the palette its tap zones resolve colours with.
  void adoptRenderConfig({
    required MoneyDisplayConfig money,
    required MarkdownColorPalette palette,
  }) {
    final moneyChanged = _render.applyMoneyConfig(money);
    final paletteChanged = _render.applyPalette(palette);
    if (!moneyChanged && !paletteChanged) return;
    _controller.forceRepaint();
    notifyListeners();
  }

  void _onTextChanged() {
    _edits.onTextChanged();
    final text = _controller.text;
    if (text == _checked) return;
    _checked = text;
    // The lines as the stage draws them: the render controller's fence role
    // covers code fences, `%%` comments and front matter alike, one lookup
    // per line — its `blockStateAt` walks a segment per call.
    final lines = GuideEditorDocument.blankBlocks(
      text.split('\n'),
      _render.lineInFence,
    );
    final document = GuideEditorDocument(
      lines: lines,
      previousLines: _lastLines,
      hasDone: hasDone,
      palette: _render.palette,
    );
    _lastLines = lines;
    var marked = false;
    for (final step in _card.steps) {
      if (hasDone(step.action) || !step.done(document)) continue;
      marked = true;
      did(step.action);
    }
    // An edit is her next action: it snaps a read-back line (D70) or a
    // standing report (D47 / D49) back to the live instruction. Any other
    // keystroke costs no rebuild.
    if (!marked && (reading || hasReport)) changed();
  }

  static String _tagReport(AppLocalizations l10n) => l10n.notesGuideReportTag;
  static String _wikiReport(AppLocalizations l10n) => l10n.notesGuideReportWiki;
  static String _linkReport(AppLocalizations l10n) => l10n.notesGuideReportLink;
  static String _moneyReport(AppLocalizations l10n) =>
      l10n.notesGuideReportMoney;

  /// Every tap that would leave the note (D19): a card cannot know what she
  /// will type, so all four, each saying what a note would do and never
  /// quoting her text.
  @override
  List<String> reports(AppLocalizations l10n) => [
    _tagReport(l10n),
    _wikiReport(l10n),
    _linkReport(l10n),
    _moneyReport(l10n),
  ];

  @override
  Widget buildStage(BuildContext context) {
    // The fork's line is its style's `TextPainter.preferredLineHeight`
    // (`_CodeFieldRender._calculatePreferredLineHeight`), which the text
    // engine rounds to a whole pixel: 24.8 dp lays out as 25, and six
    // unrounded lines would clip the sixth.
    final line =
        (ModernEditorWrapper.scaledFontSize(
                  context,
                  EditorSettings.defaults.editorFontSize,
                ) *
                MarkdownConstants.lineHeight)
            .roundToDouble();
    return GuideCaptionAboveKeyboard(
      focusNode: _focus,
      caption: captionSlotKey,
      // Her first line and the stage's air under it, not all six (D22): at
      // 2.0 on a small phone the whole editor and the coach line never fit
      // above the keyboard together, and the line is what says what to type.
      lastExtent: line + GuideMetrics.stagePadding,
      child: GuideStageSlot(
        height: line * GuideMetrics.editorStageLines + _padding.vertical,
        child: Semantics(
          identifier: SemanticsIds.guideBookTryEditor(book, _card.spec.slug),
          container: true,
          // The editor publishes a node per line and its own text field.
          explicitChildNodes: true,
          child: ModernEditorWrapper(
            controller: _controller,
            focusNode: _focus,
            scrollController: _scroll,
            searchController: _search,
            editorFontSize: EditorSettings.defaults.editorFontSize,
            onTextChanged: _onTextChanged,
            showLineNumbers: false,
            wordWrap: true,
            checkboxTapToggle: true,
            onOpenLink: (_) => say(_linkReport),
            onOpenTag: (_) => say(_tagReport),
            onOpenWikiLink: (_) => say(_wikiReport),
            // The ledger is on in a card whatever her setting (§4).
            onMoneyTap: (_) => say(_moneyReport),
            isFenceLine: _render.lineInFence,
            colorPalette: _render.palette,
            hint: null,
            followsTextScale: true,
            // Six lines scroll by drag; the note's rail would be an
            // under-48 dp target on a stage this short.
            showScrollIndicator: false,
            editorPadding: _padding,
            // `docs/guide-hub-roadmap.md` §9.6 (c): the stage already paints
            // the page's ground under its hairline; the wrapper's own would
            // lay a second tint inside it.
            paintGround: false,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _render.bindFocus(null);
    _focus.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }
}
