part of re_editor;

/// How many undo steps the editing cache keeps behind the current value.
/// Each step pins a whole `CodeLineEditingValue`, so an uncapped history
/// grows without bound on a long editing session.
const int _kMaxUndoHistory = 200;

final kIsMacOS = defaultTargetPlatform == TargetPlatform.macOS;
final kIsAndroid = defaultTargetPlatform == TargetPlatform.android;
final kIsIOS = defaultTargetPlatform == TargetPlatform.iOS;
