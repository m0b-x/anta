part of '../event_editor_sheet.dart';

/// The description as drawn: the scope strip, the cell with its counter,
/// the markdown bar and its shortcuts, and the full-height sheet.
mixin _EventEditorDescriptionViews on _EventEditorAlertsAndLinks {
  static const double _descriptionCounterTopInset = 4;
  static const int _descriptionMaxLines = 10;
  static const double _scopeStripHeight = 44;

  /// Utility buttons the description bar carries. Font sizing, sharing, bar
  /// switching, counters and scroll jumps all belong to a note, not to a
  /// 2000-character field; settings and reorder are suppressed by flag.
  static const List<UtilityButtonConfig> _descriptionUtilities = [
    UtilityButtonConfig(id: UtilityButtonId.undo),
    UtilityButtonConfig(id: UtilityButtonId.redo),
    UtilityButtonConfig(id: UtilityButtonId.paste),
  ];

  Widget _buildScopeStrip(AppLocalizations l10n, ThemeData theme) {
    final showReset =
        _scope == _DescriptionScope.thisDay &&
        _dayMaterialized &&
        !_dayResetRequested;
    return SizedBox(
      height: _scopeStripHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: RowMetrics.groupInset, right: 4),
        child: Row(
          children: [
            FormChip(
              label: l10n.eventDescriptionScopeAllDays,
              selected: _scope == _DescriptionScope.allDays,
              tapTarget: _scopeStripHeight,
              onTap: () => _setScope(_DescriptionScope.allDays),
            ),
            const SizedBox(width: FormMetrics.chipSpacing),
            FormChip(
              label: l10n.eventDescriptionScopeThisDay,
              selected: _scope == _DescriptionScope.thisDay,
              tapTarget: _scopeStripHeight,
              onTap: () => _setScope(_DescriptionScope.thisDay),
            ),
            Expanded(
              child: showReset
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resetDayToTemplate,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, _scopeStripHeight),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                            fontSize: FormMetrics.captionSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: Text(
                          l10n.eventDescriptionResetDayShort,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          semanticsLabel: l10n.eventDescriptionResetDay,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionCell(AppLocalizations l10n, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final showPreviewToggle = !_liveMarkdownRendering;
    final previewing = showPreviewToggle && _descriptionPreview;
    final rightInset = showPreviewToggle
        ? FormMetrics.trailingButtonSize * 2
        : FormMetrics.trailingButtonSize;
    // The empty box's floor is one line of the placeholder, which follows the
    // system text size: at the unscaled 22 px a large-scale placeholder hung
    // past the box into the cell's bottom padding and sat on the card's edge.
    final minLine =
        MediaQuery.textScalerOf(
          context,
        ).scale(FormMetrics.descriptionFontSize) *
        FormMetrics.descriptionLineHeight /
        FormMetrics.descriptionFontSize;
    const maxBox = FormMetrics.descriptionLineHeight * _descriptionMaxLines;
    final Widget surface;
    if (previewing) {
      final text = _descriptionController.text;
      surface = ConstrainedBox(
        constraints: BoxConstraints(minHeight: minLine, maxHeight: maxBox),
        child: text.trim().isEmpty
            ? const SizedBox.shrink()
            : SimpleMarkdownPreview(
                data: text,
                padding: EdgeInsets.zero,
                colorPalette: _colorPalette,
                scrollController: _descriptionPreviewScroll,
              ),
      );
    } else {
      surface = _DescriptionBox(
        revision: _descriptionRevision,
        measure: () => _descriptionScroll.contentHeight,
        minHeight: minLine,
        maxHeight: maxBox,
        child: ModernEditorWrapper(
          controller: _descriptionController,
          focusNode: _descriptionFocus,
          scrollController: _descriptionScroll,
          searchController: _descriptionSearch,
          editorFontSize: FormMetrics.descriptionFontSize,
          editorLineHeight:
              FormMetrics.descriptionLineHeight /
              FormMetrics.descriptionFontSize,
          editorPadding: EdgeInsets.zero,
          paintGround: false,
          onTextChanged: _descriptionEdits.onTextChanged,
          checkboxTapToggle: _liveMarkdownRendering,
          // A fenced line renders raw, so a box drawn there is text: taps
          // on it stay plain editing.
          isFenceLine: _descriptionSpanBuilder.lineInFence,
          hapticsEnabled: _hapticsEnabled,
          // The wrapper's own rail would sit on the last characters of every
          // line (the box has no padding to hold it); the cell draws one in
          // its button gutter instead.
          showScrollIndicator: false,
        ),
      );
    }
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentPlain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_scopeControlVisible) _buildScopeStrip(l10n, theme),
          Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  FormMetrics.descriptionCellPadding,
                  0,
                  FormMetrics.descriptionCellPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The rail shares the text's own stack, not the cell's,
                    // so it ends where the text box ends whether or not the
                    // counter sits under it. It lives in the button gutter —
                    // space the cell always has — so the text never rewraps
                    // when it appears, and starts under the buttons so it
                    // never takes a touch meant for one.
                    Stack(
                      // Passthrough, so the surface keeps the column's tight
                      // width: a loose stack let the rendered preview shrink
                      // to its longest line, and only that strip scrolled.
                      fit: StackFit.passthrough,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(right: rightInset),
                          child:
                              NotificationListener<ScrollMetricsNotification>(
                                onNotification: (_) {
                                  _descriptionMetricsTick.value++;
                                  return false;
                                },
                                child: Semantics(
                                  identifier: SemanticsIds.eventDescription,
                                  explicitChildNodes: true,
                                  child: KeyedSubtree(
                                    key: _descriptionKey,
                                    child: surface,
                                  ),
                                ),
                              ),
                        ),
                        Positioned(
                          top:
                              FormMetrics.trailingButtonSize -
                              FormMetrics.descriptionCellPadding,
                          right: 0,
                          bottom: 0,
                          child: ScrollProgressIndicator(
                            scrollController: previewing
                                ? _descriptionPreviewScroll
                                : _descriptionScroll.verticalScroller,
                            repaint: _descriptionMetricsTick,
                            hideWhenNotScrollable: true,
                          ),
                        ),
                      ],
                    ),
                    ListenableBuilder(
                      listenable: _descriptionRevision,
                      builder: (context, _) {
                        final length = _descriptionController.textLength;
                        final over = !_activeScopeWithinLimit;
                        if (!over && length < _descriptionCounterFrom) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: EdgeInsets.only(
                            top: _descriptionCounterTopInset,
                            right: rightInset,
                          ),
                          child: Text(
                            l10n.eventDescriptionCount(
                              length,
                              _descriptionLimit,
                            ),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: FormMetrics.counterSize,
                              height: 16 / FormMetrics.counterSize,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: over
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (!previewing)
                Positioned(
                  left: RowMetrics.groupInset,
                  top: FormMetrics.descriptionCellPadding,
                  right: rightInset,
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: _descriptionRevision,
                      builder: (context, _) {
                        if (_descriptionController.textLength > 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          l10n.eventDescriptionAdd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: FormMetrics.descriptionFontSize,
                            height:
                                FormMetrics.descriptionLineHeight /
                                FormMetrics.descriptionFontSize,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showPreviewToggle)
                      FormTrailingButton(
                        icon: _descriptionPreview
                            ? Icons.edit_outlined
                            : Icons.visibility_outlined,
                        tooltip: _descriptionPreview
                            ? l10n.eventDescriptionPreviewOff
                            : l10n.eventDescriptionPreviewOn,
                        onPressed: () => setState(
                          () => _descriptionPreview = !_descriptionPreview,
                        ),
                      ),
                    FormTrailingButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: l10n.eventDescriptionExpand,
                      identifier: SemanticsIds.eventDescriptionExpand,
                      onPressed: _openDescriptionSheet,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: _descriptionRevision,
            builder: (context, _) {
              if (_activeScopeWithinLimit) return const SizedBox.shrink();
              return FormCaption(
                text: l10n.eventDescriptionTooLong(_descriptionLimit),
                error: true,
                padding: const EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  0,
                  RowMetrics.groupInset,
                  FormMetrics.descriptionCaptionBottomPadding,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The markdown bar, shown only while the description has focus. It sits
  /// below the sheet's scroll view so appearing costs the form no layout
  /// shift — the sheet's height is fixed, so the bar takes its strip from
  /// the scrollable area.
  ///
  /// Counter-bound shortcuts are filtered out: `{c1}` resolves against a note
  /// context an event does not have, and wiring them to the global counters
  /// would mutate them from a calendar sheet.
  ///
  /// Undo/redo enablement follows the controller through a [ListenableBuilder]
  /// rather than `setState`, so a keystroke repaints the bar instead of the
  /// whole form.
  Widget _buildDescriptionBar() {
    return BlocBuilder<MarkdownBarBloc, MarkdownBarState>(
      builder: (context, state) {
        if (state is! MarkdownBarLoaded) return const SizedBox.shrink();
        final shortcuts = state.currentShortcuts
            .where((s) => s.effectiveCounters.isEmpty)
            .toList();
        return ListenableBuilder(
          listenable: _descriptionRevision,
          builder: (context, _) => MarkdownBar(
            shortcuts: shortcuts,
            isPreviewMode: false,
            canUndo: _descriptionController.canUndo,
            canRedo: _descriptionController.canRedo,
            previewFontSize: FontConstants.defaultFontSize,
            splitEnabled: false,
            showSettings: false,
            showReorder: false,
            utilityConfigs: _descriptionUtilities,
            onUndo: _descriptionController.undo,
            onRedo: _descriptionController.redo,
            onPaste: _descriptionController.paste,
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            onShortcutPressed: _handleDescriptionShortcut,
            hapticsEnabled: _hapticsEnabled,
          ),
        );
      },
    );
  }

  /// Applies a bar shortcut to the description. Mirrors the note editor's
  /// routing: the ghost / colour-slot shortcuts have bespoke inserts, and
  /// everything else goes through the shared applier as one undo entry.
  /// Counter mutation is unreachable — those shortcuts never reach the bar.
  void _handleDescriptionShortcut(CustomMarkdownShortcut shortcut) {
    // Guarded like every programmatic insert in the note editor: the
    // notification it fires must not be diffed as typing, and the length
    // must be resynced or the next keystroke is.
    _descriptionEdits.runGuarded(() {
      if (MarkdownShortcutInserter.handles(shortcut)) {
        MarkdownShortcutInserter.apply(_descriptionController, shortcut);
      } else {
        _descriptionController.runRevocableOp(() {
          ShortcutApplier.apply(
            controller: _descriptionController,
            shortcut: shortcut,
            mutateCounter: (_, _) async => null,
            isFenceLine: _descriptionSpanBuilder.lineInFence,
          );
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _descriptionController.makeCursorVisible();
    });
  }

  /// Opens the description in a full-height sheet and folds the result back
  /// into the field.
  ///
  /// Seeded from the controller — **the active scope only**. The scope control
  /// stays behind in the form and the sheet never sees it, which is what keeps
  /// the sheet a pure text-in / text-out widget and the two-buffer
  /// copy-on-write logic in exactly one place. Nothing is saved here either:
  /// this edits the in-flight controller, and the form still saves.
  Future<void> _openDescriptionSheet() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final initial = _descriptionController.text;
    final onDay = _scopeControlVisible && _scope == _DescriptionScope.thisDay;
    final result = await EventDescriptionSheet.show(
      context,
      initialText: initial,
      heading: _titleController.text.trim(),
      // Each scope carries its own budget and its own grandfather, so the
      // sheet is handed the active one's.
      limit: _descriptionLimit,
      grandfatheredLength: onDay ? _initialDayLength : _initialTemplateLength,
      scopeCaption: _scopeControlVisible
          ? (onDay
                ? l10n.eventDescriptionScopeThisDayHint
                : l10n.eventDescriptionScopeAllDaysHint)
          : null,
      colorPalette: _colorPalette,
    );
    if (result == null || !mounted || result == initial) return;
    // `loadText` for the same reason a scope swap uses it: `set text` is a
    // revocable op, so undo would otherwise pull back the text the sheet
    // replaced. The active scope's buffer is the controller itself, so there
    // is nothing else to mirror into. `setState` refreshes the reset button
    // and, while live rendering is off, the read-only preview.
    setState(() {
      _descriptionController.loadText(result);
      _descriptionEdits.syncLength();
    });
  }
}
