import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/report_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_report.dart';
import '../utils/report_labels.dart';

/// The report's Totals card (§4.8): stat tiles as flat cells of one
/// `rowGroup` card, hairlines between them full bleed.
///
/// The grid is decided by value *templates* — "888", "888 of 888", 888.8
/// hours — laid out at the page's text style and scale, never by the values
/// shown (C): a step to a busier period never reflows the grid under the
/// thumb. In two stages (D37): two columns while every template fits a half
/// card; else two columns while "888" and the hours do, a share's "of 24"
/// moving to the front of its detail line — five stacked tiles were a whole
/// first screen in German at 1.0; else one column. In two columns an odd
/// last tile takes the full width.
class ReportTotalsCard extends StatefulWidget {
  const ReportTotalsCard({
    super.key,
    required this.tiles,
    required this.labels,
    this.against,
    this.muted = false,
  });

  /// The tiles in display order.
  final List<ReportTileValue> tiles;

  final ReportLabels labels;

  /// The name of the period the deltas compare against, for the spoken
  /// labels; null when there is none.
  final String? against;

  /// An empty period: every value in `onSurfaceVariant`, never faded (F).
  final bool muted;

  @override
  State<ReportTotalsCard> createState() => _ReportTotalsCardState();
}

/// How the tiles share the card (D37), decided by templates, never values.
enum _TileFit {
  /// Two columns, "21 of 24" in the value line.
  full,

  /// Two columns, the value bare and "of 24" leading the detail line.
  ofInDetail,

  /// One column, the full value.
  single,
}

class _ReportTotalsCardState extends State<ReportTotalsCard> {
  /// The last column decision and everything it was measured from: the
  /// three template layouts run once per width, scale, locale and style,
  /// not on every layout of the card.
  ({
    double width,
    TextScaler scaler,
    String locale,
    TextStyle style,
    TextDirection direction,
  })?
  _columnsKey;
  _TileFit _fit = _TileFit.full;

  List<ReportTileValue> get tiles => widget.tiles;
  ReportLabels get labels => widget.labels;

  /// How the tiles share [cardWidth] at the current locale and scale.
  _TileFit _fitFor(BuildContext context, double cardWidth) {
    final style = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final key = (
      width: cardWidth,
      scaler: scaler,
      locale: labels.l10n.localeName,
      style: style,
      direction: direction,
    );
    if (key == _columnsKey) return _fit;
    _columnsKey = key;
    return _fit = _measureFit(style, scaler, direction, cardWidth);
  }

  _TileFit _measureFit(
    TextStyle style,
    TextScaler scaler,
    TextDirection direction,
    double cardWidth,
  ) {
    double widthOf(String template) {
      final painter = TextPainter(
        text: TextSpan(
          style: style,
          children: _runs(template, figure: _figureStyle, unit: _unitStyle),
        ),
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final count = '${ReportMetrics.tileTemplateCount}';
    final half = (cardWidth - 1) / 2 - 2 * ReportMetrics.tilePaddingHorizontal;
    final bare = [
      widthOf(count),
      widthOf(
        labels.l10n.reportHours(
          labels.hoursFigure(ReportMetrics.tileTemplateHours),
        ),
      ),
    ];
    if (bare.any((width) => width > half)) return _TileFit.single;
    return widthOf(labels.l10n.reportOfTotal(count, count)) <= half
        ? _TileFit.full
        : _TileFit.ofInDetail;
  }

  static const TextStyle _figureStyle = TextStyle(
    fontSize: ReportMetrics.tileValueSize,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.proportionalFigures()],
  );

  static const TextStyle _unitStyle = TextStyle(
    fontSize: FormMetrics.labelSize,
    fontWeight: FontWeight.w400,
  );

  static List<TextSpan> _runs(
    String text, {
    required TextStyle figure,
    required TextStyle unit,
  }) => [
    for (final run in ReportLabels.valueRuns(text))
      TextSpan(text: run.text, style: run.figure ? figure : unit),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.card,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.rowGroup,
      borderRadius: BorderRadius.circular(RowMetrics.groupRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fit = _fitFor(context, constraints.maxWidth);
          final columns = fit == _TileFit.single
              ? 1
              : ReportMetrics.tileColumns;
          final ofInDetail = fit == _TileFit.ofInDetail;
          final hairline = Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.rowDivider,
          );
          final rows = <Widget>[];
          for (var i = 0; i < tiles.length; i += columns) {
            if (rows.isNotEmpty) rows.add(hairline);
            final cells = tiles.skip(i).take(columns).toList();
            rows.add(
              cells.length == 1
                  ? _tile(context, cells.single, ofInDetail: ofInDetail)
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _tile(
                              context,
                              cells[0],
                              ofInDetail: ofInDetail,
                            ),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: colorScheme.rowDivider,
                          ),
                          Expanded(
                            child: _tile(
                              context,
                              cells[1],
                              ofInDetail: ofInDetail,
                            ),
                          ),
                        ],
                      ),
                    ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          );
        },
      ),
    );
  }

  /// One tile; [ofInDetail] is the second stage (D37). The spoken label is
  /// the same in every stage.
  Widget _tile(
    BuildContext context,
    ReportTileValue value, {
    required bool ofInDetail,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final caption = TextStyle(
      fontSize: FormMetrics.captionSize,
      height: FormMetrics.captionLineHeight / FormMetrics.captionSize,
      color: colorScheme.onSurfaceVariant,
    );
    final nothing = ReportLabels.isNothing(value);
    final figureColor = widget.muted || nothing
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;
    final detail = labels.detail(value, ofInDetail: ofInDetail);
    return Semantics(
      container: true,
      identifier: SemanticsIds.reportTile(value.tile.name),
      label: labels.tileSemantics(value, against: widget.against),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ReportMetrics.tilePaddingHorizontal,
            vertical: ReportMetrics.tilePaddingVertical,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labels.tileLabel(value.tile), style: caption),
              const SizedBox(height: RowMetrics.lineGap),
              Text.rich(
                TextSpan(
                  children: _runs(
                    labels.tileValue(value, ofInDetail: ofInDetail),
                    figure: _figureStyle.copyWith(color: figureColor),
                    unit: _unitStyle.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                strutStyle: const StrutStyle(
                  fontSize: ReportMetrics.tileValueSize,
                  height:
                      ReportMetrics.tileValueLineHeight /
                      ReportMetrics.tileValueSize,
                  forceStrutHeight: true,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
              ),
              const SizedBox(height: RowMetrics.lineGap),
              // Always one line, blank or not, so a tile's height never
              // depends on whether it has a delta.
              Text(
                detail.isEmpty ? ' ' : detail,
                style: caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
