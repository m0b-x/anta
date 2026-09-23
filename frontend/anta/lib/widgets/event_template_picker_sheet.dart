import 'package:flutter/material.dart';

import '../constants/calendar_templates.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/event_template.dart';
import '../utils/event_template_summary.dart';
import 'automation_id.dart';

/// What the template picker returned.
sealed class EventTemplateChoice {
  const EventTemplateChoice();
}

/// The user picked a template to stamp out.
class EventTemplatePicked extends EventTemplateChoice {
  final EventTemplate template;

  const EventTemplatePicked(this.template);
}

/// The user chose to skip templates and open the normal empty editor. A
/// distinct result rather than `null`, because dismissing the sheet must not
/// silently open a second one.
class EventTemplateBlank extends EventTemplateChoice {
  const EventTemplateBlank();
}

/// The user chose the quick-alarm sheet (parent roadmap §5.8): an alarm on
/// the pressed day with the fewest taps, rather than a template or the form.
class EventTemplateQuickAlarm extends EventTemplateChoice {
  const EventTemplateQuickAlarm();
}

/// Bottom-sheet selector for an event template, used by the calendar's
/// long-press quick-add. Returns the choice, or `null` if dismissed.
///
/// Reads [CalendarTemplates] rather than the service: the facade is already
/// populated at startup, so opening this sheet costs no query.
class EventTemplatePickerSheet extends StatelessWidget {
  const EventTemplatePickerSheet({super.key});

  static Future<EventTemplateChoice?> show(BuildContext context) {
    return showModalBottomSheet<EventTemplateChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.7,
        child: EventTemplatePickerSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final templates = CalendarTemplates.all;
    // `useSafeArea: true` has proven unreliable against the bottom
    // gesture/nav bar on real devices, so the list pads by the larger of the
    // keyboard inset and the system inset — same fix as `CategoryPickerSheet`.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            l10n.addFromTemplate,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 4 + bottomClearance),
            // The two neutral rows sit below the templates, the alarm first:
            // it is the row the sheet exists for when there are no templates
            // at all, which is why the FAB long press always opens it.
            itemCount: templates.length + 2,
            itemBuilder: (context, index) {
              if (index == templates.length) {
                return AutomationId(
                  identifier: SemanticsIds.quickAlarmRow,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.alarm_add_rounded),
                    ),
                    title: Text(l10n.quickAlarmRow),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const EventTemplateQuickAlarm()),
                  ),
                );
              }
              if (index == templates.length + 1) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    child: const Icon(Icons.edit_calendar_rounded),
                  ),
                  title: Text(l10n.templateBlankEvent),
                  onTap: () =>
                      Navigator.of(context).pop(const EventTemplateBlank()),
                );
              }
              final template = templates[index];
              final color = CalendarTemplates.colorFor(template);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.18),
                  foregroundColor: color,
                  child: Icon(CalendarTemplates.iconFor(template)),
                ),
                title: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  templateSummary(template, l10n, l10n.localeName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    Navigator.of(context).pop(EventTemplatePicked(template)),
              );
            },
          ),
        ),
      ],
    );
  }
}
