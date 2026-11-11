/// Where the cloud project's database keeps what syncs — what the Sync
/// page's "Where your data is stored" tells the person whose data it is
/// (cloud-multi-user-roadmap §9 R2).
///
/// A build cannot ask the server: the location belongs to the project's
/// database and is fixed when that database is created. So it is stated
/// here, and [current] changes in the same step that moves the database —
/// the last step of the R1 runbook, after the new location has been read
/// back — never before it: a notice that names a place the data is not in
/// is worse than none.
enum CloudDataRegion {
  /// The multi-region `nam5`.
  unitedStates,

  /// The multi-region `eur3`.
  europeanUnion;

  /// The live database's location.
  static const CloudDataRegion current = CloudDataRegion.unitedStates;
}
