/// When the engine reaches the space on its own (record §13 of
/// `docs/cloud-sync-phase-02-own-space.md`). Stored per database under
/// `SettingsKeys.syncCadence` by its [name]; an unknown or missing value
/// reads as [automatic].
enum SyncCadence {
  /// The default: a run at launch and on every return to the foreground,
  /// the space's signal followed while the app is open, a push 30 s after
  /// the last edit and at once when the app leaves, retries on a back-off.
  automatic,

  /// Nothing reaches the space unasked: only "Sync now" runs — and the first
  /// merge a bind owes, which is the bind's own work, not a cadence's. No
  /// signal is followed, no push timer is armed, a leave drains nothing, a
  /// failure waits for the next press instead of a retry.
  manual;

  /// The cadence a stored [name] stands for; [automatic] for anything else,
  /// a database written before the setting existed included.
  static SyncCadence parse(String? stored) => switch (stored) {
    'manual' => manual,
    _ => automatic,
  };
}
