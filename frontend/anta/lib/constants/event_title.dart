/// The longest title an event may be given, in characters.
///
/// One number for every form that names an event — the event editor and the
/// quick alarm. Save on the quick alarm makes an event the editor opens next,
/// so a title one form took and the other refused would be cut the first time
/// it was edited.
const int kEventTitleMaxLength = 120;

/// The length from which a title field shows its counter: quiet for an
/// ordinary title, counting once the limit is in sight.
const int kEventTitleCounterFrom = 100;
