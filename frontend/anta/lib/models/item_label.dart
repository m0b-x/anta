/// The optional colour label a note or folder can carry, drawn as a small dot
/// at the trailing edge of its browser row.
///
/// One label per item and [none] is the default, which draws nothing and
/// reserves no space — an unlabelled row renders exactly as it did before
/// labels existed.
///
/// The declaration order **is** the storage encoding: [storageValue] is the
/// enum index, so `label INTEGER NOT NULL DEFAULT 0` on `notes` and `folders`
/// stores 0 for [none] and 1..7 for the palette. Never reorder these, and
/// never insert a value in the middle — every existing row would change
/// colour. Append only.
enum ItemLabel {
  none,
  red,
  orange,
  yellow,
  green,
  teal,
  blue,
  pink;

  /// What the `label` column holds for this label.
  int get storageValue => index;

  /// What JSON carries, in backups and archives. The *name* rather than the
  /// index, so a hand-read backup says `"label": "teal"` and a future
  /// reordering of the enum could not silently repaint an archive.
  String get storageName => name;

  /// Every label a user can actually pick, in palette order — [none] is the
  /// absence of a label rather than one of them, and the picker draws it
  /// separately.
  static Iterable<ItemLabel> get assignable => values.skip(1);

  /// The label stored as [value], or [none] for null and for anything outside
  /// the enum — a column written by a newer build, or a hand-edited database,
  /// reads as unlabelled rather than crashing the row.
  static ItemLabel fromStorage(int? value) {
    if (value == null) return none;
    if (value < 0 || value >= values.length) return none;
    return values[value];
  }

  /// The label named [name], or [none] for null and for any name this build
  /// does not know — the tolerance an additive backup key needs.
  static ItemLabel fromName(String? name) {
    if (name == null) return none;
    for (final label in values) {
      if (label.name == name) return label;
    }
    return none;
  }
}
