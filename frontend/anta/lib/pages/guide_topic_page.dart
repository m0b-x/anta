import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_book.dart';
import '../models/guide_content.dart';
import '../services/settings_service.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/guide_example_row.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// One page of the notes or the app book (`docs/guide-hub-roadmap.md` D4):
/// the calendar guide's page without its "Try it" cards — a heading, the
/// line that says what it is, and its read and example rows.
///
/// Pushed from the book's hub without a destination stamp, as the calendar's
/// pages are: a page is a few seconds' reading, so a relaunch lands on the
/// hub. The bar names the book, the page title is the list's heading.
class GuideTopicPage extends StatefulWidget {
  const GuideTopicPage({super.key, required this.book, required this.topic});

  final GuideBook book;
  final GuideTopic topic;

  @override
  State<GuideTopicPage> createState() => _GuideTopicPageState();
}

class _GuideTopicPageState extends State<GuideTopicPage> {
  /// On until her config lands, so a ledger example renders as a ledger from
  /// the first frame.
  MoneyDisplayConfig _moneyConfig = const MoneyDisplayConfig(enabled: true);
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  @override
  void initState() {
    super.initState();
    _loadPreviewConfig();
  }

  /// Her currency, start balance and colours, read once as the editor reads
  /// them, so an example looks the way her notes do. The ledger stays on
  /// whatever her setting (§4): the money page's examples must render as a
  /// ledger even for someone who has it off. A read that throws leaves the
  /// defaults.
  Future<void> _loadPreviewConfig() async {
    try {
      final settings = await SettingsService.getInstance();
      final money = await settings.getMoneyConfig();
      final palette = await settings.getColorPalette();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _moneyConfig = MoneyDisplayConfig(
          enabled: true,
          startCents: money.startCents,
          currencySymbol: money.symbol,
          currencySuffix: money.suffix,
          errorMessages: l10n == null ? null : MoneyErrorMessages.of(l10n),
        );
        _colorPalette = palette;
      });
    } catch (e, st) {
      debugPrint('[GuideTopicPage] Preview config load failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final topic = widget.topic;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final lead = topic.lead(l10n);

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(title: book.title(l10n)),
      body: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          identifier: SemanticsIds.guideBookTopic(book.slug, topic.slug),
          child: SettingsSectionList(
            query: SettingsQuery.empty,
            header: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GuideMetrics.headingInset,
                  0,
                  GuideMetrics.headingInset,
                  GuideMetrics.headingGap,
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: GuideMetrics.headingMaxTextScale,
                  child: Semantics(
                    header: true,
                    // Under the bar's title, the route's one level-1 heading.
                    headingLevel: 2,
                    child: Text(
                      topic.title(l10n),
                      style: TextStyle(
                        fontSize: FormMetrics.titleFontSize,
                        height: FormMetrics.titleLineHeight,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              if (lead != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GuideMetrics.headingInset,
                  ),
                  child: Text(
                    lead,
                    style: calendarGuideParagraphStyle.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            sections: [
              SettingsSectionData(
                icon: topic.icon,
                title: l10n.calendarGuideHowItWorks,
                entries: [
                  for (final entry in topic.entries(l10n))
                    switch (entry) {
                      GuideReadEntry(:final row) => calendarGuideReadEntry(
                        row,
                        identifier: SemanticsIds.guideBookRow(
                          book.slug,
                          row.slug,
                        ),
                      ),
                      final GuideExampleEntry example => guideExampleEntry(
                        example,
                        book: book,
                        moneyConfig: _moneyConfig,
                        colorPalette: _colorPalette,
                      ),
                    },
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
