import 'package:flutter/material.dart';

import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/share_settings.dart';
import 'form_menu_item.dart';
import 'settings_section_list.dart';

/// The Sharing page's two sections about this phone alone — how shared
/// things look (share surfaces §6.7) and what rings for them (§6.8) — drawn
/// by the page and by the sync guide's stages (`docs/guide-hub-roadmap.md`
/// D43) from one place, so the guide can never drift from the screen.
///
/// Pure: they read nothing and write nothing; the caller holds the values
/// and answers the callbacks. Their `identifier` gives a row's id by name —
/// `events`, `events-<look>`, `notes`, `notes-<look>`, `mark-mine`,
/// `alerts`, `alerts-<choice>` — for a stage, whose ids are its card's;
/// null keeps the page's own.
typedef ShareRowIdentifier = String Function(String row);

/// "How shared things look": the events' three looks, the notes' two, and
/// the switch for the sign on what this phone shares. [inert] holds every
/// row still, undimmed — the page's rows until its first read, when a tap
/// would write from the shipped value rather than from what is stored.
SettingsSectionData shareLookSection(
  AppLocalizations l10n, {
  required ShareLook look,
  required ValueChanged<ShareEventLook> onEventLook,
  required ValueChanged<ShareNoteLook> onNoteLook,
  required ValueChanged<bool> onMarkMine,
  bool inert = false,
  ShareRowIdentifier? identifier,
}) {
  Widget untilLoaded(Widget row) => IgnorePointer(ignoring: inert, child: row);
  return SettingsSectionData(
    icon: Icons.visibility_rounded,
    title: l10n.shareLookSection,
    entries: [
      SettingsEntry(
        title: l10n.shareEventLook,
        identifier:
            identifier?.call('events') ?? SemanticsIds.sharingLookEvents,
        builder: (context, title, description) => untilLoaded(
          settingsChoiceRow<ShareEventLook>(
            title: title,
            description: description,
            value: look.eventLook,
            labels: {
              ShareEventLook.outlined: l10n.shareLookOutlined,
              ShareEventLook.avatar: l10n.shareLookAvatar,
              ShareEventLook.plain: l10n.shareLookPlain,
            },
            identifiers: {
              for (final value in ShareEventLook.values)
                value:
                    identifier?.call('events-${value.name}') ??
                    SemanticsIds.sharingLookEventsChoice(value.name),
            },
            onChanged: onEventLook,
          ),
        ),
      ),
      SettingsEntry(
        title: l10n.shareNoteLook,
        identifier: identifier?.call('notes') ?? SemanticsIds.sharingLookNotes,
        builder: (context, title, description) => untilLoaded(
          settingsChoiceRow<ShareNoteLook>(
            title: title,
            description: description,
            value: look.noteLook,
            labels: {
              ShareNoteLook.avatar: l10n.shareLookAvatar,
              ShareNoteLook.plain: l10n.shareLookPlain,
            },
            identifiers: {
              for (final value in ShareNoteLook.values)
                value:
                    identifier?.call('notes-${value.name}') ??
                    SemanticsIds.sharingLookNotesChoice(value.name),
            },
            onChanged: onNoteLook,
          ),
        ),
      ),
      SettingsEntry(
        title: l10n.shareMarkMine,
        description: l10n.shareMarkMineDesc,
        identifier:
            identifier?.call('mark-mine') ?? SemanticsIds.sharingMarkMine,
        builder: (context, title, description) => untilLoaded(
          SwitchListTile(
            value: look.markMine,
            title: title,
            subtitle: description,
            onChanged: onMarkMine,
          ),
        ),
      ),
    ],
  );
}

/// "Alerts on shared events": one entry that opens a menu rather than a
/// page, so it has no chevron (decision v). [alerts] null — the page before
/// its first read — leaves its value blank and its tap inert. [onPick] is
/// handed the row's own context, so the menu hangs from the row's box.
SettingsSectionData shareAlertsSection(
  AppLocalizations l10n, {
  required ShareAlerts? alerts,
  required void Function(BuildContext anchor, ShareAlerts current) onPick,
  ShareRowIdentifier? identifier,
}) {
  return SettingsSectionData(
    icon: Icons.notifications_rounded,
    title: l10n.shareAlertsSection,
    entries: [
      SettingsEntry(
        title: l10n.shareAlerts,
        description: alerts == null ? '' : shareAlertsLabel(l10n, alerts),
        identifier: identifier?.call('alerts') ?? SemanticsIds.sharingAlerts,
        // A `Builder` so the menu hangs from the row's own box.
        builder: (context, title, description) => Builder(
          builder: (rowContext) => ListTile(
            leading: Icon(
              Icons.notifications_rounded,
              color: Theme.of(rowContext).colorScheme.primary,
            ),
            title: title,
            subtitle: description,
            onTap: alerts == null ? null : () => onPick(rowContext, alerts),
          ),
        ),
      ),
    ],
  );
}

/// The menu [shareAlertsSection]'s row opens at [anchor]: the three choices,
/// each with the caption that says what it arms, [current] ticked. Null when
/// it is dismissed.
Future<ShareAlerts?> showShareAlertsMenu(
  BuildContext anchor,
  AppLocalizations l10n,
  ShareAlerts current, {
  ShareRowIdentifier? identifier,
}) {
  return showFormMenu<ShareAlerts>(
    anchor,
    items: [
      for (final value in ShareAlerts.values)
        FormMenuItem(
          value: value,
          label: shareAlertsLabel(l10n, value),
          caption: switch (value) {
            ShareAlerts.off => l10n.shareAlertsOffDesc,
            ShareAlerts.own => l10n.shareAlertsOwnDesc,
            ShareAlerts.category => l10n.shareAlertsCategoryDesc,
          },
          identifier:
              identifier?.call('alerts-${value.name}') ??
              switch (value) {
                ShareAlerts.off => SemanticsIds.sharingAlertsOff,
                ShareAlerts.own => SemanticsIds.sharingAlertsOwn,
                ShareAlerts.category => SemanticsIds.sharingAlertsCategory,
              },
        ),
    ],
    selected: current,
    // Floor and cap at once: a caption of two lines reads as one choice at
    // this width, and the menu never narrows with the language.
    menuWidth: FormMetrics.menuMaxWidth,
  );
}

/// The app's word for [value], the row's value and the menu's label alike.
String shareAlertsLabel(AppLocalizations l10n, ShareAlerts value) =>
    switch (value) {
      ShareAlerts.off => l10n.shareAlertsOff,
      ShareAlerts.own => l10n.shareAlertsOwn,
      ShareAlerts.category => l10n.shareAlertsCategory,
    };
