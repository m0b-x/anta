part of re_editor;

/// How many undo steps the editing cache keeps behind the current value.
/// Each step pins a whole `CodeLineEditingValue`, so an uncapped history
/// grows without bound on a long editing session.
const int _kMaxUndoHistory = 200;

/// Typing edits further apart than this start a new undo step (CodeMirror's
/// default): a pause is where a person expects Undo to stop, so a whole line
/// typed on a phone is no longer one step.
const Duration _kTypingUndoGroupGap = Duration(milliseconds: 500);

/// The clock the undo grouping reads; tests swap it through
/// `debugUndoGroupingClock` to step past [_kTypingUndoGroupGap] without
/// sleeping.
Duration Function()? _debugUndoGroupingClock;

final Stopwatch _undoGroupingStopwatch = Stopwatch()..start();

Duration _undoGroupingNow() =>
    _debugUndoGroupingClock?.call() ?? _undoGroupingStopwatch.elapsed;

final kIsMacOS = defaultTargetPlatform == TargetPlatform.macOS;
final kIsAndroid = defaultTargetPlatform == TargetPlatform.android;
final kIsIOS = defaultTargetPlatform == TargetPlatform.iOS;
