import '../constants/calendar_categories.dart';
import '../constants/category_kinds.dart';
import '../constants/category_profiles.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/category_profile.dart';

/// The profile [event]'s mark speaks for, its category resolved as rendering
/// resolves it (an unknown id is `other`), so a row and the sheet it opens
/// never name a kept mark differently.
EffectiveProfile effectiveFor(CalendarEvent event) =>
    CategoryProfiles.effectiveFor(
      CalendarCategories.resolve(event.categoryId).id,
    );

/// The word for a kept mark — "Done", "Paid", the owner's own word — and
/// "Present" for a category without a verb, which is every unprofiled one:
/// the word the detail sheet said before kinds existed.
String markVerbLabel(AppLocalizations l10n, EffectiveProfile profile) =>
    profile.customVerb ??
    switch (profile.verb) {
      MarkVerb.done => l10n.markVerbDone,
      MarkVerb.attended => l10n.markVerbAttended,
      MarkVerb.taken => l10n.markVerbTaken,
      MarkVerb.paid => l10n.markVerbPaid,
      MarkVerb.received => l10n.markVerbReceived,
      MarkVerb.met => l10n.markVerbMet,
      MarkVerb.renewed => l10n.markVerbRenewed,
      null => l10n.eventPresencePresent,
    };

/// The tooltip of the button that returns a missed occurrence to kept. A
/// kind's verb has its own whole phrase, because German and Romanian do not
/// build "Mark as …" around a bare participle the same way for every verb;
/// only the owner's word goes through the placeholder.
String markAsVerbLabel(AppLocalizations l10n, EffectiveProfile profile) {
  final custom = profile.customVerb;
  if (custom != null) return l10n.eventMarkAsVerb(custom);
  return switch (profile.verb) {
    MarkVerb.done => l10n.eventMarkDone,
    MarkVerb.attended => l10n.eventMarkAttended,
    MarkVerb.taken => l10n.eventMarkTaken,
    MarkVerb.paid => l10n.eventMarkPaid,
    MarkVerb.received => l10n.eventMarkReceived,
    MarkVerb.met => l10n.eventMarkMet,
    MarkVerb.renewed => l10n.eventMarkRenewed,
    null => l10n.eventMarkPresent,
  };
}
