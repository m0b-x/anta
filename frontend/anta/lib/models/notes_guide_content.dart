import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'calendar_guide_content.dart';
import 'guide_content.dart';
import 'notes_guide_tries.dart';

/// The "Notes and the editor" book's pages, in reading order (§3.2 of
/// `docs/guide-hub-roadmap.md`); the hub picks its "Start here" from them.
///
/// Every label a row names is the app's own string passed through a
/// placeholder, as the calendar guide does, so the book cannot drift from
/// the screens it describes in any language.
enum NotesGuideTopic implements GuideTopic {
  basics('basics', Icons.folder_rounded),
  editor('editor', Icons.edit_rounded),
  safe('safe', Icons.shield_rounded),
  markdown('markdown', Icons.text_fields_rounded),
  lists('lists', Icons.format_list_bulleted_rounded),
  own('own', Icons.auto_awesome_rounded),
  money('money', Icons.payments_rounded),
  bar('bar', Icons.dashboard_customize_rounded),
  autocomplete('autocomplete', Icons.playlist_add_check_rounded),
  counters('counters', Icons.pin_rounded),
  settings('settings', Icons.tune_rounded);

  @override
  final String slug;
  @override
  final IconData icon;

  const NotesGuideTopic(this.slug, this.icon);

  @override
  String title(AppLocalizations l10n) => switch (this) {
    basics => l10n.notesGuidePageBasics,
    editor => l10n.notesGuidePageEditor,
    safe => l10n.notesGuidePageSafe,
    markdown => l10n.notesGuidePageMarkdown,
    lists => l10n.notesGuidePageLists,
    own => l10n.notesGuidePageOwn,
    money => l10n.notesGuidePageMoney,
    bar => l10n.notesGuidePageBar,
    autocomplete => l10n.notesGuidePageAutocomplete,
    counters => l10n.notesGuidePageCounters,
    settings => l10n.notesGuidePageSettings,
  };

  @override
  String caption(AppLocalizations l10n) => switch (this) {
    basics => l10n.notesGuidePageBasicsCaption,
    editor => l10n.notesGuidePageEditorCaption,
    safe => l10n.notesGuidePageSafeCaption,
    markdown => l10n.notesGuidePageMarkdownCaption,
    lists => l10n.notesGuidePageListsCaption,
    own => l10n.notesGuidePageOwnCaption,
    money => l10n.notesGuidePageMoneyCaption,
    bar => l10n.notesGuidePageBarCaption,
    autocomplete => l10n.notesGuidePageAutocompleteCaption,
    counters => l10n.notesGuidePageCountersCaption,
    settings => l10n.notesGuidePageSettingsCaption,
  };

  @override
  String? lead(AppLocalizations l10n) => switch (this) {
    basics => l10n.notesGuideBasicsLead,
    editor => l10n.notesGuideEditorLead,
    safe => l10n.notesGuideSafeLead,
    markdown => l10n.notesGuideMarkdownLead,
    lists => l10n.notesGuideListsLead,
    own => l10n.notesGuideOwnLead,
    money => l10n.notesGuideMoneyLead(
      l10n.moneyLedgerEnabledLabel,
      l10n.settingsRowEditor,
      l10n.moneySection,
    ),
    bar => l10n.notesGuideBarLead(l10n.settingsRowEditor),
    autocomplete => l10n.notesGuideAutocompleteLead,
    counters => l10n.notesGuideCountersLead,
    settings => l10n.notesGuideSettingsLead(l10n.settingsHubTitle),
  };

  /// Only a page where a mark is read gets a card (D17): the editor's chrome
  /// a stage cannot show stays in words.
  @override
  List<GuideEditorCard> get editorCards => switch (this) {
    markdown => [notesGuideMarkdownTry],
    lists => [notesGuideListsTry],
    own => [notesGuideOwnTry],
    money => [notesGuideMoneyTry],
    _ => const [],
  };

  /// A source or body that shows a brace takes it through `open` / `close`:
  /// ICU reads a bare brace as a placeholder, so the ARBs cannot hold one.
  @override
  List<GuideEntry> entries(AppLocalizations l10n) => switch (this) {
    basics => [
      GuideReadEntry(
        CalendarGuideRow(
          'basics-create',
          Icons.note_add_rounded,
          l10n.notesGuideBasicsCreateTitle,
          l10n.notesGuideBasicsCreateBody(l10n.newNote),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-folders',
          Icons.create_new_folder_rounded,
          l10n.notesGuideBasicsFoldersTitle,
          l10n.notesGuideBasicsFoldersBody(l10n.newFolder),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-saved',
          Icons.save_rounded,
          l10n.notesGuideBasicsSavedTitle,
          l10n.notesGuideBasicsSavedBody(l10n.saveStatusSaved),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-reopen',
          Icons.history_rounded,
          l10n.notesGuideBasicsReopenTitle,
          l10n.notesGuideBasicsReopenBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-menu',
          Icons.more_vert_rounded,
          l10n.notesGuideBasicsMenuTitle,
          l10n.notesGuideBasicsMenuBody(
            l10n.renameFolder,
            l10n.moveToFolder,
            l10n.sortBy,
            l10n.shareFolder,
            l10n.importNoteOrFolder,
            l10n.select,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-hold',
          Icons.touch_app_rounded,
          l10n.notesGuideBasicsHoldTitle,
          l10n.notesGuideBasicsHoldBody(
            l10n.moveSelected,
            l10n.labelSelected,
            l10n.shareSelected,
            l10n.deleteSelected,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-sort',
          Icons.sort_rounded,
          l10n.notesGuideBasicsSortTitle,
          l10n.notesGuideBasicsSortBody(l10n.sortNotes, l10n.sortByCustom),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-labels',
          Icons.label_rounded,
          l10n.notesGuideBasicsLabelsTitle,
          l10n.notesGuideBasicsLabelsBody(l10n.labelAction, l10n.sortByLabel),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-delete',
          Icons.delete_outline_rounded,
          l10n.notesGuideBasicsDeleteTitle,
          l10n.notesGuideBasicsDeleteBody(l10n.guideBookAppTitle),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-search',
          Icons.search_rounded,
          l10n.notesGuideBasicsSearchTitle,
          l10n.notesGuideBasicsSearchBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'basics-all',
          Icons.notes_rounded,
          l10n.notesGuideBasicsAllTitle,
          l10n.notesGuideBasicsAllBody(l10n.allNotes, l10n.recent),
        ),
      ),
    ],
    editor => [
      GuideReadEntry(
        CalendarGuideRow(
          'editor-live',
          Icons.visibility_rounded,
          l10n.notesGuideEditorLiveTitle,
          l10n.notesGuideEditorLiveBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-bar',
          Icons.keyboard_rounded,
          l10n.notesGuideEditorBarTitle,
          l10n.notesGuideEditorBarBody(
            l10n.headers,
            l10n.bulletList,
            l10n.checkbox,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-undo',
          Icons.undo_rounded,
          l10n.notesGuideEditorUndoTitle,
          l10n.notesGuideEditorUndoBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-title',
          Icons.title_rounded,
          l10n.notesGuideEditorTitleTitle,
          l10n.notesGuideEditorTitleBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-menu',
          Icons.more_vert_rounded,
          l10n.notesGuideEditorMenuTitle,
          l10n.notesGuideEditorMenuBody(
            l10n.shareNote,
            l10n.moveToFolder,
            l10n.labelAction,
            l10n.openFolder,
            l10n.deleteNote,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-find',
          Icons.find_in_page_rounded,
          l10n.notesGuideEditorFindTitle,
          l10n.notesGuideEditorFindBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-font',
          Icons.text_increase_rounded,
          l10n.notesGuideEditorFontTitle,
          l10n.notesGuideEditorFontBody(
            l10n.decreaseFontSize,
            l10n.increaseFontSize,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'editor-tap',
          Icons.check_box_rounded,
          l10n.notesGuideEditorTapTitle,
          l10n.notesGuideEditorTapBody,
        ),
      ),
    ],
    safe => [
      GuideReadEntry(
        CalendarGuideRow(
          'safe-autosave',
          Icons.save_rounded,
          l10n.notesGuideSafeAutosaveTitle,
          l10n.notesGuideSafeAutosaveBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'safe-status',
          Icons.info_outline_rounded,
          l10n.notesGuideSafeStatusTitle,
          l10n.notesGuideSafeStatusBody(
            l10n.saveStatusSaved,
            l10n.saveStatusSaving,
            l10n.saveStatusUnsaved,
            l10n.saveStatusError,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'safe-event',
          Icons.event_rounded,
          l10n.notesGuideSafeEventTitle,
          l10n.notesGuideSafeEventBody(l10n.eventLinkedNote),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'safe-backup',
          Icons.backup_rounded,
          l10n.notesGuideSafeBackupTitle,
          l10n.notesGuideSafeBackupBody(l10n.guideBookAppTitle),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'safe-share',
          Icons.ios_share_rounded,
          l10n.notesGuideSafeShareTitle,
          l10n.notesGuideSafeShareBody(l10n.shareNote),
        ),
      ),
    ],
    markdown => [
      GuideExampleEntry(
        slug: 'heading',
        source: l10n.notesGuideExHeadingSource,
        caption: l10n.notesGuideExHeadingCaption,
      ),
      GuideExampleEntry(
        slug: 'emphasis',
        source: l10n.notesGuideExEmphasisSource,
        caption: l10n.notesGuideExEmphasisCaption,
      ),
      GuideExampleEntry(
        slug: 'list',
        source: l10n.notesGuideExListSource,
        caption: l10n.notesGuideExListCaption,
      ),
      GuideExampleEntry(
        slug: 'numbered',
        source: l10n.notesGuideExNumberedSource,
        caption: l10n.notesGuideExNumberedCaption,
      ),
      GuideExampleEntry(
        slug: 'task',
        source: l10n.notesGuideExTaskSource,
        caption: l10n.notesGuideExTaskCaption(l10n.checkbox),
      ),
      GuideExampleEntry(
        slug: 'quote',
        source: l10n.notesGuideExQuoteSource,
        caption: l10n.notesGuideExQuoteCaption,
      ),
      GuideExampleEntry(
        slug: 'link',
        source: l10n.notesGuideExLinkSource,
        caption: l10n.notesGuideExLinkCaption,
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'markdown-table',
          Icons.table_chart_rounded,
          l10n.notesGuideMarkdownTableTitle,
          l10n.notesGuideMarkdownTableBody(l10n.shortcutTable),
        ),
      ),
    ],
    lists => [
      GuideExampleEntry(
        slug: 'nested',
        source: l10n.notesGuideExNestedSource,
        caption: l10n.notesGuideExNestedCaption,
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'lists-enter',
          Icons.keyboard_return_rounded,
          l10n.notesGuideListsEnterTitle,
          l10n.notesGuideListsEnterBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'lists-nest',
          Icons.format_indent_increase_rounded,
          l10n.notesGuideListsNestTitle,
          l10n.notesGuideListsNestBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'lists-cap',
          Icons.vertical_align_center_rounded,
          l10n.notesGuideListsCapTitle,
          l10n.notesGuideListsCapBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'lists-task',
          Icons.check_box_rounded,
          l10n.notesGuideListsTaskTitle,
          l10n.notesGuideListsTaskBody,
        ),
      ),
    ],
    own => [
      GuideExampleEntry(
        slug: 'tag',
        source: l10n.notesGuideExTagSource,
        caption: l10n.notesGuideExTagCaption,
      ),
      GuideExampleEntry(
        slug: 'callout',
        source: l10n.notesGuideExCalloutSource,
        caption: l10n.notesGuideExCalloutCaption,
      ),
      GuideExampleEntry(
        slug: 'colour',
        source: l10n.notesGuideExColourSource('{', '}'),
        caption: l10n.notesGuideExColourCaption(l10n.markdownColorsTitle),
      ),
      GuideExampleEntry(
        slug: 'ghost',
        source: l10n.notesGuideExGhostSource('{', '}'),
        caption: l10n.notesGuideExGhostCaption(l10n.shortcutGhostText),
      ),
      GuideExampleEntry(
        slug: 'wiki',
        source: l10n.notesGuideExWikiSource,
        caption: l10n.notesGuideExWikiCaption,
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'own-date',
          Icons.today_rounded,
          l10n.notesGuideOwnDateTitle,
          l10n.notesGuideOwnDateBody(l10n.currentDate),
        ),
      ),
    ],
    money => [
      GuideExampleEntry(
        slug: 'money-basic',
        source: l10n.notesGuideExMoneyBasicSource,
        caption: l10n.notesGuideExMoneyBasicCaption,
      ),
      GuideExampleEntry(
        slug: 'money-months',
        source: l10n.notesGuideExMoneyMonthsSource,
        caption: l10n.notesGuideExMoneyMonthsCaption,
      ),
      GuideExampleEntry(
        slug: 'money-target',
        source: l10n.notesGuideExMoneyTargetSource,
        caption: l10n.notesGuideExMoneyTargetCaption,
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'money-tap',
          Icons.touch_app_rounded,
          l10n.notesGuideMoneyTapTitle,
          l10n.notesGuideMoneyTapBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'money-more',
          Icons.calculate_rounded,
          l10n.notesGuideMoneyMoreTitle,
          l10n.notesGuideMoneyMoreBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'money-settings',
          Icons.settings_rounded,
          l10n.notesGuideMoneySettingsTitle,
          l10n.notesGuideMoneySettingsBody(
            l10n.settingsRowEditor,
            l10n.moneySection,
            l10n.moneyLedgerEnabledLabel,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'money-calendar',
          Icons.calendar_month_rounded,
          l10n.notesGuideMoneyCalendarTitle,
          l10n.notesGuideMoneyCalendarBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'money-buttons',
          Icons.attach_money_rounded,
          l10n.notesGuideMoneyButtonsTitle,
          l10n.notesGuideMoneyButtonsBody(
            l10n.shortcutMoneyAdd,
            l10n.shortcutMoneySubtract,
            l10n.shortcutMoneyStart,
            l10n.shortcutMoneyTotal,
            l10n.shortcutMoneyChange,
            l10n.shortcutMoneyTarget,
          ),
        ),
      ),
    ],
    bar => [
      GuideReadEntry(
        CalendarGuideRow(
          'bar-shortcuts',
          Icons.flash_on_rounded,
          l10n.notesGuideBarShortcutsTitle,
          l10n.notesGuideBarShortcutsBody(l10n.shortcuts),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'bar-own',
          Icons.add_circle_outline_rounded,
          l10n.notesGuideBarOwnTitle,
          l10n.notesGuideBarOwnBody(l10n.shortcuts),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'bar-utility',
          Icons.build_rounded,
          l10n.notesGuideBarUtilityTitle,
          l10n.notesGuideBarUtilityBody(l10n.utilityButtons),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'bar-reorder',
          Icons.swap_horiz_rounded,
          l10n.notesGuideBarReorderTitle,
          l10n.notesGuideBarReorderBody(l10n.reorderShortcuts),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'bar-profiles',
          Icons.view_carousel_rounded,
          l10n.notesGuideBarProfilesTitle,
          l10n.notesGuideBarProfilesBody(
            l10n.manageBarProfiles,
            l10n.switchBar,
            l10n.perNoteBarAssignment,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'bar-layout',
          Icons.view_agenda_rounded,
          l10n.notesGuideBarLayoutTitle,
          l10n.notesGuideBarLayoutBody(l10n.splitToolbar, l10n.pinUndoRedo),
        ),
      ),
    ],
    autocomplete => [
      GuideReadEntry(
        CalendarGuideRow(
          'auto-lists',
          Icons.list_alt_rounded,
          l10n.notesGuideAutoListsTitle,
          l10n.notesGuideAutoListsBody(
            l10n.settingsRowEditor,
            l10n.vocabularySection,
            l10n.manageVocabularies,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'auto-trigger',
          Icons.alternate_email_rounded,
          l10n.notesGuideAutoTriggerTitle,
          l10n.notesGuideAutoTriggerBody(l10n.vocabularyTriggerLabel),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'auto-scope',
          Icons.filter_list_rounded,
          l10n.notesGuideAutoScopeTitle,
          l10n.notesGuideAutoScopeBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'auto-ghost',
          Icons.touch_app_rounded,
          l10n.notesGuideAutoGhostTitle,
          l10n.notesGuideAutoGhostBody('{', '}'),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'auto-ignore',
          Icons.do_not_disturb_alt_rounded,
          l10n.notesGuideAutoIgnoreTitle,
          l10n.notesGuideAutoIgnoreBody(l10n.vocabularySuggestionsLabel),
        ),
      ),
    ],
    counters => [
      GuideReadEntry(
        CalendarGuideRow(
          'counters-make',
          Icons.add_rounded,
          l10n.notesGuideCountersMakeTitle,
          l10n.notesGuideCountersMakeBody(
            l10n.counterSettings,
            l10n.addCounter,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'counters-note',
          Icons.edit_note_rounded,
          l10n.notesGuideCountersNoteTitle,
          l10n.notesGuideCountersNoteBody(l10n.counterInsertTooltip),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'counters-scope',
          Icons.note_rounded,
          l10n.notesGuideCountersScopeTitle,
          l10n.notesGuideCountersScopeBody(
            l10n.counterScope,
            l10n.counterScopeGlobalDesc,
            l10n.counterScopePerNoteDesc,
          ),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'counters-pin',
          Icons.push_pin_rounded,
          l10n.notesGuideCountersPinTitle,
          l10n.notesGuideCountersPinBody(l10n.pinCounter),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'counters-shortcut',
          Icons.flash_on_rounded,
          l10n.notesGuideCountersShortcutTitle,
          l10n.notesGuideCountersShortcutBody(
            l10n.shortcuts,
            l10n.counterBindingsTitle,
          ),
        ),
      ),
    ],
    settings => [
      GuideReadEntry(
        CalendarGuideRow(
          'settings-general',
          Icons.settings_rounded,
          l10n.notesGuideSettingsGeneralTitle(l10n.settingsRowGeneral),
          l10n.notesGuideSettingsGeneralBody(l10n.settingsRowGeneralDesc),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'settings-editor',
          Icons.edit_rounded,
          l10n.notesGuideSettingsEditorTitle(l10n.settingsRowEditor),
          l10n.notesGuideSettingsEditorBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'settings-counters',
          Icons.pin_rounded,
          l10n.notesGuideSettingsCountersTitle(l10n.counterSettings),
          l10n.notesGuideSettingsCountersBody,
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'settings-look',
          Icons.dark_mode_rounded,
          l10n.notesGuideSettingsLookTitle(
            l10n.settingsRowTheme,
            l10n.languageSettings,
          ),
          l10n.notesGuideSettingsLookBody(l10n.themeSettingsDesc),
        ),
      ),
      GuideReadEntry(
        CalendarGuideRow(
          'settings-pernote',
          Icons.note_rounded,
          l10n.notesGuideSettingsPerNoteTitle,
          l10n.notesGuideSettingsPerNoteBody,
        ),
      ),
    ],
  };
}
