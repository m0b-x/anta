import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/category_profiles.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/mark_verb_labels.dart';

/// The kept mark's word and its tooltip (decision B of the analytics
/// record): the kind's verb, the owner's own word, and today's words for a
/// category with no verb.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  EffectiveProfile of(CategoryKind kind, {String? markVerb}) => CategoryProfile(
    id: 'p',
    categoryId: 'c',
    kind: kind,
    markVerb: markVerb,
  ).effective;

  group('markVerbLabel', () {
    test('each kind verb has its word', () {
      expect(
        {
          for (final kind in [
            CategoryKind.task,
            CategoryKind.workout,
            CategoryKind.medication,
            CategoryKind.bill,
            CategoryKind.income,
            CategoryKind.social,
            CategoryKind.expiry,
          ])
            kind: markVerbLabel(en, of(kind)),
        },
        {
          CategoryKind.task: 'Done',
          CategoryKind.workout: 'Attended',
          CategoryKind.medication: 'Taken',
          CategoryKind.bill: 'Paid',
          CategoryKind.income: 'Received',
          CategoryKind.social: 'Met',
          CategoryKind.expiry: 'Renewed',
        },
      );
    });

    test('the owner\'s own word outranks the kind\'s', () {
      expect(
        markVerbLabel(en, of(CategoryKind.task, markVerb: 'Logged')),
        'Logged',
      );
    });

    test('no profile, and a kind without a verb, read Present', () {
      expect(markVerbLabel(en, EffectiveProfile.unprofiled), 'Present');
      expect(markVerbLabel(en, of(CategoryKind.sleep)), 'Present');
    });

    test('German reads the kind\'s word', () {
      expect(markVerbLabel(de, of(CategoryKind.task)), 'Erledigt');
    });
  });

  group('markAsVerbLabel', () {
    test('a kind verb has its whole phrase', () {
      expect(markAsVerbLabel(en, of(CategoryKind.task)), 'Mark as done');
      expect(markAsVerbLabel(en, of(CategoryKind.bill)), 'Mark as paid');
      expect(
        markAsVerbLabel(en, of(CategoryKind.appointment)),
        'Mark as attended',
      );
    });

    test('the owner\'s own word goes through the placeholder', () {
      expect(
        markAsVerbLabel(en, of(CategoryKind.task, markVerb: 'logged')),
        'Mark as logged',
      );
    });

    test('no profile reads today\'s Mark as present', () {
      expect(
        markAsVerbLabel(en, EffectiveProfile.unprofiled),
        en.eventMarkPresent,
      );
    });

    test('German keeps the phrase\'s own order', () {
      expect(
        markAsVerbLabel(de, of(CategoryKind.task)),
        'Als erledigt markieren',
      );
      expect(
        markAsVerbLabel(de, of(CategoryKind.task, markVerb: 'erfasst')),
        'Als erfasst markieren',
      );
    });
  });

  group('effectiveFor', () {
    tearDown(() {
      CategoryProfiles.resetCache();
      CalendarCategories.updateCache(const []);
    });

    test('resolves the event\'s category as rendering does', () {
      CalendarCategories.updateCache(const [
        CalendarCategory(
          id: 'other',
          name: 'Other',
          colorValue: 0xFF757575,
          iconKey: 'event',
          sortOrder: 0,
          isBuiltIn: true,
        ),
      ]);
      CategoryProfiles.updateCache({
        'other': const CategoryProfile(
          id: 'p',
          categoryId: 'other',
          kind: CategoryKind.bill,
        ),
      });
      final orphan = CalendarEvent(
        id: 'e',
        title: 'Rent',
        categoryId: 'gone',
        startDate: DateTime.utc(2026, 11, 4),
        rule: const OneTimeRecurrence(),
      );

      expect(effectiveFor(orphan).verb, MarkVerb.paid);
    });
  });
}
