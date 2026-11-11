import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/cloud_data_region.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/utils/data_notice.dart';

/// "Where your data is stored" (cloud-multi-user-roadmap §9 R2): the notice
/// has to be true in every language and for whichever place the cloud
/// database is in — the one statement in the app the code cannot check
/// against the world.
void main() {
  for (final (code, unitedStates, europeanUnion) in const [
    ('en', 'United States', 'European Union'),
    ('de', 'USA', 'Europäischen Union'),
    ('ro', 'Statele Unite', 'Uniunea Europeană'),
  ]) {
    final l10n = lookupAppLocalizations(Locale(code));
    List<String> at(CloudDataRegion region) =>
        dataNoticeParagraphs(l10n, region: region);

    group(code, () {
      test('six paragraphs, none empty, the same but for the one that names '
          'the database\'s place', () {
        final us = at(CloudDataRegion.unitedStates);
        final eu = at(CloudDataRegion.europeanUnion);

        expect(us, hasLength(6));
        expect(us.every((paragraph) => paragraph.trim().isNotEmpty), isTrue);
        expect(eu, hasLength(6));
        expect(
          [
            for (var i = 0; i < us.length; i++)
              if (us[i] != eu[i]) i,
          ],
          [1],
        );
      });

      test('the synced copy is where the database is, and nowhere else is '
          'named for it', () {
        final us = at(CloudDataRegion.unitedStates)[1];
        final eu = at(CloudDataRegion.europeanUnion)[1];

        expect(us, contains(unitedStates));
        expect(us, isNot(contains(europeanUnion)));
        expect(eu, contains(europeanUnion));
        expect(eu, isNot(contains(unitedStates)));
      });

      test('the account is the sign-in service\'s, in the United States '
          'wherever the database is', () {
        for (final region in CloudDataRegion.values) {
          expect(at(region)[3], l10n.dataNoticeAccount);
          expect(at(region)[3], contains(unitedStates));
        }
      });

      test('it says who can read the copy, and names the two rows that '
          'remove it by their own labels', () {
        final paragraphs = at(CloudDataRegion.current);

        expect(paragraphs[2], l10n.dataNoticeReadable);
        expect(paragraphs.last, contains(l10n.syncDeleteCloud));
        expect(paragraphs.last, contains(l10n.syncDeleteAccount));
      });

      test('unless a region is named, it is the build\'s own statement', () {
        expect(dataNoticeParagraphs(l10n), at(CloudDataRegion.current));
      });
    });
  }
}
