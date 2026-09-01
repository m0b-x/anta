import 'package:flutter/material.dart';

/// App-bar icon buttons that scroll horizontally when the toolbar is too
/// narrow to hold them.
///
/// The calendar carries four actions — saved filters, filters, settings, and
/// the overflow menu. On a phone at the narrow end (or with a long localized
/// title) four fixed 48dp buttons squeeze the title down to an ellipsis, and
/// the usual remedy — folding one into the overflow — would bury a button that
/// exists precisely to be one tap away.
///
/// So the buttons get a **width budget** ([reservedForTitle] is what is kept
/// back for the leading button and a readable title) and scroll inside it when
/// they do not fit. On any ordinary screen the budget exceeds the content and
/// this renders exactly as a plain `Row` would, with nothing to scroll.
///
/// Two deliberate details:
///
/// * **Put the overflow menu after this widget, not inside it.** The `⋮` then
///   stays flush against the trailing edge, where every platform puts it, and
///   the scrolling group ends before it.
/// * `reverse` is left off, so the group rests showing its *leading* buttons —
///   the ones a user reaches for. Whatever sits last is what scrolls out of
///   sight, so order these with the least-used action at the end.
///
/// A page whose `NotificationListener<UserScrollNotification>` drives
/// something must ignore horizontal scrollables (the calendar's
/// `fabExtendedFor` already does), or dragging the actions would move it.
class ScrollableAppBarActions extends StatelessWidget {
  final List<Widget> children;

  const ScrollableAppBarActions({super.key, required this.children});

  /// Width held back from the actions for the leading button and enough title
  /// to read. Chosen so four 48dp actions still fit unscrolled at 360dp — the
  /// width this app is designed against — and start scrolling below it.
  static const double reservedForTitle = 152;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - reservedForTitle;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: available < 0 ? 0 : available),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
