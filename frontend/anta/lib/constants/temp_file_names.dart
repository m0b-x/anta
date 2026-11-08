/// What ANTA names the files and folders it leaves in the system temp
/// directory. On Windows that directory is every app's, so the launch sweep
/// (`ImportExportService.sweepStaleExports`) deletes nothing without
/// [prefix]; the export folder and a share's snapshot folder carry it so the
/// sweep knows them as ANTA's own. One home for the three names keeps the
/// sweep, the exports and the snapshot share from drifting apart.
abstract final class TempFileNames {
  static const String prefix = 'anta_';

  /// The folder note files and archives are written into: their names are
  /// the user's titles, which carry no prefix the sweep could recognise.
  static const String exportDirectory = '${prefix}exports';

  /// A share's snapshot folder (`DatabaseManager.snapshotForShare`), one per
  /// share, the timestamp appended.
  static const String shareSnapshotPrefix = '${prefix}db_share_';
}
