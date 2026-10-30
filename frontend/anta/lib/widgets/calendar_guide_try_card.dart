import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
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
  GuideCardDemo(CalendarGuideTopic topic) : _coach = GuideCoach(topic.steps);

  final GuideCoach _coach;

  List<GuideCoachStep> get steps => _coach.steps;

  /// Every step is done: the line reads the closing line and the skip
  /// button is disabled.
  bool get finished => _coach.finished;

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

  /// The coach line now: one clause (D49) — the next instruction, or the
  /// report of an action the stage cannot show.
  String line(AppLocalizations l10n) => _coach.line(l10n);

  /// Every report the card can make through [say], each at its longest.
  List<String> reports(AppLocalizations l10n) => const [];

  /// Every line the card can show. The slot is as tall as the tallest, so a
  /// line changes words and never the card's height. Called once per locale.
  List<String> candidates(AppLocalizations l10n) =>
      _coach.candidates(l10n, reports(l10n));

  /// Steps past the current instruction without her doing it.
  void skip() {
    _coach.skip();
    notifyListeners();
  }

  Widget buildStage(BuildContext context);

  /// [action] — a coach step's — just happened; the stage shows what it
  /// did, so the line moves on to what is next.
  @protected
  void did(String action) {
    _coach.did(action);
    notifyListeners();
  }

  /// Records what an action that is no step and shows nothing on the stage
  /// did, and redraws the card.
  @protected
  void say(GuideLine report) {
    _coach.say(report);
    notifyListeners();
  }

  /// Redraws the card after a change the line does not name. A standing
  /// report belonged to the action before this one, so it goes.
  @protected
  void changed() {
    _coach.clearReport();
    notifyListeners();
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

/// One [DateFormat] of a demo, made again only when the language changes:
/// a format parses its pattern when it is made, and a stage or a caption
/// that made one per build paid that on every keystroke and every tap.
class GuideLocaleFormat {
  GuideLocaleFormat(this._make);

  final DateFormat Function(String localeName) _make;
  DateFormat? _format;
  String? _localeName;

  DateFormat of(AppLocalizations l10n) {
    final format = _format;
    if (format != null && _localeName == l10n.localeName) return format;
    _localeName = l10n.localeName;
    return _format = _make(l10n.localeName);
  }
}

/// The page's "Try it" card: its first instruction as its one entry's
/// title — so the kit's search finds it (D48) — over the card's body, which
/// draws the live coach line in the title's place.
SettingsSectionData calendarGuideTrySection({
  required AppLocalizations l10n,
  required CalendarGuideTopic topic,
  required String lead,
  required GuideCardDemo demo,
  required List<String> candidates,
}) {
  return SettingsSectionData(
    icon: calendarGuidePracticeIcon,
    title: l10n.calendarGuideTryIt,
    entries: [
      SettingsEntry(
        title: lead,
        titleStyle: calendarGuideParagraphStyle,
        identifier: SemanticsIds.calendarGuideTry(topic.slug),
        builder: (context, _, _) => CalendarGuideTryCard(
          slug: topic.slug,
          demo: demo,
          candidates: candidates,
        ),
      ),
    ],
  );
}

/// The body of a "Try it" card: the coach line with its skip button, then
/// the stage.
///
/// No ink, no chevron, no tap of its own — the card is a place to try
/// things, and only the stage's real controls and the skip answer a finger.
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
        return Padding(
          padding: const EdgeInsets.only(bottom: GuideMetrics.cardInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
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
                          // Level with the skip; a short line leaves its
                          // blank below, never above.
                          alignment: AlignmentDirectional.topStart,
                          candidates: [
                            for (final text in candidates)
                              Text(text, style: style),
                          ],
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            identifier: SemanticsIds.calendarGuideTryCaption(
                              slug,
                            ),
                            child: Text(demo.line(l10n), style: style),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: GuideMetrics.coachGap),
                    FormTrailingButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: l10n.calendarGuideSkipStep,
                      identifier: SemanticsIds.calendarGuideTrySkip(slug),
                      color: colorScheme.onSurfaceVariant,
                      disabledColor: colorScheme.onSurfaceVariant.withValues(
                        alpha: FormMetrics.disabledOpacity,
                      ),
                      // Disabled, never hidden, once every step is done.
                      onPressed: demo.finished ? null : demo.skip,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GuideMetrics.coachToStage),
              Padding(
                padding: fullBleed ? EdgeInsets.zero : inset,
                child: RepaintBoundary(
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
            ],
          ),
        );
      },
    );
  }

  /// The line sits this far down: its first row, and so the instruction,
  /// centred on the skip's 48 dp target and its glyph, as the band's skip
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

/// A stage's month of dots, drawn as the year tiles draw it at the largest
/// whole multiple of their size the stage's width holds, between
/// [GuideMetrics.stageMatrixMinScale] and [GuideMetrics.stageMatrixMaxScale].
/// What it shows, the stage's own rows say, so it is left out of the
/// semantics tree.
class CalendarGuideStageMatrix extends StatelessWidget {
  const CalendarGuideStageMatrix({super.key, required this.matrix});

  final MonthDotMatrix matrix;

  static double scaleFor(double width) =>
      (width / MonthDotMatrix.width).floorToDouble().clamp(
        GuideMetrics.stageMatrixMinScale,
        GuideMetrics.stageMatrixMaxScale,
      );

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = scaleFor(constraints.maxWidth);
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
