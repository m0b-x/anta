import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_guide_content.dart';
import 'settings_section_list.dart';

/// The guide's running text: the hub's intro, a page's lead and every read
/// row's paragraph.
const TextStyle calendarGuideParagraphStyle = TextStyle(
  fontSize: GuideMetrics.paragraphFontSize,
  fontWeight: FontWeight.w400,
  height: GuideMetrics.paragraphLineHeight,
);

/// [row] as a kit entry, searchable by its title and paragraph, drawn the same
/// on its page and among the hub's search results.
///
/// [identifier] is the calendar guide's row id unless given: the notes and
/// app books draw their rows through here under ids of their own
/// (`SemanticsIds.guideBookRow`) rather than through a copy of the row.
SettingsEntry calendarGuideReadEntry(
  CalendarGuideRow row, {
  String? identifier,
}) {
  return SettingsEntry(
    title: row.title,
    description: row.body,
    identifier: identifier ?? SemanticsIds.calendarGuideRow(row.slug),
    descriptionStyle: calendarGuideParagraphStyle,
    builder: (context, title, description) => CalendarGuideReadRow(
      icon: row.icon,
      title: title,
      description: description,
    ),
  );
}

/// A guide row is read, never pressed: no ink, no tap, no chevron. Its title
/// and paragraph merge so TalkBack reads the row as one stop.
class CalendarGuideReadRow extends StatelessWidget {
  const CalendarGuideReadRow({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Widget title;
  final Widget? description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Padding(
        padding: GuideMetrics.readRowPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, color: colorScheme.primary)),
            const SizedBox(width: GuideMetrics.readRowGlyphGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (description != null) ...[
                    const SizedBox(height: 4),
                    description!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
