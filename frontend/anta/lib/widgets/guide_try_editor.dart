import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../config/default_markdown_shortcuts.dart';
import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/markdown_constants.dart';
import '../constants/semantics_ids.dart';
import '../controllers/editor_edit_tracker.dart';
import '../controllers/editor_render_controller.dart';
import '../controllers/list_indent_action.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/shortcut_applier.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/editor_settings.dart';
import '../models/guide_content.dart';
import '../models/utility_button_config.dart';
import '../utils/list_aware_paste.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';
import '../utils/re_editor_search_controller.dart';
import 'automation_id.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'markdown_bar.dart';
import 'modern_editor_wrapper.dart';

/// A notes card's stage (D17): the note editor itself — the same wrapper,
/// paste controller, render controller and edit tracker, wired as the
/// editor page wires them — over an in-memory seed, with the app's own bar
/// over it (`docs/guide-hub-roadmap.md` D27, D29), so every path the book
/// describes works here as in a note. Nothing is saved; the text is hers
/// until the page goes.
///
/// The coach reads the document, never a tap (D18): after every edit each
/// step not yet done runs its check, and every check that passes marks its
/// step, several in one edit if one edit shows them. A bar button writes
/// into the document like a keystroke, so its step is read the same way.
class GuideEditorDemo extends GuideCardDemo {
  GuideEditorDemo({required this.book, required GuideEditorCard card})
    : _card = card,
      _maker = card.maker ? TextEditingController() : null,
      _makerFocus = card.maker ? FocusNode() : null,
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
    _controller.addListener(_onControllerChanged);
    _maker?.addListener(_onMakerChanged);
  }

  /// The book's slug, for the stage's ids.
  final String book;

  final GuideEditorCard _card;

  /// What her own button writes (D34), on a card that lets her make one.
  final TextEditingController? _maker;
  final FocusNode? _makerFocus;

  /// The maker text the checks last read, so a caret move in the field —
  /// which notifies its controller too — runs none.
  String _makerChecked = '';

  /// How often her own button wrote its text: what the `press` step reads.
  int _ownPresses = 0;

  /// The counters the card's shortcuts count with (D33): the stage's own,
  /// from zero, so the first `{c1}` writes 1 and none of hers is touched.
  final Map<String, int> _counters = {};

  /// Whether the editor can undo and redo. The bar listens to this rather
  /// than to the controller, which notifies on every keystroke and caret
  /// move.
  final ValueNotifier<(bool, bool)> _history = ValueNotifier((false, false));

  /// The bar's shortcuts in [_barLocale]'s language, built once per
  /// language.
  List<CustomMarkdownShortcut>? _barShortcuts;
  String? _barLocale;

  /// Set by [dispose]: a press resolves its counters across an await, and
  /// the page can go in between.
  bool _gone = false;

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

  /// The bar is docked at the stage's top edge
  /// (`docs/guide-hub-roadmap.md` D29), so the stage keeps its own air
  /// under it and none above.
  @override
  bool get stageFlush => true;

  /// Loads the seed in [l10n]'s language the first time there is one
  /// (`docs/guide-hub-roadmap.md` §9.6 (a)): the page builds the demo before
  /// it has a language. Never again — once she typed, a change of language
  /// must not take her text.
  void seed(AppLocalizations l10n) {
    if (_seeded) return;
    _seeded = true;
    _controller.loadText(_card.seed(l10n));
    // A bar button writes at the caret: it waits at the end of the note,
    // where a line would be added, never at its top (D30).
    final last = _controller.codeLines.length - 1;
    _controller.selection = CodeLineSelection.collapsed(
      index: last,
      offset: _controller.codeLines[last].text.length,
    );
    // The wrapper is not mounted yet, so the tracker never saw the load:
    // adopt its length, or her first keystroke reads as a paste.
    _edits.syncLength();
    _checked = _controller.text;
    // Whatever the load reported on its way, a seeded note has no history.
    _onControllerChanged();
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
    _runChecks();
  }

  void _onMakerChanged() {
    final text = _maker!.text;
    if (text == _makerChecked) return;
    _makerChecked = text;
    _runChecks();
  }

  void _onControllerChanged() {
    final history = (_controller.canUndo, _controller.canRedo);
    if (history != _history.value) _history.value = history;
  }

  /// Runs every step not yet done over the note as it stands now.
  void _runChecks() {
    // The lines as the stage draws them: the render controller's fence role
    // covers code fences, `%%` comments and front matter alike, one lookup
    // per line — its `blockStateAt` walks a segment per call.
    final lines = GuideEditorDocument.blankBlocks(
      _controller.text.split('\n'),
      _render.lineInFence,
    );
    final document = GuideEditorDocument(
      lines: lines,
      previousLines: _lastLines,
      hasDone: hasDone,
      palette: _render.palette,
      makerText: _maker?.text ?? '',
      ownPresses: _ownPresses,
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
  static String _emptyButtonReport(AppLocalizations l10n) =>
      l10n.notesGuideReportEmptyButton(l10n.markdownStart);

  /// Every tap that would leave the note (D19): a card cannot know what she
  /// will type, so all four, each saying what a note would do and never
  /// quoting her text — and, where she makes a button, the one for a press
  /// before it has anything to write.
  @override
  List<String> reports(AppLocalizations l10n) => [
    _tagReport(l10n),
    _wikiReport(l10n),
    _linkReport(l10n),
    _moneyReport(l10n),
    if (_card.maker) _emptyButtonReport(l10n),
  ];

  /// The card's buttons (D27): its built-ins in the shipped bar's order,
  /// shown whatever their stored visibility — the money buttons ship
  /// hidden — then its own, then hers.
  List<CustomMarkdownShortcut> _shortcutsFor(AppLocalizations l10n) {
    final cached = _barShortcuts;
    if (cached != null && _barLocale == l10n.localeName) return cached;
    final bar = _card.bar;
    _barLocale = l10n.localeName;
    return _barShortcuts = [
      for (final shortcut in DefaultMarkdownShortcuts.shortcuts)
        if (bar.builtIns.contains(shortcut.id))
          shortcut.copyWith(isVisible: true),
      ...?bar.own?.call(l10n),
      if (_card.maker)
        CustomMarkdownShortcut(
          id: GuideEditorCard.ownShortcutId,
          label: l10n.notesGuideShortcutMineLabel,
          iconCodePoint: Icons.star.codePoint,
          iconFontFamily: 'MaterialIcons',
          beforeText: '',
          afterText: '',
        ),
    ];
  }

  /// A bar button, run as the note editor runs one
  /// (`optimized_note_editor_page.dart` `_handleShortcut`): focus first, so
  /// the edit lands at a painted caret; counters resolved before the
  /// document is touched; then one guarded, revocable write, so the edit
  /// tracker never reads it as typing and one undo takes it back whole.
  Future<void> _onShortcut(CustomMarkdownShortcut pressed) async {
    var shortcut = pressed;
    final own = pressed.id == GuideEditorCard.ownShortcutId;
    if (own) {
      final text = _maker?.text ?? '';
      if (text.trim().isEmpty) {
        say(_emptyButtonReport);
        return;
      }
      shortcut = pressed.copyWith(beforeText: text);
    }
    if (!_focus.hasFocus) _focus.requestFocus();
    if (MarkdownShortcutInserter.handles(shortcut)) {
      _edits.runGuarded(
        () => MarkdownShortcutInserter.apply(_controller, shortcut),
      );
    } else {
      final text = await ShortcutApplier.resolve(
        controller: _controller,
        shortcut: shortcut,
        mutateCounter: _mutateCounter,
      );
      if (_gone) return;
      // Counted before the write: the editor reports the write to the
      // checks as it lands, and `press` is read off this count (D34).
      if (own) _ownPresses++;
      _edits.runGuarded(() {
        _controller.runRevocableOp(() {
          // A null resolution is a rewrite — a heading level, a line marker
          // or a wrapper toggled — rather than an insert at the selection.
          if (text == null) {
            ShortcutApplier.applyRewrite(
              _controller,
              shortcut,
              isFenceLine: _render.lineInFence,
              headingLevelAt: _render.headingLevelAt,
            );
          } else {
            _controller.replaceSelection(text);
          }
        });
      });
    }
    _onTextChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_gone) _controller.makeCursorVisible();
    });
  }

  /// One `{cN}` token of a card's shortcut (D33), counted here and nowhere
  /// else: a sandbox never reads or moves a counter of hers.
  Future<int?> _mutateCounter(String counterId, CounterOp op) async {
    final current = _counters[counterId] ?? 0;
    return _counters[counterId] = switch (op) {
      CounterOp.increment => current + 1,
      CounterOp.keep => current,
      CounterOp.decrement => current - 1,
    };
  }

  /// The bar's indent and outdent, the Tab edit a soft keyboard cannot
  /// send, through the one path every indent takes.
  void _shiftIndent({required bool outdent}) {
    if (!_focus.hasFocus) _focus.requestFocus();
    final before = _controller.codeLines;
    _edits.runGuarded(
      () => ListIndentAction.apply(
        _controller,
        outdent: outdent,
        isFenceLine: _render.lineInFence,
      ),
    );
    if (_controller.codeLines == before) return;
    _onTextChanged();
  }

  /// The caret line's heading level for the bar's heading menu, as the
  /// editor page reads it: an underline answers its heading's level,
  /// negated.
  int? _caretHeadingLevel() {
    final index = _controller.selection.startIndex;
    if (index < 0 || index >= _controller.codeLines.length) return null;
    final level = _render.headingLevelAt(index);
    return level == 0 ? null : level.abs();
  }

  Widget _buildBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final utilities = _card.bar.utilities;
    return Semantics(
      identifier: SemanticsIds.guideBookTryBar(book, _card.spec.slug),
      container: true,
      // Each button is a node of its own under the bar's.
      explicitChildNodes: true,
      // The bar's hairline, on the stage's ground rather than the bar's own
      // surface: in light that surface is the card's, and the bar would
      // read as the card's edge instead of the note's (D29).
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant,
              width: GuideMetrics.stageOutline,
            ),
          ),
        ),
        child: ValueListenableBuilder<(bool, bool)>(
          valueListenable: _history,
          builder: (context, history, _) => MarkdownBar(
            shortcuts: _shortcutsFor(l10n),
            isPreviewMode: false,
            canUndo: history.$1,
            canRedo: history.$2,
            showBackground: false,
            fadeGround: colorScheme.pageGround,
            previewFontSize: EditorSettings.defaults.editorFontSize,
            // One row in the card's own order: a lesson's buttons lead, and
            // nothing is pinned apart from them at the far edge.
            splitEnabled: false,
            pinUndoRedo: false,
            showSettings: false,
            showReorder: false,
            utilityConfigs: [
              for (final id in utilities) UtilityButtonConfig(id: id),
            ],
            onUndo: _controller.undo,
            onRedo: _controller.redo,
            onIndent: utilities.contains(UtilityButtonId.indent)
                ? () => _shiftIndent(outdent: false)
                : null,
            onOutdent: utilities.contains(UtilityButtonId.outdent)
                ? () => _shiftIndent(outdent: true)
                : null,
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            currentHeadingLevel: _caretHeadingLevel,
            onShortcutPressed: _onShortcut,
          ),
        ),
      ),
    );
  }

  /// The one field of the New Shortcut page a lesson needs (D34), under its
  /// own label there, so she meets it again when she makes a real one.
  Widget _buildMaker(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GuideCaptionAboveKeyboard(
      focusNode: _makerFocus!,
      caption: captionSlotKey,
      child: Padding(
        padding: _padding,
        child: AutomationId(
          identifier: SemanticsIds.guideBookTryMaker(book, _card.spec.slug),
          child: TextField(
            controller: _maker,
            focusNode: _makerFocus,
            maxLength: GuideMetrics.makerMaxChars,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.markdownStart,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ),
      ),
    );
  }

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
    final editor = GuideCaptionAboveKeyboard(
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
    // The bar leads the stage, under the line that names its buttons, not
    // under the note as in the app (D29): there the keyboard holds it in
    // view, while here a bar below six lines would sit under the keyboard
    // on a small phone or at a large text size, and every step would start
    // with a scroll. A flush stage keeps its own air under the bar.
    const air = SizedBox(height: GuideMetrics.stagePadding);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBar(context),
        air,
        if (_card.maker) ...[_buildMaker(context), air],
        editor,
        air,
      ],
    );
  }

  @override
  void dispose() {
    _gone = true;
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _render.bindFocus(null);
    _focus.dispose();
    _scroll.dispose();
    _search.dispose();
    _maker?.dispose();
    _makerFocus?.dispose();
    _history.dispose();
    super.dispose();
  }
}
