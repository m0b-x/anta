import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_templates.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/event_template.dart';
import '../utils/event_template_summary.dart';
import 'event_avatar.dart';
import 'form_rows.dart';

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
class EventTemplatePickerSheet extends StatefulWidget {
  const EventTemplatePickerSheet({super.key});

  static Future<EventTemplateChoice?> show(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<EventTemplateChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: const EventTemplatePickerSheet(),
      ),
    );
  }

  @override
  State<EventTemplatePickerSheet> createState() =>
      _EventTemplatePickerSheetState();
}

class _EventTemplatePickerSheetState extends State<EventTemplatePickerSheet> {
  /// The body's scroll position feeds the header's hairline (a sub-sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the list.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final templates = CalendarTemplates.all;
    // `useSafeArea: true` has proven unreliable against the bottom
    // gesture/nav bar on real devices, so the list pads by the larger of the
    // keyboard inset and the system inset — same fix as `CategoryPickerSheet`.
    final bottomClearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.templatePickClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.addFromTemplate,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // A row pops on tap; there is nothing to confirm.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + bottomClearance,
            ),
            child: FormRowGroup(
              trailingGap: false,
              children: [
                for (final template in templates)
                  FormPickerRow(
                    leading: EventAvatar(
                      icon: CalendarTemplates.iconFor(template),
                      color: CalendarTemplates.colorFor(template),
                    ),
                    label: template.name,
                    caption: templateSummary(template, l10n, l10n.localeName),
                    showChevron: false,
                    identifier: SemanticsIds.templatePickRow(template.id),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(EventTemplatePicked(template)),
                  ),
                // The two neutral rows sit below the templates, the alarm
                // first: it is the row the sheet exists for when there are
                // no templates at all, which is why the FAB long press
                // always opens it.
                FormActionRow(
                  glyph: Icons.alarm_add_rounded,
                  label: l10n.quickAlarmRow,
                  identifier: SemanticsIds.quickAlarmRow,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(const EventTemplateQuickAlarm()),
                ),
                FormActionRow(
                  glyph: Icons.edit_calendar_rounded,
                  label: l10n.templateBlankEvent,
                  identifier: SemanticsIds.templatePickBlank,
                  onTap: () =>
                      Navigator.of(context).pop(const EventTemplateBlank()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
