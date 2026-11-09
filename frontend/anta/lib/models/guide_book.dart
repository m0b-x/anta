import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'app_guide_content.dart';
import 'guide_content.dart';
import 'notes_guide_content.dart';

/// The guides the "How to use ANTA" hub lists (§3.1 of
/// `docs/guide-hub-roadmap.md`), in its order.
enum GuideBook {
  calendar('calendar', Icons.calendar_month_rounded),
  notes('notes', Icons.edit_note_rounded),
  app('app', Icons.phone_android_rounded);

  /// Frozen: the hub row's id and the book's own ids are built on it (D8).
  final String slug;
  final IconData icon;

  const GuideBook(this.slug, this.icon);

  String title(AppLocalizations l10n) => switch (this) {
    calendar => l10n.calendarGuideTitle,
    notes => l10n.guideBookNotesTitle,
    app => l10n.guideBookAppTitle,
  };

  String caption(AppLocalizations l10n) => switch (this) {
    calendar => l10n.guideBookCalendarCaption,
    notes => l10n.guideBookNotesCaption,
    app => l10n.guideBookAppCaption,
  };

  /// The line above the book's hub cards.
  String intro(AppLocalizations l10n) => switch (this) {
    calendar => l10n.calendarGuideIntro,
    notes => l10n.notesGuideIntro,
    app => l10n.appGuideIntro,
  };

  /// The book's pages in reading order. The calendar's are its own
  /// `CalendarGuideTopic`s with their "Try it" cards and practice lessons
  /// (D7), listed by `CalendarGuidePage`, so it has none here.
  List<GuideTopic> get topics => switch (this) {
    calendar => const [],
    notes => NotesGuideTopic.values,
    app => AppGuideTopic.values,
  };

  /// The pages under "Start here" (D3); the rest of [topics] go under
  /// "How do I…".
  List<GuideTopic> get startHere => switch (this) {
    calendar => const [],
    notes => const [
      NotesGuideTopic.basics,
      NotesGuideTopic.editor,
      NotesGuideTopic.safe,
    ],
    app => const [AppGuideTopic.menu, AppGuideTopic.settings],
  };
}
