import '../../qa/src/errors.dart';

export '../../qa/src/errors.dart';

/// Exit code for a pipeline step that ran and failed.
const int exitBuild = 4;

class BuildFailure extends QaException {
  BuildFailure(String message) : super(message, exitBuild);
}
