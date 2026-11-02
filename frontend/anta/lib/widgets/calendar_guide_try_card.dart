import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_category.dart';
import '../models/calendar_guide_coach.dart';
import '../models/calendar_guide_content.dart';
import 'calendar_guide_rows.dart';
import 'form_rows.dart';
import 'month_dot_matrix.dart';
import 'settings_section_list.dart';

/// What one "Try it" card shows and remembers: its stage, built from the real
/// widgets of the page's task, and the coach line that says where to tap
/// next (D40, D49).
///
/// Owned by the page's `State`, never by the card: the kit's list disposes a
/// card scrolled out of view, and a demo that lived in it would forget what
/// she did the moment she scrolled down to read about it. Nothing here is
/// saved — every sheet a stage opens runs in its sandbox mode and its answer
/// lands in the demo.
abstract class GuideCardDemo extends ChangeNotifier {
  GuideCardDemo(GuideCardSpec card) : _coach = GuideCoach(card.steps);

  final GuideCoach _coach;

  List<GuideCoachStep> get steps => _coach.steps;

  /// Every step is done: the line reads the closing line and, at the live
  /// line, the forward button is disabled.
  bool get finished => _coach.finished;

  /// The line is an earlier step's, read back (D70).
  bool get reading => _coach.reading;

  bool get canBack => _coach.canBack;

  bool get canForward => _coach.canForward;

  /// The owner's calendar look, for the pickers and the add button a stage
  /// draws. The defaults until the page has read it, and only read for a
  /// demo that asks ([needsAppearance]).
  CalendarAppearance get appearance => _appearance;
  CalendarAppearance _appearance = const CalendarAppearance();
  set appearance(CalendarAppearance value) {
    _appearance = value;
    notifyListeners();
  }

  bool get needsAppearance => false;

  /// The owner's categories, handed over once `CategoryService` has
  /// answered, for a demo that asks ([needsCategories]): the cache a stage
  /// reads at its first build is still empty when the app relaunches onto
  /// the guide.
  void adoptCategories(List<CalendarCategory> categories) {}

  bool get needsCategories => false;

  /// The stage runs edge to edge inside the card at every text scale, its
  /// hairline only above and below — for a stage of the real calendar's
  /// own width-hungry widgets (the screen page's grid, panel and overview),
  /// which the inset patch would narrow by another 24 dp. The other cards
  /// go edge to edge only from [GuideMetrics.stageFullBleedTextScale] up.
  bool get stageFullBleed => false;

  /// The coach line now: one clause (D49) — the next instruction, or the
  /// report of an action the stage cannot show.
  String line(AppLocalizations l10n) => _coach.line(l10n);

  /// Every report the card can make through [say], each at its longest.
  List<String> reports(AppLocalizations l10n) => const [];

  /// Every line the card can show. The slot is as tall as the tallest, so a
  /// line changes words and never the card's height. Called once per locale.
  List<String> candidates(AppLocalizations l10n) =>
      _coach.candidates(l10n, reports(l10n));

  /// Shows the line of the step before the one shown, to read it again.
  void back() {
    _coach.back();
    notifyListeners();
  }

  /// One step toward the live line; at the live line, steps past the
  /// current instruction without her doing it.
  void forward() {
    _coach.forward();
    notifyListeners();
  }

  Widget buildStage(BuildContext context);

  /// Set once the page has disposed the demo. A stage marks a step after a
  /// sheet's future completes, and the page can go in between — a pop that
  /// takes the sheet and the page together — so every mark after that is
  /// dropped rather than notifying a disposed notifier.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// [action] — a coach step's — just happened; the stage shows what it
  /// did, so the line moves on to what is next.
  @protected
  void did(String action) {
    if (_disposed) return;
    _coach.did(action);
    notifyListeners();
  }

  /// Records what an action that is no step and shows nothing on the stage
  /// did, and redraws the card.
  @protected
  void say(GuideLine report) {
    if (_disposed) return;
    _coach.say(report);
    notifyListeners();
  }

  /// Redraws the card after a change the line does not name. A standing
  /// report belonged to the action before this one, so it goes.
  @protected
  void changed() {
    if (_disposed) return;
    _coach.clearReport();
    notifyListeners();
  }

  /// [changed] without the redraw, for an action whose redraw another
  /// notifier brings — a pick on the screen page's shared demo, which every
  /// card there listens to — so one tap costs one rebuild.
  @protected
  void dropReport() {
    if (_disposed) return;
    _coach.clearReport();
  }

  /// The card's coach slot, for a stage that has to bring the line into
  /// view — the finding card, whose keyboard would cover its matches.
  final GlobalKey captionSlotKey = GlobalKey();
}

/// A title as the coach line quotes it: cut at
/// [GuideMetrics.captionTitleMaxChars] so the line's slot can be sized for
/// any title she types.
String calendarGuideQuote(String title) {
  final characters = title.characters;
  if (characters.length <= GuideMetrics.captionTitleMaxChars) return title;
  return '${characters.take(GuideMetrics.captionTitleMaxChars)}…';
}

/// The stand-in for any typed title among a slot's candidates: a title cut
/// by [calendarGuideQuote], in a glyph as wide as a typical letter rather
/// than Roboto's widest, 'W', which measured a title nobody types. A title
/// of wide capitals can wrap a line past its slot, a cost taken knowingly.
final String calendarGuideLongestQuote =
    '${'n' * GuideMetrics.captionTitleMaxChars}…';

/// A date the guide's captions write, at its widest in [dates]' language
/// over a whole year, for a caption slot's candidates.
String calendarGuideLongestDate(DateFormat dates) {
  var longest = '';
  for (var day = 0; day < 365; day++) {
    final text = dates.format(DateTime.utc(2027, 1, 1 + day));
    if (text.length > longest.length) longest = text;
  }
  return longest;
}

/// One "Try it" card of a page, under [card]'s title: its first instruction
/// as its one entry's title — so the kit's search finds it (D48) — over the
/// card's body, which draws the live coach line in the title's place.
SettingsSectionData calendarGuideTrySection({
  required AppLocalizations l10n,
  required GuideCardSpec card,
  required GuideCardDemo demo,
  required List<String> candidates,
}) {
  return SettingsSectionData(
    icon: calendarGuidePracticeIcon,
    title: card.title(l10n),
    entries: [
      SettingsEntry(
        title: card.steps.first.line(l10n),
        titleStyle: calendarGuideParagraphStyle,
        identifier: SemanticsIds.calendarGuideTry(card.slug),
        builder: (context, _, _) => CalendarGuideTryCard(
          slug: card.slug,
          demo: demo,
          candidates: candidates,
        ),
      ),
    ],
  );
}

/// The body of a "Try it" card: the coach line with its back and forward
/// buttons, then the stage.
///
/// No ink, no chevron, no tap of its own — the card is a place to try
/// things, and only the stage's real controls and the two step buttons
/// answer a finger.
/// Stateless over [demo], which outlives it.
class CalendarGuideTryCard extends StatelessWidget {
  const CalendarGuideTryCard({
    super.key,
    required this.slug,
    required this.demo,
    required this.candidates,
  });

  final String slug;
  final GuideCardDemo demo;

  /// Every line the coach can show, built once per locale by the page.
  final List<String> candidates;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fullBleed =
        demo.stageFullBleed ||
        MediaQuery.textScalerOf(context).scale(1) >=
            GuideMetrics.stageFullBleedTextScale;
    final line = BorderSide(
      color: colorScheme.outlineVariant,
      width: GuideMetrics.stageOutline,
    );
    const inset = EdgeInsets.symmetric(horizontal: GuideMetrics.cardInset);
    return ListenableBuilder(
      listenable: demo,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final style = calendarGuideParagraphStyle.copyWith(
          color: colorScheme.onSurface,
        );
        // One builder for the line and its candidates (D93), so the slot is
        // sized for every line exactly as it can be drawn.
        Widget coachText(String text, {required bool readBack}) {
          if (!readBack) return Text(text, style: style);
          return CalendarGuideReadBackText(
            text,
            style: calendarGuideParagraphStyle.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            markSize: GuideMetrics.coachDoneMarkSize,
            markColor: colorScheme.primary,
          );
        }

        final reading = demo.reading;
        final ink = colorScheme.onSurfaceVariant;
        final disabledInk = ink.withValues(alpha: FormMetrics.disabledOpacity);
        return Padding(
          padding: const EdgeInsets.only(bottom: GuideMetrics.cardInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The line and its candidates are laid out under one clamp, so
              // the slot is sized for the line as drawn.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: GuideMetrics.coachMaxTextScale,
                child: Builder(
                  builder: (context) => Padding(
                    padding: inset,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              top: _lineInset(MediaQuery.textScalerOf(context)),
                            ),
                            child: FormCaptionSlot(
                              key: demo.captionSlotKey,
                              // Level with the pair; a short line leaves its
                              // blank below, never above.
                              alignment: AlignmentDirectional.topStart,
                              candidates: [
                                for (final text in candidates)
                                  coachText(text, readBack: false),
                                for (final step in demo.steps)
                                  coachText(step.line(l10n), readBack: true),
                              ],
                              child: CalendarGuideCoachSemantics(
                                identifier:
                                    SemanticsIds.calendarGuideTryCaption(slug),
                                reading: reading,
                                child: coachText(
                                  demo.line(l10n),
                                  readBack: reading,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // No gap: the targets' own inset keeps the glyphs
                        // off the text (D87). Forward sits where the skip
                        // sat, so nothing moves under the finger.
                        FormTrailingButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: l10n.calendarGuideStepBack,
                          identifier: SemanticsIds.calendarGuideTryStepBack(
                            slug,
                          ),
                          color: ink,
                          disabledColor: disabledInk,
                          onPressed: demo.canBack ? demo.back : null,
                        ),
                        FormTrailingButton(
                          icon: reading
                              ? Icons.chevron_right_rounded
                              : Icons.skip_next_rounded,
                          tooltip: reading
                              ? l10n.calendarGuideStepForward
                              : l10n.calendarGuideSkipStep,
                          identifier: SemanticsIds.calendarGuideTrySkip(slug),
                          color: ink,
                          disabledColor: disabledInk,
                          // Disabled, never hidden, once every step is done.
                          onPressed: demo.canForward ? demo.forward : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: GuideMetrics.coachToStage),
              Padding(
                padding: fullBleed ? EdgeInsets.zero : inset,
                // The stage draws the real calendar's widgets as the calendar
                // draws them, outside the settings kit's row theme.
                child: RepaintBoundary(
                  child: ListTileTheme(
                    data: Theme.of(context).listTileTheme,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.pageGround,
                        border: fullBleed
                            ? Border(top: line, bottom: line)
                            : Border.fromBorderSide(line),
                        borderRadius: fullBleed
                            ? null
                            : BorderRadius.circular(GuideMetrics.stageRadius),
                      ),
                      child: Padding(
                        padding: fullBleed
                            ? const EdgeInsets.symmetric(
                                vertical: GuideMetrics.stagePadding,
                              )
                            : const EdgeInsets.all(GuideMetrics.stagePadding),
                        child: demo.buildStage(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The line sits this far down: its first row, and so the instruction,
  /// centred on the pair's 48 dp targets and their glyphs, as the band's pair
  /// sits on its line. It is the same for every line at a [scaler], so
  /// nothing moves when the line changes; the row stays the taller of the
  /// target and the inset slot.
  static double _lineInset(TextScaler scaler) {
    final firstRow = scaler.scale(
      GuideMetrics.paragraphFontSize * GuideMetrics.paragraphLineHeight,
    );
    return math.max(0, (FormMetrics.trailingButtonSize - firstRow) / 2);
  }
}

/// An earlier step's coach line read back (D90), on a card or the band: led
/// by a done mark so it reads as behind her, its later rows wrapping under
/// the mark. [markSize] is given at 1.0 — the paragraph scales an inline
/// widget with its text, so the mark and its gap grow with the words.
class CalendarGuideReadBackText extends StatelessWidget {
  const CalendarGuideReadBackText(
    this.text, {
    super.key,
    required this.style,
    required this.markSize,
    required this.markColor,
  });

  final String text;
  final TextStyle style;
  final double markSize;
  final Color markColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            // The node's label says "Done" (D91): the glyph alone says
            // nothing to a screen reader.
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: GuideMetrics.coachDoneMarkGap,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: markSize,
                  color: markColor,
                ),
              ),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      style: style,
    );
  }
}

/// The coach line's one node (D91), on a card and on the band: a live region
/// at the live line, so each new instruction or report is announced; off
/// while an earlier line is read back, which she asked for, and then read as
/// "Done" before the line.
class CalendarGuideCoachSemantics extends StatelessWidget {
  const CalendarGuideCoachSemantics({
    super.key,
    required this.reading,
    required this.child,
    this.identifier,
  });

  final bool reading;
  final String? identifier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: !reading,
      identifier: identifier,
      label: reading
          ? AppLocalizations.of(context)!.calendarGuideStepDone
          : null,
      child: child,
    );
  }
}

/// A stage's month of dots, drawn as the year tiles draw it at the largest
/// whole multiple of their size the stage's width holds, between [minScale]
/// and [GuideMetrics.stageMatrixMaxScale]. What it shows, the stage's own
/// rows say, so it is left out of the semantics tree — a matrix that takes
/// taps included: the rows stay the accessible path to the same days.
class CalendarGuideStageMatrix extends StatelessWidget {
  const CalendarGuideStageMatrix({
    super.key,
    required this.matrix,
    this.minScale = GuideMetrics.stageMatrixMinScale,
  });

  final MonthDotMatrix matrix;

  /// [GuideMetrics.stageMatrixTapMinScale] for a matrix she taps, so a
  /// day's hit tile never falls under a touch target.
  final double minScale;

  static double scaleFor(
    double width, {
    double minScale = GuideMetrics.stageMatrixMinScale,
  }) => (width / MonthDotMatrix.width).floorToDouble().clamp(
    minScale,
    GuideMetrics.stageMatrixMaxScale,
  );

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = scaleFor(constraints.maxWidth, minScale: minScale);
          return Center(
            child: SizedBox(
              width: MonthDotMatrix.width * scale,
              height: MonthDotMatrix.height * scale,
              child: FittedBox(child: matrix),
            ),
          );
        },
      ),
    );
  }
}
