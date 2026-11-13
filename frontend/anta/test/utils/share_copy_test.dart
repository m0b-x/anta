import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/utils/share_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalogues = <String, AppLocalizations>{
    'en': AppLocalizationsEn(),
    'de': AppLocalizationsDe(),
    'ro': AppLocalizationsRo(),
  };

  group('partnerName', () {
    test('a name is the partner\'s own, trimmed', () {
      final l10n = AppLocalizationsEn();
      expect(ShareCopy.partnerName(l10n, ' Ana '), 'Ana');
    });

    test('missing or blank, it is the localized stand-in', () {
      for (final l10n in catalogues.values) {
        expect(ShareCopy.partnerName(l10n, null), l10n.sharePartnerFallback);
        expect(ShareCopy.partnerName(l10n, '  '), l10n.sharePartnerFallback);
      }
    });
  });

  group('sentence', () {
    test('the stand-in starts a sentence as a name would', () {
      for (final MapEntry(key: locale, value: l10n) in catalogues.entries) {
        final name = ShareCopy.partnerName(l10n, null);
        final said = ShareCopy.sentence(l10n.sharePartnerSharesCaption(name));
        expect(
          said[0],
          said[0].toUpperCase(),
          reason: '$locale: "$said" starts a sentence',
        );
      }
    });

    test('a name keeps its letters after the first', () {
      expect(ShareCopy.sentence('ana McKay shares'), 'Ana McKay shares');
    });

    test('an address is never capitalised: an account with no profile name '
        'publishes its e-mail address', () {
      expect(
        ShareCopy.sentence('qa1@example.com shares Shifts with you'),
        'qa1@example.com shares Shifts with you',
      );
      expect(ShareCopy.sentence('qa1@example.com'), 'qa1@example.com');
    });

    test('an address later in the sentence changes nothing', () {
      expect(
        ShareCopy.sentence('your partner (qa1@example.com) shares'),
        'Your partner (qa1@example.com) shares',
      );
    });

    test('an empty string stays empty', () {
      expect(ShareCopy.sentence(''), '');
    });
  });

  group('folderAct', () {
    const trips = ShareFolderRef(id: 'trips', name: 'Trips');
    const lisbon = ShareFolderRef(id: 'lisbon', name: 'Lisbon');
    const porto = ShareFolderRef(id: 'porto', name: 'Porto');
    final en = AppLocalizationsEn();

    String? stopped(List<ShareFolderRef> inner, [AppLocalizations? l10n]) =>
        ShareCopy.folderAct(
          l10n ?? en,
          ShareChange(
            unsharedFolders: const [trips],
            clearedInnerFolders: inner,
          ),
          partnerName: 'Maria',
        );

    test('an un-share alone says the folder', () {
      expect(stopped(const []), 'No longer shared: Trips');
    });

    test('an un-share that also cleared inner folders counts them', () {
      expect(
        stopped(const [lisbon]),
        'No longer shared: Trips and 1 folder inside it',
      );
      expect(
        stopped(const [lisbon, porto]),
        'No longer shared: Trips and 2 folders inside it',
      );
    });

    for (final MapEntry(key: code, value: l10n) in catalogues.entries) {
      test('$code: every plural form fills its placeholders', () {
        for (var count = 1; count <= 25; count++) {
          final text = stopped([for (var i = 0; i < count; i++) lisbon], l10n)!;
          expect(text, contains('Trips'), reason: '$code $count');
          expect(text, isNot(contains('{')), reason: '$code $count');
        }
      });
    }
  });
}
