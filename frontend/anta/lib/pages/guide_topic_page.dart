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
import '../widgets/calendar_guide_try_card.dart';
import '../widgets/guide_example_row.dart';
import '../widgets/guide_try_editor.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// One page of the notes or the app book (`docs/guide-hub-roadmap.md` D4):
/// a heading, the line that says what it is, the page's "Try it" editors
/// where it has any (D17), and its read and example rows.
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

  /// The page's "Try it" editors by card slug, owned here as the calendar's
  /// topic page owns its demos: the kit's list disposes a card scrolled out
  /// of view, and what she typed must survive that.
  late Map<String, GuideEditorDemo> _demos = _demosFor(widget);

  /// Each card's coach slot candidates by card slug, built once per locale.
  Map<String, List<String>> _candidates = const {};
  Locale? _candidatesLocale;

  Map<String, GuideEditorDemo> _demosFor(GuideTopicPage page) => {
    for (final card in page.topic.editorCards)
      card.spec.slug: GuideEditorDemo(book: page.book.slug, card: card)
        ..adoptRenderConfig(money: _moneyConfig, palette: _colorPalette),
  };

  @override
  void initState() {
    super.initState();
    _loadPreviewConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prepareDemos();
  }

  /// A page handed another topic in place gets that topic's cards. The old
  /// demos go after the frame: until then the old stages still hold their
  /// controllers.
  @override
  void didUpdateWidget(GuideTopicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topic == widget.topic && oldWidget.book == widget.book) {
      return;
    }
    final old = _demos.values.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final demo in old) {
        demo.dispose();
      }
    });
    _demos = _demosFor(widget);
    _candidatesLocale = null;
    _prepareDemos();
  }

  /// Seeds each demo before its first frame, so a stage opens on its seed —
  /// once: a later change of language keeps her text — and sizes the coach
  /// slots for the current language.
  void _prepareDemos() {
    final l10n = AppLocalizations.of(context)!;
    for (final demo in _demos.values) {
      demo.seed(l10n);
    }
    final locale = Localizations.localeOf(context);
    if (locale == _candidatesLocale) return;
    _candidatesLocale = locale;
    // A ledger's error chips speak the page's language: a change of language
    // re-reads them, keeping her currency and start, and the stages take
    // them as a repaint, never a remount (D20).
    final money = _moneyConfig;
    _moneyConfig = MoneyDisplayConfig(
      enabled: money.enabled,
      startCents: money.startCents,
      currencySymbol: money.currencySymbol,
      currencySuffix: money.currencySuffix,
      errorMessages: MoneyErrorMessages.of(l10n),
    );
    for (final demo in _demos.values) {
      demo.adoptRenderConfig(money: _moneyConfig, palette: _colorPalette);
    }
    _candidates = {
      for (final MapEntry(key: slug, value: demo) in _demos.entries)
        slug: demo.candidates(l10n),
    };
  }

  @override
  void dispose() {
    for (final demo in _demos.values) {
      demo.dispose();
    }
    super.dispose();
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
      for (final demo in _demos.values) {
        demo.adoptRenderConfig(money: _moneyConfig, palette: _colorPalette);
      }
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
              for (final card in topic.editorCards)
                calendarGuideTrySection(
                  l10n: l10n,
                  card: card.spec,
                  demo: _demos[card.spec.slug]!,
                  candidates: _candidates[card.spec.slug]!,
                  identifier: SemanticsIds.guideBookTry(
                    book.slug,
                    card.spec.slug,
                  ),
                  captionIdentifier: SemanticsIds.guideBookTryCaption(
                    book.slug,
                    card.spec.slug,
                  ),
                ),
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
