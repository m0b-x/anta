import 'nav_destination.dart';

/// How much of the remembered navigation stack a cold launch replays.
///
/// The mode filters at replay, never at recording: the stack is written
/// regardless, so switching back to [everything] restores the place the user
/// actually left rather than the place they were in when they last changed
/// this setting.
enum RestoreLocationMode {
  /// Always launch at the root folder page.
  off,

  /// Replay only the folder/note substrate — the behaviour that shipped
  /// before the calendar and settings pages became restorable.
  notes,

  /// Replay the whole recorded chain.
  everything;

  /// Forward-compatible parsing: an unknown or absent value is [everything],
  /// which is also the default for an install that never touched the setting.
  static RestoreLocationMode fromName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return everything;
  }

  /// The portion of [stack] this mode restores.
  ///
  /// [notes] takes the longest **prefix** of folder/note entries rather than
  /// filtering them out of the middle: dropping an entry from the middle would
  /// leave a chain whose Back path never existed.
  List<NavDestination> apply(List<NavDestination> stack) {
    switch (this) {
      case RestoreLocationMode.off:
        return const [];
      case RestoreLocationMode.everything:
        return stack;
      case RestoreLocationMode.notes:
        final prefix = <NavDestination>[];
        for (final destination in stack) {
          if (!destination.kind.isNoteSubstrate) break;
          prefix.add(destination);
        }
        return prefix;
    }
  }
}
