import '../constants/cloud_data_region.dart';
import '../l10n/app_localizations.dart';

/// "Where your data is stored" (cloud-multi-user-roadmap §9 R2), paragraph by
/// paragraph, in the order a person asks: where it is, where a synced copy
/// goes, who can read that copy, what the account keeps, what a partner
/// sees, what of yours a partner keeps, how to take it back. [region] is the
/// cloud database's location — the build's own statement of it,
/// [CloudDataRegion.current], unless a test names another.
///
/// The sign-in service's place is not [region]: it keeps account data in the
/// United States wherever the database is, so its paragraph says so in both.
List<String> dataNoticeParagraphs(
  AppLocalizations l10n, {
  CloudDataRegion region = CloudDataRegion.current,
}) => [
  l10n.dataNoticeLocal,
  switch (region) {
    CloudDataRegion.unitedStates => l10n.dataNoticeCloudUs,
    CloudDataRegion.europeanUnion => l10n.dataNoticeCloudEu,
  },
  l10n.dataNoticeReadable,
  l10n.dataNoticeAccount,
  l10n.dataNoticePartner,
  l10n.dataNoticeShared,
  l10n.dataNoticeRemove(l10n.syncDeleteCloud, l10n.syncDeleteAccount),
];
