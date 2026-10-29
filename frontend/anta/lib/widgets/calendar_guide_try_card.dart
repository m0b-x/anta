import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_guide_content.dart';
import 'calendar_guide_rows.dart';
import 'form_rows.dart';
import 'month_dot_matrix.dart';
import 'settings_section_list.dart';

/// What one "Try it" card shows and remembers: its stage, built from the real
/// widgets of the page's task, and the caption that says what the last
/// action did.
///
/// Owned by the page's `State`, never by the card: the kit's list disposes a
/// card scrolled out of view, and a demo that lived in it would forget what
/// she did the moment she scrolled down to read about it. Nothing here is
/// saved — every sheet a stage opens runs in its sandbox mode and its answer
/// lands in the demo.
abstract class GuideCardDemo extends ChangeNotifier {
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

  /// The last action's caption, written in whatever language the page is
  /// in when it is drawn; null while nothing has happened.
  String Function(AppLocalizations l10n)? _said;

  /// The caption now. Null is the reserved, empty slot of a card with no
  /// resting caption (D30).
  String? caption(AppLocalizations l10n) => _said?.call(l10n) ?? idle(l10n);

  /// The caption before the first action.
  String? idle(AppLocalizations l10n);

  /// Every caption the card can show, each at its longest. The slot is as
  /// tall as the tallest, so a caption changes words and never the card's
  /// height. Called once per locale.
  List<String> candidates(AppLocalizations l10n);

  Widget buildStage(BuildContext context);

  /// Records what just happened and redraws the card.
  @protected
  void say(String Function(AppLocalizations l10n) caption) {
    _said = caption;
    notifyListeners();
  }

  /// Redraws the card after a change the caption does not name.
  @protected
  void changed() => notifyListeners();

  /// The card's caption slot, for a stage that has to bring the caption
  /// into view — the finding card, whose keyboard would cover the count.
  final GlobalKey captionSlotKey = GlobalKey();
}

/// A title as a caption quotes it: cut at
/// [GuideMetrics.captionTitleMaxChars] so a caption slot can be sized for
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

/// The long weekday date the guide's captions write, at its widest in
/// [dates]' language over a whole year, for a caption slot's candidates.
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

/// The page's "Try it" card: the lead-in as its one entry — so the kit's
/// search finds it — over the card's body.
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
        builder: (context, title, _) => CalendarGuideTryCard(
          slug: topic.slug,
          lead: title,
          demo: demo,
          candidates: candidates,
        ),
      ),
    ],
  );
}

/// The body of a "Try it" card: the lead-in, the stage, the live caption.
///
/// No ink, no chevron, no tap of its own — the card is a place to try
/// things, and only the stage's real controls answer a finger. Stateless
/// over [demo], which outlives it.
class CalendarGuideTryCard extends StatelessWidget {
  const CalendarGuideTryCard({
    super.key,
    required this.slug,
    required this.lead,
    required this.demo,
    required this.candidates,
  });

  final String slug;
  final Widget lead;
  final GuideCardDemo demo;
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
        return Padding(
          padding: const EdgeInsets.only(bottom: GuideMetrics.cardInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: inset, child: lead),
              const SizedBox(height: GuideMetrics.leadToStage),
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
              const SizedBox(height: GuideMetrics.stageToCaption),
              Padding(
                padding: inset,
                child: FormCaptionSlot(
                  key: demo.captionSlotKey,
                  candidates: [
                    for (final text in candidates) FormCaption(text: text),
                  ],
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    identifier: SemanticsIds.calendarGuideTryCaption(slug),
                    child: FormCaption(text: demo.caption(l10n) ?? ''),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A stage's month of dots, drawn as the year tiles draw it at the largest
/// whole multiple of their size the stage's width holds, between
/// [GuideMetrics.stageMatrixMinScale] and [GuideMetrics.stageMatrixMaxScale].
/// What it shows, the caption says, so it is left out of the semantics tree.
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
