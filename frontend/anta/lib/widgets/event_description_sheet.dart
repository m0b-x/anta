import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';

import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../constants/font_constants.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../controllers/editor_edit_tracker.dart';
import '../controllers/editor_render_controller.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/shortcut_applier.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/utility_button_config.dart';
import '../services/settings_service.dart';
import '../utils/editor_render_context.dart';
import '../utils/list_aware_paste.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/re_editor_search_controller.dart';
import 'app_dialogs.dart';
import 'form_rows.dart';
import 'markdown_bar.dart';
import 'modern_editor_wrapper.dart';

/// Full-height editing surface for one event description.
///
/// A **pure text-in / text-out modal**: it never touches a service, never
/// persists, and knows nothing about scope, occurrences or events. [show]
/// returns the edited text, or `null` when the user backed out — so both
/// callers keep the rule that a sheet reports an outcome and the caller
/// dispatches it.
///
/// It exists because the editor sheet's description box is a `CodeEditor`
/// bounded to 260px *inside* the form's own `SingleChildScrollView`, and two
/// nested scrollers fighting over a drag is what makes writing there feel bad.
/// Here the editor is the only scrollable on screen.
///
/// Everything about the re_editor wiring is carried over from
/// `EventEditorSheet` deliberately, traps included:
///
/// * **Money stays disabled by omission.** There is no money parameter to
///   pass — the span builder defaults to `MoneyDisplayConfig.disabled` and
///   stays there as long as nobody calls `configureMoney` on it. Copying the
///   note editor's money wiring into this file is what would break the rule.
/// * **Nothing listens to the controller directly** — see [_revision].
/// * **Seed through `loadText`, never `set text`** — the load is the undo
///   baseline, so undo cannot wipe the text the sheet opened with.
/// * A late-resolving setting is applied with `forceRepaint()`, **never** by
///   remounting the editor.
///
/// A form sheet on [FormSheetFrame] since the 2026-09-27 Tier 1 pass
/// (`docs/calendar-language-tier-1-roadmap.md`, D14): leaving asks first when
/// the text differs from what the sheet opened with. Until then ✕, the
/// barrier, back and a drag all popped `null` at once and a paragraph typed
/// here was gone — the one lost-text path left in the calendar, on the
/// surface that exists for writing more than a line.
class EventDescriptionSheet extends StatefulWidget {
  /// Utility buttons the bar carries — the description's own set, matching the
  /// editor sheet. Counters, font sizing, sharing and scroll jumps all belong
  /// to a note rather than to a description.
  static const List<UtilityButtonConfig> _utilities = [
    UtilityButtonConfig(id: UtilityButtonId.undo),
    UtilityButtonConfig(id: UtilityButtonId.redo),
    UtilityButtonConfig(id: UtilityButtonId.paste),
  ];

  /// Markdown source to open with. The caller resolves which description this
  /// is (a template, one day's override, a plain event's text) — the sheet
  /// only edits the string.
  final String initialText;

  /// The event's title, rendered as the muted first line of the status band
  /// **under** the header rather than beside its title — a one-line
  /// breadcrumb would ellipsise away the half naming the sheet. Empty shows no
  /// such line.
  final String heading;

  /// One line saying what the edit will affect, or null when there is nothing
  /// to warn about (a one-time event's description affects one day by
  /// definition).
  final String? scopeCaption;

  /// Character budget, from Calendar Settings.
  final int limit;

  /// Length the text already had when the sheet opened. Confirming is always
  /// allowed at that length, so lowering the limit blocks *growth* instead of
  /// trapping the user in a sheet they cannot leave.
  final int grandfatheredLength;

  final MarkdownColorPalette colorPalette;

  const EventDescriptionSheet({
    super.key,
    required this.initialText,
    required this.heading,
    required this.limit,
    required this.grandfatheredLength,
    this.scopeCaption,
    this.colorPalette = MarkdownColorPalette.presets,
  });

  /// Opens the sheet. Returns the edited text, or `null` when cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String initialText,
    required String heading,
    required int limit,
    required int grandfatheredLength,
    String? scopeCaption,
    MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      // The editor's route: the frame owns the drag (the route's own would
      // pop past the guard) and paints the ground and the radius itself.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => FractionallySizedBox(
        // Matches the editor sheet rather than the detail sheet's clamp: room
        // is the entire point of this surface.
        heightFactor: FormMetrics.sheetHeightFactor,
        child: EventDescriptionSheet(
          initialText: initialText,
          heading: heading,
          limit: limit,
          grandfatheredLength: grandfatheredLength,
          scopeCaption: scopeCaption,
          colorPalette: colorPalette,
        ),
      ),
    );
  }

  @override
  State<EventDescriptionSheet> createState() => _EventDescriptionSheetState();
}

class _EventDescriptionSheetState extends State<EventDescriptionSheet> {
  late final CodeLineEditingController _controller;

  /// Enter-continuation for list lines, exactly as the note editor gets
  /// it. Only that half is live: the sheet measures no editor width, so
  /// [PasteReformatContext] is always null and the paste-reflow branch is
  /// a no-op by construction — a description is a paragraph or two, not a
  /// document to reflow.
  late final EditorEditTracker _tracker;

  late final FocusNode _focus;
  late final CodeScrollController _scroll;

  /// The wrapper requires one; this sheet has no search UI, so it is created,
  /// wired and thrown away with the sheet.
  late final ReEditorSearchController _search;

  final MarkdownEditorSpanBuilder _spanBuilder = MarkdownEditorSpanBuilder();

  /// The renderer's theme generation, resolved once per theme/style
  /// change instead of once per line.
  final EditorRenderContextCache _renderContext = EditorRenderContextCache();

  /// Build-safe relay for [_controller]'s notifications.
  ///
  /// Nothing here may listen to the controller directly: re_editor's
  /// `_CodeEditorState.initState` wraps it in its own delegate and the
  /// `delegate =` setter calls `notifyListeners()` **synchronously while the
  /// framework is building**, so every `ListenableBuilder` mounted above the
  /// editor throws "setState() called during build" on the first frame.
  ///
  /// Keystrokes arrive outside the frame and take the synchronous path; only a
  /// mid-build notification is deferred, and repeats coalesce into one bump.
  /// The counter, the Done button **and the bar's undo/redo enablement** all
  /// route through it.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  bool _revisionBumpScheduled = false;

  /// Global "live markdown rendering" setting, so the description reads the
  /// same way it does in the note editor. Resolved after the first frame and
  /// applied with a repaint nudge — remounting a `CodeEditor` mid-init crashes
  /// re_editor's controller-delegate handoff.
  bool _liveMarkdownRendering = SettingsKeys.defaultLiveMarkdownRendering;

  /// What the guard compares against: the text as the controller holds it
  /// after seeding, not [EventDescriptionSheet.initialText] itself, so a
  /// line-ending the load normalised cannot make an untouched sheet ask.
  late final String _baseline;

  /// Re-entrancy latch for [_leave]: ✕, back and the barrier can all fire
  /// while the dialog is up.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller = ListAwarePasteController(
      delegate: CodeLineEditingController(spanBuilder: _buildSpan),
      isFenceLine: _spanBuilder.lineInFence,
    );
    // A load, not an edit: `set text` would be revocable and undo could
    // wipe what the sheet opened with.
    _controller.loadText(widget.initialText);
    _baseline = _controller.text;
    _spanBuilder.bind(_controller);
    _tracker = EditorEditTracker(
      controller: _controller,
      autoBreakLongLines: () => false,
      pasteContext: () => null,
      onLinesReformatted: (_) {},
      isFenceLine: _spanBuilder.lineInFence,
    );
    // The seed above is what the next keystroke diffs against; without
    // this the whole loaded text reads as a paste.
    _tracker.syncLength();
    // The palette is passed in already resolved (the page holds a current
    // copy), so unlike the editor sheet there is no late colour swap to
    // repaint for.
    _spanBuilder.configureColors(widget.colorPalette);
    _focus = FocusNode();
    _scroll = CodeScrollController();
    _search = ReEditorSearchController()..initialize(_controller);
    // Subscribed after the seeding write, so opening costs no spurious bump.
    _controller.addListener(_relayChange);
    _loadSettings();
    // A `CodeEditor` is not an `EditableText` and the wrapper hardcodes
    // `autofocus: false`, so nothing focuses it for us. This sheet is only
    // ever reached by an explicit "edit" action, so it opens ready to type.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    // The bar bloc is app-wide and only the note editor loads it, so from a
    // cold start into the calendar it is still Initial. A null note id yields
    // the active profile — the right default for a field that belongs to no
    // note. An already-loaded bar is left alone.
    final barBloc = context.read<MarkdownBarBloc>();
    if (barBloc.state is! MarkdownBarLoaded) {
      barBloc.add(const LoadMarkdownBar());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_relayChange);
    _controller.dispose();
    _revision.dispose();
    _focus.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final liveRendering = await settings.getLiveMarkdownRendering();
    if (!mounted || liveRendering == _liveMarkdownRendering) return;
    setState(() => _liveMarkdownRendering = liveRendering);
    _controller.forceRepaint();
  }

  /// Republishes a controller notification on [_revision], moving it out of
  /// the build phase when it arrives during one.
  void _relayChange() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!duringFrame) {
      _revision.value++;
      return;
    }
    if (_revisionBumpScheduled) return;
    _revisionBumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisionBumpScheduled = false;
      if (mounted) _revision.value++;
    });
  }

  /// Restyles one line, exactly as the note editor and the editor sheet do.
  /// Unhandled lines (and every line while live rendering is off) fall back to
  /// the ghost-text builder, which leaves a line without a `{{ … }}` run as
  /// re_editor's own span — the same routing
  /// [EditorRenderController.buildSpan] does for the note editor, so a ghost
  /// never renders raw on one surface and concealed on another.
  TextSpan _buildSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final render = _renderContext.of(Theme.of(context), style);
    if (_liveMarkdownRendering) {
      final span = _spanBuilder.build(
        context: render,
        index: index,
        codeLine: codeLine,
      );
      if (span != null) return span;
    }
    return EditorRenderController.ghostSpan(
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
      baseColor: render.baseColor,
    );
  }

  /// Whether the text may be confirmed at [length]. Over budget is allowed
  /// only while it is no longer than it already was.
  bool _withinLimit(int length) =>
      length <= widget.limit || length <= widget.grandfatheredLength;

  /// The one length source for both the counter and the Done button. Reading
  /// `textLength` in one place and `String.length` in the other is what makes
  /// "Done is disabled but the counter says you are fine" possible.
  int get _length => _controller.text.length;

  /// Done pops the text as it is, never through the guard: confirming is the
  /// one exit that keeps what was typed.
  void _confirm() => Navigator.of(context).pop(_controller.text);

  /// Whether leaving would lose typed text. A plain compare against the
  /// seeded text rather than the editor sheet's fingerprint: the text is the
  /// whole form here, and typing back to the original is not a change.
  bool get _isDirty => _controller.text != _baseline;

  /// The editor sheet's guard, shared through [AppDialogs.confirmDiscard]:
  /// a clean sheet leaves at once, a dirty one asks (D14).
  Future<bool> _confirmLeave() async {
    if (!_isDirty) return true;
    return AppDialogs.confirmDiscard(context);
  }

  /// Serves ✕, back, the system back gesture, the barrier and a dismissing
  /// drag through [FormSheetFrame]; pops `null` once the guard allows it.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final leave = await _confirmLeave();
      if (!leave || !mounted) return;
      Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  /// Applies a bar shortcut. Mirrors the editor sheet's routing: the ghost /
  /// colour-slot shortcuts have bespoke inserts, everything else goes through
  /// the shared applier as one undo entry. Counter mutation is unreachable —
  /// those shortcuts are filtered out of the bar.
  void _handleShortcut(CustomMarkdownShortcut shortcut) {
    // Guarded like every programmatic insert in the note editor: the
    // notification it fires must not be diffed as typing, and the length
    // must be resynced or the next keystroke is.
    _tracker.runGuarded(() {
      if (MarkdownShortcutInserter.handles(shortcut)) {
        MarkdownShortcutInserter.apply(_controller, shortcut);
      } else {
        _controller.runRevocableOp(() {
          ShortcutApplier.apply(
            controller: _controller,
            shortcut: shortcut,
            mutateCounter: (_, _) async => null,
          );
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.makeCursorVisible();
    });
  }

  /// The docked markdown bar. Unlike the editor sheet's, it is **not**
  /// focus-gated: there the form must not shift when it appears, but here the
  /// description is the entire content, so a stable bar beats a vanishing one.
  ///
  /// Counter-bound shortcuts are filtered out — `{c1}` resolves against a note
  /// context an event does not have.
  Widget _buildBar() {
    return BlocBuilder<MarkdownBarBloc, MarkdownBarState>(
      builder: (context, state) {
        if (state is! MarkdownBarLoaded) return const SizedBox.shrink();
        final shortcuts = state.currentShortcuts
            .where((s) => s.effectiveCounters.isEmpty)
            .toList();
        return ListenableBuilder(
          listenable: _revision,
          builder: (context, _) => MarkdownBar(
            shortcuts: shortcuts,
            isPreviewMode: false,
            canUndo: _controller.canUndo,
            canRedo: _controller.canRedo,
            previewFontSize: FontConstants.defaultFontSize,
            splitEnabled: false,
            showSettings: false,
            showReorder: false,
            utilityConfigs: EventDescriptionSheet._utilities,
            onUndo: _controller.undo,
            onRedo: _controller.redo,
            onPaste: _controller.paste,
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            onShortcutPressed: _handleShortcut,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final caption = widget.scopeCaption;
    final heading = widget.heading.trim();
    final subject = heading.isEmpty ? null : heading;
    // Reserved from the sheet's static inputs alone, so the over-limit
    // explanation can appear without resizing the editor under the caret:
    // the subject's line plus two for the scope caption while both exist,
    // else two, in `bodySmall` scaled with the user's text size. Over budget
    // the explanation replaces the whole band text, subject included — it is
    // the more urgent line, it already took the caption's slot, and reserving
    // a third line for it on an event without a caption left two empty lines
    // above the event name (D23). A status line that pushes the editor around
    // at exactly the moment the user is fighting the limit is the worst time
    // to move it.
    final statusStyle = theme.textTheme.bodySmall;
    final statusLineHeight =
        MediaQuery.textScalerOf(context).scale(statusStyle?.fontSize ?? 12) *
        FormMetrics.statusLineFactor;
    final statusBandHeight =
        statusLineHeight * (subject != null && caption != null ? 3 : 2);
    // The bar is a fixed footer below the editor, so the clearance goes on the
    // bar — never on the whole sheet. The sheet's box is a fixed fraction of
    // the screen and does not shrink for the keyboard, so padding the body
    // subtracts the inset from the content: with a tall IME (or a stale inset
    // frame) that reaches zero, the header stops rendering and the sheet reads
    // as blank and dead. Padding the footer instead lets the editor's
    // `Expanded` absorb the loss and keeps the header on screen and tappable.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return FormSheetFrame(
      onLeave: _leave,
      isClean: () => !_isDirty,
      onDismiss: () => Navigator.of(context).pop(),
      chrome: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.descriptionClose,
            onLeading: _leave,
            title: l10n.eventDescription,
            trailingInset: FormMetrics.headerActionInset,
            trailing: ListenableBuilder(
              listenable: _revision,
              builder: (context, _) => FormHeaderTextButton(
                label: l10n.eventDescriptionDone,
                identifier: SemanticsIds.descriptionDone,
                onPressed: _withinLimit(_length) ? _confirm : null,
              ),
            ),
          ),
        ],
      ),
      body: [
        // One builder for both halves: the counter and the over-limit line
        // answer the same question, and reading the length once per change
        // keeps them from ever disagreeing. The band sits at the section
        // label's inset so its text lines up with the editor's own 16dp text
        // padding behind the 4dp inset below.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RowMetrics.groupInset + RowMetrics.sectionLabelInset,
            0,
            RowMetrics.groupInset + RowMetrics.sectionLabelInset,
            RowMetrics.sectionLabelBottomPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: statusBandHeight),
            child: ListenableBuilder(
              listenable: _revision,
              builder: (context, _) {
                final over = !_withinLimit(_length);
                // Over budget the explanation is the band's only text — the
                // subject goes with the caption — so the reserved lines are
                // the message's whatever the event, and swapping costs no
                // layout change where stacking would.
                final message = over
                    ? l10n.eventDescriptionTooLong(widget.limit)
                    : caption;
                final statusColor = over
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The event name is a line of its own down here,
                          // never a `title · Description` breadcrumb in the
                          // header: between a 48dp icon and Done there is
                          // barely 180dp left on a phone, and a one-line
                          // breadcrumb ellipsises away the half that says
                          // what the sheet *is*. Here the event name
                          // truncates and the title never does (D14; a
                          // second header line was considered and rejected —
                          // one title per header).
                          if (!over && subject != null)
                            Text(
                              subject,
                              style: statusStyle?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (message != null)
                            Text(
                              message,
                              style: statusStyle?.copyWith(color: statusColor),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: RowMetrics.gap),
                    Text(
                      l10n.eventDescriptionCount(_length, widget.limit),
                      style: statusStyle?.copyWith(
                        color: statusColor,
                        fontWeight: over ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        // The editor owns all remaining height, so there is no outer scroll
        // view for it to fight — the whole reason this sheet exists. No
        // border: a bounded field inside a form earns one, a full-height
        // writing surface does not, and the note editor — the app's other
        // full-height editor — has none either. The 4dp inset only lines the
        // editor's own 16dp text padding up with the 20dp sheet gutter.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ModernEditorWrapper(
              controller: _controller,
              focusNode: _focus,
              scrollController: _scroll,
              searchController: _search,
              editorFontSize: FontConstants.defaultFontSize,
              onTextChanged: _tracker.onTextChanged,
              checkboxTapToggle: _liveMarkdownRendering,
              showScrollIndicator: false,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: bottomClearance),
          child: _buildBar(),
        ),
      ],
    );
  }
}
