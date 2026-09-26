import 'package:flutter/material.dart';

import '../models/calendar_appearance.dart';
import 'agenda_year_grid.dart';

/// Years as pages: swipe between them, or let the owner animate the
/// controller from its chevrons and its jump picker. The page count is the
/// owner's year bounds, so a swipe never lands on a year with nothing in it.
///
/// [tilesFor] runs inside the item builder, for whichever page is being drawn
/// — including the one sliding in under a finger — so the owner caches its
/// tiles per year and prewarms the neighbours after each settle; a fling
/// past the warm years resolves in the builder, which is a few milliseconds
/// against a blank page.
class AgendaYearPager extends StatelessWidget {
  final PageController controller;
  final int firstYear;
  final int lastYear;
  final List<AgendaYearTile> Function(int year) tilesFor;
  final Color color;
  final CalendarAppearance appearance;
  final DateTime today;
  final ValueChanged<DateTime> onOpenMonth;
  final ValueChanged<int> onYearChanged;
  final EdgeInsets padding;
  final DateTime? highlightMonth;
  final int highlightToken;

  const AgendaYearPager({
    super.key,
    required this.controller,
    required this.firstYear,
    required this.lastYear,
    required this.tilesFor,
    required this.color,
    required this.appearance,
    required this.today,
    required this.onOpenMonth,
    required this.onYearChanged,
    required this.padding,
    this.highlightMonth,
    this.highlightToken = 0,
  });

  static int indexOf(int year, int firstYear) => year - firstYear;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      itemCount: lastYear - firstYear + 1,
      onPageChanged: (index) => onYearChanged(firstYear + index),
      itemBuilder: (context, index) {
        final year = firstYear + index;
        final highlight = highlightMonth;
        return AgendaYearGrid(
          tiles: tilesFor(year),
          color: color,
          appearance: appearance,
          today: today,
          onOpenMonth: onOpenMonth,
          padding: padding,
          highlightMonth: highlight != null && highlight.year == year
              ? highlight
              : null,
          highlightToken: highlightToken,
        );
      },
    );
  }
}
